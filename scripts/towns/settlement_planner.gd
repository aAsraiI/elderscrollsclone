class_name SettlementPlanner
extends RefCounted
## Decides where the towns go, before any other point of interest (towns need the most room).
## Every biome gets one city, in its biggest region; every region of a biome gets a few towns and
## villages (WorldSettings > Towns and roads). The templates come from TownData resources; a
## template's Allowed Biomes limits where it may appear. Each placed town gets a name and a full
## layout (TownLayout) right away, so roads, NPCs and quests can use it before it is ever built.

## Extra tries per town compared to an ordinary POI: towns are big and must not be skipped
const ATTEMPT_FACTOR := 6


static func plan(map: WorldMap, grid: POIPlanner.SpaceGrid = null) -> Array[PlacedPOI]:
	var out: Array[PlacedPOI] = []
	var settings := map.settings
	if not settings.pois_enabled or not settings.towns_enabled:
		return out
	var templates := settings.get_town_templates()
	if templates.is_empty():
		return out
	if grid == null:
		grid = POIPlanner.SpaceGrid.new()
	var max_radius := 0.0
	for t in templates:
		max_radius = maxf(max_radius, t.footprint_radius)

	# The biggest region of each biome holds its city
	var city_region := {}  # biome key -> region index
	var weight := func(region: int) -> float:
		# the main island's regions come first: a land's city (and its named towns) stand there
		return map.get_region_area(region) * (1.0 if settings.island_of(map.placements[region]) == 0 else 0.001)
	for region in map.placements.size():
		var key := map.placements[region].biome.get_key()
		if not city_region.has(key) or weight.call(region) > weight.call(city_region[key]):
			city_region[key] = region

	for region in map.placements.size():
		var placement := map.placements[region]
		var biome := placement.biome
		var rect := map.get_placement_rect(region)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|towns|%s|%d,%d" % [map.world_seed, biome.get_key(), placement.cell.x, placement.cell.y]).hash()

		var wanted: Array[TownData] = []
		var wanted_named: Array[Dictionary] = []  # the NamedSettlements entry of each, or {}
		# A biome with named settlements gets exactly those, once (in its biggest region)
		var named: Array = NamedSettlements.for_biome(biome.get_key()) if settings.named_settlements and city_region.get(biome.get_key(), -1) == region else []
		if not named.is_empty():
			for entry: Dictionary in named:
				var nt := _pick_kind(templates, biome, NamedSettlements.town_kind(entry), rng)
				if nt != null:
					wanted.append(nt)
					wanted_named.append(entry)
		elif settings.named_settlements and not NamedSettlements.for_biome(biome.get_key()).is_empty() and settings.island_of(placement) == 0:
			pass  # a smaller pocket of a land whose named towns stand in its main region: no others
		else:
			if settings.city_per_biome and city_region.get(biome.get_key(), -1) == region:
				var city := _pick(templates, biome, true, rng)
				if city != null:
					wanted.append(city)
			var count := rng.randi_range(mini(settings.towns_per_region_min, settings.towns_per_region_max), maxi(settings.towns_per_region_min, settings.towns_per_region_max))
			for i in count:
				var t := _pick(templates, biome, false, rng)
				if t != null:
					wanted.append(t)
			for i in wanted.size():
				wanted_named.append({})

		var counters := {}
		for wi in wanted.size():
			var data := wanted[wi]
			var entry := wanted_named[wi]
			var rule := POIRule.new()
			rule.poi = data
			rule.extra_spacing = settings.town_spacing
			rule.border_margin = 80.0
			var area := rect.grow(-(rule.border_margin + data.footprint_radius))
			if area.size.x <= 0.0 or area.size.y <= 0.0:
				continue
			var spot := POIPlanner.find_spot(map, rng, area, region, rule, grid, max_radius, settings.poi_attempts * ATTEMPT_FACTOR)
			if spot == Vector3.INF and not entry.is_empty():
				# A named town must exist: try again with less room kept around it
				rule.extra_spacing = settings.town_spacing * 0.4
				spot = POIPlanner.find_spot(map, rng, area, region, rule, grid, max_radius, settings.poi_attempts * ATTEMPT_FACTOR * 2)
			if spot == Vector3.INF:
				push_warning("Towns: no room for %s in %s" % [entry.get("name", "a " + data.display_name), biome.display_name])
				continue
			var k: int = counters.get(data.get_key(), 0)
			counters[data.get_key()] = k + 1
			var placed := PlacedPOI.new()
			placed.poi = data
			placed.position = spot
			placed.region = region
			placed.id = "r%d_%d/%s/%d" % [placement.cell.x, placement.cell.y, data.get_key(), k]
			# Towns line up with the compass (streets east-west), turned a little for character
			placed.yaw = rng.randf_range(-0.35, 0.35)
			placed.seed_value = ("%d|%s" % [map.world_seed, placed.id]).hash()
			placed.named = entry
			out.append(placed)
			grid.add(placed)
	_ports(map, out, grid, templates, max_radius)
	return out


## Port towns per island (Alpha 1.21): the main island two, every other island one
const PORTS_MAIN := 2


# Every island gets its ports: the towns nearest the sea become ports (a long pier and a ship to
# the other ports, SeaPassage); an island without a town by the sea gets a new port village on its
# shore. Regions layouts only.
static func _ports(map: WorldMap, out: Array[PlacedPOI], grid: POIPlanner.SpaceGrid, templates: Array[TownData], max_radius: float) -> void:
	var settings := map.settings
	if not settings.is_regions() or not settings.water_enabled:
		return
	for isle in settings.islands.size() + 1:
		if isle > 0 and (settings.islands[isle - 1] == null or not settings.islands[isle - 1].port):
			continue
		var want := PORTS_MAIN if isle == 0 else 1
		# coastal towns already there, nearest the sea first
		var coastal: Array[PlacedPOI] = []
		for t in out:
			if t.region >= 0 and settings.island_of(map.placements[t.region]) == isle and map.get_inside_distance(t.position.x, t.position.z) < (t.poi as TownData).flatten_radius * 2.4:
				coastal.append(t)
		coastal.sort_custom(func(a: PlacedPOI, b: PlacedPOI) -> bool:
			return map.get_inside_distance(a.position.x, a.position.z) < map.get_inside_distance(b.position.x, b.position.z))
		for t in coastal.slice(0, want):
			t.extra["port"] = true
		var missing := want - mini(coastal.size(), want)
		# a new port village on the shore for the rest
		var regions: Array[int] = []
		for r in map.placements.size():
			if settings.island_of(map.placements[r]) == isle and map.get_region_area(r) > 0.0:
				regions.append(r)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|ports|%d" % [map.world_seed, isle]).hash()
		var made := 0
		var tries := 0
		while made < missing and tries < 600 and not regions.is_empty():
			tries += 1
			var region: int = regions[rng.randi() % regions.size()]
			var biome := map.placements[region].biome
			var data := _pick(templates, biome, false, rng)
			if data == null:
				continue
			var rect := map.get_placement_rect(region)
			var x := rng.randf_range(rect.position.x, rect.end.x)
			var z := rng.randf_range(rect.position.y, rect.end.y)
			var inside := map.get_inside_distance(x, z)
			if inside < data.footprint_radius + 20.0 or inside > data.flatten_radius * 2.2:
				continue  # a port stands just back from the shore
			var rule := POIRule.new()
			rule.poi = data
			rule.extra_spacing = settings.town_spacing * 0.5
			rule.border_margin = 20.0
			var spot := POIPlanner.find_spot(map, rng, Rect2(x - 40.0, z - 40.0, 80.0, 80.0), region, rule, grid, max_radius, 8)
			if spot == Vector3.INF or map.get_inside_distance(spot.x, spot.z) < data.footprint_radius + 15.0:
				continue
			var placed := PlacedPOI.new()
			placed.poi = data
			placed.position = spot
			placed.region = region
			var cell := map.placements[region].cell
			placed.id = "r%d_%d/port/%d" % [cell.x, cell.y, made]
			placed.yaw = rng.randf_range(-0.35, 0.35)
			placed.seed_value = ("%d|%s" % [map.world_seed, placed.id]).hash()
			placed.extra["port"] = true
			out.append(placed)
			grid.add(placed)
			made += 1
		if made < missing:
			push_warning("Towns: no room for a port on island %d" % isle)


## Builds the layout of every town. Called after the ground under the towns has been leveled, so
## buildings get their real height.
static func lay_out(map: WorldMap, towns: Array[PlacedPOI]) -> void:
	var used_names := {}
	for placed in towns:
		var name_rng := RandomNumberGenerator.new()
		name_rng.seed = placed.seed_value ^ 0x4A3E
		var town_name := String(placed.named.get("name", ""))
		if town_name == "":
			town_name = NameGen.town(name_rng)
			for tries in 20:
				if not used_names.has(town_name):
					break
				town_name = NameGen.town(name_rng)
		used_names[town_name] = true
		placed.town = TownLayout.generate(placed.poi as TownData, placed, town_name, map)


## A template of exactly this kind (named settlements); falls back to any template of the kind
## when none allows the biome
static func _pick_kind(templates: Array[TownData], biome: BiomeData, kind: TownData.Kind, rng: RandomNumberGenerator) -> TownData:
	var options: Array[TownData] = []
	var fallback: Array[TownData] = []
	for t in templates:
		if t.kind != kind or t.weight <= 0.0:
			continue
		fallback.append(t)
		if t.allows_biome(biome):
			options.append(t)
	if options.is_empty():
		options = fallback
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]


static func _pick(templates: Array[TownData], biome: BiomeData, city: bool, rng: RandomNumberGenerator) -> TownData:
	var options: Array[TownData] = []
	var total := 0.0
	for t in templates:
		if (t.kind == TownData.Kind.CITY) != city or t.weight <= 0.0 or not t.allows_biome(biome):
			continue
		options.append(t)
		total += t.weight
	if options.is_empty():
		return null
	var roll := rng.randf() * total
	for t in options:
		roll -= t.weight
		if roll <= 0.0:
			return t
	return options[options.size() - 1]
