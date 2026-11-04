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
		await t_gathering()
		await t_settlers()
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


func t_gathering() -> void:
	print("-- gathering, tools, salvage, recipes")
	var inv := p.get_node("Inventory") as Inventory
	var nodes := root.find_children("*", "StaticBody3D", true, false).filter(func(n): return n is HarvestNode and (n as HarvestNode).kind in HarvestNode.GATHER)
	check("the land has things to gather", nodes.size() > 0, str(nodes.size()))
	var kinds := {}
	for n in nodes:
		kinds[(n as HarvestNode).kind] = true
	check("of several kinds", kinds.size() >= 2, str(kinds.keys()))
	# gather some by hand
	var fibre: HarvestNode = null
	var rock: HarvestNode = null
	for n in nodes:
		if (n as HarvestNode).kind in ["fibre", "branches", "clay"] and fibre == null and (n as HarvestNode).is_ready():
			fibre = n
		if (n as HarvestNode).kind == "rock" and rock == null and (n as HarvestNode).is_ready():
			rock = n
	if fibre != null:
		var before := inv.stacks.size()
		fibre.interact(inv)
		check("gathering by hand fills your pack", inv.stacks.size() > before or not fibre.is_ready())
		check("and it grows back later, not now", not fibre.is_ready())
	if rock != null:
		var stone := load("res://data/materials/stone.tres") as ItemData
		var n0 := inv.get_count(stone)
		rock.interact(inv)
		check("stone needs a pick", inv.get_count(stone) == n0)
		inv.add_item(load("res://data/materials/stone_pickaxe.tres"), 1)
		rock.interact(inv)
		check("a stone pick will do", inv.get_count(stone) > n0)
	# picks by tier
	check("a stone pick is the lowest tier", HarvestNode.pick_tier(inv) == 0)
	check("obsidian needs a steel pick", int(HarvestNode.ORE_TIER["obsidian_ore"]) == 2)
	inv.add_item(load("res://data/materials/steel_pickaxe.tres"), 1)
	check("your best pick counts", HarvestNode.pick_tier(inv) == 2)
	# salvage
	var sword := load("res://data/weapons/iron_sword.tres") as ItemData
	inv.add_item(sword, 1)
	var ingot := load("res://data/materials/iron_ingot.tres") as ItemData
	var i0 := inv.get_count(ingot)
	var got := Recipes.salvage(p, sword)
	check("a sword breaks down into iron", got != "" and inv.get_count(ingot) > i0, got)
	# recipes you discover
	WorldState.erase_record(Recipes.KNOWN)
	var stone_pick: Dictionary = {}
	for r in Recipes.for_station("workbench"):
		if String(r["result"]).ends_with("stone_pickaxe.tres"):
			stone_pick = r
	var empty := Inventory.new()
	check("a recipe stays hidden until you have held what it needs", not Recipes.is_known(stone_pick, empty))
	empty.add_item(load("res://data/materials/stone.tres"), 1)
	empty.add_item(load("res://data/materials/firewood.tres"), 1)
	empty.add_item(load("res://data/materials/plant_fibre.tres"), 1)
	check("then it shows", Recipes.is_known(stone_pick, empty))
	empty.free()


func t_settlers() -> void:
	print("-- settlers and taming")
	var st := Settlers.of(self)
	check("Settlers runs", st != null)
	var home := p.global_position + Vector3(30, 0, 30)
	home.y = wm.get_height_at(home.x, home.z)
	WorldState.set_record("homestead", {"pos": [home.x, home.y, home.z], "yaw": 0.0, "built": ["hall"]})
	check("with only a hall, room for one", Settlers.capacity() == 1)
	check("a settler comes", Settlers.invite("Ada Thorn", "farmer") == "" and Settlers.all().size() == 1)
	check("no room for a second", Settlers.invite("Bram Hale", "hunter") != "")
	WorldState.set_record("homestead", {"pos": [home.x, home.y, home.z], "yaw": 0.0, "built": ["hall", "bedroom"]})
	check("a bedroom makes room", Settlers.invite("Bram Hale", "hunter") == "" and Settlers.all().size() == 2)
	st.daily()
	var store := WorldState.get_record(Settlers.STORE)
	check("they work: the farm and the hunt bring things in", store.size() >= 2, str(store))
	check("fed and housed, they are content", Settlers.all().all(func(s): return int(s["mood"]) > 60))
	# hungry and crowded, they leave in the end
	WorldState.set_record(Settlers.RECORD, {"list": [{"id": "x|0", "name": "Cor", "job": "guard", "mood": 20, "joined": 1}, {"id": "y|1", "name": "Dun", "job": "guard", "mood": 20, "joined": 1}, {"id": "z|2", "name": "Eda", "job": "guard", "mood": 20, "joined": 1}, {"id": "w|3", "name": "Fyn", "job": "guard", "mood": 20, "joined": 1}]})
	st.daily()
	check("without food or beds, settlers leave", Settlers.all().size() < 4, str(Settlers.all().size()))
	# their bodies stand about the plot
	WorldState.set_record(Settlers.RECORD, {"list": [{"id": "a|0", "name": "Ada Thorn", "job": "farmer", "mood": 70, "joined": 1}]})
	p.global_position = home + Vector3(0, 1.5, 0)
	st._place_bodies()
	await frames(5)
	check("you find them at your homestead", st._bodies.size() == 1)
	WorldState.erase_record("homestead")
	WorldState.erase_record(Settlers.RECORD)
	st._place_bodies()
	# taming
	var inv := p.get_node("Inventory") as Inventory
	inv.add_item(load(Taming.MEAT), 5)
	var wolf := Population.spawn_enemy(load("res://data/enemies/wolf.tres"), 3, wm, p.global_position + Vector3(1.5, 0, 0), RandomNumberGenerator.new())
	wolf.set_physics_process(false)
	await frames(3)
	wolf.global_position = p.global_position + Vector3(1.5, -1.0, 0)
	check("with meat, a calm wolf can be tamed", Taming.candidate(p) == wolf)
	var tamed := false
	for i in 30:
		seed(i)
		var said := Taming.tame(p, wolf)
		if wolf.has_meta("pet"):
			tamed = true
			break
		wolf._provoked = false
		wolf.stop_fighting()
		inv.add_item(load(Taming.MEAT), 1)
	check("it eats from your hand and follows you", tamed and wolf.has_meta("player_ally") and Taming.pets(p) == 1)
