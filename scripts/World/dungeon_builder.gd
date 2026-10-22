class_name DungeonBuilder
extends RefCounted
## Generates the inside of a dungeon from a DungeonData and a seed: rooms on a grid joined by
## doorways (a random tree with a few extra loops), lit by one lamp per room, with chests.
## The same seed always gives the same dungeon. This is the first, simple generator: everything
## else about dungeons (enemies, traps, other layouts) can grow from here.
##
## Local space: the start room is centered on the origin, the exit door is in that room.

const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const WALL_THICKNESS := 0.6
const DOOR_WIDTH := 3.2
const DOOR_HEIGHT := 3.2


## Returns {"root": Node3D, "start": Vector3, "rooms": int, "chests": int, "enemies": int, "boss": bool,
## "cells", "links", "signature": String}
## dungeon_id is the entrance's stable id (it names the chests and the enemies so they can be saved).
## level_min / level_max: how hard the land around the entrance is (the biome's range).
static func build(data: DungeonData, dungeon_seed: int, dungeon_id: String, level_min: int = 1, level_max: int = 10) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = dungeon_seed
	var size := data.room_size
	var height := data.ceiling_height

	# ---- layout: grow a tree of rooms, then add a few loops
	var wanted := rng.randi_range(mini(data.min_rooms, data.max_rooms), maxi(data.min_rooms, data.max_rooms))
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var occupied := {Vector2i.ZERO: true}
	var links := {}  # edge key -> true
	var tries := 0
	while cells.size() < wanted and tries < 2000:
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

	var root := Node3D.new()
	root.name = "Dungeon"
	var walls_color := data.wall_color
	var floor_color := data.floor_color

	# ---- floors, ceilings, lamps
	for c in cells:
		var center := Vector3(c.x * size, 0.0, c.y * size)
		POIBuilder.add_box(root, Vector3(size + WALL_THICKNESS, WALL_THICKNESS, size + WALL_THICKNESS), center + Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0), floor_color)
		POIBuilder.add_box(root, Vector3(size + WALL_THICKNESS, WALL_THICKNESS, size + WALL_THICKNESS), center + Vector3(0.0, height + WALL_THICKNESS * 0.5, 0.0), walls_color.darkened(0.2))
		var lamp := OmniLight3D.new()
		lamp.light_color = data.light_color
		lamp.light_energy = data.light_energy
		lamp.omni_range = size * 1.25
		lamp.position = center + Vector3(0.0, height * 0.75, 0.0)
		root.add_child(lamp)

	# ---- walls: every edge of every room, drawn once, with a doorway where rooms are joined
	var drawn := {}
	for c in cells:
		for d in DIRS:
			var n: Vector2i = c + d
			var key := _edge_key(c, n)
			if drawn.has(key):
				continue
			drawn[key] = true
			var open: bool = occupied.has(n) and links.has(key)
			_wall(root, c, d, size, height, open, walls_color)

	# ---- exit door in the start room, against a wall that has no doorway in it
	var exit_dir := Vector2i(0, 1)
	var free_sides: Array[Vector2i] = []
	for d in DIRS:
		if not links.has(_edge_key(Vector2i.ZERO, d)):
			free_sides.append(d)
	if not free_sides.is_empty():
		exit_dir = free_sides[rng.randi_range(0, free_sides.size() - 1)]
	var exit_pos := Vector3(exit_dir.x, 0.0, exit_dir.y) * (size * 0.5 - 0.9)
	var door := DungeonDoor.new()
	door.name = "Exit"
	door.entrance_id = dungeon_id
	door.label = "Leave"
	door.is_exit = true
	root.add_child(door)
	door.position = exit_pos + Vector3(0.0, 1.3, 0.0)
	var frame_size := Vector3(2.4, 3.0, 0.3) if exit_dir.x == 0 else Vector3(0.3, 3.0, 2.4)
	POIBuilder.add_box(root, frame_size, Vector3(exit_dir.x, 0.0, exit_dir.y) * (size * 0.5 - 0.35) + Vector3(0.0, 1.5, 0.0), Color(0.35, 0.25, 0.15), 0.0, Vector3.ZERO, false)

	var lmin := maxi(level_min + data.level_offset, 1)
	var lmax := maxi(level_max + data.level_offset, lmin)
	var chest_loot: Array[LootEntry] = data.loot_table.duplicate()
	if data.curve_loot:
		chest_loot.append_array(ItemCatalog.curve_loot(lmin, lmax))
	chest_loot.append_array(ItemCatalog.treasure_loot(lmin, lmax))

	# ---- chests in rooms other than the start
	var chest_count := 0
	if cells.size() > 1:
		var rooms: Array[Vector2i] = cells.slice(1)
		for i in range(rooms.size() - 1, 0, -1):  # seeded shuffle
			var j := rng.randi_range(0, i)
			var tmp := rooms[i]
			rooms[i] = rooms[j]
			rooms[j] = tmp
		chest_count = mini(rng.randi_range(mini(data.chests_min, data.chests_max), maxi(data.chests_min, data.chests_max)), rooms.size())
		for i in chest_count:
			var r := rooms[i]
			var spot := Vector3(r.x * size, 0.35, r.y * size) + Vector3(rng.randf_range(-0.3, 0.3) * size, 0.0, rng.randf_range(-0.3, 0.3) * size)
			var chest := POIBuilder.make_chest("Chest", chest_loot, "dungeon/%s/chest_%d" % [dungeon_id, i], (dungeon_seed + i * 104729) | 1)
			root.add_child(chest)
			chest.position = spot
			chest.rotation.y = rng.randf() * TAU

	# ---- enemies. They have their own random stream, so adding or removing them never moves a chest.
	var enemy_count := 0
	var has_boss := false
	if cells.size() > 1 and (data.spawn_table != null or data.boss != null):
		var erng := RandomNumberGenerator.new()
		erng.seed = dungeon_seed ^ 0x5EED5
		var dist := _room_distances(cells, links, occupied)
		var far := Vector2i.ZERO
		var far_d := -1
		for c in cells:
			if int(dist.get(c, 0)) > far_d:
				far_d = int(dist.get(c, 0))
				far = c
		var n := 0
		for c in cells:
			if c == Vector2i.ZERO:
				continue
			var groups := 0
			if data.spawn_table != null:
				groups = erng.randi_range(mini(data.enemies_per_room_min, data.enemies_per_room_max), maxi(data.enemies_per_room_min, data.enemies_per_room_max))
			if c == far and data.boss != null:
				groups = mini(groups, 1)  # the boss room is not crowded
			for g in groups:
				var group_level := erng.randi_range(lmin, lmax)
				for m in data.spawn_table.roll(erng, group_level):
					var key := "dungeon/%s/e%d" % [dungeon_id, n]
					n += 1
					var at := Vector3(c.x * size, 0.15, c.y * size) + Vector3(erng.randf_range(-0.32, 0.32) * size, 0.0, erng.randf_range(-0.32, 0.32) * size)
					var level := clampi(group_level + erng.randi_range(-1, 1), lmin, lmax + 1)
					if WorldState.has_record("kill/" + key):
						continue  # killed earlier: stays dead
					var own := RandomNumberGenerator.new()  # its own stream: skipping a dead one never changes the others
					own.seed = ("%d|%s" % [dungeon_seed, key]).hash()
					Population.spawn_enemy(m, level, root, at, own, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
					enemy_count += 1
			if c == far and data.boss != null:
				has_boss = true
				var boss_key := "dungeon/%s/boss" % dungeon_id
				if not WorldState.has_record("kill/" + boss_key):
					var bat := Vector3(c.x * size, 0.15, c.y * size)
					var boss_rng := RandomNumberGenerator.new()
					boss_rng.seed = ("%d|%s" % [dungeon_seed, boss_key]).hash()
					Population.spawn_enemy(data.boss, lmax + 3, root, bat, boss_rng, {"key": boss_key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
					enemy_count += 1
				# a better chest for whoever gets that far
				var boss_loot: Array[LootEntry] = data.loot_table.duplicate()
				boss_loot.append_array(ItemCatalog.curve_loot(lmax + 1, lmax + 4, 2.0))
				boss_loot.append_array(ItemCatalog.treasure_loot(lmax, lmax + 4, 2.5))
				var boss_chest := POIBuilder.make_chest("Boss Chest", boss_loot, "dungeon/%s/chest_boss" % dungeon_id, (dungeon_seed + 7777) | 1)
				root.add_child(boss_chest)
				boss_chest.position = Vector3(c.x * size, 0.35, c.y * size) + Vector3(size * 0.28, 0.0, size * 0.28)

	var parts := PackedStringArray()
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	return {
		"root": root,
		"start": Vector3(0.0, 0.1, -size * 0.15),
		"rooms": cells.size(),
		"chests": chest_count,
		"enemies": enemy_count,
		"boss": has_boss,
		"cells": cells,
		"links": links,
		"signature": ";".join(parts) + "|" + str(links.size()),
	}


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


# One wall on the side `d` of room `c`. Overlaps its neighbors by the thickness so corners are closed.
static func _wall(root: Node3D, c: Vector2i, d: Vector2i, size: float, height: float, open: bool, color: Color) -> void:
	var center := Vector3(c.x * size, 0.0, c.y * size) + Vector3(d.x, 0.0, d.y) * size * 0.5
	var along_x := d.x == 0  # a wall on a north/south edge runs along X
	var length := size + WALL_THICKNESS
	if not open:
		_wall_piece(root, center + Vector3(0.0, height * 0.5, 0.0), length, height, along_x, color)
		return
	var side := (length - DOOR_WIDTH) * 0.5
	var offset := DOOR_WIDTH * 0.5 + side * 0.5
	var axis := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	_wall_piece(root, center + axis * offset + Vector3(0.0, height * 0.5, 0.0), side, height, along_x, color)
	_wall_piece(root, center - axis * offset + Vector3(0.0, height * 0.5, 0.0), side, height, along_x, color)
	var lintel_h := height - DOOR_HEIGHT
	if lintel_h > 0.05:
		_wall_piece(root, center + Vector3(0.0, DOOR_HEIGHT + lintel_h * 0.5, 0.0), DOOR_WIDTH, lintel_h, along_x, color)


static func _wall_piece(root: Node3D, pos: Vector3, length: float, height: float, along_x: bool, color: Color) -> void:
	var sz := Vector3(length, height, WALL_THICKNESS) if along_x else Vector3(WALL_THICKNESS, height, length)
	POIBuilder.add_box(root, sz, pos, color)
