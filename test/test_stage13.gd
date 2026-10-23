extends SceneTree
## Headless tests for stage 13, finishing the lore bible: the clans' territory war (feeding
## grounds, monthly raids, the Night map), the Regency Council and its board, the epilogue, the
## festival calendar, and the hand-built Castle Dawnhold.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage13.gd

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


func secs(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await frames(2)
	t_territory()
	t_regency()
	t_epilogue()
	t_festival_dates()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_territory() -> void:
	print("-- the territory war")
	WorldState.clear()
	check("the Velvet Court starts out ruling the Swamp", ClanTerritory.ruler("swamp") == "velvet_court")
	ClanTerritory.lose("swamp", "velvet_court", 20)
	var s := ClanTerritory.scores("swamp")
	check("a lost raid costs the clan 20 control there", int(s["velvet_court"]) == 50 and int(s["hollow_kin"]) == 25, str(s))
	var grounds := 0
	var owners := {}
	for i in 400:
		var o := ClanTerritory.ground_owner("poi_%d" % i, "plains")
		if o != "":
			grounds += 1
			owners[o] = true
	check("about one place in four is a feeding ground", grounds > 60 and grounds < 140, str(grounds))
	check("feeding grounds belong to more than one clan", owners.size() >= 2, str(owners.keys()))
	check("lands outside the war have none", ClanTerritory.ground_owner("poi_0", "nowhere") == "")
	check("the Night map's colours cover every clan", ClanTerritory.COLORS.size() == 3)
	WorldState.clear()


func t_regency() -> void:
	print("-- the Regency Council")
	WorldState.clear()
	var inf := Regency.influence()
	check("eight houses sit on the council", inf.size() == 8)
	check("Valcourt leads at first", Regency._leader(inf, []) == "valcourt", str(inf))
	QuestBook.set_flag("S-KR07:morvaine")
	check("accusing Morvaine costs it influence", int(Regency.influence()["morvaine"]) == int(Regency.HOUSES["morvaine"]) - 8)
	QuestBook.set_flag("S-SH07:broken")
	check("breaking the Accord takes Sahrim off the council", not Regency.influence().has("sahrim") and Regency.left_council().has("sahrim"))
	check("while the King lives, the council waits", Regency.outcome(10).is_empty() and Regency.king_state(10) == "alive")
	QuestBook.set_flag("S-KR08:saved")
	WorldState.set_record(Regency.KING_SAVED, {"day": 10})
	check("a saved King lives another year", Regency.king_state(200) == "saved" and Regency.outcome(200).is_empty())
	var result := Regency.outcome(10 + Regency.KING_EXTRA_DAYS)
	check("when he dies, the strongest house wins", String(result.get("house", "")) == "valcourt", str(result))
	WorldState.set_record("qb/H-TW08", {"status": "done"})
	check("a house that finishes its last quest takes the council at once", String(Regency.outcome(20).get("house", "")) == "tidewell")
	QuestBook.set_flag("V-VC08:regency")
	check("the Velvet Court can take it from behind the throne", String(Regency.outcome(20).get("house", "")) == "velvet_court")
	WorldState.clear()


func t_epilogue() -> void:
	print("-- the epilogue")
	WorldState.clear()
	check("nothing finished, nothing told", Epilogue.lines().is_empty())
	WorldState.set_record("story", {"stage": 6})
	QuestBook.set_flag("S-KR08:peace")
	QuestBook.set_flag("W-GF08:alpha")
	var lines := Epilogue.lines()
	check("one line per finished questline", lines.size() == 3, str(lines))
	check("the main story comes first", lines.size() > 0 and lines[0].contains("Hierophant"))
	check("choices pick the line", "\n".join(lines).contains("died in peace") and "\n".join(lines).contains("new Alpha"))
	WorldState.clear()


func t_festival_dates() -> void:
	print("-- the festival calendar")
	var clock := WorldClock.new()
	clock.control_environment = false
	clock.day = 1  # 1 Seedfall
	check("no festival on the first of the month", Festivals.current(clock).is_empty())
	clock.day = Festivals.FIRST_DAY
	var f := Festivals.current(clock)
	check("the Feast of Seedfall in its month", String(f.get("name", "")) == "Feast of Seedfall", str(f))
	clock.day = Festivals.FIRST_DAY + Festivals.FESTIVAL_DAYS
	check("and it ends after its days", Festivals.current(clock).is_empty())
	check("twelve festivals, one a month", Festivals.LIST.size() == 12)
	clock.day = Festivals.FIRST_DAY + 4 * WorldClock.DAYS_PER_MONTH  # Day of the Dawn (Sunheight)
	check("no vampires on the Day of the Dawn", Festivals.encounter_factor(clock, "night_vampire") == 0.0 and Festivals.encounter_factor(clock, "plains_wolves") == 1.0,
		String(Festivals.current(clock).get("name", "")))
	clock.free()


func t_in_game() -> void:
	print("-- in the game")
	SaveSession.begin_new_game(0, true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	check("the council, the war and the festivals run in the world", wm.get_node_or_null("Regency") != null and wm.get_node_or_null("TerritoryWar") != null and wm.get_node_or_null("Festivals") != null)
	check("the Council page is in the Tab menu", player.get_node_or_null("CouncilUI") != null)
	# The festival: Kingsreach keeps the Feast of Seedfall
	var kr: PlacedPOI = null
	for t in wm.towns:
		if t.town != null and t.town.display_name == "Kingsreach":
			kr = t
	check("Kingsreach is in the realm", kr != null)
	if kr == null:
		return
	wm.clock.set_time(10.0, Festivals.FIRST_DAY)
	wm.ensure_area_loaded(kr.position, 2)
	player.global_position = kr.position + Vector3(0, 20, 0)
	player.velocity = Vector3.ZERO
	await secs(6.0)
	var node := wm.get_poi_node(kr.id)
	check("Kingsreach hangs its festival banners", node != null and node.get_node_or_null(Festivals.DECOR) != null)
	var stall := false
	for e in ActorRegistry.near(kr.position, 60.0):
		stall = stall or String(e.get_meta("merchant", "")) == "festival"
	check("a festival stall sells in the plaza", stall)
	wm.clock.set_time(10.0, Festivals.FIRST_DAY + Festivals.FESTIVAL_DAYS)
	await secs(5.0)
	check("the banners come down when it ends", node == null or not is_instance_valid(node) or node.get_node_or_null(Festivals.DECOR) == null)
	# Castle Dawnhold, by hand
	var seat: BuildingPlot = null
	for b in kr.town.buildings:
		if b.kind == BuildingPlot.Kind.SEAT:
			seat = b
	check("Kingsreach's seat is Castle Dawnhold", seat != null and seat.display_name == InteriorBuilder.DAWNHOLD)
	if seat == null:
		return
	var entered: bool = await wm.dungeons.enter(seat.id, seat.get_door_position(), 0.0)
	await secs(1.0)
	var inside := wm.dungeons._root
	check("entering it loads the hand-built castle", entered and inside != null and inside.get_node_or_null("GreatHall") != null and inside.get_node_or_null("CryptOfKings") != null)
	check("with its council chamber, solar and treasury", inside != null and inside.find_child("CouncilChamber", true, false) != null and inside.find_child("RoyalSolar", true, false) != null and inside.find_child("Treasury", true, false) != null)
	check("a way out, the Crown's chests and the lore shelf", inside != null and inside.get_node_or_null("Exit") is DungeonDoor and inside.find_children("*", "ContainerComponent", true, false).size() >= 3)
	check("the player stands in the great hall, on the floor", player.global_position.distance_to(inside.to_global(Vector3(1.2, 0.1, -12.6))) < 2.0 and absf(player.velocity.y) < 5.0, str(player.global_position))
	# The crypt stair is walkable: a ray down the stair finds it
	var q := PhysicsRayQueryParameters3D.create(inside.to_global(Vector3(-5.0, -2.0, 5.0)), inside.to_global(Vector3(-5.0, -9.0, 5.0)))
	var hit := inside.get_world_3d().direct_space_state.intersect_ray(q)
	check("the stair down to the Crypt of Kings is solid", not hit.is_empty())
	wm.dungeons.exit()
	await secs(1.0)
