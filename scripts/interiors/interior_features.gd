class_name InteriorFeatures
extends RefCounted
## What makes a stitched dungeon more than rooms to walk through, placed from its plan
## (DungeonAssembler) so that nothing is ever locked behind itself:
##   a locked door before the boss room, its key in a chest in a side room on this side of it
##   from gate_from_level: a gate on the main path, its lever in a room on this side of it
##   from traps_from_level: pressure plates in some corridors
##   secret_chance: a hidden room behind a loose stone, with a better chest
##   a lever puzzle in a big room guarding a caged chest (the order is carved on the cage)
##   poison gas in some crypt and sewer rooms, barricades across some corridors
##   a shortcut out of the boss room
## Everything is named by the room's id, so it is saved like the rest of the dungeon.

const MARKS := ["the sun", "the moon", "the stars", "the crown", "the skull", "the tree"]


static func apply(plan: DungeonAssembler, root: Node3D, data: DungeonData, dungeon_id: String, level: int, seed_value: int) -> Dictionary:
	var out := {"locked": 0, "gates": 0, "traps": 0, "secret": 0, "puzzles": 0, "gas": 0, "barricades": 0, "shortcut": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|features" % seed_value).hash()
	var rooms := {}
	for n in root.get_children():
		if n is RoomModule:
			rooms[int(String(n.name).get_slice("_", 0).trim_prefix("R"))] = n
	# who joined whom: child room -> [parent, parent's door, child's door]
	var parent := {}
	for l: Array in plan.links:
		parent[int(l[2])] = [int(l[0]), int(l[1]), int(l[3])]
	var boss := -1
	for p in plan.placed:
		if p.entry.role == RoomModule.Role.BOSS:
			boss = p.index
	var main := {}
	var at := boss
	while at >= 0:
		main[at] = true
		at = int(parent[at][0]) if parent.has(at) else -1
	var name := data.display_name if data != null else "dungeon"
	# ---- the locked door before the boss room, and its key in a side room
	if boss > 0 and parent.has(boss) and level >= 3:
		var j: Array = parent[boss]
		var door := _door_at(plan, root, int(j[0]), int(j[1]), "%s/door_boss" % dungeon_id)
		door.key_name = "Key to the %s's Inner Hall" % name
		door.lock_level = clampi(1 + level / 12, 1, 5)
		out["locked"] += 1
		var key_room := _side_room(plan, main, _behind(plan, parent, boss), rng)
		_put_in_chest(rooms.get(key_room), door.get_key(), "%s/r%d/keychest" % [dungeon_id, key_room])
	# ---- a gate on the main path, opened by a lever on this side of it
	if data != null and level >= data.gate_from_level and main.size() > 4:
		var path := main.keys()
		path.sort()
		var gated: int = path[path.size() / 2]
		if gated != boss and parent.has(gated):
			var j: Array = parent[gated]
			var gate := _door_at(plan, root, int(j[0]), int(j[1]), "%s/gate" % dungeon_id)
			gate.is_gate = true
			gate.name = "Gate"
			out["gates"] += 1
			var lever_room := _side_room(plan, main, _behind(plan, parent, gated), rng)
			var lroom: RoomModule = rooms.get(lever_room)
			if lroom != null:
				var lever := DungeonFeature.new()
				lever.kind = DungeonFeature.Kind.LEVER
				lever.save_id = "door/%s/gate" % dungeon_id
				lever.target = "Gate"
				lever.name = "Lever"
				root.add_child(lever)
				lever.position = lroom.transform * (_wall_spot(lroom) + Vector3(0, 0.6, 0))
	# ---- traps in corridors
	if data != null and level >= data.traps_from_level:
		for i in rooms:
			var r: RoomModule = rooms[i]
			if r.role in [RoomModule.Role.CORRIDOR, RoomModule.Role.JUNCTION] and rng.randf() < 0.3:
				var trap := DungeonFeature.new()
				trap.kind = DungeonFeature.Kind.TRAP
				trap.save_id = "%s/trap" % r.get_meta("room_id")
				trap.damage = 8.0 + level * 1.2
				trap.name = "Trap"
				r.add_child(trap)
				out["traps"] += 1
	# ---- the secret room
	if plan.secret_link.size() == 4:
		var l := plan.secret_link
		var near: RoomModule = rooms.get(int(l[0]))
		var far: RoomModule = rooms.get(int(l[2]))
		if near != null and far != null:
			var d := near.doorways()[int(l[1])]
			var wall := InteriorKit.cap(d, String(near.themes[0]))
			wall.name = "SecretWall"
			wall.add_to_group("interior_dynamic")  # it opens: never merged into the room
			var stone := DungeonFeature.new()
			stone.kind = DungeonFeature.Kind.SECRET
			stone.save_id = "%s/secret" % near.get_meta("room_id")
			stone.target = "SecretWall"
			stone.name = "LooseStone"
			near.add_child(stone)
			stone.position = d.position + d.basis.z * 0.6 + Vector3(0, 1.0, 0) + d.basis.x * 1.2
			if DungeonFeature.is_done(stone.save_id):
				wall.queue_free()
				stone.queue_free()
			_treasure(far, "%s/secret_chest" % far.get_meta("room_id"), level + 3)
			out["secret"] += 1
	# ---- a lever puzzle in a big room
	for i in rooms:
		var r: RoomModule = rooms[i]
		if r.role == RoomModule.Role.ROOM and r.cells.x * r.cells.z >= 6 and rng.randf() < 0.35 and out["puzzles"] == 0:
			_puzzle(r, rng, level)
			out["puzzles"] += 1
	# ---- gas and barricades
	for i in rooms:
		var r: RoomModule = rooms[i]
		var theme := String(r.themes[0])
		if theme in ["crypt", "sewer", "lair"] and r.role == RoomModule.Role.ROOM and rng.randf() < 0.15:
			var gas := InteriorHazards.GasCloud.new()
			gas.name = "Gas"
			gas.size = Vector3(r.bounds().size.x - 1.0, 2.5, r.bounds().size.z - 1.0)
			gas.damage_per_second = 2.0 + level * 0.15
			r.add_child(gas)
			out["gas"] += 1
	for l: Array in plan.links:
		var child: RoomModule = rooms.get(int(l[2]))
		if child != null and child.role == RoomModule.Role.CORRIDOR and rng.randf() < 0.08 and int(l[2]) != boss:
			var b := InteriorHazards.Barricade.new()
			b.save_id = "%s/barricade" % child.get_meta("room_id")
			b.name = "Barricade"
			root.add_child(b)
			var w := plan.door_world(plan.placed[int(l[0])], int(l[1]))
			b.position = Vector3(w["pos"])
			b.basis = Basis.looking_at(Vector3(w["out"]), Vector3.UP)
			out["barricades"] += 1
	# ---- a shortcut out of the boss room
	var broom: RoomModule = rooms.get(boss)
	if broom != null:
		var way := DungeonDoor.new()
		way.name = "Shortcut"
		way.entrance_id = dungeon_id
		way.label = "Take the shortcut out"
		way.is_exit = true
		way.target_floor = -1
		broom.add_child(way)
		way.position = Vector3(0, 1.3, broom.bounds().size.z * 0.5 - 0.6)
		out["shortcut"] += 1
	return out


# A door filling the joint between a room and the one joined at its doorway
static func _door_at(plan: DungeonAssembler, root: Node3D, room_index: int, door_index: int, id: String) -> InteriorDoor:
	var w := plan.door_world(plan.placed[room_index], door_index)
	var d: Dictionary = plan.placed[room_index].entry.doors[door_index]
	var door := InteriorDoor.new()
	door.door_id = id
	door.name = "Door_%d_%d" % [room_index, door_index]
	door.size = Vector2(float(d["width"]), 3.0)
	root.add_child(door)
	door.position = Vector3(w["pos"])
	door.basis = Basis.looking_at(Vector3(w["out"]), Vector3.UP)
	return door


# Every room behind a room (itself and all joined after it)
static func _behind(plan: DungeonAssembler, parent: Dictionary, room: int) -> Dictionary:
	var out := {room: true}
	var grew := true
	while grew:
		grew = false
		for p in plan.placed:
			if not out.has(p.index) and parent.has(p.index) and out.has(int(parent[p.index][0])):
				out[p.index] = true
				grew = true
	return out


# A room off the main path (deepest first) that isn't in `blocked`; else any room on this side
static func _side_room(plan: DungeonAssembler, main: Dictionary, blocked: Dictionary, rng: RandomNumberGenerator) -> int:
	var options: Array = []
	for p in plan.placed:
		if not blocked.has(p.index) and not main.has(p.index) and p.entry.role in [RoomModule.Role.ROOM, RoomModule.Role.HALL, RoomModule.Role.DEAD_END]:
			options.append(p)
	if options.is_empty():
		for p in plan.placed:
			if not blocked.has(p.index) and p.index > 0:
				options.append(p)
	if options.is_empty():
		return 0
	options.sort_custom(func(a: DungeonAssembler.Placed, b: DungeonAssembler.Placed) -> bool: return a.depth > b.depth)
	return options[rng.randi_range(0, mini(options.size(), 3) - 1)].index


static func _wall_spot(r: RoomModule) -> Vector3:
	return Vector3(r.bounds().size.x * 0.5 - 0.6, 0, 0)


static func _put_in_chest(r: RoomModule, item: ItemData, save_id: String) -> void:
	if r == null:
		return
	var chest := POIBuilder.make_chest("Strongbox", [], save_id, absi(save_id.hash()) | 1)
	r.add_child(chest)
	chest.position = Vector3(-r.bounds().size.x * 0.5 + 1.0, 0.35, r.bounds().size.z * 0.5 - 1.0)
	var cc := chest.get_node("ContainerComponent") as ContainerComponent
	chest.ready.connect(func() -> void:  # its inventory exists once it is in the world
		if not WorldState.has_record(save_id + "/key_placed"):
			WorldState.set_record(save_id + "/key_placed", {"done": true})
			cc.inventory.add_item(item), CONNECT_ONE_SHOT)


static func _treasure(r: RoomModule, save_id: String, level: int) -> void:
	var loot: Array[LootEntry] = []
	loot.append_array(ItemCatalog.curve_loot(level, level + 3, 2.0))
	loot.append(ItemCatalog.gold_loot(level + 3, 1.0))
	var chest := POIBuilder.make_chest("Hidden Chest", loot, save_id, absi(save_id.hash()) | 1)
	r.add_child(chest)
	chest.position = Vector3(0, 0.35, 0)


# Three levers along the walls and a caged chest in the middle; the order is carved on the cage
static func _puzzle(r: RoomModule, rng: RandomNumberGenerator, level: int) -> void:
	var id := "%s/puzzle" % r.get_meta("room_id")
	var marks := MARKS.duplicate()
	for i in range(marks.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = marks[i]
		marks[i] = marks[j]
		marks[j] = t
	marks = marks.slice(0, 3)
	var order := [0, 1, 2]
	for i in range(2, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var puzzle := InteriorHazards.LeverPuzzle.new()
	puzzle.name = "Puzzle"
	puzzle.save_id = id
	puzzle.order = order
	puzzle.gate_name = "Vault"
	puzzle.damage = 6.0 + level
	r.add_child(puzzle)
	var b := r.bounds()
	for i in 3:
		var lever := InteriorHazards.PuzzleLever.new()
		lever.puzzle = puzzle
		lever.index = i
		lever.mark = marks[i]
		lever.name = "PuzzleLever%d" % i
		r.add_child(lever)
		lever.position = Vector3(-b.size.x * 0.5 + 0.8, 0, -b.size.z * 0.25 + i * b.size.z * 0.25)
		lever.rotation.y = -PI * 0.5
	_treasure(r, id + "_chest", level + 4)
	if WorldState.has_record(id):
		return
	var cage := Node3D.new()
	cage.name = "Vault"
	r.add_child(cage)
	for side in 4:
		var bars := InteriorDoor.new()
		bars.door_id = "%s/bars%d" % [id, side]
		bars.is_gate = true
		bars.size = Vector2(1.8, 1.6)
		bars.hint = "Carved on the bars: %s, then %s, then %s." % [marks[order[0]], marks[order[1]], marks[order[2]]]
		cage.add_child(bars)
		bars.position = Basis(Vector3.UP, side * PI * 0.5) * Vector3(0, 0, 0.9)
		bars.rotation.y = side * PI * 0.5
