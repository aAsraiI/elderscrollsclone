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

	# True if no place of this same kind stands within `dist` of (x, z)
	func far_from_same(x: float, z: float, poi: POIData, dist: float) -> bool:
		var c0 := Vector2i(floori((x - dist) / GRID_CELL), floori((z - dist) / GRID_CELL))
		var c1 := Vector2i(floori((x + dist) / GRID_CELL), floori((z + dist) / GRID_CELL))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				for other: PlacedPOI in cells.get(Vector2i(cx, cz), []):
					if other.poi == poi and Vector2(other.position.x - x, other.position.z - z).length() < dist:
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

	for sites_pass in [false, true]:  # the older kinds of place everywhere first, then the 1.14 sites
		for region in map.placements.size():
			var placement := map.placements[region]
			var rect := map.get_placement_rect(region)
			var area_km2 := rect.size.x * rect.size.y / 1.0e6

			# Rules that can actually be placed, biggest footprint first
			var rules: Array[POIRule] = []
			for r in placement.biome.poi_rules:
				if r != null and r.poi != null:
					rules.append(r)
			# the places a world had before Alpha 1.14 first (an old save finds them where they were), then
			# the 1.14 sites; biggest first within each
			rules.sort_custom(func(a: POIRule, b: POIRule) -> bool:
				var sa := a.poi is SitePOIData
				var sb := b.poi is SitePOIData
				if sa != sb:
					return sb
				return a.poi.footprint_radius > b.poi.footprint_radius)

			for rule in rules:
				if (rule.poi is SitePOIData) != sites_pass:
					continue
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
					var spot := find_spot(map, rng, area, region, rule, grid, max_radius, settings.poi_attempts if poi.footprint_radius >= 8.0 else maxi(settings.poi_attempts / 3, 6))  # small things: fewer tries
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
	_lay_paths(map, out)
	_signposts(map, out, already)
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
	var best := Vector3.INF
	var best_score := -INF
	var found := 0
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
		if map.is_under_water(h0 - 1.5):
			continue  # nothing is built at or under the water line
		var worst := 0.0
		for q in 8:
			var a := float(q) * PI * 0.25
			map.sample(x + cos(a) * ring, z + sin(a) * ring, s)
			worst = maxf(worst, absf(s.height - h0))
			if map.is_under_water(s.height - 0.5):
				worst = INF  # part of it would be in the water
		if rad_to_deg(atan2(worst, ring)) > poi.max_slope_deg:
			continue
		if poi.min_same_distance > 0.0 and not grid.far_from_same(x, z, poi, poi.min_same_distance):
			continue
		if poi.prefer == "any" or poi.prefer == "":
			return Vector3(x, h0, z)
		# a place with a liking: keep the best of a few spots that fit
		var score := _score(map, x, z, h0, poi.prefer)
		if score > best_score:
			best_score = score
			best = Vector3(x, h0, z)
		found += 1
		if found >= 6:
			break
	return best


# How well a spot suits what a place likes: hilltops stand above the land round them, hollows below
# it, a water place has water close by (but is dry itself), a road place stands near a road
static func _score(map: WorldMap, x: float, z: float, h0: float, prefer: String) -> float:
	var s := WorldMap.Sample.new()
	match prefer:
		"high", "low":
			var around := 0.0
			for q in 8:
				var a := float(q) * PI * 0.25
				map.sample(x + cos(a) * 90.0, z + sin(a) * 90.0, s)
				around += s.height
			var rise := h0 - around / 8.0
			return rise if prefer == "high" else -rise
		"water":
			var wet := 0.0
			for d in [25.0, 45.0, 70.0]:
				for q in 8:
					var a := float(q) * PI * 0.25
					map.sample(x + cos(a) * d, z + sin(a) * d, s)
					if map.is_under_water(s.height):
						wet += 100.0 / d
			return wet
		"road":
			if map.roads == null:
				return 0.0
			var d := map.roads.distance_to(x, z, 300.0)
			return -d if d != INF else -300.0
	return 0.0


# A dirt path from each place that asks for one to the nearest road (if one is near enough)
static func _lay_paths(map: WorldMap, placed: Array[PlacedPOI]) -> void:
	if map.roads == null:
		return
	var dirt := Color(0.40, 0.34, 0.25)
	for p in placed:
		var reach := p.poi.path_to_road
		if reach <= 0.0:
			continue
		var to := map.roads.nearest_point(p.position.x, p.position.z, reach + p.poi.footprint_radius)
		if to == Vector3.INF:
			continue
		var from := p.position
		var dir := Vector3(to.x - from.x, 0, to.z - from.z)
		var length := dir.length()
		if length < p.poi.footprint_radius + 6.0:
			continue
		dir /= length
		var start := from + dir * (p.poi.footprint_radius * 0.6)
		var pts := PackedVector3Array()
		var steps := maxi(int((length - p.poi.footprint_radius * 0.6) / 12.0), 1)
		for i in steps + 1:
			var t := float(i) / steps
			var q := start.lerp(to, t)
			q.y = to.y if i == steps else map.get_height(q.x, q.z)
			pts.append(q)
		map.roads.add_polyline(pts, 1.1, dirt, true, p.id, "")


# Signposts where roads meet outside the towns (an arm for each way, naming the town it leads to and
# how far), and a milestone every MILESTONE_EVERY meters along the longer roads
const MILESTONE_EVERY := 2000.0

static func _signposts(map: WorldMap, out: Array[PlacedPOI], towns: Array[PlacedPOI]) -> void:
	if map.roads == null:
		return
	var names := {}
	for t in towns:
		if t.town != null:
			names[t.id] = t.town.display_name
	var roads := map.roads.get_roads()
	var post := SignpostPOIData.new()
	var stone := SignpostPOIData.new()
	stone.id = &"milestone"
	stone.display_name = "Milestone"
	var made: Array[Vector3] = []
	var n := 0
	for road in roads:
		var pts: PackedVector3Array = road["points"]
		for e in [pts[0], pts[pts.size() - 1]]:
			if towns.any(func(t: PlacedPOI) -> bool: return Vector2(t.position.x - e.x, t.position.z - e.z).length() < 170.0):
				continue
			if made.any(func(m: Vector3) -> bool: return m.distance_to(e) < 40.0):
				continue
			var arms := _arms_at(roads, e, names)
			if arms.size() < 2:
				continue
			made.append(e)
			var first: float = arms[0][0]
			var side := Vector3(cos(first), 0, -sin(first)) * 4.5
			var placed := PlacedPOI.new()
			placed.poi = post
			placed.position = e + side
			placed.position.y = map.get_height(placed.position.x, placed.position.z)
			placed.id = "signpost/%d" % n
			placed.seed_value = ("%d|%s" % [map.world_seed, placed.id]).hash()
			placed.named = {"arms": arms}
			out.append(placed)
			n += 1
		# milestones along the way
		var from_name: String = names.get(String(road["from"]), "")
		var to_name: String = names.get(String(road["to"]), "")
		if from_name == "" or to_name == "":
			continue
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		var walked := 0.0
		var next := MILESTONE_EVERY
		for i in pts.size() - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			while walked + seg >= next and total - next > MILESTONE_EVERY * 0.5:
				var at := pts[i].lerp(pts[i + 1], (next - walked) / seg)
				var dir := (pts[i + 1] - pts[i]).normalized()
				var placed := PlacedPOI.new()
				placed.poi = stone
				placed.position = at + Vector3(-dir.z, 0, dir.x) * (float(road["half_width"]) + 1.5)
				placed.position.y = map.get_height(placed.position.x, placed.position.z)
				placed.yaw = atan2(-dir.x, -dir.z)
				placed.id = "milestone/%d" % n
				placed.seed_value = n
				placed.named = {"milestone": "%s  %.1f km\n%s  %.1f km" % [from_name, next / 1000.0, to_name, (total - next) / 1000.0]}
				out.append(placed)
				n += 1
				next += MILESTONE_EVERY
			walked += seg


# The ways out of a meeting of roads: for every road passing within reach, an arm each way it goes to
# a town ([yaw, "Town  2.3 km"]), the nearest way to each town only
static func _arms_at(roads: Array[Dictionary], at: Vector3, names: Dictionary) -> Array:
	var best := {}  # town name -> [yaw, km]
	for road in roads:
		var pts: PackedVector3Array = road["points"]
		var bi := -1
		var bd := INF
		for i in pts.size():
			var d := Vector2(pts[i].x - at.x, pts[i].z - at.z).length()
			if d < bd:
				bd = d
				bi = i
		if bd > 14.0:
			continue
		for dir in [-1, 1]:
			var j: int = bi + dir
			if j < 0 or j >= pts.size():
				continue
			var name: String = names.get(String(road["to"] if dir > 0 else road["from"]), "")
			if name == "":
				continue
			var length := 0.0
			var k := bi
			while k + dir >= 0 and k + dir < pts.size():
				length += pts[k].distance_to(pts[k + dir])
				k += dir
			var v := pts[j] - pts[bi]
			if not best.has(name) or float(best[name][1]) > length:
				best[name] = [atan2(-v.x, -v.z), length]
	var out: Array = []
	for name: String in best:
		out.append([best[name][0], "%s  %.1f km" % [name, float(best[name][1]) / 1000.0]])
	return out
