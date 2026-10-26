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
	check("site scenes (%d over %d kinds)" % [count, kinds.size()], count >= 40 and kinds.size() >= 25 and count >= kinds.size() + 14)
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
			var props := site.find_children("*", "InteriorProp", true, false).size()
			var enemies := site.find_children("*", "Enemy", true, false).size()
			var doors := site.find_children("*", "DungeonDoor", true, false).size()
			if props < 2:
				bad.append("%s v%d: %d props" % [f, v, props])
			var can_live := d.occupants != null and not d.occupants.roll(RandomNumberGenerator.new(), 1).is_empty()
			if can_live and enemies == 0 and not f.begins_with("hunters") and not f.begins_with("lighthouse") and not f.begins_with("mine"):
				bad.append("%s v%d: nobody lives there" % [f, v])
			if d.dungeon != null and not site.links().is_empty() and doors != 1:
				bad.append("%s v%d: no way down" % [f, v])
			if site.get_node_or_null("MergedRoom") == null:
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
