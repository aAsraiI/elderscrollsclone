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
			if site.get_node_or_null("MergedRoom") == null and site.find_children("*", "MeshInstance3D", true, false).size() > 12:
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
	check("water places stand by the water (%d of %d)" % [wet, wet_n], wet_n == 0 or wet >= wet_n * 0.6)
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
		var calm := before.find_children("*", "Enemy", true, false).size()
		before.free()
		SiteChanges._new_owners(wm, farm, 5, RandomNumberGenerator.new(), "taken")
		var after := (farm.poi as SitePOIData).build(farm, map)
		var now := after.find_children("*", "Enemy", true, false).size()
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
