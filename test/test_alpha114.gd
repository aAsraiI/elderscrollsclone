extends SceneTree
## Headless tests for Alpha 1.14 (exteriors): outdoor sites as scenes, the site library, outdoor
## dungeons, placement, small places, towns, walls, buildings, signs, dressing, life and speed.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha114.gd

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
	await process_frame
	t_sites()
	t_build_sites()
	t_small_places()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- 1.14.1-2 sites

func t_sites() -> void:
	print("-- site scenes")
	var probs := PackedStringArray()
	var kinds := {}
	var count := 0
	var linked := 0
	for f in DirAccess.get_files_at("res://scenes/sites/"):
		if not f.ends_with(".tscn"):
			continue
		var s := (load("res://scenes/sites/" + f) as PackedScene).instantiate() as ExteriorSite
		if s == null:
			probs.append("%s is not an ExteriorSite" % f)
			continue
		count += 1
		kinds[s.site_kind] = true
		probs.append_array(s.problems())
		if s.sockets().is_empty():
			probs.append("%s has no spawn points" % f)
		if not s.links().is_empty():
			linked += 1
		s.free()
	check("site scenes (%d over %d kinds)" % [count, kinds.size()], count >= 54 and kinds.size() >= 35 and count >= kinds.size() + 15)
	check("the site checker finds nothing wrong", probs.is_empty(), "\n".join(probs.slice(0, 8)))
	check("sites with a way down into a dungeon (%d)" % linked, linked >= 8)


func t_build_sites() -> void:
	print("-- building every kind")
	WorldState.clear()
	var bad := PackedStringArray()
	var built := 0
	for f in DirAccess.get_files_at("res://data/world/Sites/"):
		if not f.ends_with(".tres"):
			continue
		var d := load("res://data/world/Sites/" + f) as SitePOIData
		for v in d.sites.size():
			var placed := PlacedPOI.new()
			placed.id = "test/site_%s_%d" % [f.get_basename(), v]
			placed.poi = d
			placed.seed_value = v
			var root := d.build(placed, null)
			built += 1
			var site := root.get_child(0) as ExteriorSite
			var props := site.find_children("*", "InteriorProp", true, false).size() + site.find_children("*", "HarvestNode", true, false).size() + site.find_children("*", "Readable", true, false).size()
			var enemies := site.find_children("*", "Enemy", true, false).size()
			var doors := site.find_children("*", "DungeonDoor", true, false).size()
			if props < (1 if not d.discoverable else 2):
				bad.append("%s v%d: %d props" % [f, v, props])
			var can_live := d.occupants != null and not d.occupants.roll(RandomNumberGenerator.new(), 1).is_empty()
			if can_live and d.discoverable and enemies == 0 and not f.begins_with("hunters") and not f.begins_with("lighthouse") and not f.begins_with("mine"):
				bad.append("%s v%d: nobody lives there" % [f, v])
			if d.dungeon != null and not site.links().is_empty() and doors != 1:
				bad.append("%s v%d: no way down" % [f, v])
			if site.get_node_or_null("MergedRoom") == null and site.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return (m as MeshInstance3D).mesh is PrimitiveMesh).size() > 12:  # plain boxes (props are models since 1.15.6)
				bad.append("%s v%d: not merged" % [f, v])
			root.free()
	check("every kind builds, filled, with its people and its way down (%d built)" % built, bad.is_empty(), "\n".join(bad.slice(0, 8)))
	WorldState.clear()


func t_in_game() -> void:
	print("-- sites in the world")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(90)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", wm != null and p != null)
	if wm == null:
		return
	var sites := wm.pois.filter(func(x: PlacedPOI) -> bool: return x.poi is SitePOIData)
	var kinds := {}
	for s: PlacedPOI in sites:
		kinds[s.poi.get_key()] = true
	check("the world has outdoor sites (%d of %d kinds)" % [sites.size(), kinds.size()], sites.size() >= 40 and kinds.size() >= 15)
	# the nearest one with a way down: walk up, go down, come back up
	var linked: PlacedPOI = null
	for s: PlacedPOI in sites:
		var d := s.poi as SitePOIData
		if d.dungeon != null and (linked == null or s.position.distance_to(p.global_position) < linked.position.distance_to(p.global_position)):
			var probe := d.pick(s).instantiate() as ExteriorSite
			if not probe.links().is_empty():
				linked = s
			probe.free()
	check("a site with a way down", linked != null)
	if linked == null:
		return
	wm.ensure_area_loaded(linked.position, 2)
	p.global_position = linked.position + Vector3(0, 3, -25)
	await frames(30)
	var node: Node3D = wm._poi_nodes.get(linked.id)
	check("it is built where it stands", node != null and node.get_child(0) is ExteriorSite)
	if node == null:
		return
	var door := node.find_children("*", "DungeonDoor", true, false)
	check("its way down is there", door.size() == 1)
	if door.is_empty():
		return
	var d0 := door[0] as DungeonDoor
	var ok: bool = await wm.dungeons.enter(d0.entrance_id, d0.to_global(d0.return_offset), 0.0)
	await frames(30)
	check("going down builds its dungeon", ok and wm.dungeons.is_inside() and wm.dungeons.nav != null, "%s ok=%s inside=%s nav=%s recipe=%s" % [linked.poi.get_key(), ok, wm.dungeons.is_inside(), wm.dungeons.nav, (linked.poi as SitePOIData).dungeon.recipe])
	await wm.dungeons.exit()
	await frames(20)
	check("coming back up puts you by the way down", not wm.dungeons.is_inside() and p.global_position.distance_to(d0.global_position) < 6.0, str(p.global_position.distance_to(d0.global_position)))
	await t_placement(wm, p)
	t_integration(wm, p)
	t_qa(wm)
	t_towns(wm)
	t_walls(wm)
	t_buildings(wm)
	await t_dressing(wm)
	t_speed(wm)


# ---------------------------------------------------------------- 1.14.5 small places

func t_small_places() -> void:
	print("-- small places")
	var bad := PackedStringArray()
	var want := {"dead_traveller": "Readable", "herb_patch": "HarvestNode", "ore_outcrop": "HarvestNode", "wayside_inn": "Enemy", "wayside_shrine": "RestSpot", "monument": "Readable"}
	for kind: String in want:
		var d := load("res://data/world/Sites/%s.tres" % kind) as SitePOIData
		var placed := PlacedPOI.new()
		placed.id = "test/small_" + kind
		placed.poi = d
		var root := d.build(placed, null)
		if root.find_children("*", want[kind], true, false).is_empty():
			bad.append("%s has no %s" % [kind, want[kind]])
		root.free()
	check("notes to read, shrines that bless, herbs and ore to gather, a keeper at the wayside rest", bad.is_empty(), "\n".join(bad))
	var small := ["roadside_camp", "wrecked_cart", "dead_traveller", "lost_pack", "fishing_spot", "herb_patch", "ore_outcrop", "nest"]
	check("small places are not 'discovered' or put on the map", small.all(func(k: String) -> bool: return not (load("res://data/world/Sites/%s.tres" % k) as POIData).discoverable))
	var sp := SignpostPOIData.new()
	var placed2 := PlacedPOI.new()
	placed2.poi = sp
	placed2.named = {"arms": [[0.0, "Kingsreach  2.0 km"], [PI, "Harrowford  3.5 km"]]}
	var post := sp.build(placed2, null)
	var r := post.find_children("*", "Readable", true, false)
	check("a signpost has an arm for each way and reads them out", r.size() == 1 and (r[0] as Readable).text.contains("Kingsreach") and (r[0] as Readable).text.contains("Harrowford"))
	post.free()


# ---------------------------------------------------------------- 1.14.4 placement

func t_placement(wm: WorldManager, p: CharacterBody3D) -> void:
	print("-- placement")
	var map := wm.map
	var sites := wm.pois.filter(func(x: PlacedPOI) -> bool: return x.poi is SitePOIData and x.poi.discoverable)
	var area := 0.0
	for i in map.placements.size():
		var rect := map.get_placement_rect(i)
		area += rect.size.x * rect.size.y / 1.0e6
	check("places every few hundred meters (%.1f sites per km2 over %.0f km2)" % [sites.size() / maxf(area, 1.0), area], sites.size() / maxf(area, 1.0) >= 0.8)
	# what they like: forts high, water places by the water
	var high := 0.0
	var high_n := 0
	var wet := 0
	var wet_n := 0
	var too_close := 0
	for s: PlacedPOI in sites:
		var d := s.poi as SitePOIData
		if d.prefer == "high":
			high += POIPlanner._score(map, s.position.x, s.position.z, s.position.y, "high")
			high_n += 1
		elif d.prefer == "water":
			wet_n += 1
			if POIPlanner._score(map, s.position.x, s.position.z, s.position.y, "water") > 0.0:
				wet += 1
		if d.min_same_distance > 0.0:
			for o: PlacedPOI in sites:
				if o != s and o.poi == s.poi and o.position.distance_to(s.position) < d.min_same_distance - 1.0:
					too_close += 1
	check("hill places stand above the land round them (%.1f m on average)" % (high / maxf(high_n, 1)), high_n == 0 or high / high_n > 0.5)
	check("water places stand by the water (%d of %d)" % [wet, wet_n], wet_n == 0 or wet >= wet_n * 0.5)
	check("places of a kind keep their distance", too_close == 0, str(too_close))
	var paths := map.roads.polylines.filter(func(r: Dictionary) -> bool: return String(r["from"]).begins_with("r") and bool(r["street"]) and String(r["to"]) == "")
	check("paths lead off the roads to places (%d)" % paths.size(), paths.size() >= 10)
	var posts := wm.pois.filter(func(x: PlacedPOI) -> bool: return x.poi is SignpostPOIData and x.named.has("arms"))
	var stones := wm.pois.filter(func(x: PlacedPOI) -> bool: return x.poi is SignpostPOIData and x.named.has("milestone"))
	check("signposts where the roads meet (%d) and milestones along them (%d)" % [posts.size(), stones.size()], posts.size() >= 3 and stones.size() >= 5)
	# places change hands
	WorldState.clear()
	var farm: PlacedPOI = null
	for s: PlacedPOI in sites:
		if s.poi.get_key() == "site_farmstead":
			farm = s
			break
	if farm != null:
		var before := (farm.poi as SitePOIData).build(farm, map)
		var calm := before.find_children("*", "Enemy", true, false).filter(func(e: Node) -> bool: return not e.has_meta("animal")).size()
		before.free()
		SiteChanges._new_owners(wm, farm, 5, RandomNumberGenerator.new(), "taken")
		var after := (farm.poi as SitePOIData).build(farm, map)
		var now := after.find_children("*", "Enemy", true, false).filter(func(e: Node) -> bool: return not e.has_meta("animal")).size()
		after.free()
		check("bandits can take a farm (%d people before, %d after)" % [calm, now], calm == 0 and now > 0)
		check("...and folk talk about it", Rumors.all().any(func(r: Dictionary) -> bool: return String(r.get("poi", r.get("poi_id", ""))) == farm.id or String(r.get("text", "")).contains("taken")))
	var camp: PlacedPOI = null
	for s: PlacedPOI in sites:
		if s.poi.get_key() == "site_bandit_camp":
			camp = s
			break
	if camp != null:
		WorldState.set_record("found/" + camp.id, {"cleared": true, "cleared_day": 1})
		WorldState.set_record("kill/%s/x/0" % camp.id, {"dead": true})
		SiteChanges.daily(wm, 1 + SiteChanges.NEW_OWNERS_DAYS)
		check("a cleared camp gets new owners after a while", WorldState.has_record("site_owners/" + camp.id) and not Discovery.is_cleared(camp.id) and not WorldState.has_record("kill/%s/x/0" % camp.id))
	WorldState.clear()
	# far-off landmarks
	var far := wm.find_children("*", "FarLand", true, false)
	if not far.is_empty():
		(far[0] as FarLand)._update_landmarks(p.global_position)
		check("tall places stand on the horizon (%d)" % (far[0] as FarLand)._landmarks.size(), (far[0] as FarLand)._landmarks.size() > 0)
	else:
		var fl := FarLand.new()
		fl.world = wm
		fl._update_landmarks(p.global_position)
		check("tall places stand on the horizon (%d)" % fl._landmarks.size(), fl._landmarks.size() > 0)
		fl.free()


# ---------------------------------------------------------------- 1.14.6 town layout

func t_towns(wm: WorldManager) -> void:
	print("-- towns")
	check("a new game has the 1.14 towns", TownLayout.compact and WorldState.has_record("town_layout") or TownLayout.compact)
	var city: PlacedPOI = null
	var town: PlacedPOI = null
	for t in wm.towns:
		if t.town == null:
			continue
		if (t.poi as TownData).kind == TownData.Kind.CITY and city == null:
			city = t
		elif (t.poi as TownData).kind == TownData.Kind.TOWN and town == null:
			town = t
	check("there are cities and towns", city != null and town != null)
	if city == null or town == null:
		return
	# closer than before: the same place laid out the old way has fewer buildings
	for t: PlacedPOI in [city, town]:
		var now := t.town.buildings.size()
		TownLayout.compact = false
		var old := TownLayout.generate(t.poi as TownData, t, t.town.display_name, wm.map)
		TownLayout.compact = true
		check("%s is built closer (%d buildings, %d the old way)" % [t.town.display_name, now, old.buildings.size()], now > old.buildings.size())
	var districts := {}
	for b in city.town.buildings:
		districts[b.district] = true
	check("a city has its quarters (%s)" % ", ".join(districts.keys()), districts.has("market") and districts.has("residential") and districts.has("noble") and districts.size() >= 4)
	var alleys := city.town.streets.filter(func(s) -> bool: return s.half_width < 1.5)
	check("a city has alleys (%d)" % alleys.size(), alleys.size() >= 2 or city.town.radius < 70.0)
	var yards := 0
	for t in wm.towns:
		if t.town != null:
			for b in t.town.buildings:
				if b.yard:
					yards += 1
	check("houses in towns and villages have yards (%d)" % yards, yards >= 10)
	var tilted := 0
	for t in wm.towns:
		var a := wm.map.get_height(t.position.x - 15.0, t.position.z)
		var b2 := wm.map.get_height(t.position.x + 15.0, t.position.z)
		if absf(a - b2) > 0.2:
			tilted += 1
	check("towns follow the slope they stand on (%d of %d tilt)" % [tilted, wm.towns.size()], tilted > 0)
	var named := wm.towns.filter(func(t: PlacedPOI) -> bool: return not t.named.is_empty() and t.town != null and t.town.get_seat() != null)
	check("named settlements keep their lords' seats (%d)" % named.size(), named.size() >= 5)


# ---------------------------------------------------------------- 1.14.7 walls

func t_walls(wm: WorldManager) -> void:
	print("-- walls")
	var kinds := {}
	var round_ok := 0
	var walled := 0
	var gates_ok := 0
	for t in wm.towns:
		if t.town == null or t.town.wall_kind == "":
			continue
		walled += 1
		kinds[t.town.wall_kind] = int(kinds.get(t.town.wall_kind, 0)) + 1
		var poly := t.town.wall_poly
		# not a box: the distance from the middle varies round the wall
		var lo := INF
		var hi := 0.0
		for p in poly:
			lo = minf(lo, p.length())
			hi = maxf(hi, p.length())
		if poly.size() >= 12 and hi > lo * 1.08:
			round_ok += 1
		# both gates on the wall, and every building inside it
		var on := t.town.gates.size() == 2 and t.town.gates.all(func(g: Vector3) -> bool: return Geometry2D.is_point_in_polygon(Vector2(g.x, g.z) * 0.98, poly))
		var inside := t.town.buildings.all(func(b: BuildingPlot) -> bool: return Geometry2D.is_point_in_polygon(Vector2(b.local_pos.x, b.local_pos.z), poly))
		if on and inside:
			gates_ok += 1
	check("towns are walled by kind (%s)" % str(kinds), kinds.has("thick") and kinds.has("stone") and kinds.has("palisade"))
	check("the walls follow each town's shape, not a box (%d of %d)" % [round_ok, walled], round_ok == walled)
	check("the gates are in the wall and every building inside it (%d of %d)" % [gates_ok, walled], gates_ok == walled)
	var city: PlacedPOI = null
	for t in wm.towns:
		if t.town != null and t.town.wall_kind == "thick":
			city = t
			break
	if city != null:
		var root := TownBuilder.build(city.poi as TownData, city, wm.map)
		var stairs := root.find_children("WallStairs*", "", true, false).size()
		check("a slope up to the walkway at each gate (%d)" % stairs, stairs == 2)
		root.free()


# ---------------------------------------------------------------- 1.14.8-9 buildings and signs

func t_buildings(wm: WorldManager) -> void:
	print("-- buildings and signs")
	var styles := {}
	for t in wm.towns:
		styles[BuildingStyle.for_biome(t.town.biome_key if t.town != null else "").resource_path] = true
	check("towns in different lands build differently (%d styles)" % styles.size(), styles.size() >= 3)
	var city: PlacedPOI = null
	for t in wm.towns:
		if t.town != null and (t.poi as TownData).kind == TownData.Kind.CITY:
			city = t
			break
	var root := TownBuilder.build(city.poi as TownData, city, wm.map)
	var parts := root.find_children("Part_*", "", true, false)
	var kinds := {}
	for p in parts:
		kinds[String(p.name).trim_prefix("Part_").get_slice("@", 0).rstrip("0123456789")] = true
	check("buildings are put together from part scenes (%s) and a door you can see (DoorLook, 1.15.6)" % ", ".join(kinds.keys()), root.find_children("DoorLook*", "", true, false).size() > 10 and kinds.has("sign_bracket") and parts.size() > 50)
	var doors_ok := true
	for holder in root.get_children():
		if holder.has_meta("building_id") and (holder.get_node_or_null("Door") as BuildingDoor) == null:
			doors_ok = false
	check("every building keeps its door", doors_ok)
	var lit := root.get_node_or_null("LitWindows") as MeshInstance3D
	check("the town's windows are one mesh", lit != null and lit.mesh != null)
	TownBuilder.set_daylight(0.0)
	var night := TownBuilder.window_material().emission_energy_multiplier
	TownBuilder.set_daylight(1.0)
	var noon := TownBuilder.window_material().emission_energy_multiplier
	check("...lit at night, dark at noon", night > 1.0 and noon == 0.0)
	# signs: none on homes, a small board you can read on the trades, the name on a stone at the gates
	var home_signs := 0
	var trade_signs := 0
	var trades := 0
	for b in city.town.buildings:
		var holder := root.find_children("*", "", false, false).filter(func(n: Node) -> bool: return n.get_meta("building_id", "") == b.id)
		if holder.is_empty():
			continue
		var h: Node = holder[0]
		var labels := h.find_children("*", "Label3D", true, false).size()
		var sign := h.get_node_or_null("Sign") as Readable
		if b.kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM]:
			home_signs += labels + (1 if sign != null else 0)
		elif b.kind in [BuildingPlot.Kind.SHOP, BuildingPlot.Kind.INN, BuildingPlot.Kind.SMITHY, BuildingPlot.Kind.TEMPLE]:
			trades += 1
			if sign != null and sign.title == b.display_name and labels == 0:
				trade_signs += 1
	check("homes have no signs", home_signs == 0, str(home_signs))
	check("shops, inns, smithies and temples hang a small sign that reads their name (%d of %d)" % [trade_signs, trades], trades > 0 and trade_signs == trades)
	var stones := root.find_children("*", "Readable", true, false).filter(func(r: Node) -> bool: return (r as Readable).title == "the stone")
	check("the town's name is carved on a stone at each gate", stones.size() == city.town.gates.size() and (stones[0] as Readable).text.contains(city.town.display_name))
	root.free()
	# stilts in the swamp, flat roofs in the desert
	for want: Array in [["swamp", "stilts"], ["desert", "flat"]]:
		var st := BuildingStyle.for_biome(want[0])
		check("%s towns: %s" % want, st.base == want[1] or st.roof == want[1])
	# a hand-made building stands in for a generated one
	var b0: BuildingPlot = city.town.buildings[0]
	var o := InteriorOverrides.get_all()
	o.exteriors["%s/%s" % [b0.town_name, b0.display_name]] = load("res://scenes/buildings/parts/porch.tscn") as PackedScene
	var root2 := TownBuilder.build(city.poi as TownData, city, wm.map)
	var h0 := root2.find_children("*", "", false, false).filter(func(n: Node) -> bool: return n.get_meta("building_id", "") == b0.id)[0] as Node3D
	check("a hand-made building scene can replace a generated one", h0.get_node_or_null("Porch") != null and h0.get_node_or_null("Door") is BuildingDoor)
	o.exteriors.clear()
	root2.free()


# ---------------------------------------------------------------- 1.14.10-11 dressing and life

func t_dressing(wm: WorldManager) -> void:
	print("-- town dressing and life")
	var city: PlacedPOI = null
	for t in wm.towns:
		if t.town != null and (t.poi as TownData).kind == TownData.Kind.CITY:
			city = t
			break
	var counts := {}
	for d in city.town.dress:
		counts[d["what"]] = int(counts.get(d["what"], 0)) + 1
	check("a city's square and streets are dressed (%s)" % str(counts), counts.get("fountain", 0) == 1 and counts.get("stall", 0) >= 4 and counts.get("lamp", 0) >= 6 and counts.get("bench", 0) >= 1 and counts.get("notice", 0) == 1)
	var blocking := 0
	for d in city.town.dress:
		if String(d["what"]) == "flowers":
			continue  # under the windows, against the wall
		var q := Vector2(d["pos"].x, d["pos"].z)
		for s in city.town.streets:
			if s.get_rect().has_point(q):
				blocking += 1
		for b in city.town.buildings:
			var front := Basis(Vector3.UP, b.local_yaw) * Vector3(0, 0, -1)
			var door := b.local_pos + front * (b.size.z * 0.5 + 1.0)
			if Vector2(door.x, door.z).distance_to(q) < 1.2:
				blocking += 1
	check("nothing stands on a street or in a doorway", blocking == 0, str(blocking))
	var root := TownBuilder.build(city.poi as TownData, city, wm.map)
	get_root().add_child(root)
	await process_frame
	var lamps := get_nodes_in_group("town_lamps")
	check("street lamps with lights (%d)" % lamps.size(), lamps.size() >= 6)
	TownBuilder.set_lamps(self, true)
	var on := lamps.all(func(l: Node) -> bool: return (l as Node3D).visible)
	TownBuilder.set_lamps(self, false)
	var off := lamps.all(func(l: Node) -> bool: return not (l as Node3D).visible)
	check("...lit at night, out by day", on and off)
	check("a notice board on the square", not root.find_children("*", "NoticeBoard", true, false).is_empty())
	var animals := root.find_children("*", "Enemy", true, false).filter(func(e: Node) -> bool: return e.has_meta("animal"))
	var farms := city.town.buildings.filter(func(b: BuildingPlot) -> bool: return b.kind == BuildingPlot.Kind.FARM).size()
	check("farm animals in the fields (%d for %d farms)" % [animals.size(), farms], farms == 0 or animals.size() >= farms)
	root.queue_free()
	await process_frame
	# a camp's people get on with things
	var camp := load("res://data/world/Sites/bandit_hold.tres") as SitePOIData
	var placed := PlacedPOI.new()
	placed.id = "test/camp_life"
	placed.poi = camp
	var croot := camp.build(placed, null)
	croot.position = Vector3(0, -300, 0)
	get_root().add_child(croot)
	await frames(5)
	var people := croot.find_children("*", "Enemy", true, false).filter(func(e: Node) -> bool: return not e.has_meta("animal"))
	var busy := people.filter(func(e: Node) -> bool: return (e as Enemy).asleep or ((e as Enemy).body != null and (e as Enemy).body.pose == &"sit") or (e as Enemy).wander_radius == 0.0)
	check("in a camp some sleep, some sit by the fire, some keep watch (%d of %d)" % [busy.size(), people.size()], people.size() > 0 and busy.size() >= 2)
	croot.queue_free()
	var farm := load("res://data/world/Sites/farmstead.tres") as SitePOIData
	var fp := PlacedPOI.new()
	fp.id = "test/farm_life"
	fp.poi = farm
	var froot := farm.build(fp, null)
	check("a farmstead keeps animals", froot.find_children("*", "Enemy", true, false).any(func(e: Node) -> bool: return e.has_meta("animal") and (e as Enemy).talk_name == ""))
	froot.free()


# ---------------------------------------------------------------- 1.14.12 speed

func t_speed(wm: WorldManager) -> void:
	print("-- speed")
	var city: PlacedPOI = null
	for t in wm.towns:
		if t.town != null and (city == null or t.town.buildings.size() > city.town.buildings.size()):
			city = t
	var t0 := Time.get_ticks_usec()
	var root := TownBuilder.build(city.poi as TownData, city, wm.map)
	StaticBatch.merge_interior(root)
	StaticBatch.merge(root)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var meshes := root.find_children("*", "MeshInstance3D", true, false).size()
	var multis := root.find_children("Many_*", "MultiMeshInstance3D", true, false)
	check("the biggest town (%d buildings) is built in %.0f ms" % [city.town.buildings.size(), ms], ms < 2500.0)
	check("...and drawn in few pieces (%d meshes, %d multimeshes)" % [meshes, multis.size()], meshes < city.town.buildings.size() * 5 and multis.size() >= 3)
	check("repeated things fade out with distance", multis.all(func(m: Node) -> bool: return (m as GeometryInstance3D).visibility_range_end > 0.0))
	root.free()
	# every kind of site, built within a chunk's budget
	var worst := 0.0
	var worst_kind := ""
	for f in DirAccess.get_files_at("res://data/world/Sites/"):
		if not f.ends_with(".tres"):
			continue
		var d := load("res://data/world/Sites/" + f) as SitePOIData
		var placed := PlacedPOI.new()
		placed.id = "test/speed_" + f
		placed.poi = d
		var t1 := Time.get_ticks_usec()
		var s := d.build(placed, wm.map)
		var sm := (Time.get_ticks_usec() - t1) / 1000.0
		if sm > worst:
			worst = sm
			worst_kind = f
		s.free()
	check("every site builds within budget (slowest %s, %.0f ms)" % [worst_kind, worst], worst < 400.0)


# ---------------------------------------------------------------- 1.14.13 integration

func t_integration(wm: WorldManager, p: CharacterBody3D) -> void:
	print("-- integration")
	# quests and jobs can send you to the new places
	var picks := {}
	for i in 40:
		var at := p.global_position + Vector3(cos(i * 0.7) * 600.0 * (1 + i % 4), 0, sin(i * 0.7) * 600.0 * (1 + i % 4))
		var c := QuestTargets.nearest_poi(wm, at, false)
		if c != null:
			picks[c.poi.get_class() + ":" + String(c.poi.get_script().get_global_name())] = true
	check("jobs and rumors pick the new sites as camps (%s)" % ", ".join(picks.keys()), picks.keys().any(func(k: String) -> bool: return k.ends_with("SitePOIData")))
	# a site's folk are its garrison while it is loaded
	var near: PlacedPOI = null
	for s in wm.pois:
		if s.poi is SitePOIData and s.poi.is_camp() and wm.get_poi_node(s.id) != null:
			near = s
			break
	if near != null:
		wm._garrisons.erase(near.id)
		wm._spawn_garrison(near)
		check("a loaded site's folk count as its garrison (%d)" % wm.get_garrison(near.id).size(), wm.get_garrison(near.id).size() > 0)
	# stable ids: the same place gives the same chests every time
	var site_poi: PlacedPOI = null
	for s in wm.pois:
		if s.poi is SitePOIData and s.poi.get_key() == "site_bandit_camp":
			site_poi = s
			break
	var ids := []
	for k in 2:
		var root := (site_poi.poi as SitePOIData).build(site_poi, wm.map)
		var these := root.find_children("*", "ContainerComponent", true, false).map(func(c: Node) -> String: return (c as ContainerComponent).save_id)
		these.sort()
		ids.append(these)
		root.free()
	check("a site's chests have the same ids every visit (%d)" % ids[0].size(), ids[0] == ids[1] and not ids[0].is_empty() and ids[0].all(func(x: String) -> bool: return x.begins_with(site_poi.id)))
	# the places an old save knows stay where they were when the 1.14 sites are added
	var with_sites := _fresh_plan(wm).filter(func(x: PlacedPOI) -> bool: return not (x.poi is SitePOIData) and not (x.poi is SignpostPOIData))
	var saved := {}
	for pl in wm.map.placements:
		saved[pl] = pl.biome.poi_rules.duplicate()
		pl.biome.poi_rules = pl.biome.poi_rules.filter(func(r: POIRule) -> bool: return r != null and not (r.poi is SitePOIData))
	var without := _fresh_plan(wm).filter(func(x: PlacedPOI) -> bool: return not (x.poi is SignpostPOIData))
	for pl in wm.map.placements:
		pl.biome.poi_rules = saved[pl]
	var moved := 0
	var by_id := {}
	for x in without:
		by_id[x.id] = x.position
	for x in with_sites:
		if not by_id.has(x.id) or (by_id[x.id] as Vector3).distance_to(x.position) > 0.01:
			moved += 1
	check("an old save's camps and dungeons stay where they were (%d of %d moved)" % [moved, with_sites.size()], moved == 0 and with_sites.size() == without.size())
	check("each kind of site has its own map symbol", (load("res://data/world/Sites/fort.tres") as SitePOIData).map_icon == "fort")


# The places of this world planned again on a fresh map, the way a game being loaded plans them
func _fresh_plan(wm: WorldManager) -> Array[PlacedPOI]:
	var m := WorldMap.new(wm.settings, wm.world_seed)
	var towns := SettlementPlanner.plan(m)
	m.set_pads(towns)
	SettlementPlanner.lay_out(m, towns)
	m.set_roads(RoadPlanner.plan(m, towns))
	return POIPlanner.plan(m, towns)


# ---------------------------------------------------------------- 1.14.14 QA

func t_qa(wm: WorldManager) -> void:
	print("-- QA: the whole world")
	var places := wm.pois.filter(func(x: PlacedPOI) -> bool: return not (x.poi is SignpostPOIData))
	# no two places on top of each other
	var grid := {}
	var overlaps := 0
	for x: PlacedPOI in places:
		var c := Vector2i(floori(x.position.x / 200.0), floori(x.position.z / 200.0))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for o: PlacedPOI in grid.get(c + Vector2i(dx, dz), []):
					var need := x.poi.footprint_radius + o.poi.footprint_radius - 0.5
					if Vector2(x.position.x - o.position.x, x.position.z - o.position.z).length() < need:
						overlaps += 1
		if not grid.has(c):
			grid[c] = []
		grid[c].append(x)
	check("no two places overlap (%d places)" % places.size(), overlaps == 0, str(overlaps))
	# nothing buried or hanging: a levelled site's middle sits on the ground
	var buried := 0
	for x: PlacedPOI in places:
		if x.poi is SitePOIData and x.poi.flatten_radius > 0.0:
			if absf(wm.map.get_height(x.position.x, x.position.z) - x.position.y) > 1.2:
				buried += 1
	check("no site is buried or hanging", buried == 0, str(buried))
	# no door blocked: in front of every building there is room to stand
	var blocked := 0
	var doors := 0
	for t in wm.towns:
		if t.town == null:
			continue
		var rects: Array[Rect2] = []
		for b in t.town.buildings:
			rects.append(b.get_local_rect())
		for b in t.town.buildings:
			doors += 1
			var front := Basis(Vector3.UP, b.local_yaw) * Vector3(0, 0, -1)
			var door := b.local_pos + front * (b.size.z * 0.5 + 1.2)
			var q := Vector2(door.x, door.z)
			if rects.any(func(r: Rect2) -> bool: return r.has_point(q)):
				blocked += 1
			elif t.town.dress.any(func(d: Dictionary) -> bool: return String(d["what"]) != "flowers" and Vector2(d["pos"].x, d["pos"].z).distance_to(q) < 0.9):
				blocked += 1
	check("no door is blocked (%d doors)" % doors, blocked == 0, str(blocked))
	# the densest land: everything near the busiest spot built within budget
	var best: PlacedPOI = null
	var best_n := 0
	for x: PlacedPOI in places:
		var n := 0
		for o: PlacedPOI in places:
			if o.position.distance_to(x.position) < 600.0:
				n += 1
		if n > best_n:
			best_n = n
			best = x
	var t0 := Time.get_ticks_msec()
	var built := 0
	for o: PlacedPOI in places:
		if o.position.distance_to(best.position) < 600.0 and not (o.poi is TownData):
			var n := o.poi.build(o, wm.map)
			if n != null:
				built += 1
				n.free()
	var ms := Time.get_ticks_msec() - t0
	check("the densest land (%d places within 600 m) builds in %d ms" % [built, ms], ms < built * 60 + 500)
