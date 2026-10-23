extends SceneTree
## The real main scene at night: walk into a house whose owner is asleep, save, load, and check
## the owner is still asleep in bed, the doors are locked as they were, and a picked lock is still
## open. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage3_scene.gd

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
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var clock := get_first_node_in_group("world_clock") as WorldClock
	var player := get_first_node_in_group("player") as Node3D
	check("the main scene has town life", wm.life != null and wm.life.residents.size() > 0)
	clock.set_time(1.0)
	await frames(60)
	var town := wm.get_town_at(player.global_position, 10.0)
	var owner: TownLife.Resident = null
	var other: BuildingPlot = null
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.COMMONER and owner == null:
			owner = r
	for b in town.town.buildings:
		if owner != null and b.id != owner.data.home_id and not b.is_public() and other == null:
			other = b
	check("at 1:00 a townsperson is home asleep", owner != null and owner.inside == owner.data.home_id)
	check("their door is locked", Locks.is_locked(owner.data.home_id, false))
	var home := wm.get_building(owner.data.home_id)
	Locks.set_locked(home.id, false)  # as if picked
	player.global_position = home.get_door_position() + Vector3.UP
	wm.dungeons.enter(home.id, home.get_door_position(), 0.0)
	await frames(60)
	check("inside, the owner is in bed", owner.node != null and is_instance_valid(owner.node) and owner.node.get_meta("asleep", false))
	check("saving works", sm.save_game("slot_test3"), sm.get_last_error())
	await wm.dungeons.exit()
	clock.set_time(13.0)
	await frames(60)
	check("load_game starts", sm.load_game("slot_test3"), sm.get_last_error())
	await frames(120)
	wm = get_first_node_in_group("world_manager") as WorldManager
	sm = get_first_node_in_group("save_manager") as SaveManager
	clock = get_first_node_in_group("world_clock") as WorldClock
	check("the time came back", absf(clock.hour - 1.0) < 0.2, str(clock.hour))
	check("you are back inside the house", wm.dungeons.is_in_building() and wm.dungeons.current_entrance_id == home.id)
	var again := wm.life.get_resident(owner.data.id)
	check("the owner is still asleep in bed", again != null and again.node != null and is_instance_valid(again.node) and again.node.get_meta("asleep", false))
	check("the lock you picked is still open", not Locks.is_locked(home.id, true))
	check("the neighbor's door is still locked", other == null or Locks.is_locked(other.id, false))
	sm.delete_slot("slot_test3")
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
