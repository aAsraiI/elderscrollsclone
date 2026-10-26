extends SceneTree
## A short end-to-end playtest on the real game scene (the 16x16 km realm): start a new game,
## check the player and HUD, fight, walk into a town, go down a dungeon and back, then save and load.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_playtest.gd

var passes := 0
var fails := 0


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	SaveSession.begin_new_game(0, true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	await t_spawn(wm, player)
	await t_combat(player)
	await t_town(wm, player)
	await t_dungeon(wm, player)
	await t_save_load()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_spawn(wm: WorldManager, player: CharacterBody3D) -> void:
	print("-- a new game")
	check("the world and the player are there", wm != null and player != null)
	await secs(2.0)
	check("the player stands on the ground", player.is_on_floor() or absf(player.velocity.y) < 0.5, str(player.global_position))
	check("the start is by a town", wm.get_town_at(player.global_position, 60.0) != null)
	var missing: Array[String] = []
	for part in ["Stats", "Inventory", "Equipment", "MeleeCombat", "Skills", "Stealth", "SpellCaster", "Spellbook",
			"InventoryUI", "MenuHub", "VitalsHUD", "CompassHUD", "DialogueUI", "JournalUI", "MagicUI", "PauseMenu"]:
		if player.get_node_or_null(part) == null:
			missing.append(part)
	check("every part of the player is there (player.tscn)", missing.is_empty(), str(missing))
	check("the sky and sun come from game.tscn", current_scene.get_node_or_null("WorldEnvironment") != null and current_scene.get_node_or_null("Sun") != null)
	check("creatures are listed in the ActorRegistry", ActorRegistry.count() > 0 and ActorRegistry.count() == get_nodes_in_group("enemies").size(),
		"%d vs %d" % [ActorRegistry.count(), get_nodes_in_group("enemies").size()])
	check("the town nearby is drawn as merged boxes", not current_scene.find_children("MergedBoxes", "MeshInstance3D", true, false).is_empty())


func t_combat(player: CharacterBody3D) -> void:
	print("-- a fight")
	var foe := Enemy.spawn(current_scene, player.global_position - player.global_basis.z * 1.6 + Vector3.UP * 0.3,
		load("res://data/weapons/iron_sword.tres"))
	foe.set_physics_process(false)  # stands still to be hit
	await frames(5)
	var hp := foe.stats.health
	var combat := player.get_node("MeleeCombat") as MeleeCombat
	var swung := false
	for i in 4:
		swung = combat.primary_attack() or swung
		await secs(0.9)
	check("the player can swing", swung)
	check("the swing hurts the creature in front", foe.stats.health < hp, "%f -> %f" % [hp, foe.stats.health])
	foe.queue_free()
	await frames(2)


func t_town(wm: WorldManager, player: CharacterBody3D) -> void:
	print("-- a town")
	var town := wm.get_nearest_town(player.global_position)
	wm.ensure_area_loaded(town.position, 2)
	player.global_position = town.position + Vector3(0, 30, 0)
	player.velocity = Vector3.ZERO
	await secs(4.0)
	check("the town is built", wm.get_poi_node(town.id) != null)
	check("people live there (the registry finds them near the plaza)", ActorRegistry.near(town.position, 120.0).size() >= 3,
		str(ActorRegistry.near(town.position, 120.0).size()))
	check("the player landed in town, not under it", player.global_position.y > wm.get_height_at(player.global_position.x, player.global_position.z) - 1.0)


func t_dungeon(wm: WorldManager, player: CharacterBody3D) -> void:
	print("-- a dungeon")
	var entrance: PlacedPOI = null
	var best := INF
	for p in wm.pois:
		if p.poi is DungeonEntrancePOIData and (p.poi as DungeonEntrancePOIData).dungeon != null and p.position.distance_to(player.global_position) < best:
			best = p.position.distance_to(player.global_position)
			entrance = p
	check("there is a dungeon entrance in the realm", entrance != null)
	if entrance == null:
		return
	var outside := entrance.position + Vector3(0, 0, -6)
	wm.ensure_area_loaded(outside, 2)
	player.global_position = Vector3(outside.x, wm.get_height_at(outside.x, outside.z) + 2.0, outside.z)
	await secs(0.5)
	var entered: bool = await wm.dungeons.enter(entrance.id, outside, 0.0)
	check("the player goes down", entered and wm.dungeons.is_inside())
	await secs(1.5)
	check("the floor is drawn as merged boxes", not wm.dungeons._root.find_children("MergedBoxes", "MeshInstance3D", true, false).is_empty() or not wm.dungeons._root.find_children("MergedRoom", "MeshInstance3D", true, false).is_empty())
	check("the player stands inside, not falling", player.global_position.y > DungeonManager.DUNGEON_Y - 50.0 and absf(player.velocity.y) < 20.0,
		str(player.global_position))
	wm.dungeons.exit()
	await secs(1.5)
	check("and comes back out", not wm.dungeons.is_inside() and player.global_position.distance_to(outside) < 30.0, str(player.global_position))


func t_save_load() -> void:
	print("-- save and load")
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var player := get_first_node_in_group("player")
	var inv := player.get_node("Inventory") as Inventory
	Currency.add_gold(inv, 77)
	var gold := Currency.get_gold(inv)
	var pos: Vector3 = player.global_position
	WorldState.set_record("playtest/flag", {"on": true})
	check("saving works", sm.save_game("slot_playtest"), sm.get_last_error())
	Currency.spend_gold(inv, 50)
	WorldState.set_record("playtest/after_save", {"on": true})
	check("loading starts", sm.load_game("slot_playtest"), sm.get_last_error())
	await frames(120)
	player = get_first_node_in_group("player")
	inv = player.get_node("Inventory") as Inventory
	check("gold came back", Currency.get_gold(inv) == gold, "%d vs %d" % [Currency.get_gold(inv), gold])
	check("the player is where they saved", (player as Node3D).global_position.distance_to(pos) < 3.0, "%s vs %s" % [(player as Node3D).global_position, pos])
	check("the world remembers what happened before the save", WorldState.has_record("playtest/flag"))
	check("...and nothing from after it", not WorldState.has_record("playtest/after_save"))
	sm = get_first_node_in_group("save_manager") as SaveManager
	sm.delete_slot("slot_playtest")
