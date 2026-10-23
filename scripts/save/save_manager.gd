class_name SaveManager
extends Node
## Saving and loading. Setup: add a Node named SaveManager to your main scene (next to the
## World node) and attach this script. It finds the Player and the World on its own and
## creates the Save / Load menu itself.
##
##   F5  quicksave        F9  quickload        F10  Save / Load menu (slots, new game + seed)
##
## What a save holds (user://saves/<slot>/save.json, readable text):
##   world seed, player (position, look direction, skills, inventory, equipment, vitals),
##   every node in group "persistent" (dropped items, enemies, corpses), the dungeon the player
##   is inside (if any), the time of day, active food / potion effects, and WorldState
##   (the list of things changed in the generated world, keyed by stable ids).
## The world itself is NOT saved: it is rebuilt from the seed.
##
## How a load works: the save is parked in SaveSession, the scene reloads (so the world is built
## fresh from the saved seed), then this node applies the rest behind a black screen.
##
## Adding your own saved things later:
##   - a loose object: join group "persistent", add get_persist_data() (with a "type"), add a
##     static restore(data, parent), and add the type to _restore_entity() below
##   - a change to the generated world: WorldState.set_record(stable_id, {...})
##   - a system on the player: give it to_dict() / from_dict() and list it in _gather_player()
##     and _restore_player()

signal saved(slot: String)
signal loaded(slot: String)
signal save_failed(slot: String, reason: String)
signal load_failed(slot: String, reason: String)

## Bump when the save layout changes, and teach _migrate() how to upgrade older saves
const SAVE_VERSION := 2
const SAVE_DIR := "user://saves"
const QUICKSAVE := "quicksave"
const AUTOSAVE := "autosave"

@export var game_version := "0.1"
## Number of numbered slots in the menu
@export_range(0, 12) var manual_slots := 8
## Minutes between automatic saves (0 = off)
@export_range(0.0, 60.0, 0.5) var autosave_minutes := 5.0
## Create the Save / Load menu (F10)
@export var show_menu := true
## Empty = the game scene itself (loading reloads it). The main menu sets this to the game
## scene, so loading or starting a game switches to it instead.
@export_file("*.tscn") var game_scene := ""

const MAIN_MENU_SCENE := "res://scenes/game/main_menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"

var menu: SaveMenu

var _autosave_clock := 0.0
var _loading := false
var _last_error := ""


func _ready() -> void:
	add_to_group("save_manager")
	if game_scene == "":
		add_to_group("settings_listener")
		apply_settings()
	_register_action("quicksave", KEY_F5)
	_register_action("quickload", KEY_F9)
	if show_menu:
		menu = SaveMenu.new()
		menu.name = "SaveMenu"
		add_child(menu)
	if SaveSession.has_pending():
		_loading = true
		_apply_pending.call_deferred()
	else:
		# A fresh run (new game, or the scene restarted after dying): nothing is remembered
		WorldState.clear()


func _process(delta: float) -> void:
	if _loading or game_scene != "":
		return
	SaveSession.playtime += delta
	if autosave_minutes > 0.0:
		_autosave_clock += delta
		if _autosave_clock >= autosave_minutes * 60.0:
			_autosave_clock = 0.0
			if can_save() == "":
				if save_game(AUTOSAVE) and menu != null:
					menu.show_toast("Autosaved")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or _loading:
		return
	if event.is_action_pressed("quicksave"):
		get_viewport().set_input_as_handled()
		quick_save()
	elif event.is_action_pressed("quickload"):
		get_viewport().set_input_as_handled()  # first: a load removes this node from the tree
		quick_load()


# ---------------------------------------------------------------- public API

## GameSettings changed (the autosave interval)
func apply_settings() -> void:
	autosave_minutes = float(GameSettings.get_value("autosave_minutes"))


## Leaves the game for the main menu (the pause menu and the death screen use this)
static func go_to_main_menu(tree: SceneTree) -> void:
	SaveSession.pending = {}
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.change_scene_to_file(MAIN_MENU_SCENE)


## The slot saved most recently ("" = no saves at all). The main menu's Continue uses it.
func latest_slot() -> String:
	var best := ""
	var best_time := -1.0
	for s in list_slots():
		if not s["exists"]:
			continue
		var t := float((s["meta"] as Dictionary).get("time_unix", 0.0))
		if t > best_time:
			best_time = t
			best = s["id"]
	return best

func is_loading() -> bool:
	return _loading


## "" if saving is possible right now, else the reason it is not
func can_save() -> String:
	if _loading or SaveSession.has_pending():
		return "A load is in progress."
	var player := _get_player()
	if player == null:
		return "There is no player to save."
	var stats := player.get_node_or_null("Stats") as Stats
	if stats != null and stats.is_dead:
		return "You cannot save while dead."
	return ""


func get_slot_ids() -> Array[String]:
	var ids: Array[String] = [QUICKSAVE, AUTOSAVE]
	for i in manual_slots:
		ids.append("slot_%d" % (i + 1))
	return ids


func get_slot_label(slot: String) -> String:
	match slot:
		QUICKSAVE:
			return "Quicksave"
		AUTOSAVE:
			return "Autosave"
	if slot.begins_with("slot_"):
		return "Slot " + slot.trim_prefix("slot_")
	return slot


## One entry per slot: {"id", "label", "exists", "meta"} (meta is empty for an empty slot)
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in get_slot_ids():
		var meta: Variant = SaveUtil.read_json(_slot_dir(id) + "/meta.json")
		var has_file := FileAccess.file_exists(_slot_dir(id) + "/save.json") or FileAccess.file_exists(_slot_dir(id) + "/save.json.bak")
		out.append({
			"id": id,
			"label": get_slot_label(id),
			"exists": has_file,
			"meta": meta if meta is Dictionary else {},
		})
	return out


func slot_exists(slot: String) -> bool:
	return FileAccess.file_exists(_slot_dir(slot) + "/save.json") or FileAccess.file_exists(_slot_dir(slot) + "/save.json.bak")


func get_last_error() -> String:
	return _last_error


func save_game(slot: String) -> bool:
	if GameRules.ironman() and SaveSession.current_slot.begins_with("ironman_"):
		slot = SaveSession.current_slot  # ironman: always the one save of this character
	var problem := can_save()
	if problem != "":
		return _save_fail(slot, problem)
	if not _valid_slot(slot):
		return _save_fail(slot, "Bad slot name.")
	var data := build_save_data()
	var dir := _slot_dir(slot)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return _save_fail(slot, "Could not create the save folder (error %d)." % err)
	err = SaveUtil.write_json_atomic(dir + "/save.json", data)
	if err != OK:
		return _save_fail(slot, "Could not write the save file (error %d)." % err)
	SaveUtil.write_json_atomic(dir + "/meta.json", data["meta"], false)
	SaveSession.current_slot = slot
	saved.emit(slot)
	return true


## Reads the slot and restarts the scene to apply it. Returns false (and says why through
## get_last_error() / load_failed) if the save is missing or damaged.
func load_game(slot: String) -> bool:
	if _loading:
		return false
	if not _valid_slot(slot):
		return _load_fail(slot, "Bad slot name.")
	var data := _read_slot(slot)
	if data.is_empty():
		return _load_fail(slot, _last_error)
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		return _load_fail(slot, "This save was made by a newer version of the game.")
	data = _migrate(data, version)
	_loading = true
	SaveSession.begin_load(data, slot)
	get_tree().paused = false
	var err := _start_scene()
	if err != OK:
		_loading = false
		return _load_fail(slot, "Could not restart the scene (error %d). Run the game from a saved scene." % err)
	return true


func quick_save() -> void:
	var problem := can_save()
	if problem != "":
		if menu != null:
			menu.show_toast(problem, true)
		return
	if save_game(QUICKSAVE) and menu != null:
		menu.show_toast("Quicksaved")


func quick_load() -> void:
	if GameRules.ironman():
		if menu != null:
			menu.show_toast("Ironman: there is no going back", true)
		return
	if not slot_exists(QUICKSAVE):
		if menu != null:
			menu.show_toast("No quicksave yet", true)
		return
	load_game(QUICKSAVE)


func delete_slot(slot: String) -> void:
	if not _valid_slot(slot):
		return
	for f in ["save.json", "save.json.bak", "save.json.tmp", "meta.json"]:
		var path: String = _slot_dir(slot) + "/" + f
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_slot_dir(slot))


## Starts a fresh game. Blank text = the default world from WorldSettings.
func new_game(seed_text: String, rules: Dictionary = {}, character: Dictionary = {}) -> void:
	if _loading:
		return
	_loading = true
	var blank := seed_text.strip_edges() == ""
	SaveSession.begin_new_game(0 if blank else SaveSession.seed_from_text(seed_text), blank)
	# The World Creation and Character Creation screens
	GameRules.from_dict(rules)
	GameSettings.get_value("difficulty")
	GameSettings._values["difficulty"] = int(GameRules.get_rule("difficulty"))
	CharacterSetup.pending = character.duplicate(true)
	if GameRules.ironman() and not character.is_empty():
		SaveSession.current_slot = "ironman_" + String(character.get("name", "hero")).to_lower().validate_filename().replace(" ", "_").replace("-", "_")
	get_tree().paused = false
	_start_scene()


# Reloads the game scene, or switches to it from the main menu
func _start_scene() -> Error:
	if game_scene != "":
		return get_tree().change_scene_to_file(game_scene)
	return get_tree().reload_current_scene()


## Everything that goes into a save file
func build_save_data() -> Dictionary:
	var player := _get_player()
	var world := _get_world()
	var data := {"version": SAVE_VERSION, "game_version": game_version}
	data["meta"] = _make_meta(player, world)
	if world != null:
		data["world"] = world.to_dict()
	data["player"] = _gather_player(player)
	data["entities"] = _gather_entities()
	var dungeons := _get_dungeons()
	if dungeons != null:
		data["dungeon"] = dungeons.to_dict()
	data["world_state"] = WorldState.to_dict()
	var clock := _get_clock()
	if clock != null:
		data["clock"] = clock.to_dict()
	var weather := Weather.get_instance(get_tree())
	if weather != null:
		data["weather"] = weather.to_dict()
	data["rules"] = GameRules.to_dict()
	data["playtime"] = SaveSession.playtime
	return data


# ---------------------------------------------------------------- gathering

func _make_meta(player: Node3D, world: WorldManager) -> Dictionary:
	var meta := {
		"time_unix": Time.get_unix_time_from_system(),
		"time_text": Time.get_datetime_string_from_system(false, true),
		"playtime": SaveSession.playtime,
		"version": SAVE_VERSION,
		"game_version": game_version,
		"level": 1,
		"location": "",
		"seed": 0,
	}
	if world != null:
		meta["seed"] = world.world_seed
		var pos := player.global_position
		var biome := world.get_biome_at(pos.x, pos.z)
		meta["location"] = "%s (%d, %d)" % [biome.display_name if biome != null else "Outside", roundi(pos.x), roundi(pos.z)]
		var town := world.get_town_at(pos)
		if town != null and town.town != null:
			meta["location"] = "%s, %s" % [town.town.display_name, biome.display_name if biome != null else "Outside"]
		var dungeons := _get_dungeons()
		if dungeons != null and dungeons.is_inside():
			meta["location"] = "Inside: %s" % dungeons.get_current_name()
			var b := world.get_building(dungeons.current_entrance_id)
			if b != null:
				meta["location"] += ", " + b.town_name
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		meta["level"] = skills.get_player_level()
	return meta


func _gather_player(player: Node3D) -> Dictionary:
	var head := player.get_node_or_null("Head") as Node3D
	var p := {
		"pos": SaveUtil.vec3_to_array(player.global_position),
		"yaw": player.rotation.y,
		"pitch": head.rotation.x if head != null else 0.0,
	}
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		p["skills"] = skills.to_dict()
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory != null:
		p["inventory"] = inventory.to_dict()
	var equipment := player.get_node_or_null("Equipment") as Equipment
	if equipment != null:
		p["equipment"] = equipment.to_dict()
	var stats := player.get_node_or_null("Stats") as Stats
	if stats != null:
		p["stats"] = stats.to_dict()
	var effects := player.get_node_or_null("StatusEffects") as StatusEffects
	if effects != null:
		p["effects"] = effects.to_dict()
	var book := player.get_node_or_null("Spellbook") as Spellbook
	if book != null:
		p["spellbook"] = book.to_dict()
	for n in ["Afflictions", "Survival", "Powers", "Followers"]:
		var node := player.get_node_or_null(n)
		if node != null:
			p[n.to_lower()] = node.to_dict()
	if player.has_meta("character"):
		p["character"] = player.get_meta("character")
	var magic := player.get_node_or_null("ActiveMagic") as ActiveMagic
	if magic != null:
		p["magic"] = magic.to_dict()
	return p


func _gather_entities() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("persistent"):
		if n.is_queued_for_deletion() or not n.has_method("get_persist_data"):
			continue
		var d: Dictionary = n.get_persist_data()
		if not d.is_empty():
			out.append(d)
	return out


# ---------------------------------------------------------------- applying a load

func _apply_pending() -> void:
	var data := SaveSession.take_pending()
	if data.is_empty():
		_loading = false
		return
	if menu != null:
		menu.set_loading(true)
	# Let the scene start up first: the Player waits a frame and then hands out its test items
	for i in 3:
		await get_tree().process_frame

	var player := _get_player()
	var world := _get_world()
	if player == null:
		push_error("SaveManager: no player found, cannot apply the save.")
		_finish_loading(false)
		return

	# Whatever the fresh scene spawned (test sword, test enemy) is replaced by what was saved
	for n in get_tree().get_nodes_in_group("persistent"):
		if not n.is_queued_for_deletion():
			n.queue_free()

	var p: Dictionary = data.get("player", {})
	var pos := SaveUtil.array_to_vec3(p.get("pos"), player.global_position)
	if world != null:
		world.ensure_area_loaded(pos)
	# Saved inside a dungeon: build it first so the player has a floor to stand on
	var dungeons := _get_dungeons()
	if dungeons != null and data.has("dungeon"):
		dungeons.restore(data["dungeon"])
	_restore_player(player, p)
	var clock := _get_clock()
	if clock != null and data.has("clock"):
		clock.from_dict(data["clock"])
	var weather := Weather.get_instance(get_tree())
	if weather != null and data.has("weather"):
		weather.from_dict(data["weather"])

	var scene := get_tree().current_scene
	for d in data.get("entities", []):
		var at := SaveUtil.array_to_vec3(d.get("pos"))
		if world != null:
			world.ensure_area_loaded(at)  # ground must exist before something is placed on it
		_restore_entity(d, scene)

	for i in 2:
		await get_tree().physics_frame
	_finish_loading(true)


func _finish_loading(success: bool) -> void:
	_loading = false
	if menu != null:
		menu.set_loading(false)
		menu.show_toast("Game loaded" if success else "Load failed", not success)
	if success:
		loaded.emit(SaveSession.current_slot)


func _restore_player(player: Node3D, p: Dictionary) -> void:
	# Order matters: skills and gear set the maximums, then the current vitals are filled in
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null and p.has("skills"):
		skills.from_dict(p["skills"])
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory != null and p.has("inventory"):
		inventory.from_dict(p["inventory"])
	var equipment := player.get_node_or_null("Equipment") as Equipment
	if equipment != null and p.has("equipment"):
		equipment.from_dict(p["equipment"])
	var stats := player.get_node_or_null("Stats") as Stats
	if stats != null and p.has("stats"):
		stats.from_dict(p["stats"])
	var effects := player.get_node_or_null("StatusEffects") as StatusEffects
	if effects != null:
		effects.from_dict(p.get("effects", {}))
	var book := player.get_node_or_null("Spellbook") as Spellbook
	if book != null and p.has("spellbook"):
		book.from_dict(p["spellbook"])
	var magic := player.get_node_or_null("ActiveMagic") as ActiveMagic
	if magic != null:
		magic.from_dict(p.get("magic", {}))
	if p.has("character"):
		CharacterSetup.apply(player, p["character"], false)
	for n in ["Afflictions", "Survival", "Powers", "Followers"]:
		var node := player.get_node_or_null(n)
		if node != null and p.has(n.to_lower()):
			node.from_dict(p[n.to_lower()])

	player.global_position = SaveUtil.array_to_vec3(p.get("pos"), player.global_position)
	player.rotation.y = float(p.get("yaw", player.rotation.y))
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = float(p.get("pitch", 0.0))
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


func _restore_entity(d: Dictionary, parent: Node) -> void:
	match String(d.get("type", "")):
		"world_item":
			WorldItem.restore(d, parent)
		"enemy":
			Enemy.restore(d, parent)
		_:
			push_warning("SaveManager: unknown saved entity type '%s' was skipped." % d.get("type", ""))


# ---------------------------------------------------------------- files

func _slot_dir(slot: String) -> String:
	return "%s/%s" % [SAVE_DIR, slot]


func _valid_slot(slot: String) -> bool:
	return slot != "" and slot.is_valid_identifier()


# save.json, or its backup if the main file is damaged
func _read_slot(slot: String) -> Dictionary:
	var dir := _slot_dir(slot)
	for file in ["save.json", "save.json.bak"]:
		var data: Variant = SaveUtil.read_json(dir + "/" + file)
		if data is Dictionary and (data as Dictionary).has("version"):
			if file != "save.json":
				push_warning("SaveManager: %s was damaged, loaded its backup instead." % slot)
			return data
	_last_error = "This save is missing or damaged."
	return {}


## Upgrades an old save to the current layout, one step per version:
##   2: files moved into scripts/<area>/, data/ and scenes/ (SaveUtil.MOVED_PATHS)
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		data = SaveUtil.migrate_moved_paths(data)
	return data


func _save_fail(slot: String, reason: String) -> bool:
	_last_error = reason
	save_failed.emit(slot, reason)
	return false


func _load_fail(slot: String, reason: String) -> bool:
	_last_error = reason
	load_failed.emit(slot, reason)
	return false


# ---------------------------------------------------------------- finding things

func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _get_dungeons() -> DungeonManager:
	return get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager


func _get_clock() -> WorldClock:
	return get_tree().get_first_node_in_group("world_clock") as WorldClock


func _get_world() -> WorldManager:
	return get_tree().get_first_node_in_group("world_manager") as WorldManager


func _register_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
