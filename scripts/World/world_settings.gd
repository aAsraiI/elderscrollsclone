class_name WorldSettings
extends Resource
## Everything about how the world is laid out and generated. One of these per game.
## Create: FileSystem > right-click > New Resource > WorldSettings, then drag it into the
## "Settings" field of the WorldManager node. With no settings assigned, WorldManager makes a
## small default world so you can test right away.

## The world is a pure function of this number: same seed + same settings = same world.
## Saves store the seed, so every save gets this world unless the player picks another seed.
@export var world_seed: int = 1337

@export_group("Layout")
## Size of one layout cell in meters. Biome positions and sizes are measured in cells.
@export_range(50.0, 5000.0, 10.0, "or_greater") var cell_size := 500.0
## The biome rectangles that make up the world. Order does not matter.
@export var placements: Array[BiomePlacement] = []
## Which placement (counting valid ones from 0) the player starts in the middle of
@export var spawn_placement := 0

@export_group("Biome borders")
## How far noise pushes biome borders around, in meters. 0 = perfectly straight borders.
@export_range(0.0, 2000.0, 1.0, "or_greater") var border_warp_strength := 140.0
## Size of the wiggles in meters. Small = jagged, large = long smooth curves.
@export_range(20.0, 5000.0, 1.0, "or_greater") var border_warp_scale := 450.0

@export_group("World edge")
## Width of the cliff ring around the world, in meters
@export_range(10.0, 1000.0, 1.0, "or_greater") var edge_width := 160.0
## How high the cliffs rise above the ground (meters). Keep it steep enough to stop walking.
@export_range(10.0, 1000.0, 1.0, "or_greater") var edge_height := 170.0

@export_group("Terrain streaming")
## Width of one terrain chunk in meters
@export_range(16.0, 256.0, 1.0) var chunk_size := 64.0
## Distance between terrain vertices in meters. Smaller = smoother but slower.
@export_range(0.5, 8.0, 0.25) var vertex_spacing := 2.0
## Chunks drawn around the player (radius). View distance = this x chunk_size.
@export_range(2, 40) var view_distance_chunks := 10
## Chunks built instantly around the player at start (radius), so there is ground to stand on
@export_range(1, 6) var spawn_radius_chunks := 2
## Finished chunks added to the scene per frame (keeps the frame rate steady)
@export_range(1, 8) var max_chunks_per_frame := 2
## Chunks built on background threads at the same time
@export_range(1, 16) var max_build_tasks := 6

@export_group("Points of interest")
## Turn off to get bare terrain
@export var pois_enabled := true
## How far (m) POIs stay away from the cliff ring, on top of their own size
@export_range(0.0, 1000.0, 1.0, "or_greater") var poi_edge_margin := 80.0
## Random tries per POI before it is skipped (more = fewer skipped in crowded or steep biomes)
@export_range(5, 200) var poi_attempts := 40

@export_group("Water")
## Lakes and coasts: everything below sea_level is under water (a water surface is drawn there,
## nothing is built there, and roads go around). There is no swimming yet: you walk on the bottom.
@export var water_enabled := false
@export var sea_level := 0.0

@export_group("Towns and roads")
## Villages, towns and cities, joined by roads
@export var towns_enabled := true
## The kinds of settlement to build. Empty = every TownData in scripts/Resources/World/Towns/
@export var town_templates: Array[TownData] = []
## Towns and villages in every biome region (on top of the city)
@export_range(0, 8) var towns_per_region_min := 2
@export_range(0, 8) var towns_per_region_max := 3
## One city in every biome, in its biggest region
@export var city_per_biome := true
## Build the named settlements of the realm (NamedSettlements: Kingsreach, Merewater...), each
## with its lord's seat, instead of random towns. Biomes with no named settlements keep the
## random ones.
@export var named_settlements := false
## Empty ground (m) kept between two settlements, on top of their own size
@export_range(0.0, 2000.0, 10.0, "or_greater") var town_spacing := 260.0
@export var roads_enabled := true
## Meters per cell of the grid roads are planned on. Smaller = roads hug the land more closely,
## but the world takes longer to plan.
@export_range(8.0, 64.0, 1.0) var road_grid := 24.0
@export_range(2.0, 12.0, 0.5) var road_width := 5.0
## Steepest a road may climb (0.2 = 20%). Where the land is steeper the road cuts into it.
@export_range(0.05, 0.6, 0.01) var road_max_grade := 0.2
## Travellers, merchants and road wardens on the roads near the player
@export var road_traffic := true
## Start a new game at the gate of the town nearest the spawn point
@export var start_in_town := true

@export_group("Debug")
@export var debug_map_enabled := true
## Pixels along the longer side of the debug map (press M in game)
@export_range(64, 1024, 16) var debug_map_resolution := 256


const DEFAULT_PATH := "res://scripts/Resources/World/default_world.tres"
const TOWNS_DIR := "res://scripts/Resources/World/Towns"

static var _found_towns: Array[TownData] = []
static var _towns_scanned := false


## The town templates in use: the list above, or every TownData in the Towns folder
func get_town_templates() -> Array[TownData]:
	var out: Array[TownData] = []
	for t in town_templates:
		if t != null:
			out.append(t)
	if not out.is_empty():
		return out
	if not _towns_scanned:
		_towns_scanned = true
		var files := DirAccess.get_files_at(TOWNS_DIR)
		var names := PackedStringArray()
		for f in files:
			var file := f.trim_suffix(".remap")  # exported games rename resources
			if file.ends_with(".tres") and not names.has(file):
				names.append(file)
		names.sort()
		for file in names:
			var t := load(TOWNS_DIR + "/" + file) as TownData
			if t != null:
				_found_towns.append(t)
	return _found_towns.duplicate()


## Used when WorldManager has no settings assigned: default_world.tres if it exists (a small
## plains world with points of interest), otherwise a bare single-biome world made in code
static func create_default() -> WorldSettings:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded := load(DEFAULT_PATH) as WorldSettings
		if loaded != null:
			return loaded
	var s := WorldSettings.new()
	var p := BiomePlacement.new()
	p.biome = BiomeData.new()
	p.cell = Vector2i(-2, -2)
	p.size_cells = Vector2i(4, 4)
	s.placements.append(p)
	return s


func get_valid_placements() -> Array[BiomePlacement]:
	var out: Array[BiomePlacement] = []
	for p in placements:
		if p != null and p.is_valid():
			out.append(p)
	return out


## Human-readable problems with the layout. Empty = fine.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var valid: Array[BiomePlacement] = []
	for i in placements.size():
		var p := placements[i]
		if p == null or p.biome == null:
			out.append("Placement %d has no biome and is ignored." % i)
		elif p.size_cells.x <= 0 or p.size_cells.y <= 0:
			out.append("Placement %d ('%s') has a size of zero and is ignored." % [i, p.biome.display_name])
		else:
			valid.append(p)
	if valid.is_empty():
		out.append("No valid biome placements: the world will be empty.")
	for i in valid.size():
		for j in range(i + 1, valid.size()):
			if valid[i].get_rect(cell_size).intersects(valid[j].get_rect(cell_size)):
				out.append("'%s' and '%s' overlap. Move one so the rectangles only touch." % [valid[i].biome.display_name, valid[j].biome.display_name])
	return out


## A number that changes when the layout changes (saves use it to notice an edited layout)
func layout_hash() -> int:
	var parts := PackedStringArray()
	for p in get_valid_placements():
		parts.append("%s@%d,%d+%d,%d" % [p.biome.get_key(), p.cell.x, p.cell.y, p.size_cells.x, p.size_cells.y])
		for rule in p.biome.poi_rules:
			if rule != null and rule.poi != null:
				parts.append("%s:%d:%.3f:%.3f" % [rule.poi.get_key(), rule.count_mode, rule.count_min, rule.count_max])
	if towns_enabled:
		parts.append("towns:%d:%d:%s:%s" % [towns_per_region_min, towns_per_region_max, city_per_biome, roads_enabled])
		if named_settlements:
			parts.append("named:%d" % NamedSettlements.count())
		for t in get_town_templates():
			parts.append(t.get_key())
	return ("%f|%s" % [cell_size, "|".join(parts)]).hash()
