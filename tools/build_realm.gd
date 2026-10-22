extends SceneTree
## Builds the six new biomes and realm_world.tres (the 16 x 16 km world of stage 9). Run with:
##   godot --headless --path . -s res://tools/build_realm.gd
## Each new biome starts as a copy of a similar existing one (its places and encounters) with its
## own name, colors, terrain and levels. Run it again after changing the tables; it overwrites
## the files it makes. You can also edit the results by hand in the inspector afterwards.

const W := "res://scripts/Resources/World/"

## new biome -> [copied from, settings]
const NEW_BIOMES := {
	"coast": ["lakeland", {"display_name": "Coast", "map_color": Color(0.80, 0.76, 0.55), "base_height": 3.0, "hills_amplitude": 9.0,
		"ground_color": Color(0.74, 0.68, 0.50), "ground_color_alt": Color(0.55, 0.62, 0.40), "tree_density": 8.0, "level_min": 10, "level_max": 27}],
	"badlands": ["desert", {"display_name": "Badlands", "map_color": Color(0.72, 0.42, 0.26), "base_height": 22.0, "hills_amplitude": 16.0,
		"mountain_amplitude": 60.0, "mountain_scale": 500.0, "mountain_coverage": 0.45, "ground_color": Color(0.62, 0.36, 0.22),
		"ground_color_alt": Color(0.70, 0.46, 0.28), "steep_color": Color(0.50, 0.28, 0.20), "level_min": 33, "level_max": 57}],
	"deadlands": ["swamp", {"display_name": "Deadlands", "map_color": Color(0.40, 0.39, 0.35), "base_height": 8.0, "hills_amplitude": 8.0,
		"ground_color": Color(0.35, 0.34, 0.30), "ground_color_alt": Color(0.30, 0.30, 0.27), "steep_color": Color(0.26, 0.25, 0.23),
		"tree_density": 10.0, "tree_color": Color(0.30, 0.28, 0.25), "level_min": 50, "level_max": 73}],
	"tundra": ["snow_mountains", {"display_name": "Tundra", "map_color": Color(0.74, 0.78, 0.74), "base_height": 30.0, "hills_amplitude": 7.0,
		"mountain_amplitude": 15.0, "ground_color": Color(0.76, 0.79, 0.76), "ground_color_alt": Color(0.60, 0.65, 0.56),
		"peak_height": 100000.0, "tree_density": 4.0, "level_min": 57, "level_max": 80}],
	"ashlands": ["highlands", {"display_name": "Ashlands", "map_color": Color(0.26, 0.19, 0.17), "base_height": 35.0, "hills_amplitude": 20.0,
		"mountain_amplitude": 80.0, "ground_color": Color(0.19, 0.18, 0.18), "ground_color_alt": Color(0.30, 0.20, 0.16),
		"steep_color": Color(0.12, 0.11, 0.11), "tree_density": 0.0, "level_min": 70, "level_max": 93}],
	"frozen_crown": ["snow_mountains", {"display_name": "Frozen Crown", "map_color": Color(0.94, 0.97, 1.0), "base_height": 80.0,
		"mountain_amplitude": 200.0, "mountain_coverage": 0.75, "ground_color": Color(0.90, 0.93, 0.98), "ground_color_alt": Color(0.82, 0.88, 0.95),
		"peak_height": 130.0, "blend_distance": 450.0, "tree_density": 6.0, "level_min": 80, "level_max": 100}],
}

## [biome file, cell x, cell y, width, height, level min, level max (0 = the biome's)]
## Cells are 1 km; y grows to the south. North is the hard end of the world.
const LAYOUT := [
	["ashlands", -8, -8, 5, 4, 0, 0],
	["frozen_crown", -3, -8, 6, 4, 0, 0],
	["tundra", 3, -8, 5, 4, 0, 0],
	["snow_mountains", -8, -4, 4, 4, 43, 67],
	["highlands", -4, -4, 5, 4, 27, 50],
	["badlands", 1, -4, 4, 4, 0, 0],
	["deadlands", 5, -4, 3, 4, 0, 0],
	["desert", -8, 0, 4, 4, 20, 43],
	["forest", -4, 0, 5, 4, 7, 23],
	["swamp", 1, 0, 7, 4, 17, 37],
	["lakeland", -8, 4, 5, 4, 3, 17],
	["plains", -3, 4, 7, 4, 1, 13],
	["coast", 4, 4, 4, 4, 0, 0],
]
const SPAWN := 11  # plains: you start in the south


func _initialize() -> void:
	for key in NEW_BIOMES:
		var spec: Array = NEW_BIOMES[key]
		var src := load(W + spec[0] + ".tres") as BiomeData
		var b := src.duplicate(true) as BiomeData
		b.id = StringName(key)
		var fields: Dictionary = spec[1]
		for f in fields:
			b.set(f, fields[f])
		var err := ResourceSaver.save(b, W + key + ".tres")
		print("%s: %s" % [key, "ok" if err == OK else "error %d" % err])

	var grand := load(W + "grand_world.tres") as WorldSettings
	var s := grand.duplicate(false) as WorldSettings
	s.cell_size = 1000.0
	var list: Array[BiomePlacement] = []
	for row: Array in LAYOUT:
		var p := BiomePlacement.new()
		p.biome = load(W + row[0] + ".tres") as BiomeData
		p.cell = Vector2i(row[1], row[2])
		p.size_cells = Vector2i(row[3], row[4])
		p.level_min = row[5]
		p.level_max = row[6]
		list.append(p)
	s.placements = list
	s.spawn_placement = SPAWN
	s.border_warp_strength = 260.0
	s.border_warp_scale = 900.0
	s.towns_per_region_min = 2
	s.towns_per_region_max = 3
	s.town_spacing = 450.0
	s.road_grid = 40.0
	s.debug_map_resolution = 768
	var err := ResourceSaver.save(s, W + "realm_world.tres")
	print("realm_world: %s" % ("ok" if err == OK else "error %d" % err))
	quit()
