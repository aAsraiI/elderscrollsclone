extends SceneTree
## Headless tests for stage 2: towns, roads, building interiors, locks and keys. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage2.gd

const R := "res://scripts/Resources/"

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
	t_locks_and_keys()
	t_plan()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _settings() -> WorldSettings:
	var s := (load(R + "World/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	return s


# Plans a world the way WorldManager does, without any nodes
func _plan(settings: WorldSettings, world_seed: int) -> Dictionary:
	var map := WorldMap.new(settings, world_seed)
	var towns := SettlementPlanner.plan(map)
	map.set_pads(towns)
	SettlementPlanner.lay_out(map, towns)
	map.set_roads(RoadPlanner.plan(map, towns))
	var pois := towns.duplicate()
	pois.append_array(POIPlanner.plan(map, towns))
	map.set_pads(pois)
	return {"map": map, "towns": towns, "pois": pois}


# ---------------------------------------------------------------- pure logic

func t_locks_and_keys() -> void:
	print("-- locks and keys")
	check("lock tiers have names", Locks.tier_name(5) == "Novice" and Locks.tier_name(45) == "Adept" and Locks.tier_name(100) == "Requires a key")
	check("a beginner has a fair chance at a novice lock", Locks.pick_chance(1, 0.0, 5) > 0.4)
	check("a beginner has almost no chance at a master lock", Locks.pick_chance(1, 0.0, 90) <= 0.05)
	check("a master has a good chance at a master lock", Locks.pick_chance(100, 0.0, 90) > 0.6)
	check("a key-only lock can't be picked", Locks.pick_chance(100, 1.0, 100) == 0.0)
	check("the lockpick item exists", Locks.get_lockpick() != null and Locks.get_lockpick().stackable)

	WorldState.clear()
	check("a lock starts as the building says", Locks.is_locked("t/b1", true) and not Locks.is_locked("t/b2", false))
	Locks.set_locked("t/b1", false)
	check("a changed lock is remembered in WorldState", not Locks.is_locked("t/b1", true) and WorldState.has_record("lock/t/b1"))

	var k1 := KeyRing.get_key("t/b1", "Brenna's House")
	var k2 := KeyRing.get_key("t/b1", "Brenna's House")
	check("asking twice gives the same key", k1 == k2)
	check("a key is a KEY item named after its door", k1.item_type == ItemData.ItemType.KEY and k1.display_name.contains("Brenna's House"))
	check("a key knows its lock", KeyRing.lock_id_of(k1) == "t/b1")
	var path := SaveUtil.item_to_path(k1)
	check("a key saves as a key:// path", path.begins_with("key://"), path)
	check("and loads back as the same key", SaveUtil.path_to_item(path) == k1)
	var inv := Inventory.new()
	inv.add_item(k1)
	inv.add_item(load(R + "Consumables/gold.tres"), 5)
	var saved := inv.to_dict()
	var inv2 := Inventory.new()
	inv2.from_dict(saved)
	check("a key in the inventory survives a save", inv2.has_item(k1) and inv2.stacks.size() == 2)
	inv.free()
	inv2.free()
	WorldState.clear()


func t_plan() -> void:
	print("-- planning towns and roads")
	var settings := _settings()
	var t0 := Time.get_ticks_msec()
	var a := _plan(settings, 1337)
	print("   (planned in %d ms)" % (Time.get_ticks_msec() - t0))
	var map: WorldMap = a["map"]
	var towns: Array[PlacedPOI] = []
	towns.assign(a["towns"])
	check("the world has towns", towns.size() >= 8, str(towns.size()))

	# one city per biome, a few towns per region
	var cities := {}
	var per_region := {}
	for t in towns:
		var data := t.poi as TownData
		var key := map.placements[t.region].biome.get_key()
		if data.kind == TownData.Kind.CITY:
			cities[key] = int(cities.get(key, 0)) + 1
		else:
			per_region[t.region] = int(per_region.get(t.region, 0)) + 1
	var biome_keys := {}
	for p in map.placements:
		biome_keys[p.biome.get_key()] = true
	var one_city := true
	for k in biome_keys:
		if int(cities.get(k, 0)) != 1:
			one_city = false
	check("every biome has exactly one city", one_city, str(cities))
	var enough := true
	for r in map.placements.size():
		if int(per_region.get(r, 0)) < settings.towns_per_region_min:
			enough = false
	check("every region has at least %d towns or villages" % settings.towns_per_region_min, enough, str(per_region))

	# same seed, same world
	var b := _plan(settings, 1337)
	var same := towns.size() == (b["towns"] as Array).size()
	if same:
		for i in towns.size():
			var t1 := towns[i]
			var t2: PlacedPOI = b["towns"][i]
			if t1.id != t2.id or t1.position.distance_to(t2.position) > 0.01 or t1.town.display_name != t2.town.display_name or t1.town.buildings.size() != t2.town.buildings.size():
				same = false
			elif t1.town.buildings[t1.town.buildings.size() - 1].owner_name != t2.town.buildings[t2.town.buildings.size() - 1].owner_name:
				same = false
	check("the same seed gives the same towns, names and buildings", same)
	var c := _plan(settings, 4242)
	check("another seed gives other towns", (c["towns"] as Array).size() > 0 and (c["towns"][0] as PlacedPOI).position.distance_to(towns[0].position) > 1.0)

	# names
	var names := {}
	for t in towns:
		names[t.town.display_name] = true
	check("every town has its own name", names.size() == towns.size(), str(names.keys()))

	# layouts
	var overlap := false
	var outside := false
	var on_street := false
	var ids := {}
	var dup_ids := false
	var owners_ok := true
	var locks_ok := true
	var farms := 0
	var city: PlacedPOI = null
	for t in towns:
		var layout := t.town
		var rects: Array[Rect2] = []
		for bp in layout.buildings:
			var rect := bp.get_local_rect()
			for other in rects:
				if rect.intersects(other):
					overlap = true
			rects.append(rect)
			for corner in [rect.position, rect.end]:
				if (corner as Vector2).length() > layout.radius * 1.05:
					outside = true
			for st in layout.streets:
				if st.get_rect().intersects(rect):
					on_street = true
			if ids.has(bp.id):
				dup_ids = true
			ids[bp.id] = true
			if bp.owner_name == "" or bp.display_name == "":
				owners_ok = false
			if bp.lock_level < 1 or bp.lock_level > 100 or (bp.is_public() and bp.starts_locked):
				locks_ok = false
			if bp.kind == BuildingPlot.Kind.FARM:
				farms += 1
		if (t.poi as TownData).kind == TownData.Kind.CITY and city == null:
			city = t
	check("no two buildings overlap", not overlap)
	check("buildings stay inside their town", not outside)
	check("no building stands on a street", not on_street)
	check("every building has its own id", not dup_ids)
	check("every building has a name and an owner", owners_ok)
	check("lock levels are 1-100 and shops, inns and halls start open", locks_ok)
	check("villages have farms", farms >= 2, str(farms))
	check("there is a city", city != null)
	if city != null:
		var cl := city.town
		check("the city has walls", cl.wall_half > 0.0)
		check("the city has a hall for each of the three guilds", cl.count_kind(BuildingPlot.Kind.GUILD_HALL) == 3)
		check("the city has a temple, inns and shops", cl.count_kind(BuildingPlot.Kind.TEMPLE) >= 1 and cl.count_kind(BuildingPlot.Kind.INN) >= 1 and cl.count_kind(BuildingPlot.Kind.SHOP) >= 3)
		check("the city has plenty of houses", cl.count_kind(BuildingPlot.Kind.HOUSE) >= 8, str(cl.count_kind(BuildingPlot.Kind.HOUSE)))
		var flat := true
		for bp in cl.buildings:
			if absf(bp.world_pos.y - city.position.y) > 0.5:
				flat = false
		check("the city's buildings stand on its leveled ground", flat)

	# roads
	var net := map.roads
	var roads := net.get_roads()
	check("there are roads", roads.size() >= towns.size() - 1, "%d roads for %d towns" % [roads.size(), towns.size()])
	var parent := {}
	for t in towns:
		parent[t.id] = t.id
	var find := func(x: String) -> String:
		while parent[x] != x:
			x = parent[x]
		return x
	for r in roads:
		var ra: String = find.call(r["from"])
		var rb: String = find.call(r["to"])
		parent[ra] = rb
	var groups := {}
	for t in towns:
		groups[find.call(t.id)] = true
	check("the roads connect every town", groups.size() == 1, "%d separate groups" % groups.size())

	var ends_ok := true
	var steep := 0.0
	var through_town := false
	var ground_ok := true
	var by_id := {}
	for t in towns:
		by_id[t.id] = t
	for r in roads:
		var pts: PackedVector3Array = r["points"]
		var ta: PlacedPOI = by_id[r["from"]]
		var tb: PlacedPOI = by_id[r["to"]]
		var near_a := false
		var near_b := false
		for g in ta.town.get_gates_world():
			near_a = near_a or g.distance_to(pts[0]) < 1.0
		for g in tb.town.get_gates_world():
			near_b = near_b or g.distance_to(pts[pts.size() - 1]) < 1.0
		ends_ok = ends_ok and near_a and near_b
		# the grade of the ground you actually walk on, every 3 m along the road
		var prev := Vector3.INF
		for i in pts.size() - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			var steps := maxi(int(seg / 3.0), 1)
			for k in steps:
				var q := pts[i].lerp(pts[i + 1], float(k) / float(steps))
				q.y = map.get_height(q.x, q.z)
				if prev != Vector3.INF:
					var run := Vector2(q.x - prev.x, q.z - prev.z).length()
					if run > 1.0:
						steep = maxf(steep, absf(q.y - prev.y) / run)
				prev = q
		for i in range(0, pts.size(), 3):
			var p := pts[i]
			for t in towns:
				if t == ta or t == tb:
					continue
				if Vector2(p.x - t.position.x, p.z - t.position.z).length() < t.poi.footprint_radius * 0.8:
					through_town = true
			if i > 0 and i < pts.size() - 1 and absf(map.get_height(p.x, p.z) - p.y) > 0.35:
				ground_ok = false
	check("roads start and end at town gates", ends_ok)
	check("roads are never steeper than the limit (%d%%)" % roundi(settings.road_max_grade * 100.0), steep <= settings.road_max_grade + 0.05, "%.2f" % steep)
	check("roads go around other towns, not through them", not through_town)
	check("the ground is leveled to the road", ground_ok)
	var road_pt: Vector3 = (roads[0]["points"] as PackedVector3Array)[(roads[0]["points"] as PackedVector3Array).size() / 2]
	var s := WorldMap.Sample.new()
	map.sample(road_pt.x, road_pt.z, s)
	check("roads are colored on the ground", s.color.is_equal_approx(RoadPlanner.ROAD_COLOR), str(s.color))
	var street_pt := city.town.to_world(Vector3(city.town.radius * 0.5, 0, 0)) if city != null else road_pt
	map.sample(street_pt.x, street_pt.z, s)
	check("town streets are colored too", city == null or s.color.is_equal_approx((city.poi as TownData).street_color), str(s.color))

	# everything else keeps out of the way
	var clear := true
	for p in a["pois"]:
		if p.poi is TownData:
			continue
		if net.distance_to(p.position.x, p.position.z, p.poi.footprint_radius) < p.poi.footprint_radius:
			clear = false
		for t in towns:
			if p.position.distance_to(t.position) < p.poi.footprint_radius + t.poi.footprint_radius:
				clear = false
	check("camps, caves and ruins keep off the roads and out of towns", clear)


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
	p.add_to_group("player")
	parent.add_child(p)
	return p


func _teleport(wm: WorldManager, p: Node3D, pos: Vector3) -> void:
	wm.ensure_area_loaded(pos, 2)
	p.global_position = Vector3(pos.x, wm.get_height_at(pos.x, pos.z) + 1.0, pos.z)


func _door_of(wm: WorldManager, b: BuildingPlot) -> BuildingDoor:
	var node := wm.get_poi_node(b.town_id)
	if node == null:
		return null
	for d in node.find_children("*", "BuildingDoor", true, false):
		if (d as BuildingDoor).building_id == b.id:
			return d
	return null


func t_world() -> void:
	print("-- towns in a running world")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var player := make_player(holder)
	var inv := player.get_node("Inventory") as Inventory
	var skills := player.get_node("Skills") as Skills
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = _settings()
	holder.add_child(wm)
	await frames(10)
	wm.clock.set_time(12.0)  # midday: shops are open (people come with stage 3)
	wm.crime.process_mode = Node.PROCESS_MODE_DISABLED  # no arrests here: picking locks in plain view is tested in test_stage6a
	await secs(0.7)
	check("the world planned towns", wm.towns.size() >= 8)
	check("towns are points of interest too", wm.get_poi(wm.towns[0].id) == wm.towns[0])

	var town := wm.get_nearest_town(player.global_position)
	var at_gate := false
	for g in town.town.get_gates_world():
		at_gate = at_gate or Vector2(g.x - player.global_position.x, g.z - player.global_position.z).length() < 15.0
	check("a new game starts at a town gate", at_gate, str(player.global_position))
	check("the start is next to town, not inside its buildings", wm.get_town_at(player.global_position, 5.0) != null)

	await secs(1.0)
	var node := wm.get_poi_node(town.id)
	check("the town is built when its chunk loads", node != null)
	if node == null:
		return
	var doors := node.find_children("*", "BuildingDoor", true, false)
	check("every building has a door", doors.size() == town.town.buildings.size(), "%d doors, %d buildings" % [doors.size(), town.town.buildings.size()])
	check("buildings have name signs", node.find_children("*", "Label3D", true, false).size() >= town.town.buildings.size())
	check("buildings are solid", node.find_children("*", "StaticBody3D", true, false).size() > doors.size() * 2)
	check("a building can be found by its id", wm.get_building(town.town.buildings[0].id) == town.town.buildings[0])
	check("a wrong id finds nothing", wm.get_building(town.id + "/b999") == null and wm.get_building("nonsense") == null)

	# no fights start in town
	var em := wm.encounters
	em.chance = 1.0
	_teleport(wm, player, town.position + Vector3(0, 0, 3))
	await frames(5)
	var spawned := 0
	for i in 5:
		spawned += em.try_encounter().size()
	check("random encounters never start in a town", spawned == 0, str(spawned))

	# a public building: walk right in
	var shop: BuildingPlot = null
	var house: BuildingPlot = null
	var house2: BuildingPlot = null
	for bp in town.town.buildings:
		if bp.is_public() and shop == null:
			shop = bp
		elif not bp.is_public() and bp.starts_locked and bp.lock_level < 100:
			if house == null:
				house = bp
			elif house2 == null:
				house2 = bp
	check("the town has a public building and two locked houses to test", shop != null and house != null and house2 != null)
	if shop == null or house == null or house2 == null:
		return
	var dm := wm.dungeons
	var door := _door_of(wm, shop)
	check("the shop door is not locked", door != null and not door.is_locked())
	check("its prompt names the building", door.get_prompt() == "Enter " + shop.display_name, door.get_prompt())
	_teleport(wm, player, shop.get_door_position())
	door.interact(inv)
	await secs(0.8)
	check("the door takes you inside", dm.is_inside() and dm.is_in_building())
	check("inside is far below the world", player.global_position.y < DungeonManager.DUNGEON_Y + 50.0, str(player.global_position))
	check("the inside knows which building it is", dm.current_entrance_id == shop.id and dm.get_current_name() == shop.display_name)
	var inside: Node3D = dm._root
	check("the inside has lamps", inside.find_children("*", "OmniLight3D", true, false).size() >= 1)
	var exits := inside.find_children("*", "DungeonDoor", true, false)
	check("the inside has a way out", exits.size() == 1 and (exits[0] as DungeonDoor).is_exit)
	var chests := inside.find_children("*", "ContainerComponent", true, false)
	check("the inside has the owner's chest, saved by id", chests.size() >= 1 and (chests[0] as ContainerComponent).save_id.begins_with("building/" + shop.id))
	var standing := true
	await secs(0.5)
	standing = player.global_position.y > DungeonManager.DUNGEON_Y - 1.0
	check("the player stands on the floor inside", standing, str(player.global_position.y))
	check("no encounters inside", em.try_encounter(true).is_empty())

	# save inside, restore inside
	var saved := dm.to_dict()
	check("being inside a building is saved", bool(saved.get("inside", false)) and saved.get("entrance") == shop.id)
	(exits[0] as DungeonDoor).interact(inv)
	await secs(0.8)
	check("leaving puts you back outside, at the door", not dm.is_inside() and player.global_position.distance_to(shop.get_door_position()) < 4.0, str(player.global_position.distance_to(shop.get_door_position())))
	check("and the inside is gone", not is_instance_valid(inside))
	check("a saved visit can be rebuilt", dm.restore(saved) and dm.is_in_building() and dm.current_entrance_id == shop.id)
	await dm.exit()
	await frames(2)

	# a locked house, no lockpicks
	door = _door_of(wm, house)
	check("the house door is locked", door != null and door.is_locked())
	check("the prompt says so", door.get_prompt().contains("Locked"), door.get_prompt())
	_teleport(wm, player, house.get_door_position())
	door.interact(inv)
	await secs(0.5)
	check("without a key or a lockpick it stays shut", not dm.is_inside() and door.is_locked())

	# lockpicks: a skilled picker gets in, and breaks picks on the way
	skills.levels[&"security"] = 60
	var pick := Locks.get_lockpick()
	inv.add_item(pick, 30)
	var xp_before := skills.get_xp(&"security") + skills.get_level(&"security") * 1000.0
	var tries := 0
	while door.is_locked() and tries < 30:
		door.try_unlock(inv)
		tries += 1
	check("picking eventually opens the lock", not door.is_locked(), "%d tries" % tries)
	check("picking trains Security", skills.get_xp(&"security") + skills.get_level(&"security") * 1000.0 > xp_before)
	check("every failed try broke a lockpick", inv.get_count(pick) == 30 - (tries - 1))
	check("the open lock is saved", WorldState.has_record("lock/" + house.id) and not Locks.is_locked(house.id, true))
	door.interact(inv)
	await secs(0.8)
	check("an opened house can be entered", dm.is_inside() and dm.current_entrance_id == house.id)
	var owner_chest := false
	for c in dm._root.find_children("*", "ContainerComponent", true, false):
		owner_chest = owner_chest or (c as ContainerComponent).display_name.begins_with(NameGen.first_name(house.owner_name))
	check("the house is furnished and has its owner's chest", dm._root.get_child_count() > 15 and owner_chest)
	await dm.exit()
	await frames(2)

	# a key opens its own door, and no other
	var door2 := _door_of(wm, house2)
	inv.remove_item(pick, inv.get_count(pick))
	var key := KeyRing.get_key(house.id, house.display_name)
	inv.add_item(key)
	check("the wrong key does nothing", not door2.try_unlock(inv) and door2.is_locked())
	inv.add_item(door2.get_key())
	_teleport(wm, player, house2.get_door_position())
	door2.interact(inv)
	await secs(0.8)
	check("the right key opens the door and lets you in", not door2.is_locked() and dm.is_inside() and dm.current_entrance_id == house2.id)
	check("the key is kept", inv.has_item(door2.get_key()))
	await dm.exit()
	await frames(2)

	# going far away and back: the town comes back with the same doors and locks
	var far := town.position + Vector3(900, 0, 0)
	if wm.map.get_inside_distance(far.x, far.z) < 200.0:
		far = town.position - Vector3(900, 0, 0)
	_teleport(wm, player, far)
	await secs(2.0)
	check("the town is removed when you are far away", wm.get_poi_node(town.id) == null)
	_teleport(wm, player, house.get_door_position())
	await secs(1.0)
	door = _door_of(wm, house)
	check("coming back, the picked door is still open", door != null and not door.is_locked())
	door2 = _door_of(wm, house2)
	check("and so is the one opened with the key", door2 != null and not door2.is_locked())
	holder.queue_free()
	await frames(2)
