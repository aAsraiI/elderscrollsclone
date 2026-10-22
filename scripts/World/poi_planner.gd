class_name POIPlanner
extends RefCounted
## Decides where every point of interest goes. Pure data in, list out: the same world seed and
## settings always give the same list, and nothing is created in the scene here.
##
## For every biome rectangle ("region") and every rule in that biome's Poi Rules, it picks a count,
## then tries random spots (seeded) until each one fits: inside the region, away from the world
## edge, not too steep, not touching another POI. Big things are placed first so they get room.

const GRID_CELL := 200.0
## Meters a POI keeps between its footprint and the edge of a road
const ROAD_GAP := 8.0

# Spatial hash of what has been placed, so spacing checks stay fast with thousands of POIs
class SpaceGrid:
	var cells := {}

	func add(p: PlacedPOI) -> void:
		var key := Vector2i(floori(p.position.x / GRID_CELL), floori(p.position.z / GRID_CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(p)

	# True if a circle at (x, z) with this radius + gap would touch something already placed
	func is_free(x: float, z: float, radius: float, gap: float, max_other_radius: float) -> bool:
		var reach := radius + gap + max_other_radius
		var c0 := Vector2i(floori((x - reach) / GRID_CELL), floori((z - reach) / GRID_CELL))
		var c1 := Vector2i(floori((x + reach) / GRID_CELL), floori((z + reach) / GRID_CELL))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var list: Array = cells.get(Vector2i(cx, cz), [])
				for other: PlacedPOI in list:
					var dx := other.position.x - x
					var dz := other.position.z - z
					var need := radius + other.poi.footprint_radius + gap
					if dx * dx + dz * dz < need * need:
						return false
		return true


## Returns the full POI list for this world. `already` = things placed before (the towns): new
## POIs keep their distance from them, and from the roads.
static func plan(map: WorldMap, already: Array[PlacedPOI] = []) -> Array[PlacedPOI]:
	var out: Array[PlacedPOI] = []
	var settings := map.settings
	if not settings.pois_enabled:
		return out

	var grid := SpaceGrid.new()
	var max_radius := 0.0
	for p in already:
		grid.add(p)
		max_radius = maxf(max_radius, p.poi.footprint_radius)
	for p in map.placements:
		for rule in p.biome.poi_rules:
			if rule != null and rule.poi != null:
				max_radius = maxf(max_radius, rule.poi.footprint_radius)

	for region in map.placements.size():
		var placement := map.placements[region]
		var rect := map.get_placement_rect(region)
		var area_km2 := rect.size.x * rect.size.y / 1.0e6

		# Rules that can actually be placed, biggest footprint first
		var rules: Array[POIRule] = []
		for r in placement.biome.poi_rules:
			if r != null and r.poi != null:
				rules.append(r)
		rules.sort_custom(func(a: POIRule, b: POIRule) -> bool:
			return a.poi.footprint_radius > b.poi.footprint_radius)

		for rule in rules:
			var poi := rule.poi
			var key := "%s|%d,%d|%s" % [placement.biome.get_key(), placement.cell.x, placement.cell.y, poi.get_key()]
			var rng := RandomNumberGenerator.new()
			rng.seed = ("%d|poi|%s" % [map.world_seed, key]).hash()

			var amount := rng.randf_range(minf(rule.count_min, rule.count_max), maxf(rule.count_min, rule.count_max))
			if rule.count_mode == POIRule.CountMode.PER_SQUARE_KM:
				amount *= area_km2
			var count := int(floor(amount))
			if rng.randf() < amount - float(count):
				count += 1

			var margin := rule.border_margin + poi.footprint_radius
			var area := rect.grow(-margin)
			if area.size.x <= 0.0 or area.size.y <= 0.0:
				continue  # the region is too small for this POI

			for k in count:
				var spot := find_spot(map, rng, area, region, rule, grid, max_radius, settings.poi_attempts)
				if spot == Vector3.INF:
					continue  # nowhere fits; that POI is simply skipped
				var placed := PlacedPOI.new()
				placed.poi = poi
				placed.position = spot
				placed.region = region
				placed.id = "r%d_%d/%s/%d" % [placement.cell.x, placement.cell.y, poi.get_key(), k]
				placed.yaw = rng.randf_range(0.0, TAU) if poi.random_rotation else 0.0
				placed.seed_value = ("%d|%s" % [map.world_seed, placed.id]).hash()
				out.append(placed)
				grid.add(placed)
	return out


## Up to `attempts` random tries. Returns the ground point, or Vector3.INF if nothing fit.
## A spot must be free (grid), inside the region all around, away from the world edge and the
## roads, and not too steep.
static func find_spot(map: WorldMap, rng: RandomNumberGenerator, area: Rect2, region: int, rule: POIRule, grid: SpaceGrid, max_radius: float, attempts: int) -> Vector3:
	var s := WorldMap.Sample.new()
	var poi := rule.poi
	var r := poi.footprint_radius
	var settings := map.settings
	var ring := r * 0.7
	for attempt in attempts:
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if not grid.is_free(x, z, r, rule.extra_spacing, max_radius):
			continue
		if map.roads != null and map.roads.distance_to(x, z, r + ROAD_GAP) < r + ROAD_GAP:
			continue
		if map.get_placement_index_at(x, z) != region:
			continue
		if map.get_inside_distance(x, z) < settings.edge_width + r + settings.poi_edge_margin:
			continue
		# stay inside the biome all the way around
		var inside := true
		for q in 4:
			var a := float(q) * PI * 0.5 + 0.4
			if map.get_placement_index_at(x + cos(a) * r, z + sin(a) * r) != region:
				inside = false
				break
		if not inside:
			continue
		# not too steep across the footprint
		map.sample(x, z, s)
		var h0 := s.height
		var worst := 0.0
		for q in 8:
			var a := float(q) * PI * 0.25
			map.sample(x + cos(a) * ring, z + sin(a) * ring, s)
			worst = maxf(worst, absf(s.height - h0))
		if rad_to_deg(atan2(worst, ring)) > poi.max_slope_deg:
			continue
		return Vector3(x, h0, z)
	return Vector3.INF
