extends SceneTree
## Headless tests for rebuild phase 2: GameState wipes everything a game leaves behind, and
## ActorRegistry answers "who is near?" the same way scanning the "enemies" group did.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_phase2.gd

var passes := 0
var fails := 0
var world: Node3D


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
	await frames(2)
	t_new_game_is_clean()
	t_load_is_clean()
	await t_registry()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# Everything one game can leave in static variables, set to something a fresh game wouldn't have
func _dirty() -> Dictionary:
	WorldState.set_record("bounty/kingsreach", {"gold": 500})
	DialogueState.change_disposition("temp:road_merchant", 40, 30)
	var key := KeyRing.get_key("r0/town/b1", "Old Name")
	var quest_item := QuestItems.get_item("Q-LEDGER", "Old Ledger")
	GameRules.set_rule("survival", true)
	CharacterSetup.pending = {"name": "Old Hero"}
	Engine.time_scale = 0.05
	return {"key": key, "quest_item": quest_item}


func t_new_game_is_clean() -> void:
	print("-- a new game after playing another")
	var old := _dirty()
	SaveSession.current_slot = "slot_1"
	SaveSession.playtime = 3600.0
	SaveSession.begin_new_game(0, true)
	check("world records are gone (no old bounty)", not WorldState.has_record("bounty/kingsreach"))
	check("strangers' disposition is back to normal", DialogueState.get_disposition("temp:road_merchant", 40) == 40)
	check("keys are made fresh", KeyRing.get_key("r0/town/b1", "New Name") != old["key"])
	check("quest items are made fresh", QuestItems.get_item("Q-LEDGER", "New Ledger").display_name == "New Ledger")
	check("rules are back to the defaults", GameRules.get_rule("survival") == GameRules.DEFAULTS["survival"])
	check("no leftover character", CharacterSetup.pending.is_empty())
	check("time runs at normal speed", is_equal_approx(Engine.time_scale, 1.0))
	check("not saving over the old slot", SaveSession.current_slot == "")
	check("playtime starts at zero", SaveSession.playtime == 0.0)


func t_load_is_clean() -> void:
	print("-- loading a save after playing another game")
	_dirty()
	var save := {"version": 2, "playtime": 120.0, "world": {"seed": 77},
		"world_state": {"flag/met_the_lord": {"on": true}}, "rules": {"survival": false},
		"player": {"pos": [1, 2, 3], "character": {"name": "Saved Hero"}}}
	SaveSession.begin_load(save, "slot_2")
	check("only the save's world records are there", WorldState.has_record("flag/met_the_lord") and not WorldState.has_record("bounty/kingsreach"))
	check("strangers' disposition is back to normal", DialogueState.get_disposition("temp:road_merchant", 40) == 40)
	check("quest items are made fresh", QuestItems.get_item("Q-LEDGER", "Saved Ledger").display_name == "Saved Ledger")
	check("the save's rules are used", GameRules.get_rule("survival") == false)
	check("the save's character is used", String(CharacterSetup.pending.get("name", "")) == "Saved Hero")
	check("time runs at normal speed", is_equal_approx(Engine.time_scale, 1.0))
	check("the save's slot and playtime", SaveSession.current_slot == "slot_2" and SaveSession.playtime == 120.0)
	SaveSession.take_pending()
	SaveSession.begin_new_game(0, true)


# The old way: every living actor in the "enemies" group within the radius
func _scan(pos: Vector3, radius: float) -> Array:
	var out := []
	for n in get_nodes_in_group("enemies"):
		if (n as Node3D).global_position.distance_to(pos) <= radius:
			out.append(n)
	return out


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(x):
			return false
	return true


func t_registry() -> void:
	print("-- ActorRegistry")
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	var start := ActorRegistry.count()
	var spots := [Vector3(0, 0.1, 0), Vector3(10, 0.1, 5), Vector3(-25, 0.1, 30), Vector3(70, 0.1, -70),
		Vector3(31, 0.1, 31), Vector3(33, 0.1, -1), Vector3(-90, 0.1, 0), Vector3(5, 0.1, 140)]
	var made: Array[Enemy] = []
	for p in spots:
		var e := Enemy.spawn(world, p)
		e.set_physics_process(false)  # stand still so the positions are known
		made.append(e)
	await frames(2)
	check("every spawned actor is registered", ActorRegistry.count() == start + spots.size(), "%d" % ActorRegistry.count())
	var agree := true
	for center in [Vector3.ZERO, Vector3(30, 0, 30), Vector3(-60, 0, 10), Vector3(5, 0, 100)]:
		for radius in [5.0, 12.0, 32.0, 50.0, 120.0]:
			if not _same(ActorRegistry.near(center, radius), _scan(center, radius)):
				agree = false
				print("   differs at ", center, " r=", radius)
	check("near() finds exactly who a full scan finds", agree)
	# Dying, leaving the scene and being freed all take an actor off the list
	made[0].stats.modify_vital("health", -99999.0)
	await frames(1)
	check("the dead are not listed", not ActorRegistry.all().has(made[0]) and not ActorRegistry.near(Vector3.ZERO, 3.0).has(made[0]))
	world.remove_child(made[1])
	check("an actor taken out of the scene is not listed", not ActorRegistry.all().has(made[1]))
	world.add_child(made[1])
	check("...and is listed again when it comes back", ActorRegistry.all().has(made[1]))
	made[2].free()
	check("a freed actor is not listed", ActorRegistry.count() == start + spots.size() - 2, "%d" % ActorRegistry.count())
	world.free()
	await frames(1)
	check("clearing the scene empties the registry", ActorRegistry.count() == start, "%d" % ActorRegistry.count())
