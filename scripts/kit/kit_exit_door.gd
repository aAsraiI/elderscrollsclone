@tool
class_name KitExitDoor
extends Node3D
## The builder kit: the way out of a dungeon or interior you build by hand. Using it leaves to wherever
## the player came in from (DungeonManager.exit), so it is right in any place. Its back goes against the
## wall and it faces +Z, into the room. Drawn as DoorLook: a door model, a frame and a lantern.

@export var label := "Leave"
@export var lantern := true


func _ready() -> void:
	DoorLook.dress(self, Vector3.ZERO, 0.0, "door/dungeon", lantern)
	if Engine.is_editor_hint():
		return
	var door := DungeonDoor.new()
	door.name = "Door"
	door.is_exit = true
	door.label = label
	add_child(door)
	door.position = Vector3(0, 1.3, 0.4)
