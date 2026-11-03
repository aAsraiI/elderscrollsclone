extends SceneTree
## Alpha 1.21: the island world. Sets every biome's terrain layers, colours, flora and herbs, and
## lays out realm_world.tres as rounded regions on an island in the sea. Run with:
##   godot --headless --path . -s res://tools/build_world.gd [-- terrain|layout|flora]  (default: all)
## It changes only the fields in the tables below and keeps everything else in each file (places,
## encounters, levels you set by hand). Edit the results in the inspector afterwards if you like.

const W := "res://data/world/"

## Each biome's land, from the bottom up: base height and hills, then the layers that give it its
## own shape (see BiomeData: swirl, valleys, terraces, dunes, pools, crags, cones)
const TERRAIN := {
	"plains": {"base_height": 12.0, "hills_amplitude": 9.0, "hills_scale": 280.0, "swirl": 220.0, "swirl_scale": 700.0,
		"valley_depth": 7.0, "valley_scale": 950.0, "valley_width": 0.12, "mountain_amplitude": 0.0, "blend_distance": 260.0,
		"shore_color": Color(0.5, 0.47, 0.34), "high_color": Color(0.36, 0.42, 0.2), "high_start": 4.0, "high_full": 14.0},
	"lakeland": {"base_height": 6.0, "hills_amplitude": 8.0, "hills_scale": 240.0, "swirl": 180.0, "swirl_scale": 600.0,
		"pool_depth": 8.0, "pool_scale": 300.0, "pool_coverage": 0.3, "blend_distance": 260.0, "shore_color": Color(0.45, 0.43, 0.33)},
	"forest": {"base_height": 22.0, "hills_amplitude": 15.0, "hills_scale": 220.0, "swirl": 140.0, "swirl_scale": 420.0,
		"valley_depth": 11.0, "valley_scale": 700.0, "valley_width": 0.14, "crag_amplitude": 5.0, "crag_scale": 170.0, "crag_size": 0.2,
		"blend_distance": 260.0, "shore_color": Color(0.33, 0.3, 0.22)},
	"coast": {"base_height": 9.0, "hills_amplitude": 10.0, "hills_scale": 280.0, "swirl": 160.0, "swirl_scale": 500.0,
		"crag_amplitude": 9.0, "crag_scale": 230.0, "crag_size": 0.18, "valley_depth": 6.0, "valley_scale": 600.0, "valley_width": 0.12,
		"blend_distance": 240.0, "shore_color": Color(0.74, 0.68, 0.5), "high_color": Color(0.5, 0.55, 0.36), "high_start": 6.0, "high_full": 16.0},
	"swamp": {"base_height": 2.4, "hills_amplitude": 3.0, "hills_scale": 160.0, "pool_depth": 4.5, "pool_scale": 75.0, "pool_coverage": 0.4,
		"detail_amplitude": 0.3, "swirl": 60.0, "swirl_scale": 250.0, "blend_distance": 220.0, "shore_color": Color(0.24, 0.23, 0.16)},
	"highlands": {"base_height": 40.0, "hills_amplitude": 22.0, "hills_scale": 320.0, "swirl": 320.0, "swirl_scale": 850.0,
		"mountain_amplitude": 50.0, "mountain_scale": 650.0, "mountain_coverage": 0.42, "ridge_sharpness": 1.6,
		"valley_depth": 18.0, "valley_scale": 1100.0, "valley_width": 0.2, "crag_amplitude": 9.0, "crag_scale": 200.0, "crag_size": 0.2,
		"blend_distance": 340.0, "high_color": Color(0.4, 0.3, 0.3), "high_start": 15.0, "high_full": 45.0, "shore_color": Color(0.4, 0.38, 0.3)},
	"snow_mountains": {"base_height": 58.0, "hills_amplitude": 18.0, "hills_scale": 300.0, "swirl": 360.0, "swirl_scale": 1200.0,
		"mountain_amplitude": 150.0, "mountain_scale": 900.0, "mountain_coverage": 0.7, "ridge_sharpness": 2.6,
		"valley_depth": 28.0, "valley_scale": 1400.0, "valley_width": 0.12, "peak_height": 110.0, "blend_distance": 400.0,
		"shore_color": Color(0.5, 0.5, 0.5)},
	"frozen_crown": {"base_height": 85.0, "hills_amplitude": 20.0, "hills_scale": 300.0, "swirl": 420.0, "swirl_scale": 1300.0,
		"mountain_amplitude": 240.0, "mountain_scale": 1000.0, "mountain_coverage": 0.8, "ridge_sharpness": 3.0,
		"valley_depth": 40.0, "valley_scale": 1500.0, "valley_width": 0.11, "peak_height": 120.0, "blend_distance": 460.0,
		"shore_color": Color(0.7, 0.72, 0.76)},
	"tundra": {"base_height": 26.0, "hills_amplitude": 8.0, "hills_scale": 380.0, "swirl": 260.0, "swirl_scale": 900.0,
		"mountain_amplitude": 15.0, "mountain_scale": 800.0, "pool_depth": 4.0, "pool_scale": 150.0, "pool_coverage": 0.22,
		"crag_amplitude": 4.0, "crag_scale": 140.0, "crag_size": 0.15, "blend_distance": 380.0, "shore_color": Color(0.55, 0.56, 0.52)},
	"desert": {"base_height": 14.0, "hills_amplitude": 10.0, "hills_scale": 420.0, "swirl": 240.0, "swirl_scale": 700.0,
		"dune_amplitude": 9.0, "dune_scale": 90.0, "dune_angle": 35.0, "crag_amplitude": 12.0, "crag_scale": 600.0, "crag_size": 0.12,
		"terrace_height": 0.0, "blend_distance": 280.0, "shore_color": Color(0.78, 0.7, 0.5)},
	"badlands": {"base_height": 24.0, "hills_amplitude": 14.0, "hills_scale": 320.0, "swirl": 180.0, "swirl_scale": 600.0,
		"mountain_amplitude": 45.0, "mountain_scale": 500.0, "mountain_coverage": 0.5, "terrace_height": 7.0, "terrace_sharpness": 0.72,
		"valley_depth": 16.0, "valley_scale": 520.0, "valley_width": 0.09, "crag_amplitude": 14.0, "crag_scale": 160.0, "crag_size": 0.16,
		"blend_distance": 300.0, "shore_color": Color(0.6, 0.42, 0.3)},
	"deadlands": {"base_height": 10.0, "hills_amplitude": 7.0, "hills_scale": 200.0, "swirl": 110.0, "swirl_scale": 380.0,
		"pool_depth": 3.0, "pool_scale": 110.0, "pool_coverage": 0.2, "valley_depth": 5.0, "valley_scale": 420.0, "valley_width": 0.12,
		"crag_amplitude": 5.0, "crag_scale": 150.0, "crag_size": 0.15, "blend_distance": 240.0, "shore_color": Color(0.25, 0.24, 0.21)},
	"ashlands": {"base_height": 32.0, "hills_amplitude": 18.0, "hills_scale": 300.0, "swirl": 220.0, "swirl_scale": 650.0,
		"mountain_amplitude": 40.0, "mountain_scale": 600.0, "mountain_coverage": 0.45, "cone_amplitude": 95.0, "cone_scale": 1300.0,
		"crater_depth": 0.4, "crag_amplitude": 8.0, "crag_scale": 120.0, "crag_size": 0.16, "valley_depth": 12.0, "valley_scale": 600.0,
		"valley_width": 0.1, "blend_distance": 340.0, "shore_color": Color(0.17, 0.16, 0.16)},
}

## What grows in each land, layer by layer (FloraLayer). "models" are Morrowind building pieces
## ("set/name" = kit/plants/set/name, "rocks:set/name" = kit/rocks/set/name) or any other key;
## "shape" is the plain look when none of them is there. Sizes: TREE, SHRUB, PLANT, GROUND.
const S := FloraLayer.Shape
const Z := FloraLayer.Size
const FLORA := {
	"plains": [
		{"name": "copse oaks", "shape": S.BROADLEAF, "size": Z.TREE, "density": 9.0, "clump_scale": 260.0, "clumping": 0.85,
			"models": ["trees/flora_tree_01", "trees/flora_tree_02", "trees/flora_tree_ai_05", "tree/broadleaf"],
			"scale_min": 0.45, "scale_max": 0.75, "height": 9.0, "color": Color(0.24, 0.4, 0.17), "sink": 0.3, "max_slope": 24.0, "water": -0.3, "trunk_radius": 0.35},
		{"name": "hedgerow shrubs", "shape": S.BUSH, "size": Z.SHRUB, "density": 28.0, "clump_scale": 110.0, "clumping": 0.65,
			"models": ["other/flora_bush_01", "solstheim/flora_bm_shrub_01", "solstheim/flora_bm_shrub_03"], "scale_min": 0.55, "scale_max": 0.9,
			"height": 1.5, "color": Color(0.27, 0.38, 0.17), "solid": false},
		{"name": "meadow flowers", "shape": S.FLOWERS, "size": Z.PLANT, "density": 240.0, "clump_scale": 70.0, "clumping": 0.75,
			"height": 0.45, "color": Color(0.92, 0.78, 0.25), "solid": false, "lean": 6.0},
		{"name": "cornflowers", "shape": S.FLOWERS, "size": Z.PLANT, "density": 90.0, "clump_scale": 50.0, "clumping": 0.8,
			"height": 0.5, "color": Color(0.35, 0.45, 0.95), "solid": false},
		{"name": "tall grass", "shape": S.REEDS, "size": Z.PLANT, "density": 260.0, "clump_scale": 60.0, "clumping": 0.55,
			"models": ["grass/flora_grass_01", "grass/flora_grass_02", "grass/flora_grass_03"], "scale_min": 0.8, "scale_max": 1.3,
			"height": 0.7, "color": Color(0.42, 0.5, 0.25), "solid": false},
		{"name": "field stones", "shape": S.ROCK, "size": Z.GROUND, "density": 1.5, "clump_scale": 300.0, "clumping": 0.5,
			"models": ["rocks:ascadian/terrain_rock_ai_02", "rocks:ascadian/terrain_rock_ai_04", "rocks:ascadian/terrain_rock_ai_06"],
			"scale_min": 0.6, "scale_max": 1.0, "height": 1.2, "color": Color(0.5, 0.48, 0.44), "lean": 15.0, "follow_ground": true, "sink": 0.3},
		{"name": "fallen logs", "shape": S.LOG, "size": Z.GROUND, "density": 1.2, "models": ["logs_roots/flora_bm_log_01", "logs_roots/flora_bm_log_02"],
			"scale_min": 0.7, "scale_max": 1.0, "height": 4.0, "follow_ground": true, "lean": 0.0, "sink": 0.15, "max_slope": 20.0},
	],
	"forest": [
		{"name": "oaks", "shape": S.BROADLEAF, "size": Z.TREE, "density": 50.0, "clump_scale": 320.0, "clumping": 0.45,
			"models": ["trees/flora_tree_01", "trees/flora_tree_02", "trees/flora_tree_ai_05", "tree/broadleaf"],
			"scale_min": 0.45, "scale_max": 0.72, "height": 11.0, "color": Color(0.2, 0.36, 0.15), "sink": 0.35, "max_slope": 32.0, "trunk_radius": 0.4},
		{"name": "pines", "shape": S.PINE, "size": Z.TREE, "density": 34.0, "clump_scale": 220.0, "clumping": 0.6,
			"models": ["trees/flora_tree_bm_01", "trees/flora_tree_bm_02", "trees/flora_tree_bm_03", "trees/flora_tree_bm_05", "trees/flora_tree_bm_06", "tree/pine"],
			"scale_min": 0.9, "scale_max": 1.4, "height": 9.0, "color": Color(0.17, 0.3, 0.16), "sink": 0.25, "max_slope": 38.0, "trunk_radius": 0.3},
		{"name": "saplings", "shape": S.BIRCH, "size": Z.TREE, "density": 12.0, "clump_scale": 120.0, "clumping": 0.5,
			"models": ["trees/flora_tree_03", "trees/flora_tree_ai_06"], "scale_min": 0.4, "scale_max": 0.6, "height": 6.0,
			"color": Color(0.3, 0.45, 0.2), "sink": 0.1, "trunk_radius": 0.15},
		{"name": "ferns", "shape": S.FERN, "size": Z.PLANT, "density": 260.0, "clump_scale": 60.0, "clumping": 0.6,
			"models": ["bitter_coast/flora_bc_fern_02", "bitter_coast/flora_bc_fern_03", "bitter_coast/flora_bc_fern_04"],
			"scale_min": 0.55, "scale_max": 0.95, "height": 0.9, "color": Color(0.25, 0.42, 0.18), "solid": false, "water": 0.0},
		{"name": "undergrowth", "shape": S.BUSH, "size": Z.SHRUB, "density": 40.0, "clump_scale": 90.0, "clumping": 0.5,
			"models": ["solstheim/flora_bm_shrub_01", "solstheim/flora_bm_shrub_02", "solstheim/flora_bm_shrub_03"],
			"scale_min": 0.6, "scale_max": 1.0, "height": 1.4, "color": Color(0.22, 0.34, 0.15), "solid": false},
		{"name": "toadstools", "shape": S.MUSHROOM, "size": Z.GROUND, "density": 26.0, "clump_scale": 30.0, "clumping": 0.85,
			"models": ["mushrooms/flora_bc_mushroom_01", "mushrooms/flora_bc_mushroom_02", "mushrooms/flora_bc_mushroom_05"],
			"scale_min": 0.6, "scale_max": 1.0, "height": 0.35, "color": Color(0.75, 0.3, 0.2), "solid": false, "lean": 8.0},
		{"name": "logs and roots", "shape": S.LOG, "size": Z.GROUND, "density": 6.0, "clump_scale": 150.0, "clumping": 0.4,
			"models": ["logs_roots/flora_bm_log_01", "logs_roots/flora_bm_log_02", "logs_roots/flora_bm_log_05", "logs_roots/flora_root_wg_01", "logs_roots/flora_root_wg_05"],
			"scale_min": 0.6, "scale_max": 0.9, "height": 4.0, "follow_ground": true, "lean": 0.0, "sink": 0.2},
		{"name": "stumps", "shape": S.STUMP, "size": Z.GROUND, "density": 5.0, "models": ["trees/flora_bm_treestump_01", "trees/flora_bm_treestump_02", "trees/flora_bm_treestump_04"],
			"scale_min": 0.7, "scale_max": 1.0, "height": 0.8, "sink": 0.1},
		{"name": "mossy boulders", "shape": S.ROCK, "size": Z.GROUND, "density": 2.0, "clump_scale": 200.0, "clumping": 0.6,
			"models": ["rocks:west_gash/terrain_rock_wg_01", "rocks:west_gash/terrain_rock_wg_02", "rocks:bitter_coast/terrain_rock_bc_04"],
			"scale_min": 0.4, "scale_max": 0.8, "height": 1.6, "color": Color(0.4, 0.43, 0.36), "lean": 12.0, "follow_ground": true, "sink": 0.4},
	],
	"lakeland": [
		{"name": "willows", "shape": S.BROADLEAF, "size": Z.TREE, "density": 20.0, "clump_scale": 200.0, "clumping": 0.55,
			"models": ["trees/flora_tree_01", "trees/flora_tree_02", "tree/broadleaf"],
			"scale_min": 0.4, "scale_max": 0.6, "height": 9.0, "color": Color(0.3, 0.45, 0.22), "water": 0.6, "water_reach": 40.0, "sink": 0.3, "trunk_radius": 0.35},
		{"name": "birches", "shape": S.BIRCH, "size": Z.TREE, "density": 10.0, "clump_scale": 160.0, "clumping": 0.7,
			"models": ["trees/flora_tree_03", "trees/flora_tree_04", "trees/flora_tree_ai_06"], "scale_min": 0.4, "scale_max": 0.65, "height": 8.0,
			"color": Color(0.36, 0.52, 0.24), "sink": 0.2, "trunk_radius": 0.2},
		{"name": "reeds", "shape": S.REEDS, "size": Z.PLANT, "density": 600.0, "clump_scale": 40.0, "clumping": 0.4, "water": 1.0, "water_ok": true,
			"models": ["bitter_coast/flora_bc_grass_01", "bitter_coast/flora_bc_grass_02"], "scale_min": 0.7, "scale_max": 1.1,
			"height": 1.6, "color": Color(0.45, 0.5, 0.26), "solid": false},
		{"name": "lily pads", "shape": S.FLOWERS, "size": Z.PLANT, "density": 500.0, "clump_scale": 40.0, "clumping": 0.6, "in_water": true, "floats": true,
			"models": ["bitter_coast/flora_bc_lilypad_01", "bitter_coast/flora_bc_lilypad_02", "bitter_coast/flora_bc_lilypad_03"],
			"height": 0.1, "color": Color(0.3, 0.5, 0.25), "solid": false, "lean": 0.0, "sink": 0.0},
		{"name": "meadow flowers", "shape": S.FLOWERS, "size": Z.PLANT, "density": 150.0, "clump_scale": 60.0, "clumping": 0.7,
			"height": 0.45, "color": Color(0.95, 0.95, 0.9), "solid": false},
		{"name": "shrubs", "shape": S.BUSH, "size": Z.SHRUB, "density": 22.0, "models": ["solstheim/flora_bm_shrub_02", "other/flora_bush_01"],
			"scale_min": 0.6, "scale_max": 0.9, "height": 1.4, "color": Color(0.28, 0.4, 0.2), "solid": false},
		{"name": "shore stones", "shape": S.ROCK, "size": Z.GROUND, "density": 2.5, "water": 0.5, "water_reach": 30.0,
			"models": ["rocks:bitter_coast/terrain_rock_bc_01", "rocks:bitter_coast/terrain_rock_bc_02", "rocks:bitter_coast/terrain_rock_bc_03"],
			"scale_min": 0.5, "scale_max": 0.9, "height": 1.0, "color": Color(0.46, 0.45, 0.42), "lean": 15.0, "follow_ground": true, "sink": 0.25},
	],
	"coast": [
		{"name": "sea pines", "shape": S.PINE, "size": Z.TREE, "density": 9.0, "clump_scale": 300.0, "clumping": 0.7,
			"models": ["trees/flora_tree_bm_01", "trees/flora_tree_bm_02", "trees/flora_tree_bm_04", "trees/flora_tree_bm_06", "tree/pine"], "scale_min": 0.7, "scale_max": 1.0,
			"height": 8.0, "color": Color(0.22, 0.34, 0.2), "sink": 0.2, "water": -0.2, "lean": 7.0, "trunk_radius": 0.25},
		{"name": "dune grass", "shape": S.REEDS, "size": Z.PLANT, "density": 220.0, "clump_scale": 50.0, "clumping": 0.6,
			"models": ["grass/flora_grass_01", "grass/flora_grass_03"], "scale_min": 0.6, "scale_max": 1.0, "height": 0.7,
			"color": Color(0.62, 0.62, 0.4), "solid": false},
		{"name": "kelp", "shape": S.REEDS, "size": Z.PLANT, "density": 260.0, "clump_scale": 50.0, "clumping": 0.6, "in_water": true,
			"models": ["grass/flora_kelp_01", "grass/flora_kelp_02", "grass/flora_kelp_03", "grass/flora_kelp_04"], "scale_min": 0.4, "scale_max": 0.7,
			"height": 1.0, "color": Color(0.25, 0.32, 0.15), "solid": false, "lean": 10.0},
		{"name": "driftwood", "shape": S.LOG, "size": Z.GROUND, "density": 4.0, "water": 1.0, "water_reach": 25.0,
			"models": ["logs_roots/flora_bc_log_01", "logs_roots/flora_bc_log_02", "logs_roots/flora_bm_log_03"], "scale_min": 0.3, "scale_max": 0.45,
			"height": 3.0, "follow_ground": true, "lean": 0.0, "sink": 0.2},
		{"name": "blossom trees", "shape": S.BIRCH, "size": Z.TREE, "density": 2.5, "clump_scale": 260.0, "clumping": 0.8,
			"models": ["trees/flora_tree_ac_01", "trees/flora_tree_ac_02"], "scale_min": 0.55, "scale_max": 0.8, "height": 6.0,
			"color": Color(0.6, 0.45, 0.25), "sink": 0.15, "trunk_radius": 0.18},
		{"name": "salt shrubs", "shape": S.BUSH, "size": Z.SHRUB, "density": 14.0, "models": ["solstheim/flora_bm_shrub_01"],
			"scale_min": 0.5, "scale_max": 0.8, "height": 1.0, "color": Color(0.4, 0.45, 0.28), "solid": false},
		{"name": "sea rocks", "shape": S.ROCK, "size": Z.GROUND, "density": 2.5, "clump_scale": 160.0, "clumping": 0.6,
			"models": ["rocks:coast/terrain_rock_ac_02", "rocks:coast/terrain_rock_ac_04", "rocks:coast/terrain_rock_ac_06"],
			"scale_min": 0.4, "scale_max": 0.9, "height": 1.5, "color": Color(0.55, 0.52, 0.47), "lean": 10.0, "follow_ground": true, "sink": 0.3, "water_ok": true},
	],
	"swamp": [
		{"name": "swamp trees", "shape": S.DEAD, "size": Z.TREE, "density": 36.0, "clump_scale": 220.0, "clumping": 0.5, "water_ok": true,
			"models": ["bitter_coast/flora_bc_tree_01", "bitter_coast/flora_bc_tree_03", "bitter_coast/flora_bc_tree_05", "bitter_coast/flora_bc_tree_07", "bitter_coast/flora_bc_tree_08", "bitter_coast/flora_bc_tree_10"],
			"scale_min": 0.42, "scale_max": 0.65, "height": 9.0, "color": Color(0.27, 0.3, 0.18), "sink": 0.4, "trunk_radius": 0.45},
		{"name": "cypress knees", "shape": S.STUMP, "size": Z.GROUND, "density": 50.0, "clump_scale": 60.0, "clumping": 0.7, "water_ok": true,
			"models": ["bitter_coast/flora_bc_knee_01", "bitter_coast/flora_bc_knee_02", "bitter_coast/flora_bc_knee_03", "bitter_coast/flora_bc_knee_04"],
			"scale_min": 0.3, "scale_max": 0.5, "height": 0.8, "solid": false},
		{"name": "cap trees", "shape": S.MUSHROOM, "size": Z.TREE, "density": 3.0, "clump_scale": 300.0, "clumping": 0.8,
			"models": ["trees/flora_tree_ac_03", "trees/flora_tree_ac_04"], "scale_min": 0.6, "scale_max": 0.9, "height": 6.0,
			"color": Color(0.55, 0.45, 0.32), "sink": 0.2, "trunk_radius": 0.3},
		{"name": "giant mushrooms", "shape": S.MUSHROOM, "size": Z.TREE, "density": 1.2, "clump_scale": 500.0, "clumping": 0.9,
			"models": ["other/flora_emp_parasol_01", "other/flora_emp_parasol_02", "mushrooms/flora_t_mushroom_02"], "scale_min": 0.45, "scale_max": 0.7,
			"height": 6.0, "color": Color(0.6, 0.5, 0.35), "trunk_radius": 0.6},
		{"name": "marsh grass", "shape": S.REEDS, "size": Z.PLANT, "density": 320.0, "clump_scale": 50.0, "clumping": 0.5, "water_ok": true,
			"models": ["bitter_coast/flora_bc_grass_01", "bitter_coast/flora_bc_grass_02"], "scale_min": 0.6, "scale_max": 1.0,
			"height": 1.2, "color": Color(0.36, 0.4, 0.2), "solid": false},
		{"name": "lily pads", "shape": S.FLOWERS, "size": Z.PLANT, "density": 450.0, "clump_scale": 40.0, "clumping": 0.5, "in_water": true, "floats": true,
			"models": ["bitter_coast/flora_bc_lilypad_01", "bitter_coast/flora_bc_lilypad_02", "bitter_coast/flora_bc_lilypad_03"],
			"height": 0.1, "color": Color(0.3, 0.45, 0.22), "solid": false, "lean": 0.0, "sink": 0.0},
		{"name": "moss mounds", "shape": S.BUSH, "size": Z.GROUND, "density": 60.0, "clump_scale": 70.0, "clumping": 0.6,
			"models": ["bitter_coast/flora_bc_moss_01", "bitter_coast/flora_bc_moss_02", "bitter_coast/flora_bc_moss_05"], "scale_min": 0.6, "scale_max": 1.1,
			"height": 0.4, "color": Color(0.25, 0.3, 0.15), "solid": false, "follow_ground": true},
		{"name": "pods", "shape": S.MUSHROOM, "size": Z.PLANT, "density": 30.0, "clump_scale": 50.0, "clumping": 0.8,
			"models": ["other/flora_muckpod_01", "other/flora_muckpod_02", "other/flora_muckpod_03"], "scale_min": 0.6, "scale_max": 1.0,
			"height": 0.8, "color": Color(0.55, 0.55, 0.3), "solid": false},
		{"name": "rotten logs", "shape": S.LOG, "size": Z.GROUND, "density": 3.0, "water_ok": true,
			"models": ["logs_roots/flora_bc_log_01", "logs_roots/flora_bc_log_02"], "scale_min": 0.35, "scale_max": 0.5, "height": 4.0,
			"follow_ground": true, "lean": 0.0, "sink": 0.3},
	],
	"highlands": [
		{"name": "highland pines", "shape": S.PINE, "size": Z.TREE, "density": 14.0, "clump_scale": 360.0, "clumping": 0.75,
			"models": ["trees/flora_tree_bm_01", "trees/flora_tree_bm_03", "trees/flora_tree_bm_04", "trees/flora_tree_bm_06", "tree/pine"],
			"scale_min": 0.8, "scale_max": 1.2, "height": 8.0, "color": Color(0.17, 0.28, 0.16), "sink": 0.25, "max_slope": 36.0, "trunk_radius": 0.3},
		{"name": "gnarled trees", "shape": S.BROADLEAF, "size": Z.TREE, "density": 3.0, "models": ["trees/flora_tree_01", "trees/flora_tree_ai_05"],
			"scale_min": 0.35, "scale_max": 0.5, "height": 7.0, "color": Color(0.3, 0.38, 0.2), "sink": 0.3, "trunk_radius": 0.35},
		{"name": "heather", "shape": S.FLOWERS, "size": Z.PLANT, "density": 480.0, "clump_scale": 120.0, "clumping": 0.65,
			"models": ["other/flora_heather_01"], "scale_min": 1.0, "scale_max": 1.6, "height": 0.45, "color": Color(0.6, 0.38, 0.58), "solid": false},
		{"name": "juniper", "shape": S.BUSH, "size": Z.SHRUB, "density": 32.0, "clump_scale": 100.0, "clumping": 0.5,
			"models": ["solstheim/flora_bm_shrub_01", "solstheim/flora_bm_shrub_02", "solstheim/flora_bm_shrub_03"],
			"scale_min": 0.55, "scale_max": 0.9, "height": 1.2, "color": Color(0.22, 0.32, 0.18), "solid": false},
		{"name": "tussocks", "shape": S.REEDS, "size": Z.PLANT, "density": 220.0, "clump_scale": 80.0, "clumping": 0.4,
			"models": ["grass/flora_grass_01", "grass/flora_grass_02", "grass/flora_grass_03"], "scale_min": 0.6, "scale_max": 1.0,
			"height": 0.6, "color": Color(0.52, 0.5, 0.3), "solid": false},
		{"name": "tors", "shape": S.ROCK, "size": Z.GROUND, "density": 2.5, "clump_scale": 260.0, "clumping": 0.6, "min_slope": 6.0, "max_slope": 60.0,
			"models": ["rocks:grazelands/terrain_rock_gl_02", "rocks:grazelands/terrain_rock_gl_04", "rocks:grazelands/terrain_rock_gl_06", "rocks:west_gash/terrain_rock_wg_02"],
			"scale_min": 0.5, "scale_max": 1.0, "height": 2.0, "color": Color(0.46, 0.44, 0.4), "lean": 12.0, "follow_ground": true, "sink": 0.4},
		{"name": "stumps", "shape": S.STUMP, "size": Z.GROUND, "density": 1.5, "models": ["trees/flora_bm_treestump_03", "trees/flora_bm_treestump_05"],
			"scale_min": 0.7, "scale_max": 1.0, "height": 0.7},
	],
	"snow_mountains": [
		{"name": "snow pines", "shape": S.PINE, "size": Z.TREE, "density": 30.0, "clump_scale": 260.0, "clumping": 0.5, "max_height": 150.0,
			"models": ["trees/flora_tree_bm_snow_01", "trees/flora_tree_bm_snow_02", "trees/flora_tree_bm_snow_03", "trees/flora_tree_bm_snow_05", "trees/flora_tree_bm_snow_06", "tree/pine"],
			"scale_min": 0.9, "scale_max": 1.3, "height": 8.0, "color": Color(0.7, 0.75, 0.75), "sink": 0.25, "max_slope": 40.0, "trunk_radius": 0.3},
		{"name": "snowy logs", "shape": S.LOG, "size": Z.GROUND, "density": 3.0, "models": ["logs_roots/flora_bm_snow_log_01", "logs_roots/flora_bm_snow_log_02", "logs_roots/flora_bm_snow_log_04"],
			"scale_min": 0.6, "scale_max": 0.9, "height": 4.0, "follow_ground": true, "lean": 0.0, "sink": 0.15},
		{"name": "snowy stumps", "shape": S.STUMP, "size": Z.GROUND, "density": 3.0,
			"models": ["logs_roots/flora_bm_snowstump_01", "logs_roots/flora_bm_snowstump_03", "logs_roots/flora_bm_snowstump_05"], "scale_min": 0.7, "scale_max": 1.0, "height": 0.8},
		{"name": "fallen branches", "shape": S.LOG, "size": Z.GROUND, "density": 5.0, "models": ["solstheim/flora_bm_snowbranch_01", "solstheim/flora_bm_snowbranch_02", "solstheim/flora_bm_snowbranch_03"],
			"scale_min": 0.6, "scale_max": 1.0, "height": 1.5, "follow_ground": true, "lean": 0.0, "solid": false},
		{"name": "frost rocks", "shape": S.ROCK, "size": Z.GROUND, "density": 2.0, "clump_scale": 200.0, "clumping": 0.5,
			"models": ["rocks:other/terrain_rock_bm_05", "rocks:other/terrain_boulder_02", "rocks:other/terrain_boulder_04"], "scale_min": 0.4, "scale_max": 0.8,
			"height": 1.5, "color": Color(0.6, 0.62, 0.66), "lean": 12.0, "follow_ground": true, "sink": 0.3},
	],
	"frozen_crown": [
		{"name": "lone pines", "shape": S.PINE, "size": Z.TREE, "density": 5.0, "clump_scale": 400.0, "clumping": 0.8, "max_height": 120.0,
			"models": ["trees/flora_tree_bm_snow_04", "trees/flora_tree_bm_snow_07", "tree/pine"], "scale_min": 0.7, "scale_max": 1.0,
			"height": 6.0, "color": Color(0.75, 0.8, 0.82), "sink": 0.2, "trunk_radius": 0.25},
		{"name": "ice chunks", "shape": S.ROCK, "size": Z.GROUND, "density": 5.0, "clump_scale": 160.0, "clumping": 0.7, "solid": false,
			"models": ["rocks:solstheim/terrain_bm_icechunk_01", "rocks:solstheim/terrain_bm_icechunk_02", "rocks:solstheim/terrain_bm_icechunk_03"],
			"scale_min": 0.8, "scale_max": 1.4, "height": 0.3, "color": Color(0.75, 0.85, 0.95), "follow_ground": true, "lean": 0.0, "sink": 0.0},
		{"name": "frost boulders", "shape": S.ROCK, "size": Z.GROUND, "density": 2.5, "models": ["rocks:other/terrain_rock_bm_05", "rocks:other/terrain_rock_bm_06"],
			"scale_min": 0.4, "scale_max": 0.8, "height": 2.0, "color": Color(0.62, 0.64, 0.7), "lean": 10.0, "follow_ground": true, "sink": 0.4},
	],
	"tundra": [
		{"name": "dwarf pines", "shape": S.PINE, "size": Z.TREE, "density": 6.0, "clump_scale": 400.0, "clumping": 0.8,
			"models": ["trees/flora_tree_bm_snow_04", "trees/flora_tree_bm_snow_06", "trees/flora_tree_bm_07", "tree/pine"], "scale_min": 0.45, "scale_max": 0.7,
			"height": 4.0, "color": Color(0.3, 0.38, 0.3), "sink": 0.15, "trunk_radius": 0.2},
		{"name": "tussock grass", "shape": S.REEDS, "size": Z.PLANT, "density": 320.0, "clump_scale": 90.0, "clumping": 0.4,
			"models": ["solstheim/flora_bm_grass_02", "solstheim/flora_bm_grass_04", "solstheim/flora_bm_grass_06"], "scale_min": 0.6, "scale_max": 1.0,
			"height": 0.5, "color": Color(0.55, 0.55, 0.42), "solid": false},
		{"name": "heather", "shape": S.FLOWERS, "size": Z.PLANT, "density": 120.0, "clump_scale": 100.0, "clumping": 0.7,
			"models": ["other/flora_heather_01"], "scale_min": 0.9, "scale_max": 1.3, "height": 0.4, "color": Color(0.55, 0.4, 0.55), "solid": false},
		{"name": "crowberry", "shape": S.BUSH, "size": Z.SHRUB, "density": 18.0, "models": ["solstheim/flora_bm_shrub_02"],
			"scale_min": 0.4, "scale_max": 0.7, "height": 0.8, "color": Color(0.3, 0.32, 0.22), "solid": false},
		{"name": "erratics", "shape": S.ROCK, "size": Z.GROUND, "density": 1.2, "models": ["rocks:other/terrain_boulder_01", "rocks:other/terrain_boulder_04", "rocks:other/terrain_rock_bm_05"],
			"scale_min": 0.5, "scale_max": 1.0, "height": 2.0, "color": Color(0.5, 0.52, 0.5), "lean": 10.0, "follow_ground": true, "sink": 0.4},
	],
	"desert": [
		{"name": "cacti", "shape": S.CACTUS, "size": Z.TREE, "density": 6.0, "clump_scale": 300.0, "clumping": 0.6,
			"height": 3.2, "color": Color(0.32, 0.45, 0.25), "scale_min": 0.6, "scale_max": 1.2, "trunk_radius": 0.25, "lean": 4.0},
		{"name": "oasis palms", "shape": S.PALM, "size": Z.TREE, "density": 30.0, "water": 1.0, "water_reach": 60.0,
			"height": 8.0, "color": Color(0.3, 0.45, 0.2), "scale_min": 0.8, "scale_max": 1.2, "trunk_radius": 0.25, "lean": 8.0},
		{"name": "dry shrubs", "shape": S.BUSH, "size": Z.SHRUB, "density": 10.0, "models": ["other/flora_roobrush_01"],
			"scale_min": 0.45, "scale_max": 0.75, "height": 0.9, "color": Color(0.55, 0.5, 0.33), "solid": false},
		{"name": "dead trees", "shape": S.DEAD, "size": Z.TREE, "density": 1.2, "models": ["trees/flora_treedead_mh_02", "trees/flora_ashtree_02"],
			"scale_min": 0.7, "scale_max": 1.0, "height": 4.0, "trunk_radius": 0.2},
		{"name": "sandstone", "shape": S.ROCK, "size": Z.GROUND, "density": 1.0, "models": ["rocks:coast/terrain_rock_ac_03", "rocks:coast/terrain_rock_ac_05"],
			"scale_min": 0.5, "scale_max": 1.0, "height": 1.2, "color": Color(0.68, 0.58, 0.42), "follow_ground": true, "lean": 8.0, "sink": 0.3},
	],
	"badlands": [
		{"name": "dead trees", "shape": S.DEAD, "size": Z.TREE, "density": 4.0, "clump_scale": 300.0, "clumping": 0.7,
			"models": ["trees/flora_treedead_mh_02", "trees/flora_ashtree_01", "trees/flora_ashtree_02", "trees/flora_ashtree_05"],
			"scale_min": 0.6, "scale_max": 0.9, "height": 5.0, "trunk_radius": 0.2},
		{"name": "sagebrush", "shape": S.BUSH, "size": Z.SHRUB, "density": 32.0, "clump_scale": 150.0, "clumping": 0.5,
			"models": ["other/flora_roobrush_01"], "scale_min": 0.45, "scale_max": 0.75, "height": 0.9, "color": Color(0.55, 0.57, 0.45), "solid": false},
		{"name": "thornbushes", "shape": S.DEAD, "size": Z.SHRUB, "density": 7.0, "models": ["other/flora_rm_scathecraw_01", "other/flora_rm_scathecraw_02"],
			"scale_min": 0.35, "scale_max": 0.55, "height": 1.2, "color": Color(0.35, 0.28, 0.2), "solid": false},
		{"name": "small cacti", "shape": S.CACTUS, "size": Z.SHRUB, "density": 3.0, "height": 1.4, "color": Color(0.35, 0.45, 0.28), "solid": false},
		{"name": "red boulders", "shape": S.ROCK, "size": Z.GROUND, "density": 2.5, "clump_scale": 200.0, "clumping": 0.6,
			"models": ["rocks:west_gash/terrain_rock_wg_01", "rocks:west_gash/terrain_rock_wg_05", "rocks:ascadian/terrain_rock_ai_04"],
			"scale_min": 0.4, "scale_max": 0.8, "height": 1.6, "color": Color(0.55, 0.36, 0.26), "follow_ground": true, "lean": 10.0, "sink": 0.35},
	],
	"deadlands": [
		{"name": "dead trees", "shape": S.DEAD, "size": Z.TREE, "density": 14.0, "clump_scale": 200.0, "clumping": 0.5,
			"models": ["trees/flora_treedead_mh_01", "trees/flora_ashtree_04", "trees/flora_ashtree_06", "trees/flora_ashtree_07", "trees/flora_tree_gl_10", "trees/flora_tree_gl_07"],
			"scale_min": 0.5, "scale_max": 0.75, "height": 7.0, "color": Color(0.25, 0.23, 0.2), "sink": 0.3, "trunk_radius": 0.25},
		{"name": "gnarled roots", "shape": S.LOG, "size": Z.GROUND, "density": 7.0, "clump_scale": 120.0, "clumping": 0.5,
			"models": ["logs_roots/flora_root_wg_02", "logs_roots/flora_root_wg_04", "logs_roots/flora_root_wg_06", "logs_roots/flora_root_wg_08"],
			"scale_min": 0.45, "scale_max": 0.75, "height": 2.0, "sink": 0.3},
		{"name": "grave moss", "shape": S.BUSH, "size": Z.GROUND, "density": 40.0, "clump_scale": 80.0, "clumping": 0.6,
			"models": ["bitter_coast/flora_bc_moss_03", "bitter_coast/flora_bc_moss_07", "bitter_coast/flora_bc_moss_11"], "scale_min": 0.6, "scale_max": 1.0,
			"height": 0.3, "color": Color(0.25, 0.27, 0.2), "solid": false, "follow_ground": true},
		{"name": "rotting logs", "shape": S.LOG, "size": Z.GROUND, "density": 3.0, "models": ["logs_roots/flora_ash_log_01", "logs_roots/flora_ash_log_02"],
			"scale_min": 0.5, "scale_max": 0.8, "height": 4.0, "follow_ground": true, "lean": 0.0, "sink": 0.2},
		{"name": "pods", "shape": S.MUSHROOM, "size": Z.PLANT, "density": 10.0, "models": ["other/flora_muckpod_04", "other/flora_muckpod_05"],
			"scale_min": 0.6, "scale_max": 1.0, "height": 0.7, "color": Color(0.45, 0.42, 0.35), "solid": false},
		{"name": "bare giants", "shape": S.DEAD, "size": Z.TREE, "density": 1.0, "models": ["trees/flora_tree_gl_03", "trees/flora_tree_gl_05"],
			"scale_min": 0.4, "scale_max": 0.55, "height": 6.0, "trunk_radius": 0.6},
	],
	"ashlands": [
		{"name": "ash trees", "shape": S.DEAD, "size": Z.TREE, "density": 5.0, "clump_scale": 300.0, "clumping": 0.7,
			"models": ["trees/flora_ashtree_01", "trees/flora_ashtree_03", "trees/flora_ashtree_04", "trees/flora_ashtree_05", "trees/flora_ashtree_07"],
			"scale_min": 0.7, "scale_max": 1.0, "height": 6.0, "color": Color(0.2, 0.17, 0.15), "trunk_radius": 0.25},
		{"name": "trama shrubs", "shape": S.DEAD, "size": Z.SHRUB, "density": 12.0, "clump_scale": 150.0, "clumping": 0.6,
			"models": ["other/flora_trama_shrub_01", "other/flora_trama_shrub_03", "other/flora_trama_shrub_04", "other/flora_trama_shrub_06"],
			"scale_min": 0.18, "scale_max": 0.3, "height": 1.8, "color": Color(0.3, 0.16, 0.12), "solid": false},
		{"name": "ash grass", "shape": S.REEDS, "size": Z.PLANT, "density": 70.0, "clump_scale": 80.0, "clumping": 0.6,
			"models": ["other/flora_ash_grass_b_01", "other/flora_ash_grass_r_01", "other/flora_ash_grass_w_01"], "scale_min": 0.4, "scale_max": 0.7,
			"height": 0.8, "color": Color(0.4, 0.3, 0.25), "solid": false},
		{"name": "thorns", "shape": S.DEAD, "size": Z.SHRUB, "density": 5.0, "models": ["other/flora_rm_scathecraw_01", "other/flora_rm_scathecraw_02"],
			"scale_min": 0.35, "scale_max": 0.55, "height": 1.2, "color": Color(0.25, 0.18, 0.14), "solid": false},
		{"name": "ash logs", "shape": S.LOG, "size": Z.GROUND, "density": 2.5, "models": ["logs_roots/flora_ash_log_01", "logs_roots/flora_ash_log_03"],
			"scale_min": 0.5, "scale_max": 0.8, "height": 4.0, "follow_ground": true, "lean": 0.0, "sink": 0.2},
		{"name": "lava rocks", "shape": S.ROCK, "size": Z.GROUND, "density": 3.0, "clump_scale": 200.0, "clumping": 0.6,
			"models": ["rocks:ashlands/terrain_ashland_rock_01", "rocks:ashlands/terrain_ashland_rock_03", "rocks:ashlands/terrain_rock_rm_03", "rocks:ashlands/terrain_rock_rm_04"],
			"scale_min": 0.3, "scale_max": 0.6, "height": 2.0, "color": Color(0.16, 0.14, 0.14), "follow_ground": true, "lean": 10.0, "sink": 0.4},
	],
}

## The herbs you can pick in each land ("id:weight"; HarvestNode.HERB_INFO says which grow at the water)
const HERBS := {
	"plains": ["red_poppy:3", "yarrow:3", "cornflower:3", "lavender:2", "wild_garlic:2", "bramble_berries:2", "bulbroot:1", "thistle:1", "blue_mountain_flower:1", "water_mint:2", "cattail_root:1"],
	"lakeland": ["water_mint:3", "cattail_root:3", "swamp_lily:2", "bulbroot:2", "yarrow:1", "saltgrass:1", "lavender:1", "cornflower:1"],
	"forest": ["fly_agaric:3", "fiddlehead:3", "bramble_berries:2", "shelf_fungus:2", "nightshade:2", "glowcap:1", "belladonna:1", "wild_garlic:1", "mandrake_root:1", "water_mint:1"],
	"coast": ["sea_kelp:3", "saltgrass:3", "thistle:2", "blue_mountain_flower:1", "yarrow:1", "cattail_root:1"],
	"swamp": ["spore_pod:2", "strangleweed:2", "bloodmoss:2", "shelf_fungus:1", "nightshade:1", "glowcap:1", "bog_bean:3", "mire_sponge:2", "swamp_lily:2"],
	"highlands": ["heather:4", "yarrow:2", "blue_mountain_flower:2", "juniper_berries:2", "red_mountain_flower:2", "thistle:1", "mandrake_root:1", "water_mint:1"],
	"snow_mountains": ["cloudberries:3", "wolfsbane:2", "ice_lichen:2", "snowberries:2", "frost_mirriam:2", "juniper_berries:1", "blue_mountain_flower:1"],
	"frozen_crown": ["ice_lichen:4", "frost_mirriam:3", "snowberries:2", "wolfsbane:1"],
	"tundra": ["cloudberries:3", "heather:2", "ice_lichen:2", "snowberries:2", "juniper_berries:1"],
	"desert": ["aloe_leaf:3", "sand_lily:2", "cactus_flower:3", "sandroot:3", "sagebrush:1"],
	"badlands": ["sagebrush:4", "thornroot:3", "cactus_flower:1", "sandroot:1", "thistle:1"],
	"deadlands": ["grave_moss:4", "belladonna:3", "wolfsbane:2", "spore_pod:1", "nightshade:2"],
	"ashlands": ["ash_root:4", "ember_fern:3", "thornroot:2"],
}
## The herbs added in 1.21: id -> [name, value, where it is found (for the description), loot tags].
## Their four effects are in Alchemy.INGREDIENTS. Files that exist are left as they are.
const NEW_INGREDIENTS := {
	"heather": ["Heather", 4, "on high moors", ["alchemist"]],
	"bog_bean": ["Bog Bean", 6, "in swamp pools", ["alchemist"]],
	"shelf_fungus": ["Shelf Fungus", 7, "in damp woods", ["alchemist", "cave"]],
	"spore_pod": ["Spore Pod", 9, "in swamps and dead lands", ["alchemist"]],
	"cattail_root": ["Cattail Root", 5, "at the edge of still water", ["alchemist"]],
	"cloudberries": ["Cloudberries", 6, "on cold heaths", ["alchemist", "food"]],
	"wolfsbane": ["Wolfsbane", 12, "on mountainsides and in dead lands", ["alchemist"]],
	"belladonna": ["Belladonna", 14, "in shaded and dead places", ["alchemist"]],
	"aloe_leaf": ["Aloe Leaf", 8, "in the desert", ["alchemist"]],
	"sagebrush": ["Sagebrush", 4, "in the badlands and desert", ["alchemist"]],
	"ash_root": ["Ash Root", 10, "in the ashlands", ["alchemist"]],
	"ember_fern": ["Ember Fern", 14, "in the ashlands", ["alchemist"]],
	"thornroot": ["Thornroot", 9, "in dry, broken land", ["alchemist"]],
	"sea_kelp": ["Sea Kelp", 5, "in the shallows of the sea", ["alchemist"]],
	"saltgrass": ["Saltgrass", 3, "along the coast", ["alchemist"]],
	"red_poppy": ["Red Poppy", 5, "in meadows", ["alchemist"]],
	"yarrow": ["Yarrow", 3, "in meadows and on hills", ["alchemist"]],
	"cornflower": ["Cornflower", 4, "in fields", ["alchemist"]],
	"fly_agaric": ["Fly Agaric", 8, "in forests", ["alchemist"]],
	"fiddlehead": ["Fiddlehead", 4, "among forest ferns", ["alchemist", "food"]],
	"bramble_berries": ["Bramble Berries", 4, "in hedges and woods", ["alchemist", "food"]],
	"water_mint": ["Water Mint", 5, "beside streams and lakes", ["alchemist"]],
	"grave_moss": ["Grave Moss", 10, "in the dead lands", ["alchemist", "crypt"]],
	"ice_lichen": ["Ice Lichen", 11, "on frozen peaks", ["alchemist"]],
	"strangleweed": ["Strangleweed", 9, "in swamps", ["alchemist"]],
	"bulbroot": ["Bulbroot", 5, "in wet meadows", ["alchemist"]],
	"mire_sponge": ["Mire Sponge", 7, "in swamp water", ["alchemist"]],
	"sand_lily": ["Sand Lily", 13, "in the desert", ["alchemist"]],
}

## Herbs compared to the usual amount: the rich lands have more, the bare ones less
const HERB_DENSITY := {"forest": 1.4, "swamp": 1.3, "lakeland": 1.3, "plains": 1.2, "highlands": 1.1, "coast": 1.0, "deadlands": 0.9,
	"snow_mountains": 0.8, "tundra": 0.8, "badlands": 0.8, "desert": 0.7, "ashlands": 0.7, "frozen_crown": 0.5}


## [biome file, cell x, cell y, width, height, level min, level max (0 = the biome's)]
## Cells are 500 m; y grows to the south. The island is 12 x 12 km; north is the hard end. Several
## lands come twice (a big region and a small pocket), so no land is one huge block.
const LAYOUT := [
	["ashlands", -12, -12, 8, 7, 0, 0],
	["frozen_crown", -4, -12, 8, 6, 0, 0],
	["tundra", 4, -12, 8, 6, 0, 0],
	["badlands", -12, -5, 4, 6, 33, 57],
	["snow_mountains", -8, -6, 5, 5, 43, 67],
	["highlands", -3, -6, 7, 6, 27, 50],
	["snow_mountains", 4, -6, 4, 4, 14, 30],
	["deadlands", 8, -7, 4, 7, 50, 73],
	["desert", -12, 1, 6, 6, 20, 43],
	["forest", -6, 0, 7, 6, 7, 23],
	["highlands", 1, 0, 4, 4, 10, 24],
	["swamp", 5, 0, 7, 6, 17, 37],
	["lakeland", -12, 7, 7, 5, 3, 17],
	["plains", -5, 6, 9, 6, 1, 13],
	["coast", 4, 6, 8, 6, 10, 27],
	["forest", -7, 4, 3, 3, 3, 12],
	["forest", 2, 4, 3, 3, 8, 18],
	["badlands", -6, -2, 2, 2, 26, 40],
]
const SPAWN := 13  # plains: you start in the south

## Islands out in the sea (data/world/Islands/<file>.tres, IslandData), each like the main island:
## [file, name, roundness, [[biome, cell x, cell y, width, height, level min, level max], ...]]
## The main island runs from cell -12 to 12 both ways; these keep 2-3 km of sea from it.
const ISLANDS := [
	["isle_of_cinders", "Isle of Cinders", 0.45, [["ashlands", -25, -23, 6, 6, 72, 95]]],
	["frosthold", "Frosthold", 0.38, [["tundra", 18, -24, 5, 5, 60, 80], ["frozen_crown", 23, -24, 4, 5, 70, 90]]],
	["saltmarsh_isles", "Saltmarsh Isles", 0.3, [["swamp", 21, 2, 5, 6, 20, 34], ["coast", 26, 2, 3, 6, 18, 30]]],
	["greenisle", "Greenisle", 0.42, [["forest", -27, 5, 5, 5, 4, 14], ["plains", -27, 10, 5, 4, 3, 12], ["lakeland", -22, 6, 3, 6, 5, 15]]],
	["sunreach", "Sunreach", 0.36, [["desert", -6, 18, 5, 5, 30, 46], ["badlands", -1, 17, 5, 4, 34, 50], ["highlands", -1, 21, 4, 4, 28, 44],
		["plains", -6, 23, 5, 3, 26, 40], ["coast", 3, 18, 4, 6, 28, 42]]],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var all := args.is_empty()
	if all or args.has("terrain"):
		for key in TERRAIN:
			var b := load(W + key + ".tres") as BiomeData
			var fields: Dictionary = TERRAIN[key]
			for f in fields:
				b.set(f, fields[f])
			_save(b, W + key + ".tres")
	if all or args.has("flora"):
		for key in FLORA:
			var b := load(W + key + ".tres") as BiomeData
			var list: Array[FloraLayer] = []
			for spec: Dictionary in FLORA[key]:
				var f := FloraLayer.new()
				for field in spec:
					if field == "models":
						var keys := PackedStringArray()
						for m: String in spec[field]:
							keys.append(_model_key(m))
						f.models = keys
					else:
						f.set(field, spec[field])
				list.append(f)
			b.flora = list
			b.herbs = PackedStringArray(HERBS.get(key, []))
			b.herb_density = float(HERB_DENSITY.get(key, 1.0))
			_save(b, W + key + ".tres")
	if all or args.has("ingredients"):
		for id: String in NEW_INGREDIENTS:
			var path := "res://data/ingredients/%s.tres" % id
			if ResourceLoader.exists(path):
				continue
			var row: Array = NEW_INGREDIENTS[id]
			var item := ItemData.new()
			item.id = StringName(id)
			item.display_name = row[0]
			item.description = "An alchemical ingredient, found %s. Alchemists buy it." % row[2]
			item.item_type = 4
			item.weight = 0.1
			item.value = row[1]
			item.stackable = true
			item.max_stack = 99
			item.loot_tags = PackedStringArray(row[3])
			item.ingredient_effects = PackedStringArray(Alchemy.INGREDIENTS[id])
			_save(item, path)
	if all or args.has("layout"):
		var s := load(W + "realm_world.tres") as WorldSettings
		s.layout_style = WorldSettings.LayoutStyle.REGIONS
		s.cell_size = 500.0
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
		s.water_enabled = true
		s.sea_level = 0.0
		s.edge_width = 20.0
		s.poi_edge_margin = 30.0
		s.towns_per_region_min = 0
		s.towns_per_region_max = 1
		s.town_spacing = 380.0
		s.road_grid = 36.0
		_save(s, W + "realm_world.tres")
	if all or args.has("islands"):
		var s := load(W + "realm_world.tres") as WorldSettings
		var list: Array[IslandData] = []
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(W + "Islands"))
		for row: Array in ISLANDS:
			var isle := IslandData.new()
			isle.name = row[1]
			isle.roundness = row[2]
			var ps: Array[BiomePlacement] = []
			for pr: Array in row[3]:
				var p := BiomePlacement.new()
				p.biome = load(W + pr[0] + ".tres") as BiomeData
				p.cell = Vector2i(pr[1], pr[2])
				p.size_cells = Vector2i(pr[3], pr[4])
				p.level_min = pr[5]
				p.level_max = pr[6]
				ps.append(p)
			isle.placements = ps
			_save(isle, W + "Islands/%s.tres" % row[0])
			list.append(load(W + "Islands/%s.tres" % row[0]) as IslandData)
		s.islands = list
		_save(s, W + "realm_world.tres")
	quit()


# "set/name" is a Morrowind plant (kit/plants/...), "rocks:set/name" a Morrowind rock; any key with a
# known prefix (tree/, nature/, kit/) is used as it is
static func _model_key(m: String) -> String:
	if m.begins_with("rocks:"):
		return "kit/rocks/" + m.substr(6)
	for p in ["tree/", "nature/", "kit/", "prop/"]:
		if m.begins_with(p):
			return m
	return "kit/plants/" + m


func _save(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	print("%s: %s" % [path.get_file(), "ok" if err == OK else "error %d" % err])
