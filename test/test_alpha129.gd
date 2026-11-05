extends SceneTree
## Alpha 1.29 (stealth, thievery and crime), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha129.gd

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
		await t_pickpocket()
		await t_lockpick()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _npc(at: Vector3) -> Enemy:
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var e := Population.spawn_enemy(load("res://data/enemies/bandit.tres"), 5, wm, at, RandomNumberGenerator.new())
	e.disposition = Enemy.Disposition.NEUTRAL
	return e


func t_pickpocket() -> void:
	print("-- picking pockets")
	check("there is a Pickpocket skill", SkillDatabase.get_skill(&"pickpocket") != null)
	var e := _npc(p.global_position + Vector3(0, 0, -1.5))
	await frames(3)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	var gold := load("res://data/consumables/gold.tres") as ItemData
	e.inventory.add_item(gold, 30)
	var st: Stealth = p.get_meta("stealth")
	check("not while standing up", not Pickpocket.can(p, e))
	st.set_sneaking(true)
	st.awareness.clear()
	check("sneaking up on someone unaware, you can", Pickpocket.can(p, e))
	var c := Pickpocket.chance(p, e, gold, 5)
	check("gold is light and easy", c > 0.4, "%.2f" % c)
	var heavy := load("res://data/weapons/iron_warhammer.tres") as ItemData
	check("a warhammer is not", Pickpocket.chance(p, e, heavy, 1) < c)
	st.awareness[e.get_instance_id()] = 0.3
	check("a watchful mark is harder", Pickpocket.chance(p, e, gold, 5) < c)
	st.awareness.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ok := 0
	for i in 20:
		if Pickpocket.try_take(p, e, gold, 1, rng):
			ok += 1
	check("lifts come off often, not always", ok > 5 and ok < 20, str(ok))
	check("they count, and train the skill", Achievements.count("pickpocket") == ok and (p.get_node("Skills") as Skills).get_xp(&"pickpocket") > 0.0)
	check("planting takes skill 25", not Pickpocket.can_plant(p))
	var opened := Pickpocket.open(p, e)
	check("the pockets open", opened)
	var ui := get_first_node_in_group("container_ui") as ContainerUI
	if ui != null and opened:
		ui._close()
	Pickpocket.caught(p, e)
	check("caught, they know", st.awareness_of(e) >= 1.0 and e.has_meta("wronged_by_player"))
	st.set_sneaking(false)
	e.queue_free()


func t_lockpick() -> void:
	print("-- the lockpicking minigame")
	var inv := p.get_node("Inventory") as Inventory
	inv.add_item(Locks.get_lockpick(), 3)
	var result := [-2]
	check("it starts on a lock", LockpickGame.start(self, inv, 30, func(r: int) -> void: result[0] = r))
	await frames(2)
	var g: LockpickGame = null
	for n in root.get_children():
		if n is LockpickGame:
			g = n
	check("with pins by the lock's level", g != null and g.pins == 2)
	g._pos = g._gap_at
	g.press()
	check("in the gap a pin sets", g.set_pins == 1)
	g._pos = g._gap_at + g._gap
	if g._pos > 1.0:
		g._pos = g._gap_at - g._gap
	var picks := inv.get_count(Locks.get_lockpick())
	g.press()
	check("a miss breaks a pick and drops a pin", inv.get_count(Locks.get_lockpick()) == picks - 1 and g.set_pins == 0)
	g._pos = g._gap_at
	g.press()
	g._pos = g._gap_at
	g.press()
	await frames(2)
	check("all pins set: open", result[0] == Locks.PickResult.OPENED and not paused)
	check("Security widens the gap", LockpickGame.gap_for(10, inv) > LockpickGame.gap_for(90, inv))
	check("it is off by default", not bool(GameSettings.DEFAULTS["lock_minigame"]))
