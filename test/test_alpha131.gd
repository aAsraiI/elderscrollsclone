extends SceneTree
## Alpha 1.31 (world and exploration), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha131.gd

var passes := 0
var fails := 0
var wm: WorldManager
var p: CharacterBody3D


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


func secs(s: float) -> void:
	await frames(int(round(s * 60.0)))


func _run() -> void:
	await process_frame
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(120)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", wm != null and p != null)
	if wm != null and p != null:
		GameRules._rules["encounter_rate"] = 0.0
		(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
		(p.get_node("Stats") as Stats).revive()
		wm.clock.set_time(12.0)
		await t_explore()
		await t_sites()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_explore() -> void:
	print("-- fog, maps, treasure, meteors, the hours")
	var pos := p.global_position
	await secs(2.5)
	check("the fog clears where you are", ExploredMap.is_explored(pos.x, pos.z))
	check("not far away", not ExploredMap.is_explored(pos.x + 5000.0, pos.z + 5000.0))
	var img := ExploredMap.make_image(wm.map.get_bounds())
	check("the fog draws as an image", img != null and img.get_width() > 0)
	var far := pos + Vector3(4000, 0, 4000)
	var n := ExploredMap.buy_map(far, wm, 3)
	check("a bought map clears the fog there", ExploredMap.is_explored(far.x, far.z), str(n))
	# treasure
	var inv := p.get_node("Inventory") as Inventory
	var map_item := load("res://data/misc/treasure_map.tres") as ItemData
	inv.add_item(map_item, 1)
	check("a treasure map is studied", ItemUse.verb(p, map_item) == "Study the map")
	var ev := WorldEvents.of(self)
	check("the world has events", ev != null)
	var markers := MapMarkers.all().size()
	ItemUse.use(p, map_item)
	var list: Array = WorldState.get_record("treasure").get("list", [])
	check("it marks a spot on your map", list.size() == 1 and MapMarkers.all().size() == markers + 1 and inv.get_count(map_item) == 0, str(list.size()))
	if not list.is_empty():
		var id := String(list[0]["id"])
		check("digging needs a tool", WorldEvents.dig(p, id).contains("pickaxe") or DigSpot.has_tool(inv))
		inv.add_item(load("res://data/clutter/shovel.tres") as ItemData, 1)
		var gold := Currency.get_gold(inv)
		var said := WorldEvents.dig(p, id)
		check("dug up: gold", Currency.get_gold(inv) > gold, said)
		check("and it's gone", (WorldState.get_record("treasure").get("list", []) as Array).is_empty())
	# a meteor
	var at := Vector3.INF
	for i in 30:
		at = ev.fall(p)
		if at.is_finite():
			break
	check("a star can fall", at.is_finite())
	if at.is_finite():
		ev._stream(p)
		p.global_position = at + Vector3(5, 2, 0)
		ev._stream(p)
		await frames(3)
		var ore := []
		for c in ev.get_children():
			ore.append_array(c.find_children("*", "HarvestNode", true, false))
		check("its crater holds Star Ore", ore.any(func(h: Node) -> bool: return (h as HarvestNode).item_id == "star_ore"), str(ore.size()))
	# day and night
	wm.clock.set_time(0.0)
	check("the dead walk at night", EncounterManager._hour_factor("skeletons", wm.clock) > 1.0)
	wm.clock.set_time(12.0)
	check("and hardly by day", EncounterManager._hour_factor("skeletons", wm.clock) < 1.0)
	check("others are not bothered", EncounterManager._hour_factor("wolves", wm.clock) == 1.0)
	# ash storms
	var w := Weather.get_instance(self)
	check("there are ash storms", Weather.TABLE.has("ash") and Weather.LOOK.has(Weather.Kind.ASHSTORM) and Weather.NAMES[Weather.Kind.ASHSTORM] == "Ash storm")
	if w != null:
		w.set_weather(Weather.Kind.ASHSTORM, 1.0)
		await frames(5)
		check("and the sky can hold one", w.current == Weather.Kind.ASHSTORM)
		w.set_weather(Weather.Kind.CLEAR, 1.0)


func t_sites() -> void:
	print("-- landmarks, drowned places, puzzles, cities, roamers")
	var ws := WorldSites.of(self)
	check("the sites exist", ws != null)
	var t0 := Time.get_ticks_msec()
	ws.plan()
	print("planned in %d ms: %d sites" % [Time.get_ticks_msec() - t0, ws.sites.size()])
	var kinds := {}
	for s in ws.sites:
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
	check("landmarks and puzzles are placed", int(kinds.get("landmark", 0)) >= 6 and int(kinds.get("puzzle", 0)) >= 4, str(kinds))
	var first := ws.sites.duplicate()
	ws.plan()
	check("the same for the same world", first.size() == ws.sites.size() and first[0]["pos"] == ws.sites[0]["pos"])
	for s in ws.sites:
		var n := ws.build(s)
		check("%s builds" % s["id"], n != null and n.get_child_count() > 0)
		n.queue_free()
		if s["id"].ends_with("_1"):
			pass
	await frames(3)
	# a landmark is found
	var lm: Dictionary = ws.sites.filter(func(s: Dictionary) -> bool: return s["kind"] == "landmark")[0]
	ws.mark_found(lm)
	check("found, it goes on the map", WorldSites.is_found(lm["id"]) and Achievements.count("site_landmark") == 1 and MapMarkers.all().any(func(m: Dictionary) -> bool: return String(m.get("name", "")) == String(lm["name"])))
	# puzzles
	for form in PuzzleSite.FORMS:
		var root := Node3D.new()
		wm.add_child(root)
		root.global_position = p.global_position + Vector3(0, 0, 30)
		var ps := PuzzleSite.make(root, {"id": "test_" + form, "form": form, "pos": root.global_position})
		await frames(2)
		check("%s: a clue on the plaque" % form, ps.use("plaque", 0).length() > 5)
		match form:
			"levers":
				var wrong: int = (int(ps.order[0]) + 1) % 4
				check("levers: a wrong one resets", ps.use("lever", wrong).contains("snaps back"))
				for i in ps.order:
					ps.use("lever", int(i))
			"pillars", "mirrors":
				var what := "pillar" if form == "pillars" else "mirror"
				for i in ps.state.size():
					while int(ps.state[i]) != int(ps.order[i]):
						ps.use(what, i)
		await frames(1)
		check("%s: solved" % form, PuzzleSite.solved("test_" + form))
		check("%s: the cage is gone" % form, ps._cage == null or not is_instance_valid(ps._cage) or ps._cage.is_queued_for_deletion())
		root.queue_free()
	check("puzzles count", Achievements.count("puzzle") == 3)
	# a ruined city
	var root2 := Node3D.new()
	wm.add_child(root2)
	root2.global_position = p.global_position + Vector3(60, 0, 0)
	var city := RuinedCity.make(root2, {"id": "test_city", "name": "Old Test", "pos": root2.global_position}, wm)
	await frames(3)
	check("the dead hold the city", city.foes_left() == RuinedCity.GUARDS and city._foes.size() == RuinedCity.GUARDS)
	check("the stone is cold", city.prompt().contains("cold") and city.use(p).contains("dead"))
	for e in city._foes.duplicate():
		e._hurt_by_player = true
		e.stats.modify_vital("health", -9999999.0)
	await frames(5)
	check("killed, they stay dead", city.foes_left() == 0, str(city.foes_left()))
	var inv := p.get_node("Inventory") as Inventory
	Currency.add_gold(inv, RuinedCity.RESETTLE_GOLD + 10)
	check("then it can be settled", city.prompt().contains("Resettle") and city.use(p).contains("people") and RuinedCity.settled("test_city"))
	var rec := WorldState.get_record("city/test_city").duplicate()
	rec["paid"] = wm.clock.day - 5
	WorldState.set_record("city/test_city", rec)
	var gold := Currency.get_gold(inv)
	city.use(p)
	check("and pays taxes", Currency.get_gold(inv) - gold == 5 * RuinedCity.TAX_PER_DAY)
	root2.queue_free()
	await frames(3)
	# roamers
	var ro := Roamers.of(self)
	check("roamers exist", ro != null)
	var walkers: Array[Enemy] = []
	for i in 20:
		walkers = ro.send("caravan", p)
		if not walkers.is_empty():
			break
	check("a caravan walks by", walkers.size() == 3 and walkers.all(func(e: Enemy) -> bool: return e.disposition == Enemy.Disposition.FRIENDLY), str(walkers.size()))
	await frames(5)
	check("on a route", not walkers.is_empty() and not walkers[0].route.is_empty())
	var low := ro.pick_kind(p)
	check("a beginner only meets caravans", low == "caravan" or (p.get_node("Skills") as Skills).get_player_level() >= 15)
	for e in walkers:
		e.queue_free()
