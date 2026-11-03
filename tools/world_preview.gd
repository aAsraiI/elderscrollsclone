extends SceneTree
## Draws the whole world from above into a PNG and counts what is in it: biome colours with hill
## shading, the sea, lakes and rivers, roads, towns and places, and the biome borders. Prints the
## planning times and a census of places by kind and by biome.
##   godot --headless --path . -s res://tools/world_preview.gd -- out.png [settings.tres] [size] [seed] [noplaces] [at=x,z,meters]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://world_preview.png"
	var path := args[1] if args.size() > 1 and args[1] != "" else "res://data/world/realm_world.tres"
	var px := int(args[2]) if args.size() > 2 else 1024
	var settings := load(path) as WorldSettings
	var seed_value := int(args[3]) if args.size() > 3 and args[3] != "" else settings.world_seed
	var places := not args.has("noplaces")
	var t0 := Time.get_ticks_msec()
	var map := WorldMap.new(settings, seed_value)
	print("map: %d ms" % (Time.get_ticks_msec() - t0))
	var towns: Array[PlacedPOI] = []
	var pois: Array[PlacedPOI] = []
	if places:
		TownLayout.compact = true
		var t1 := Time.get_ticks_msec()
		WorldPlan.water(map)
		var t2 := Time.get_ticks_msec()
		towns = SettlementPlanner.plan(map)
		map.set_pads(towns)
		SettlementPlanner.lay_out(map, towns)
		map.set_foundations(WorldPlan.foundations(towns))
		var t3 := Time.get_ticks_msec()
		map.set_roads(RoadPlanner.plan(map, towns))
		var t4 := Time.get_ticks_msec()
		pois = towns.duplicate()
		pois.append_array(POIPlanner.plan(map, towns))
		map.set_pads(pois)
		WorldPlan.bridges(map, pois)
		var t5 := Time.get_ticks_msec()
		print("water %d ms, towns %d ms, roads %d ms, places %d ms" % [t2 - t1, t3 - t2, t4 - t3, t5 - t4])
		_census(map, pois)
	var img := _draw(map, px)
	if places:
		_draw_places(map, img, pois)
	img.save_png(out)
	print("saved ", out)
	quit()


func _draw(map: WorldMap, px: int) -> Image:
	var b := _view(map)
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var step := maxf(b.size.x, b.size.y) / float(px)
	var rows: Array = []
	rows.resize(px)
	var task := WorkerThreadPool.add_group_task(func(j: int) -> void:
		var s := WorldMap.Sample.new()
		var hs := PackedFloat32Array()
		var cols := PackedColorArray()
		var own := PackedInt32Array()
		var water := PackedFloat32Array()
		for i in px:
			var x := b.position.x + (float(i) + 0.5) * step
			var z := b.position.y + (float(j) + 0.5) * step
			map.sample(x, z, s)
			hs.append(s.height)
			cols.append(s.map_color)
			own.append(map.get_placement_index_at(x, z))
			water.append(map.get_water_level(x, z))
		rows[j] = [hs, cols, own, water], px, -1, true, "preview")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for j in px:
		var hs: PackedFloat32Array = rows[j][0]
		var cols: PackedColorArray = rows[j][1]
		var own: PackedInt32Array = rows[j][2]
		var water: PackedFloat32Array = rows[j][3]
		for i in px:
			var h := hs[i]
			var hn: float = (rows[j - 1][0] as PackedFloat32Array)[i] if j > 0 else h
			var hw: float = hs[i - 1] if i > 0 else h
			var shade := clampf(1.0 + ((h - hw) + (h - hn)) / step * 0.9, 0.45, 1.5)
			var c := cols[i] * shade
			c = c.lerp(Color(1, 1, 1), clampf((h - 60.0) / 300.0, 0.0, 0.35))
			if water[i] > h:
				var depth := water[i] - h
				c = Color(0.18, 0.36, 0.55).lerp(Color(0.05, 0.12, 0.28), clampf(depth / 25.0, 0.0, 1.0))
			var border := (i > 0 and own[i - 1] != own[i]) or (j > 0 and (rows[j - 1][2] as PackedInt32Array)[i] != own[i])
			if border:
				c = c.darkened(0.55)
			c.a = 1.0
			img.set_pixel(i, j, c)
	return img


func _draw_places(map: WorldMap, img: Image, pois: Array[PlacedPOI]) -> void:
	var b := _view(map)
	var px := img.get_width()
	var step := maxf(b.size.x, b.size.y) / float(px)
	if map.roads != null:
		for road in map.roads.get_roads():
			for p: Vector3 in road["points"]:
				_dot(img, Vector2i(int((p.x - b.position.x) / step), int((p.z - b.position.y) / step)), 0, Color(0.35, 0.22, 0.1))
	for p in pois:
		var at := Vector2i(int((p.position.x - b.position.x) / step), int((p.position.z - b.position.y) / step))
		if p.town != null:
			_dot(img, at, 4, Color(0.9, 0.1, 0.1))
		elif p.poi is BridgePOIData:
			_dot(img, at, 1, Color(1, 1, 1))
		elif p.poi is DungeonEntrancePOIData:
			_dot(img, at, 1, Color(0.1, 0.1, 0.1))
		else:
			_dot(img, at, 1, Color(1.0, 0.85, 0.2))


func _dot(img: Image, at: Vector2i, r: int, c: Color) -> void:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := at + Vector2i(dx, dz)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				img.set_pixelv(q, c)


func _census(map: WorldMap, pois: Array[PlacedPOI]) -> void:
	var kinds := {}
	var per_biome := {}
	for p in pois:
		var k := p.poi.get_key().get_file().get_basename()
		if p.poi is SitePOIData:
			k = "site:" + k
		kinds[k] = int(kinds.get(k, 0)) + 1
		var bk := map.placements[p.region].biome.get_key() if p.region >= 0 and p.region < map.placements.size() else "?"
		per_biome[bk] = int(per_biome.get(bk, 0)) + 1
	var names := kinds.keys()
	names.sort_custom(func(a, b2): return kinds[a] > kinds[b2])
	var line := PackedStringArray()
	for n in names:
		line.append("%s %d" % [n, kinds[n]])
	print("places: %d  |  %s" % [pois.size(), ", ".join(line)])
	print("by biome: ", per_biome)
	for p in pois:
		if bool(p.extra.get("port", false)):
			print("port: %s at %d, %d" % [p.town.display_name if p.town != null else p.id, roundi(p.position.x), roundi(p.position.z)])
	if map.rivers != null:
		print("rivers: %d, lakes: %d, river length %.1f km" % [map.rivers.river_count(), map.rivers.lake_count(), map.rivers.total_length() / 1000.0])


# The whole world, or the square given as "at=x,z,size" (meters) on the command line
func _view(map: WorldMap) -> Rect2:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("at="):
			var v := a.substr(3).split_floats(",")
			return Rect2(v[0] - v[2] * 0.5, v[1] - v[2] * 0.5, v[2], v[2])
	return map.get_bounds()
