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
	t_houses()
	t_handmade()
	await t_nav()
	await t_integration()
	t_qa()
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
	await t_atmosphere(wm, p, root)
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
	await t_features(wm, p)
	await t_house_in_game(wm, p)


func t_features(wm: WorldManager, p: CharacterBody3D) -> void:
	print("-- keys, gates, traps, secrets, puzzles")
	var data := load("res://data/world/Dungeons/fort_ruin.tres") as DungeonData
	var totals := {}
	var tested := false
	for s in 12:
		var res := StitchedInterior.build(data, 900 + s, "feat%d" % s, 30, 34)
		var root: Node3D = res["root"]
		wm.add_child(root)
		root.global_position = p.global_position + Vector3(0, 400 + s * 30, 0)
		await frames(2)
		for k in res["features"]:
			totals[k] = int(totals.get(k, 0)) + int(res["features"][k])
		if not tested and int(res["features"]["locked"]) > 0 and int(res["features"]["gates"]) > 0:
			tested = true
			var inv := p.get_node("Inventory") as Inventory
			var door: InteriorDoor = null
			var gate: InteriorDoor = null
			for d in root.find_children("*", "", true, false):
				if d is InteriorDoor:
					if (d as InteriorDoor).is_gate and d.name == "Gate":
						gate = d
					elif not (d as InteriorDoor).is_gate:
						door = d
			check("a locked door before the boss", door != null)
			var key := door.get_key()
			var holder: ContainerComponent = null
			for c in root.find_children("*", "ContainerComponent", true, false):
				if (c as ContainerComponent).inventory.has_item(key):
					holder = c
			check("its key is in a chest", holder != null)
			var boss_room := root.get_children().filter(func(n: Node) -> bool: return n is RoomModule and (n as RoomModule).role == RoomModule.Role.BOSS)
			check("not behind the door it opens", holder != null and not boss_room.any(func(b: Node) -> bool: return b.is_ancestor_of(holder)))
			var picks := 0
			for st in inv.stacks:
				if String(st.item.id) == "lockpick":
					picks += st.count
			inv.add_item(key)
			door.interact(inv)
			await frames(2)
			check("the key opens it, and it stays open", not is_instance_valid(door) and WorldState.has_record("door/feat%d/door_boss" % s))
			var lever: DungeonFeature = root.get_node_or_null("Lever")
			check("a gate and its lever", gate != null and lever != null)
			if lever != null:
				lever.interact(inv)
				await frames(2)
				check("the lever opens the gate", not is_instance_valid(gate))
		root.queue_free()
		await frames(2)
	check("traps at high levels (%d)" % totals.get("traps", 0), int(totals.get("traps", 0)) > 0)
	check("secret rooms (%d in 12)" % totals.get("secret", 0), int(totals.get("secret", 0)) >= 3)
	check("lever puzzles (%d)" % totals.get("puzzles", 0), int(totals.get("puzzles", 0)) >= 1)
	check("a shortcut out of every boss room", int(totals.get("shortcut", 0)) == 12)
	# a puzzle, solved
	var puzzle := InteriorHazards.LeverPuzzle.new()
	puzzle.save_id = "puzzle_test"
	puzzle.order = [2, 0, 1]
	puzzle.gate_name = "Vault"
	var room := Node3D.new()
	wm.add_child(room)
	room.add_child(puzzle)
	var vault := Node3D.new()
	vault.name = "Vault"
	room.add_child(vault)
	puzzle.lever_pulled(0)
	check("the wrong lever resets the puzzle", puzzle.pulled.is_empty())
	for i in [2, 0, 1]:
		puzzle.lever_pulled(i)
	await frames(2)
	check("the right order opens the vault", not is_instance_valid(vault) and WorldState.has_record("puzzle_test"))
	room.queue_free()


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


# ---------------------------------------------------------------- 1.13.9 town interiors

func t_houses() -> void:
	print("-- town interiors from scenes")
	var mods := InteriorBuilder.house_modules()
	var kinds := {}
	for m: Array in mods:
		kinds[m[1]] = true
	check("building interior scenes are found (%d)" % mods.size(), mods.size() >= 15)
	check("every kind has one", ["house", "farm", "manor", "shop", "smithy", "inn", "temple", "guild", "seat"].all(func(k: String) -> bool: return kinds.has(k)), str(kinds.keys()))
	var used := {}
	var bad := PackedStringArray()
	for kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM, BuildingPlot.Kind.SHOP, BuildingPlot.Kind.SMITHY, BuildingPlot.Kind.INN, BuildingPlot.Kind.TEMPLE, BuildingPlot.Kind.GUILD_HALL, BuildingPlot.Kind.SEAT]:
		for i in 12:
			var b := BuildingPlot.new()
			b.id = "test_town/b%d_%d" % [kind, i]
			b.kind = kind
			b.display_name = "Test"
			b.owner_name = "Anna Smith"
			b.trade = "alchemy"
			b.guild = "mages"
			b.seat_type = ["keep", "castle", "reeve"][i % 3]
			b.town_name = "Test"
			b.town_id = "test_town"
			b.size = Vector3(6.0 + (i % 3) * 3.0, 3.4, 6.0 + (i % 2) * 3.0)
			var r := InteriorBuilder.build(b, 1000 + i * 7, 5, 1)
			var root := r["root"] as Node3D
			var path := String(root.get_meta("module", ""))
			used[path.get_file()] = true
			var spots: Dictionary = r["spots"]
			var beds: Array = spots["beds"]
			var chest := root.find_children("*", "ContainerComponent", true, false).filter(func(c: Node) -> bool: return (c as ContainerComponent).save_id == "building/%s/chest_0" % b.id)
			var exits := root.get_children().filter(func(n: Node) -> bool: return n is DungeonDoor)
			var props := root.get_children().filter(func(n: Node) -> bool: return n is InteriorProp).size()
			var why := ""
			if path == "":
				why = "no scene"
			elif beds.is_empty():
				why = "no bed"
			elif chest.size() != 1:
				why = "no chest_0"
			elif exits.size() != 1:
				why = "no way out"
			elif props < 4:
				why = "%d props" % props
			elif kind == BuildingPlot.Kind.INN and root.get_children().filter(func(n: Node) -> bool: return n is NoticeBoard).size() != 1:
				why = "no notice board"
			elif kind == BuildingPlot.Kind.SMITHY and root.get_children().filter(func(n: Node) -> bool: return n is CraftingStation).size() < 5:
				why = "missing stations"
			elif kind == BuildingPlot.Kind.SHOP and root.get_children().filter(func(n: Node) -> bool: return n is CraftingStation).size() < 1:
				why = "no alchemy lab"
			elif kind == BuildingPlot.Kind.TEMPLE and root.get_children().filter(func(n: Node) -> bool: return n is RestSpot and (n as RestSpot).kind == "shrine").size() != 1:
				why = "no shrine"
			elif kind == BuildingPlot.Kind.GUILD_HALL and root.get_children().filter(func(n: Node) -> bool: return n is CraftingStation).size() < 3:
				why = "no spell altar, enchanter and lab"
			elif kind == BuildingPlot.Kind.SEAT and root.get_children().filter(func(n: Node) -> bool: return n is BountyBoard).size() != 1:
				why = "no bounty board"
			elif kind == BuildingPlot.Kind.SEAT and b.seat_type != "reeve" and root.find_children("Cell*", "Marker3D", false, false).size() < 3:
				why = "no cells below"
			# every bed behind a wall or upstairs has its way there, and the way ends near the bed
			for bed: Vector3 in beds:
				var rt := InteriorBuilder.route(spots, spots["exit"], bed)
				if rt[-1] != bed:
					why = "route doesn't end at the bed"
				if bed.y > 1.0 and rt.size() < 3:
					why = "an upstairs bed with no way up"
			if why != "":
				bad.append("%s %s: %s" % [BuildingPlot.Kind.keys()[kind], path.get_file(), why])
			root.free()
	check("every kind of building is built from a scene, with its beds, chest, door and things", bad.is_empty(), "\n".join(bad.slice(0, 6)))
	check("the scenes are varied (%d used)" % used.size(), used.size() >= 10, str(used.keys()))
	# the same building twice is the same inside
	var b := BuildingPlot.new()
	b.id = "test_town/same"
	b.kind = BuildingPlot.Kind.HOUSE
	b.size = Vector3(8, 3.4, 6)
	var r1 := InteriorBuilder.build(b, 77, 5, 1)
	var r2 := InteriorBuilder.build(b, 77, 5, 1)
	check("the same inside every visit", (r1["root"] as Node3D).get_meta("module") == (r2["root"] as Node3D).get_meta("module") and r1["decor"] == r2["decor"] and (r1["root"] as Node3D).get_child_count() == (r2["root"] as Node3D).get_child_count())
	(r1["root"] as Node3D).free()
	(r2["root"] as Node3D).free()
	# a home you own gets its stations and planters
	WorldState.set_record("home/" + b.id, {"town": "Test"})
	var mine := InteriorBuilder.build(b, 77, 5, 1)
	var mroot := mine["root"] as Node3D
	var stations := mroot.get_children().filter(func(n: Node) -> bool: return n is CraftingStation).size()
	var planters := mroot.get_children().filter(func(n: Node) -> bool: return n is Planter).size()
	var owned := mroot.find_children("*", "ContainerComponent", true, false).all(func(c: Node) -> bool: return (c as ContainerComponent).owner_id == "")
	check("your own home has its lab, bench and planters, and nothing in it is stolen", stations >= 3 and planters == 2 and owned, "%d stations, %d planters" % [stations, planters])
	mroot.free()
	WorldState.clear()
	# the Fighters' hall keeps its arena
	var t := BuildingPlot.new()
	t.id = "test_town/fighters"
	t.guild = "fighters"
	t.kind = BuildingPlot.Kind.GUILD_HALL
	var tr := InteriorBuilder.build(t, 5, 5, 1)
	check("the Fighters' hall keeps its arena", not (tr["root"] as Node3D).has_meta("module"))
	(tr["root"] as Node3D).free()


func t_house_in_game(wm: WorldManager, p: CharacterBody3D) -> void:
	print("-- walking into an inn")
	var inn: BuildingPlot = null
	for t in wm.towns:
		for b in t.town.buildings:
			if b.kind == BuildingPlot.Kind.INN and (inn == null or b.world_pos.distance_to(p.global_position) < inn.world_pos.distance_to(p.global_position)):
				inn = b
	check("there is an inn", inn != null)
	if inn == null:
		return
	Locks.set_locked(inn.id, false)
	wm.ensure_area_loaded(inn.get_door_position(), 2)
	await wm.dungeons.enter(inn.id, inn.get_door_position(), 0.0)
	await frames(60)
	var root := wm.dungeons.get_interior_root()
	check("the inn is built from a scene", root != null and String(root.get_meta("module", "")).contains("inn_"), str(root.get_meta("module", "") if root != null else ""))
	check("you stand on its floor", p.global_position.y > DungeonManager.DUNGEON_Y - 1.0 and absf(p.velocity.y) < 5.0, str(p.global_position))
	# up the stairs to the guest rooms
	var spots := wm.dungeons.current_spots
	var bed: Vector3 = (spots["beds"] as Array)[0]
	var way := InteriorBuilder.route(spots, spots["exit"], bed)
	for pt in way:
		var target := root.to_global(pt)
		for f in 400:
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.5:
				break
			p.velocity = Vector3(to.normalized().x * 4.0, p.velocity.y, to.normalized().z * 4.0)
			p.move_and_slide()
			await physics_frame
	var at_bed := p.global_position.distance_to(root.to_global(bed))
	check("you can walk up the stairs to a guest bed", at_bed < 1.6 and p.global_position.y > root.global_position.y + 4.0, "%.1f m away, at %.1f" % [at_bed, p.global_position.y - root.global_position.y])
	await wm.dungeons.exit()
	await frames(20)


# ---------------------------------------------------------------- 1.13.10 hand-made and baked

func t_handmade() -> void:
	print("-- hand-made and baked")
	WorldState.clear()
	var recipe := load("res://data/interiors/recipes/fort.tres") as DungeonRecipe
	var path := "user://test_baked.tscn"
	var err := DungeonPreview.bake_to(recipe, 77, 20, path)
	var plan := DungeonAssembler.plan(recipe, 77, 20)
	check("a generated dungeon bakes to a scene", err == OK and ResourceLoader.exists(path))
	var baked := (load(path) as PackedScene).instantiate() as Node3D
	var back := DungeonAssembler.from_scene(baked)
	check("the baked scene reads back as the same plan", back.placed.size() == plan.placed.size() and back.links.size() == plan.links.size() and back.summary() == plan.summary(), "%s / %s" % [back.summary(), plan.summary()])
	check("its doorways are capped and its spawn points kept", baked.find_children("Cap*", "", true, false).size() > 0 and baked.find_children("*", "SpawnSocket", true, false).size() > 20)
	baked.free()
	# a dungeon that names the baked scene uses it, filled and with its doors and secrets
	var data := (load("res://data/world/Dungeons/fort_ruin.tres") as DungeonData).duplicate() as DungeonData
	data.handmade = load(path) as PackedScene
	check("a hand-made dungeon is used instead of a plan", StitchedInterior.handmade_for(data, "test/hand") == path)
	var r := StitchedInterior.build(data, 5, "test/hand", 18, 22)
	var root := r["root"] as Node3D
	check("built from the hand-made scene: rooms, enemies, a boss and the way out", int(r["rooms"]) == plan.placed.size() and int(r["enemies"]) >= 3 and bool(r["boss"]) and root.find_children("Exit", "", true, false).size() == 1, str(r.get("signature")))
	var bc := root.find_children("*", "ContainerComponent", true, false).filter(func(c: Node) -> bool: return (c as ContainerComponent).save_id == "dungeon/test/hand/chest_boss")
	check("its boss chest keeps the name quests look for", bc.size() == 1)
	root.free()
	check("once seen it stays the same scene", StitchedInterior.handmade_for(data, "test/hand") == path)
	# one first seen generated stays generated (an old save's chests stay where they were)
	WorldState.set_record("stitched/test/old", {"v": 1})
	check("a dungeon first seen generated stays generated", StitchedInterior.handmade_for(data, "test/old") == "")
	# the story's vault
	WorldState.set_record("handmade/test/story", {"scene": Story.CODEX_VAULT})
	check("the story's dungeon gets the hand-made Codex vault", StitchedInterior.handmade_for(load("res://data/world/Dungeons/crypt.tres") as DungeonData, "test/story") == Story.CODEX_VAULT)
	WorldState.clear()
	# set-pieces pinned into random dungeons
	var with_piece := 0
	var crypt := load("res://data/interiors/recipes/crypt.tres") as DungeonRecipe
	check("recipes list their set-pieces", not crypt.set_pieces.is_empty() and not recipe.set_pieces.is_empty())
	for s in 20:
		var p := DungeonAssembler.plan(crypt, 9000 + s, 20)
		if p.set_piece >= 0 and p.placed[p.set_piece].entry.path.contains("setpieces"):
			with_piece += 1
	check("most crypts have the royal tomb in them (%d/20)" % with_piece, with_piece >= 14)
	# lords' halls of their own
	var b := BuildingPlot.new()
	b.id = "test_town/seat"
	b.kind = BuildingPlot.Kind.SEAT
	b.seat_type = "keep"
	b.town_name = "Harrowford"
	b.display_name = "Harrowford Manor"
	b.house = "aurelane"
	var hall := InteriorBuilder.build(b, 3, 10, 1)
	var hroot := hall["root"] as Node3D
	check("a named lord's hall is its own hand-made scene", String(hroot.get_meta("module", "")).contains("handmade/seat_harrowford"), str(hroot.get_meta("module", "")))
	check("with the bounty board, the treasury and the court's places", hroot.get_children().any(func(n: Node) -> bool: return n is BountyBoard) and (hall["spots"]["seats"] as Array).size() >= 4 and (hall["spots"]["work"] as Vector3).z > 0.0)
	hroot.free()
	var o := InteriorOverrides.get_all()
	check("every named keep and castle but Dawnhold is listed (%d)" % o.buildings.size(), o.buildings.size() >= 15 and not o.buildings.has("Kingsreach/Castle Dawnhold"))


# ---------------------------------------------------------------- 1.13.11 atmosphere and speed

func t_atmosphere(wm: WorldManager, p: CharacterBody3D, root: Node3D) -> void:
	print("-- atmosphere and speed")
	var dm := wm.dungeons
	var a := dm.atmosphere
	check("the dungeon has its theme's atmosphere", a != null and InteriorAtmosphere.PRESETS.has(a.theme) and dm.current_darkness == float(a.preset["dark"]), str(a.theme if a != null else "none"))
	if a == null:
		return
	var we := root.get_tree().root.find_children("*", "WorldEnvironment", true, false)
	var env: Environment = (we[0] as WorldEnvironment).environment if not we.is_empty() else null
	check("its fog and ambient light", env != null and env.fog_enabled and env.ambient_light_color == a.preset["ambient"])
	var stealth := p.get_node_or_null("Stealth")
	if stealth != null and stealth.has_method("light_level"):
		check("its darkness is what sneaking measures (%.2f)" % stealth._measure_light(), stealth._measure_light() >= float(a.preset["dark"]) - 0.001)
	var rooms := root.get_children().filter(func(n: Node) -> bool: return n is RoomModule)
	var merged := rooms.filter(func(r: Node) -> bool: return r.get_node_or_null("MergedRoom") != null).size()
	check("every room is drawn as one merged mesh (%d of %d)" % [merged, rooms.size()], merged >= rooms.size() - 1)
	var enemies := root.find_children("*", "Enemy", true, false)
	var loose := root.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return not enemies.any(func(e: Node) -> bool: return e.is_ancestor_of(m))).size()
	check("few loose meshes left (%d)" % loose, loose < rooms.size() * 12, str(loose))
	check("walls hide what is behind them (occluders)", root.find_children("*", "OccluderInstance3D", true, false).size() >= rooms.size())
	check("fire lights flicker (%d)" % a._flames.size(), a._flames.size() > 0)
	var e0 := (a._flames[0][0] as OmniLight3D).light_energy if not a._flames.is_empty() else 0.0
	await frames(7)
	check("...their light changes", a._flames.is_empty() or not is_equal_approx((a._flames[0][0] as OmniLight3D).light_energy, e0))
	check("dust in the air", a.get_node_or_null("Dust") != null or float(a.preset["dust"]) == 0.0)
	check("every room has its sound hook", rooms.all(func(r: Node) -> bool: return r.get_node_or_null("Ambience") != null))
	a.update_rooms(p.global_position)
	check("rooms far along the doorways are hidden (%d of %d)" % [a.hidden_rooms, rooms.size()], rooms.size() < 8 or a.hidden_rooms > 0)
	var near := rooms.filter(func(r: Node) -> bool: return (r as Node3D).global_position.distance_to(p.global_position) < 10.0)
	check("the room you are in is shown", near.all(func(r: Node) -> bool: return (r.get_node("MergedRoom") as Node3D).visible) if not near.is_empty() else true)
	# a frame budget for a big dungeon: the biggest recipe at a high level, built and in the tree
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 60000.0
	check("frames stay inside the budget (%.1f ms)" % ms, ms < 34.0)


# ---------------------------------------------------------------- 1.13.12 AI and navigation

func t_nav() -> void:
	print("-- AI and navigation")
	WorldState.clear()
	var data := load("res://data/world/Dungeons/fort_ruin.tres") as DungeonData
	var roles := {"sleep": 0, "ambush": 0, "patrol": 0, "fallback": 0, "paths": 0, "enemies": 0}
	var path_ok := 0
	var tries := 0
	for s in 6:
		var r := StitchedInterior.build(data, 400 + s, "test/nav%d" % s, 20, 26)
		var root := r["root"] as Node3D
		root.position = Vector3(0, -500, 0)
		get_root().add_child(root)
		await process_frame
		var nav := InteriorNav.make(root, r["plan"], s)
		for e in root.find_children("*", "Enemy", true, false):
			var en := e as Enemy
			roles["enemies"] += 1
			if en.asleep:
				roles["sleep"] += 1
			if en.lurking:
				roles["ambush"] += 1
			if en.has_meta("fallback"):
				roles["fallback"] += 1
			if en.path_provider.is_valid() and en.path_always:
				roles["paths"] += 1
		roles["patrol"] += nav.patrols.size()
		# a path from the entrance to the farthest room goes through every doorway between
		var far := 0
		for p in nav.plan.placed:
			if p.depth > nav.plan.placed[far].depth:
				far = p.index
		var way := nav.path(nav.room_center(0), nav.room_center(far))
		tries += 1
		if way.size() == nav.plan.placed[far].depth + 1 and way[-1] == nav.room_center(far):
			path_ok += 1
		# ambushers come out when you walk into the room next to theirs
		if not nav.ambushers.is_empty():
			var amb := nav.ambushers[0]
			var room := int(amb.get_meta("ambush_room"))
			nav._spring_ambush(room)
			check("an ambush is sprung when you come by", not amb.lurking)
		root.queue_free()
		await process_frame
	check("paths go room by room through the doorways (%d/%d)" % [path_ok, tries], path_ok == tries)
	check("every enemy finds its way by the doorways (%d/%d)" % [roles["paths"], roles["enemies"]], roles["paths"] == roles["enemies"] and roles["enemies"] > 0)
	check("sleepers in the bunks (%d)" % roles["sleep"], roles["sleep"] > 0)
	check("patrols walk their loops (%d)" % roles["patrol"], roles["patrol"] > 0)
	check("ambushers wait in side rooms (%d)" % roles["ambush"], roles["ambush"] > 0)
	check("the hurt have a deeper room to fall back to (%d)" % roles["fallback"], roles["fallback"] > roles["enemies"] / 3)
	# a sleeper sees nothing from across the room, and wakes when hurt
	var sleeper: Enemy = null
	var r2 := StitchedInterior.build(data, 404, "test/nav_s", 20, 26)
	var root2 := r2["root"] as Node3D
	root2.position = Vector3(0, -500, 0)
	get_root().add_child(root2)
	await process_frame
	InteriorNav.make(root2, r2["plan"], 4)
	for e in root2.find_children("*", "Enemy", true, false):
		if (e as Enemy).asleep:
			sleeper = e
	if sleeper != null:
		check("a sleeper lies asleep", sleeper.body == null or sleeper.body.pose == &"sleep")
		sleeper.wake()
		check("...and gets up when woken", not sleeper.asleep and (sleeper.body == null or sleeper.body.pose == &""))
	root2.queue_free()
	await process_frame
	WorldState.clear()


# ---------------------------------------------------------------- 1.13.13 integration

func t_integration() -> void:
	print("-- integration")
	WorldState.clear()
	var data := load("res://data/world/Dungeons/fort_ruin.tres") as DungeonData
	# captives in the cells, freed for good
	var captives: Array = []
	var roots: Array = []
	for s in 16:
		var r := StitchedInterior.build(data, 700 + s * 3, "test/cap%d" % s, 20, 24)
		var root := r["root"] as Node3D
		root.position = Vector3(0, -500, 0)
		get_root().add_child(root)
		roots.append(root)
		captives.append_array(root.find_children("*", "Captive", true, false))
	await process_frame
	check("captives wait in some dungeons' cells (%d)" % captives.size(), captives.size() > 0)
	if not captives.is_empty():
		var c := captives[0] as Captive
		var key := c.key
		c.interact(null)
		check("freeing one is remembered", WorldState.has_record("freed/" + key))
	for root in roots:
		(root as Node3D).queue_free()
	await process_frame
	# the rooms you walk into are remembered for the map, and the map draws them
	var r2 := StitchedInterior.build(data, 701, "test/map", 20, 24)
	var root2 := r2["root"] as Node3D
	root2.position = Vector3(0, -500, 0)
	get_root().add_child(root2)
	await process_frame
	var nav := InteriorNav.make(root2, r2["plan"], 1)
	nav.dungeon_id = "test/map"
	nav._mark_explored(0)
	nav._mark_explored(2)
	check("explored rooms are remembered", nav.explored() == [0, 2])
	check("the boss's room can be asked for (REACH room:boss)", nav.boss_room() >= 0 and nav.room_is(nav.boss_room(), "boss") and nav.room_is(0, "entrance"))
	var m := DungeonMap.open_for(self, nav)
	await process_frame
	check("the dungeon map opens and draws its rooms", m.room_outline(0).size() == 4 and paused)
	m.close()
	await process_frame
	check("...and closes", not paused)
	root2.queue_free()
	await process_frame
	# a long-cleared dungeon gets new occupants
	WorldState.set_record("found/test/old_fort", {"cleared": true, "cleared_day": 3})
	WorldState.set_record("kill/test/old_fort/r2/Enemy5/0", {"dead": true})
	WorldState.set_record("kill/dungeon/test/old_fort/boss", {"dead": true})
	var soon := DungeonRefill.occupants(data, "test/old_fort", 10)
	check("not before its time", int(soon["gen"]) == 0 and Discovery.is_cleared("test/old_fort"))
	var later := DungeonRefill.occupants(data, "test/old_fort", 3 + DungeonRefill.REFILL_DAYS)
	var folk := later["data"] as DungeonData
	check("after a while, new folk move in", int(later["gen"]) == 1 and folk.spawn_table != data.spawn_table and folk.recipe == data.recipe)
	check("...its dead are forgotten and it is not cleared any more", not WorldState.has_record("kill/test/old_fort/r2/Enemy5/0") and not WorldState.has_record("kill/dungeon/test/old_fort/boss") and not Discovery.is_cleared("test/old_fort"))
	check("...and they stay", (DungeonRefill.occupants(data, "test/old_fort", 40)["data"] as DungeonData).spawn_table == folk.spawn_table)
	WorldState.set_record("handmade/test/story_place", {"scene": Story.CODEX_VAULT})
	WorldState.set_record("found/test/story_place", {"cleared": true, "cleared_day": 1})
	check("the story's vault stays cleared", int(DungeonRefill.occupants(data, "test/story_place", 99)["gen"]) == 0)
	WorldState.clear()


# ---------------------------------------------------------------- 1.13.14 QA

func t_qa() -> void:
	print("-- QA: 100 dungeons per recipe")
	var bad := PackedStringArray()
	var t0 := Time.get_ticks_msec()
	var plans := 0
	for f in DirAccess.get_files_at("res://data/interiors/recipes/"):
		if not f.ends_with(".tres"):
			continue
		var recipe := load("res://data/interiors/recipes/" + f) as DungeonRecipe
		for s in 100:
			var lvl := 1 + (s * 7) % 80
			var plan := DungeonAssembler.plan(recipe, 50000 + s * 31, lvl)
			plans += 1
			# no two rooms in one cell
			var cells := 0
			for p in plan.placed:
				cells += p.cells.size()
			if cells != plan.occupied.size():
				bad.append("%s #%d: rooms overlap" % [f, s])
				continue
			# every doorway joined to one other or capped: each join is between two real doorways
			for l: Array in plan.links:
				var a: Dictionary = plan.door_world(plan.placed[int(l[0])], int(l[1]))
				var b: Dictionary = plan.door_world(plan.placed[int(l[2])], int(l[3]))
				if Vector3(a["pos"]).distance_to(b["pos"]) > 0.05 or Vector3(a["out"]).dot(b["out"]) > -0.99:
					bad.append("%s #%d: a doorway that doesn't meet its neighbour" % [f, s])
					break
			# every room reachable from the entrance
			var seen := {0: true}
			var queue := [0]
			while not queue.is_empty():
				var r: int = queue.pop_front()
				for l: Array in plan.links:
					for pair in [[int(l[0]), int(l[2])], [int(l[2]), int(l[0])]]:
						if pair[0] == r and not seen.has(pair[1]):
							seen[pair[1]] = true
							queue.append(pair[1])
			if seen.size() != plan.placed.size():
				bad.append("%s #%d: %d rooms can't be reached" % [f, s, plan.placed.size() - seen.size()])
			if recipe.boss and not plan.placed.any(func(p) -> bool: return p.entry.role == RoomModule.Role.BOSS):
				bad.append("%s #%d: no boss room" % [f, s])
	check("%d dungeons: no overlaps, holes, unreachable rooms or missing bosses (%d ms)" % [plans, Time.get_ticks_msec() - t0], bad.is_empty(), "\n".join(bad.slice(0, 8)))
	# the module checker on every room, house, set-piece and hand-made scene
	var probs := PackedStringArray()
	var count := 0
	for dir in ["res://scenes/interiors/houses/", "res://scenes/interiors/setpieces/", "res://scenes/interiors/handmade/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".tscn"):
				continue
			var n := (load(dir + f) as PackedScene).instantiate()
			count += 1
			for room in ([n] if n is RoomModule else []) + n.find_children("*", "RoomModule", true, false):
				for pr in (room as RoomModule).problems():
					probs.append("%s: %s" % [f, pr])
			n.free()
	check("the module checker finds nothing wrong in %d more scenes" % count, probs.is_empty(), "\n".join(probs.slice(0, 8)))
	# the biggest dungeon there is: built, merged and filled inside a budget
	var big := load("res://data/world/Dungeons/fort_ruin.tres").duplicate() as DungeonData
	big.recipe = load("res://data/interiors/recipes/fort_over_crypt.tres") as DungeonRecipe
	var t1 := Time.get_ticks_msec()
	var r := StitchedInterior.build(big, 99, "test/big", 70, 80)
	var root := r["root"] as Node3D
	StaticBatch.merge_interior(root)
	var ms := Time.get_ticks_msec() - t1
	var meshes := root.find_children("*", "MeshInstance3D", true, false).size()
	check("the biggest dungeon (%d rooms) builds in %d ms" % [int(r["rooms"]), ms], ms < 4000)
	check("...and draws in few pieces (%d meshes for %d rooms)" % [meshes, int(r["rooms"])], meshes < int(r["rooms"]) * 10)
	root.free()
	WorldState.clear()
