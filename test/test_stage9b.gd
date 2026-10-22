extends SceneTree
## Headless tests for stage 9b (the 16 x 16 km realm, level bands, discovery, fast travel).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage9b.gd

const W := "res://scripts/Resources/World/"

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
	t_settings()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_settings() -> void:
	print("-- the realm")
	var s := load(W + "realm_world.tres") as WorldSettings
	check("realm_world loads with 13 biome regions", s != null and s.get_valid_placements().size() == 13)
	var map := WorldMap.new(s, 1)
	var b := map.get_bounds()
	check("the realm is at least 16 x 16 km", b.size.x >= 16000.0 and b.size.y >= 16000.0, str(b.size))
	var names := {}
	for p in s.placements:
		names[p.biome.display_name] = p.get_level_range()
	for n in ["Coast", "Badlands", "Deadlands", "Tundra", "Ashlands", "Frozen Crown"]:
		check("new biome: %s" % n, names.has(n))
	check("the Frozen Crown goes up to level 100", names.get("Frozen Crown", Vector2i.ZERO) == Vector2i(80, 100))
	check("placements can override a biome's levels", names.get("Plains", Vector2i.ZERO) == Vector2i(1, 13))
	var start := map.get_placement_rect(s.spawn_placement).get_center()
	var peak := map.get_placement_rect(1).get_center()
	var low := map.get_level_band(start.x, start.y)
	var high := map.get_level_band(peak.x, peak.y)
	check("the south start is low level, the north is high", low.y <= 14.0 and high.x >= 75.0, "%s %s" % [low, high])
	# crossing a border, the band changes gradually
	var a := map.get_placement_rect(11).get_center()  # plains
	var c := map.get_placement_rect(9).get_center()   # swamp
	var steps := 40
	var biggest := 0.0
	var prev := map.get_level_band(a.x, a.y)
	for i in range(1, steps + 1):
		var q := a.lerp(c, float(i) / steps)
		var band := map.get_level_band(q.x, q.y)
		biggest = maxf(biggest, absf(band.x - prev.x))
		prev = band
	check("levels blend across a border instead of jumping", biggest < 6.0, str(biggest))


func t_world() -> void:
	print("-- in the game")
	change_scene_to_file("res://test_level.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	check("the game builds the realm", wm != null and wm.settings.resource_path.ends_with("realm_world.tres") and player != null)
	if wm == null or player == null:
		return
	check("the realm has dozens of towns", wm.towns.size() >= 25, str(wm.towns.size()))
	var here := LevelCurve.zone_range(wm.map, player.global_position)
	check("you start somewhere easy", here.y <= 10, str(here))
	var disc := wm.discovery
	check("WorldManager made Discovery", disc != null)
	var near := wm.get_town_at(player.global_position, 80.0)
	await frames(40)
	check("the town you start in is found", near == null or Discovery.is_found(near.id))
	# a place deep in the wild of the start biome is harder than one next to a town
	var town := wm.towns[0]
	var t_lvl := LevelCurve.place_level(wm.map, town.position)
	var far_lvl := t_lvl
	for poi in wm.pois:
		if poi.region == town.region and poi.town == null and wm.map.get_town_distance(poi.position.x, poi.position.z) > 1200.0:
			far_lvl = LevelCurve.place_level(wm.map, poi.position)
			break
	check("places far from towns are harder", far_lvl >= t_lvl, "%d vs %d" % [far_lvl, t_lvl])
	# finding and travelling
	var target: PlacedPOI = null
	for poi in wm.pois:
		if poi.town == null and not Discovery.is_found(poi.id) and poi.position.distance_to(player.global_position) > 1500.0 and wm.map.get_town_distance(poi.position.x, poi.position.z) > 700.0:
			target = poi
			break
	check("there is an unfound place to test with", target != null)
	if target == null:
		return
	check("you can't travel to a place you have not found", disc.can_travel_to(target) != "")
	var dmap := get_first_node_in_group("world_map") as WorldDebugMap
	dmap.open()
	dmap._view.size = Vector2(1200, 700)
	dmap._center = Vector2(target.position.x, target.position.z)
	dmap._zoom = 8.0
	var spot := dmap.world_to_screen(Vector2(target.position.x, target.position.z))
	check("unfound places are not on the map", dmap.hover_name(spot) == "" or dmap.place_at(spot) != target)
	dmap.close()
	var sk := player.get_node("Skills") as Skills
	var deeds := sk.deed_xp
	check("finding a place counts", disc.mark_found(target) and Discovery.is_found(target.id) and sk.deed_xp > deeds)
	check("finding it twice does nothing", not disc.mark_found(target))
	dmap.open()
	dmap._view.size = Vector2(1200, 700)
	dmap._center = Vector2(target.position.x, target.position.z)
	spot = dmap.world_to_screen(Vector2(target.position.x, target.position.z))
	check("found places show their level on the map", dmap.hover_name(spot).contains("level"), dmap.hover_name(spot))
	for e in get_nodes_in_group("enemies"):
		if (e as Enemy).disposition == Enemy.Disposition.HOSTILE and (e as Node3D).global_position.distance_to(player.global_position) < 60.0:
			e.queue_free()  # the test enemy the player spawns next to itself
	await frames(2)
	dmap._view.size = Vector2(1200, 700)
	dmap._center = Vector2(target.position.x, target.position.z)
	spot = dmap.world_to_screen(Vector2(target.position.x, target.position.z))
	var clock := wm.clock
	var hour_before := clock.day * 24.0 + clock.hour
	dmap.click_place(spot)
	check("the first click only asks", dmap.is_open() and dmap._pending_travel == target.id, dmap._notice)
	dmap.click_place(spot)
	await frames(5)
	check("the second click travels there and closes the map", not dmap.is_open() and player.global_position.distance_to(target.position) < target.poi.footprint_radius + 40.0, str(player.global_position.distance_to(target.position)))
	check("time passed on the way", clock.day * 24.0 + clock.hour > hour_before + 0.05)
	Discovery.mark_cleared(target.id)
	check("a place can be marked cleared", Discovery.is_cleared(target.id) and Discovery.is_found(target.id))
	var saved := WorldState.to_dict()
	WorldState.clear()
	WorldState.from_dict(saved)
	check("found places are saved", Discovery.is_found(target.id))
