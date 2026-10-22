class_name DungeonDoor
extends StaticBody3D
## The interactable door of a dungeon: either the entrance out in the world ("Enter Cave") or
## the exit inside ("Leave"). It sits on physics layer 3 (interactable), so the player walks
## through it and only the interaction ray notices it. Made by DungeonEntrancePOIData and
## DungeonBuilder, not meant to be placed by hand.

@export var entrance_id := ""
@export var label := "Enter"
## true = the way out, inside the dungeon
@export var is_exit := false
## Stairs inside a dungeon: the floor they lead to (-1 = not stairs)
@export var target_floor := -1
## Entrance only: where the player is put back when they leave (relative to this door, local space)
@export var return_offset := Vector3(0.0, 0.0, -4.0)

const INTERACTABLE_LAYER := 4  # physics layer 3


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.6, 1.2)
	shape.shape = box
	add_child(shape)


func get_prompt() -> String:
	return label


func interact(_actor: Inventory) -> void:
	var manager := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if manager == null:
		push_error("DungeonDoor: no DungeonManager found. The World node creates one.")
		return
	if target_floor >= 0:
		manager.go_floor(target_floor)
	elif is_exit:
		manager.exit()
	else:
		manager.enter(entrance_id, to_global(return_offset), global_rotation.y)
