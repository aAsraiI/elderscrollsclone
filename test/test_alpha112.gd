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
	_dialogue_roles()
	await _main_story()
	_journal_cleanup()
	await _notes()
	await _custom_npc()
	await _across_a_load()


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
