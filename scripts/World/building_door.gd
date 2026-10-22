class_name BuildingDoor
extends StaticBody3D
## The front door of a town building. Interacting with it takes the player inside (an instanced
## interior, like a dungeon, see DungeonManager). A door can be locked: the building's key always
## opens it, otherwise the player tries to pick the lock (needs a lockpick, see Locks).
## Made by TownBuilder, not meant to be placed by hand. On physics layer 3 (interactable) only,
## so the player walks through it and only the interaction ray notices it.

const INTERACTABLE_LAYER := 4  # physics layer 3

## The building's id (BuildingPlot.id); also the lock's id and the key's id
@export var building_id := ""
@export var building_name := "House"
## 1..100 (100 = only the key opens it)
@export var lock_level := 10
## Locked until someone changes it (the state is then saved in WorldState)
@export var default_locked := false
## Where the player is put back when they leave (relative to this door, local space)
@export var return_offset := Vector3(0.0, -1.2, -2.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.6, 0.8)
	shape.shape = box
	add_child(shape)


func is_locked() -> bool:
	return Locks.is_locked(building_id, default_locked)


func set_locked(locked: bool) -> void:
	Locks.set_locked(building_id, locked)


func get_prompt() -> String:
	if is_locked():
		return "Enter %s  (Locked: %s)" % [building_name, Locks.tier_name(lock_level)]
	return "Enter %s" % building_name


func get_key() -> ItemData:
	return KeyRing.get_key(building_id, building_name)


func interact(actor: Inventory) -> void:
	var manager := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if manager == null:
		push_error("BuildingDoor: no DungeonManager found. The World node creates one.")
		return
	if manager.is_busy() or manager.is_inside():
		return
	if is_locked() and not try_unlock(actor):
		return
	manager.enter(building_id, to_global(return_offset), global_rotation.y)


## Opens the lock with the key, or by picking it. Returns true if the door is now unlocked.
func try_unlock(actor: Inventory) -> bool:
	if not is_locked():
		return true
	if actor != null and actor.has_item(get_key()):
		set_locked(false)
		Locks.toast(get_tree(), "Unlocked with your key")
		return true
	var result := Locks.try_pick(actor, lock_level, _rng)
	if result == Locks.PickResult.OPENED or result == Locks.PickResult.FAILED:
		var crime := get_tree().get_first_node_in_group("crime") as CrimeManager
		if crime != null:
			crime.on_lock_attempt(building_id)  # a crime if someone sees it
	match result:
		Locks.PickResult.OPENED:
			set_locked(false)
			Locks.toast(get_tree(), "You picked the lock")
			return true
		Locks.PickResult.FAILED:
			Locks.toast(get_tree(), "Your lockpick broke", true)
		Locks.PickResult.NO_PICKS:
			Locks.toast(get_tree(), "Locked. You need the key or a lockpick.", true)
		Locks.PickResult.KEY_ONLY:
			Locks.toast(get_tree(), "This lock can only be opened with its key.", true)
	return false
