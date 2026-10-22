extends SceneTree
## Loads the real main scene: starts at a town, walks into a building, saves inside, loads, and
## checks the player is back inside the same building with a picked lock and a key remembered.
## Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage2_scene.gd

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


func _door_of(wm: WorldManager, b: BuildingPlot) -> BuildingDoor:
	var node := wm.get_poi_node(b.town_id)
	if node == null:
		return null
	for d in node.find_children("*", "BuildingDoor", true, false):
		if (d as BuildingDoor).building_id == b.id:
			return d
	return null


func _run() -> void:
	change_scene_to_file("res://test_level.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var player := get_first_node_in_group("player") as Node3D
	(get_first_node_in_group("world_clock") as WorldClock).set_time(12.0)  # shops open
	await frames(40)
	check("the main scene has towns", wm != null and wm.towns.size() > 0)
	var town := wm.get_town_at(player.global_position, 10.0)
	check("the game starts at a town", town != null, str(player.global_position))
	if town == null:
		_finish()
		return
	var inv := player.get_node("Inventory") as Inventory
	check("the test loadout has lockpicks", inv.get_count(Locks.get_lockpick()) == 10)

	var shop: BuildingPlot = null
	var house: BuildingPlot = null
	for b in town.town.buildings:
		if b.is_public() and shop == null:
			shop = b
		if not b.is_public() and b.starts_locked and house == null:
			house = b
	check("the town has a public building and a locked house", shop != null and house != null)
	if shop == null or house == null:
		_finish()
		return
	# open the house's lock (as if picked) and carry its key
	Locks.set_locked(house.id, false)
	inv.add_item(KeyRing.get_key(house.id, house.display_name))

	# towns are big now: go to the shop first so its part of town is loaded
	player.global_position = shop.get_door_position() + Vector3.UP
	var door: Node = null
	for i in 300:
		door = _door_of(wm, shop)
		if door != null:
			break
		await frames(1)
	check("the shop door is in the scene", door != null)
	if door == null:
		_finish()
		return
	player.global_position = shop.get_door_position() + Vector3.UP
	door.interact(inv)
	await frames(60)
	var dm := wm.dungeons
	check("walked into the shop", dm.is_in_building() and dm.current_entrance_id == shop.id)
	var meta := sm.build_save_data()["meta"] as Dictionary
	check("the save says where you are", String(meta.get("location", "")).contains(shop.display_name), String(meta.get("location", "")))
	check("saving inside works", sm.save_game("slot_test2"), sm.get_last_error())

	await dm.exit()
	await frames(5)
	check("left the shop", not dm.is_inside())
	Locks.set_locked(house.id, true)  # changed after the save: the load must undo this
	inv.remove_item(KeyRing.get_key(house.id, house.display_name))

	check("load_game starts", sm.load_game("slot_test2"), sm.get_last_error())
	await frames(100)
	wm = get_first_node_in_group("world_manager") as WorldManager
	sm = get_first_node_in_group("save_manager") as SaveManager
	player = get_first_node_in_group("player") as Node3D
	dm = wm.dungeons
	inv = player.get_node("Inventory") as Inventory
	check("after loading you are inside the same shop", dm.is_in_building() and dm.current_entrance_id == shop.id)
	check("standing on its floor", player.global_position.y < DungeonManager.DUNGEON_Y + 20.0 and player.global_position.y > DungeonManager.DUNGEON_Y - 2.0, str(player.global_position))
	check("the picked lock came back open", not Locks.is_locked(house.id, true))
	check("the key came back", inv.has_item(KeyRing.get_key(house.id, house.display_name)))
	await dm.exit()
	await frames(10)
	check("leaving puts you at the shop door", player.global_position.distance_to(shop.get_door_position()) < 4.0, str(player.global_position.distance_to(shop.get_door_position())))
	sm.delete_slot("slot_test2")
	_finish()


func _finish() -> void:
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
