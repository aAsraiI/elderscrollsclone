class_name WorldItem
extends RigidBody3D
## An item lying in the world. Built entirely in code, no scene needed.
## Spawn with: WorldItem.spawn(item, 1, get_tree().current_scene, Vector3(0, 2, 0))
## Tap interact to take it, hold interact to pick it up and carry it (see Grabber).

@export var item: ItemData
@export var count: int = 1
## Who it belongs to: a building id, or "guild:<id>" (members may take it). Empty = anyone's.
## Taking an owned item is theft (see CrimeManager), exactly like taking from an owned chest.
@export var owner_id := ""
## Set for things a furnished room put on a shelf or table (see RoomDecorator). Such items are
## rebuilt with the room instead of being saved; taking one is remembered under this id.
@export var slot_id := ""
## Lies still (no physics) until it is grabbed, so a room full of things costs nothing
@export var start_frozen := false

## The collision box around the model (zero until it is built)
var size := Vector3.ZERO

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


## A placed item on a shelf or table: frozen, owned (or not), remembered by its slot
static func place(item_data: ItemData, amount: int, parent: Node3D, local_pos: Vector3, slot: String, owner_key: String) -> WorldItem:
	var w := WorldItem.new()
	w.item = item_data
	w.count = amount
	w.slot_id = slot
	w.owner_id = owner_key
	w.start_frozen = true
	w.build_body()
	w.position = local_pos + Vector3(0.0, w.size.y * 0.5 + 0.005, 0.0)  # resting on the surface
	parent.add_child(w)
	return w


## WorldState id of a taken slot
static func taken_key(slot: String) -> String:
	return "taken/" + slot


## Is the player allowed to take things that belong to this owner?
static func may_take(owner_key: String) -> bool:
	if owner_key == "":
		return true
	if owner_key.begins_with("guild:"):
		return Factions.is_member(owner_key.trim_prefix("guild:"))
	return false


func _ready() -> void:
	add_to_group("world_items")
	if slot_id == "":
		add_to_group("persistent")  # SaveManager saves everything in this group
	if start_frozen:
		freeze = true
	# Interactable layer: the interaction ray finds it. Items layer: loose items land on each other
	# (and on the floor, layer 1) instead of sinking into one another. Players, enemies and attack
	# rays still pass through loose items.
	collision_layer = INTERACTABLE_LAYER | ITEM_LAYER
	collision_mask = WORLD_LAYER | ITEM_LAYER
	continuous_cd = true  # small, fast things would otherwise fall through each other
	if item != null:
		mass = maxf(item.weight * count, 0.1)  # heavier stacks push back harder once physics matters
	build_body()


## Builds the model and its collision box (once). place() calls it early, before the item is
## in the tree, so it can be set down on a surface.
func build_body() -> void:
	if size != Vector3.ZERO:
		return
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
	size = box.size


func interact(target_inventory: Inventory) -> void:
	target_inventory.add_item(item, count)
	if slot_id != "":
		var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
		WorldState.set_record(taken_key(slot_id), {"day": clock.day if clock != null else 1})
	if not may_take(owner_id):
		var crime := get_tree().get_first_node_in_group("crime") as CrimeManager
		if crime != null:
			crime.on_taken(item, count)  # theft: witnesses, bounty, the stolen mark
	queue_free()


func get_prompt() -> String:
	if item == null:
		return ""
	var verb := "Take" if may_take(owner_id) else "Steal"
	return "%s %s%s" % [verb, item.display_name, " x%d" % count if count > 1 else ""]


# ---- Knocking things over

## A placed item (frozen on its shelf) comes loose: bumped, hit, or struck by something thrown.
## It stays where its owner put it until then, so a tidy room only gets messy when you make it so.
func wake(push: Vector3 = Vector3.ZERO) -> void:
	if freeze:
		freeze = false
	if push != Vector3.ZERO:
		apply_central_impulse(push * mass)


## Just thrown (Grabber.throw): for a moment it knocks loose whatever it flies into
func on_thrown() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	if not body_entered.is_connected(_on_thrown_hit):
		body_entered.connect(_on_thrown_hit)
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(self) and body_entered.is_connected(_on_thrown_hit):
			body_entered.disconnect(_on_thrown_hit)
			contact_monitor = false)


func _on_thrown_hit(body: Node) -> void:
	if body is WorldItem and body != self:
		(body as WorldItem).wake(linear_velocity * 0.4)


# ---- Grabbing (hold interact). The Interactor / Grabber call these.

func can_grab() -> bool:
	return item != null


## The node that actually moves
func get_grab_body() -> Node3D:
	freeze = false  # a placed item wakes up when you pick it up
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
		"owner": owner_id,
	}


static func restore(data: Dictionary, parent: Node) -> WorldItem:
	var item_data := SaveUtil.path_to_item(String(data.get("item", "")))
	if item_data == null:
		push_warning("WorldItem: saved item '%s' no longer exists." % data.get("item", ""))
		return null
	var w := spawn(item_data, maxi(int(data.get("count", 1)), 1), parent, SaveUtil.array_to_vec3(data.get("pos")))
	w.rotation = SaveUtil.array_to_vec3(data.get("rot"))
	w.owner_id = String(data.get("owner", ""))
	return w
