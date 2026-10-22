extends SceneTree
## The real main scene: talk to someone in the starting town, persuade them, save, load, and
## check the journal, the known topics and their disposition all came back. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage4_scene.gd

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
	change_scene_to_file("res://test_level.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var player := get_first_node_in_group("player") as Node3D
	(get_first_node_in_group("world_clock") as WorldClock).set_time(12.0)
	await frames(60)
	var ui := player.get_node_or_null("DialogueUI") as DialogueUI
	var journal := player.get_node_or_null("JournalUI") as JournalUI
	check("the player has a dialogue window and a journal", ui != null and journal != null)
	var town := wm.get_town_at(player.global_position, 10.0)
	var who: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.node != null and is_instance_valid(r.node) and not r.node_inside and r.data.role != NpcData.Role.GUARD:
			who = r
			break
	check("someone is out in town", who != null)
	(who.node.get_node("NpcTalk") as NpcTalk).interact(player.get_node("Inventory") as Inventory)
	check("talking opens the window", ui.is_open())
	DialogueState.change_disposition(who.data.id, who.data.base_disposition, 40)  # someone who dislikes you keeps rumors to themselves
	ui.ask("background")
	ui.ask("latest rumors")
	var entries := DialogueState.journal().size()
	var known := DialogueState.known_topics().size()
	DialogueState.change_disposition(who.data.id, who.data.base_disposition, 9)
	var disp := DialogueState.get_disposition(who.data.id, who.data.base_disposition)
	ui.close()
	check("the journal has entries and topics were learned", entries >= 2 and known > DialogueState.START_TOPICS.size(), "%d entries, %d topics" % [entries, known])
	check("saving works", sm.save_game("slot_test4"), sm.get_last_error())
	WorldState.clear()
	check("load_game starts", sm.load_game("slot_test4"), sm.get_last_error())
	await frames(120)
	check("the journal came back", DialogueState.journal().size() == entries)
	check("the known topics came back", DialogueState.known_topics().size() == known)
	check("their liking for you came back", DialogueState.get_disposition(who.data.id, who.data.base_disposition) == disp)
	sm = get_first_node_in_group("save_manager") as SaveManager
	sm.delete_slot("slot_test4")
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
