class_name DungeonEntrancePOIData
extends POIData
## The door of a dungeon, standing in the open world. Interacting with it takes the player
## into an instanced dungeon generated from the Dungeon resource. The dungeon is NOT part of the
## open world, only this entrance is.

enum Shape { CAVE, DOORWAY }

@export var dungeon: DungeonData
## Your own model. Leave empty to use the placeholder Shape below. Its front faces -Z; the
## entrance's door trigger is added for you at the front.
@export var scene: PackedScene
@export var shape: Shape = Shape.CAVE
@export_range(0.3, 4.0, 0.05) var shape_scale := 1.0
@export var color := Color(0.42, 0.40, 0.37)
## Prompt text: "Enter <this>"
@export var enter_name := "Cave"


func build(placed: PlacedPOI, map: WorldMap) -> Node3D:
	var root := Node3D.new()
	if scene != null:
		root.add_child(scene.instantiate())
	else:
		POIBuilder.build_entrance_shape(root, int(shape), shape_scale, color, placed, map)
	var door := DungeonDoor.new()
	door.name = "Door"
	door.entrance_id = placed.id
	door.label = "Enter %s" % enter_name
	door.is_exit = false
	door.position = Vector3(0.0, 1.3, -2.2 * shape_scale)
	door.return_offset = Vector3(0.0, -1.2, -4.5 * shape_scale)
	if root.has_meta("door_at"):
		# a model's own doorway (a Morrowind cave mouth's, up its rock ramp): you come back out in front of it
		door.position = root.get_meta("door_at")
		door.return_offset = Vector3(0.0, -door.position.y + 0.3, -door.position.z - 4.5 * shape_scale)
	root.add_child(door)
	return root
