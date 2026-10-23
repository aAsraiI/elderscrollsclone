class_name SaveUtil
extends RefCounted
## Small helpers shared by everything that saves: JSON-friendly conversions and safe file IO.
## Save data may only contain things JSON can hold: numbers, strings, bools, arrays and
## dictionaries. Vector3 becomes [x, y, z]; items are stored by their resource path.

static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## "res://data/weapons/iron_sword.tres". Keys made at runtime save as "key://..." (KeyRing).
## Empty for other items made at runtime (they can't be saved).
static func item_to_path(item: ItemData) -> String:
	if item == null:
		return ""
	if item.has_meta("save_path"):
		return String(item.get_meta("save_path"))
	return item.resource_path


static func path_to_item(path: String) -> ItemData:
	if KeyRing.is_key_path(path):
		return KeyRing.from_path(path)
	if QuestItems.is_path(path):
		return QuestItems.from_path(path)
	if LoreBooks.is_path(path):
		return LoreBooks.from_path(path)
	if CraftedItems.is_path(path):
		return CraftedItems.from_path(path)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as ItemData


## Writes JSON so that a crash or a full disk can never leave a half-written save behind:
## write to .tmp, check it reads back, keep the old file as .bak, then rename into place.
## compress: compact JSON, gzip-compressed (a save shrinks to about a tenth); read_json reads both.
static func write_json_atomic(path: String, data: Variant, keep_backup: bool = true, compress: bool = false) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP) if compress else FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data) if compress else JSON.stringify(data, "\t"))
	file.close()
	if read_json(tmp) == null:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if keep_backup:
			DirAccess.rename_absolute(path, path + ".bak")
		else:
			DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Parsed JSON, or null if the file is missing or damaged. Reads plain and compressed files.
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := ""
	var probe := FileAccess.open(path, FileAccess.READ)
	var head := probe.get_buffer(4) if probe != null else PackedByteArray()
	if probe != null:
		probe.close()
	if head.get_string_from_ascii() == "GCPF":  # Godot's compressed file header
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
		if f == null:
			return null
		text = f.get_as_text()
		f.close()
	else:
		text = FileAccess.get_file_as_string(path)
	if text == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## "1h 05m" / "12m" / "40s"
static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm" % (s / 60)
	return "%ds" % s


## Where files lived before the project was reorganized (save version 1). Old saves store item and scene
## paths, so loading one rewrites them with this list: exact files first, then whole folders.
const MOVED_PATHS := [
	["res://scripts/currency.gd", "res://scripts/core/currency.gd"],
	["res://scripts/difficulty.gd", "res://scripts/core/difficulty.gd"],
	["res://scripts/Game/game_rules.gd", "res://scripts/core/game_rules.gd"],
	["res://scripts/ItemData.gd", "res://scripts/items/item_data.gd"],
	["res://scripts/Inventory.gd", "res://scripts/items/inventory.gd"],
	["res://scripts/Equipment.gd", "res://scripts/items/equipment.gd"],
	["res://scripts/item_catalog.gd", "res://scripts/items/item_catalog.gd"],
	["res://scripts/item_models.gd", "res://scripts/items/item_models.gd"],
	["res://scripts/WorldItem.gd", "res://scripts/items/world_item.gd"],
	["res://scripts/container_component.gd", "res://scripts/items/container_component.gd"],
	["res://scripts/key_ring.gd", "res://scripts/items/key_ring.gd"],
	["res://scripts/quest_items.gd", "res://scripts/items/quest_items.gd"],
	["res://scripts/loot_entry.gd", "res://scripts/items/loot_entry.gd"],
	["res://scripts/barter.gd", "res://scripts/trade/barter.gd"],
	["res://scripts/merchant_data.gd", "res://scripts/trade/merchant_data.gd"],
	["res://scripts/player.gd", "res://scripts/player/player.gd"],
	["res://scripts/player_combat.gd", "res://scripts/player/player_combat.gd"],
	["res://scripts/interactor.gd", "res://scripts/player/interactor.gd"],
	["res://scripts/grabber.gd", "res://scripts/player/grabber.gd"],
	["res://scripts/stealth.gd", "res://scripts/player/stealth.gd"],
	["res://scripts/view_model.gd", "res://scripts/player/view_model.gd"],
	["res://scripts/status_effects.gd", "res://scripts/player/status_effects.gd"],
	["res://scripts/Game/third_person.gd", "res://scripts/player/third_person.gd"],
	["res://scripts/Game/night_vision.gd", "res://scripts/player/night_vision.gd"],
	["res://scripts/Game/swimming.gd", "res://scripts/player/swimming.gd"],
	["res://scripts/Stats.gd", "res://scripts/character/stats.gd"],
	["res://scripts/Skills.gd", "res://scripts/character/skills.gd"],
	["res://scripts/SkillData.gd", "res://scripts/character/skill_data.gd"],
	["res://scripts/SkillDatabase.gd", "res://scripts/character/skill_database.gd"],
	["res://scripts/level_curve.gd", "res://scripts/character/level_curve.gd"],
	["res://scripts/Game/races.gd", "res://scripts/character/races.gd"],
	["res://scripts/Game/classes.gd", "res://scripts/character/classes.gd"],
	["res://scripts/Game/character_setup.gd", "res://scripts/character/character_setup.gd"],
	["res://scripts/Game/powers.gd", "res://scripts/character/powers.gd"],
	["res://scripts/Game/survival.gd", "res://scripts/character/survival.gd"],
	["res://scripts/Game/afflictions.gd", "res://scripts/character/afflictions.gd"],
	["res://scripts/enemy.gd", "res://scripts/actors/enemy.gd"],
	["res://scripts/enemy_data.gd", "res://scripts/actors/enemy_data.gd"],
	["res://scripts/npc_data.gd", "res://scripts/actors/npc_data.gd"],
	["res://scripts/npc_talk.gd", "res://scripts/actors/npc_talk.gd"],
	["res://scripts/spawn_entry.gd", "res://scripts/actors/spawn_entry.gd"],
	["res://scripts/spawn_table.gd", "res://scripts/actors/spawn_table.gd"],
	["res://scripts/population.gd", "res://scripts/actors/population.gd"],
	["res://scripts/animation_hooks.gd", "res://scripts/actors/animation_hooks.gd"],
	["res://scripts/Bodies/creature_body.gd", "res://scripts/actors/creature_body.gd"],
	["res://scripts/Bodies/ragdoll.gd", "res://scripts/actors/ragdoll.gd"],
	["res://scripts/Game/followers.gd", "res://scripts/actors/followers.gd"],
	["res://scripts/Game/horse.gd", "res://scripts/actors/horse.gd"],
	["res://scripts/Game/rider.gd", "res://scripts/actors/rider.gd"],
	["res://scripts/Game/carriage.gd", "res://scripts/actors/carriage.gd"],
	["res://scripts/melee_combat.gd", "res://scripts/combat/melee_combat.gd"],
	["res://scripts/damage_info.gd", "res://scripts/combat/damage_info.gd"],
	["res://scripts/combat_feedback.gd", "res://scripts/combat/combat_feedback.gd"],
	["res://scripts/Combat/ranged_combat.gd", "res://scripts/combat/ranged_combat.gd"],
	["res://scripts/Combat/arrow.gd", "res://scripts/combat/arrow.gd"],
	["res://scripts/faction_data.gd", "res://scripts/factions/faction_data.gd"],
	["res://scripts/factions.gd", "res://scripts/factions/factions.gd"],
	["res://scripts/inventory_ui.gd", "res://scripts/ui/inventory_ui.gd"],
	["res://scripts/stats_ui.gd", "res://scripts/ui/stats_ui.gd"],
	["res://scripts/container_ui.gd", "res://scripts/ui/container_ui.gd"],
	["res://scripts/barter_ui.gd", "res://scripts/ui/barter_ui.gd"],
	["res://scripts/interaction_hud.gd", "res://scripts/ui/interaction_hud.gd"],
	["res://scripts/status_hud.gd", "res://scripts/ui/status_hud.gd"],
	["res://scripts/vitals_hud.gd", "res://scripts/ui/vitals_hud.gd"],
	["res://scripts/compass_hud.gd", "res://scripts/ui/compass_hud.gd"],
	["res://scripts/pause_menu.gd", "res://scripts/ui/pause_menu.gd"],
	["res://scripts/World/arrest_ui.gd", "res://scripts/ui/arrest_ui.gd"],
	["res://scripts/World/world_debug_map.gd", "res://scripts/ui/world_debug_map.gd"],
	["res://scripts/Game/rest_spots.gd", "res://scripts/world/rest_spots.gd"],
	["res://scripts/Game/homes.gd", "res://scripts/world/homes.gd"],
	["res://scripts/Game/planter.gd", "res://scripts/world/planter.gd"],
	["res://scripts/Game/story.gd", "res://scripts/quests/story.gd"],
	["res://scripts/World/quest_manager.gd", "res://scripts/quests/quest_manager.gd"],
	["res://scripts/World/building_door.gd", "res://scripts/towns/building_door.gd"],
	["res://scripts/World/building_plot.gd", "res://scripts/towns/building_plot.gd"],
	["res://scripts/World/interior_builder.gd", "res://scripts/towns/interior_builder.gd"],
	["res://scripts/World/residents.gd", "res://scripts/towns/residents.gd"],
	["res://scripts/World/room_decorator.gd", "res://scripts/towns/room_decorator.gd"],
	["res://scripts/World/settlement_planner.gd", "res://scripts/towns/settlement_planner.gd"],
	["res://scripts/World/town_builder.gd", "res://scripts/towns/town_builder.gd"],
	["res://scripts/World/town_data.gd", "res://scripts/towns/town_data.gd"],
	["res://scripts/World/town_layout.gd", "res://scripts/towns/town_layout.gd"],
	["res://scripts/World/town_life.gd", "res://scripts/towns/town_life.gd"],
	["res://scripts/World/named_settlements.gd", "res://scripts/towns/named_settlements.gd"],
	["res://scripts/World/locks.gd", "res://scripts/towns/locks.gd"],
	["res://scripts/World/crime_manager.gd", "res://scripts/towns/crime_manager.gd"],
	["res://scripts/World/dungeon_builder.gd", "res://scripts/dungeons/dungeon_builder.gd"],
	["res://scripts/World/dungeon_data.gd", "res://scripts/dungeons/dungeon_data.gd"],
	["res://scripts/World/dungeon_door.gd", "res://scripts/dungeons/dungeon_door.gd"],
	["res://scripts/World/dungeon_entrance_poi_data.gd", "res://scripts/dungeons/dungeon_entrance_poi_data.gd"],
	["res://scripts/World/dungeon_feature.gd", "res://scripts/dungeons/dungeon_feature.gd"],
	["res://scripts/World/dungeon_manager.gd", "res://scripts/dungeons/dungeon_manager.gd"],
	["res://main_menu.tscn", "res://scenes/game/main_menu.tscn"],
	["res://test_level.tscn", "res://scenes/game/game.tscn"],
	["res://player.tscn", "res://scenes/player/player.tscn"],
	["res://scripts/Resources/iron_chestplate.tres", "res://data/weapons/iron_chestplate.tres"],
	["res://scripts/Resources/iron_dagger.tres", "res://data/weapons/iron_dagger.tres"],
	["res://scripts/Resources/iron_shield.tres", "res://data/weapons/iron_shield.tres"],
	["res://scripts/Resources/iron_sword.tres", "res://data/weapons/iron_sword.tres"],
	["res://scripts/Resources/iron_warhammer.tres", "res://data/weapons/iron_warhammer.tres"],
	["res://scripts/Resources/steel_greatsword.tres", "res://data/weapons/steel_greatsword.tres"],
	["res://scripts/World/", "res://scripts/world/"],
	["res://scripts/Magic/", "res://scripts/magic/"],
	["res://scripts/Crafting/", "res://scripts/crafting/"],
	["res://scripts/Dialogue/", "res://scripts/dialogue/"],
	["res://scripts/Quests/", "res://scripts/quests/"],
	["res://scripts/Realms/", "res://scripts/realms/"],
	["res://scripts/Save/", "res://scripts/save/"],
	["res://scripts/UI/", "res://scripts/ui/"],
	["res://scripts/Audio/", "res://scripts/audio/"],
	["res://scripts/Resources/Armor/", "res://data/armor/"],
	["res://scripts/Resources/Artifacts/", "res://data/artifacts/"],
	["res://scripts/Resources/Books/", "res://data/books/"],
	["res://scripts/Resources/Clothing/", "res://data/clothing/"],
	["res://scripts/Resources/Clutter/", "res://data/clutter/"],
	["res://scripts/Resources/Consumables/", "res://data/consumables/"],
	["res://scripts/Resources/Dialogue/", "res://data/dialogue/"],
	["res://scripts/Resources/Encounters/", "res://data/encounters/"],
	["res://scripts/Resources/Enemies/", "res://data/enemies/"],
	["res://scripts/Resources/Factions/", "res://data/factions/"],
	["res://scripts/Resources/Ingredients/", "res://data/ingredients/"],
	["res://scripts/Resources/Jewelry/", "res://data/jewelry/"],
	["res://scripts/Resources/Materials/", "res://data/materials/"],
	["res://scripts/Resources/Merchants/", "res://data/merchants/"],
	["res://scripts/Resources/Misc/", "res://data/misc/"],
	["res://scripts/Resources/NPCs/", "res://data/npcs/"],
	["res://scripts/Resources/Ranged/", "res://data/ranged/"],
	["res://scripts/Resources/SoulGems/", "res://data/soul_gems/"],
	["res://scripts/Resources/Spawns/", "res://data/spawns/"],
	["res://scripts/Resources/Treasure/", "res://data/treasure/"],
	["res://scripts/Resources/Weapons/", "res://data/weapons/"],
	["res://scripts/Resources/World/", "res://data/world/"],
]


## Rewrites every old res:// path inside save data (values and dictionary keys) to where the file is now
static func migrate_moved_paths(v: Variant) -> Variant:
	if v is String:
		var s := v as String
		if not s.begins_with("res://"):
			return s
		for pair in MOVED_PATHS:
			if s.begins_with(String(pair[0])):
				return String(pair[1]) + s.substr(String(pair[0]).length())
		return s
	if v is Array:
		var out := []
		for x in v:
			out.append(migrate_moved_paths(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[migrate_moved_paths(k)] = migrate_moved_paths(v[k])
		return out
	return v
