extends SceneTree
## Alpha 1.24 (immersion): enemy factions and how they get on. On a flat floor with real creatures:
## the table, sides that fight on sight, one side never fighting itself, neutral ones fighting back,
## friends helping, the player's standing, and only your kills lasting.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha124.gd

var passes := 0
var fails := 0
var world: Node3D
var rng := RandomNumberGenerator.new()


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
	t_table()
	await t_on_sight()
	await t_same_side()
	await t_neutral()
	await t_rally()
	await t_spare()
	await t_standing()
	await t_kill_record()
	await t_wildlife()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


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
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	floor_body.add_child(cs)
	world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	await frames(2)


func make(id: String, pos: Vector3, level: int = 5) -> Enemy:
	var dir := "npcs" if ResourceLoader.exists("res://data/npcs/%s.tres" % id) else "enemies"
	var data := load("res://data/%s/%s.tres" % [dir, id]) as EnemyData
	var e := Enemy.create()
	data.apply(e, level, rng)
	e.position = pos
	e.field_of_view = 360.0
	world.add_child(e)
	e.stats.add_modifiers("test_tough", {"max_health": 5000.0})
	e.stats.revive()
	return e


func hit(victim: Enemy, attacker: Node, amount: float = 5.0) -> void:
	var info := DamageInfo.new()
	info.amount = amount
	info.source = attacker
	info.direction = Vector3.FORWARD
	info.hit_position = victim.global_position + Vector3.UP
	victim.combat.take_damage(info)


func t_table() -> void:
	print("-- the table")
	CreatureFactions.refresh()
	var R := CreatureFactions.Rel
	check("bandits and smugglers are friends", CreatureFactions.relation("bandits", "smugglers") == R.FRIENDLY)
	check("bandits and the undead are at war", CreatureFactions.relation("undead", "bandits") == R.HOSTILE)
	check("bandits and beasts leave each other be", CreatureFactions.relation("bandits", "beasts") == R.NEUTRAL)
	check("a side is its own", CreatureFactions.relation("undead", "undead") == R.SAME)
	check("wolves hunt sheep", CreatureFactions.relation("beasts", "livestock") == R.HOSTILE)
	check("the undead fight on sight: bandits among them", CreatureFactions.hostile_to("undead").has("bandits"))
	CreatureFactions.set_relation("bandits", "beasts", R.HOSTILE)
	check("a relation can change during a game", CreatureFactions.relation("beasts", "bandits") == R.HOSTILE and CreatureFactions.hostile_to("bandits").has("beasts"))
	CreatureFactions.set_relation("bandits", "beasts", R.NEUTRAL)
	check("and change back", not CreatureFactions.hostile_to("bandits").has("beasts"))


func t_on_sight() -> void:
	print("-- sides at war fight on sight")
	await reset_world()
	var b := make("bandit", Vector3(-3, 0.2, 0))
	var s := make("skeleton", Vector3(3, 0.2, 0))
	check("a bandit is a bandit", CreatureFactions.of(b) == "bandits", CreatureFactions.of(b))
	check("a skeleton is undead", CreatureFactions.of(s) == "undead", CreatureFactions.of(s))
	var blows := [0]
	b.combat.damaged.connect(func(_i, _a): blows[0] += 1)
	s.combat.damaged.connect(func(_i, _a): blows[0] += 1)
	await secs(2.5)
	check("the bandit goes for the skeleton", b.get_fight_target() == s, str(b.get_fight_target()))
	check("and the skeleton for the bandit", s.get_fight_target() == b, str(s.get_fight_target()))
	for k in 10:
		if blows[0] > 0:
			break
		await secs(1.0)
	check("blows are struck", blows[0] > 0, str(blows[0]))


func t_same_side() -> void:
	print("-- one side never fights itself")
	await reset_world()
	var a := make("bandit", Vector3(-1.5, 0.2, 0))
	var c := make("bandit_thug", Vector3(1.5, 0.2, 0))
	var sm := make("smuggler", Vector3(0, 0.2, 2.5))
	await secs(2.0)
	check("bandits standing together are calm", a.get_fight_target() == null and c.get_fight_target() == null)
	check("and smugglers sit with them", sm.get_fight_target() == null)
	hit(c, a)
	await secs(1.0)
	check("a stray blow from your own side is forgiven", c.get_fight_target() == null, str(c.get_fight_target()))
	hit(sm, a)
	await secs(1.0)
	check("and from a friendly side", sm.get_fight_target() == null, str(sm.get_fight_target()))


func t_neutral() -> void:
	print("-- neutral sides fight back")
	await reset_world()
	var b := make("bandit", Vector3(-2, 0.2, 0))
	var w := make("wolf", Vector3(2, 0.2, 0))
	var w2 := make("wolf", Vector3(30, 0.2, 30))  # far off: not part of it
	await secs(2.0)
	check("a bandit and a wolf leave each other alone", b.get_fight_target() == null and w.get_fight_target() == null)
	hit(w, b)
	await secs(0.5)
	check("hit by accident, the wolf turns on the bandit", w.get_fight_target() == b, str(w.get_fight_target()))
	check("a wolf far away stays out of it", w2.get_fight_target() == null)


func t_rally() -> void:
	print("-- a side looks after its own")
	await reset_world()
	var b1 := make("bandit", Vector3(0, 0.2, 0))
	var b2 := make("bandit", Vector3(4, 0.2, 0))
	var b3 := make("bandit_brute", Vector3(-4, 0.2, 2))
	var w := make("wolf", Vector3(0, 0.2, -4))
	await frames(10)
	hit(b1, w)
	await secs(0.5)
	check("the one bitten fights the wolf", b1.get_fight_target() == w, str(b1.get_fight_target()))
	check("its friends join in", b2.get_fight_target() == w and b3.get_fight_target() == w, "%s %s" % [b2.get_fight_target(), b3.get_fight_target()])


func t_spare() -> void:
	print("-- swings and spells spare their own side")
	await reset_world()
	var b := make("bandit", Vector3(0, 0.2, 0))
	var sm := make("smuggler", Vector3(1, 0.2, 0))
	var w := make("wolf", Vector3(-1, 0.2, 0))
	await frames(5)
	check("a bandit's swing passes through a smuggler", b.combat.spare_body.call(sm))
	check("but not through a wolf", not b.combat.spare_body.call(w))
	check("a bandit's swings can hit other creatures", (b.combat.hit_mask & Enemy.ENEMY_LAYER) != 0)
	check("spells: bandit and smuggler are friends", MagicHit.friendly(b, sm))
	check("spells: bandit and wolf are not", not MagicHit.friendly(b, w))


func t_standing() -> void:
	print("-- your standing with a side")
	await reset_world()
	WorldState.erase_record(CreatureFactions.STANDING_RECORD)
	var s := make("skeleton", Vector3(0, 0.2, 0))
	CreatureFactions.on_player_kill(self, s)
	s.queue_free()  # (the undead would fight the bandit below)
	check("killing the undead: bandits think better of you", CreatureFactions.standing("bandits") == CreatureFactions.STANDING_HELP)
	check("and the undead worse", CreatureFactions.standing("undead") == CreatureFactions.STANDING_HARM)
	CreatureFactions.add_standing(self, "bandits", CreatureFactions.STANDING_TRUCE)
	check("enough of it and bandits leave you be", CreatureFactions.tolerates_player("bandits"))
	var dummy := Node3D.new()
	dummy.add_to_group("player")
	var target := GDScript.new()
	target.source_code = "extends Node
func take_damage(_i) -> float:
	return 0.0
func is_alive() -> bool:
	return true
"
	target.reload()
	var soak := Node.new()
	soak.set_script(target)
	dummy.add_child(soak)
	dummy.set_meta("damageable", soak)
	world.add_child(dummy)
	dummy.position = Vector3(0, 0, 4)
	var b := make("bandit", Vector3(0, 0.2, 0))
	await frames(1)
	await secs(2.0)
	check("a bandit next to you does not attack", b.get_fight_target() == null, str(b.get_fight_target()))
	hit(b, dummy)
	await secs(0.6)
	check("unless you start it", b.get_fight_target() == dummy, str(b.get_fight_target()))
	dummy.queue_free()
	WorldState.erase_record(CreatureFactions.STANDING_RECORD)


func t_kill_record() -> void:
	print("-- only your kills last")
	await reset_world()
	var b := make("bandit", Vector3(-2, 0.2, 0))
	var w := make("wolf", Vector3(2, 0.2, 0))
	w.spawn_key = "test/wolf_a"
	w.stats.remove_modifiers("test_tough")
	w.stats.revive()
	for i in 30:
		if w.is_dead():
			break
		hit(w, b, 50.0)
		await frames(2)
	check("the wolf dies", w.is_dead())
	check("killed by a bandit, it comes back with its place", not WorldState.has_record("kill/test/wolf_a"))
	var w2 := make("wolf", Vector3(5, 0.2, 0))
	w2.spawn_key = "test/wolf_b"
	w2.stats.remove_modifiers("test_tough")
	w2.stats.revive()
	for i in 30:
		if w2.is_dead():
			break
		hit(w2, null, 50.0)  # no source = you (a trap, a fall)
		await frames(2)
	check("killed by you, it stays dead", WorldState.has_record("kill/test/wolf_b"))


# ---------------------------------------------------------------- 1.24.2 wildlife, in the real world

func t_wildlife() -> void:
	print("-- wildlife")
	if world != null:
		world.queue_free()
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(120)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var wl := get_first_node_in_group("wild_life") as WildLife
	var al := get_first_node_in_group("ambient_life") as AmbientLife
	check("the game is up with wildlife", wm != null and p != null and wl != null and al != null)
	if wm == null or p == null or wl == null:
		return
	(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
	wl.enabled = false  # only what the test makes
	for g in wl.groups:
		for e in g["members"]:
			if is_instance_valid(e):
				e.queue_free()
	wl.groups.clear()
	wm.clock.set_time(12.0)
	var lands: Dictionary = wl._data.get("lands", {})
	check("every land has animals", lands.size() >= 12 and lands.has("default"), str(lands.keys()))
	var missing := []
	for land in lands:
		for en in lands[land]:
			if wl._data_for(String(en["kind"])) == null:
				missing.append(en["kind"])
	check("every animal in the tables exists", missing.is_empty(), str(missing))
	# a herd of deer, 30 m off
	var at := p.global_position + Vector3(30, 0, 0)
	at.y = wm.get_height_at(at.x, at.z)
	var herd := wl.spawn({"kind": "deer", "group": [4, 4], "herd": true}, at)
	SpawnQueue.flush()
	await frames(10)
	var members: Array = herd.get("members", [])
	check("a herd of four deer", members.size() == 4 and members.all(func(e): return is_instance_valid(e) and e.is_inside_tree()))
	check("deer are wild game", CreatureFactions.of(members[0]) == "prey" and bool(herd["prey"]))
	check("the others follow the lead animal", members.slice(1).all(func(e): return e.has_meta("follows")))
	# sneaking far off they stay; walk up and they run
	var st := p.get_node_or_null("Stealth") as Stealth
	if st != null:
		st.set_sneaking(true)
	p.global_position = at + Vector3(-45, 1, 0)
	await secs(1.0)
	var fled := members.filter(func(e): return e.state == Enemy.State.FLEE).size()
	check("deer 45 m off don't run", fled <= 1, str(fled))
	if st != null:
		st.set_sneaking(false)
	p.global_position = at + Vector3(-6, 1, 0)
	await secs(1.2)
	fled = members.filter(func(e): return e.state == Enemy.State.FLEE).size()
	check("walk up and they run", fled >= 3, str(fled))
	# a wolf pack hunts deer
	var pack := wl.spawn({"kind": "wolf", "group": [3, 3], "pack": true}, at + Vector3(0, 0, 25))
	SpawnQueue.flush()
	await frames(5)
	var wolves: Array = pack["members"]
	check("a pack has an alpha", wolves[0].has_meta("alpha") and wolves[0].body_scale > wolves[1].body_scale)
	check("wolves and deer are at war", CreatureFactions.relation("beasts", "prey") == CreatureFactions.Rel.HOSTILE)
	# a wild wolf warns before it charges
	var w: Enemy = wolves[1]
	p.global_position = w.global_position + Vector3(12, 1, 0)
	w._target = p
	w._alerted = true
	w._enter_state(Enemy.State.CHASE)
	check("a wild wolf growls before it charges", w._warn_until > w._clock)
	var start := w.global_position
	await secs(0.8)
	check("and stands its ground meanwhile", w.global_position.distance_to(start) < 2.5, "%.1f m" % w.global_position.distance_to(start))
	# small life
	al._spawn(p)
	al._spawn(p)
	await frames(3)
	var crit := get_nodes_in_group("critters")
	check("small life appears around you", crit.size() >= 1, str(crit.size()))
	if not crit.is_empty():
		var c := crit[0] as Critter
		c.take_damage(DamageInfo.new())
		await frames(2)
		check("a hit kills a critter", not is_instance_valid(c) or c.is_queued_for_deletion())
	# legends: once killed, never again
	WorldState.set_record("legend/white_stag", {"day": 1})
	var tries := 0
	var got := {}
	wl._rng.seed = 1
	for i in 200:
		got = wl._maybe_legend("forest", at)
		if not got.is_empty():
			break
		tries += 1
	check("a legend killed never comes back", got.is_empty() or String(got["kind"]) != "white_stag", str(got))
	for g in wl.groups:
		for e in g["members"]:
			if is_instance_valid(e):
				e.queue_free()
	wl.groups.clear()
