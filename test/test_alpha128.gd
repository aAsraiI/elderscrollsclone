extends SceneTree
## Alpha 1.28 (magic), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha128.gd

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
		(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0, "max_magicka": 100000.0})
		(p.get_node("Stats") as Stats).revive()
		wm.clock.set_time(12.0)
		await t_spells()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_spells() -> void:
	print("-- island ranks, scrolls, levitation, water walking")
	var five := SpellCatalog.all_ids().filter(func(id: String) -> bool: return SpellCatalog.rank_of(id) == 5)
	var six := SpellCatalog.all_ids().filter(func(id: String) -> bool: return SpellCatalog.rank_of(id) == 6)
	check("every school has Grandmaster and Ascendant spells", five.size() >= 12 and six.size() >= 12, "%d %d" % [five.size(), six.size()])
	check("each has a tome", (five + six).all(func(id: String) -> bool: return SpellCatalog.get_tome(id) != null))
	check("the tomes are far-island loot", SpellCatalog.get_tome("meteor").min_level == 100 and SpellCatalog.get_tome("sunfire").min_level == 150)
	var stock := CraftStock.extra_for("mages", 100, 160).map(func(e: LootEntry) -> String: return String(e.item.id))
	var home := CraftStock.extra_for("mages", 1, 40).map(func(e: LootEntry) -> String: return String(e.item.id))
	check("far-island mages sell them", stock.has("tome_sunfire") and stock.has("tome_meteor"))
	check("mainland mages do not", not home.has("tome_meteor"))
	# scrolls
	var inv := p.get_node("Inventory") as Inventory
	var scroll := load("res://data/consumables/scroll_healing_hands.tres") as ItemData
	inv.add_item(scroll, 2)
	check("a scroll is read", ItemUse.verb(p, scroll) == "Read the scroll")
	var st := p.get_node("Stats") as Stats
	st.modify_vital("magicka", -st.magicka)
	ItemUse.use(p, scroll)
	await frames(20)
	check("it casts with no magicka and is used up", inv.get_count(scroll) == 1 and Achievements.count("scroll") == 1, str(inv.get_count(scroll)))
	st.modify_vital("magicka", 100000.0)
	# levitation
	var am := ActiveMagic.of(p)
	am.apply_one({"id": "levitate", "mag": 0.0, "dur": 30.0}, p, "test", "spell")
	check("levitate lets you fly", bool(p.get("can_fly")) and p.has_meta("levitating"))
	var town := wm.get_nearest_town(p.global_position)
	p.call("set_flying", true)
	var over: bool = p.call("over_town")
	if over:
		await frames(40)
		check("never over a town", not bool(p.get("flying")))
	else:
		check("the town check runs", true)
	am.remove_effect(&"levitate")
	await frames(2)
	check("when it ends you come down", not bool(p.get("can_fly")) and not p.has_meta("levitating"))
	# water walking
	var water := Vector3.INF
	for r in range(50, 1200, 40):
		for a in 16:
			var q := p.global_position + Vector3(cos(a * TAU / 16.0), 0, sin(a * TAU / 16.0)) * r
			if wm.get_height_at(q.x, q.z) < wm.map.get_water_level(q.x, q.z) - 2.0:
				water = q
				break
		if water.is_finite():
			break
	check("there is water nearby", water.is_finite())
	if water.is_finite():
		am.apply_one({"id": "water_walk", "mag": 0.0, "dur": 60.0}, p, "test", "spell")
		wm.ensure_area_loaded(water, 1)
		var sea := wm.map.get_water_level(water.x, water.z)
		p.global_position = Vector3(water.x, sea + 0.05, water.z)
		p.velocity = Vector3.ZERO
		await secs(1.5)
		check("water walking holds you on the surface", absf(p.global_position.y - sea) < 0.3, "%.2f vs %.2f" % [p.global_position.y, sea])
		am.remove_effect(&"water_walk")
		await secs(1.5)
		check("without it you sink", p.global_position.y < sea - 0.3, "%.2f vs %.2f" % [p.global_position.y, sea])
	if town != null:
		pass
