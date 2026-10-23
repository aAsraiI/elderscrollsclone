extends SceneTree
## Headless tests for stage 4: dialogue, topics, disposition, persuasion, the journal. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage4.gd

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
	t_state()
	t_journal_filter()
	t_persuasion_math()
	t_words()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- pure logic

func t_state() -> void:
	print("-- what the player knows")
	WorldState.clear()
	check("you start knowing the general topics", DialogueState.known_topics() == PackedStringArray(DialogueState.START_TOPICS))
	check("learning a topic", DialogueState.learn("Dunwatch") and DialogueState.knows("Dunwatch"))
	check("learning it twice does nothing", not DialogueState.learn("Dunwatch") and DialogueState.known_topics().size() == DialogueState.START_TOPICS.size() + 1)
	check("disposition starts at the base", DialogueState.get_disposition("npc/x", 50) == 50)
	check("and changes", DialogueState.change_disposition("npc/x", 50, 12) == 62 and DialogueState.get_disposition("npc/x", 50) == 62)
	check("it never goes past 100 or below 0", DialogueState.change_disposition("npc/x", 50, 500) == 100 and DialogueState.change_disposition("npc/x", 50, -500) == 0)
	check("a remembered person's disposition is saved", WorldState.has_record("disp/npc/x"))
	DialogueState.change_disposition("temp:7", 50, 5)
	check("a traveler's is not saved", not WorldState.has_record("disp/temp:7") and DialogueState.get_disposition("temp:7", 50) == 55)
	DialogueState.set_flag("asked")
	check("flags", DialogueState.has_flag("asked") and not DialogueState.has_flag("other"))
	var e := {"text": "The cave is east.", "speaker": "Brenna", "topic": "latest rumors", "place": "Dunwatch", "day": 2, "time": "10:00"}
	check("a line goes into the journal", DialogueState.add_journal(e) and DialogueState.journal().size() == 1)
	var e2 := e.duplicate()
	e2["speaker"] = "Osric"
	check("the same words from someone else are not written twice", not DialogueState.add_journal(e2) and DialogueState.journal().size() == 1)
	check("the first speaker is the one kept", DialogueState.journal()[0]["speaker"] == "Brenna")
	check("empty lines are ignored", not DialogueState.add_journal({"text": "  "}))
	WorldState.clear()


func t_journal_filter() -> void:
	print("-- journal search and filters")
	var entries := [
		{"text": "Bandits camp east of the river.", "speaker": "Brenna Ashford", "topic": "latest rumors", "place": "Dunwatch", "quest_id": "", "quest_name": ""},
		{"text": "I lost a ring in the cellar.", "speaker": "Osric Vance", "topic": "a lost ring", "place": "Ashford", "quest_id": "ring", "quest_name": "The Lost Ring"},
		{"text": "The ring was my mother's.", "speaker": "Osric Vance", "topic": "a lost ring", "place": "Ashford", "quest_id": "ring", "quest_name": "The Lost Ring"},
		{"text": "Dunwatch is a village in the plains.", "speaker": "Wren Yew", "topic": "Dunwatch", "place": "Dunwatch", "quest_id": "", "quest_name": ""},
	]
	check("no search, no filter: everything", JournalUI.filter(entries, "").size() == 4)
	check("search finds words in the text, any case", JournalUI.filter(entries, "BANDITS").size() == 1)
	check("search finds the speaker", JournalUI.filter(entries, "osric").size() == 2)
	check("search finds the place", JournalUI.filter(entries, "dunwatch").size() == 2)
	check("search finds the quest name", JournalUI.filter(entries, "lost ring").size() == 2)
	check("quest filter", JournalUI.filter(entries, "", "quest", "ring").size() == 2)
	check("quest filter plus search", JournalUI.filter(entries, "mother", "quest", "ring").size() == 1)
	check("topic filter (asked about it, or mentioned in the text)", JournalUI.filter(entries, "", "topic", "Dunwatch").size() == 1 and JournalUI.filter(entries, "", "topic", "latest rumors").size() == 1)
	check("nothing matches: nothing shown", JournalUI.filter(entries, "dragon").is_empty())
	check("matches are highlighted", JournalUI._mark("The ring was mine", "RING").contains("[bgcolor"))


func t_persuasion_math() -> void:
	print("-- persuasion odds")
	var P := Persuasion.Kind
	var proud := NpcData.Personality.PROUD
	var grumpy := NpcData.Personality.GRUMPY
	var cheerful := NpcData.Personality.CHEERFUL
	var nervous := NpcData.Personality.NERVOUS
	var commoner := NpcData.Role.COMMONER
	check("proud people like admiration more than grumpy ones", Persuasion.chance(P.ADMIRE, 20, 50, proud, commoner) > Persuasion.chance(P.ADMIRE, 20, 50, grumpy, commoner))
	check("cheerful people like jokes, grumpy ones don't", Persuasion.chance(P.JOKE, 20, 50, cheerful, commoner) > Persuasion.chance(P.JOKE, 20, 50, grumpy, commoner) + 0.3)
	check("nervous people fold when threatened, proud ones don't", Persuasion.chance(P.INTIMIDATE, 20, 50, nervous, commoner) > Persuasion.chance(P.INTIMIDATE, 20, 50, proud, commoner) + 0.25)
	check("guards are hard to intimidate", Persuasion.chance(P.INTIMIDATE, 20, 50, nervous, NpcData.Role.GUARD) < Persuasion.chance(P.INTIMIDATE, 20, 50, nervous, commoner))
	check("a bigger bribe works better", Persuasion.chance(P.BRIBE_1000, 20, 50, cheerful, commoner) > Persuasion.chance(P.BRIBE_10, 20, 50, cheerful, commoner) + 0.2)
	check("Speech makes everything easier", Persuasion.chance(P.ADMIRE, 80, 50, proud, commoner) > Persuasion.chance(P.ADMIRE, 5, 50, proud, commoner) + 0.3)
	check("liking you already helps", Persuasion.chance(P.JOKE, 20, 90, cheerful, commoner) > Persuasion.chance(P.JOKE, 20, 20, cheerful, commoner))
	var lo := Persuasion.chance(P.JOKE, 1, 0, grumpy, NpcData.Role.GUARD)
	var hi := Persuasion.chance(P.BRIBE_1000, 100, 100, cheerful, commoner)
	check("there is always some chance either way", lo >= 0.05 and hi <= 0.95)


func t_words() -> void:
	print("-- directions")
	check("compass: +X is east, -Z is north", DialogueEngine.compass(Vector2(10, 0)) == "east" and DialogueEngine.compass(Vector2(0, -10)) == "north" and DialogueEngine.compass(Vector2(-7, 7)) == "south-west")
	check("distances in words", DialogueEngine.distance_words(80) == "a short walk" and DialogueEngine.distance_words(420) == "about 400 meters" and DialogueEngine.distance_words(2300) == "about 2.3 km")


# ---------------------------------------------------------------- in a running world

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
	var dlg := DialogueUI.new()
	dlg.name = "DialogueUI"
	p.add_child(dlg)
	var journal := JournalUI.new()
	journal.name = "JournalUI"
	p.add_child(journal)
	p.add_to_group("player")
	parent.add_child(p)
	return p


func _settings() -> WorldSettings:
	var s := (load(R + "world/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	return s


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func t_world() -> void:
	print("-- talking in a running world")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var player := make_player(holder)
	var inv := player.get_node("Inventory") as Inventory
	var skills := player.get_node("Skills") as Skills
	var ui := player.get_node("DialogueUI") as DialogueUI
	var journal := player.get_node("JournalUI") as JournalUI
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = _settings()
	holder.add_child(wm)
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)
	var town := wm.get_nearest_town(player.global_position)
	player.global_position = Vector3(town.position.x, town.position.y + 1.0, town.position.z)
	await secs(1.0)

	# the index
	var ix := DialogueEngine.index(wm)
	check("towns are topics", ix.entries.has(town.town.display_name.to_lower()))
	check("buildings and people are topics", ix.entries.has(town.town.buildings[0].display_name.to_lower()) and ix.entries.has(town.town.buildings[0].owner_name.to_lower()))
	check("guilds are topics", ix.entries.has("fighters guild") and ix.entries.has("mages guild") and ix.entries.has("knightly order"))
	var poi_topics := 0
	for k in ix.entries:
		if ix.entries[k]["kind"] == "poi":
			poi_topics += 1
	check("places in the wild are topics (\"Bandit Camp east of ...\")", poi_topics > 10, str(poi_topics))
	var found := DialogueEngine.find_topics("Have you been to %s? Ask at the Fighters Guild." % town.town.display_name, ix)
	check("topic names are found in what people say", found.size() == 2 and found[0]["name"] == town.town.display_name and found[1]["name"] == "Fighters Guild")
	check("a longer name wins over a shorter one inside it", DialogueEngine.find_topics("the Fighters Guild Hall", ix)[0]["name"] == "Fighters Guild Hall")

	# someone to talk to
	var talker: TownLife.Resident = null
	var keeper: TownLife.Resident = null
	var guard: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.node == null or not is_instance_valid(r.node) or r.node_inside:
			continue
		if r.data.role == NpcData.Role.GUARD:
			guard = r
		elif talker == null:
			talker = r
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.INNKEEPER:
			keeper = r
	check("there is someone outside to talk to", talker != null)
	var body := talker.node
	var talk := body.get_node_or_null("NpcTalk") as NpcTalk
	talk.interact(inv)
	check("pressing E opens the dialogue window", ui.is_open() and paused)
	check("it knows who it is talking to", ui.speaker != null and ui.speaker.name == talker.data.display_name and ui.speaker.home != null)
	var s := ui.speaker
	check("the general topics are listed", DialogueEngine.topics_for(s, wm).has("background") and DialogueEngine.topics_for(s, wm).has("latest rumors"))
	DialogueState.learn("the law")
	check("townsfolk send you to a guard about the law", String(DialogueEngine.respond(s, "the law", wm)["text"]).contains("guard"))
	var r1 := ui.ask("background")
	check("asking about background gives an answer", String(r1.get("text", "")).length() > 10, String(r1.get("text", "")))
	check("which mentions their home, and you learn it as a topic", DialogueState.knows(s.home.display_name), s.home.display_name)
	check("and the town", DialogueState.knows(town.town.display_name))
	check("the answer is written in the journal", DialogueState.journal().size() == 1 and DialogueState.journal()[0]["speaker"] == talker.data.display_name and DialogueState.journal()[0]["topic"] == "background")
	ui.ask("background")
	check("asking again adds nothing new", DialogueState.journal().size() == 1)
	check("the new topics show up in the list", DialogueEngine.topics_for(s, wm).has(town.town.display_name))
	var rt := ui.ask(town.town.display_name)
	check("they talk about their own town", String(rt["text"]).contains(town.town.display_name))
	var rr := ui.ask("latest rumors")
	check("they have rumors", String(rr["text"]).length() > 10, String(rr["text"]))
	var learned_poi := false
	for t in DialogueState.known_topics():
		var e: Dictionary = ix.entries.get(t.to_lower(), {})
		learned_poi = learned_poi or e.get("kind", "") == "poi"
	var other_town: PlacedPOI = null
	for t in wm.towns:
		if t != town:
			other_town = t
	DialogueState.learn(other_town.town.buildings[0].owner_name)
	check("people in another town are not their business", not DialogueEngine.can_discuss(s, other_town.town.buildings[0].owner_name, wm) or other_town.town.buildings[0].owner_name == s.name)
	DialogueState.learn(other_town.town.display_name)
	var ro := ui.ask(other_town.town.display_name)
	check("but they can point you to another town", String(ro["text"]).contains("to the "), String(ro["text"]))
	var rf := ui.ask("Fighters Guild")
	check("everyone knows a little about the guilds", String(rf["text"]).contains("Fighters Guild"))
	print("   sample: ", rr["text"])

	# disposition gates gossip
	var base := s.base_disposition
	DialogueState.change_disposition(s.id, base, -200)
	var cold := ui.ask("latest rumors")
	check("someone who dislikes you won't gossip", not bool(cold["journal"]) and DialogueEngine.get_disposition(s) == 0)
	DialogueState.change_disposition(s.id, base, 200)

	# persuasion
	DialogueState.change_disposition(s.id, base, -200)
	DialogueState.change_disposition(s.id, base, 40)
	var before_disp := DialogueEngine.get_disposition(s)
	var xp_before := skills.get_xp(&"speech") + skills.get_level(&"speech") * 1000.0
	check("no gold, no bribe", Persuasion.blocked(Persuasion.Kind.BRIBE_100, player) != "")
	Currency.add_gold(inv, 5000)
	var tries := 0
	var res := {}
	while tries < 40:
		tries += 1
		var gold_before := Currency.get_gold(inv)
		res = ui.persuade(Persuasion.Kind.BRIBE_1000)
		if res["success"]:
			check("a bribe that works takes the gold", Currency.get_gold(inv) == gold_before - 1000)
			break
		check("a bribe that fails keeps your gold", Currency.get_gold(inv) == gold_before)
	check("a big bribe works sooner or later", bool(res.get("success", false)), "%d tries" % tries)
	check("persuading trains Speech", skills.get_xp(&"speech") + skills.get_level(&"speech") * 1000.0 > xp_before)
	var admire_ok := 0
	for i in 30:
		admire_ok += 1 if ui.persuade(Persuasion.Kind.ADMIRE)["success"] else 0
	check("admiring sometimes works", admire_ok > 0)
	check("disposition changed and is shown", DialogueEngine.get_disposition(s) != before_disp and ui._disp_bar.value == DialogueEngine.get_disposition(s))
	check("persuasion buttons show the chance", ui._persuade_buttons[0].text.contains("%"))

	# the journal, opened from the dialogue
	ui._log.meta_clicked.emit(town.town.display_name.uri_encode())
	check("clicking a highlighted word asks about it", DialogueState.journal().size() >= 3)
	# names with an apostrophe must not break the links (what the screen shows is the plain text)
	var probe := RichTextLabel.new()
	probe.bbcode_enabled = true
	root.add_child(probe)
	var apostrophe := "I live at %s, next to %s." % [s.home.display_name, town.town.display_name]
	probe.text = DialogueUI.linkify(apostrophe, ix)
	check("links survive names like \"%s\"" % s.home.display_name, probe.get_parsed_text() == apostrophe, probe.get_parsed_text())
	probe.queue_free()
	journal.open()
	check("the journal opens over the dialogue", journal.is_open() and ui.is_open())
	journal.set_search(town.town.display_name)
	check("searching the journal", journal._count.text.begins_with(str(JournalUI.filter(DialogueState.journal(), town.town.display_name).size())))
	journal.close()
	check("closing the journal goes back to the dialogue, still paused", ui.is_open() and paused)
	ui.close()
	check("Goodbye closes the window and unpauses", not ui.is_open() and not paused)

	# J opens the journal during play
	await frames(2)
	_press(KEY_J)
	await frames(3)
	check("J opens the journal", journal.is_open() and paused)
	_press(KEY_ESCAPE)
	await frames(3)
	check("Esc closes it", not journal.is_open() and not paused)

	# the example quest topic at the inn
	if keeper != null:
		check("the innkeeper is at work (indoors)", keeper.inside != "")
		var inn := wm.get_building(keeper.data.work_id)
		await wm.dungeons.enter(inn.id, inn.get_door_position(), 0.0)
		await frames(10)
		var kbody := keeper.node
		check("you can talk to the innkeeper inside", kbody != null and is_instance_valid(kbody) and ui.open_with(kbody))
		check("greeting them teaches you their special topic", DialogueState.knows("a rare vintage") and DialogueEngine.topics_for(ui.speaker, wm).has("a rare vintage"))
		var q1 := ui.ask("a rare vintage")
		check("the first answer", String(q1["text"]).contains("Sunfire Red") and DialogueState.has_flag("vintage_asked"))
		var q2 := ui.ask("a rare vintage")
		check("asking again gives the follow-up (the flag)", String(q2["text"]).begins_with("Still no Sunfire Red"))
		var quest_entries := JournalUI.filter(DialogueState.journal(), "", "quest", "example_vintage")
		check("both lines are filed under the quest in the journal", quest_entries.size() == 2 and quest_entries[0]["quest_name"] == "(Example) A Rare Vintage")
		ui.close()
		await wm.dungeons.exit()
		await frames(5)

	# guards, sleepers and people who won't talk
	if guard != null:
		var opened := ui.open_with(guard.node)
		check("you can talk to a guard", opened and ui.speaker.role == NpcData.Role.GUARD)
		check("a guard explains the law", opened and DialogueEngine.topics_for(ui.speaker, wm).has("the law") and String(ui.ask("the law")["text"]).contains("answer to us"))
		ui.close()
	else:
		check("there is a guard to talk to", false)
	var angry := Enemy.new()
	angry.disposition = Enemy.Disposition.HOSTILE
	angry.position = player.global_position + Vector3(3, 0, 0)
	holder.add_child(angry)
	check("hostile ones won't talk", not ui.open_with(angry))
	angry.queue_free()
	wm.clock.set_time(2.0)
	await secs(1.0)
	var home := wm.get_building(talker.data.home_id)
	Locks.set_locked(home.id, false)
	await wm.dungeons.enter(home.id, home.get_door_position(), 0.0)
	await frames(10)
	var sleeper := talker.node
	if sleeper != null and is_instance_valid(sleeper) and sleeper.get_meta("asleep", false):
		var d0 := DialogueState.get_disposition(talker.data.id, talker.data.base_disposition)
		check("you can wake someone to talk", ui.open_with(sleeper) and ui.speaker.asleep)
		check("they don't like being woken", DialogueEngine.get_disposition(ui.speaker) == maxi(d0 - 3, 0))
		check("and won't gossip half asleep", not bool(ui.ask("latest rumors")["journal"]))
		ui.close()
	else:
		check("the owner is asleep at home to test with", false)
	await wm.dungeons.exit()
	holder.queue_free()
	await frames(2)
