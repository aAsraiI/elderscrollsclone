@tool
class_name RoomFiller
extends RefCounted
## Fills a built room from its spawn points (SpawnSocket), the same way every visit:
##   furniture, decorations, wall decorations, ceiling things and lights: a prop from PropLibrary
##     that fits the socket's tags, the room's theme and wealth (two props never overlap)
##   chests: a chest with loot for the level (the boss room's is "dungeon/<id>/chest_boss", where
##     quests put their items); loot: a satchel with a little in it
##   enemies: a group from the dungeon's spawn table; boss: the dungeon's boss
## What a socket gets comes from a seed made of the room's id and the socket's name, so taking
## things or killing things never changes what the other sockets hold. Killed enemies stay dead
## (WorldState "kill/<key>"); chests remember their contents by their save id.

## What a dungeon passes along: {"data": DungeonData, "dungeon_id", "level_min", "level_max",
## "density", "seed"}
static func fill(room: RoomModule, ctx: Dictionary) -> Dictionary:
	var out := {"props": 0, "chests": 0, "enemies": 0, "boss": false}
	var room_id := String(room.get_meta("room_id", room.name))
	var theme := String(room.themes[0]) if not room.themes.is_empty() else "fort"
	var data: DungeonData = ctx.get("data")
	var lmin := int(ctx.get("level_min", 1))
	var lmax := int(ctx.get("level_max", lmin + 3))
	var density := float(ctx.get("density", 1.0))
	var taken: Array = []  # [position, radius] of props already placed
	for s in room.sockets():
		var key := "%s/%s" % [room_id, s.name]
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|%s" % [int(ctx.get("seed", 0)), key]).hash()
		var always := s.kind in [SpawnSocket.Kind.BOSS] or (s.kind == SpawnSocket.Kind.CHEST and s.tags.has("boss"))
		if not always and rng.randf() > clampf(s.chance * density, 0.0, 1.0):
			continue
		if bool(ctx.get("props_only", false)) and s.kind in [SpawnSocket.Kind.CHEST, SpawnSocket.Kind.LOOT, SpawnSocket.Kind.ENEMY, SpawnSocket.Kind.BOSS]:
			continue  # the editor preview: furniture only
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
				chest.position = Vector3(0, 0.35, 0)
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
				var bkey := "dungeon/%s/boss" % ctx.get("dungeon_id", "")
				out["boss"] = true
				if WorldState.has_record("kill/" + bkey):
					continue
				var boss := Population.spawn_enemy(data.boss, lmax + 3, room, s.position + Vector3(0, 0.2, 0), rng, {"key": bkey, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
				var did := String(ctx.get("dungeon_id", ""))
				boss.died.connect(func(_e: Enemy) -> void: DungeonBuilder._on_boss_died(did, lmax + 3))
				out["enemies"] += 1
			SpawnSocket.Kind.TRAP, SpawnSocket.Kind.NPC, SpawnSocket.Kind.QUEST_ITEM, SpawnSocket.Kind.PATROL:
				pass  # filled by the features and quest systems (1.13.8, 1.13.13)
			_:
				var kind_name := String(SpawnSocket.Kind.keys()[s.kind])
				var e := PropLibrary.pick(kind_name, s.tags, theme, room.wealth, rng)
				if e == null and not s.tags.is_empty():
					e = PropLibrary.pick(kind_name, PackedStringArray(), theme, room.wealth, rng)
				if e == null:
					continue
				var at := s.position
				if taken.any(func(t: Array) -> bool: return Vector2(at.x - t[0].x, at.z - t[0].z).length() < e.radius + float(t[1]) and absf(at.y - t[0].y) < 1.5):
					continue
				var prop := (load(e.path) as PackedScene).instantiate() as Node3D
				room.add_child(prop)
				prop.transform = s.transform
				if s.kind != SpawnSocket.Kind.WALL_DECORATION and e.snap == InteriorProp.Snap.FLOOR and not s.tags.has("tabletop"):
					prop.rotate_y(rng.randf_range(-0.15, 0.15))  # never quite straight
				taken.append([at, e.radius])
				out["props"] += 1
	return out
