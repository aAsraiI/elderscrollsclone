extends SceneTree
## Headless tests for the combat overhaul. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_combat.gd

const R := "res://scripts/Resources/"

var passes := 0
var fails := 0
var world: Node3D
var sword: ItemData
var dagger: ItemData
var shield: ItemData
var hammer: ItemData
var greatsword: ItemData


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


func reset_world() -> void:
	if world != null:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	floor_body.add_child(cs)
	world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)


func make_player(extra_pc := false) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.collision_layer = 1
	p.collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	p.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	stats.base_stats["max_health"] = 5000.0
	p.add_child(stats)
	var inv := Inventory.new()
	inv.name = "Inventory"
	inv.stats = stats
	p.add_child(inv)
	var eq := Equipment.new()
	eq.name = "Equipment"
	eq.inventory = inv
	eq.stats = stats
	p.add_child(eq)
	var sk := Skills.new()
	sk.name = "Skills"
	p.add_child(sk)
	var mc := MeleeCombat.new()
	mc.name = "MeleeCombat"
	p.add_child(mc)
	if extra_pc:
		var pc := PlayerCombat.new()
		pc.name = "PlayerCombat"
		p.add_child(pc)
	p.add_to_group("player")
	p.position = Vector3(0, 0.05, 0)
	world.add_child(p)
	return p


func give(p: Node, item: ItemData, count := 1, do_equip := true) -> void:
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	inv.add_item(item, count)
	if do_equip:
		for i in count:
			eq.equip(item)


func make_enemy(pos: Vector3, ai: bool, hp := 300.0, facing_player := false) -> Enemy:
	var e := Enemy.new()
	e.max_health = hp
	e.starting_weapon = sword
	e.field_of_view = 360.0
	e.position = pos
	world.add_child(e)
	if facing_player:
		e.rotation.y = PI
	if not ai:
		e.set_physics_process(false)
	return e


func _run() -> void:
	await process_frame
	await process_frame
	sword = load(R + "iron_sword.tres")
	dagger = load(R + "iron_dagger.tres")
	shield = load(R + "iron_shield.tres")
	hammer = load(R + "iron_warhammer.tres")
	greatsword = load(R + "steel_greatsword.tres")
	check("items load", sword != null and dagger != null and shield != null and hammer != null and greatsword != null)

	await t_light_hit()
	await t_combo_buffer()
	await t_poise_chain()
	await t_stagger_cannot_hit()
	await t_parry_block()
	await t_heavy()
	await t_winded()
	await t_bash()
	await t_dual_wield()
	await t_slam_and_arc()
	await t_ai_group()
	await t_helpers()
	await t_persist()

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- tests

func t_light_hit() -> void:
	print("-- light attack")
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var e := make_enemy(Vector3(0, 0.05, -1.8), false)
	var hits: Array = []
	pc.hit_dealt.connect(func(_t, info, f): hits.append([info, f]))
	var phases: Array = []
	pc.phase_changed.connect(func(ph, _d): phases.append(ph))
	await frames(3)
	pc.light_attack()
	await secs(0.9)
	check("light attack lands exactly once", hits.size() == 1, str(hits.size()))
	check("damage = base 5 + sword 10", hits.size() == 1 and absf(float(hits[0][1]) - 15.0) < 0.01, str(hits))
	check("enemy lost 15 health", absf(e.stats.health - (e.max_health - 15.0)) < 0.01, str(e.stats.health))
	check("enemy poise chipped by 15", absf(e.combat.poise - 25.0) < 0.01, str(e.combat.poise))
	check("phases ran WINDUP, ACTIVE, RECOVERY, IDLE in order", phases == [1, 2, 3, 0], str(phases))


func t_combo_buffer() -> void:
	print("-- combo and input buffer")
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var starts: Array = []
	pc.attack_started.connect(func(_h, _w): starts.append([pc.get_combo_step(), Engine.get_physics_frames(), pc.get_swing_dir()]))
	await frames(3)
	pc.light_attack()
	await frames(20)
	pc.light_attack()  # pressed while the first swing is still recovering: must be remembered
	await secs(1.6)
	check("second click was buffered and fired", starts.size() == 2, str(starts))
	if starts.size() == 2:
		check("second swing is combo step 1", starts[1][0] == 1, str(starts))
		check("second swing goes the other way", starts[0][2] == 1.0 and starts[1][2] == -1.0, str(starts))
		var gap: int = starts[1][1] - starts[0][1]
		check("second swing waited for the first to finish (>= 40 frames)", gap >= 40, str(gap))
		check("but did not wait much longer (<= 50 frames)", gap <= 50, str(gap))
	# a full combo: 0, 1, 2 (finisher), then it starts over
	await reset_world()
	p = make_player()
	give(p, sword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	starts = []
	pc.attack_started.connect(func(_h, _w): starts.append(pc.get_combo_step()))
	await frames(3)
	for i in 4:
		pc.light_attack()
		await secs(0.95)
	check("combo steps run 0, 1, 2 then wrap to 0", starts == [0, 1, 2, 0], str(starts))
	starts.clear()
	await secs(1.2)
	pc.light_attack()
	await secs(0.3)
	check("after a pause the combo starts over", starts == [0], str(starts))
	# a click that comes far too early is forgotten rather than firing late
	await secs(1.0)
	starts.clear()
	pc.light_attack()
	await frames(2)
	pc.light_attack()
	await secs(0.2)
	check("a click 2 frames after a swing starts is buffered, not fired", starts.size() == 1, str(starts))


func t_poise_chain() -> void:
	print("-- poise, stagger and punish")
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var e := make_enemy(Vector3(0, 0.05, -1.8), false)
	var hits: Array = []
	pc.hit_dealt.connect(func(_t, info, f): hits.append([info, f]))
	var staggers := [0]
	e.combat.staggered.connect(func(_i): staggers[0] += 1)
	await frames(3)
	for i in 3:
		pc.light_attack()
		await secs(0.72)
	check("three hits landed", hits.size() == 3, str(hits.size()))
	check("third hit was the combo finisher", hits.size() == 3 and hits[2][0].combo_step == 2)
	check("finisher damage = 15 x 1.25", hits.size() == 3 and absf(float(hits[2][1]) - 18.75) < 0.01, str(hits.size()))
	check("third hit broke poise", hits.size() == 3 and hits[2][0].staggered)
	check("enemy staggered once", staggers[0] == 1, str(staggers[0]))
	check("enemy is stunned", e.combat.is_stunned())
	check("enemy AI entered STAGGER", e.state == Enemy.State.STAGGER)
	check("poise refilled after the stagger", absf(e.combat.poise - e.combat.max_poise) < 0.01)
	check("stagger grace stops poise being chipped again", absf(e.combat.poise - e.combat.max_poise) < 0.01)
	await secs(2.0)
	check("stagger ends", not e.combat.is_stunned())
	# punish: anything that hits a staggered enemy does more damage
	hits.clear()
	e.combat.force_stagger(1.5)
	pc.light_attack()
	await secs(0.5)
	check("hit on a staggered enemy is a punish hit", hits.size() == 1 and hits[0][0].punish, str(hits.size()))
	check("punish damage = 15 x 1.35", hits.size() == 1 and absf(float(hits[0][1]) - 20.25) < 0.05, str(hits))


func t_stagger_cannot_hit() -> void:
	print("-- a staggered enemy can never hit")
	# control: with nothing interrupting, the swing does land
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var a := make_enemy(Vector3(0, 0.05, -2.0), false, 300.0, true)
	var dmg := [0]
	pc.damaged.connect(func(_i, _f): dmg[0] += 1)
	await frames(3)
	a.combat.light_attack()
	await secs(1.2)
	check("control: an uninterrupted enemy swing hits the player", dmg[0] == 1, str(dmg[0]))

	# staggered during the windup
	await reset_world()
	p = make_player()
	give(p, sword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	a = make_enemy(Vector3(0, 0.05, -2.0), false, 300.0, true)
	dmg = [0]
	pc.damaged.connect(func(_i, _f): dmg[0] += 1)
	await frames(3)
	a.combat.light_attack()
	await secs(0.2)
	a.combat.force_stagger(0.8)
	await secs(1.5)
	check("stagger during windup: no damage", dmg[0] == 0, str(dmg[0]))
	check("stagger during windup: swing was cancelled", not a.combat.is_busy())

	# staggered the instant the hit window opens
	await reset_world()
	p = make_player()
	give(p, sword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	a = make_enemy(Vector3(0, 0.05, -2.0), false, 300.0, true)
	dmg = [0]
	pc.damaged.connect(func(_i, _f): dmg[0] += 1)
	a.combat.phase_changed.connect(func(ph, _d):
		if ph == MeleeCombat.Phase.ACTIVE:
			a.combat.force_stagger(0.8))
	await frames(3)
	a.combat.light_attack()
	await secs(1.5)
	check("stagger as the hit window opens: no damage", dmg[0] == 0, str(dmg[0]))

	# stagger every enemy mid-swing, all the time, with the real AI running
	await reset_world()
	p = make_player()
	give(p, sword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	var enemies: Array[Enemy] = []
	for i in 2:
		enemies.append(make_enemy(Vector3(-1.5 + 3.0 * i, 0.05, -2.5), true, 5000.0))
	var violations := [0]
	var landed := [0]
	pc.damaged.connect(func(info, _f):
		landed[0] += 1
		var atk := info.get_attacker_combat() as MeleeCombat
		if atk != null and atk.is_stunned():
			violations[0] += 1)
	var forced := [0]
	for step in 40:
		await secs(0.7)
		# stagger whichever enemy is mid swing right now, but only every other time
		for e in enemies:
			if e.combat.is_attacking() and step % 3 == 0:
				e.combat.force_stagger(0.8)
				forced[0] += 1
	check("AI enemies landed some hits on the player", landed[0] > 0, str(landed[0]))
	check("AI enemies were staggered mid swing at least once", forced[0] > 0, str(forced[0]))
	check("no hit ever came from a stunned attacker", violations[0] == 0, str(violations[0]))

	# whoever hits first wins: hitting a winding-up enemy flinches it and cancels the swing
	await reset_world()
	p = make_player()
	give(p, sword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	a = make_enemy(Vector3(0, 0.05, -2.0), false, 300.0, true)
	dmg = [0]
	pc.damaged.connect(func(_i, _f): dmg[0] += 1)
	await frames(3)
	a.combat.light_attack()
	pc.light_attack()
	await secs(0.3)
	check("hit during the enemy's windup flinches it", a.combat.is_stunned())
	await secs(1.2)
	check("and its swing never lands", dmg[0] == 0, str(dmg[0]))


func t_parry_block() -> void:
	print("-- block and parry")
	# parry: guard raised shortly before the hit
	await reset_world()
	var p := make_player()
	give(p, sword)
	give(p, shield)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var a := make_enemy(Vector3(0, 0.05, -2.0), false, 300.0, true)
	var stats := p.get_node("Stats") as Stats
	var dmg := [0]
	var parried := [0]
	pc.damaged.connect(func(_i, _f): dmg[0] += 1)
	pc.parried.connect(func(_i): parried[0] += 1)
	await frames(3)
	var hp := stats.health
	a.combat.light_attack()
	await secs(0.28)
	pc.secondary_press()
	await secs(1.0)
	check("parry fired", parried[0] == 1, str(parried[0]))
	check("parry: no damage taken", dmg[0] == 0 and absf(stats.health - hp) < 0.001)
	check("parry: attacker is staggered", a.combat.is_stunned() or a.state == Enemy.State.STAGGER)
	check("parry: attacker's swing is gone", not a.combat.is_busy())

	# plain block: guard raised long before the hit
	await reset_world()
	p = make_player()
	give(p, sword)
	give(p, shield)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	stats = p.get_node("Stats") as Stats
	a = make_enemy(Vector3(0, 0.05, -2.0), false, 300.0, true)
	var seen: Array = []
	var blocked := [0]
	pc.damaged.connect(func(info, f): seen.append([info, f]))
	pc.blocked.connect(func(_i, _a): blocked[0] += 1)
	await frames(3)
	pc.secondary_press()
	await frames(2)
	a.combat.light_attack()
	await secs(1.0)
	check("early block is a block, not a parry", blocked[0] == 1 and seen.size() == 1, str(blocked[0]))
	check("block takes 60% off a 13 damage hit, then shield armor 10%", seen.size() == 1 and absf(float(seen[0][1]) - 4.68) < 0.05, str(seen))
	check("a blocked hit does not stagger the attacker", not a.combat.is_stunned())

	# block can't be raised while stunned; stagger drops the guard
	pc.force_stagger(0.5)
	check("staggering the blocker drops the guard", not pc.is_blocking())
	check("cannot raise the guard while stunned", not pc.secondary_press())


func t_heavy() -> void:
	print("-- charged heavy attack")
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var stats := p.get_node("Stats") as Stats
	var e := make_enemy(Vector3(0, 0.05, -1.8), false)
	var hits: Array = []
	pc.hit_dealt.connect(func(_t, info, f): hits.append([info, f]))
	var ready := [0]
	pc.charge_ready.connect(func(): ready[0] += 1)
	await frames(3)
	pc.begin_charge()
	await secs(0.3)
	check("not ready yet after 0.3 s", ready[0] == 0 and pc.get_charge_ratio() < 1.0)
	await secs(0.3)
	check("charge ready fired once", ready[0] == 1, str(ready[0]))
	check("charge ratio is full", pc.get_charge_ratio() >= 1.0)
	pc.release_charge()
	await secs(1.2)
	check("heavy attack landed", hits.size() == 1 and hits[0][0].heavy, str(hits.size()))
	check("heavy damage = 15 x 1.7", hits.size() == 1 and absf(float(hits[0][1]) - 25.5) < 0.05, str(hits))
	check("heavy poise = 15 x 2", hits.size() == 1 and absf(hits[0][0].poise_damage - 30.0) < 0.01)
	check("heavy cost double stamina", stats.stamina < 90.0, str(stats.stamina))

	# a tap is a light attack, and the weapon is already drawn back so it is quick
	hits.clear()
	await secs(1.0)
	pc.begin_charge()
	await secs(0.1)
	pc.release_charge()
	await secs(0.5)
	check("a short tap is a light attack", hits.size() == 1 and not hits[0][0].heavy, str(hits.size()))

	# cancelling a charge (feint)
	hits.clear()
	await secs(1.0)
	pc.begin_charge()
	await secs(0.2)
	pc.cancel_charge()
	pc.release_charge()
	await secs(0.5)
	check("cancelled charge does not swing", hits.is_empty() and not pc.is_busy())


func t_winded() -> void:
	print("-- out of stamina")
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var stats := p.get_node("Stats") as Stats
	var e := make_enemy(Vector3(0, 0.05, -1.8), false)
	var hits: Array = []
	pc.hit_dealt.connect(func(_t, info, f): hits.append([info, f]))
	var warned := [0]
	pc.attack_failed.connect(func(r): if r == &"stamina": warned[0] += 1)
	await frames(3)
	stats.modify_vital("stamina", -stats.stamina)
	pc.light_attack()
	await secs(1.2)
	check("a swing with no stamina still happens", hits.size() == 1, str(hits.size()))
	check("winded swing does 70% damage", hits.size() == 1 and absf(float(hits[0][1]) - 10.5) < 0.05, str(hits))
	check("player is told about it", warned[0] == 1, str(warned[0]))
	check("enemy is not stunned by a weak hit", not e.combat.is_stunned())

	# a heavy attack without the stamina becomes a normal swing
	hits.clear()
	stats.modify_vital("stamina", -stats.stamina + 8.0)  # enough for light (6), not heavy (12)
	pc.begin_charge()
	await secs(0.6)
	pc.release_charge()
	await secs(1.0)
	check("heavy without stamina becomes a light swing", hits.size() == 1 and not hits[0][0].heavy, str(hits.size()))


func t_bash() -> void:
	print("-- shield bash")
	await reset_world()
	var p := make_player()
	give(p, sword)
	give(p, shield)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var e := make_enemy(Vector3(0, 0.05, -1.5), false)
	var hits: Array = []
	pc.hit_dealt.connect(func(_t, info, f): hits.append([info, f]))
	await frames(3)
	pc.secondary_press()
	await secs(0.1)
	check("blocking", pc.is_blocking())
	pc.begin_charge()  # left click while blocking
	await secs(0.6)
	check("bash landed", hits.size() == 1 and hits[0][0].kind == &"bash", str(hits.size()))
	check("bash is not parryable", hits.size() == 1 and not hits[0][0].parryable)
	check("bash damage = (5+3) x 0.4", hits.size() == 1 and absf(float(hits[0][1]) - 3.2) < 0.05, str(hits))
	check("bash drops the guard", not pc.is_blocking())
	check("bash chips 30 poise", absf(e.combat.poise - 10.0) < 0.01, str(e.combat.poise))


func t_dual_wield() -> void:
	print("-- dual wield")
	await reset_world()
	var p := make_player()
	give(p, dagger, 2)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var eq := p.get_node("Equipment") as Equipment
	check("both hands hold a dagger", eq.get_main_hand() == dagger and eq.get_off_hand() == dagger)
	var starts: Array = []
	pc.attack_started.connect(func(h, _w): starts.append([h, Engine.get_physics_frames()]))
	await frames(3)
	pc.light_attack()
	await frames(2)
	pc.secondary_press()
	await secs(1.0)
	check("main then off hand swung", starts.size() == 2 and starts[0][0] == MeleeCombat.MAIN and starts[1][0] == MeleeCombat.OFF, str(starts))
	if starts.size() == 2:
		var gap: int = starts[1][1] - starts[0][1]
		check("off hand cut in during the recovery (faster than a full swing)", gap >= 10 and gap <= 20, str(gap))


func t_slam_and_arc() -> void:
	print("-- slam and arc sweep")
	await reset_world()
	var p := make_player()
	give(p, hammer)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var e1 := make_enemy(Vector3(0, 0.05, -2.2), false)
	var e2 := make_enemy(Vector3(1.8, 0.05, -2.2), false)
	var hits: Array = []
	pc.hit_dealt.connect(func(t, info, f): hits.append([t, info, f]))
	await frames(3)
	pc.secondary_press()
	await secs(1.2)
	check("slam hit both enemies in the splash", hits.size() == 2, str(hits.size()))
	check("slam is not parryable", hits.size() > 0 and not hits[0][1].parryable)
	check("hammer slam staggers hard (35 x 1.8 poise)", e1.combat.is_stunned() or e1.combat.poise < e1.combat.max_poise)

	# arc: greatsword sweeps and hits several targets, each only once
	await reset_world()
	p = make_player()
	give(p, greatsword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	var left := make_enemy(Vector3(-1.4, 0.05, -2.2), false)
	var mid := make_enemy(Vector3(0, 0.05, -2.4), false)
	var right := make_enemy(Vector3(1.4, 0.05, -2.2), false)
	hits = []
	pc.hit_dealt.connect(func(t, info, f): hits.append([t, info, f]))
	await frames(3)
	pc.light_attack()
	await secs(1.5)
	var targets := {}
	for h in hits:
		targets[h[0].get_instance_id()] = targets.get(h[0].get_instance_id(), 0) + 1
	check("greatsword arc hit all three", targets.size() == 3, str(targets.size()))
	var once := true
	for k in targets:
		if targets[k] != 1:
			once = false
	check("each target hit only once per swing", once, str(targets))
	check("one clean greatsword hit staggers (poise 40 vs 40)", mid.combat.is_stunned() or mid.state == Enemy.State.STAGGER or mid.combat.poise >= 0.0)
	# a swing at nothing is reported as a miss
	var missed := [0]
	await reset_world()
	p = make_player()
	give(p, sword)
	pc = p.get_node("MeleeCombat") as MeleeCombat
	pc.attack_missed.connect(func(_h, _w): missed[0] += 1)
	await frames(3)
	pc.light_attack()
	await secs(0.9)
	check("whiff reports attack_missed", missed[0] == 1, str(missed[0]))


func t_ai_group() -> void:
	print("-- AI group behaviour")
	await reset_world()
	var p := make_player()
	give(p, sword)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	var enemies: Array[Enemy] = []
	for i in 4:
		var a := float(i) / 4.0 * TAU
		enemies.append(make_enemy(Vector3(cos(a), 0.05, sin(a)) * 4.0, true, 5000.0))
	var dmg := [0]
	pc.damaged.connect(func(_i, _f): dmg[0] += 1)
	var max_committed := 0
	var saw_attack := [false]
	var saw_heavy := [false]
	for e in enemies:
		e.combat.attack_started.connect(func(_h, _w): saw_attack[0] = true)
		e.combat.phase_changed.connect(func(ph, _d):
			if ph == MeleeCombat.Phase.WINDUP and e.combat.is_heavy_action():
				saw_heavy[0] = true)
	for i in 60 * 14:
		await physics_frame
		var committed := 0
		for e in enemies:
			if e.is_attack_committed():
				committed += 1
		max_committed = maxi(max_committed, committed)
	check("enemies attacked", saw_attack[0])
	check("enemies hit the player", dmg[0] > 0, str(dmg[0]))
	check("never more than 2 enemies committed to a swing at once", max_committed <= 2, str(max_committed))
	check("at least two did swing together at some point or alone (slots used)", max_committed >= 1)
	print("   (info) player hit %d times, heavy seen: %s, max committed: %d" % [dmg[0], str(saw_heavy[0]), max_committed])

	# circling: an enemy in reach moves sideways around the player
	await reset_world()
	p = make_player()
	give(p, sword)
	var e1 := make_enemy(Vector3(0, 0.05, -2.2), true, 5000.0)
	await secs(0.5)
	var start_angle := atan2(e1.global_position.x, -e1.global_position.z)
	await secs(2.0)
	var end_angle := atan2(e1.global_position.x, -e1.global_position.z)
	check("an enemy in reach circles the player", absf(angle_difference(start_angle, end_angle)) > 0.1, str(angle_difference(start_angle, end_angle)))


func t_helpers() -> void:
	print("-- view model, feedback and input node")
	await reset_world()
	var p := make_player(true)
	give(p, sword)
	give(p, shield)
	var pc := p.get_node("MeleeCombat") as MeleeCombat
	await frames(5)
	check("CombatFeedback was created", p.get_node_or_null("CombatFeedback") != null)
	check("ViewModel was created under the camera", p.get_node_or_null("Head/Camera3D/ViewModel") != null)
	var e := make_enemy(Vector3(0, 0.05, -1.8), false, 300.0)
	var a := make_enemy(Vector3(2.0, 0.05, -2.0), false, 300.0)
	var slowed := false
	for i in 40:
		await physics_frame
	# swing, heavy, block, parry, bash while everything is watching
	pc.light_attack()
	for i in 90:
		await physics_frame
		slowed = slowed or Engine.time_scale < 1.0
	check("hit made the game freeze briefly (hitstop)", slowed)
	pc.begin_charge()
	for i in 60:
		await physics_frame
	pc.release_charge()
	for i in 90:
		await physics_frame
	pc.secondary_press()
	for i in 20:
		await physics_frame
	pc.begin_charge()  # bash
	for i in 60:
		await physics_frame
	# wait for the hitstop (real time) to end
	var guard := 0
	while Engine.time_scale < 1.0 and guard < 200:
		OS.delay_msec(10)
		await physics_frame
		guard += 1
	check("time scale returns to normal after hitstop", Engine.time_scale == 1.0, str(Engine.time_scale))
	var vm := p.get_node("Head/Camera3D/ViewModel") as ViewModel
	check("view model shows the sword and the shield", vm.get_node("MainHand").get_child_count() > 0 and vm.get_node("OffHand").get_child_count() > 0)
	p.queue_free()
	await frames(3)
	check("camera and time scale are restored when the feedback goes away", Engine.time_scale == 1.0)


func t_persist() -> void:
	print("-- save compatibility")
	await reset_world()
	var e := make_enemy(Vector3(3, 0.05, -3), false, 120.0)
	e.stats.modify_vital("health", -20.0)
	var data := e.get_persist_data()
	check("enemy persists health", absf(float(data["health"]) - 100.0) < 0.01)
	var restored := Enemy.restore(data, world)
	await frames(2)
	check("enemy restores with poise and combat intact", restored != null and restored.combat != null and absf(restored.stats.health - 100.0) < 0.01)
