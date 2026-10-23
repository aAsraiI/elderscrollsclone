extends SceneTree
## Loads the real main scene and checks the pause menu can save and load. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage1_scene.gd

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
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	var sm := get_first_node_in_group("save_manager") as SaveManager
	check("main scene has a SaveManager (auto-created)", sm != null)
	var player := get_first_node_in_group("player")
	var pm := player.get_node_or_null("PauseMenu") as PauseMenu
	var clock := get_first_node_in_group("world_clock") as WorldClock
	check("pause menu and clock exist", pm != null and clock != null)
	pm.open()
	check("Save / Load buttons are enabled", not pm._save.disabled and not pm._load.disabled)
	pm.close()
	var inv := player.get_node("Inventory") as Inventory
	var fx := player.get_node("StatusEffects") as StatusEffects
	var bread: ItemData = load("res://data/consumables/bread.tres")
	fx.use_item(bread)
	clock.set_time(19.25, 3)
	Currency.add_gold(inv, 42)
	var gold_before := Currency.get_gold(inv)
	check("save_game works from the main scene", sm.save_game("slot_test"), sm.get_last_error())
	Currency.spend_gold(inv, 10)
	clock.set_time(2.0, 9)
	check("load_game starts", sm.load_game("slot_test"), sm.get_last_error())
	await frames(90)
	player = get_first_node_in_group("player")
	inv = player.get_node("Inventory") as Inventory
	fx = player.get_node("StatusEffects") as StatusEffects
	clock = get_first_node_in_group("world_clock") as WorldClock
	check("gold came back", Currency.get_gold(inv) == gold_before, "%d vs %d" % [Currency.get_gold(inv), gold_before])
	check("time came back", clock.day == 3 and absf(clock.hour - 19.25) < 0.1, "%d %f" % [clock.day, clock.hour])
	check("bread effect came back", fx.has_effect_from(bread))
	sm = get_first_node_in_group("save_manager") as SaveManager
	sm.delete_slot("slot_test")
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
