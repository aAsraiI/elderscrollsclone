@tool
class_name RoomFiller
extends RefCounted
## Fills a built room from its spawn points (SpawnSocket), the same way every visit:
##   chests: a chest with loot for the level (the boss room's is "dungeon/<id>/chest_boss", where
##     quests put their items); loot: a satchel with a little in it
##   enemies: a group from the dungeon's spawn table; boss: the dungeon's boss
##   captives, quest items
## Furniture is never picked here (Alpha 1.20): it is part of the room's scene, placed by hand (props and
## builder-kit pieces), so a room looks the same wherever it is used; only what is in it changes. The
## old furniture spawn points were baked into the scenes once (tools/bake_room_props.gd) and do nothing.
## What a socket gets comes from a seed made of the room's id and the socket's name, so taking things or
## killing things never changes what the other sockets hold. Killed enemies stay dead
## (WorldState "kill/<key>"); chests remember their contents by their save id.

## What a dungeon passes along: {"data": DungeonData, "dungeon_id", "level_min", "level_max",
## "density", "seed"}
static func fill(room: RoomModule, ctx: Dictionary) -> Dictionary:
	var out := {"props": 0, "chests": 0, "enemies": 0, "boss": false}
	var room_id := String(room.get_meta("room_id", room.name))
	var data: DungeonData = ctx.get("data")
	var lmin := int(ctx.get("level_min", 1))
	var lmax := int(ctx.get("level_max", lmin + 3))
	var density := float(ctx.get("density", 1.0))
	var socks := room.sockets()
	var furniture: Array[AABB] = []  # the room's own furniture, read before anything is spawned into it
	for s in socks:
		if s.kind in [SpawnSocket.Kind.CHEST, SpawnSocket.Kind.LOOT]:
			furniture = furniture_in(room)
			break
	for s in socks:
		if not s.kind in [SpawnSocket.Kind.CHEST, SpawnSocket.Kind.LOOT, SpawnSocket.Kind.ENEMY, SpawnSocket.Kind.BOSS, SpawnSocket.Kind.NPC, SpawnSocket.Kind.QUEST_ITEM]:
			continue  # furniture, lights, traps and patrols: the room's own (or InteriorFeatures / InteriorNav)
		var nudge := Vector3.ZERO  # a chest spot under a brazier or a table moves to the nearest free floor (1.23: the main quest's Codex was buried this way)
		if s.kind in [SpawnSocket.Kind.CHEST, SpawnSocket.Kind.LOOT]:
			var free := free_spot(furniture, room, s.position)
			if not free.is_finite():
				continue
			nudge = s.transform.basis.inverse() * (free - s.position)
		var key := "%s/%s" % [room_id, s.name]
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|%s" % [int(ctx.get("seed", 0)), key]).hash()
		var always := s.kind in [SpawnSocket.Kind.BOSS] or (s.kind == SpawnSocket.Kind.CHEST and s.tags.has("boss"))
		var boost := 1.6 if s.kind in [SpawnSocket.Kind.CHEST, SpawnSocket.Kind.LOOT] else 1.0  # dungeons hold plenty to find (1.16)
		if not always and rng.randf() > clampf(s.chance * density * boost, 0.0, 1.0):
			continue
		match s.kind:
			SpawnSocket.Kind.CHEST, SpawnSocket.Kind.LOOT:
				var boss_chest := s.tags.has("boss")
				if boss_chest and bool(ctx.get("boss_chest_done", false)):
					boss_chest = false  # one boss chest per dungeon; the other corners get ordinary ones
				if boss_chest:
					ctx["boss_chest_done"] = true
				var save_id := "dungeon/%s/chest_boss" % ctx.get("dungeon_id", "") if boss_chest else key
				var loot: Array[LootEntry] = []
				if data != null:
					loot.append_array(data.loot_table)
				var top := lmax + (4 if boss_chest else 1)
				loot.append_array(ItemCatalog.curve_loot(lmin, top, 2.0 if boss_chest else 1.0))
				loot.append(ItemCatalog.gold_loot(top, 1.0 if boss_chest else 0.7))
				var chest_name := "Boss Chest" if boss_chest else ("Satchel" if s.kind == SpawnSocket.Kind.LOOT else "Chest")
				var chest := POIBuilder.make_chest(chest_name, loot, save_id, absi(key.hash()) | 1)
				s.add_child(chest)
				chest.position = nudge + Vector3(0, 0.35, 0)
				var stand := s.position + s.transform.basis * nudge
				furniture.append(AABB(stand + Vector3(-0.5, 0.0, -0.35), Vector3(1.0, 0.8, 0.7)))  # the next chest does not land on this one
				if s.kind == SpawnSocket.Kind.LOOT:
					chest.scale = Vector3(0.5, 0.5, 0.5)
				out["chests"] += 1
			SpawnSocket.Kind.ENEMY:
				if data == null or data.spawn_table == null:
					continue
				var lvl := rng.randi_range(lmin, lmax)
				var group := data.spawn_table.roll(rng, lvl)
				var n := 0
				for m in group.slice(0, maxi(s.count, 1) + 1):
					var ekey := "%s/%d" % [key, n]
					n += 1
					if WorldState.has_record("kill/" + ekey):
						continue
					var own := RandomNumberGenerator.new()
					own.seed = ekey.hash()
					var at := s.position + Vector3(own.randf_range(-0.8, 0.8), 0.2, own.randf_range(-0.8, 0.8))
					Population.spawn_enemy(m, lvl, room, at, own, {"key": ekey, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
					out["enemies"] += 1
			SpawnSocket.Kind.BOSS:
				if data == null or data.boss == null:
					continue
				if bool(ctx.get("boss_done", false)):
					continue  # one boss per dungeon
				ctx["boss_done"] = true
				var bkey := "dungeon/%s/boss" % ctx.get("dungeon_id", "")
				out["boss"] = true
				if WorldState.has_record("kill/" + bkey):
					continue
				var boss := Population.spawn_enemy(data.boss, lmax + 3, room, s.position + Vector3(0, 0.2, 0), rng, {"key": bkey, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
				var did := String(ctx.get("dungeon_id", ""))
				boss.died.connect(func(_e: Enemy) -> void: DungeonBuilder._on_boss_died(did, lmax + 3))
				BossMechanics.attach(boss)  # 1.26: a trick of its own (raises the dead, regrows, brood, rage)
				out["enemies"] += 1
			SpawnSocket.Kind.NPC:
				# a prisoner in a dungeon's cells, now and then (not in a lord's cells: those are the law's)
				if s.tags.has("captive") and data != null and String(ctx.get("dungeon_id", "")) != "":
					if Captive.make(s, room, key, rng, lmax) != null:
						out["captives"] = int(out.get("captives", 0)) + 1
			SpawnSocket.Kind.QUEST_ITEM:
				# a quest's item waiting here: the record "quest_item/<dungeon id>" {"item": path} puts it at
				# the dungeon's first quest-item spot (hand-made rooms place these; else the boss chest holds it)
				var want := WorldState.get_record("quest_item/%s" % ctx.get("dungeon_id", ""))
				if not want.is_empty() and not bool(ctx.get("quest_item_done", false)) and not WorldState.has_record(WorldItem.taken_key(key)):
					ctx["quest_item_done"] = true  # the first quest-item spot in the dungeon
					var item := load(String(want["item"])) as ItemData if ResourceLoader.exists(String(want.get("item", ""))) else null
					if item != null:
						WorldItem.place(item, 1, room, s.position + Vector3(0, 0.4, 0), key, "")
						out["quest_items"] = int(out.get("quest_items", 0)) + 1
	return out


## Footprints (room space) of the room's furniture: direct children that are not spawn points,
## markers or the room's shell, and are the size of a piece of furniture (under 3 m across)
static func furniture_in(room: RoomModule) -> Array[AABB]:
	var out: Array[AABB] = []
	for c in room.get_children():
		if c is SpawnSocket:
			for chest in (c as Node).get_children():  # a chest already standing at a spawn point
				if chest is StaticBody3D:
					out.append((c as Node3D).transform * ((chest as Node3D).transform * AABB(Vector3(-0.5, -0.35, -0.3), Vector3(1.0, 0.8, 0.6))))
			continue
		if not (c is Node3D) or c is Marker3D or c is CharacterBody3D or c is RigidBody3D or (c as Node).is_in_group("interior_geometry"):
			continue
		var b := ModelLibrary.bounds(c as Node3D)
		if b.size == Vector3.ZERO:
			b = _shape_bounds(c as Node3D)  # builder-kit pieces make their model in _ready (not yet in the tree)
		if b.size == Vector3.ZERO or b.size.x > 3.0 or b.size.z > 3.0 or b.size.y < 0.3:
			continue  # walls, floors, rugs and decals
		out.append((c as Node3D).transform * b)
	return out


## Would a chest at this spot (room space) stand inside a piece of furniture?
static func blocked(furniture: Array[AABB], at: Vector3) -> bool:
	var chest := AABB(at + Vector3(-0.35, 0.1, -0.25), Vector3(0.7, 0.5, 0.5))
	for f in furniture:
		if f.intersects(chest):
			return true
	return false


## Where a chest meant for this spot can stand: the spot itself if it is clear, else the nearest
## clear floor within 2.5 m that is still inside the room (INF = nowhere)
static func free_spot(furniture: Array[AABB], room: RoomModule, at: Vector3) -> Vector3:
	if not blocked(furniture, at):
		return at
	var inner := room.bounds().grow(-0.8)
	for r in [0.7, 1.1, 1.5, 2.0, 2.5]:
		for i in 12:
			var a := float(i) / 12.0 * TAU
			var p := Vector3(at.x + cos(a) * r, 0.0 if at.y < 0.6 else at.y, at.z + sin(a) * r)
			if inner.has_point(Vector3(p.x, inner.position.y + 0.1, p.z)) and not blocked(furniture, p):
				return p
	return Vector3.INF


static func _shape_bounds(node: Node3D) -> AABB:
	var out := AABB()
	for cs in node.find_children("*", "CollisionShape3D", true, false):
		var shape := (cs as CollisionShape3D).shape
		if shape == null:
			continue
		var local := ModelLibrary.relative_transform(node, cs as Node3D) * shape.get_debug_mesh().get_aabb()
		out = local if out.size == Vector3.ZERO else out.merge(local)
	return out
