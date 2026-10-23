class_name SimplePOIData
extends POIData
## A structure with no inside: a camp, a tower, ruins, standing stones, a shrine...
## Until you have real models it builds a simple placeholder out of boxes. Assign a Scene to
## use your own model instead (its origin = the middle of the site, its front faces -Z).

enum Shape { NONE, STANDING_STONES, CAMP, TOWER, RUINS, SHRINE, DRAGON_LAIR }

## Your own model. Leave empty to use the placeholder Shape below.
@export var scene: PackedScene
@export var shape: Shape = Shape.RUINS
## Makes the placeholder bigger or smaller
@export_range(0.3, 4.0, 0.05) var shape_scale := 1.0
@export var color := Color(0.50, 0.49, 0.46)
## Chests inside the structure. They remember what is in them across saves.
@export var containers: Array[POIContainer] = []


func build(placed: PlacedPOI, map: WorldMap) -> Node3D:
	var root := Node3D.new()
	if scene != null:
		root.add_child(scene.instantiate())
	else:
		POIBuilder.build_shape(root, int(shape), shape_scale, color, placed, map)
	POIBuilder.add_containers(root, containers, placed, map)
	return root
