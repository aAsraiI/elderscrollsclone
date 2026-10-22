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
	for region in map.placements.size():
		var key := map.placements[region].biome.get_key()
		var area := map.get_placement_rect(region).get_area()
		if not city_region.has(key) or area > map.get_placement_rect(city_region[key]).get_area():
			city_region[key] = region

	for region in map.placements.size():
		var placement := map.placements[region]
		var biome := placement.biome
		var rect := map.get_placement_rect(region)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|towns|%s|%d,%d" % [map.world_seed, biome.get_key(), placement.cell.x, placement.cell.y]).hash()

		var wanted: Array[TownData] = []
		if settings.city_per_biome and city_region.get(biome.get_key(), -1) == region:
			var city := _pick(templates, biome, true, rng)
			if city != null:
				wanted.append(city)
		var count := rng.randi_range(mini(settings.towns_per_region_min, settings.towns_per_region_max), maxi(settings.towns_per_region_min, settings.towns_per_region_max))
		for i in count:
			var t := _pick(templates, biome, false, rng)
			if t != null:
				wanted.append(t)

		var counters := {}
		for data in wanted:
			var rule := POIRule.new()
			rule.poi = data
			rule.extra_spacing = settings.town_spacing
			rule.border_margin = 80.0
			var area := rect.grow(-(rule.border_margin + data.footprint_radius))
			if area.size.x <= 0.0 or area.size.y <= 0.0:
				continue
			var spot := POIPlanner.find_spot(map, rng, area, region, rule, grid, max_radius, settings.poi_attempts * ATTEMPT_FACTOR)
			if spot == Vector3.INF:
				push_warning("Towns: no room for a %s in %s" % [data.display_name, biome.display_name])
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
			out.append(placed)
			grid.add(placed)
	return out


## Builds the layout of every town. Called after the ground under the towns has been leveled, so
## buildings get their real height.
static func lay_out(map: WorldMap, towns: Array[PlacedPOI]) -> void:
	var used_names := {}
	for placed in towns:
		var name_rng := RandomNumberGenerator.new()
		name_rng.seed = placed.seed_value ^ 0x4A3E
		var town_name := NameGen.town(name_rng)
		for tries in 20:
			if not used_names.has(town_name):
				break
			town_name = NameGen.town(name_rng)
		used_names[town_name] = true
		placed.town = TownLayout.generate(placed.poi as TownData, placed, town_name, map)


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
