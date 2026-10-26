extends SceneTree
## Headless tests for stage 6a: sneaking, detection, sneak attacks, crime, bounty and guards. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage6a.gd

const R := "res://data/"

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


func secs(s: float) -> void:
	await frames(int(round(s * 60.0)))


func _run() -> void:
	await process_frame
	await t_stealth()
	await t_crime()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func make_player(parent: Node) -> CharacterBody3D:
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
	head.add_child(Camera3D.new())
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	stats.base_stats["max_health"] = 50000.0
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
	var st := Stealth.new()
	st.name = "Stealth"
	p.add_child(st)
	for ui in [ContainerUI.new(), DialogueUI.new(), BarterUI.new()]:
		ui.name = ui.get_script().get_global_name()
		p.add_child(ui)
	p.add_to_group("player")
	parent.add_child(p)
	return p


func _floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.position = Vector3(0, -0.5, 0)


func _npc(parent: Node3D, pos: Vector3, facing: Vector3, disposition: Enemy.Disposition = Enemy.Disposition.NEUTRAL) -> Enemy:
	var e := Enemy.new()
	e.disposition = disposition
	e.max_health = 400.0
	e.position = pos
	parent.add_child(e)
	e.look_at(e.global_position + facing, Vector3.UP)
	return e


# Awareness after `t` seconds of looking
func _watch(st: Stealth, t: float) -> void:
	var steps := int(t / 0.1)
	for i in steps:
		st.update_awareness(0.1)


func _act(weapon: ItemData) -> Dictionary:
	return {"weapon": weapon, "kind": MeleeCombat.Kind.LIGHT, "dmg_mult": 1.0, "poise_mult": 1.0, "knock_mult": 1.0, "heavy": false, "combo": 0}


# ---------------------------------------------------------------- sneaking

func t_stealth() -> void:
	print("-- sneaking and being seen")
	var world := Node3D.new()
	root.add_child(world)
	_floor(world)
	var p := make_player(world)
	await frames(3)
	var st := p.get_node("Stealth") as Stealth
	p.process_mode = Node.PROCESS_MODE_DISABLED  # the test moves time by hand
	st.process_mode = Node.PROCESS_MODE_DISABLED
	var watcher := _npc(world, Vector3(0, 0, -10), Vector3(0, 0, 1))  # 10 m away, looking at the player
	await frames(3)
	watcher.process_mode = Node.PROCESS_MODE_DISABLED
	_watch(st, 1.5)
	check("standing in plain view, you are seen within a moment", st.is_detected_by(watcher) and st.detection_level() == 2, "%.2f" % st.awareness_of(watcher))
	st.awareness.clear()
	st.set_sneaking(true)
	_watch(st, 4.0)
	check("sneaking 10 m away, you stay hidden", not st.is_detected_by(watcher), "%.2f" % st.awareness_of(watcher))
	check("sneaking makes you slower", st.get_speed_mult() < 0.7)
	p.global_position = Vector3(0, 0, -6.5)
	st.awareness.clear()
	_watch(st, 2.0)
	check("sneaking right up in front of someone gets you seen", st.is_detected_by(watcher))
	# behind them
	st.awareness.clear()
	p.global_position = Vector3(0, 0, -13)
	_watch(st, 3.0)
	check("behind someone, sneaking, you are unseen even close", st.awareness_of(watcher) < Stealth.NOTICED)
	st.set_sneaking(false)
	p.velocity = Vector3(7.5, 0, 0)  # sprinting
	_watch(st, 1.0)
	check("but sprinting behind them is heard", st.is_detected_by(watcher))
	p.velocity = Vector3.ZERO
	# walls
	st.awareness.clear()
	p.global_position = Vector3(0, 0, 0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(6, 4, 0.5)
	wcs.shape = wbox
	wall.add_child(wcs)
	world.add_child(wall)
	wall.position = Vector3(0, 2, -5)
	await frames(2)
	_watch(st, 2.0)
	check("a wall blocks the view", st.awareness_of(watcher) < Stealth.NOTICED)
	wall.queue_free()
	await frames(2)
	# darkness
	var clock := WorldClock.new()
	clock.control_environment = false
	world.add_child(clock)
	clock.set_time(1.0)
	st.forget_light()
	st.awareness.clear()
	_watch(st, 3.0)
	check("at night, 10 m away is too far to be seen", not st.is_detected_by(watcher), "%.2f" % st.awareness_of(watcher))
	clock.set_time(12.0)
	st.forget_light()
	_watch(st, 1.5)
	check("by day, the same spot is in plain view", st.is_detected_by(watcher))

	# sneak attacks
	var sword := load(R + "weapons/iron_sword.tres") as ItemData
	var dagger := load(R + "weapons/iron_dagger.tres") as ItemData
	st.awareness.clear()
	check("an unaware target takes double damage", st.sneak_attack_mult(watcher, sword) == 2.0)
	check("triple with a dagger", st.sneak_attack_mult(watcher, dagger) == 3.0)
	_watch(st, 1.5)
	check("no bonus once they've seen you", st.sneak_attack_mult(watcher, sword) == 1.0)
	var mc := p.get_node("MeleeCombat") as MeleeCombat
	var victim := _npc(world, Vector3(4, 0, 0), Vector3(1, 0, 0), Enemy.Disposition.HOSTILE)
	await frames(2)
	victim.process_mode = Node.PROCESS_MODE_DISABLED
	st.awareness.clear()
	var hp0 := victim.stats.health
	var got_sneak := [false]
	st.sneak_attack.connect(func(_v: Node3D, _m: float) -> void: got_sneak[0] = true, CONNECT_ONE_SHOT)
	mc._deal(_act(sword), victim.combat, victim.global_position + Vector3.UP, p.global_position + Vector3.UP, 10.0, &"melee")
	var sneak_dmg := hp0 - victim.stats.health
	st.awareness[victim.get_instance_id()] = 1.2
	var hp1 := victim.stats.health
	mc._deal(_act(sword), victim.combat, victim.global_position + Vector3.UP, p.global_position + Vector3.UP, 10.0, &"melee")
	var normal_dmg := hp1 - victim.stats.health
	check("a real sneak attack hits twice as hard", got_sneak[0] and absf(sneak_dmg - normal_dmg * 2.0) < 0.5, "%.1f vs %.1f" % [sneak_dmg, normal_dmg])
	victim.queue_free()

	# hostile creatures use it too
	var bandit := _npc(world, Vector3(0, 0, -6), Vector3(0, 0, -1), Enemy.Disposition.HOSTILE)  # facing away
	p.global_position = Vector3.ZERO
	st.set_sneaking(true)
	st.awareness.clear()
	p.process_mode = Node.PROCESS_MODE_INHERIT
	st.process_mode = Node.PROCESS_MODE_INHERIT
	await secs(2.0)
	check("a bandit with its back turned doesn't notice you sneaking", bandit.state != Enemy.State.CHASE and bandit.state != Enemy.State.ATTACK)
	st.set_sneaking(false)
	p.velocity = Vector3(7.5, 0, 0)
	await secs(1.0)
	check("but comes for you when you run", bandit.state == Enemy.State.CHASE or bandit.state == Enemy.State.ATTACK)
	world.queue_free()
	await frames(3)


# ---------------------------------------------------------------- crime

func t_crime() -> void:
	print("-- crime, bounty and guards")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var p := make_player(holder)
	var inv := p.get_node("Inventory") as Inventory
	var st := p.get_node("Stealth") as Stealth
	var s := (load(R + "world/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = s
	holder.add_child(wm)
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)
	var crime := wm.crime
	check("the world has a CrimeManager", crime != null)
	var town := wm.get_nearest_town(p.global_position)

	# ---- theft in a shop
	var keeper: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.work_id != "" and r.inside == r.data.work_id and keeper == null:
			keeper = r
	check("a shopkeeper at work", keeper != null)
	var shop := wm.get_building(keeper.data.work_id)
	await wm.dungeons.enter(shop.id, shop.get_door_position(), 0.0)
	await frames(10)
	var chest: ContainerComponent = null
	for c in wm.dungeons.get_interior_root().find_children("*", "ContainerComponent", true, false):
		if (c as ContainerComponent).owner_id != "":
			chest = c
	check("the shop's chest belongs to someone", chest != null and chest.owner_id == shop.id)
	check("its prompt says Steal", chest.get_prompt().begins_with("Steal from"))
	var cui := p.get_node("ContainerUI") as ContainerUI
	chest.roll_contents()
	var ruby := load(R + "treasure/ruby.tres") as ItemData
	chest.inventory.add_item(ruby, 2)
	st.awareness.clear()
	st.awareness[keeper.node.get_instance_id()] = 0.0
	cui.open(chest)
	cui._take_all()
	cui._close()
	check("unseen theft: no bounty", CrimeManager.get_bounty(town.id) == 0)
	check("but the goods are marked stolen", CrimeManager.stolen_count(inv, ruby) == 2)
	chest.inventory.add_item(ruby, 1)
	st.awareness[keeper.node.get_instance_id()] = 1.2
	cui.open(chest)
	cui._take_all()
	cui._close()
	check("seen stealing: a bounty worth what you took", CrimeManager.get_bounty(town.id) >= ruby.value, str(CrimeManager.get_bounty(town.id)))
	check("the owner likes you less", DialogueState.get_disposition(keeper.data.id, keeper.data.base_disposition) < keeper.data.base_disposition)

	# merchants and fences
	var dlg := p.get_node("DialogueUI") as DialogueUI
	var barter := p.get_node("BarterUI") as BarterUI
	if Barter.merchant_for(shop).will_buy(ruby):
		dlg.open_with(keeper.node)
		dlg.open_barter()
		check("a merchant won't buy stolen goods", barter.sell(ruby)["error"].contains("stolen"))
		barter.close()
		dlg.close()
	var fence_data := (Barter.merchant_for(shop).duplicate() as MerchantData)
	fence_data.buys_stolen = true
	fence_data.buys = PackedStringArray(["all"])
	var fence := Barter.open_shop("t/fence", fence_data, 1)
	fence.gold = 50000
	var sold := Barter.sell(fence, inv, null, ruby, 1, Barter.deal_for(p, 50))
	check("a fence buys them, and the mark goes with them", sold["error"] == "" and CrimeManager.stolen_count(inv, ruby) == 2)
	Barter.close_shop(fence)
	await wm.dungeons.exit()
	await frames(5)
	CrimeManager.set_bounty_raw(town.id, 0)

	# ---- assault and murder, through a real hit
	var mc := p.get_node("MeleeCombat") as MeleeCombat
	var sword := load(R + "weapons/iron_sword.tres") as ItemData
	var folk: Array[TownLife.Resident] = []
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.node != null and is_instance_valid(r.node) and not r.node_inside and r.data.role != NpcData.Role.GUARD:
			folk.append(r)
	check("two townspeople outside to test with", folk.size() >= 2)
	var victim := folk[0].node
	p.global_position = victim.global_position + Vector3(1.5, 0.5, 0)
	await frames(2)
	st.awareness[victim.get_instance_id()] = 1.2
	mc._deal(_act(sword), victim.combat, victim.global_position + Vector3.UP, p.global_position + Vector3.UP, 5.0, &"melee")
	await frames(2)
	check("hitting a townsperson is assault (they always know)", CrimeManager.get_bounty(town.id) == CrimeManager.BOUNTY["assault"], str(CrimeManager.get_bounty(town.id)))
	check("they run", victim.state == Enemy.State.FLEE)
	mc._deal(_act(sword), victim.combat, victim.global_position + Vector3.UP, p.global_position + Vector3.UP, 5.0, &"melee")
	check("hitting them again right away isn't counted twice", CrimeManager.get_bounty(town.id) == CrimeManager.BOUNTY["assault"])
	var victim2 := folk[1].node
	victim2.global_position = victim.global_position + Vector3(4, 0.3, 3)  # towns are big now: bring the witness close
	st.awareness.clear()
	st.awareness[victim2.get_instance_id()] = 1.2
	var before := CrimeManager.get_bounty(town.id)
	mc._deal(_act(sword), victim.combat, victim.global_position + Vector3.UP, p.global_position + Vector3.UP, 99999.0, &"melee")
	await frames(2)
	check("killing someone who did no harm, seen, is murder", victim.is_dead() and CrimeManager.get_bounty(town.id) == before + CrimeManager.BOUNTY["murder"], str(CrimeManager.get_bounty(town.id)))
	check("the witness runs", victim2.state == Enemy.State.FLEE)

	# guards attack a murderer on sight
	var guard: Enemy = null
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.GUARD and r.node != null and is_instance_valid(r.node):
			guard = r.node
	check("there is a guard", guard != null)
	p.global_position = guard.global_position + Vector3(5, 0.5, 0)
	st.awareness[guard.get_instance_id()] = 1.2
	await secs(0.6)
	check("with a murder bounty, guards attack on sight", guard.disposition == Enemy.Disposition.HOSTILE)
	holder.queue_free()
	await frames(3)
	await t_arrest()


func _new_world() -> Dictionary:
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var p := make_player(holder)
	var s := (load(R + "world/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = s
	holder.add_child(wm)
	return {"holder": holder, "player": p, "world": wm}


func _guard_of(wm: WorldManager, town: PlacedPOI) -> Enemy:
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.GUARD and r.node != null and is_instance_valid(r.node) and not r.node.is_dead():
			return r.node
	return null


func t_arrest() -> void:
	print("-- arrest: pay, jail, resist")
	var w := _new_world()
	var wm: WorldManager = w["world"]
	var p: CharacterBody3D = w["player"]
	var inv := p.get_node("Inventory") as Inventory
	var st := p.get_node("Stealth") as Stealth
	var skills := p.get_node("Skills") as Skills
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)
	var town := wm.get_nearest_town(p.global_position)
	var crime := wm.crime
	var ui := crime._ui
	var ruby := load(R + "treasure/ruby.tres") as ItemData

	# pay the fine
	crime.set_bounty(town.id, 60)
	inv.add_item(ruby, 2)
	CrimeManager.add_stolen(ruby, 2)
	Currency.add_gold(inv, 500)
	var guard := _guard_of(wm, town)
	guard.process_mode = Node.PROCESS_MODE_INHERIT
	p.global_position = guard.global_position + Vector3(10, 0.5, 0)
	var waited := 0
	while not ui.is_open() and waited < 400:
		st.awareness[guard.get_instance_id()] = 1.2
		await frames(5)
		waited += 5
	check("a guard who sees you with a bounty comes and stops you", ui.is_open() and paused, "%d frames" % waited)
	check("the window offers to pay, go to jail or resist", ui._pay.text.contains("60") and not ui._pay.disabled and ui._jail.text.contains("1 day"))
	var gold := Currency.get_gold(inv)
	ui.choose("pay")
	await frames(2)
	check("paying clears the bounty and takes the gold", CrimeManager.get_bounty(town.id) == 0 and Currency.get_gold(inv) == gold - 60)
	check("and the stolen goods", inv.get_count(ruby) == 0 and CrimeManager.stolen_ledger().is_empty())
	check("the game goes on", not paused)

	# jail
	crime.set_bounty(town.id, 250)
	skills.add_xp(&"sneak", 5.0)
	skills.add_xp(&"speech", 5.0)
	skills.add_xp(&"athletics", 5.0)
	var day := wm.clock.day
	var res := crime.serve_jail(town, 250)
	await frames(2)
	check("jail lasts a day per 100 gold of bounty", int(res["days"]) == 3 and wm.clock.day == day + 3)
	check("some skill progress is lost", (res["lost"] as PackedStringArray).size() >= 1)
	check("the bounty is gone", CrimeManager.get_bounty(town.id) == 0)
	var gate := town.town.get_gates_world()[0]
	check("you are let out at the town gate", Vector2(p.global_position.x - gate.x, p.global_position.z - gate.z).length() < 15.0)
	await secs(1.0)

	# resist
	wm.clock.set_time(12.0)
	await secs(1.0)
	crime.set_bounty(town.id, 40)
	guard = _guard_of(wm, town)
	p.global_position = guard.global_position + Vector3(2, 0.5, 0)
	waited = 0
	while not ui.is_open() and waited < 400:
		st.awareness[guard.get_instance_id()] = 1.2
		await frames(5)
		waited += 5
	check("stopped again", ui.is_open())
	ui.choose("resist")
	await frames(2)
	check("resisting adds to the bounty and the guards attack", CrimeManager.get_bounty(town.id) == 45 and guard.disposition == Enemy.Disposition.HOSTILE)
	check("bounties are listed per town", CrimeManager.bounties().has(town.id) and CrimeManager.bounties().size() == 1)
	(w["holder"] as Node).queue_free()
	await frames(3)
	await t_trespass_and_defense()


func t_trespass_and_defense() -> void:
	print("-- trespassing, and guards defending the town")
	var w := _new_world()
	var wm: WorldManager = w["world"]
	var p: CharacterBody3D = w["player"]
	var st := p.get_node("Stealth") as Stealth
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)
	var town := wm.get_nearest_town(p.global_position)
	var crime := wm.crime
	var house: BuildingPlot = null
	var shop: BuildingPlot = null
	for b in town.town.buildings:
		if not b.is_public() and b.starts_locked and house == null:
			house = b
		if b.is_public() and shop == null:
			shop = b
	check("an open shop at noon is not closed", not crime.is_closed(shop))
	check("a house kept locked is closed to visitors", crime.is_closed(house))
	wm.clock.set_time(2.0)
	await secs(1.0)
	check("at night everything is closed", crime.is_closed(shop) and crime.is_closed(house))
	wm.clock.set_time(12.0)
	await secs(1.0)
	Locks.set_locked(house.id, false)
	await wm.dungeons.enter(house.id, house.get_door_position(), 0.0)
	await frames(10)
	var root_node := wm.dungeons.get_interior_root()
	var visitor := _npc(root_node, Vector3(0, 0.3, 0), Vector3(0, 0, -1), Enemy.Disposition.FRIENDLY)  # local to the interior
	visitor.display_name = "A Visitor"
	await frames(2)
	st.awareness[visitor.get_instance_id()] = 1.2
	st.process_mode = Node.PROCESS_MODE_DISABLED
	await secs(1.0)
	check("caught inside: first a warning, no bounty yet", CrimeManager.get_bounty(town.id) == 0 and crime._warned_at >= 0.0)
	await secs(10.5)
	check("still there after being told: trespassing", CrimeManager.get_bounty(town.id) == CrimeManager.BOUNTY["trespass"], str(CrimeManager.get_bounty(town.id)))
	st.process_mode = Node.PROCESS_MODE_INHERIT
	CrimeManager.set_bounty_raw(town.id, 0)  # before stepping out, or the guards would stop us
	await wm.dungeons.exit()
	await frames(5)
	check("no arrest waiting outside", not crime._ui.is_open() and not paused)

	# a wolf walks into town
	var guard := _guard_of(wm, town)
	var wolf_data := load(R + "enemies/wolf.tres") as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	p.global_position = guard.global_position + Vector3(0, 0.5, 30)
	var at := guard.global_position + Vector3(8, 0.5, 0)
	var wolf := Population.spawn_enemy(wolf_data, 1, wm, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
	await secs(2.5)
	check("a guard goes for a creature in town", guard.state == Enemy.State.CHASE or guard.state == Enemy.State.ATTACK or wolf.is_dead())
	var waited := 0.0
	while not wolf.is_dead() and waited < 40.0:
		await secs(1.0)
		waited += 1.0
	check("and kills it", wolf.is_dead(), "%.0f s, wolf hp %.0f" % [waited, wolf.stats.health])
	await secs(3.0)
	check("then goes back to the rounds", guard.state != Enemy.State.CHASE and guard.state != Enemy.State.ATTACK and guard.disposition != Enemy.Disposition.HOSTILE)
	(w["holder"] as Node).queue_free()
	await frames(3)
