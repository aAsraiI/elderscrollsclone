extends SceneTree
## Headless tests for the debug console's travel and movement commands (Alpha 1.20.1): tp nearest, near,
## exit, speed, fly, noclip, pos, reveal, bounty, timescale.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_debug_console.gd

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


func _run() -> void:
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var con := p.find_children("*", "DebugConsole", true, false)
	var c: DebugConsole = con[0] if not con.is_empty() else null
	check("the console is on the player", c != null)
	if c == null:
		_end()
		return
	wm.dungeons.fade_time = 0.0

	print("-- finding places")
	var near := c.run("near dungeon")
	check("near lists the closest dungeons", near.split("\n").size() >= 3 and near.contains(" m "), near)
	check("near guild lists guild halls", c.run("near guild").contains(" m "))
	check("an unknown kind says so", c.run("near xyzzy").begins_with("Nothing"))

	print("-- tp nearest")
	var msg := c.run("tp nearest dungeon")
	await frames(30)
	check("tp nearest dungeon goes inside one (%s)" % msg, wm.dungeons.is_inside() and wm.dungeons.get_interior_root().find_children("*", "RoomModule", true, false).size() >= 2)
	check("pos says where you are", c.run("pos").contains("Inside"))
	msg = c.run("tpn inn")
	await frames(40)
	check("tpn inn leaves the dungeon and goes into an inn (%s)" % msg, wm.dungeons.is_inside() and wm.get_building(wm.dungeons.current_entrance_id) != null and wm.get_building(wm.dungeons.current_entrance_id).kind == BuildingPlot.Kind.INN)
	c.run("exit")
	await frames(30)
	check("exit leaves it", not wm.dungeons.is_inside())
	msg = c.run("teleport nearest house out")
	await frames(20)
	check("...out stops at the door (%s)" % msg, not wm.dungeons.is_inside() and msg.begins_with("Going to"))
	msg = c.run("tpn")
	await frames(30)
	check("tpn alone goes into the nearest dungeon or building (%s)" % msg, wm.dungeons.is_inside())
	c.run("exit")
	await frames(30)

	print("-- movement")
	check("speed 3", c.run("speed 3").contains("x3") and is_equal_approx(float(p.get("debug_speed")), 3.0))
	c.run("speed")
	check("speed alone puts it back", is_equal_approx(float(p.get("debug_speed")), 1.0))
	check("fly allows flight", c.run("fly").contains("on") and bool(p.get("can_fly")))
	p.call("set_flying", true)
	var y0 := p.global_position.y + 6.0
	p.global_position.y = y0
	await frames(60)
	check("flying, you don't fall", absf(p.global_position.y - y0) < 0.5, "%.2f" % (p.global_position.y - y0))
	c.run("fly")
	await frames(60)
	check("flight off: you fall again", p.global_position.y < y0 - 1.0 and not bool(p.get("flying")))
	c.run("noclip")
	check("noclip flies", bool(p.get("noclip")) and bool(p.get("flying")))
	c.run("noclip")
	c.run("fly")
	check("noclip and flight off again", not bool(p.get("noclip")) and not bool(p.get("can_fly")))

	print("-- the rest")
	check("reveal finds places", c.run("reveal").contains("places found"))
	CrimeManager.set_bounty_raw("test_town", 50)
	check("bounty lists bounties", c.run("bounty").contains("50 gold"))
	c.run("bounty clear")
	check("bounty clear wipes them", CrimeManager.bounties().is_empty())
	c.run("timescale 2")
	check("timescale", is_equal_approx(Engine.time_scale, 2.0))
	c.run("timescale")
	check("timescale back to 1", is_equal_approx(Engine.time_scale, 1.0))
	check("help lists the new commands", c.run("help").contains("tp nearest") and c.run("help").contains("noclip"))
	_end()


func _end() -> void:
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
