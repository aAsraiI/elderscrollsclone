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
		await t_data()
		await t_achievements()
		await t_guide()
		await t_journal()
		await t_ranged()
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
	check("one click shoots at full power", inv.get_count(bolt) == 9 and Achievements.count("shot") == shots + 1)
	check("then it has to be wound again", rc.reload_ratio() < 0.2 and not rc.begin_draw() and inv.get_count(bolt) == 9)
	await secs(cb.draw_time + 0.2)
	check("and is ready after its reload time", rc.reload_ratio() >= 1.0)
	var knife := load("res://data/ranged/iron_throwing_knife.tres") as ItemData
	inv.add_item(knife, 3)
	eq.equip(knife)
	await frames(2)
	check("throwing knives go in the hand as a stack", eq.get_main_hand() == knife and rc.best_arrow() == knife)
	rc.begin_draw()
	await frames(2)
	check("left click throws one", inv.get_count(knife) == 2)
	var flying := root.find_children("*", "Arrow", true, false)
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
