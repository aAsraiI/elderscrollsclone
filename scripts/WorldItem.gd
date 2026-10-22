class_name WorldItem
extends RigidBody3D
## An item lying in the world. Built entirely in code, no scene needed.
## Spawn with: WorldItem.spawn(item, 1, get_tree().current_scene, Vector3(0, 2, 0))
## Tap interact to take it, hold interact to pick it up and carry it (see Grabber).

@export var item: ItemData
@export var count: int = 1

const WORLD_LAYER := 1  # physics layer 1
const INTERACTABLE_LAYER := 4  # physics layer 3
const ITEM_LAYER := 32  # physics layer 6 "Items": loose items bump into each other


static func spawn(item_data: ItemData, amount: int, parent: Node, pos: Vector3) -> WorldItem:
	var w := WorldItem.new()
	w.item = item_data
	w.count = amount
	parent.add_child(w)
	w.global_position = pos
	return w


func _ready() -> void:
	add_to_group("persistent")  # SaveManager saves everything in this group
	# Interactable layer: the interaction ray finds it. Items layer: loose items land on each other
	# (and on the floor, layer 1) instead of sinking into one another. Players, enemies and attack
	# rays still pass through loose items.
	collision_layer = INTERACTABLE_LAYER | ITEM_LAYER
	collision_mask = WORLD_LAYER | ITEM_LAYER
	continuous_cd = true  # small, fast things would otherwise fall through each other
	if item != null:
		mass = maxf(item.weight * count, 0.1)  # heavier stacks push back harder once physics matters

	# The model (ItemModels: World Scene, View Scene, or a placeholder), lying down and centered,
	# with a collision box that fits around it
	var model := ItemModels.build_world(item)
	if item != null and item.world_scene == null and (item.item_type == ItemData.ItemType.WEAPON or item.equip_slot == ItemData.EquipSlot.OFF_HAND):
		# hand models stand upright (blade along +Y): lay them on the ground
		model.rotation_degrees = Vector3(90, 0, 0) if item.secondary_action == ItemData.SecondaryAction.BLOCK else Vector3(0, 0, 90)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	var bounds := ItemModels.get_bounds(holder)
	model.position -= bounds.get_center()
	add_child(holder)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3(0.06, 0.06, 0.06))
	shape.shape = box
	add_child(shape)


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
