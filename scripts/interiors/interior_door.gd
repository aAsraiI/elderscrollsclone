class_name InteriorDoor
extends StaticBody3D
## A door or gate between two rooms of an interior. Saved by its id (WorldState "door/<id>").
##   locked door  opens with its key (Key Name), or by picking the lock (Lock Level, Security)
##   gate         opens only when a lever somewhere pulls it (DungeonFeature LEVER, target = name)
## Doors open once and stay open.

@export var door_id := ""
@export var key_name := ""
@export var lock_level := 2
@export var is_gate := false
@export var size := Vector2(2.4, 3.2)
## What a gate says when you look at it (a puzzle's hint)
@export var hint := ""

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if is_open():
		queue_free()
		return
	collision_layer = 1 | 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.25)
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(shape)
	if is_gate:
		for i in 7:  # iron bars
			_part(Vector3(0.08, size.y, 0.08), Vector3(-size.x * 0.5 + 0.15 + i * (size.x - 0.3) / 6.0, size.y * 0.5, 0), "iron")
		_part(Vector3(size.x, 0.12, 0.12), Vector3(0, size.y * 0.8, 0), "iron")
	else:
		_part(Vector3(size.x, size.y, 0.18), Vector3(0, size.y * 0.5, 0), "wood_dark")
		_part(Vector3(size.x * 0.9, 0.12, 0.22), Vector3(0, size.y * 0.25, 0), "iron")
		_part(Vector3(size.x * 0.9, 0.12, 0.22), Vector3(0, size.y * 0.75, 0), "iron")
		_part(Vector3(0.12, 0.12, 0.26), Vector3(size.x * 0.35, size.y * 0.48, 0), "gold")


func _part(s: Vector3, at: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = InteriorKit.material(mat)
	mi.position = at
	add_child(mi)


func is_open() -> bool:
	return WorldState.has_record("door/" + door_id)


func get_key() -> ItemData:
	return KeyRing.get_key("door/" + door_id, key_name)


func get_prompt() -> String:
	if is_gate:
		return hint if hint != "" else "A gate. A lever must open it."
	return "Open the locked door (%s)" % Locks.tier_name(lock_level)


func interact(actor: Inventory) -> void:
	if is_gate:
		Locks.toast(get_tree(), "It won't budge. There must be a lever somewhere.", true)
		return
	if actor != null and actor.has_item(get_key()):
		Locks.toast(get_tree(), "Unlocked with the %s" % key_name)
		open()
		return
	match Locks.try_pick(actor, lock_level, _rng):
		Locks.PickResult.OPENED:
			Locks.toast(get_tree(), "You picked the lock")
			open()
		Locks.PickResult.FAILED:
			Locks.toast(get_tree(), "Your lockpick broke", true)
		_:
			Locks.toast(get_tree(), "Locked. Find the %s, or pick it." % key_name, true)


func open() -> void:
	WorldState.set_record("door/" + door_id, {"open": true})
	queue_free()
