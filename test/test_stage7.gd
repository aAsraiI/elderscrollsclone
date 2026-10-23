extends SceneTree
## Headless tests for the world update: the large default world (biomes, water, trees), roads that
## cut instead of fill, large towns with tradesmen, road traffic, the map and the compass. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage7.gd

const R := "res://data/"
const GRAND := "res://data/world/grand_world.tres"

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
	t_plan()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- the planned world

func t_plan() -> void:
	print("-- the large default world, planned")
	var s := load(GRAND) as WorldSettings
	var keys := {}
	for p in s.get_valid_placements():
		keys[p.biome.get_key()] = true
	check("seven kinds of land", keys.size() == 7, str(keys.keys()))
	check("including forest, lakeland, swamp and highlands", keys.has("forest") and keys.has("lakeland") and keys.has("swamp") and keys.has("highlands"))
	check("it has water", s.water_enabled)
	check("and its own large town templates", not s.town_templates.is_empty() and s.town_templates[0].footprint_radius >= 110.0)
	check("the tests' old world is untouched (no water, no traffic)", not (load(R + "world/multi_biome_world.tres") as WorldSettings).water_enabled and not (load(R + "world/multi_biome_world.tres") as WorldSettings).road_traffic)

	var t0 := Time.get_ticks_msec()
	var map := WorldMap.new(s, 1337)
	var towns := SettlementPlanner.plan(map)
	map.set_pads(towns)
	SettlementPlanner.lay_out(map, towns)
	var net := RoadPlanner.plan(map, towns)
	var plan_ms := Time.get_ticks_msec() - t0
	check("the world plans quickly enough to load (%d ms)" % plan_ms, plan_ms < 6000)
	var b := map.get_bounds()
	check("it is large: %.1f x %.1f km" % [b.size.x / 1000.0, b.size.y / 1000.0], b.size.x > 6500.0 and b.size.y > 5500.0)
	check("lots of towns (%d)" % towns.size(), towns.size() >= 25)

	# towns: big, dry, with tradesmen
	var dry := true
	var city_ok := true
	var village_ok := true
	var trades := {}
	var fisher_ok := true
	var spot_ok := true
	for t in towns:
		if map.is_under_water(t.position.y - 1.0):
			dry = false
		var data := t.poi as TownData
		if data.kind == TownData.Kind.CITY and t.town.buildings.size() < 45:
			city_ok = false
		if data.kind == TownData.Kind.VILLAGE and t.town.buildings.size() < 12:
			village_ok = false
		for bp in t.town.buildings:
			if bp.kind == BuildingPlot.Kind.HOUSE and bp.trade != "":
				trades[bp.trade] = int(trades.get(bp.trade, 0)) + 1
				if bp.trade == "fisherman" and t.town.shore == Vector3.INF:
					fisher_ok = false
				if NpcData.role_for_plot(bp) == NpcData.Role.COMMONER:
					spot_ok = false
				if bp.trade == "fisherman" and t.town.get_trade_spot(bp) != t.town.shore:
					spot_ok = false
	check("no town is built in the water", dry)
	check("cities are big (45+ buildings)", city_ok)
	check("villages are big (12+ buildings)", village_ok)
	check("tradesmen live in some houses: %s" % str(trades), trades.size() >= 4)
	check("fishermen only where there is water", fisher_ok and trades.has("fisherman"))
	check("tradesmen get their own job and work spot", spot_ok)

	# roads: every town joined, out of the water, cutting into hills instead of standing on banks
	var parent := {}
	for t in towns:
		parent[t.id] = t.id
	var find := func(x: String) -> String:
		while parent[x] != x:
			x = parent[x]
		return x
	for r in net.get_roads():
		parent[find.call(r["from"])] = find.call(r["to"])
	var groups := {}
	for t in towns:
		groups[find.call(t.id)] = true
	check("roads join every town (%d roads)" % net.get_roads().size(), groups.size() == 1, "%d groups" % groups.size())
	var wet := 0
	var worst_fill := 0.0
	for r in net.get_roads():
		for p: Vector3 in r["points"]:
			var land := map.get_height(p.x, p.z)  # roads not applied to this map yet: the natural land
			if map.is_under_water(land + 0.2):
				wet += 1
			var near := false
			for t in towns:
				var ramp := maxf(110.0, absf(t.position.y - land) / maxf(s.road_max_grade, 0.01) + 30.0)  # the road climbs up to a raised town pad
				if Vector2(p.x - t.position.x, p.z - t.position.z).length() < t.poi.footprint_radius + ramp:
					near = true
					break
			if not near:
				worst_fill = maxf(worst_fill, p.y - land)
	check("roads stay out of the water", wet == 0, "%d points" % wet)
	check("away from towns a road never stands above the land (%.2f m)" % worst_fill, worst_fill <= RoadPlanner.MAX_FILL + 0.05)
	map.set_roads(net)
	var grade := 0.0
	for r in net.get_roads():
		var pts: PackedVector3Array = r["points"]
		var prev := Vector3.INF
		for i in pts.size() - 1:
			var steps := maxi(int(pts[i].distance_to(pts[i + 1]) / 3.0), 1)
			for k in steps:
				var q := pts[i].lerp(pts[i + 1], float(k) / float(steps))
				q.y = map.get_height(q.x, q.z)
				if prev != Vector3.INF:
					var run := Vector2(q.x - prev.x, q.z - prev.z).length()
					if run > 1.0:
						grade = maxf(grade, absf(q.y - prev.y) / run)
				prev = q
	check("roads hold their grade (%.2f)" % grade, grade <= s.road_max_grade + 0.06)

	# trees
	var forest_trees := 0
	var desert_trees := 0
	var bad_tree := false
	for region in map.placements.size():
		var key := map.placements[region].biome.get_key()
		if key != "forest" and key != "desert":
			continue
		var c := map.get_placement_rect(region).get_center()
		var coord := Vector2i(floori(c.x / s.chunk_size), floori(c.y / s.chunk_size))
		var trees := TerrainChunk._scatter_trees(map, coord, s.chunk_size)
		for style in trees:
			for p: Vector3 in trees[style]["pos"]:
				var w := Vector3(p.x + coord.x * s.chunk_size, p.y, p.z + coord.y * s.chunk_size)
				if key == "forest":
					forest_trees += 1
				else:
					desert_trees += 1
				if map.is_on_pad(w.x, w.z) or map.is_under_water(w.y - 0.2) or net.distance_to(w.x, w.z, 3.0) < 3.0:
					bad_tree = true
	check("forests are thick with trees (%d in one chunk)" % forest_trees, forest_trees >= 20)
	check("deserts only have a few (%d)" % desert_trees, desert_trees < forest_trees / 3)
	check("no tree on a road, in a town or in the water", not bad_tree)


# ---------------------------------------------------------------- in a running world

func make_player(parent: Node) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.collision_layer = 1
	p.collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	p.add_child(head)
	head.add_child(Camera3D.new())
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	stats.base_stats["max_health"] = 50000.0
	p.add_child(stats)
	var inv := Inventory.new()
	inv.name = "Inventory"
	inv.stats = stats
	p.add_child(inv)
	var eq := Equipment.new()
	eq.name = "Equipment"
	eq.inventory = inv
	eq.stats = stats
	p.add_child(eq)
	var sk := Skills.new()
	sk.name = "Skills"
	p.add_child(sk)
	var mc := MeleeCombat.new()
	mc.name = "MeleeCombat"
	p.add_child(mc)
	var st := Stealth.new()
	st.name = "Stealth"
	p.add_child(st)
	for ui in [DialogueUI.new(), BarterUI.new(), CompassHUD.new()]:
		ui.name = ui.get_script().get_global_name()
		p.add_child(ui)
	p.add_to_group("player")
	parent.add_child(p)
	return p


func t_world() -> void:
	print("-- the large world in play")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var p := make_player(holder)
	var s := (load(GRAND) as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = s
	wm.encounters_enabled = false
	holder.add_child(wm)
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)
	check("a water surface at sea level", wm._water != null and is_equal_approx(wm._water.global_position.y, s.sea_level))
	var town := wm.get_nearest_town(p.global_position)
	check("a new game starts at a town gate", wm.get_town_at(p.global_position, 20.0) == town)

	# tradesmen at work
	var tradesman: TownLife.Resident = null
	for t in wm.towns:
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			if NpcData.is_tradesman(r.data.role) and tradesman == null:
				tradesman = r
	check("tradesmen live in the towns", tradesman != null)
	if tradesman != null:
		var home := wm.get_building(tradesman.data.home_id)
		var spot := tradesman.town.town.get_trade_spot(home)
		check("at noon they work outside at their spot (%s)" % NpcData.role_name(tradesman.data.role), tradesman.inside == "" and tradesman.goal.get("outside", Vector3.INF) == spot)

	# road traffic
	var rl := wm.road_life
	check("the roads have traffic", rl != null and rl.enabled)
	rl.enabled = false  # the test drives it by hand
	var road: Dictionary = wm.map.roads.get_roads()[0]
	var pts: PackedVector3Array = road["points"]
	var mid := pts[pts.size() / 2]
	p.global_position = Vector3(mid.x, wm.get_height_at(mid.x, mid.z) + 1.0, mid.z)
	wm.ensure_area_loaded(p.global_position, 2)
	await secs(1.0)
	var kinds := {}
	var members_ok := true
	for i in 3:
		var got: Array = rl.spawn_group(RoadLife.KINDS[i])
		if not got.is_empty():
			kinds[RoadLife.KINDS[i]] = got
			for e: Enemy in got:
				var d := Vector2(e.global_position.x - p.global_position.x, e.global_position.z - p.global_position.z).length()
				members_ok = members_ok and d >= RoadLife.new().spawn_min - 5.0 and d <= 200.0 and e.state == Enemy.State.PATROL
	check("wardens, a merchant and a traveller appear on the road", kinds.size() == 3, str(kinds.keys()))
	check("out of sight, and walking along the road", members_ok)
	if kinds.has("wardens"):
		check("wardens come in pairs", (kinds["wardens"] as Array).size() == 2)
	if kinds.has("merchant"):
		var m: Enemy = kinds["merchant"][0]
		var sp := DialogueEngine.speaker_for(m, wm)
		var st := Barter.trade_status(sp, wm)
		check("you can barter with a travelling merchant", st["merchant"] != null and st["open"])
		var bui := p.get_node("BarterUI") as BarterUI
		check("their pack opens in the trade window", bui.open_for(sp) and bui.shop.inventory.stacks.size() > 0)
		bui.close()
	if kinds.has("wardens"):
		var w0: Enemy = kinds["wardens"][0]
		var wolf := Population.spawn_enemy(load(R + "enemies/wolf.tres") as EnemyData, 1, wm, w0.global_position + Vector3(6, 0.5, 0), RandomNumberGenerator.new(), {"persist_mode": Enemy.PersistMode.NEVER})
		rl.tick()
		await secs(0.2)
		check("road wardens go for a creature that comes near", w0.state == Enemy.State.CHASE or w0.state == Enemy.State.ATTACK)
		wolf.queue_free()
	var old: Array = []
	for g in rl.groups:
		old.append_array(g["members"] as Array)
	var far := p.global_position + Vector3(700, 0, 0)
	p.global_position = Vector3(far.x, wm.get_height_at(far.x, far.z) + 1.0, far.z)
	rl.tick()  # may also start a new group near the new spot
	await frames(3)
	var left := 0
	for e in old:
		if is_instance_valid(e):
			left += 1
	check("they are gone once you are far away (%d spawned)" % old.size(), left == 0, "%d still here" % left)

	# the map
	var dmap := wm.get_node_or_null("WorldDebugMap") as WorldDebugMap
	check("the world has a map", dmap != null)
	if dmap != null:
		dmap.open()
		await frames(5)
		check("opening the map pauses the game", dmap.is_open() and paused)
		var a := Vector2(123.0, -456.0)
		check("map coordinates go there and back", dmap.screen_to_world(dmap.world_to_screen(a)).distance_to(a) < 0.5)
		var z0 := dmap._zoom
		dmap.zoom_at(dmap._view.size / 2.0, 2.0)
		check("zooming in", dmap._zoom > z0)
		var t := wm.towns[0]
		dmap._center = Vector2(t.position.x, t.position.z)
		check("hovering a town names it", dmap.hover_name(dmap.world_to_screen(Vector2(t.position.x, t.position.z))).begins_with(t.town.display_name))
		dmap._cache_roads()
		check("the map has the roads to draw", not dmap._road_lines.is_empty())
		var target := Vector2(t.position.x + 40.0, t.position.z)
		check("teleporting is a debug feature", dmap.can_teleport() == OS.is_debug_build())
		dmap.teleport_to(target)
		await frames(3)
		check("right click teleports you there, on the ground", Vector2(p.global_position.x, p.global_position.z).distance_to(target) < 1.0 and p.global_position.y > wm.get_height_at(target.x, target.y))
		check("and closes the map", not dmap.is_open() and not paused)

	# the compass
	var compass := p.get_node("CompassHUD") as CompassHUD
	p.rotation.y = 0.0  # facing north (-Z)
	check("the compass: north is straight ahead", absf(compass._strip_x(0.0, Vector3(0, 0, -1))) < 1.0)
	check("east is to the right, west to the left", compass._strip_x(0.0, Vector3(1, 0, 0)) > 100.0 and compass._strip_x(0.0, Vector3(-1, 0, 0)) < -100.0)
	check("what is behind you is off the strip", compass._strip_x(0.0, Vector3(0.1, 0, 1)) == INF)
	var town2 := wm.towns[1]
	compass._last_town = ""
	p.global_position = Vector3(town2.position.x, town2.position.y + 1.0, town2.position.z)
	compass._check_town()
	check("walking into a town shows its name", compass._banner.text == town2.town.display_name and compass._banner_time > 0.0)
	holder.queue_free()
	await frames(3)
