extends SceneTree
## Headless tests for stage 14, the system improvements: smaller saves, the shop economy, NPC
## memory, the debug console, light and shadow for stealth, smarter fighters, throwing and knocking
## things over, and the far land with town outlines.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage14.gd

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
		await process_frame


func secs(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await frames(2)
	t_saves()
	t_economy()
	t_memory()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_saves() -> void:
	print("-- smaller saves")
	WorldState.clear()
	for i in 300:
		WorldState.set_record("npcact/person_%d" % i, {"a": 3})
		WorldState.set_record("lock/house_%d" % i, {"locked": i % 2 == 0})
	var saved := WorldState.to_save_dict()
	check("what you changed is all in the save", saved.has("npcact/person_1") and saved.has("lock/house_1"))
	var data := {"version": 2, "world_state": saved}
	var plain := "user://test_plain.json"
	var packed := "user://test_packed.json"
	SaveUtil.write_json_atomic(plain, data, false)
	SaveUtil.write_json_atomic(packed, data, false, true)
	var plain_size := FileAccess.open(plain, FileAccess.READ).get_length()
	var packed_size := FileAccess.open(packed, FileAccess.READ).get_length()
	check("a compressed save is much smaller", packed_size * 4 < plain_size, "%d vs %d bytes" % [packed_size, plain_size])
	check("and reads back the same", SaveUtil.read_json(packed) == SaveUtil.read_json(plain))
	check("old plain saves still read", (SaveUtil.read_json(plain) as Dictionary).has("world_state"))
	DirAccess.remove_absolute(plain)
	DirAccess.remove_absolute(packed)
	WorldState.clear()


func t_economy() -> void:
	print("-- the shop economy")
	WorldState.clear()
	var ore := load("res://data/materials/iron_ore.tres") as ItemData
	var bread := load("res://data/consumables/bread.tres") as ItemData
	check("ore is cheap where it is mined", Economy.buy_factor(ore, "t1", "highlands", false, 1) < 1.0)
	check("food is dear in the desert", Economy.buy_factor(bread, "t1", "desert", false, 1) > 1.0)
	var before := Economy.sell_factor(ore, "t1", "plains", false, 1)
	Economy.record("t1", ore, 20, 1)
	var flooded := Economy.sell_factor(ore, "t1", "plains", false, 1)
	check("selling a lot floods the market", flooded < before - 0.2, "%f -> %f" % [before, flooded])
	check("and it recovers over the days", Economy.sell_factor(ore, "t1", "plains", false, 15) > flooded + 0.2)
	Economy.record("t2", bread, -20, 1)
	check("buying it all up makes it dearer", Economy.buy_factor(bread, "t2", "plains", false, 1) > Economy.buy_factor(bread, "t3", "plains", false, 1))
	check("festivals put up food prices", Economy.buy_factor(bread, "t3", "plains", true, 1) > Economy.buy_factor(bread, "t3", "plains", false, 1))
	var m := load("res://data/merchants/general.tres") as MerchantData
	var d := Barter.Deal.new()
	var plain := Barter.sell_price(ore, m, d)
	d.town_id = "t1"
	d.biome = "plains"
	check("the barter price follows the market", Barter.sell_price(ore, m, d) < plain or plain <= 1, "%d vs %d" % [Barter.sell_price(ore, m, d), plain])
	WorldState.clear()


func t_memory() -> void:
	print("-- NPC memory")
	WorldState.clear()
	var s := DialogueEngine.Speaker.new()
	s.name = "Brenna Fenn"
	check("nothing remembered, nothing said", NpcMemory.greeting(s, 1) == "")
	NpcMemory.remember("Brenna Fenn", "", "theft", "", 1)
	var g := NpcMemory.greeting(s, 2)
	check("a witness mentions the theft", g.contains("took") and g.contains("yesterday"), g)
	NpcMemory.remember("Brenna Fenn", "", "quest", "The Lost Ring", 3)
	check("the newest memory comes first", NpcMemory.greeting(s, 3).contains("The Lost Ring"))
	NpcMemory.greeting(s, 3)
	check("each thing is mentioned only a couple of times", NpcMemory.greeting(s, 3).contains("took"))
	NpcMemory.greeting(s, 3)
	check("then they let it rest", NpcMemory.greeting(s, 3) == "")
	WorldState.clear()


func t_in_game() -> void:
	print("-- in the game")
	SaveSession.begin_new_game(0, true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	# The debug console
	var console := player.get_node("DebugConsole") as DebugConsole
	var inv := player.get_node("Inventory") as Inventory
	var gold := Currency.get_gold(inv)
	console.run("gold 250")
	check("console: gold", Currency.get_gold(inv) == gold + 250)
	console.run("give health_potion 3")
	check("console: give", inv.get_count(load("res://data/consumables/health_potion.tres")) >= 3)
	console.run("god")
	(player.get_node("Stats") as Stats).modify_vital("health", -500.0)
	check("console: god mode", not (player.get_node("Stats") as Stats).is_dead and (player.get_node("Stats") as Stats).health > 0.0)
	console.run("god")
	check("console: unknown words are explained", console.run("dance").contains("Unknown"))
	var out := console.run("spawn wolf 2 5")
	check("console: spawn", out.begins_with("Spawned 2"), out)
	console.run("kill")
	await frames(2)
	check("console: tp to a town", console.run("tp kingsreach").begins_with("Teleported"))
	await secs(2.0)
	# Light and shadow
	var stealth := player.get_node("Stealth") as Stealth
	wm.clock.set_time(23.0, 2)
	wm.clock.apply_now()
	await secs(0.5)
	stealth._light_clock = 0.0
	var dark := stealth.light_level()
	var lamp := OmniLight3D.new()
	lamp.omni_range = 8.0
	lamp.light_energy = 1.5
	var poi_node := wm.get_poi_node(wm.get_town_at(player.global_position, 80.0).id) if wm.get_town_at(player.global_position, 80.0) != null else null
	check("there is a town node to hang a lamp in", poi_node != null)
	if poi_node != null:
		poi_node.add_child(lamp)
		lamp.global_position = player.global_position + Vector3(0, 2.0, 0)
		stealth._lights_for = self  # forget the list so it is looked up again
		stealth._light_clock = 0.0
		var lit := stealth.light_level()
		check("at night, standing under a lamp makes you easier to see", lit > dark + 0.2, "%f vs %f" % [lit, dark])
		lamp.queue_free()
	# Smarter fighters: two hunting the player come from different sides
	var a := Enemy.spawn(wm, player.global_position + Vector3(0, 0.5, 12))
	var b := Enemy.spawn(wm, player.global_position + Vector3(1, 0.5, 12))
	await frames(2)
	a._target = player
	b._target = player
	a._flank_angle = 0.9
	b._flank_angle = -0.9
	a.cunning = 0.6
	b.cunning = 0.6
	var ga := a._flank_goal(player.global_position - a.global_position, 12.0)
	var gb := b._flank_goal(player.global_position - b.global_position, 12.0)
	check("two hunters spread out to flank", ga.angle_to(gb) > 0.6, str(ga.angle_to(gb)))
	b.queue_free()
	await frames(2)
	for e in ActorRegistry.all():
		if e != a:
			e._target = null  # the game scene's practice enemy is after the player too
	var alone := a._flank_goal(player.global_position - a.global_position, 12.0)
	check("one alone comes straight on", alone.angle_to((player.global_position - a.global_position).normalized()) < 0.05)
	a.queue_free()
	# Throwing and knocking things over
	var cup := WorldItem.spawn(load("res://data/consumables/apple.tres"), 1, wm, player.global_position + Vector3(0, 1.0, -1.5))
	var shelf_thing := WorldItem.spawn(load("res://data/consumables/bread.tres"), 1, wm, player.global_position + Vector3(0, 1.0, -4.0))
	await frames(2)
	shelf_thing.freeze = true
	shelf_thing.wake(Vector3(0, 1, 0))
	check("a frozen thing on a shelf can be knocked loose", not shelf_thing.freeze)
	var grabber := player.get_node("Head/RayCast3D/Grabber") as Grabber
	check("the player can pick a thing up", grabber.grab(cup))
	await frames(5)
	check("and throw it", grabber.throw() and not grabber.is_holding())
	await secs(0.3)
	check("it flies", cup.linear_velocity.length() > 2.0, str(cup.linear_velocity))
	# The far land and the towns out there
	var far := wm.get_node_or_null("FarLand") as FarLand
	check("the real game draws the far land", far != null)
	if far != null:
		await secs(3.0)
		check("its coarse terrain is built", far._mesh.mesh != null)
		var outlines := 0
		for c in far.get_children():
			if String(c.name).begins_with("FarTown_") and (c as Node3D).visible:
				outlines += 1
		check("far towns show as outlines", outlines >= 3, str(outlines))
