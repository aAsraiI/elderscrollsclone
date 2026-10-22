class_name DungeonBuilder
extends RefCounted
## Generates one floor of a dungeon from a DungeonData and a seed. The same seed always gives the
## same dungeon.
##
## Size grows with the dungeon's level: more rooms per floor, and more floors (see
## DungeonData.floors_for: one floor below level 22, up to four). Only the floor you are on is built.
##
## A floor is a tree of grid cells (with a few loops). Each cell holds one room of its own size,
## joined to its neighbors by corridors:
##   corridor junction (small), chamber, hall, and the great hall at the far end of the floor
## The first room of floor 0 has the way out; the first room of deeper floors has stairs up.
## The far room has stairs down and a mini-boss, or on the last floor the boss, its chest and a
## shortcut back out. From gate_from_level on, a gate blocks the far room until you pull a lever
## somewhere else on the floor. Most floors hide a secret room behind a loose stone, and from
## traps_from_level on, pressure plates wait in some rooms. Every room is furnished by the
## dungeon's theme (RoomDecorator) with loot for its level.
##
## Local space: the start room is centered on the origin.

const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const WALL_THICKNESS := 0.6
const DOOR_WIDTH := 3.2
const DOOR_HEIGHT := 3.2
const MAX_ROOMS := 40


## Returns {"root", "start" (local), "start_yaw", "down_spot" (local, stairs down, or null),
## "rooms", "chests", "enemies", "boss" (bool), "floor", "floors", "cells", "links", "signature"}
## dungeon_id is the entrance's stable id (it names the chests and enemies so they can be saved).
## level_min / level_max: how hard the land around the entrance is.
static func build(data: DungeonData, dungeon_seed: int, dungeon_id: String, level_min: int = 1, level_max: int = 10, floor_index: int = 0) -> Dictionary:
	var lmin0 := maxi(level_min + data.level_offset, 1)
	var lmax0 := maxi(level_max + data.level_offset, lmin0)
	var floors := data.floors_for((lmin0 + lmax0) / 2)
	var f := clampi(floor_index, 0, floors - 1)
	var last := f == floors - 1
	var lmin := lmin0 + f * 2  # each floor deeper is a little harder
	var lmax := lmax0 + f * 2
	var level := (lmin + lmax) / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = dungeon_seed if f == 0 else ("%d|floor|%d" % [dungeon_seed, f]).hash()
	var size := data.room_size
	var height := data.ceiling_height
	var prefix := "dungeon/%s" % dungeon_id if f == 0 else "dungeon/%s/f%d" % [dungeon_id, f]

	# ---- layout: grow a tree of rooms, then add a few loops
	var base := rng.randi_range(mini(data.min_rooms, data.max_rooms), maxi(data.min_rooms, data.max_rooms))
	var wanted := clampi(base + int(data.rooms_per_10_levels * maxf(level - 5, 0) / 10.0), 2, MAX_ROOMS)
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var occupied := {Vector2i.ZERO: true}
	var links := {}  # edge key -> true
	var tries := 0
	while cells.size() < wanted and tries < 4000:
		tries += 1
		var from: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var to: Vector2i = from + DIRS[rng.randi_range(0, 3)]
		if occupied.has(to):
			continue
		occupied[to] = true
		cells.append(to)
		links[_edge_key(from, to)] = true
	for c in cells:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if occupied.has(n) and not links.has(_edge_key(c, n)) and rng.randf() < data.extra_loops:
				links[_edge_key(c, n)] = true
	var dist := _room_distances(cells, links, occupied)
	var far := Vector2i.ZERO
	for c in cells:
		if int(dist.get(c, 0)) > int(dist.get(far, 0)):
			far = c

	# ---- a secret room next to some room, behind a loose stone
	var secret := Vector2i(1 << 20, 0)
	var secret_from := Vector2i.ZERO
	if cells.size() > 2 and rng.randf() < data.secret_chance:
		for attempt in 30:
			var host: Vector2i = cells[rng.randi_range(1, cells.size() - 1)]
			var d: Vector2i = DIRS[rng.randi_range(0, 3)]
			if host != far and not occupied.has(host + d):
				secret = host + d
				secret_from = host
				break
	var has_secret := secret.x != 1 << 20

	# ---- room sizes (half extents) per cell
	var half := {}
	for c in cells:
		var kind := rng.randf()
		var hx := size * 0.5 - 0.2
		var hz := size * 0.5 - 0.2
		if c == far:
			pass  # the great hall: the whole cell
		elif c == Vector2i.ZERO:
			hx *= 0.75
			hz *= 0.75
		elif kind < 0.25:
			hx = DOOR_WIDTH * 0.5 + 1.2  # a junction where corridors meet
			hz = hx
		elif kind < 0.75:
			hx *= rng.randf_range(0.55, 0.75)
			hz *= rng.randf_range(0.55, 0.75)
		else:
			hx *= rng.randf_range(0.8, 0.95)
			hz *= rng.randf_range(0.8, 0.95)
		half[c] = Vector2(hx, hz)
	if has_secret:
		half[secret] = Vector2(size * 0.28, size * 0.28)

	var root := Node3D.new()
	root.name = "Dungeon"
	var wc := data.wall_color
	var fc := data.floor_color
	var all_cells: Array[Vector2i] = cells.duplicate()
	if has_secret:
		all_cells.append(secret)

	# ---- rooms, corridors and lamps
	var openings := {}  # cell -> the sides with a doorway
	for c in all_cells:
		openings[c] = []
	for c in all_cells:
		var h: Vector2 = half[c]
		var center := Vector3(c.x * size, 0.0, c.y * size)
		POIBuilder.add_box(root, Vector3(h.x * 2.0 + WALL_THICKNESS, WALL_THICKNESS, h.y * 2.0 + WALL_THICKNESS), center + Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0), fc)
		POIBuilder.add_box(root, Vector3(h.x * 2.0 + WALL_THICKNESS, WALL_THICKNESS, h.y * 2.0 + WALL_THICKNESS), center + Vector3(0.0, height + WALL_THICKNESS * 0.5, 0.0), wc.darkened(0.2))
		var lamp := OmniLight3D.new()
		lamp.light_color = data.light_color
		lamp.light_energy = data.light_energy
		lamp.omni_range = maxf(h.x, h.y) * 2.4
		lamp.position = center + Vector3(0.0, height * 0.75, 0.0)
		root.add_child(lamp)
		for d in DIRS:
			var n: Vector2i = c + d
			var open := (occupied.has(n) or n == secret) and (links.has(_edge_key(c, n)) or (has_secret and _edge_key(c, n) == _edge_key(secret_from, secret)))
			_room_wall(root, center, h, d, height, open, wc)
			if open:
				(openings[c] as Array).append(d)
			if open:
				_corridor(root, center, h, d, size, height, wc, fc)

	# ---- the way out (floor 0) or stairs up, against a wall of the start room without a doorway
	var start_h: Vector2 = half[Vector2i.ZERO]
	var exit_dir := Vector2i(0, 1)
	var free_sides: Array[Vector2i] = []
	for d in DIRS:
		if not links.has(_edge_key(Vector2i.ZERO, d)) and not (has_secret and secret == d):
			free_sides.append(d)
	if not free_sides.is_empty():
		exit_dir = free_sides[rng.randi_range(0, free_sides.size() - 1)]
	var exit_pos := _wall_spot(Vector3.ZERO, start_h, exit_dir, 0.9)
	var door := DungeonDoor.new()
	door.name = "Exit" if f == 0 else "StairsUp"
	door.entrance_id = dungeon_id
	door.label = "Leave" if f == 0 else "Go up (floor %d)" % f
	door.is_exit = f == 0
	door.target_floor = -1 if f == 0 else f - 1
	root.add_child(door)
	door.position = exit_pos + Vector3(0.0, 1.3, 0.0)
	_door_frame(root, exit_pos, exit_dir, Color(0.35, 0.25, 0.15) if f == 0 else wc.lightened(0.15))
	var start := exit_pos - Vector3(exit_dir.x, 0.0, exit_dir.y) * 2.2 + Vector3(0.0, 0.1, 0.0)
	var start_yaw := atan2(float(exit_dir.x), float(exit_dir.y))  # facing away from the door, into the room

	# ---- loot tables
	var chest_loot: Array[LootEntry] = data.loot_table.duplicate()
	if data.curve_loot:
		chest_loot.append_array(ItemCatalog.curve_loot(lmin, lmax))
	chest_loot.append_array(ItemCatalog.treasure_loot(lmin, lmax))
	chest_loot.append_array(ItemCatalog.tag_loot(PackedStringArray(RoomDecorator.THEMES.get(data.theme, {}).get("tags", [])), level, 0.6))
	chest_loot.append(ItemCatalog.gold_loot(level, 0.8))

	# ---- the far room: stairs down, or (last floor) the boss's chest and a shortcut out
	var far_center := Vector3(far.x * size, 0.0, far.y * size)
	var far_h: Vector2 = half[far]
	var far_dir := Vector2i.ZERO
	for d in DIRS:
		if not links.has(_edge_key(far, far + d)) and not (has_secret and secret == far + d):
			far_dir = d
			break
	if far_dir == Vector2i.ZERO:
		far_dir = Vector2i(0, -1)
	var down_spot: Variant = null
	if far != Vector2i.ZERO:
		var spot := _wall_spot(far_center, far_h, far_dir, 0.9)
		var way := DungeonDoor.new()
		way.entrance_id = dungeon_id
		if last:
			way.name = "Shortcut"
			way.label = "Take the shortcut out"
			way.is_exit = true
		else:
			way.name = "StairsDown"
			way.label = "Go down (floor %d)" % (f + 2)
			way.target_floor = f + 1
			down_spot = spot - Vector3(far_dir.x, 0.0, far_dir.y) * 2.2 + Vector3(0.0, 0.1, 0.0)
		root.add_child(way)
		way.position = spot + Vector3(0.0, 1.3, 0.0)
		_door_frame(root, spot, far_dir, wc.lightened(0.2))

	# ---- the gate in front of the far room, and its lever somewhere else
	if level >= data.gate_from_level and data.gate_from_level > 0 and cells.size() >= 4 and far != Vector2i.ZERO:
		var gate_id := prefix + "/gate"
		var gate_dir := Vector2i.ZERO
		for d in DIRS:
			var n: Vector2i = far + d
			if occupied.has(n) and links.has(_edge_key(far, n)) and int(dist.get(n, 999)) < int(dist.get(far, 0)):
				gate_dir = d
		if gate_dir != Vector2i.ZERO and not DungeonFeature.is_done(gate_id):
			var gpos := _wall_spot(far_center, far_h, gate_dir, 0.0)
			var gate := POIBuilder.add_box(root, Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.25) if gate_dir.x == 0 else Vector3(0.25, DOOR_HEIGHT, DOOR_WIDTH),
				gpos + Vector3(0.0, DOOR_HEIGHT * 0.5, 0.0), Color(0.25, 0.25, 0.28))
			gate.name = "Gate"
		var lever_rooms: Array[Vector2i] = []
		for c in cells:
			if c != far and c != Vector2i.ZERO:
				lever_rooms.append(c)
		if not lever_rooms.is_empty():
			var lc: Vector2i = lever_rooms[rng.randi_range(0, lever_rooms.size() - 1)]
			var ld := Vector2i.ZERO
			for d in DIRS:
				if not links.has(_edge_key(lc, lc + d)) and not (has_secret and secret == lc + d):
					ld = d
					break
			if ld != Vector2i.ZERO:
				var lever := DungeonFeature.new()
				lever.kind = DungeonFeature.Kind.LEVER
				lever.save_id = gate_id
				lever.target = "Gate"
				lever.name = "Lever"
				root.add_child(lever)
				lever.position = _wall_spot(Vector3(lc.x * size, 0.0, lc.y * size), half[lc], ld, 0.4) + Vector3(0.0, 0.6, 0.0)

	# ---- the loose stone in front of the secret room, and a better chest inside it
	if has_secret:
		var sid := prefix + "/secret"
		var d := secret - secret_from
		var host_center := Vector3(secret_from.x * size, 0.0, secret_from.y * size)
		if not DungeonFeature.is_done(sid):
			var bpos := _wall_spot(host_center, half[secret_from], d, 0.0)
			var block := POIBuilder.add_box(root, Vector3(DOOR_WIDTH + 0.2, height, WALL_THICKNESS + 0.1) if d.x == 0 else Vector3(WALL_THICKNESS + 0.1, height, DOOR_WIDTH + 0.2),
				bpos + Vector3(0.0, height * 0.5, 0.0), wc)
			block.name = "SecretWall"
			var stone := DungeonFeature.new()
			stone.kind = DungeonFeature.Kind.SECRET
			stone.save_id = sid
			stone.target = "SecretWall"
			stone.name = "LooseStone"
			root.add_child(stone)
			stone.position = bpos - Vector3(d.x, 0.0, d.y) * 0.5 + Vector3(0.0, 1.0, 0.0)
		var sloot := chest_loot.duplicate()
		sloot.append_array(ItemCatalog.curve_loot(lmax, lmax + 3, 1.5))
		var schest := POIBuilder.make_chest("Hidden Chest", sloot, prefix + "/chest_secret", (dungeon_seed + 3301 + f) | 1)
		root.add_child(schest)
		schest.position = Vector3(secret.x * size, 0.35, secret.y * size)

	# ---- chests in rooms other than the start
	var chest_count := 0
	if cells.size() > 1:
		var rooms: Array[Vector2i] = cells.slice(1)
		for i in range(rooms.size() - 1, 0, -1):  # seeded shuffle
			var j := rng.randi_range(0, i)
			var tmp := rooms[i]
			rooms[i] = rooms[j]
			rooms[j] = tmp
		var per_floor := rng.randi_range(mini(data.chests_min, data.chests_max), maxi(data.chests_min, data.chests_max)) + cells.size() / 10
		chest_count = mini(per_floor, rooms.size())
		for i in chest_count:
			var r := rooms[i]
			var h: Vector2 = half[r]
			var spot := Vector3(r.x * size, 0.35, r.y * size) + Vector3(rng.randf_range(-0.5, 0.5) * h.x, 0.0, rng.randf_range(-0.5, 0.5) * h.y)
			var chest := POIBuilder.make_chest("Chest", chest_loot, "%s/chest_%d" % [prefix, i], (dungeon_seed + i * 104729 + f * 31) | 1)
			root.add_child(chest)
			chest.position = spot
			chest.rotation.y = rng.randf() * TAU
	var boss_chest_spot := far_center + Vector3(far_h.x * 0.55, 0.35, far_h.y * 0.55)
	if last and data.boss != null and far != Vector2i.ZERO:
		var boss_loot: Array[LootEntry] = data.loot_table.duplicate()
		boss_loot.append_array(ItemCatalog.curve_loot(lmax + 1, lmax + 4, 2.0))
		boss_loot.append_array(ItemCatalog.treasure_loot(lmax, lmax + 4, 2.5))
		boss_loot.append_array(ItemCatalog.tag_loot(PackedStringArray(RoomDecorator.THEMES.get(data.theme, {}).get("tags", [])), lmax + 4, 2.0))
		boss_loot.append(ItemCatalog.gold_loot(lmax + 4, 1.0))
		var boss_chest := POIBuilder.make_chest("Boss Chest", boss_loot, "dungeon/%s/chest_boss" % dungeon_id, (dungeon_seed + 7777) | 1)
		root.add_child(boss_chest)
		boss_chest.position = boss_chest_spot

	# ---- traps on the way (never in the first or the far room)
	if data.traps_from_level > 0 and level >= data.traps_from_level:
		var t := 0
		for c in cells:
			if c == Vector2i.ZERO or c == far or rng.randf() > 0.3:
				continue
			var tid := "%s/trap_%d" % [prefix, t]
			t += 1
			var trap := DungeonFeature.new()
			trap.kind = DungeonFeature.Kind.TRAP
			trap.save_id = tid
			trap.damage = 8.0 + level * 1.2
			trap.name = "Trap%d" % t
			root.add_child(trap)
			var tdir: Vector2i = DIRS[rng.randi_range(0, 3)]
			trap.position = Vector3(c.x * size, 0.0, c.y * size) + Vector3(tdir.x, 0.0, tdir.y) * minf(half[c].x, half[c].y) * 0.5

	# ---- furnish every room (after the chests and doors, so it leaves them room)
	for i in all_cells.size():
		var c: Vector2i = all_cells[i]
		var h: Vector2 = half[c]
		if h.x < 3.0:
			continue  # junctions stay bare
		var center := Vector3(c.x * size, 0.0, c.y * size)
		var doors: Array[Vector3] = []
		for d: Vector2i in openings[c]:
			doors.append(center + Vector3(d.x * h.x, 0.0, d.y * h.y))
		RoomDecorator.decorate(root, Rect2(center.x - h.x, center.z - h.y, h.x * 2.0, h.y * 2.0), data.theme, level,
			("%d|room|%d|%d" % [dungeon_seed, f, i]).hash(), "", "%s/r%d" % [prefix, i], doors, 0, 1, height)

	# ---- enemies. They have their own random stream, so adding or removing them never moves a chest.
	var enemy_count := 0
	var has_boss := false
	if cells.size() > 1 and (data.spawn_table != null or data.boss != null):
		var erng := RandomNumberGenerator.new()
		erng.seed = dungeon_seed ^ 0x5EED5 ^ (f * 7919)
		var n := 0
		for c in all_cells:
			if c == Vector2i.ZERO:
				continue
			var h: Vector2 = half[c]
			var groups := 0
			if data.spawn_table != null:
				groups = erng.randi_range(mini(data.enemies_per_room_min, data.enemies_per_room_max), maxi(data.enemies_per_room_min, data.enemies_per_room_max))
				if h.x > size * 0.4 and level >= 20:
					groups += 1  # big rooms deep down are busier
			if c == far and data.boss != null:
				groups = mini(groups, 1)  # the boss room is not crowded
			for g in groups:
				var group_level := erng.randi_range(lmin, lmax)
				for m in data.spawn_table.roll(erng, group_level):
					var key := "%s/e%d" % [prefix, n]
					n += 1
					var at := Vector3(c.x * size, 0.15, c.y * size) + Vector3(erng.randf_range(-0.45, 0.45) * h.x, 0.0, erng.randf_range(-0.45, 0.45) * h.y)
					var lvl := clampi(group_level + erng.randi_range(-1, 1), lmin, lmax + 1)
					if WorldState.has_record("kill/" + key):
						continue  # killed earlier: stays dead
					var own := RandomNumberGenerator.new()  # its own stream: skipping a dead one never changes the others
					own.seed = ("%d|%s" % [dungeon_seed, key]).hash()
					Population.spawn_enemy(m, lvl, root, at, own, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
					enemy_count += 1
			if c == far and data.boss != null:
				# the boss on the last floor, a mini-boss (the same kind, weaker) guarding the stairs above
				var boss_key := "dungeon/%s/boss" % dungeon_id if last else "%s/miniboss" % prefix
				if last:
					has_boss = true
				if not WorldState.has_record("kill/" + boss_key):
					var bat := Vector3(c.x * size, 0.15, c.y * size)
					var boss_rng := RandomNumberGenerator.new()
					boss_rng.seed = ("%d|%s" % [dungeon_seed, boss_key]).hash()
					var boss := Population.spawn_enemy(data.boss, lmax + (3 if last else 0), root, bat, boss_rng, {"key": boss_key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
					if not last:
						boss.display_name = "%s Guard" % data.boss.display_name
						boss.max_health *= 0.6
					else:
						boss.died.connect(func(_e: Enemy) -> void: _on_boss_died(dungeon_id, lmax + 3))
					enemy_count += 1

	var parts := PackedStringArray()
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	return {
		"root": root,
		"start": start,
		"start_yaw": start_yaw,
		"down_spot": down_spot,
		"rooms": cells.size(),
		"chests": chest_count,
		"enemies": enemy_count,
		"boss": has_boss,
		"floor": f,
		"floors": floors,
		"secret": has_secret,
		"cells": cells,
		"links": links,
		"signature": ";".join(parts) + "|" + str(links.size()) + "|f" + str(f),
	}


## The boss is dead: the place is cleared on the map, and that is worth player XP (a deed)
static func _on_boss_died(dungeon_id: String, level: int) -> void:
	Discovery.mark_cleared(dungeon_id)
	var tree := Engine.get_main_loop() as SceneTree
	var p := tree.get_first_node_in_group("player") if tree != null else null
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	if skills != null:
		skills.add_deed_xp(SkillDatabase.deed_xp(level, 3.0))


# Steps from the start room to every room, going through doorways only
static func _room_distances(cells: Array[Vector2i], links: Dictionary, occupied: Dictionary) -> Dictionary:
	var dist := {Vector2i.ZERO: 0}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if occupied.has(n) and links.has(_edge_key(c, n)) and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%d,%d>%d,%d" % [lo.x, lo.y, hi.x, hi.y]


# A point on the floor by the middle of a room's wall on side d, `inset` meters inside it
static func _wall_spot(center: Vector3, h: Vector2, d: Vector2i, inset: float) -> Vector3:
	return center + Vector3(d.x * (h.x - inset), 0.0, d.y * (h.y - inset))


# One wall of a room, with a doorway in the middle when it is open
static func _room_wall(root: Node3D, center: Vector3, h: Vector2, d: Vector2i, height: float, open: bool, color: Color) -> void:
	var along_x := d.x == 0  # a wall on a north/south side runs along X
	var length := (h.x if along_x else h.y) * 2.0 + WALL_THICKNESS
	var at := center + Vector3(d.x * (h.x + WALL_THICKNESS * 0.5), 0.0, d.y * (h.y + WALL_THICKNESS * 0.5))
	if not open:
		_wall_piece(root, at + Vector3(0.0, height * 0.5, 0.0), length, height, along_x, color)
		return
	var side := (length - DOOR_WIDTH) * 0.5
	var offset := DOOR_WIDTH * 0.5 + side * 0.5
	var axis := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	_wall_piece(root, at + axis * offset + Vector3(0.0, height * 0.5, 0.0), side, height, along_x, color)
	_wall_piece(root, at - axis * offset + Vector3(0.0, height * 0.5, 0.0), side, height, along_x, color)
	var lintel_h := height - DOOR_HEIGHT
	if lintel_h > 0.05:
		_wall_piece(root, at + Vector3(0.0, DOOR_HEIGHT + lintel_h * 0.5, 0.0), DOOR_WIDTH, lintel_h, along_x, color)


# The corridor from a room's doorway on side d to the edge of its cell (the neighbor's corridor
# meets it there)
static func _corridor(root: Node3D, center: Vector3, h: Vector2, d: Vector2i, size: float, height: float, wc: Color, fc: Color) -> void:
	var edge := (h.x if d.x != 0 else h.y) + WALL_THICKNESS
	var length := size * 0.5 - edge
	if length <= 0.02:
		return
	var mid := center + Vector3(d.x, 0.0, d.y) * (edge + length * 0.5)
	var w := DOOR_WIDTH + 0.4
	var ch := minf(height, DOOR_HEIGHT + 0.4)
	if d.x != 0:
		POIBuilder.add_box(root, Vector3(length, WALL_THICKNESS, w), mid + Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0), fc)
		POIBuilder.add_box(root, Vector3(length, WALL_THICKNESS, w), mid + Vector3(0.0, ch + WALL_THICKNESS * 0.5, 0.0), wc.darkened(0.2))
		for s in [-1.0, 1.0]:
			_wall_piece(root, mid + Vector3(0.0, ch * 0.5, s * (w * 0.5 + WALL_THICKNESS * 0.5)), length, ch, true, wc)
	else:
		POIBuilder.add_box(root, Vector3(w, WALL_THICKNESS, length), mid + Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0), fc)
		POIBuilder.add_box(root, Vector3(w, WALL_THICKNESS, length), mid + Vector3(0.0, ch + WALL_THICKNESS * 0.5, 0.0), wc.darkened(0.2))
		for s in [-1.0, 1.0]:
			_wall_piece(root, mid + Vector3(s * (w * 0.5 + WALL_THICKNESS * 0.5), ch * 0.5, 0.0), length, ch, false, wc)


static func _door_frame(root: Node3D, spot: Vector3, d: Vector2i, color: Color) -> void:
	var frame_size := Vector3(2.4, 3.0, 0.3) if d.x == 0 else Vector3(0.3, 3.0, 2.4)
	POIBuilder.add_box(root, frame_size, spot + Vector3(d.x, 0.0, d.y) * 0.55 + Vector3(0.0, 1.5, 0.0), color, 0.0, Vector3.ZERO, false)


static func _wall_piece(root: Node3D, pos: Vector3, length: float, height: float, along_x: bool, color: Color) -> void:
	var sz := Vector3(length, height, WALL_THICKNESS) if along_x else Vector3(WALL_THICKNESS, height, length)
	POIBuilder.add_box(root, sz, pos, color)
