extends SceneTree
## The real main scene: Ctrl sneaks, the eye shows, and a bounty and stolen goods survive save and
## load (and show on the pause screen). Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage6a_scene.gd

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


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _run() -> void:
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var player := get_first_node_in_group("player") as Node3D
	var st := player.get_node_or_null("Stealth") as Stealth
	check("the player can sneak", st != null and wm.crime != null)
	_press(KEY_CTRL)
	await frames(30)
	check("Ctrl starts sneaking", st.sneaking)
	check("the view drops lower", (player.get_node("Head") as Node3D).position.y < 1.4)
	check("the eye shows", st._eye.visible)
	_press(KEY_CTRL)
	await frames(30)
	check("Ctrl again stands up", not st.sneaking and (player.get_node("Head") as Node3D).position.y > 1.5)

	var town := wm.get_town_at(player.global_position, 10.0)
	wm.crime.set_bounty(town.id, 35)
	var inv := player.get_node("Inventory") as Inventory
	var ruby := load("res://data/treasure/ruby.tres") as ItemData
	inv.add_item(ruby, 1)
	CrimeManager.add_stolen(ruby, 1)
	var pm := player.get_node("PauseMenu") as PauseMenu
	pm.open()
	check("the pause screen lists the bounty", pm._info.text.contains("Bounty: %s 35" % town.town.display_name), pm._info.text)
	pm.close()
	wm.crime.process_mode = Node.PROCESS_MODE_DISABLED  # no arrest while saving
	check("saving works", sm.save_game("slot_test6a"), sm.get_last_error())
	CrimeManager.set_bounty_raw(town.id, 0)
	check("load_game starts", sm.load_game("slot_test6a"), sm.get_last_error())
	await frames(120)
	player = get_first_node_in_group("player") as Node3D
	inv = player.get_node("Inventory") as Inventory
	check("the bounty came back", CrimeManager.get_bounty(town.id) == 35)
	check("the stolen mark came back", CrimeManager.stolen_count(inv, ruby) == 1)
	sm = get_first_node_in_group("save_manager") as SaveManager
	sm.delete_slot("slot_test6a")
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
