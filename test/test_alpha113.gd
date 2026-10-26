extends SceneTree
## Headless tests for Alpha 1.13 (interiors): room modules, props, the stitcher and recipes.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha113.gd

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
		await physics_frame


func _run() -> void:
	await process_frame
	t_modules()
	t_props()
	t_stitch()
	await t_build()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- 1.13.1 modules

func t_modules() -> void:
	print("-- room modules")
	var all := ModuleLibrary.all()
	check("room modules are found (%d)" % all.size(), all.size() >= 100)
	var themes := {}
	for e in all:
		for t in e.themes:
			themes[t] = true
	check("every theme has rooms", ["fort", "crypt", "cave", "mine", "sewer", "ruin", "lair"].all(func(t: String) -> bool: return themes.has(t)), str(themes.keys()))
	var probs := PackedStringArray()
	var no_sockets := 0
	for e in all:
		var room := (load(e.path) as PackedScene).instantiate() as RoomModule
		probs.append_array(room.problems())
		if room.sockets().is_empty() and room.role != RoomModule.Role.STAIRS:
			no_sockets += 1
		room.free()
	check("the module checker finds nothing wrong", probs.is_empty(), "\n".join(probs.slice(0, 8)))
	check("rooms have spawn points", no_sockets <= 2, str(no_sockets))
	for theme in ["fort", "crypt", "cave"]:
		check("%s has an entrance, corridors, rooms, stairs and a boss room" % theme, [RoomModule.Role.ENTRANCE, RoomModule.Role.CORRIDOR, RoomModule.Role.ROOM, RoomModule.Role.STAIRS, RoomModule.Role.BOSS].all(func(r: int) -> bool: return not ModuleLibrary.of(theme, r).is_empty()))
	var fort_kinds := {}
	for e in ModuleLibrary.of("fort"):
		fort_kinds[e.kind] = int(fort_kinds.get(e.kind, 0)) + 1
	check("a fort has barracks, a war room, a kitchen... each in two versions", ["barracks", "war_room", "kitchen", "mess_hall", "armory", "cells"].all(func(k: String) -> bool: return int(fort_kinds.get(k, 0)) >= 2), str(fort_kinds))
	check("templates exist to copy", ResourceLoader.exists(ModuleLibrary.DIR + "templates/room.tscn") and ResourceLoader.exists(ModuleLibrary.DIR + "templates/corridor.tscn"))


# ---------------------------------------------------------------- 1.13.2 props

func t_props() -> void:
	print("-- props")
	var dir := "res://scenes/interiors/props/"
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".tscn"))
	check("a prop library (%d props)" % files.size(), files.size() >= 45)
	var bad := 0
	var lights := 0
	for f in files:
		var p := (load(dir + f) as PackedScene).instantiate() as InteriorProp
		if p == null or p.tags.is_empty():
			bad += 1
		elif p.get_node_or_null("Light") != null:
			lights += 1
		if p != null:
			p.free()
	check("every prop says what it is", bad == 0, str(bad))
	check("light props carry a light", lights >= 6, str(lights))
	check("props share their materials", ResourceLoader.exists(InteriorKit.MAT_DIR + "stone.tres") and ResourceLoader.exists(InteriorKit.MAT_DIR + "wood.tres"))


# ---------------------------------------------------------------- 1.13.4 / 1.13.5 the stitcher

func t_stitch() -> void:
	print("-- the stitcher")
	var recipes := Array(DirAccess.get_files_at("res://data/interiors/recipes/")).filter(func(f: String) -> bool: return f.ends_with(".tres"))
	check("recipes for every dungeon type (%d)" % recipes.size(), recipes.size() >= 8)
	for f in recipes:
		var r := load("res://data/interiors/recipes/" + f) as DungeonRecipe
		var made := 0
		var short := 0
		var no_boss := 0
		var missing := 0
		var overlaps := 0
		var floors_ok := 0
		var t0 := Time.get_ticks_msec()
		for seed_value in 30:
			var lvl := 1 + seed_value * 3
			var plan := DungeonAssembler.plan(r, seed_value * 7919 + 13, lvl)
			made += 1
			if plan._room_count() < int(r.rooms_for(lvl) * 0.7):
				short += 1
			if r.boss and not plan.placed.any(func(p: DungeonAssembler.Placed) -> bool: return p.entry.role == RoomModule.Role.BOSS):
				no_boss += 1
			var kinds := {}
			for p in plan.placed:
				kinds[p.entry.kind] = true
			for k in r.required:
				if not kinds.has(k):
					missing += 1
			var seen := {}
			for p in plan.placed:
				for c in p.cells:
					if seen.has(c):
						overlaps += 1
					seen[c] = true
			var ys := {}
			for c in seen:
				ys[(c as Vector3i).y] = true
			if ys.size() > 1:
				floors_ok += 1
		var ms := Time.get_ticks_msec() - t0
		var name: String = String(f).get_basename()
		check("%s: 30 dungeons, no overlaps" % name, overlaps == 0, str(overlaps))
		check("%s: big enough (%d short)" % [name, short], short <= 3)
		check("%s: always a boss room (%d without)" % [name, no_boss], no_boss <= 1)
		check("%s: the rooms it must have (%d missing)" % [name, missing], missing <= 3)
		if r.extra_floors > 0:
			check("%s: more than one floor (%d of 30)" % [name, floors_ok], floors_ok >= 10)
		check("%s: planned quickly (%d ms for 30)" % [name, ms], ms < 6000)
	var r := load("res://data/interiors/recipes/fort.tres") as DungeonRecipe
	var a := DungeonAssembler.plan(r, 42, 20)
	var b := DungeonAssembler.plan(r, 42, 20)
	check("the same seed gives the same dungeon", a.summary() == b.summary() and a.placed.map(func(p: DungeonAssembler.Placed) -> String: return p.entry.path) == b.placed.map(func(p: DungeonAssembler.Placed) -> String: return p.entry.path))
	var c := DungeonAssembler.plan(r, 43, 20)
	check("another seed gives another", c.placed.map(func(p: DungeonAssembler.Placed) -> String: return p.entry.path) != a.placed.map(func(p: DungeonAssembler.Placed) -> String: return p.entry.path))
	var lo := DungeonAssembler.plan(r, 5, 1)
	var hi := DungeonAssembler.plan(r, 5, 60)
	check("higher levels make bigger dungeons (%d vs %d)" % [lo._room_count(), hi._room_count()], hi._room_count() > lo._room_count())


# ---------------------------------------------------------------- in the game

func t_in_game() -> void:
	print("-- a stitched dungeon in the game")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(90)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", wm != null and p != null)
	if wm == null:
		return
	var entrance: PlacedPOI = null
	for poi in wm.pois:
		var e := poi.poi as DungeonEntrancePOIData
		if e != null and e.dungeon != null and e.dungeon.recipe != null and e.dungeon.boss != null and (entrance == null or poi.position.distance_to(p.global_position) < entrance.position.distance_to(p.global_position)):
			entrance = poi
	check("dungeons have recipes", entrance != null)
	if entrance == null:
		return
	var outside := entrance.position + Vector3(0, 0, -6)
	wm.ensure_area_loaded(outside, 2)
	p.global_position = Vector3(outside.x, wm.get_height_at(outside.x, outside.z) + 2.0, outside.z)
	await frames(30)
	var t0 := Time.get_ticks_msec()
	var ok: bool = await wm.dungeons.enter(entrance.id, outside, 0.0)
	var ms := Time.get_ticks_msec() - t0
	check("entering builds it", ok and wm.dungeons.is_inside(), str(ms))
	await frames(60)
	var root := wm.dungeons.get_interior_root()
	var rooms := root.find_children("*", "RoomModule", true, false) if root != null else []
	check("from room modules (%d rooms)" % rooms.size(), rooms.size() >= 6)
	check("filled with props", root.find_children("*", "InteriorProp", true, false).size() >= 20, str(root.find_children("*", "InteriorProp", true, false).size()))
	var enemies := get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return root.is_ancestor_of(e))
	check("with enemies (%d)" % enemies.size(), enemies.size() >= 3)
	var boss_chest := root.find_children("*", "ContainerComponent", true, false).filter(func(c: Node) -> bool: return (c as ContainerComponent).save_id == "dungeon/%s/chest_boss" % entrance.id)
	check("the boss chest keeps the name quests look for", boss_chest.size() == 1)
	check("the player stands inside, not falling", p.global_position.y > DungeonManager.DUNGEON_Y - 30.0 and absf(p.velocity.y) < 15.0, str(p.global_position))
	check("a way out", root.find_children("Exit", "", true, false).filter(func(n: Node) -> bool: return n is DungeonDoor).size() == 1)
	var enemy_keys := enemies.map(func(e: Enemy) -> String: return e.spawn_key)
	await wm.dungeons.exit()
	await frames(30)
	check("leaving brings you back out", not wm.dungeons.is_inside())
	await wm.dungeons.enter(entrance.id, outside, 0.0)
	await frames(40)
	var again := get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return wm.dungeons.get_interior_root().is_ancestor_of(e)).map(func(e: Enemy) -> String: return e.spawn_key)
	enemy_keys.sort()
	again.sort()
	check("the same dungeon every visit", enemy_keys == again)
	await wm.dungeons.exit()
	await frames(20)
	await t_climb(wm, p)


# The player can climb a ladder room and walk up a stair room
func t_climb(wm: WorldManager, p: CharacterBody3D) -> void:
	print("-- ladders and stairs")
	for file in ["fort/stairs_ladder", "fort/stairs_straight"]:
		var room := (load(ModuleLibrary.DIR + file + ".tscn") as PackedScene).instantiate() as RoomModule
		wm.add_child(room)
		room.global_position = p.global_position + Vector3(0, 300, 0)
		await frames(5)
		var start := room.global_position + Vector3(0, 0.3, -room.bounds().size.z * 0.5 + 1.5)
		p.global_position = start
		p.velocity = Vector3.ZERO
		p.rotation.y = PI  # face +Z, into the room
		await frames(10)
		Input.action_press("move_forward")
		var rose := 0.0
		for k in 360:
			await physics_frame
			rose = maxf(rose, p.global_position.y - room.global_position.y)
			if rose > RoomModule.LEVEL - 0.3:
				break
		Input.action_release("move_forward")
		check("%s: you get up to the next floor (%.1f m)" % [file.get_file(), rose], rose > RoomModule.LEVEL - 1.0, str(p.global_position - room.global_position))
		room.queue_free()
		await frames(3)


func t_build() -> void:
	print("-- building one")
	var r := load("res://data/interiors/recipes/fort.tres") as DungeonRecipe
	var plan := DungeonAssembler.plan(r, 1234, 25)
	var root := plan.build("test_fort")
	get_root().add_child(root)
	await frames(2)
	var rooms := root.get_children().filter(func(n: Node) -> bool: return n is RoomModule)
	check("every planned room is built (%d)" % rooms.size(), rooms.size() == plan.placed.size())
	check("rooms have stable ids", rooms.all(func(n: Node) -> bool: return String(n.get_meta("room_id", "")).begins_with("test_fort/r")))
	var open := plan._open_doors().size()
	var caps := root.find_children("Cap_*", "", true, false).size()
	check("every doorway nobody joined is capped (%d)" % caps, caps == open, "%d open, %d caps" % [open, caps])
	# joined doorways meet: same spot, facing each other
	var bad := 0
	for l: Array in plan.links:
		var da := plan.door_world(plan.placed[l[0]], l[1])
		var db := plan.door_world(plan.placed[l[2]], l[3])
		if Vector3(da["pos"]).distance_to(db["pos"]) > 0.05 or Vector3(da["out"]).dot(db["out"]) > -0.99:
			bad += 1
	check("joined doorways meet face to face", bad == 0, str(bad))
	root.queue_free()
