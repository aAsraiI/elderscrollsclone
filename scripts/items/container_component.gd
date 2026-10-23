class_name ContainerComponent
extends Node
## Turns ANY object into something the player can open and loot.
## Add this node as a child of EITHER:
##   - a physics body (StaticBody3D, RigidBody3D, CharacterBody3D, Area3D), or
##   - the mesh / model node that has a physics body as a direct child
##     (what Godot makes with Mesh > Create Collision Shape > Static Body).
## It needs a ContainerUI in the scene (see container_ui.gd).
## Hold interact to drag it around if it is a body (a corpse); tap interact to open it.

signal opened
@warning_ignore("unused_signal")
signal closed  ## handy for playing a lid / door animation

const INTERACTABLE_LAYER := 4  # physics layer 3, same as WorldItem

@export var display_name: String = "Chest"
@export var open_verb: String = "Open"
## What is inside. Rolled once, the first time the container is opened.
@export var contents: Array[LootEntry] = []
## 0 = different every run. Any other number = same loot every time (good for a seeded world:
## set it from your world seed + the container's position).
@export var loot_seed: int = 0
## Can the player drag this around by holding interact? Auto = bodies (anything on a
## CharacterBody3D, like a corpse) can, chests and other static things can't.
## Always on a RigidBody3D (a crate) lets the player carry it instead.
@export_enum("Auto", "Always", "Never") var draggable: int = 0
## Weight of the object itself. What is inside it is added on top. Decides how hard it is to drag.
@export var body_weight: float = 60.0
## Give a placed container a UNIQUE text here (e.g. "chest_castle_cellar") and it remembers
## what is inside across saves. Leave empty for containers that don't need to be remembered.
## Corpses are saved with their enemy instead and don't need this.
@export var save_id: String = ""
## Who this belongs to (a building id). Not empty = taking from it is stealing ("Steal" prompt).
@export var owner_id: String = ""

var inventory: Inventory
## Set before the node enters the tree to use an Inventory that already exists (see attach)
var existing_inventory: Inventory
var _rolled := false


## For things that become containers at runtime, e.g. when an enemy dies:
##   var c := ContainerComponent.attach(self, "Bandit")
##   c.inventory.add_item(sword)
## Pass `existing` to loot a body that already owns an Inventory (the Enemy does this, so
## everything it carried is lootable). `loot_entries` are extra rolled items, as in `contents`.
static func attach(body: Node, name_shown: String = "Chest", verb: String = "Search", existing: Inventory = null, loot_entries: Array[LootEntry] = []) -> ContainerComponent:
	var c := ContainerComponent.new()
	c.display_name = name_shown
	c.open_verb = verb
	c.existing_inventory = existing
	c.contents = loot_entries.duplicate()
	body.add_child(c)
	return c


func _ready() -> void:
	if existing_inventory != null:
		inventory = existing_inventory
	else:
		inventory = Inventory.new()
		inventory.name = "ContainerInventory"
		add_child(inventory)

	if save_id != "":
		if WorldState.has_record(save_id):
			from_dict(WorldState.get_record(save_id))
		inventory.changed.connect(_store_state)
		var quests := get_tree().get_first_node_in_group("quests") as QuestManager
		if quests != null:
			quests.fill_container(self)  # a guild job may have hidden its item in here

	var parent := get_parent()
	var bodies := _find_bodies(parent)
	if bodies.is_empty():
		push_warning("ContainerComponent on '%s': no physics body found. Put this node under a StaticBody3D (or similar) with a CollisionShape3D, or under a node that has one as a direct child." % parent.name)
		return
	for body in bodies:
		# The Interactor looks for this when its ray hits the body
		body.set_meta("interactable", self)
		body.collision_layer |= INTERACTABLE_LAYER


func _find_bodies(parent: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	var parent_body := parent as CollisionObject3D
	if parent_body != null:
		found.append(parent_body)
		return found
	for child in parent.get_children():
		var child_body := child as CollisionObject3D
		if child_body != null:
			found.append(child_body)
	return found


func get_prompt() -> String:
	if owner_id != "":
		return "Steal from %s" % display_name
	return "%s %s" % [open_verb, display_name]


func interact(_actor: Inventory) -> void:
	var ui := get_tree().get_first_node_in_group("container_ui") as ContainerUI
	if ui == null:
		push_error("ContainerComponent: no ContainerUI found. Add a ContainerUI node under the Player.")
		return
	roll_contents()
	if ui.open(self):
		opened.emit()


## Fills the container from its Contents list. Safe to call more than once; only the first call does anything.
func roll_contents() -> void:
	if _rolled:
		return
	_rolled = true
	var rng := RandomNumberGenerator.new()
	if loot_seed != 0:
		rng.seed = loot_seed
	else:
		rng.randomize()
	for entry in contents:
		if entry == null or entry.item == null:
			continue
		if rng.randf() > minf(entry.chance * float(GameRules.get_rule("loot_rate")), 1.0):
			continue
		var item := LootMagic.maybe_enchant(entry.item, rng)
		inventory.add_item(item, rng.randi_range(entry.min_count, maxi(entry.min_count, entry.max_count)) if item == entry.item else 1)
	_store_state()


# ---- Saving

func to_dict() -> Dictionary:
	return {"rolled": _rolled, "inventory": inventory.to_dict()}


## `inventory` is optional: a corpse keeps the inventory its enemy restored
func from_dict(data: Dictionary) -> void:
	_rolled = bool(data.get("rolled", false))
	if data.has("inventory"):
		inventory.from_dict(data["inventory"])


func _store_state() -> void:
	if save_id != "":
		WorldState.set_record(save_id, to_dict())


# ---- Grabbing (hold interact). The Interactor / Grabber call these.

func can_grab() -> bool:
	if get_ragdoll() != null:
		return true
	if draggable == 1:
		return true
	if draggable == 2:
		return false
	for body in _find_bodies(get_parent()):
		if body is CharacterBody3D:
			return true
	return false


## The node that actually moves (the corpse itself, or the mesh the body hangs under)
func get_grab_body() -> Node3D:
	return get_parent() as Node3D


## The physics body of a corpse (see Ragdoll), or null
func get_ragdoll() -> Ragdoll:
	var r := get_parent().get_node_or_null("Ragdoll") as Ragdoll
	return r if r != null and not r.parts.is_empty() else null


func get_grab_mode() -> StringName:
	if get_ragdoll() != null:
		return &"ragdoll"
	return &"carry" if get_parent() is RigidBody3D else &"drag"


func get_grab_weight() -> float:
	var rag := get_ragdoll()
	if rag != null:
		return rag.total_mass() * 0.6 + (inventory.get_total_weight() if inventory != null else 0.0) * 0.5
	return body_weight + (inventory.get_total_weight() if inventory != null else 0.0)
