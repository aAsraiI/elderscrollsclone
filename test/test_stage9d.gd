extends SceneTree
## Headless tests for stage 9d (bigger dungeons, floors, gates, secrets, traps, new types).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage9d.gd

const D := "res://data/world/Dungeons/"

var passes := 0
var fails := 0
var world: Node3D


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
	world = Node3D.new()
	root.add_child(world)
	await frames(2)
	t_sizes()
	await t_features()
	await t_types()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _build(data: DungeonData, lvl: int, f: int = 0, id: String = "t") -> Dictionary:
	return DungeonBuilder.build(data, 1234, id, lvl, lvl + 2, f)


func t_sizes() -> void:
	print("-- size grows with level")
	WorldState.clear()
	var cave := load(D + "dark_cave.tres") as DungeonData
	var low := _build(cave, 3)
	var mid := _build(cave, 40)
	var high := _build(cave, 85)
	check("a low cave has one floor and few rooms", int(low["floors"]) == 1 and int(low["rooms"]) <= 12, "%d floors, %d rooms" % [low["floors"], low["rooms"]])
	check("a level 40 cave has 2 floors and more rooms", int(mid["floors"]) == 2 and int(mid["rooms"]) > int(low["rooms"]), "%d floors, %d rooms" % [mid["floors"], mid["rooms"]])
	check("a level 85 cave has 4 floors of 20+ rooms", int(high["floors"]) == 4 and int(high["rooms"]) >= 20, "%d floors, %d rooms" % [high["floors"], high["rooms"]])
	var total := 0
	for f in 4:
		var r := _build(cave, 85, f)
		total += int(r["rooms"])
		(r["root"] as Node3D).free()
	check("a late dungeon is massive: 80+ rooms over its floors", total >= 80, str(total))
	for r in [low, mid, high]:
		(r["root"] as Node3D).free()
	var t0 := Time.get_ticks_msec()
	var big := _build(cave, 95, 3)
	var ms := Time.get_ticks_msec() - t0
	check("building the biggest floor takes under 3 s", ms < 3000, "%d ms" % ms)
	(big["root"] as Node3D).free()


func t_features() -> void:
	print("-- floors, gates, secrets, traps")
	WorldState.clear()
	var crypt := load(D + "crypt.tres") as DungeonData
	var top := _build(crypt, 40, 0, "deep")
	var r0: Node3D = top["root"]
	check("floor 0 has the way out and stairs down", r0.get_node_or_null("Exit") != null and r0.get_node_or_null("StairsDown") != null)
	check("there is no boss on an upper floor", not bool(top["boss"]))
	var bottom := _build(crypt, 40, 1, "deep")
	var r1: Node3D = bottom["root"]
	check("the last floor has stairs up, the boss and a shortcut out", r1.get_node_or_null("StairsUp") != null and r1.get_node_or_null("Shortcut") != null and bool(bottom["boss"]))
	var gate := r0.get_node_or_null("Gate")
	var lever := r0.get_node_or_null("Lever") as DungeonFeature
	check("a gate blocks the far room, a lever opens it", gate != null and lever != null)
	if lever != null:
		world.add_child(r0)
		await frames(2)
		lever.interact(null)
		await frames(2)
		check("pulling the lever opens the gate", not is_instance_valid(gate) and DungeonFeature.is_done(lever.save_id))
		world.remove_child(r0)
		r0.free()
		var again := _build(crypt, 40, 0, "deep")
		check("an opened gate stays open", (again["root"] as Node3D).get_node_or_null("Gate") == null)
		(again["root"] as Node3D).free()
	else:
		r0.free()
	var with_secret := 0
	var with_traps := 0
	for s in 12:
		var r := DungeonBuilder.build(crypt, 1000 + s, "s%d" % s, 30, 32)
		var rt: Node3D = r["root"]
		if rt.get_node_or_null("LooseStone") != null:
			with_secret += 1
		for c in rt.get_children():
			if c is DungeonFeature and (c as DungeonFeature).kind == DungeonFeature.Kind.TRAP:
				with_traps += 1
				break
		rt.free()
	check("most floors hide a secret room", with_secret >= 4, str(with_secret))
	check("deeper dungeons have traps", with_traps >= 3, str(with_traps))
	var easy := _build(crypt, 1)
	var trap_free := true
	for c in (easy["root"] as Node3D).get_children():
		if c is DungeonFeature and (c as DungeonFeature).kind == DungeonFeature.Kind.TRAP:
			trap_free = false
	check("easy dungeons have no traps", trap_free)
	var decor := (easy["root"] as Node3D).find_children("Decor_*", "", false, false)
	check("dungeon rooms are furnished", decor.size() >= 4, str(decor.size()))
	(easy["root"] as Node3D).free()
	r1.free()


func t_types() -> void:
	print("-- dungeon types")
	for key in ["sewers", "abandoned_mine", "barrow", "fort_ruin", "ice_cavern", "ashen_temple", "sunken_vault"]:
		var d := load(D + key + ".tres") as DungeonData
		check("%s loads with enemies and a boss" % key, d != null and d.spawn_table != null and d.boss != null and d.theme != "")
		var r := DungeonBuilder.build(d, 77, key, 30, 34)
		var rt: Node3D = r["root"]
		world.add_child(rt)
		await frames(2)
		var enemies := rt.find_children("*", "Enemy", true, false)
		var items := rt.find_children("*", "WorldItem", true, false)
		check("%s has enemies and things to find" % key, enemies.size() > 0 and items.size() > 0, "%d enemies, %d items" % [enemies.size(), items.size()])
		rt.queue_free()
		await frames(1)
	var found := {}
	for b in ["ashlands", "frozen_crown", "coast", "badlands", "tundra"]:
		var biome := load("res://data/world/%s.tres" % b) as BiomeData
		for rule in biome.poi_rules:
			if rule.poi is DungeonEntrancePOIData:
				found[String((rule.poi as DungeonEntrancePOIData).dungeon.id)] = true
	check("the new biomes have the new dungeons", found.has("ashen_temple") and found.has("ice_cavern") and found.has("sunken_vault") and found.has("abandoned_mine") and found.has("barrow"), str(found.keys()))


func t_in_game() -> void:
	print("-- floors in the game")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var target: PlacedPOI = null
	for poi in wm.pois:
		var ent := poi.poi as DungeonEntrancePOIData
		if ent != null and not (ent is SitePOIData) and ent.dungeon != null and LevelCurve.place_level(wm.map, poi.position) + ent.dungeon.level_offset >= 25:
			target = poi
			break
	check("the realm has a dungeon of level 25+", target != null)
	if target == null:
		return
	wm.dungeons.fade_time = 0.0
	# a dungeon from an old save keeps the old many-floored layout (new ones are stitched, Alpha 1.13)
	WorldState.set_record("dungeon/%s/opened" % target.id, {"old": true})
	await wm.dungeons.enter(target.id, target.position, 0.0)
	await frames(5)
	check("you are on floor 1 of several", wm.dungeons.current_floor == 0 and wm.dungeons.floor_count >= 2, str(wm.dungeons.floor_count))
	var stairs := wm.dungeons.get_interior_root().get_node_or_null("StairsDown") as DungeonDoor
	check("there are stairs down", stairs != null)
	if stairs == null:
		return
	stairs.interact(null)
	await frames(10)
	check("the stairs take you down a floor", wm.dungeons.current_floor == 1 and wm.dungeons.is_inside())
	var saved := wm.dungeons.to_dict()
	check("the save remembers the floor", int(saved.get("floor", -1)) == 1)
	var up := wm.dungeons.get_interior_root().get_node_or_null("StairsUp") as DungeonDoor
	up.interact(null)
	await frames(10)
	var down_again := wm.dungeons.get_interior_root().get_node_or_null("StairsDown") as Node3D
	check("going up puts you by the stairs down", wm.dungeons.current_floor == 0 and down_again != null and p.global_position.distance_to(down_again.global_position) < 5.0, str(p.global_position.distance_to(down_again.global_position) if down_again != null else -1.0))
	DungeonBuilder._on_boss_died(target.id, 30)
	check("killing the boss marks the place cleared", Discovery.is_cleared(target.id))
