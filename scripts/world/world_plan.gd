class_name WorldPlan
extends RefCounted
## The steps of planning a world that come before and after the towns and roads (Alpha 1.21):
## the water first (rivers and lakes are carved before anything is placed, so towns, roads and
## places keep out of them), and the bridges last (one wherever a road crosses running water).
## WorldManager and tools/world_preview.gd both plan a world this way.

static var _bridge_data: BridgePOIData


## Works out the rivers, streams and lakes and carves them into the map
static func water(map: WorldMap) -> void:
	if map.settings.is_regions() and map.settings.rivers_enabled:
		var t0 := Time.get_ticks_msec()
		map.set_rivers(RiverPlanner.plan(map))
		print("World: %d rivers and streams (%.0f km), %d lakes (%d ms)" % [map.rivers.river_count(), map.rivers.total_length() / 1000.0,
			map.rivers.lake_count(), Time.get_ticks_msec() - t0])


## The footprint of every town building, for WorldMap.set_foundations (the ground is leveled to
## each building's floor)
static func foundations(towns: Array[PlacedPOI]) -> Array:
	var out: Array = []
	for t in towns:
		if t.town == null:
			continue
		for b in t.town.buildings:
			out.append({"pos": b.world_pos, "half": Vector2(b.size.x, b.size.z) * 0.5 + Vector2(0.6, 0.6), "yaw": b.world_yaw})
	return out


## Adds a bridge to `pois` for every place a road crosses running water
static func bridges(map: WorldMap, pois: Array[PlacedPOI]) -> void:
	if map.roads == null or map.roads.crossings.is_empty():
		return
	if _bridge_data == null:
		_bridge_data = BridgePOIData.new()
	var n := 0
	for c: Dictionary in map.roads.crossings:
		var a: Vector3 = c["a"]
		var b: Vector3 = c["b"]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.5:
			continue
		var mid := (a + b) * 0.5
		var twice := false
		for q in pois:
			if q.poi == _bridge_data and q.position.distance_to(mid) < 12.0:
				twice = true  # two roads sharing one crossing
				break
		if twice:
			continue
		var p := PlacedPOI.new()
		p.poi = _bridge_data
		p.position = (a + b) * 0.5
		p.yaw = atan2(dir.x, dir.z)
		p.id = "bridge/%d_%d" % [roundi(p.position.x), roundi(p.position.z)]
		p.seed_value = p.id.hash()
		p.region = map.get_placement_index_at(p.position.x, p.position.z)
		var span := float(c["span"])
		p.extra = {"span": span, "width": map.settings.road_width + 1.0, "water": float(c["water"]),
			"stone": span >= BridgePOIData.STONE_FROM * 2.0}
		pois.append(p)
		n += 1
	print("World: %d bridges" % n)
