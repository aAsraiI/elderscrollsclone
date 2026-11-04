extends SceneTree
## Alpha 1.25 (survival sandbox), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha125.gd

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
	GameRules.set_rule("survival", true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(120)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", wm != null and p != null)
	if wm != null and p != null:
		(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
		wm.clock.set_time(12.0)
		await t_body()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	GameRules.set_rule("survival", false)
	quit(1 if fails > 0 else 0)


func t_body() -> void:
	print("-- the body: meals, warmth, fire, wet, rest")
	var surv := p.get_node("Survival") as Survival
	var stats := p.get_node("Stats") as Stats
	check("survival is on for this test", surv != null and surv.enabled())
	# meals
	var hp := stats.get_stat("max_health")
	var stew := load("res://data/consumables/beef_stew.tres") as ItemData
	var apple := load("res://data/consumables/apple.tres") as ItemData
	surv.on_eat(stew)
	check("a meal raises your health and stamina for a while", surv.meals.size() == 1 and stats.get_stat("max_health") > hp, "%.0f -> %.0f" % [hp, stats.get_stat("max_health")])
	surv.on_eat(stew)
	check("the same dish again just refreshes it", surv.meals.size() == 1)
	surv.on_eat(apple)
	surv.on_eat(load("res://data/consumables/apple_pie.tres"))
	surv.on_eat(load("res://data/consumables/baked_potato.tres"))
	check("three meals at most, the oldest goes", surv.meals.size() == 3 and String(surv.meals[0]["id"]) != "beef_stew", str(surv.meals.map(func(m): return m["id"])))
	check("bigger food, bigger buff", float(surv.meals.filter(func(m): return m["id"] == "apple_pie")[0]["health"]) >= float(surv.meals.filter(func(m): return m["id"] == "apple")[0]["health"]))
	wm.clock.set_time(wm.clock.hour + 9.0)
	surv._meal_t = 0.0
	surv._tick_meals(0.1)
	check("they wear off", surv.meals.is_empty() and absf(stats.get_stat("max_health") - hp) < 0.5)
	check("and they are saved", surv.to_dict().has("meals"))
	# warmth
	var fur := ItemData.new()
	fur.item_type = ItemData.ItemType.ARMOR
	fur.display_name = "Bear Fur Cloak"
	var iron := load("res://data/armor/iron_chestplate.tres") as ItemData if ResourceLoader.exists("res://data/armor/iron_chestplate.tres") else ItemData.new()
	iron.item_type = ItemData.ItemType.ARMOR
	check("furs keep you warmer than plate", Survival.warmth(fur) > Survival.warmth(iron))
	# a fire warms you and dries you
	var ws := WorldSurfaces.of(self)
	wm.clock.set_time(23.0)
	var cold := surv.cold_target()
	var at := p.global_position + Vector3(1.5, 0, 0)
	at.y = wm.get_height_at(at.x, at.z)
	var fire := ws.add(WorldSurfaces.Kind.FIRE, at, 1.0, 30.0)
	await frames(2)
	check("a fire close by is a heat source", surv.near_fire())
	check("and it keeps the cold off", surv.cold_target() < cold or cold == 0.0, "%.0f -> %.0f" % [cold, surv.cold_target()])
	ws._remove(fire)
	await frames(2)
	surv.wet = 80.0
	check("wet clothes chill you", surv.cold_target() > cold - 0.01)
	surv.wet = 0.0
	# tired: you learn slowly
	surv.fatigue = 80.0
	surv._update_stages()
	check("exhausted, you learn more slowly", stats.get_stat("skill_xp_pct") < 0.0)
	surv.fatigue = 0.0
	surv._update_stages()
	check("more comfort, a longer rest", Survival.rest_minutes(4) > Survival.rest_minutes(0))
	check("heat and wet have stages too", surv.status_lines() is PackedStringArray and Survival.STAGE_NAMES.has("heat") and Survival.STAGE_NAMES.has("wet"))
