class_name WorldItem
extends RigidBody3D
## An item lying in the world. Built entirely in code, no scene needed.
## Spawn with: WorldItem.spawn(item, 1, get_tree().current_scene, Vector3(0, 2, 0))
## Tap interact to take it, hold interact to pick it up and carry it (see Grabber).

@export var item: ItemData
@export var count: int = 1

const INTERACTABLE_LAYER := 4  # physics layer 3


static func spawn(item_data: ItemData, amount: int, parent: Node, pos: Vector3) -> WorldItem:
	var w := WorldItem.new()
	w.item = item_data
	w.count = amount
	parent.add_child(w)
	w.global_position = pos
	return w


func _ready() -> void:
	add_to_group("persistent")  # SaveManager saves everything in this group
	# Interactable layer only: the interaction ray finds it, and it still lands on the floor
	# (it collides with layer 1), but players, enemies and attack rays pass through loose items.
	collision_layer = INTERACTABLE_LAYER
	if item != null:
		mass = maxf(item.weight * count, 0.1)  # heavier stacks push back harder once physics matters
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	shape.shape = box
	add_child(shape)

	if item and item.world_scene:
		add_child(item.world_scene.instantiate())
	else:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.3, 0.3)
		mesh.mesh = bm
		add_child(mesh)


func interact(target_inventory: Inventory) -> void:
	target_inventory.add_item(item, count)
	queue_free()


func get_prompt() -> String:
	if item == null:
		return ""
	return "Take %s%s" % [item.display_name, " x%d" % count if count > 1 else ""]


# ---- Grabbing (hold interact). The Interactor / Grabber call these.

func can_grab() -> bool:
	return item != null


## The node that actually moves
func get_grab_body() -> Node3D:
	return self


## &"carry" = lifted and floated in front of the camera
func get_grab_mode() -> StringName:
	return &"carry"


func get_grab_weight() -> float:
	return item.weight * count if item != null else 0.0


# ---- Saving. SaveManager calls these.

func get_persist_data() -> Dictionary:
	var path := SaveUtil.item_to_path(item)
	if path == "":
		return {}  # a runtime-made item can't be saved
	return {
		"type": "world_item",
		"item": path,
		"count": count,
		"pos": SaveUtil.vec3_to_array(global_position),
		"rot": SaveUtil.vec3_to_array(rotation),
	}


static func restore(data: Dictionary, parent: Node) -> WorldItem:
	var item_data := SaveUtil.path_to_item(String(data.get("item", "")))
	if item_data == null:
		push_warning("WorldItem: saved item '%s' no longer exists." % data.get("item", ""))
		return null
	var w := spawn(item_data, maxi(int(data.get("count", 1)), 1), parent, SaveUtil.array_to_vec3(data.get("pos")))
	w.rotation = SaveUtil.array_to_vec3(data.get("rot"))
	return w
