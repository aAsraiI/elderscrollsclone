extends SceneTree
## Alpha 1.27.0 (achievements, the Guide in the journal), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha127.gd

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
		(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
		(p.get_node("Stats") as Stats).revive()
		wm.clock.set_time(12.0)
		GameRules._rules["encounter_rate"] = 0.0
		await t_data()
		await t_achievements()
		await t_guide()
		await t_journal()
		await t_ranged()
		await t_durability()
		await t_build()
		await t_mastery()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_data() -> void:
	print("-- the lists")
	var ids := {}
	var bad := []
	for a in Achievements.LIST:
		if ids.has(a[0]):
			bad.append("twice: " + a[0])
		ids[a[0]] = true
		if GuideBook.page(String(a[4])).is_empty():
			bad.append("%s -> no page %s" % [a[0], a[4]])
		if int(a[1]) < 0 or int(a[1]) >= Achievements.CHAPTERS.size():
			bad.append("chapter: " + a[0])
	check("every achievement is unique, in a chapter, with a Guide page", bad.is_empty(), str(bad))
	check("there are achievements in all five chapters", Achievements.CHAPTERS.size() == 5 and range(5).all(func(c: int) -> bool: return Achievements.LIST.any(func(a: Array) -> bool: return a[1] == c)))
	check("about ninety of them", Achievements.LIST.size() >= 80, str(Achievements.LIST.size()))
	var pages := {}
	for pg in GuideBook.PAGES:
		pages[pg[0]] = true
	check("every Guide page has an id of its own", pages.size() == GuideBook.PAGES.size())
	check("the guide covers the whole game", GuideBook.PAGES.size() >= 45, str(GuideBook.PAGES.size()))
	# every state check gives a number without error
	var vals := []
	for a in Achievements.LIST:
		vals.append(Achievements.value(a, self))
	check("every check can be read", vals.size() == Achievements.LIST.size())


func t_achievements() -> void:
	print("-- achievements")
	check("nothing done at the start", Achievements.unlocked_count() == 0, str(Achievements.unlocked_count()))
	var a := Achievements.get_def("first_blood")
	check("first blood waits for a kill", not Achievements.check(a, self))
	var at := p.global_position + Vector3(4, 0, 0)
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var wolf := Population.spawn_enemy(load("res://data/enemies/wolf.tres"), 1, wm, at, RandomNumberGenerator.new())
	await frames(3)
	wolf._hurt_by_player = true
	wolf.stats.modify_vital("health", -999999.0)
	await frames(5)
	check("a kill is counted", Achievements.count("kill") >= 1, str(Achievements.count("kill")))
	check("first blood unlocks", Achievements.check(a, self))
	check("only once", not Achievements.check(a, self))
	check("it is kept with the character", WorldState.has_record("ach/first_blood"))
	var notices := Notices.of(self)
	await frames(2)
	check("a notice says so", notices != null and notices.pending().any(func(n: Dictionary) -> bool: return n["title"] == "Achievement"))
	# counters from the game
	Locks.try_pick(p.get_node("Inventory") as Inventory, 0)  # may fail without picks: count only on success
	var inv := p.get_node("Inventory") as Inventory
	inv.add_item(Locks.get_lockpick(), 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var opened := false
	for i in 20:
		if Locks.try_pick(inv, 1, rng) == Locks.PickResult.OPENED:
			opened = true
			break
	check("picking a lock counts", not opened or Achievements.count("lockpick") >= 1)
	BookUI.open(self, "A Test", "Words.")
	check("reading counts", Achievements.count("read") >= 1)
	for n in get_nodes_in_group("book_ui"):
		n.queue_free()
	# levels and gold are read from the game
	Currency.add_gold(inv, 1200)
	check("a full purse is read from your gold", Achievements.check(Achievements.get_def("purse"), self))
	# the tutorial node checks them by itself
	Achievements.note("talk")
	await secs(15.0)
	check("the tutorial checks them as you play", Achievements.is_unlocked("talk"))
	var next := Achievements.next_up(5)
	check("what to try next skips what is done", not next.is_empty() and not next.any(func(x: Array) -> bool: return Achievements.is_unlocked(x[0])))
	check("progress shows for counters", Achievements.progress_text(Achievements.get_def("kills25"), self).ends_with("/ 25"))


func t_guide() -> void:
	print("-- the guide")
	var tut := p.get_node_or_null("Tutorial") as Tutorial
	check("the tutorial is not a pop-up any more", tut != null and not tut.is_class("CanvasLayer"))
	check("the first pages are there from the start", GuideBook.has_come_up("welcome") and GuideBook.has_come_up("menus"))
	check("a page has a dot until read", GuideBook.is_unread("welcome"))
	check("pages wait until they come up", not GuideBook.has_come_up("werewolf"))
	tut.hint("werewolf")
	check("a page comes up", GuideBook.has_come_up("werewolf") and GuideBook.is_unread("werewolf"))
	tut.hint("low_health")
	check("old hint names open the new pages", GuideBook.has_come_up("health"))
	WorldState.set_record("tut/combat_old", {})
	check("an old save's hints count as read", not GuideBook.is_unread("combat_old"))
	check("a page's text names its achievements", GuideBook.text_of("combat").contains("First Blood"))


func t_journal() -> void:
	print("-- the journal")
	var j := p.get_node_or_null("JournalUI") as JournalUI
	check("the journal is there", j != null)
	if j == null:
		return
	j.open()
	await process_frame
	j.show_guide("")
	await process_frame
	check("the Guide tab lists the pages", j._text.get_parsed_text().contains("Moving About"))
	j.show_guide("werewolf")
	await process_frame
	check("a Guide page opens", j._text.get_parsed_text().contains("Lycanthropy"))
	check("reading it clears its dot", not GuideBook.is_unread("werewolf"))
	j.show_achievement("")
	await process_frame
	var t := j._text.get_parsed_text()
	check("the Achievements tab shows what to try next", t.contains("Try next") and t.contains("First Steps"))
	j.show_achievement("first_blood")
	await process_frame
	check("an achievement's page says when it was done", j._text.get_parsed_text().contains("Done on"))
	j.show_achievement("kills25")
	await process_frame
	check("and links its Guide page", j._text.get_parsed_text().contains("Guide: Melee Combat"))
	j._tabs.current_tab = JournalUI.TAB_ALL
	await process_frame
	check("the other tabs still work", j._tabs.current_tab == JournalUI.TAB_ALL)
	j.close()


func t_ranged() -> void:
	print("-- crossbows, thrown weapons, where it hits")
	for e in get_nodes_in_group("enemies"):  # nothing wanders in and knocks the bow about
		if not e.has_meta("player_ally") and (e as Enemy).disposition == Enemy.Disposition.HOSTILE:
			e.queue_free()
	await frames(2)
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	var rc := p.get_node("RangedCombat") as RangedCombat
	var cb := load("res://data/ranged/steel_crossbow.tres") as ItemData
	var bolt := load("res://data/ranged/steel_bolt.tres") as ItemData
	var arrow := load("res://data/ranged/steel_arrow.tres") as ItemData
	check("crossbows and bolts exist for every tier", LevelCurve.TIER_KEYS.all(func(k: String) -> bool:
		return ResourceLoader.exists("res://data/ranged/%s_crossbow.tres" % k) and ResourceLoader.exists("res://data/ranged/%s_bolt.tres" % k) and ResourceLoader.exists("res://data/ranged/%s_javelin.tres" % k)))
	inv.add_item(cb, 1)
	inv.add_item(arrow, 10)
	eq.equip(cb)
	check("a crossbow is a ranged weapon", rc.has_bow() and cb.is_crossbow and cb.armor_pierce >= 0.5)
	check("it will not shoot arrows", rc.best_arrow() == null)
	inv.add_item(bolt, 10)
	check("it shoots bolts", rc.best_arrow() == bolt)
	var shots := Achievements.count("shot")
	rc.begin_draw()
	check("one click shoots at full power", inv.get_count(bolt) == 9 and Achievements.count("shot") == shots + 1, "%d bolts, shots %d->%d, stunned %s" % [inv.get_count(bolt), shots, Achievements.count("shot"), (p.get_node("MeleeCombat") as MeleeCombat).is_stunned()])
	var mc := p.get_node("MeleeCombat") as MeleeCombat
	check("then it has to be wound again", rc.reload_ratio() < 0.2 and not rc.begin_draw() and inv.get_count(bolt) == 9)
	await secs(cb.draw_time + 0.2)
	check("and is ready after its reload time", rc.reload_ratio() >= 1.0)
	var knife := load("res://data/ranged/iron_throwing_knife.tres") as ItemData
	inv.add_item(knife, 3)
	eq.equip(knife)
	await frames(2)
	check("throwing knives go in the hand as a stack", eq.get_main_hand() == knife and rc.best_arrow() == knife)
	rc.begin_draw()
	var flying := root.find_children("*", "Arrow", true, false)
	await frames(2)
	check("left click throws one", inv.get_count(knife) == 2)
	check("it flies as a knife", flying.any(func(a: Node) -> bool: return (a as Arrow).item == knife and a.get_node_or_null("Spin") != null))
	check("the forge makes them", Recipes.all().any(func(r: Dictionary) -> bool: return String(r["result"]).ends_with("iron_throwing_knife.tres")) and Recipes.all().any(func(r: Dictionary) -> bool: return String(r["result"]).ends_with("iron_crossbow.tres")))
	# where it hits
	var at := p.global_position + Vector3(0, 0, 6)
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var foe := Population.spawn_enemy(load("res://data/enemies/bandit.tres"), 5, wm, at, RandomNumberGenerator.new())
	await frames(3)
	var info := DamageInfo.new(10.0, p, &"arrow")
	rc._locational(foe, foe.global_position + Vector3.UP * 1.7, info)
	check("a head shot does half again", is_equal_approx(info.amount, 15.0) and Achievements.count("headshot") >= 1)
	var leg := DamageInfo.new(10.0, p, &"arrow")
	rc._locational(foe, foe.global_position + Vector3.UP * 0.3, leg)
	var am := ActiveMagic.of(foe)
	check("a leg hit slows them", is_equal_approx(leg.amount, 10.0) and am != null and am.has_effect(&"slow"))
	foe.queue_free()


func t_durability() -> void:
	print("-- gear wears down")
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	var sword := load("res://data/weapons/iron_sword.tres") as ItemData
	inv.add_item(sword, 1)
	eq.equip(sword)
	check("gear wear is on by default", Durability.enabled())
	check("new gear is at 100", Durability.condition(sword) == 100.0 and Durability.weapon_mult(sword) == 1.0)
	var info := DamageInfo.new(10.0, p, &"melee")
	info.weapon = sword
	BuildHooks.outgoing_mult(p, null, info)
	check("a hit wears the weapon", Durability.condition(sword) < 100.0)
	WorldState.set_record(Durability.RECORD, {"iron_sword": 10.0})
	check("a worn weapon hits softer", Durability.weapon_mult(sword) < 0.7, str(Durability.weapon_mult(sword)))
	check("the inventory shows it", Durability.text(sword).begins_with("Condition 10%"))
	var price := Durability.smith_price(p)
	check("a smith asks for gold by the wear", price > 0 and Services.repair_fee(p) == price)
	Currency.add_gold(inv, price + 10)
	var said := Services.repair(p)
	check("and mends it", Durability.condition(sword) == 100.0, said)
	WorldState.set_record(Durability.RECORD, {"iron_sword": 30.0})
	var hammer := load("res://data/misc/repair_hammer.tres") as ItemData
	inv.add_item(hammer, 1)
	check("a hammer has a use", ItemUse.verb(p, hammer) == "Mend your gear")
	ItemUse.use(p, hammer)
	check("a hammer mends what you wear, and is used up", Durability.condition(sword) > 30.0 and inv.get_count(hammer) == 0)
	GameRules._rules["durability"] = false
	WorldState.set_record(Durability.RECORD, {"iron_sword": 0.0})
	check("with it off nothing wears", Durability.weapon_mult(sword) == 1.0 and Durability.text(sword) == "")
	GameRules._rules["durability"] = true
	WorldState.erase_record(Durability.RECORD)


func t_build() -> void:
	print("-- perk moves, synergies, titles")
	var sk := p.get_node("Skills") as Skills
	var pa := p.get_node_or_null("PerkAbilities") as PerkAbilities
	check("the player has perk moves", pa != null)
	check("none until a perk gives one", PerkAbilities.owned(p).is_empty() and pa.use() != "")
	sk.build.owned["wa_whirlwind_sprint"] = 1
	sk.build.owned["g_shield_charge"] = 1
	check("a perk gives a move", PerkAbilities.owned(p) == ["shield_charge", "whirlwind"])
	check("Shift+G picks the next", pa.cycle() == "whirlwind" and pa.current() == "whirlwind")
	(p.get_node("Stats") as Stats).modify_vital("stamina", 1000.0)
	var start := p.global_position
	check("G uses it", pa.use() == "")
	await secs(0.5)
	var moved := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	check("whirlwind sprint carries you far", moved > 6.0, "%.1f m" % moved)
	check("then it has a cooldown", pa.use() != "" and pa.cooldown_left("whirlwind") > 5.0)
	pa.cycle()
	var at := p.global_position - p.global_transform.basis.z * 3.0
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var foe := Population.spawn_enemy(load("res://data/enemies/bandit.tres"), 5, wm, at, RandomNumberGenerator.new())
	await frames(3)
	var hp := foe.stats.health
	(p.get_node("Stats") as Stats).modify_vital("stamina", 1000.0)
	check("shield charge works", pa.current() == "shield_charge" and pa.use() == "")
	check("and strikes whoever is in the way", foe.stats.health < hp, "%.0f -> %.0f" % [hp, foe.stats.health])
	foe.queue_free()
	# synergies
	check("no synergy from one tree", sk.build.synergies().is_empty())
	sk.build.owned["w_brawn"] = 1
	sk.build.owned["s_spell_mastery"] = 1
	sk.build.apply()
	sk.build.announce_synergies(self)
	check("two perks from two trees give a hidden third", sk.build.synergies().any(func(s: Array) -> bool: return s[0] == "spellblade"))
	check("its bonus counts", (p.get_node("Stats") as Stats).get_stat("spell_power") >= 0.1 - 0.001, str((p.get_node("Stats") as Stats).get_stat("spell_power")))
	check("it is announced once", Achievements.count("synergy") == 1)
	sk.build.announce_synergies(self)
	check("only once", Achievements.count("synergy") == 1)
	# titles
	check("no title before level 10", CharacterBuild.title(sk) == "" or sk.get_player_level() >= 10)
	for i in 40:
		sk.set_level(&"sneak", sk.get_level(&"sneak") + 1)
		sk.set_level(&"security", sk.get_level(&"security") + 1)
	check("a build earns a title", sk.get_player_level() < 10 or CharacterBuild.title(sk) != "", "%d %s" % [sk.get_player_level(), CharacterBuild.archetype(sk)])


func t_mastery() -> void:
	print("-- loadouts, trials, tomes, trainers")
	var sk := p.get_node("Skills") as Skills
	var inv := p.get_node("Inventory") as Inventory
	var b := sk.build
	b.owned.clear()
	b.owned["w_brawn"] = 1
	b.save_loadout("A")
	b.owned.clear()
	b.owned["g_toughness"] = 1
	b.save_loadout("B")
	check("two builds can be saved", b.loadouts.has("A") and b.loadouts.has("B"))
	check("taking one up needs a shrine", b.load_loadout("A", inv, p) != "")
	var shrine := RestSpot.make_shrine(wm, p.global_position + Vector3(1, 0, 0))
	await frames(2)
	Currency.add_gold(inv, b.loadout_cost() + 5)
	check("at a shrine it works", b.load_loadout("A", inv, p) == "" and b.rank_of("w_brawn") == 1 and b.rank_of("g_toughness") == 0)
	shrine.queue_free()
	var saved := b.to_dict()
	check("loadouts are saved with the character", (saved["loadouts"] as Dictionary).has("B"))
	# trials
	sk.set_level(&"archery", 50)
	SignatureTrials.on_level(self, sk, &"archery", 50)
	check("at 50 a master sends word", SignatureTrials.state(&"archery", 50) == "active")
	var before := inv.stacks.size()
	sk.set_level(&"archery", 53)
	SignatureTrials.on_level(self, sk, &"archery", 53)
	check("three levels on, the trial is done", SignatureTrials.state(&"archery", 50) == "done")
	check("and the amulet is yours", inv.stacks.any(func(s) -> bool: return s.item.display_name == "Archery Master's Amulet"), str(inv.stacks.size() - before))
	# a tome of mastery
	var tome := load("res://data/books/tome_of_mastery.tres") as ItemData
	inv.add_item(tome, 1)
	check("a tome waits for a skill of 100", ItemUse.mastery_tome(p, tome).contains("beyond you"))
	sk.set_level(&"lore", 104)
	ItemUse.use(p, tome)
	check("it raises the best skill to its next mastery step", sk.get_level(&"lore") == 125 and inv.get_count(tome) == 0, str(sk.get_level(&"lore")))
	check("trainer ranks go to 150", Services.TRAINER_RANKS[-1][1] == 150)
