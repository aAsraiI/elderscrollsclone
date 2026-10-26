extends SceneTree
## Headless tests for stage 9c (furnished rooms, things on shelves, stealing them).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage9c.gd

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


func _run() -> void:
	t_decorator()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _items(node: Node) -> Array:
	return node.find_children("*", "WorldItem", true, false)


func t_decorator() -> void:
	print("-- the decorator")
	WorldState.clear()
	var counts := {}
	for theme in ["home", "tavern", "smithy", "library", "crypt", "mine", "vault"]:
		var trial := Node3D.new()
		var r := RoomDecorator.decorate(trial, Rect2(-5, -4, 10, 8), theme, 30, 77, "", "t/" + theme, [Vector3(0, 0, -4)])
		counts[theme] = r
		check("%s: furniture and things on it" % theme, r["pieces"] >= 3 and r["items"] >= 2, str(r))
		trial.free()
	var room := Node3D.new()
	RoomDecorator.decorate(room, Rect2(-5, -4, 10, 8), "home", 10, 5, "house_1", "t/same", [Vector3(0, 0, -4)])
	var first := _items(room).map(func(w: WorldItem) -> String: return "%s@%s" % [w.item.display_name, w.position.snapped(Vector3.ONE * 0.01)])
	room.free()
	room = Node3D.new()
	RoomDecorator.decorate(room, Rect2(-5, -4, 10, 8), "home", 10, 5, "house_1", "t/same", [Vector3(0, 0, -4)])
	var again := _items(room).map(func(w: WorldItem) -> String: return "%s@%s" % [w.item.display_name, w.position.snapped(Vector3.ONE * 0.01)])
	check("the same room is furnished the same way every time", first == again and first.size() > 0)
	var items := _items(room)
	check("things are owned, frozen and remembered by slot", items.all(func(w: WorldItem) -> bool: return w.owner_id == "house_1" and w.start_frozen and w.slot_id.begins_with("t/same/slot_")))
	check("owned things say Steal", (items[0] as WorldItem).get_prompt().begins_with("Steal"))
	var path_clear := true
	for c in room.get_children():
		if c is Node3D and String(c.name).begins_with("Decor_"):
			var p := (c as Node3D).position
			if absf(p.x) < 0.9 and p.z < 0.0:
				path_clear = false
	check("a walkway from the door stays clear", path_clear)
	# taking a slot empties it; shops and homes refill after a few days
	var slot := (items[0] as WorldItem).slot_id
	WorldState.set_record(WorldItem.taken_key(slot), {"day": 1})
	room.free()
	room = Node3D.new()
	RoomDecorator.decorate(room, Rect2(-5, -4, 10, 8), "home", 10, 5, "house_1", "t/same", [Vector3(0, 0, -4)], 3, 2)
	check("a taken thing stays gone", not _items(room).any(func(w: WorldItem) -> bool: return w.slot_id == slot))
	room.free()
	room = Node3D.new()
	RoomDecorator.decorate(room, Rect2(-5, -4, 10, 8), "home", 10, 5, "house_1", "t/same", [Vector3(0, 0, -4)], 3, 5)
	check("...until the room restocks", _items(room).any(func(w: WorldItem) -> bool: return w.slot_id == slot))
	room.free()
	room = Node3D.new()
	RoomDecorator.decorate(room, Rect2(-6, -6, 12, 12), "vault", 60, 9, "", "t/vault", [Vector3(0, 0, -6)])
	check("dungeon things belong to nobody", _items(room).all(func(w: WorldItem) -> bool: return w.owner_id == "" and w.get_prompt().begins_with("Take")))
	room.free()
	check("guild things are free for members only", not WorldItem.may_take("guild:fighters") and WorldItem.may_take(""))


func t_in_game() -> void:
	print("-- in a real house")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var town := wm.get_nearest_town(p.global_position)
	var house: BuildingPlot = null
	for b in town.town.buildings:
		if b.kind == BuildingPlot.Kind.HOUSE and house == null:
			house = b
	check("the start town has a house", house != null)
	if house == null:
		return
	await wm.dungeons.enter(house.id, house.get_door_position(), 0.0)
	await frames(10)
	var interior := wm.dungeons.get_interior_root()
	var items := _items(interior)
	check("the house is furnished with things in it", items.size() >= 3, "%d in %s" % [items.size(), interior.get_meta("module", "")])
	check("they are the family's", items.all(func(wi: WorldItem) -> bool: return wi.owner_id == house.id))
	var w := items[0] as WorldItem
	var thing := w.item
	var inv := p.get_node("Inventory") as Inventory
	var slot := w.slot_id
	var before := inv.get_count(w.item)
	var stolen_before := CrimeManager.stolen_count(inv, w.item)
	w.interact(inv)
	await frames(2)
	check("taking it puts it in your pack", inv.get_count(thing) == before + 1)
	check("...and marks it stolen", CrimeManager.stolen_count(inv, thing) == stolen_before + 1)
	check("...and the slot remembers", WorldState.has_record(WorldItem.taken_key(slot)))
	var _crate := interior.find_children("*", "WorldItem", true, false)
	check("placed things are not saved as loose items", not get_nodes_in_group("persistent").any(func(n: Node) -> bool: return n is WorldItem and (n as WorldItem).slot_id != ""))
	# walls and furniture leave the residents' spots free (no decor on the work spot)
	var spots: Dictionary = wm.dungeons.current_spots
	var work: Vector3 = spots.get("work", Vector3.ZERO)
	var blocked := false
	for c in interior.get_children():
		if c is Node3D and String(c.name).begins_with("Decor_") and Vector2((c as Node3D).position.x - work.x, (c as Node3D).position.z - work.z).length() < 0.6:
			blocked = true
	check("nothing is built on the resident's work spot", not blocked)
