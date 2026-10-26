extends SceneTree
## Headless tests for Alpha 1.12 (quests, dialogue and journal), in the real game world:
## one guild job of each radiant kind (retrieve, kill, steal, persuade) taken, done and handed in
## the way a player does it: through the dialogue window, real dungeons, houses and chests.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha112.gd

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
	await t_radiant()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- the four radiant jobs

var wm: WorldManager
var p: CharacterBody3D
var ui: DialogueUI
var leaders := {}  # faction -> TownLife.Resident
var city: PlacedPOI


func t_radiant() -> void:
	print("-- the four radiant jobs, end to end")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(90)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as CharacterBody3D
	ui = get_first_node_in_group("dialogue_ui") as DialogueUI
	check("the game is up", wm != null and p != null and ui != null)
	if wm == null or p == null or ui == null:
		return
	wm.clock.set_time(12.0)
	var probs := QuestCheck.problems(wm)
	for line in probs:
		print("  [Quest] ", line)
	check("every written quest can be finished in this world (%d problems)" % probs.size(), probs.is_empty())
	(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
	for t in wm.towns:
		if (t.poi as TownData).kind != TownData.Kind.CITY:
			continue
		var found := {}
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			var lead := Factions.leader_of(_speaker(r), wm)
			if lead != "" and not found.has(lead):
				found[lead] = r
		if found.has("fighters") and found.has("thieves") and found.has("mages"):
			city = t
			leaders = found
			break
	check("a city with Fighters, Mages and Thieves leaders", city != null, str(leaders.keys()))
	if city == null:
		return
	Factions.note_crime("thefts")
	for f in ["fighters", "thieves", "mages"]:
		Factions.join(f, p)
	await _retrieve()
	await _kill()
	await _steal()
	await _persuade()
	_console()
	await _job_rules()
	_dialogue_roles()
	await _dialogue_services()
	await _main_story()
	_journal_cleanup()
	await _notes()
	await _custom_npc()
	await _handmade_quest()
	await _lifecycle()
	await _journal_ux()
	await _hud()
	await _radiant_v2()
	_guilds()
	await _integration()
	_rumors_and_barks()
	await _authoring()
	await _qa()
	await _across_a_load()


# ---------------------------------------------------------------- 1.12.2 / 1.12.3 handmade quests

func _handmade_quest() -> void:
	print("-- a handmade quest (QuestData)")
	var runner := wm.runner
	check("the runner exists and loads data/quests (not the templates)", runner != null and QuestRunner.get_data("maudrey_old_kings") != null and QuestRunner.get_data("template_kill") == null)
	if runner == null:
		return
	var id := "maudrey_old_kings"
	check("a change that isn't allowed is refused", not runner.set_state(id, "completed") and runner.status(id) == "available")
	var hermit: CustomNpcData = null
	for d in CustomNpcs.all():
		if d.id == "example_hermit":
			hermit = d
	var spot := (wm.get_node("CustomNpcs") as CustomNpcs).spot_of(hermit)
	var body := await _custom_body(hermit, spot)
	if body == null or not ui.open_with(body):
		check("Maudrey can be talked to", false)
		return
	check("she offers the quest", DialogueEngine.topics_for(ui.speaker, wm).has("the barrow"))
	var said := String(ui.ask("the barrow")["text"])
	check("taking it shows the reward", runner.status(id) == "active" and said.contains("Reward"), said)
	ui.close()
	var inv := p.get_node("Inventory") as Inventory
	var flower := load("res://data/ingredients/blue_mountain_flower.tres") as ItemData
	inv.add_item(flower, 2)
	var camp := QuestTargets.place(wm, "camp near Kingsreach")
	await _go(camp["pos"] + Vector3(0, 0, 20))
	await secs(1.5)
	var wolves: Array = []
	for e in get_nodes_in_group("enemies"):
		if String((e as Enemy).spawn_key).begins_with("qi/%s/" % id):
			wolves.append(e)
	check("the grave wolves appear when you come near (3)", wolves.size() == 3, str(wolves.size()))
	check("they are quest-critical", wolves.all(func(e: Enemy) -> bool: return QuestTargets.is_critical(e)))
	check("the tracker shows the count", runner.next_step(id).contains("0/3"), runner.next_step(id))
	for e: Enemy in wolves:
		e.stats.modify_vital("health", -999999.0)
	await secs(1.0)
	check("killing them moves to the choice", int(QuestRunner.record(id).get("stage", 0)) == 1, str(QuestRunner.record(id)))
	body = await _custom_body(hermit, spot)
	if body == null or not ui.open_with(body):
		check("Maudrey is back", false)
		return
	var topics := DialogueEngine.topics_for(ui.speaker, wm)
	check("the choice is offered", topics.has("bury the bones") and topics.has("keep the barrow open"), str(topics))
	ui.ask("bury the bones")
	check("the choice is remembered", QuestBook.flag("%s:buried" % id))
	check("then it's ready to turn in", runner.status(id) == "ready")
	topics = DialogueEngine.topics_for(ui.speaker, wm)
	var pick := ""
	for t in topics:
		if t.begins_with("take the "):
			pick = t
	check("a reward to pick from", pick != "", str(topics))
	var gold := Currency.get_gold(inv)
	var answer := String(ui.ask(pick)["text"])
	ui.close()
	check("picking it completes the quest", runner.status(id) == "completed")
	check("with gold, the bonus for the flowers, and the flowers handed over", Currency.get_gold(inv) >= gold + 60 + 25 and inv.get_count(flower) == 0, "%d -> %d" % [gold, Currency.get_gold(inv)])
	check("the turn-in says what you handed over", answer.contains("You hand over 2 Blue Mountain Flower"), answer)
	check("and Kingsreach thinks better of you", Reputation.get_rep("Kingsreach") > 0)
	check("the flag is set", DialogueState.has_flag("maudrey_barrow_done"))


# ---------------------------------------------------------------- 1.12.6 - 1.12.8 the journal

func _journal_ux() -> void:
	print("-- the journal, notes and quest pages")
	var entries := DialogueState.journal()
	check("entries have ids, types and a read flag", entries.any(func(e: Dictionary) -> bool: return e.has("id") and e.has("type") and e.has("read")))
	check("joining a guild was written down", entries.any(func(e: Dictionary) -> bool: return String(e["text"]).begins_with("Joined the")))
	check("there is something unread", DialogueState.unread_count() > 0)
	DialogueState.mark_read()
	check("mark all read", DialogueState.unread_count() == 0)
	var big := DialogueState.journal().duplicate(true)
	for i in DialogueState.JOURNAL_MAX + 20:
		big.append({"text": "filler %d" % i, "topic": "", "type": "Rumor", "quest_id": "", "day": 1})
	WorldState.set_record(DialogueState.JOURNAL, {"entries": big})
	DialogueState.add_journal({"text": "one more", "topic": "", "type": "Rumor"})
	check("the journal keeps to its size cap, dropping old rumors", DialogueState.journal().size() <= DialogueState.JOURNAL_MAX)
	check("quests stay when pruning", DialogueState.journal().any(func(e: Dictionary) -> bool: return String(e.get("quest_id", "")) != ""))
	var quests := QuestLog.all(wm)
	var sources := {}
	for q: Dictionary in quests:
		sources[q["source"]] = true
	check("the quest list has jobs, written quests, handmade quests and the story", sources.has("job") and sources.has("runner") and sources.has("story"), str(sources.keys()))
	check("each with a status from the four", quests.all(func(q: Dictionary) -> bool: return q["status"] in ["active", "completed", "failed", "abandoned"]))
	var ju := get_first_node_in_group("journal_ui") as JournalUI
	ju.open()
	ju.show_quest("maudrey_old_kings")
	var page := ju._text.get_parsed_text()
	check("a quest page shows its objectives, ticked", page.contains("Objectives") and page.contains("[x]"), page.left(300))
	check("and its reward", page.contains("Reward"))
	ju._tabs.current_tab = JournalUI.TAB_PLACES
	check("the Places tab lists places", ju._list.get_root().get_child_count() > 0)
	DialogueState.toggle_bookmark("quest:maudrey_old_kings")
	ju._tabs.current_tab = JournalUI.TAB_QUESTS
	check("bookmarks come first", ju._list.get_root().get_first_child().get_text(0) == "Bookmarks")
	ju.edit_note(0, "Wolves at the barrow.")
	ju._note_pin.button_pressed = true
	ju._note_color.selected = 2
	ju._note_link.selected = maxi(ju._link_values.find("quest:" + String(QuestManager.all_quests()[-1]["id"])), 0)
	var nid := ju.save_note()
	var n := DialogueState.get_note(nid)
	check("a note can be pinned and coloured", bool(n.get("pinned", false)) and int(n.get("color", 0)) == 2)
	ju.edit_note(nid)
	ju._note_body.text = "Changed my mind."
	ju.cancel_note()
	check("Esc with unsaved words asks first", ju.is_editing() and ju._status.text.contains("Unsaved"))
	ju.cancel_note()
	check("a second Esc throws them away", not ju.is_editing() and DialogueState.get_note(nid)["text"] == "Wolves at the barrow.")
	var path := DialogueState.export_notes()
	check("notes export to a text file", path != "" and FileAccess.file_exists(path), path)
	ju.close()
	JournalUI._last_tab = JournalUI.TAB_NOTES
	ju.open()
	check("the journal reopens where you left it", ju._tabs.current_tab == JournalUI.TAB_NOTES)
	ju.close()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.keycode = KEY_J
	key.shift_pressed = true
	key.pressed = true
	root.push_input(key)
	await process_frame
	check("Shift+J writes a new note from anywhere", ju.is_open() and ju.is_editing())
	ju.cancel_note()
	ju.close()


# ---------------------------------------------------------------- 1.12.9 tracking and notices

func _hud() -> void:
	print("-- tracking, notices, markers")
	WorldState.erase_record(QuestTracker.KEY)
	for id in ["a", "b", "c", "d"]:
		QuestTracker.toggle(id)
	check("at most three tracked quests", QuestTracker.tracked() == ["b", "c", "d"])
	WorldState.erase_record(QuestTracker.KEY)
	var q := _job("fighters", "kill")
	QuestTracker.toggle(String(q["id"]))
	check("the compass shows only tracked quests", QuestManager.compass_targets().all(func(t: Dictionary) -> bool: return t["id"] == q["id"]))
	GameSettings.set_value("quest_tracker", true)
	await secs(1.0)
	var tracker := wm.get_node("QuestTracker") as QuestTracker
	check("the tracker shows the tracked quest", tracker._box.get_child_count() >= 2)
	GameSettings.set_value("quest_tracker", false)
	var notices := Notices.of(self)
	notices._queue.clear()
	notices.push("Quest started", "A")
	notices.push("Quest started", "A")
	notices.push("Objective updated", "B")
	check("notices queue up, repeats dropped", notices.pending().size() == 2)
	GameSettings.set_value("quest_popups", false)
	notices.push("Quest started", "C")
	check("notices can be turned off", notices.pending().size() == 2)
	GameSettings.set_value("quest_popups", true)
	var camp := wm.get_poi(String(q["target"]))
	await _go(camp.position + Vector3(0, 0, 25))
	for e in wm.get_garrison(camp.id):
		if is_instance_valid(e) and e.display_name == String(q["chief"]):
			e.stats.modify_vital("health", -999999.0)
	await secs(1.5)
	var marks := wm.get_node("QuestMarkers") as QuestMarkers
	check("the leader gets a hand-in mark", marks.mark_for(_speaker(leaders["fighters"])) == "ready")
	wm.quests.respond(_speaker(leaders["fighters"]), "report back")


# ---------------------------------------------------------------- 1.12.10 radiant v2

func _radiant_v2() -> void:
	print("-- radiant quests v2")
	var qm := wm.quests
	var saved: Dictionary = WorldState.get_record(QuestManager.STATE).duplicate(true)
	# soak: 100 jobs of every kind from every guild leader of several towns
	var made := 0
	var bad := PackedStringArray()
	var types := ["retrieve", "kill", "hunt", "steal", "persuade", "deliver", "gather", "rescue", "escort", "investigate", "protect", "road"]
	var towns: Array = wm.towns.slice(0, 12)
	var i := 0
	while made < 100 and i < 400:
		var town: PlacedPOI = towns[i % towns.size()]
		var type: String = types[i % types.size()]
		i += 1
		var giver := DialogueEngine.Speaker.new()
		giver.id = "soak"
		giver.name = "Soak Tester"
		giver.town = town
		_clear_jobs()
		var q := qm.offer("fighters", giver, type)
		if q.is_empty():
			continue
		made += 1
		if Radiant.validate(qm, q) != "":
			bad.append("%s: %s" % [q["type"], Radiant.validate(qm, q)])
		if String(q["objective"]).to_lower().contains("the the ") or String(q["objective"]).contains("  "):
			bad.append("%s: clumsy wording '%s'" % [q["type"], q["objective"]])
		if String(q["name"]).contains("{") or String(q["objective"]).contains("{") or String(q["name"]) == "":
			bad.append("%s: bad wording '%s' / '%s'" % [q["type"], q["name"], q["objective"]])
	check("100 generated jobs, none impossible (%d made)" % made, made >= 100 and bad.is_empty(), "\n".join(bad.slice(0, 5)))
	check("every kind has a template with several wordings", types.all(func(t: String) -> bool: return Radiant.template(t) != null and Radiant.template(t).names.size() >= 2))
	WorldState.set_record(QuestManager.STATE, saved)
	# gather
	_clear_jobs()
	var g := _job("mages", "gather")
	if not g.is_empty():
		var it := load(String(g["item_path"])) as ItemData
		(p.get_node("Inventory") as Inventory).add_item(it, int(g["count"]))
		check("gather: carrying them, it's ready", qm.is_ready(g))
		qm.complete(g)
		check("gather: handing in takes them", (p.get_node("Inventory") as Inventory).get_count(it) == 0)
	# investigate
	_clear_jobs()
	var inv_q := _job("mages", "investigate")
	if not inv_q.is_empty():
		await _go(Vector3(float(inv_q["at"][0]), 0, float(inv_q["at"][2])))
		await secs(1.5)
		check("investigate: going there finds the clue", qm.is_ready(QuestManager.get_quest(String(inv_q["id"]))))
	# rescue
	_clear_jobs()
	var r := _job("fighters", "rescue")
	if not r.is_empty():
		var at := Vector3(float(r["at"][0]), 0, float(r["at"][2]))
		await _go(at + Vector3(0, 0, 20))
		await secs(1.5)
		var guards := _spawned_of(String(r["id"]), "guard")
		check("rescue: guards stand over the captive", guards.size() == int(r["count"]) and qm._radiant_spawned.has("quest/%s/captive" % r["id"]), "%d guards" % guards.size())
		for e: Enemy in guards:
			e.stats.modify_vital("health", -999999.0)
		var cap: Enemy = qm._radiant_spawned.get("quest/%s/captive" % r["id"])
		if cap != null:
			p.global_position = cap.global_position + Vector3(1.5, 0.5, 0)
		await secs(1.5)
		check("rescue: guards dead and the captive reached, it's ready", qm.is_ready(QuestManager.get_quest(String(r["id"]))))
	# protect and road
	for kind in ["protect", "road"]:
		_clear_jobs()
		var pr := _job("fighters" if kind == "road" else "knights", kind)
		if pr.is_empty():
			continue
		await _go(Vector3(float(pr["at"][0]), 0, float(pr["at"][2])) + Vector3(0, 0, 15))
		await secs(1.5)
		var raiders := _spawned_of(String(pr["id"]), "raider")
		check("%s: raiders come" % kind, raiders.size() == int(pr["count"]))
		for e: Enemy in raiders:
			e.stats.modify_vital("health", -999999.0)
		await secs(0.5)
		check("%s: all dead, it's ready" % kind, qm.is_ready(QuestManager.get_quest(String(pr["id"]))))
	# escort
	_clear_jobs()
	var es := _job("knights", "escort")
	if not es.is_empty():
		await _go(Vector3(float(es["at"][0]), 0, float(es["at"][2])))
		await secs(1.5)
		var walker: Enemy = qm._radiant_spawned.get("quest/%s/escort" % es["id"])
		check("escort: they wait for you", walker != null)
		var dest := wm.get_poi(String(es["target"]))
		await _go(dest.position + Vector3(10, 0, 0))
		if walker != null and is_instance_valid(walker):
			walker.global_position = p.global_position + Vector3(2, 0.5, 0)
		await secs(1.5)
		check("escort: reaching the town together, it's ready", qm.is_ready(QuestManager.get_quest(String(es["id"]))))
	# kill: escorts and the signet
	_clear_jobs()
	var k := _job("fighters", "kill")
	if not k.is_empty():
		var camp := wm.get_poi(String(k["target"]))
		await _go(camp.position + Vector3(0, 0, 25))
		var chief: Enemy = null
		var escorts := 0
		for e in wm.get_garrison(camp.id):
			if is_instance_valid(e) and e.display_name == String(k["chief"]):
				chief = e
			if is_instance_valid(e) and String(e.spawn_key).begins_with("quest/%s/escort" % k["id"]):
				escorts += 1
		check("kill: the chief has an escort", escorts == 2, str(escorts))
		var token := QuestItems.get_item(String(k["id"]) + "_proof", String(k["proof"]))
		check("kill: the chief carries a signet", chief != null and chief.inventory.has_item(token))
		(p.get_node("Inventory") as Inventory).add_item(token)
		check("kill: the signet pays a bonus", Radiant.hand_over(qm, k, 100) == 20)
	# the "already taken" twist
	_clear_jobs()
	var t := _job("fighters", "retrieve")
	if not t.is_empty():
		var tp := wm.get_poi(String(t["target"]))
		t["twist"] = true
		t["at"] = [tp.position.x + 8.0, tp.position.y, tp.position.z + 8.0]
		QuestManager._update_quest(t)
		await _go(tp.position + Vector3(0, 0, 20))
		await secs(1.5)
		var thief: Enemy = qm._radiant_spawned.get("quest/%s/thief0" % t["id"])
		var item := QuestItems.get_item(String(t["id"]), String(t["item_name"]))
		check("twist: a thief has the item", thief != null and thief.inventory.has_item(item))
	# other ways through
	_clear_jobs()
	var pq := _job("mages", "persuade")
	var target: TownLife.Resident = wm.life.get_resident(String(pq.get("target", "")))
	if target != null:
		var ts := _speaker(target)
		DialogueState.learn(target.data.display_name)
		var topics := qm.extra_topics(ts)
		check("persuade: a favour, or what you know", topics.has("a favour") and topics.has("what I know"), str(topics))
		qm.respond(ts, "what I know")
		check("persuade: what you know works", qm.is_ready(QuestManager.get_quest(String(pq["id"]))))
	_clear_jobs()
	var st := _job("thieves", "steal")
	var owner: TownLife.Resident = wm.life.get_resident("npc/" + String(st.get("target", "")))
	if owner != null:
		Currency.add_gold(p.get_node("Inventory") as Inventory, 1000)
		var os := _speaker(owner)
		var buy := "buy the " + String(st["item_name"]).to_lower()
		check("steal: or buy it from the owner", qm.extra_topics(os).has(buy))
		qm.respond(os, buy)
		check("steal: bought, it's ready", qm.is_ready(QuestManager.get_quest(String(st["id"]))))
	# the notice board
	_clear_jobs()
	var board := NoticeBoard.new()
	board.town_id = city.id
	wm.add_child(board)
	var offers := board.offers()
	check("a notice board posts offers", offers.size() >= 2, str(offers.size()))
	check("the same offers all period", board.offers().map(func(o: Dictionary) -> String: return o["name"]) == offers.map(func(o: Dictionary) -> String: return o["name"]))
	var job := board.take(0)
	check("taking one makes a job", not job.is_empty() and qm.bounty_of(board.board_id()) == QuestManager.get_quest(String(job["id"])))
	check("only one at a time", board.take(1).is_empty())
	var late: Dictionary = (offers[1] as Dictionary).duplicate()
	late["expires_day"] = wm.clock.day
	check("an offer past its day can't be taken", qm.take_offer(late, "x", city).is_empty())
	board.queue_free()
	# limits per town
	_clear_jobs()
	WorldState.erase_record(QuestManager.COOLDOWN)
	for n in Radiant.TOWN_LIMIT:
		Radiant.count_town(city.id, wm.clock.day)
	var said := qm.respond(_speaker(leaders["fighters"]), "duties")
	check("a town gives out only so many jobs a day", String(said.get("text", "")).contains("all the work"), String(said.get("text", "")))
	WorldState.erase_record("radiant_day/" + city.id)
	_clear_jobs()


# ---------------------------------------------------------------- 1.12.11 guilds and reputation

func _guilds() -> void:
	print("-- guilds and reputation")
	check("rivals: a thief can't join the Knightly Order", Factions.join_problem("knights", p).contains("Thieves"), Factions.join_problem("knights", p))
	var ls := _speaker(leaders["mages"])
	check("members can leave", wm.quests.extra_topics(ls).has("leave the guild"))
	var first := String(wm.quests.respond(ls, "leave the guild")["text"])
	check("leaving asks first", first.contains("Ask me again") and Factions.is_member("mages"))
	wm.quests.respond(ls, "leave the guild")
	check("asking again leaves", not Factions.is_member("mages"))
	Factions.join("mages", p)
	check("and you can come back", Factions.is_member("mages"))
	var fighter: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		if r.data.faction == "fighters" and r != leaders["fighters"]:
			fighter = r
	if fighter != null and fighter.node != null and is_instance_valid(fighter.node):
		wm.quests.on_murder(fighter.node, true)
		check("murdering a guildmate in sight gets you expelled", not Factions.is_member("fighters"))
		check("and the guild hates you for it", Reputation.get_rep("fighters") < 0)
		WorldState.erase_record("fexpel/fighters")
		Factions.join("fighters", p)
	var before := Reputation.infamy(city.town.display_name)
	wm.quests._on_crime("theft", city.id, 100, true)
	check("crimes seen in a town add to your infamy there", Reputation.infamy(city.town.display_name) > before)
	var s := _speaker(leaders["fighters"])
	var plain := DialogueState.get_disposition(s.id, s.base_disposition)
	Reputation.add_fame(city.town.display_name, 80)
	check("fame makes people like you more", DialogueEngine.get_disposition(s) > plain)
	Reputation.add_fame(city.town.display_name, -80)
	Reputation.add("fighters", -100)
	check("a guild that distrusts you gives no work", String(wm.quests.respond(s, "duties")["text"]).contains("trust"))
	Reputation.add("fighters", 100)


# ---------------------------------------------------------------- 1.12.12 everything together

func _integration() -> void:
	print("-- quests with the other systems")
	var qm := wm.quests
	_clear_jobs()
	# Speech opens an option
	var pq := _job("mages", "persuade")
	var target: TownLife.Resident = wm.life.get_resident(String(pq.get("target", "")))
	var sk := p.get_node("Skills") as Skills
	while sk.get_level(&"speech") < Radiant.SPEECH_CHECK:
		sk.debug_level_up(&"speech")
	if target != null:
		var ts := _speaker(target)
		check("high Speech: \"talk them round\"", qm.extra_topics(ts).has("talk them round"))
		var said := String(qm.respond(ts, "talk them round")["text"])
		check("the Speech check is marked with the skill", said.begins_with("[Speech"), said)
		check("and it works", qm.is_ready(QuestManager.get_quest(String(pq["id"]))))
	_clear_jobs()
	# a shopkeeper's errand
	var merchant: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		if r.data.role == NpcData.Role.MERCHANT and Factions.leader_of(_speaker(r), wm) == "" and merchant == null:
			merchant = r
	if merchant != null:
		var ms := _speaker(merchant)
		check("merchants give errands", qm.extra_topics(ms).has("supplies"))
		qm.respond(ms, "supplies")
		var job := qm._job_given_by(ms)
		check("a gather job from the shop", not job.is_empty() and job["type"] == "gather")
		if not job.is_empty():
			(p.get_node("Inventory") as Inventory).add_item(load(String(job["item_path"])), int(job["count"]))
			check("and they take it back", qm.extra_topics(ms).has("report back"))
			var gold := Currency.get_gold(p.get_node("Inventory") as Inventory)
			qm.respond(ms, "report back")
			check("and pay for it", Currency.get_gold(p.get_node("Inventory") as Inventory) > gold)
	# rewards from the loot tables
	var loot := 0
	for n in 20:
		if qm._loot_reward({"id": "loot%d" % n}) != null:
			loot += 1
	check("some jobs pay in loot too (%d of 20)" % loot, loot > 0 and loot < 20)
	# a building is a place: walking in counts
	var house: BuildingPlot = null
	for b in city.town.buildings:
		if b.kind == BuildingPlot.Kind.HOUSE and house == null:
			house = b
	var q := QuestData.new()
	q.id = "test_enter"
	q.title = "Test Enter"
	q.completion = QuestData.Completion.AUTO
	var st := QuestStage.new()
	var o := QuestObjective.new()
	o.type = QuestObjective.Type.REACH
	o.place = house.id
	o.radius = 0.5
	st.objectives = [o]
	q.stages = [st]
	QuestRunner.register(q)
	wm.runner.start("test_enter")
	check("a building is a quest place", not QuestTargets.place(wm, house.id).is_empty())
	QuestEvents.enter(self, house.id)
	check("going inside completes it", wm.runner.status("test_enter") == "completed")
	# old saves: entries and jobs from before 1.12
	var old_entry := {"text": "An old line.", "speaker": "Old", "topic": "Kingsreach", "place": "", "day": 3, "time": "", "quest_id": "", "quest_name": ""}
	check("old journal entries get a type", JournalUI.type_of(old_entry) != "")
	var list := QuestManager.all_quests().duplicate(true)
	list.append({"id": "q_old", "type": "kill", "name": "Old Job", "status": "active", "target": "nowhere", "chief": "Nobody the Old", "faction": "fighters", "reward": 50, "pos": [0, 0], "objective": "Old."})
	WorldState.set_record(QuestManager.STATE, {"list": list, "counter": QuestManager._counter()})
	check("old jobs show in the quest list", QuestLog.find(wm, "q_old").get("name", "") == "Old Job")
	check("old jobs that can't be done are flagged", QuestCheck.job_problem(wm, list[-1]) != "")
	WorldState.erase_record(QuestTracker.KEY)
	WorldState.set_record("tracked_quest", {"id": "q_old"})
	check("an old save's tracked quest carries over", QuestTracker.tracked() == ["q_old"])
	WorldState.erase_record("tracked_quest")
	_clear_jobs()


# ---------------------------------------------------------------- 1.12.13 rumors and barks

func _rumors_and_barks() -> void:
	print("-- rumors and barks")
	var day := wm.clock.day
	var far: PlacedPOI = null
	for t in wm.towns:
		if t.position.distance_to(city.position) > 3000.0 and t.position.distance_to(city.position) < 4800.0 and far == null:
			far = t
	Rumors.add("deed", "Test: the old mill burned down.", city.position, day)
	check("news is heard where it happened", Rumors.heard_at(city.position, day).any(func(r: Dictionary) -> bool: return r["text"] == "Test: the old mill burned down."))
	if far != null:
		check("but not yet far away", not Rumors.heard_at(far.position, day).any(func(r: Dictionary) -> bool: return r["text"] == "Test: the old mill burned down."))
		check("it spreads there in a few days", Rumors.heard_at(far.position, day + 8).any(func(r: Dictionary) -> bool: return r["text"] == "Test: the old mill burned down."))
	var told := false
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		var s := _speaker(r)
		s.position = city.position
		if String(DialogueEngine._rumor(s, wm)).begins_with("Test: the old mill"):
			told = true
	check("people pass on news that really happened", told)
	var camp := QuestTargets.nearest_poi(wm, city.position, false)
	Rumors.add("trouble", "Test: cutthroats at the camp.", camp.position, day, camp.id)
	check("trouble talked about in town", Rumors.trouble_near(city.position, day) == camp.id)
	var victim: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		if r.data.role == NpcData.Role.COMMONER and victim == null and r != leaders.get("fighters"):
			victim = r
	wm.life._on_died(null, victim)
	check("a murder becomes a rumor", Rumors.all().any(func(r: Dictionary) -> bool: return r["kind"] == "murder" and String(r["text"]).contains(victim.data.display_name)))
	victim.dead = false
	var barks := wm.get_node("Barks") as Barks
	var guard: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		if r.data.role == NpcData.Role.GUARD and guard == null:
			guard = r
	check("guards bark as you pass", guard != null and barks.bark_for(_speaker(guard)) != "")
	Reputation.add_fame(city.town.display_name, 40)
	check("people notice your fame", barks.bark_for(_speaker(guard)).length() > 0 and DialogueEngine._about_you(_speaker(guard), "background").contains("helped"))
	Reputation.add_fame(city.town.display_name, -40)
	Barks.voice(self, "Test", "A line.")
	check("the voice hook is silent without audio", true)


# ---------------------------------------------------------------- 1.12.14 authoring tools

func _authoring() -> void:
	print("-- authoring: validator, imports, test mode, custom people")
	check("the example quest passes the validator", QuestCheck.check_quest_data(wm, QuestRunner.get_data("maudrey_old_kings")).is_empty(), str(QuestCheck.check_quest_data(wm, QuestRunner.get_data("maudrey_old_kings"))))
	var bad := QuestData.new()
	bad.id = "broken"
	bad.giver = "Nobody Atall@Nowhere"
	bad.after = PackedStringArray(["no_such_quest"])
	var s1 := QuestStage.new()
	var o := QuestObjective.new()
	o.type = QuestObjective.Type.COLLECT
	o.target = "res://data/no/such_item.tres"
	o.place = "Atlantis"
	s1.objectives = [o]
	s1.next = 5
	var s2 := QuestStage.new()
	bad.stages = [s1, s2]
	var probs := QuestCheck.check_quest_data(wm, bad)
	check("the validator catches a deliberately broken quest (%d problems)" % probs.size(), probs.size() >= 5, "\n".join(probs))
	# dialogue written in a spreadsheet
	var imported := DialogueImport.load_dir(DialogueEngine.DIALOGUE_DIR)
	check("dialogue rows load from a .csv", imported.any(func(d: DialogueData) -> bool: return d.get_topic("the old mill") != null))
	var keeper: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		if r.data.role == NpcData.Role.INNKEEPER and keeper == null:
			keeper = r
	if keeper != null:
		var said := DialogueEngine.respond(_speaker(keeper), "the old mill", wm)
		check("and are spoken", String(said["text"]).contains("Burned down"))
		var resp := said.get("response") as DialogueResponse
		check("with branching choices", resp != null and resp.choices.has("who burned it"))
	# test mode: talk to anyone, start any quest at any stage
	var dc: DebugConsole = null
	for n in p.find_children("*", "DebugConsole", true, false):
		dc = n
	var name := (leaders["fighters"] as TownLife.Resident).data.display_name
	var out := dc.run("talk " + name)
	await frames(3)
	check("talk <name> opens a conversation with them", ui.is_open() and ui.speaker != null and ui.speaker.name == name, out)
	ui.close()
	await frames(2)
	WorldState.erase_record(QuestRunner.STATE + "maudrey_old_kings")
	dc.run("quest.setstage maudrey_old_kings 2")
	check("a handmade quest can be put at any stage", wm.runner.status("maudrey_old_kings") == "active" and int(QuestRunner.record("maudrey_old_kings").get("stage", 0)) == 1)
	# a custom person with gear, a schedule and a quest
	var c := CustomNpcData.new()
	c.id = "test_smith"
	c.display_name = "Test Smith"
	c.town = city.town.display_name
	c.offset = Vector3(5, 0, 5)
	c.home_offset = Vector3(-5, 0, -5)
	c.work_start = 8.0
	c.work_end = 18.0
	c.inventory = [load("res://data/ingredients/bloodmoss.tres")]
	var cn := wm.get_node("CustomNpcs") as CustomNpcs
	wm.clock.set_time(12.0)
	var work := cn.spot_of(c)
	wm.clock.set_time(22.0)
	var home := cn.spot_of(c)
	check("a custom person keeps hours: work by day, home at night", work.distance_to(home) > 10.0)
	wm.clock.set_time(12.0)
	var body := CustomNpcs.spawn(c, wm, p.global_position + Vector3(3, 0, 0))
	check("and carries what they were given", body.inventory.get_count(load("res://data/ingredients/bloodmoss.tres")) == 1)
	body.queue_free()
	check("text keys are ready for translation", tr("Quests") == "Quests")


# ---------------------------------------------------------------- 1.12.15 QA

func _qa() -> void:
	print("-- QA: every state saved, edge cases, speed, balance")
	var runner := wm.runner
	var id := "qa_states"
	var q := QuestData.new()
	q.id = id
	q.title = "QA States"
	var a := QuestStage.new()
	var o := QuestObjective.new()
	o.type = QuestObjective.Type.COLLECT
	o.target = "res://data/ingredients/thistle.tres"
	o.count = 2
	a.objectives = [o]
	var b := QuestStage.new()
	var c := QuestChoice.new()
	c.topic = "qa choice"
	b.choices = [c]
	q.stages = [a, b]
	QuestRunner.register(q)
	var inv := p.get_node("Inventory") as Inventory
	var thistle := load("res://data/ingredients/thistle.tres") as ItemData
	var states := []
	var snap := func() -> void:
		var before := runner.status(id)
		var stage := int(QuestRunner.record(id).get("stage", 0))
		var saved := WorldState.to_dict()
		WorldState.clear()
		WorldState.from_dict(saved)
		runner.recompute()
		states.append(runner.status(id) == before and int(QuestRunner.record(id).get("stage", 0)) == stage)
	snap.call()                       # available
	runner.start(id)
	snap.call()                       # active, stage 1
	inv.add_item(thistle, 2)
	await secs(1.0)
	snap.call()                       # active, stage 2 (the choice)
	runner._begin_stage(id, 2)
	snap.call()                       # ready
	inv.remove_item(thistle, inv.get_count(thistle))
	await secs(1.0)
	check("losing a collected item takes a ready quest back to active", runner.status(id) == "active")
	inv.add_item(thistle, 2)
	runner._begin_stage(id, 2)
	runner.complete(id)
	snap.call()                       # completed
	check("saved and loaded at every state, each comes back the same (%d states)" % states.size(), states.size() == 5 and states.all(func(x: bool) -> bool: return x), str(states))
	# a conversation ends when the person dies mid-talk
	var r: TownLife.Resident = null
	for res: TownLife.Resident in wm.life.get_town_residents(city.id):
		if res.data.role == NpcData.Role.COMMONER and res.node != null and is_instance_valid(res.node) and r == null:
			r = res
	if r == null:
		await _go(city.position)
		for res: TownLife.Resident in wm.life.get_town_residents(city.id):
			if res.data.role == NpcData.Role.COMMONER and res.node != null and is_instance_valid(res.node) and r == null:
				r = res
	if r != null and ui.open_with(r.node):
		await frames(3)
		var focus := ui.get_viewport().gui_get_focus_owner()
		check("the keyboard starts on the first topic", focus is Button and focus.get_parent() == ui._topics)
		r.node.stats.modify_vital("health", -999999.0)
		await frames(5)
		check("the conversation closes when they die mid-talk", not ui.is_open())
		WorldState.erase_record("kill/" + r.data.id)
		r.dead = false
	# speed
	var big := DialogueState.journal().duplicate(true)
	for n in DialogueState.JOURNAL_MAX:
		big.append({"text": "Line %d about nothing." % n, "topic": "Topic %d" % (n % 40), "type": "Knowledge", "quest_id": "", "day": 1, "id": 100000 + n, "read": false})
	WorldState.set_record(DialogueState.JOURNAL, {"entries": big})
	var ju := get_first_node_in_group("journal_ui") as JournalUI
	var t0 := Time.get_ticks_msec()
	ju.open()
	ju._tabs.current_tab = JournalUI.TAB_TOPICS
	ju._refresh()
	var ms := Time.get_ticks_msec() - t0
	ju.close()
	check("the journal opens fast with %d entries (%d ms)" % [big.size(), ms], ms < 1500)
	var list := QuestManager.all_quests().duplicate(true)
	for n in 60:
		list.append({"id": "perf%d" % n, "type": "kill", "name": "Perf", "status": "active", "target": "", "chief": "X", "faction": "fighters", "reward": 1, "pos": [0, 0], "objective": "x"})
	WorldState.set_record(QuestManager.STATE, {"list": list, "counter": QuestManager._counter()})
	t0 = Time.get_ticks_msec()
	wm.quests._check_ready()
	ms = Time.get_ticks_msec() - t0
	check("60 active jobs checked quickly (%d ms)" % ms, ms < 200)
	_clear_jobs()
	for n in 2500:
		DialogueState.learn("Made-up Topic %d" % n)
	t0 = Time.get_ticks_msec()
	DialogueEngine.topics_for(_speaker(leaders["fighters"]), wm)
	ms = Time.get_ticks_msec() - t0
	check("a person's topics are worked out quickly even with thousands known (%d ms)" % ms, ms < 400)
	# balance
	var t := Radiant.template("retrieve")
	var low := t.reward_base + t.reward_per_level * 1
	var high := t.reward_base + t.reward_per_level * 30
	check("rewards grow sensibly with level (%d at 1, %d at 30)" % [low, high], low >= 50 and low <= 200 and high > low * 2 and high < 800)
	check("cooldowns and limits are sensible", QuestManager.COOLDOWN_HOURS <= 6.0 and Radiant.TOWN_LIMIT >= 2 and Radiant.BOARD_DAYS <= 7)


func _clear_jobs() -> void:
	var list := QuestManager.all_quests().duplicate(true)
	for q: Dictionary in list:
		if q["status"] == "active":
			q["status"] = "abandoned"
	WorldState.set_record(QuestManager.STATE, {"list": list, "counter": QuestManager._counter()})


func _spawned_of(id: String, role: String) -> Array:
	var out: Array = []
	for key in wm.quests._radiant_spawned:
		if String(key).begins_with("quest/%s/%s" % [id, role]) and is_instance_valid(wm.quests._radiant_spawned[key]):
			out.append(wm.quests._radiant_spawned[key])
	return out


func _custom_body(d: CustomNpcData, spot: Vector3) -> Enemy:
	await _go(spot + Vector3(4, 0, 4))
	await secs(1.0)
	for e in get_nodes_in_group("enemies"):
		if (e as Node).has_meta("custom_npc") and (e as Node).get_meta("custom_npc") == d:
			return e
	return null


func _lifecycle() -> void:
	print("-- the life of a quest")
	var runner := wm.runner
	# a quest given by a townsperson who dies before it is handed in
	var giver: TownLife.Resident = null
	var lord: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		if r.data.role == NpcData.Role.COMMONER and giver == null and Factions.leader_of(_speaker(r), wm) == "":
			giver = r
		if r.data.role == NpcData.Role.LORD:
			lord = r
	var q := QuestData.new()
	q.id = "test_fallback"
	q.title = "Test Fallback"
	q.giver = giver.data.id
	q.hook = "test errand"
	var st := QuestStage.new()
	var o := QuestObjective.new()
	o.type = QuestObjective.Type.COLLECT
	o.target = "res://data/ingredients/bloodmoss.tres"
	o.count = 1
	st.objectives = [o]
	q.stages = [st]
	q.reward_gold = 10
	QuestRunner.register(q)
	check("the giver offers a registered quest", runner.topics_for(_speaker(giver)).has("test errand"))
	runner.respond(_speaker(giver), "test errand")
	(p.get_node("Inventory") as Inventory).add_item(load("res://data/ingredients/bloodmoss.tres"), 1)
	await secs(1.0)
	check("collecting it makes it ready", runner.status("test_fallback") == "ready")
	WorldState.set_record("kill/" + giver.data.id, {"dead": true})
	giver.dead = true
	check("with the giver dead, the lord takes it in", lord != null and runner.topics_for(_speaker(lord)).has("report back"))
	if lord != null:
		runner.respond(_speaker(lord), "report back")
	check("and it completes", runner.status("test_fallback") == "completed")
	giver.dead = false
	WorldState.erase_record("kill/" + giver.data.id)
	# time limits, abandoning, retrying, offers that run out
	var t := QuestData.new()
	t.id = "test_timed"
	t.title = "Test Timed"
	t.time_limit_hours = 1.0
	t.stages = [st]
	t.retry = false
	QuestRunner.register(t)
	runner.start("test_timed")
	wm.clock.set_time(wm.clock.hour + 2.0 if wm.clock.hour < 21.0 else 1.0, wm.clock.day + (0 if wm.clock.hour < 21.0 else 1))
	await secs(1.0)
	check("running out of time fails it", runner.status("test_timed") == "failed" and String(QuestRunner.record("test_timed").get("why", "")).contains("time"))
	check("a failed quest without retry is closed for good", not runner.can_offer(t))
	var a := QuestData.new()
	a.id = "test_abandon"
	a.title = "Test Abandon"
	a.stages = [st]
	QuestRunner.register(a)
	runner.start("test_abandon")
	runner.abandon("test_abandon")
	check("abandoning ends it", runner.status("test_abandon") == "abandoned")
	check("it can be offered again only after a while", not runner.can_offer(a))
	wm.clock.set_time(wm.clock.hour, wm.clock.day + 4)
	check("then it can", runner.can_offer(a))
	check("every ended quest is exactly one ending", ["completed", "failed", "abandoned"].all(func(s: String) -> bool: return QuestRunner.ENDED.has(s)))
	var cond := QuestCondition.new()
	cond.kind = QuestCondition.Kind.TIME_OF_DAY
	cond.amount = int(wm.clock.hour)
	cond.amount2 = int(wm.clock.hour) + 1
	check("a time-of-day condition", cond.passes(self))
	cond.kind = QuestCondition.Kind.QUEST_DONE
	cond.key = "maudrey_old_kings"
	check("a quest-done condition", cond.passes(self))
	check("notices queue instead of overlapping", Notices.of(self) != null)


# ---------------------------------------------------------------- 1.12.4 / 1.12.5 dialogue

func _dialogue_roles() -> void:
	print("-- who talks about what")
	# the player knows every topic in the world
	for e: Dictionary in DialogueEngine.index(wm).entries.values():
		DialogueState.learn(String(e["name"]))
	var by_role := {}
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		var sp := _speaker(r)
		var plain := Factions.leader_of(sp, wm) == "" and wm.book.topics_for(sp).is_empty()  # no guild or quest of their own
		if not by_role.has(r.data.role) and plain:
			by_role[r.data.role] = r
	var commoner: TownLife.Resident = by_role.get(NpcData.Role.COMMONER, by_role.get(NpcData.Role.FARMER))
	check("the city has a commoner or farmer", commoner != null)
	if commoner == null:
		return
	var cs := _speaker(commoner)
	var topics := DialogueEngine.topics_for(cs, wm)
	check("a commoner has no Duties", not topics.has("duties"), str(topics))
	check("a guild leader does", DialogueEngine.topics_for(_speaker(leaders["fighters"]), wm).has("duties"))
	var named := Array(topics).filter(func(t: String) -> bool: return not DialogueEngine.GENERIC.has(t))
	check("a commoner lists a handful of named topics, not dozens (%d)" % named.size(), named.size() <= 6 and named.size() >= 2, str(named))
	check("including their own town", topics.has(city.town.display_name), str(topics))
	check("the same answer list every visit", DialogueEngine.topics_for(cs, wm) == topics)
	wm.clock.set_time(12.0, wm.clock.day + 1)
	check("and the next day too", DialogueEngine.topics_for(cs, wm) == topics)
	var guard: TownLife.Resident = by_role.get(NpcData.Role.GUARD)
	if guard != null:
		var gt := DialogueEngine.topics_for(_speaker(guard), wm)
		check("a guard talks about the law", gt.has("the law"), str(gt))
		check("a guard lists at most 8 named topics", Array(gt).filter(func(t: String) -> bool: return not DialogueEngine.GENERIC.has(t)).size() <= 8, str(gt))
	check("a commoner doesn't talk about the law", not topics.has("the law"))
	var merchant: TownLife.Resident = by_role.get(NpcData.Role.MERCHANT)
	if merchant != null:
		var mt := DialogueEngine.topics_for(_speaker(merchant), wm)
		check("a merchant has no little advice to give", not mt.has("little advice") and mt.has("my trade"), str(mt))
	var far := 0
	for t in topics:
		for town in wm.towns:
			if town.town.display_name == t and town.position.distance_to(city.position) > 6000.0:
				far += 1
	check("a commoner doesn't talk about towns far away", far == 0)


# ---------------------------------------------------------------- 1.12.4 / 1.12.5 buttons and lines

func _dialogue_services() -> void:
	print("-- service buttons, training, persuasion, lines")
	var by_role := {}
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		var sp := _speaker(r)
		if not by_role.has(r.data.role) and Factions.leader_of(sp, wm) == "" and wm.book.topics_for(sp).is_empty():
			by_role[r.data.role] = r
	var ids := func(r: TownLife.Resident) -> Array:
		return Services.for_speaker(_speaker(r), wm, p).map(func(x: Dictionary) -> String: return x["id"])
	var commoner: TownLife.Resident = by_role.get(NpcData.Role.COMMONER, by_role.get(NpcData.Role.FARMER))
	check("a commoner has no service buttons", commoner != null and not ids.call(commoner).has("duties") and not ids.call(commoner).has("train"), str(ids.call(commoner)))
	check("a guild leader has Duties", ids.call(leaders["fighters"]).has("duties"))
	check("a Mages Guild leader can enchant", ids.call(leaders["mages"]).has("enchant"))
	var keeper: TownLife.Resident = by_role.get(NpcData.Role.INNKEEPER)
	if keeper != null:
		check("an innkeeper rents rooms", ids.call(keeper).has("rent"), str(ids.call(keeper)))
		check("and talks about rooms", DialogueEngine.profile_for(_speaker(keeper), wm).generic.has("rooms"))
	var smith: TownLife.Resident = by_role.get(NpcData.Role.SMITH)
	if smith != null:
		var sp := _speaker(smith)
		check("a smith trains and repairs", ids.call(smith).has("train") and ids.call(smith).has("repair"), str(ids.call(smith)))
		var sk := p.get_node("Skills") as Skills
		var inv := p.get_node("Inventory") as Inventory
		Currency.add_gold(inv, 5000)
		var before := sk.get_level(&"smithing")
		var gold := Currency.get_gold(inv)
		var left := Services.trainings_left(p)
		var said := Services.train("smithing", sp, wm, p)
		check("training raises the skill for gold", sk.get_level(&"smithing") == before + 1 and Currency.get_gold(inv) < gold, said)
		check("and counts toward the limit per level", Services.trainings_left(p) == left - 1)
		check("trainers stop at their limit", Services.train_max(sp, wm) > 0)
	var cs := _speaker(commoner)
	check("the same person gives the same answer", String(DialogueEngine.respond(cs, "small talk", wm)["text"]) == String(DialogueEngine.respond(cs, "small talk", wm)["text"]))
	check("small talk is not written in the journal", DialogueState.entry_type("small talk", "", "generic") == "")
	check("a farewell", DialogueEngine.farewell(cs, wm) != "")
	check("placeholders are filled from the world", not DialogueEngine._fill("{town} {guild} {nearest_poi} {nearest_town}", cs, wm).contains("{"))
	check("the hand-written dialogue has no problems", DialogueTools.lint().is_empty(), str(DialogueTools.lint()))
	check("the duplicate finder runs", DialogueTools.duplicates(wm) is PackedStringArray)
	check("near-identical lines are spotted", DialogueTools.similarity("The bridge is down to the north.", "The bridge is down to the north!") >= 0.8)
	check("a dialogue audit lists topics and buttons", DialogueTools.audit(cs, wm, p).size() > 2)
	# persuasion: a failure closes that approach for a while
	Persuasion.lock(Persuasion.Kind.JOKE, cs, wm.quests._hours())
	check("a failed approach is locked", Persuasion.locked(Persuasion.Kind.JOKE, cs, wm.quests._hours()))
	check("and opens again later", not Persuasion.locked(Persuasion.Kind.JOKE, cs, wm.quests._hours() + 2.0))
	# in the window: asked topics, typewriter
	if commoner.node != null and is_instance_valid(commoner.node) and ui.open_with(commoner.node):
		ui.ask("small talk")
		check("asked topics are remembered (dimmed)", DialogueState.was_asked("small talk"))
		GameSettings.set_value("dialogue_typewriter", true)
		ui.ask("background")
		check("typewriter text appears letter by letter", ui._typing and ui._log.visible_characters < ui._log.get_total_character_count())
		ui.skip_typing()
		check("a click shows it all", ui._log.visible_characters == -1)
		GameSettings.set_value("dialogue_typewriter", false)
		ui.close()


# ---------------------------------------------------------------- the main quest's priest

func _main_story() -> void:
	print("-- the main quest")
	var story := get_first_node_in_group("story") as Story
	check("the story runs", story != null)
	if story == null:
		return
	WorldState.erase_record(Story.ID)
	story._begin(p)
	var st := Story.state()
	check("the story starts with the letter", Story.stage() == 1)
	var priest: TownLife.Resident = null
	for t in wm.towns:
		if t.id == String(st.get("town", "")):
			for r: TownLife.Resident in wm.life.get_town_residents(t.id):
				if r.data.work_id == String(st["temple"]):
					priest = r
	check("the temple has its priest", priest != null)
	if priest == null:
		return
	var b := wm.get_building(String(st["temple"]))
	var mark: Vector2 = Story.target()["pos"]
	check("the marker points at the temple", mark.distance_to(Vector2(b.world_pos.x, b.world_pos.z)) < 1.0)
	Locks.set_locked(b.id, false)
	wm.clock.set_time(priest.data.work_start + 1.0)
	await _go(b.get_door_position())
	await wm.dungeons.enter(b.id, b.get_door_position(), 0.0)
	await secs(0.5)
	var opened := priest.node != null and is_instance_valid(priest.node) and ui.open_with(priest.node)
	check("you can talk to the priest", opened)
	if opened:
		var topics := DialogueEngine.topics_for(ui.speaker, wm)
		check("the priest lists \"the sealed letter\"", topics.has("the sealed letter"), str(topics))
		ui.ask("the sealed letter")
		check("asking moves the main quest on", Story.stage() == 2, str(Story.state()))
		ui.close()
	await wm.dungeons.exit()
	await secs(0.5)
	wm.clock.set_time(12.0)


# ---------------------------------------------------------------- 1.12.6 journal

func _journal_cleanup() -> void:
	print("-- the journal")
	var before := DialogueState.journal().size()
	for i in 10:
		DialogueState.add_journal({"text": "Brightwater is %d km to the north. Variant %d." % [i + 1, i], "speaker": "Person %d" % i, "topic": "Brightwater", "day": 1})
	var about := DialogueState.journal().filter(func(e: Dictionary) -> bool: return e["topic"] == "Brightwater")
	check("ten people on one topic make one entry", about.size() == 1 and DialogueState.journal().size() == before + 1, str(about.size()))
	check("it remembers who said it", about.size() == 1 and (about[0]["heard"] as Array).size() == 10)
	check("and keeps the newest words", about.size() == 1 and String(about[0]["text"]).contains("Variant 9"))
	DialogueState.add_journal({"text": "Quest line one.", "speaker": "A", "topic": "Brightwater", "quest_id": "q99", "quest_name": "X"})
	DialogueState.add_journal({"text": "Quest line two.", "speaker": "A", "topic": "Brightwater", "quest_id": "q99", "quest_name": "X"})
	check("quest lines are all kept", DialogueState.journal().filter(func(e: Dictionary) -> bool: return e["quest_id"] == "q99").size() == 2)
	# an old save, full of near-duplicates
	var old := DialogueState.journal().duplicate(true)
	for i in 5:
		old.append({"text": "Old line %d" % i, "speaker": "Old %d" % i, "topic": "Old Topic", "place": "", "day": 1, "time": "", "quest_id": "", "quest_name": ""})
	WorldState.set_record(DialogueState.JOURNAL, {"entries": old})
	var gone := DialogueState.compact_journal()
	check("an old save's duplicates are cleaned (%d removed)" % gone, gone == 4 and DialogueState.journal().filter(func(e: Dictionary) -> bool: return e["topic"] == "Old Topic").size() == 1)


# ---------------------------------------------------------------- 1.12.7 notes

func _notes() -> void:
	print("-- your own notes")
	var ju := get_first_node_in_group("journal_ui") as JournalUI
	check("the journal exists", ju != null)
	if ju == null:
		return
	ju.open()
	ju.edit_note(0)
	check("+ New note opens the editor", ju.is_editing())
	ju._note_title.text = "Smith's prices"
	ju._note_body.text = "The smith in town buys swords dear."
	var id := ju.save_note()
	var n := DialogueState.get_note(id)
	check("a note is saved with its title and words", n.get("title") == "Smith's prices" and n.get("text") == "The smith in town buys swords dear.")
	check("and the day and place it was written", int(n.get("day", 0)) >= 1 and String(n.get("place", "")) != "", str(n))
	ju.edit_note(id)
	ju._note_body.grab_focus()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.keycode = KEY_J
	key.unicode = "j".unicode_at(0)
	key.pressed = true
	root.push_input(key)
	await process_frame
	check("typing J in a note doesn't close the journal", ju.is_open() and ju.is_editing())
	ju._note_body.text = "The smith pays well for swords."
	ju.close()
	check("closing the journal mid-edit keeps the words", DialogueState.get_note(id).get("text") == "The smith pays well for swords.")
	ju.open()
	ju.edit_note(id)
	ju.delete_note()
	check("Delete asks first", not DialogueState.get_note(id).is_empty())
	ju.delete_note()
	check("and then deletes it", DialogueState.get_note(id).is_empty())
	ju.close()
	DialogueState.add_note("Kept", "This one survives a load.", 1, "", "")


# ---------------------------------------------------------------- 1.12.14 custom NPCs

func _custom_npc() -> void:
	print("-- a hand-made person")
	var hermit: CustomNpcData = null
	for d in CustomNpcs.all():
		if d.id == "example_hermit":
			hermit = d
	check("the example custom NPC is found", hermit != null)
	if hermit == null:
		return
	var spot := (wm.get_node("CustomNpcs") as CustomNpcs).spot_of(hermit)
	await _go(spot + Vector3(4, 0, 4))
	await secs(1.0)
	var body: Enemy = null
	for e in get_nodes_in_group("enemies"):
		if (e as Node).has_meta("custom_npc") and (e as Node).get_meta("custom_npc") == hermit:
			body = e
	check("they stand in their town when you come near", body != null and body.global_position.distance_to(spot) < 5.0)
	if body == null or not ui.open_with(body):
		check("and talk", false)
		return
	var topics := DialogueEngine.topics_for(ui.speaker, wm)
	check("they talk about their own topics only", topics.has("the dark noon") and not topics.has("latest rumors") and not topics.has("duties"), str(topics))
	ui.ask("the dark noon")
	check("their answer teaches a new topic", DialogueEngine.topics_for(ui.speaker, wm).has("the old kings"))
	var cold := String(ui.ask("the old kings")["text"])
	DialogueState.change_disposition(ui.speaker.id, ui.speaker.base_disposition, 20)
	var warm := String(ui.ask("the old kings")["text"])
	check("their answers depend on how much they like you", cold.contains("only to friends") and warm.contains("Crypt of Kings"), cold + " / " + warm)
	ui.close()


## Guild jobs: failing, abandoning, waiting for the next one
func _job_rules() -> void:
	print("-- job rules")
	var qm := wm.quests
	var cool := QuestManager.cooldown_left("fighters", qm._hours())
	check("after a job, the guild waits before the next", cool > 0.0)
	var said := qm.respond(_speaker(leaders["fighters"]), "duties")
	check("and says so", String(said.get("text", "")).contains("Come back in"), String(said.get("text", "")))
	WorldState.erase_record(QuestManager.COOLDOWN)
	var q := _job("mages", "persuade")
	var r: TownLife.Resident = wm.life.get_resident(String(q.get("target", "")))
	if r != null:
		r.dead = true
		await secs(1.5)
		check("the person dying fails a persuade job", QuestManager.get_quest(String(q["id"]))["status"] == "failed")
		check("with the reason", String(QuestManager.get_quest(String(q["id"])).get("fail_reason", "")).contains("dead"))
		r.dead = false
	var k := _job("fighters", "kill")
	var rep := Reputation.get_rep("fighters")
	qm.abandon(k)
	check("abandoning a job ends it", QuestManager.get_quest(String(k["id"]))["status"] == "abandoned")
	check("and the guild thinks less of you", Reputation.get_rep("fighters") < rep)
	check("finished jobs raised guild reputation", rep > 0)
	var later := QuestManager.get_quest(String(k["id"]))
	check("a job's pay grows with level (it records the level-based reward)", int(later["reward"]) > 0)


## The quest.* debug console commands
func _console() -> void:
	var dc: DebugConsole = null
	for n in p.find_children("*", "DebugConsole", true, false):
		dc = n
	check("the debug console exists", dc != null)
	if dc == null:
		return
	var out := dc.run("quest.start fighters kill")
	var q := QuestManager.active_for("fighters")
	check("quest.start makes a guild job", not q.is_empty() and q["type"] == "kill", out)
	check("quest.why says what blocks it", dc.run("quest.why").contains("still alive"), dc.run("quest.why"))
	dc.run("quest.complete " + String(q["id"]))
	check("quest.complete finishes it", QuestManager.get_quest(String(q["id"]))["status"] == "done")
	dc.run("quest.start S-KR01")
	check("quest.start starts a written quest", QuestBook.is_active("S-KR01"))
	dc.run("quest.setstage S-KR01 2")
	check("quest.setstage jumps to a step", int(QuestBook.state("S-KR01").get("step", 0)) == 1)
	check("quest.list shows it", dc.run("quest.list").contains("S-KR01"))
	dc.run("quest.fail S-KR01")
	check("quest.fail fails it", QuestBook.status("S-KR01") == "failed")
	dc.run("quest.reset S-KR01")
	check("quest.reset forgets it", QuestBook.status("S-KR01") == "")
	check("quest.check finds nothing wrong", dc.run("quest.check") == "No problems found.", dc.run("quest.check"))
	dc.run("quest.overlay")
	check("quest.overlay shows the overlay", dc._overlay != null)
	dc.run("quest.overlay")


## Take a job, save, load, then finish it: nothing about it may be lost
func _across_a_load() -> void:
	var q := _job("fighters", "kill")
	if q.is_empty():
		return
	var sm := get_first_node_in_group("save_manager") as SaveManager
	check("save mid-job", sm != null and sm.save_game("slot_test112"), sm.get_last_error() if sm != null else "no SaveManager")
	check("load it", sm.load_game("slot_test112"), sm.get_last_error())
	await frames(150)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as CharacterBody3D
	ui = get_first_node_in_group("dialogue_ui") as DialogueUI
	for f in leaders.keys():
		leaders[f] = wm.life.get_resident((leaders[f] as TownLife.Resident).data.id)
	var after := QuestManager.get_quest(String(q["id"]))
	check("after loading, the job is still active", String(after.get("status", "")) == "active", str(after))
	check("after loading, your notes are still there", DialogueState.notes().any(func(n: Dictionary) -> bool: return n["title"] == "Kept"))
	var camp := wm.get_poi(String(q["target"]))
	await _go(camp.position + Vector3(0, 0, 25))
	var chief: Enemy = null
	for e in wm.get_garrison(camp.id):
		if is_instance_valid(e) and e.display_name == String(q["chief"]):
			chief = e
	check("after loading, the chief is at the camp", chief != null)
	if chief != null:
		var hit := DamageInfo.new(999999.0, p, &"melee")
		hit.direction = Vector3(0, 0, 1)
		chief.combat.take_damage(hit)
		await frames(5)
	var said := await _ask_leader("fighters", "report back")
	check("after loading, the job can be handed in", String(said.get("text", "")).begins_with("Well done"), String(said.get("text", "")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://saves/slot_test112.json"))


func _speaker(r: TownLife.Resident) -> DialogueEngine.Speaker:
	var s := DialogueEngine.Speaker.new()
	s.data = r.data
	s.id = r.data.id
	s.name = r.data.display_name
	s.role = r.data.role
	s.personality = r.data.personality
	s.base_disposition = r.data.base_disposition
	s.town = r.town
	s.home = wm.get_building(r.data.home_id)
	return s


func _go(at: Vector3) -> void:
	wm.ensure_area_loaded(at, 2)
	p.global_position = Vector3(at.x, wm.get_height_at(at.x, at.z) + 1.5, at.z)
	p.velocity = Vector3.ZERO
	await secs(1.0)


## Walks into the leader's building and asks them about a topic through the dialogue window
func _ask_leader(faction: String, topic: String) -> Dictionary:
	var r: TownLife.Resident = leaders[faction]
	var b := wm.get_building(r.data.home_id)
	Locks.set_locked(b.id, false)
	await _go(b.get_door_position())
	await wm.dungeons.enter(b.id, b.get_door_position(), 0.0)
	await secs(0.5)
	var said := {}
	if r.node != null and is_instance_valid(r.node) and ui.open_with(r.node):
		said = ui.ask(topic)
		ui.close()
	else:
		check("%s's leader is there to talk to" % faction, false)
	await wm.dungeons.exit()
	await secs(0.5)
	return said


## A job of one kind from this guild, offered the way the leader offers it
func _job(faction: String, type: String) -> Dictionary:
	var q := wm.quests.offer(faction, _speaker(leaders[faction]), type)
	check("%s offers a %s job" % [faction, type], not q.is_empty())
	return q


func _retrieve() -> void:
	var q := _job("fighters", "retrieve")
	if q.is_empty():
		return
	var entrance := wm.get_poi(String(q["target"]))
	await _go(entrance.position + Vector3(0, 0, -6))
	var ok: bool = await wm.dungeons.enter(entrance.id, entrance.position + Vector3(0, 0, -6), 0.0)
	await secs(0.5)
	if ok and wm.dungeons.floor_count > 1:
		await wm.dungeons.go_floor(wm.dungeons.floor_count - 1)
		await secs(0.5)
	var item := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
	var chest: ContainerComponent = null
	if wm.dungeons.is_inside():
		for c in wm.dungeons.get_interior_root().find_children("*", "ContainerComponent", true, false):
			if (c as ContainerComponent).save_id == String(q["container"]):
				chest = c
	check("retrieve: the boss chest holds the item", chest != null and chest.inventory.has_item(item),
		"floors %d, chest %s" % [wm.dungeons.floor_count, chest != null])
	var before: Vector2 = QuestManager.active_targets().filter(func(t: Dictionary) -> bool: return t["id"] == q["id"])[0]["pos"]
	if chest != null:
		_take_all(chest)
	await wm.dungeons.exit()
	await secs(1.5)
	check("retrieve: carrying it, the job is ready", wm.quests.is_ready(q))
	var now := QuestManager.get_quest(String(q["id"]))
	check("retrieve: ready is noticed and written down", bool(now.get("ready", false))
		and DialogueState.journal().any(func(e: Dictionary) -> bool: return String(e.get("quest_id", "")) == q["id"] and String(e["text"]).begins_with("Done.")))
	var after: Vector2 = QuestManager.active_targets().filter(func(t: Dictionary) -> bool: return t["id"] == q["id"])[0]["pos"]
	var home := wm.get_building((leaders["fighters"] as TownLife.Resident).data.home_id).world_pos
	check("retrieve: the marker moves from the dungeon to the giver", before.distance_to(after) > 50.0 and after.distance_to(Vector2(home.x, home.z)) < 1.0, "%s -> %s" % [before, after])
	check("retrieve: the leader now has a \"report back\" topic", wm.quests.extra_topics(_speaker(leaders["fighters"])).has("report back"))
	var said := await _ask_leader("fighters", "report back")
	check("retrieve: the leader takes it and pays", String(said.get("text", "")).begins_with("Well done"), String(said.get("text", "")))


func _kill() -> void:
	var q := _job("fighters", "kill")
	if q.is_empty():
		return
	var camp := wm.get_poi(String(q["target"]))
	await _go(camp.position + Vector3(0, 0, 25))
	var chief: Enemy = null
	for e in wm.get_garrison(camp.id):
		if is_instance_valid(e) and e.display_name == String(q["chief"]):
			chief = e
	check("kill: the chief is at the camp", chief != null)
	if chief != null:
		var hit := DamageInfo.new(999999.0, p, &"melee")
		hit.direction = Vector3(0, 0, 1)
		chief.combat.take_damage(hit)
		await frames(5)
	check("kill: the job is ready", wm.quests.is_ready(q))
	var said := await _ask_leader("fighters", "report back")
	check("kill: the leader pays", String(said.get("text", "")).begins_with("Well done"), String(said.get("text", "")))


func _steal() -> void:
	var q := _job("thieves", "steal")
	if q.is_empty():
		return
	var house := wm.get_building(String(q["target"]))
	Locks.set_locked(house.id, false)
	await _go(house.get_door_position())
	await wm.dungeons.enter(house.id, house.get_door_position(), 0.0)
	await secs(0.5)
	var item := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
	var chest: ContainerComponent = null
	if wm.dungeons.is_inside():
		for c in wm.dungeons.get_interior_root().find_children("*", "ContainerComponent", true, false):
			if (c as ContainerComponent).save_id == String(q["container"]):
				chest = c
	check("steal: the owner's chest holds the item", chest != null and chest.inventory.has_item(item))
	if chest != null:
		(p.get_node("Stealth") as Stealth).awareness.clear()
		_take_all(chest)
	await wm.dungeons.exit()
	await secs(0.5)
	check("steal: the job is ready", wm.quests.is_ready(q))
	var said := await _ask_leader("thieves", "report back")
	check("steal: the contact pays", String(said.get("text", "")).begins_with("Well done"), String(said.get("text", "")))


func _persuade() -> void:
	var q := _job("mages", "persuade")
	if q.is_empty():
		return
	var r: TownLife.Resident = wm.life.get_resident(String(q["target"]))
	check("persuade: the person exists", r != null)
	if r == null:
		return
	DialogueState.change_disposition(r.data.id, r.data.base_disposition, 100)
	check("persuade: once they like you, the job is ready", wm.quests.is_ready(q))
	var said := await _ask_leader("mages", "report back")
	check("persuade: the leader pays", String(said.get("text", "")).begins_with("Well done"), String(said.get("text", "")))


func _take_all(c: ContainerComponent) -> void:
	var inv := p.get_node("Inventory") as Inventory
	var totals := {}
	for s in c.inventory.stacks:
		totals[s.item] = int(totals.get(s.item, 0)) + s.count
	for item: ItemData in totals:
		if c.inventory.remove_item(item, totals[item]):
			inv.add_item(item, totals[item])
