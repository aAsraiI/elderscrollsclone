extends SceneTree
## Headless tests for stage 12b: every written quest (QuestBook), the faction rules of houses,
## clans and the pack, and the instanced realms.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage12b.gd

const STEPS := ["talk", "choice", "clear", "fetch", "fight", "visit", "collect", "wait", "realm", "site"]

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


func _run() -> void:
	t_data()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- the quest data

func t_data() -> void:
	print("-- the quests")
	var defs := QuestBook.defs()
	var counts := {}
	for id in QuestBook.ids():
		var p := String(id).substr(0, 1)
		counts[p] = int(counts.get(p, 0)) + 1
	check("over 300 written quests (%d)" % defs.size(), defs.size() >= 300, str(counts))
	check("ids are unique", defs.size() == QuestBook.ids().size())
	check("settlement, house, clan, pack, guild and realm quests", counts.get("S", 0) >= 120 and counts.get("H", 0) == 64 and counts.get("V", 0) == 27 and counts.get("W", 0) == 9 and counts.get("G", 0) == 57 and counts.get("R", 0) >= 24, str(counts))
	var towns := {}
	for biome: String in NamedSettlements.LIST:
		for e: Dictionary in NamedSettlements.LIST[biome]:
			towns[e["name"]] = biome
	var problems: Array = []
	var hooks := {}
	for id in QuestBook.ids():
		var d: Dictionary = defs[id]
		for a in d["after"]:
			if not defs.has(a):
				problems.append("%s: needs unknown %s" % [id, a])
		var f := String(d.get("faction", ""))
		if f != "" and Factions.get_data(f) == null:
			problems.append("%s: unknown faction %s" % [id, f])
		if String(d["hook"]) == "":
			problems.append("%s: no hook" % id)
		var gkey := "%s|%s" % [JSON.stringify(d["giver"]), d["hook"]]
		if hooks.has(gkey):
			problems.append("%s: same giver and hook as %s" % [id, hooks[gkey]])
		hooks[gkey] = id
		_check_who(id, d["giver"], towns, problems)
		if (d["steps"] as Array).is_empty():
			problems.append("%s: no steps" % id)
		for st: Dictionary in d["steps"]:
			if not STEPS.has(st["do"]):
				problems.append("%s: unknown step %s" % [id, st["do"]])
			if st.has("who"):
				_check_who(id, st["who"], towns, problems)
			if st.has("at"):
				_check_place(id, st["at"], towns, problems)
			if st["do"] == "fight":
				for foe: Array in st["foes"]:
					if not ResourceLoader.exists(QuestBook.ENEMY_DIR + String(foe[0]) + ".tres"):
						problems.append("%s: no enemy %s" % [id, foe[0]])
			if st["do"] == "collect" and not ResourceLoader.exists(String(st["item"])):
				problems.append("%s: no item %s" % [id, st["item"]])
			if st["do"] == "realm" or st["do"] == "site":
				var rd := RealmManager.get_data(String(st["realm"]))
				if rd.is_empty():
					problems.append("%s: no realm %s" % [id, st["realm"]])
				elif st["do"] == "site" and int(st["site"]) >= (rd["sites"] as Array).size():
					problems.append("%s: no site %d in %s" % [id, st["site"], st["realm"]])
			if st["do"] == "talk" and String(st["topic"]) == "":
				problems.append("%s: a talk with no topic" % id)
		var r: Dictionary = d["reward"]
		for path in r.get("items", []):
			if not ResourceLoader.exists(String(path)):
				problems.append("%s: no reward item %s" % [id, path])
		for n: Dictionary in r.get("named", []):
			if not ResourceLoader.exists(String(n["base"])):
				problems.append("%s: no base %s" % [id, n["base"]])
		if r.has("spell") and SpellCatalog.get_spell(String(r["spell"])) == null:
			problems.append("%s: no spell %s" % [id, r["spell"]])
		if r.has("home") and not towns.has(String(r["home"])):
			problems.append("%s: no town %s" % [id, r["home"]])
	check("every quest's people, places, foes, items and rewards exist", problems.is_empty(), "\n  " + "\n  ".join(problems.slice(0, 40)))
	# every faction has its questline gates
	var gates_ok := true
	for f in Factions.IDS:
		var fd := Factions.get_data(f)
		gates_ok = gates_ok and fd != null and defs.has(fd.gate_mid) and defs.has(fd.gate_final)
		if fd != null and fd.join_quest != "":
			gates_ok = gates_ok and defs.has(fd.join_quest)
		if fd != null and fd.penance_quest != "":
			gates_ok = gates_ok and defs.has(fd.penance_quest)
	check("all 20 factions have mid and final gate quests", gates_ok)
	check("every named town has its quest people", QuestBook.cast_for("Kingsreach").size() >= 5 and QuestBook.cast_for("Blackfen").size() >= 4)
	check("all 12 realms are defined", RealmManager.REALMS.size() == 12)


func _check_who(id: String, who: Dictionary, towns: Dictionary, problems: Array) -> void:
	if who.has("lord") and not towns.has(String(who["lord"])):
		problems.append("%s: no lord of %s" % [id, who["lord"]])
	if who.has("cast") and not towns.has(String(who["town"])):
		problems.append("%s: %s lives in unknown %s" % [id, who["cast"], who["town"]])
	if who.has("guild") and Factions.get_data(String(who["guild"])) == null:
		problems.append("%s: no guild %s" % [id, who["guild"]])
	if who.has("leader") and Factions.get_data(String(who["leader"])) == null:
		problems.append("%s: no leader of %s" % [id, who["leader"]])
	if who.has("spawn"):
		_check_place(id, who["spawn"], towns, problems)
	if who.has("realm_npc"):
		var rd := RealmManager.get_data(String(who["realm"]))
		if rd.is_empty() or not (rd["npcs"] as Array).has(who["realm_npc"]):
			problems.append("%s: no %s in %s" % [id, who["realm_npc"], who["realm"]])


func _check_place(id: String, place: Dictionary, towns: Dictionary, problems: Array) -> void:
	for key in ["town", "dungeon", "camp", "wild"]:
		if place.has(key):
			var n := String(place[key])
			if not towns.has(n) and not NamedSettlements.LIST.has(n):
				problems.append("%s: unknown place %s" % [id, n])


# ---------------------------------------------------------------- in the game

func t_world() -> void:
	print("-- in the game")
	WorldState.clear()
	change_scene_to_file("res://test_level.tscn")
	await frames(60)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	check("the world has a QuestBook and a RealmManager", wm != null and wm.book != null and wm.realms != null)
	if wm == null or wm.book == null:
		return
	var book := wm.book
	var inv := p.get_node("Inventory") as Inventory
	var kings: PlacedPOI = null
	for t in wm.towns:
		if t.town.display_name == "Kingsreach":
			kings = t
	var ames: BuildingPlot = null
	for b in kings.town.buildings:
		if b.owner_name == "Watch Captain Bertil Ames":
			ames = b
	check("quest people get homes in their town", ames != null and ames.display_name == "Bertil Ames's House")
	var r: TownLife.Resident = wm.life.get_owner_of(ames.id) if ames != null else null
	check("and live there", r != null and r.data.display_name == "Watch Captain Bertil Ames")
	if r == null:
		return
	var s := _speaker(r)
	check("the giver offers the quest as a topic", book.topics_for(s).has("false crowns"))
	check("and the dialogue knows it", DialogueEngine.topics_for(s, wm).has("false crowns"))
	var said := book.respond(s, "false crowns")
	check("asking starts it", QuestBook.is_active("S-KR01") and String(said.get("quest_id", "")) == "S-KR01")
	var st := QuestBook.state("S-KR01")
	var place: Dictionary = st.get("places", {}).get("0", {})
	check("its first step found a dungeon near Kingsreach", place.has("poi") and st.has("pos"), str(st))
	check("its target is on the map", QuestManager.active_targets().any(func(t: Dictionary) -> bool: return t["name"] == "False Crowns"))
	# go there: the forgers appear
	var at := QuestBook._vec(place.get("pos", []))
	wm.ensure_area_loaded(at, 1)
	p.global_position = at + Vector3(10.0, 2.0, 0.0)
	await frames(30)
	var foes: Array = []
	for e in get_nodes_in_group("enemies"):
		if String((e as Enemy).spawn_key).begins_with("qb/S-KR01/0/"):
			foes.append(e)
	check("the counterfeiters appear when you come near", foes.size() == 4, str(foes.size()))
	for e: Enemy in foes:
		e.stats.modify_vital("health", -99999.0)
	await frames(30)
	check("killing them moves the quest on", int(QuestBook.state("S-KR01").get("step", 0)) == 1)
	var gold := Currency.get_gold(inv)
	check("the choice offers its answers", book.topics_for(s).has("arrest the forger") and book.topics_for(s).has("take a cut"))
	book.respond(s, "arrest the forger")
	check("choosing finishes the quest, with its reward", QuestBook.is_done("S-KR01") and Currency.get_gold(inv) >= gold + 300 and QuestBook.flag("S-KR01:arrested"))
	check("the next quest of the city waits for its turn", not book.can_start(QuestBook.get_def("S-KR04")) and book.can_start(QuestBook.get_def("S-KR02")))
	# a quest item in a dungeon's deepest chest
	book.start("S-MW03")
	var mp: Dictionary = QuestBook.state("S-MW03")["places"]["0"]
	var cc := ContainerComponent.new()
	cc.save_id = "dungeon/%s/chest_boss" % mp["poi"]
	cc.inventory = Inventory.new()
	book.fill_container(cc)
	var lantern := QuestItems.get_item(QuestBook._item_key("S-MW03", "0"), "Star-Glass Lantern")
	check("a fetched item waits in the boss chest", cc.inventory.has_item(lantern))
	inv.add_item(lantern, 1)
	book._check_step("S-MW03")
	check("carrying it moves the quest on", int(QuestBook.state("S-MW03").get("step", 0)) == 1)
	cc.inventory.free()
	cc.free()
	# a person met in the wild
	var wd := QuestBook.get_def("S-WD01")
	var wpos := book._spawn_place_pos("S-WD01", wd["giver"])
	wm.ensure_area_loaded(wpos, 1)
	p.global_position = wpos + Vector3(5.0, 2.0, 5.0)
	await frames(30)
	var courier: Enemy = null
	for e in get_nodes_in_group("enemies"):
		if String((e as Node).get_meta("qb_npc", "")).begins_with("qbnpc/S-WD01/"):
			courier = e
	check("someone waits out in the wild with a quest", courier != null and courier.display_name == "Dying Courier")
	if courier != null:
		var cs := DialogueEngine.speaker_for(courier, wm)
		check("and offers it", book.topics_for(cs).has("the courier's satchel"))
	await t_factions(wm, book, p)
	await t_realms(wm, book, p)
	t_books(wm, p)


func t_books(wm: WorldManager, p: Node3D) -> void:
	print("-- lorebooks")
	check("72 lorebooks", LoreBooks.count() == 72, str(LoreBooks.count()))
	var towns := {}
	for t in wm.towns:
		towns[t.town.display_name] = t
	var ok := true
	var ids := {}
	for e: Array in LoreBooks.LIST:
		ids[e[0]] = true
		ok = ok and towns.has(e[3]) and String(e[5]).length() > 80
		if String(e[4]) != "":
			ok = ok and SkillDatabase.get_skill(StringName(e[4])) != null
	check("every book has a home town, real text and a real skill", ok and ids.size() == 72)
	var it := LoreBooks.get_item("korrund_anvil")
	check("a book saves and loads by its path", SaveUtil.path_to_item(SaveUtil.item_to_path(it)) == it)
	check("books are read, not used up", ItemUse.verb(p, it) == "Read book")
	var skills := p.get_node("Skills") as Skills
	var before := skills.get_level(&"smithing")
	var text := LoreBooks.read(p, it)
	check("reading shows its text and teaches its skill once", text.begins_with("Heat the metal") and skills.get_level(&"smithing") == before + 1)
	LoreBooks.read(p, it)
	check("but only once", skills.get_level(&"smithing") == before + 1)
	var seat: BuildingPlot = (towns["Frosthelm"] as PlacedPOI).town.get_seat()
	var inside := InteriorBuilder.build(seat, 99, 40, 1)
	var shelf_books := 0
	for c in (inside["root"] as Node3D).get_children():
		var cc := c.get_node_or_null("ContainerComponent") as ContainerComponent
		if cc != null and cc.display_name == "Bookshelf":
			shelf_books = cc.contents.size()
	check("a town's books sit on its seat's bookshelf", shelf_books == LoreBooks.for_town("Frosthelm").size() and shelf_books > 0, str(shelf_books))
	(inside["root"] as Node3D).free()


func _speaker(r: TownLife.Resident) -> DialogueEngine.Speaker:
	var s := DialogueEngine.Speaker.new()
	s.id = r.data.id
	s.name = r.data.display_name
	s.role = r.data.role
	s.town = r.town
	s.data = r.data
	return s


func t_factions(wm: WorldManager, book: QuestBook, p: Node3D) -> void:
	print("-- houses, clans and the pack")
	var duke := _named_speaker(wm, "Merewater", "Duke Lucan Valcourt")
	check("a great lord leads his house", duke != null and Factions.leader_of(duke, wm) == "valcourt")
	check("joining needs the trial first", Factions.join_problem("valcourt", p).begins_with("Prove yourself"))
	check("the trial is offered to anyone", book.can_start(QuestBook.get_def("H-VA01")) and book.can_start(QuestBook.get_def("H-TW01")))
	book.debug_complete("H-VA01")
	check("the trial swears you in", Factions.is_member("valcourt"))
	check("and closes every other house for good", not book.can_start(QuestBook.get_def("H-TW01")) and Factions.join_problem("tidewell", p).contains("sworn"))
	book.debug_complete("H-VA02")
	book.debug_complete("H-VA03")
	var n := Factions.next_rank("valcourt", p)
	check("rank 3 waits for the mid gate quest", Factions.rank("valcourt") == 2 and not bool(n["ok"]) and String(n["why"]).contains("The Heron's Claim"), "%d %s" % [Factions.rank("valcourt"), n])
	book.debug_complete("H-VA04")
	check("the gate quest opens rank 3", Factions.rank("valcourt") == 3)
	for id in ["H-VA05", "H-VA06"]:
		book.debug_complete(id)
	n = Factions.next_rank("valcourt", p)
	check("rank 5 waits for the final gate quest", Factions.rank("valcourt") == 4 and String(n["why"]).contains("The Council of Ten"), "%d %s" % [Factions.rank("valcourt"), n])
	book.debug_complete("H-VA07")
	check("the final gate opens the top rank", Factions.rank("valcourt") == 5)
	# guilds keep their gates too
	Factions._store("fighters", 2, 20)
	var fg := Factions.next_rank("fighters", p)
	check("a guild's rank 3 needs its gate quest", String(fg.get("why", "")).contains("The Black Lance"), str(fg))
	# clans: only the afflicted
	var aff := p.get_node("Afflictions") as Afflictions
	check("only vampires may start a clan's trial", not book.can_start(QuestBook.get_def("V-VC01")))
	aff.become_vampire()
	check("a vampire may", book.can_start(QuestBook.get_def("V-VC01")) and book.can_start(QuestBook.get_def("V-HK01")))
	check("but not the werewolf pack", not book.can_start(QuestBook.get_def("W-GF01")))
	book.debug_complete("V-VC01")
	check("the Embrace makes you one of the Court", Factions.is_member("velvet_court"))
	check("and rival clans close for good", not book.can_start(QuestBook.get_def("V-HK01")) and Factions.join_problem("hollow_kin", p).contains("sworn"))
	aff.cure_vampire()
	await frames(40)
	check("a cure expels you", not Factions.is_member("velvet_court") and WorldState.has_record("fexpel/velvet_court"))
	check("the penance waits until you are turned again", not book.can_start(QuestBook.get_def("V-VC00")))
	aff.become_vampire()
	check("then the penance is offered", book.can_start(QuestBook.get_def("V-VC00")))
	book.debug_complete("V-VC00")
	check("and brings you back", Factions.is_member("velvet_court") and not WorldState.has_record("fexpel/velvet_court"))
	aff.cure_vampire()
	await frames(40)
	# the territory war
	check("the clans start where the bible says", ClanTerritory.ruler("swamp") == "velvet_court" and ClanTerritory.ruler("highlands") == "hollow_kin" and ClanTerritory.ruler("ashlands") == "ashen_choir")
	var kin_before := int(ClanTerritory.scores("plains")["hollow_kin"])
	for i in 5:
		ClanTerritory.gain("plains", "hollow_kin")
	check("clan work wins ground", ClanTerritory.ruler("plains") == "hollow_kin" and int(ClanTerritory.scores("plains")["hollow_kin"]) == mini(kin_before + 50, 100), str(ClanTerritory.scores("plains")))
	var mir := _named_speaker(wm, "Blackfen", "Lady Mireille Morvaine")
	check("a clan leader tells of the territory war", mir != null and wm.quests.extra_topics(mir).has("the territory war") and String(wm.quests.respond(mir, "the territory war").get("text", "")).contains("Hollow Kin holds"))


func _named_speaker(wm: WorldManager, town: String, name: String) -> DialogueEngine.Speaker:
	for t in wm.towns:
		if t.town.display_name != town:
			continue
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			if r.data.display_name == name:
				return _speaker(r)
	return null


func t_realms(wm: WorldManager, book: QuestBook, p: Node3D) -> void:
	print("-- the realms")
	var all_found := true
	for id: String in RealmManager.REALMS:
		all_found = all_found and RealmManager.gate_position(wm, id).is_finite()
	check("every realm has a gate in the world", all_found)
	check("gates start sealed", not RealmManager.is_open("R2"))
	book.start("S-MG01")
	check("a quest that sends you there opens the gate", RealmManager.is_open("R2"))
	var gate := RealmManager.gate_position(wm, "R2")
	wm.ensure_area_loaded(gate, 1)
	p.global_position = gate + Vector3(0.0, 2.0, -6.0)
	await frames(80)
	var gate_node := wm.get_node_or_null("RealmGate_R2") as RealmGate
	check("the gate stands in the world", gate_node != null and gate_node.get_prompt().begins_with("Enter"))
	wm.dungeons.fade_time = 0.0
	wm.dungeons.enter("realm:R2", gate, 0.0)
	await frames(20)
	check("going through puts you in the realm", wm.dungeons.is_in_realm() and p.global_position.y < RealmManager.REALM_Y + 200.0, str(p.global_position))
	check("with its own name", wm.dungeons.get_current_name() == "The Thornheart Dreamwood")
	var npc := false
	var guards: Array = []
	for e in get_nodes_in_group("enemies"):
		if String((e as Node).get_meta("realm_npc", "")) == "The Talking Fox":
			npc = true
		if String((e as Enemy).spawn_key).begins_with("realm/R2/s0/"):
			guards.append(e)
	check("its hub has its people", npc)
	check("its sites have guards", guards.size() == RealmManager.site_guards("R2", 0), str(guards.size()))
	for e: Enemy in guards:
		e.stats.modify_vital("health", -99999.0)
	await frames(30)
	check("killing them clears the site", RealmManager.is_site_cleared("R2", 0))
	check("which moves the quest on", int(QuestBook.state("S-MG01").get("step", 0)) == 1)
	p.global_position = p.global_position + Vector3(0.0, -200.0, 0.0)
	await frames(80)
	check("falling off the edge puts you back at the hub", p.global_position.y > RealmManager.REALM_Y - 60.0, str(p.global_position))
	wm.dungeons.exit()
	await frames(20)
	check("leaving puts you back at the gate", not wm.dungeons.is_inside() and p.global_position.distance_to(gate) < 20.0, str(p.global_position.distance_to(gate)))
