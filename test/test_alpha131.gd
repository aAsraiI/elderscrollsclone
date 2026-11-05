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
