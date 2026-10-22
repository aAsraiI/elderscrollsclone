extends SceneTree
## The real main scene: join guilds, take a delivery job, save, load, and check membership, rank
## perks, the job and its package all came back. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage6b_scene.gd

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
	var stats := player.get_node("Stats") as Stats
	var health_before := stats.get_stat("max_health")
	check("the main scene has a QuestManager", wm.quests != null)
	Factions.join("fighters", player)
	Factions.join("mages", player)
	check("joining the Fighters Guild adds its perk", is_equal_approx(stats.get_stat("max_health"), health_before + 5.0))
	var leader: DialogueEngine.Speaker = null
	for t in wm.towns:
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			if r.data.role == NpcData.Role.GUILD_MEMBER and r.data.faction == "mages" and leader == null:
				leader = DialogueEngine.Speaker.new()
				leader.data = r.data
				leader.id = r.data.id
				leader.name = r.data.display_name
				leader.role = r.data.role
				leader.town = r.town
				leader.home = wm.get_building(r.data.home_id)
	var q := wm.quests.offer("mages", leader, "deliver")
	var inv := player.get_node("Inventory") as Inventory
	var package := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
	check("a delivery job with its package", not q.is_empty() and inv.has_item(package))
	wm.crime.process_mode = Node.PROCESS_MODE_DISABLED
	check("saving works", sm.save_game("slot_test6b"), sm.get_last_error())
	WorldState.clear()
	check("load_game starts", sm.load_game("slot_test6b"), sm.get_last_error())
	await frames(120)
	player = get_first_node_in_group("player") as Node3D
	inv = player.get_node("Inventory") as Inventory
	stats = player.get_node("Stats") as Stats
	check("guild memberships came back", Factions.is_member("fighters") and Factions.is_member("mages"))
	check("so did the rank perk", is_equal_approx(stats.get_stat("max_health"), health_before + 5.0), str(stats.get_stat("max_health")))
	check("the job is still active", QuestManager.active_for("mages").get("id") == q["id"])
	check("and the package is still in your pack", inv.has_item(QuestItems.get_item(String(q["id"]), String(q["item_name"]))))
	sm = get_first_node_in_group("save_manager") as SaveManager
	sm.delete_slot("slot_test6b")
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
