class_name Population
extends RefCounted
## Puts enemies and NPCs into the world. Used by the world (garrisons of points of interest),
## by dungeons, and by the random encounter system, so all of them build creatures the same way.
##
## A creature made here remembers its death: its spawn_key goes into WorldState as "kill/<key>",
## so a cleared camp or dungeon stays cleared when the chunk or dungeon is loaded again (and
## across save files, WorldState is part of the save). Living ones are NOT saved: they are rebuilt
## from the world seed, so the same camp always has the same people in it. Corpses are saved.


## Builds one creature. `pos` is a world position, unless `parent` is not in the scene tree yet
## (a dungeon being built), then it is a position inside that parent.
## opts: "key" (String, makes the kill be remembered), "persist_mode" (Enemy.PersistMode)
static func spawn_enemy(data: EnemyData, level: int, parent: Node, pos: Vector3, rng: RandomNumberGenerator, opts: Dictionary = {}) -> Enemy:
	var e := Enemy.create()
	data.apply(e, level, rng)
	e.persist_mode = int(opts.get("persist_mode", Enemy.PersistMode.CORPSE_ONLY)) as Enemy.PersistMode
	e.spawn_key = String(opts.get("key", ""))
	e.rotation.y = rng.randf() * TAU
	var host := parent as Node3D
	if host != null and host.is_inside_tree():
		e.position = host.to_local(pos)  # set before entering the tree, see Enemy.spawn()
	else:
		e.position = pos
	parent.add_child(e)
	return e


## The creatures that stand around a point of interest. Same world seed = same creatures.
## Returns what it made (the caller frees them when the chunk unloads).
static func spawn_garrison(placed: PlacedPOI, map: WorldMap, parent: Node3D) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var poi := placed.poi
	if poi == null or poi.garrison == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = placed.seed_value ^ 0x6A77
	var zone := LevelCurve.zone_range(map, placed.position)
	var lmin := maxi(zone.x + poi.garrison_level_offset, 1)
	var lmax := maxi(zone.y + poi.garrison_level_offset, lmin)
	var radius := poi.garrison_radius if poi.garrison_radius > 0.0 else poi.footprint_radius * 0.6
	var groups := rng.randi_range(mini(poi.garrison_groups_min, poi.garrison_groups_max), maxi(poi.garrison_groups_min, poi.garrison_groups_max))
	var n := 0
	for g in groups:
		var group_level := rng.randi_range(lmin, lmax)
		var members := poi.garrison.roll(rng, group_level)
		var heading := rng.randf() * TAU
		var dist := rng.randf_range(0.25, 1.0) * radius
		for m in members:
			var key := "%s/g%d" % [placed.id, n]
			n += 1
			var ang := heading + rng.randf_range(-0.7, 0.7)
			var d := clampf(dist + rng.randf_range(-2.0, 2.0), 1.0, radius)
			var level := clampi(group_level + rng.randi_range(-1, 1), lmin, lmax + 1)
			var x := placed.position.x + cos(ang) * d
			var z := placed.position.z + sin(ang) * d
			if WorldState.has_record("kill/" + key):
				continue  # already killed in this game
			var y := map.get_height(x, z)
			var own := RandomNumberGenerator.new()  # its own stream: skipping a dead one never changes the others
			own.seed = ("%d|%s" % [placed.seed_value, key]).hash()
			var e := spawn_enemy(m, level, parent, Vector3(x, y + 0.6, z), own, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
			out.append(e)
	return out
