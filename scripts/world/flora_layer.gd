class_name FloraLayer
extends Resource
## One kind of thing growing (or lying) on the land: a tree, a shrub, ferns, reeds, mushrooms, a
## fallen log, boulders. A biome's Flora list holds several; each is scattered on its own, so a
## forest can have tall pines on the slopes, birches in clumps, ferns in the shade and logs here
## and there. Same seed = same plants.
##
## Looks: the first of Models that has a model is used, and every one that has a model is mixed in
## for variety. Keys are any ModelLibrary key, e.g. the Morrowind building pieces
## ("kit/plants/trees/flora_tree_gl_01"; these need Settings > Models > Import building pieces) or the
## built-in ones ("tree/pine", "nature/bush", "nature/rock_0"). With none, Shape draws a plain one.

enum Shape { BROADLEAF, PINE, DEAD, CACTUS, BUSH, FERN, REEDS, MUSHROOM, LOG, STUMP, ROCK, FLOWERS, PALM, BIRCH }
enum Size { TREE, SHRUB, PLANT, GROUND }

@export var name := ""
@export var models := PackedStringArray()
## What it looks like without a model
@export var shape: Shape = Shape.BROADLEAF
## TREE: seen far off, solid trunk. SHRUB: seen fairly far. PLANT and GROUND: only up close.
@export var size: Size = Size.TREE
## Colour of the plain shape (no model)
@export var color := Color(0.25, 0.4, 0.18)

@export_group("Amount")
## How many per hectare (100 x 100 m) where it grows thickest
@export_range(0.0, 2000.0, 0.1, "or_greater") var density := 20.0
## Meters across its clumps and clearings. 0 = spread evenly.
@export_range(0.0, 2000.0, 1.0, "or_greater") var clump_scale := 120.0
## 0 = evenly everywhere, 1 = only in dense clumps with bare ground between
@export_range(0.0, 1.0, 0.01) var clumping := 0.5

@export_group("Where")
## Steepest ground it grows on (degrees)
@export_range(0.0, 90.0, 0.5) var max_slope := 30.0
## Only on ground at least this steep (rocks on hillsides). 0 = any.
@export_range(0.0, 90.0, 0.5) var min_slope := 0.0
## Height range above sea level (m)
@export var min_height := -1.0
@export var max_height := 10000.0
## -1 = keeps away from water, 0 = doesn't care, 1 = only along rivers, lakes and the shore
@export_range(-1.0, 1.0, 0.05) var water := 0.0
## How far from the water (m) "along the water" reaches
@export_range(2.0, 200.0, 1.0) var water_reach := 24.0
## Grows in the water itself (reeds, lily pads, kelp)
@export var in_water := false
## May also stand in shallow water (swamp trees, cypress knees)
@export var water_ok := false
## Sits on the water's surface instead of the bottom (lily pads)
@export var floats := false

@export_group("Size and pose")
## Height in meters for the plain shape, and for a model that is not drawn at its real size
@export var height := 6.0
## Random size range (times height, or times the model's own size)
@export var scale_min := 0.8
@export var scale_max := 1.3
## Draw models at their real size (Morrowind's) instead of fitting them to height
@export var real_size := true
## Meters sunk into the ground (models whose base is not flat, so they never float on a slope)
@export var sink := 0.15
## Random lean (degrees). Trees lean a little, logs and rocks a lot.
@export_range(0.0, 90.0, 0.5) var lean := 3.0
## Lean with the slope of the ground (logs, rocks) instead of standing straight up (trees)
@export var follow_ground := false
## Solid: you bump into it (a trunk the width of trunk_radius, or the whole thing for a rock or log)
@export var solid := true
@export var trunk_radius := 0.3
## Draw distance in meters. 0 = by Size.
@export var draw_distance := 0.0


const DRAW := {Size.TREE: 900.0, Size.SHRUB: 220.0, Size.PLANT: 70.0, Size.GROUND: 120.0}


func get_draw_distance() -> float:
	return draw_distance if draw_distance > 0.0 else float(DRAW[size])


## The model keys that exist (empty = use the plain shape)
func usable_models() -> PackedStringArray:
	var out := PackedStringArray()
	for k in models:
		if k != "" and ModelLibrary.has(k):
			out.append(k)
	return out


static func make(p_name: String, p_shape: Shape, p_size: Size, p_density: float, p_models: Array = [], extra: Dictionary = {}) -> FloraLayer:
	var f := FloraLayer.new()
	f.name = p_name
	f.shape = p_shape
	f.size = p_size
	f.density = p_density
	f.models = PackedStringArray(p_models)
	for k in extra:
		f.set(k, extra[k])
	return f
