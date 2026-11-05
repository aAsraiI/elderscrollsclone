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
		await t_combos()
		await t_rituals()
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


func t_combos() -> void:
	print("-- combos, wards, counterspells, resistances")
	var at := p.global_position + Vector3(0, 0, 6)
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var foe := Population.spawn_enemy(load("res://data/enemies/bandit.tres"), 10, wm, at, RandomNumberGenerator.new())
	await frames(3)
	foe.stats.add_modifiers("test", {"max_health": 5000.0})
	foe.stats.revive()
	var fm := ActiveMagic.of(foe)
	var hp := foe.stats.health
	fm.apply_one({"id": "fire_damage", "mag": 20.0, "dur": 0.0}, p, "t", "spell")
	var first := hp - foe.stats.health
	hp = foe.stats.health
	fm.apply_one({"id": "frost_damage", "mag": 20.0, "dur": 0.0}, p, "t", "spell")
	var second := hp - foe.stats.health
	check("fire then frost hits harder (Thermal Shock)", second > first * 1.3, "%.1f then %.1f" % [first, second])
	check("a combo counts", Achievements.count("combo") >= 1)
	hp = foe.stats.health
	fm.apply_one({"id": "shock_damage", "mag": 20.0, "dur": 0.0}, p, "t", "spell")
	check("one combo per pair", hp - foe.stats.health < second, "%.1f" % (hp - foe.stats.health))
	# counterspell
	fm.apply_one({"id": "silence", "mag": 0.0, "dur": 8.0}, p, "t", "spell")
	check("a counterspell silences", foe.has_meta("silenced_until") and int(foe.get_meta("silenced_until")) > Time.get_ticks_msec())
	foe.queue_free()
	# a ward on the player
	var pm := ActiveMagic.of(p)
	var st := p.get_node("Stats") as Stats
	pm.apply_one({"id": "ward", "mag": 50.0, "dur": 30.0}, p, "t", "spell")
	var php := st.health
	pm.apply_one({"id": "fire_damage", "mag": 30.0, "dur": 0.0}, foe if is_instance_valid(foe) else null, "t", "spell")
	check("a ward soaks up spell harm", absf(st.health - php) < 0.5, "%.1f" % (php - st.health))
	pm.apply_one({"id": "frost_damage", "mag": 40.0, "dur": 0.0}, null, "t", "spell")
	check("until it breaks", st.health < php, "%.1f" % (php - st.health))
	# resistances on the health bar
	var w := Node.new()
	w.set_meta("resists", {"resist_fire": 1.0, "resist_frost": -0.5, "resist_poison": 0.5})
	var txt := CombatFeedback.resist_text(w)
	check("the health bar shows resistances", txt.contains("immune: fire") and txt.contains("weak: frost") and txt.contains("resists: poison"), txt)
	w.free()


func t_rituals() -> void:
	print("-- rituals and research")
	var r := Rituals.of(p)
	var inv := p.get_node("Inventory") as Inventory
	var st := p.get_node("Stats") as Stats
	check("the player can perform rituals", r != null)
	var book := load("res://data/books/ritual_book_ward.tres") as ItemData
	inv.add_item(book, 1)
	check("a ritual book is performed", ItemUse.verb(p, book) == "Perform the ritual")
	check("it needs a circle", r.perform("ward").contains("circle"))
	var chalk := load("res://data/misc/ritual_chalk.tres") as ItemData
	inv.add_item(chalk, 1)
	ItemUse.use(p, chalk)
	await frames(2)
	check("chalk draws a circle", Rituals.in_circle(p) and inv.get_count(chalk) == 0)
	check("and it needs a filled soul gem", r.perform("ward").contains("soul gem"))
	var gem := load(SoulGems.DIR + "common_soul_gem_filled.tres") as ItemData
	inv.add_item(gem, 2)
	st.modify_vital("magicka", 100000.0)
	check("in the circle it begins", r.perform("ward") == "" and r.is_channelling())
	p.velocity = Vector3.ZERO
	await secs(Rituals.RITUAL_SECONDS + 0.5)
	var am := ActiveMagic.of(p)
	check("after the channel it takes hold", not r.is_channelling() and am.has_effect(&"ward"), "channelling %s" % r.is_channelling())
	check("the gem is used, the book kept", inv.get_count(gem) == 1 and inv.get_count(book) == 1)
	r.perform("storm")
	p.global_position += Vector3(3, 0, 0)
	await frames(5)
	check("moving breaks it", not r.is_channelling())
	check("raise the fallen needs the dead", r.finish("raise").contains("no dead"))
	# research
	var open := Rituals.open_research(p)
	check("there are effects to research", not open.is_empty())
	var eid := open[0]
	check("not known before", not (p.get_node("Spellbook") as Spellbook).known_effects().has(eid))
	WorldState.set_record("research", {"ids": [String(eid)]})
	check("researched, the spellmaker can use it", (p.get_node("Spellbook") as Spellbook).known_effects().has(eid))
	check("research is for guild members", Rituals.topics_for(null).is_empty())
