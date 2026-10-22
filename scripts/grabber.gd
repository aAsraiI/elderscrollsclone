class_name Grabber
extends Node
## Skyrim-style "hold the interact key to grab". Created automatically by the Interactor,
## so there is nothing to add in the editor.
##
## Two ways to hold something, picked by the thing being grabbed:
##   CARRY  a loose physics item (WorldItem). Lifted and floated in front of the camera.
##   DRAG   a body (a corpse). Slid along the ground in front of you, never lifted.
##
## Weight decides how hard it is. load = weight / your carry capacity, and
## effort = 1 / (1 + load * slowdown), so 1.0 = effortless and smaller = heavy. Effort controls:
##   - how quickly the object catches up with you (heavy things lag behind)
##   - how much it slows YOUR movement (player.gd asks get_move_speed_multiplier())
##   - drag only: stamina drained per second while you are pulling it
## Items use a small slowdown and bodies a big one, so a sword is nearly free and a corpse is a chore.
##
## Anything grabbable implements (duck typed, like interact / get_prompt):
##   can_grab() -> bool            get_grab_body() -> Node3D      the thing that actually moves
##   get_grab_mode() -> StringName &"carry" or &"drag"            get_grab_weight() -> float

signal grabbed(target: Object)
## reason: &"released" (you let go), &"too_far", &"exhausted", &"lost", &"dead", &"replaced"
signal released(target: Object, reason: StringName)
signal grab_failed(reason: StringName)

const MODE_CARRY := &"carry"
const MODE_DRAG := &"drag"
## A ragdoll corpse: the limb you grabbed is pulled up in front of you and the rest hangs from it
const MODE_RAGDOLL := &"ragdoll"

## Optional. Found on the Player automatically.
@export var stats: Stats

@export_group("Carry (loose items)")
## Meters in front of the camera where the item floats
@export var carry_distance := 1.6
@export var carry_height_offset := -0.15
## How hard the item is pulled toward the hold point (per second)
@export var carry_gain := 14.0
@export var carry_max_speed := 14.0
## How much the load slows you down. Small: items are easy.
@export var carry_slowdown := 0.5
## Dropped if it stays this far from the hold point (stuck behind a wall)
@export var carry_break_distance := 2.5
## When let go, its speed is capped at this. 0 = it just drops straight down where it is.
@export var release_speed_limit := 0.0

@export_group("Drag (bodies)")
## Meters in front of you (on the ground) where the grip point is held
@export var drag_distance := 1.6
@export var drag_gain := 8.0
@export var drag_max_speed := 10.0
## How much the load slows you down. Big: bodies are heavy.
@export var drag_slowdown := 2.0
@export var drag_break_distance := 2.5
## Stamina per second per point of weight, only while the body is actually moving
@export var drag_stamina_per_weight := 0.06
## Swing the body around so it trails behind you (made for the Enemy's fall-over pose)
@export var align_dragged_body := true
@export var drag_turn_speed := 5.0
## Physics layers that count as ground and walls for a dragged body
@export_flags_3d_physics var world_mask: int = 1

@export_group("Ragdoll (corpses)")
## Meters in front of the camera where the grabbed limb is held
@export var ragdoll_distance := 1.5
## How far below the camera it hangs (a body is held low, its feet dragging)
@export var ragdoll_height_offset := -0.45
@export var ragdoll_gain := 12.0
@export var ragdoll_max_speed := 7.0
@export var ragdoll_slowdown := 1.6
@export var ragdoll_break_distance := 2.6
## Stamina per second per kilogram while the body is moving
@export var ragdoll_stamina_per_kg := 0.04

@export_group("General")
## You can never be slowed below this multiplier, however heavy the load
@export var min_move_mult := 0.3
## Seconds the object may stay stretched past its break distance before you let go
@export var strain_tolerance := 0.4

var _player: CharacterBody3D
var _target: Object
var _node: Node3D
var _mode: StringName = MODE_CARRY
var _weight := 0.0
var _strain := 0.0
var _exclude: Array[RID] = []
# carry
var _saved_gravity := 1.0
var _saved_can_sleep := true
# drag
var _local_grab := Vector3.ZERO
var _ground_offset := 0.0
var _has_ground := false
# ragdoll
var _ragdoll: Ragdoll
var _ragdoll_parts: Array[RigidBody3D] = []
var _saved_mass := 0.0


func _ready() -> void:
	_player = _find_player()
	if _player != null:
		_exclude.append(_player.get_rid())
		# player.gd looks for this to slow you down while you hold something
		_player.set_meta("grabber", self)
		if stats == null:
			stats = _player.get_node_or_null("Stats") as Stats


# ---------------------------------------------------------------- public API

func is_holding() -> bool:
	return _target != null


func get_held_target() -> Object:
	return _target


func get_held_weight() -> float:
	return _weight if _target != null else 0.0


## Movement multiplier for the player: 1.0 when empty-handed, lower when holding something heavy
func get_move_speed_multiplier() -> float:
	if _target == null:
		return 1.0
	return clampf(_effort(), min_move_mult, 1.0)


## Starts holding `target` (anything implementing the grab functions above).
## `hit_point` (world space) is where on a body you grabbed it. Returns false if it didn't work.
func grab(target: Object, hit_point: Vector3 = Vector3.INF) -> bool:
	release(&"replaced")
	if target == null or not is_instance_valid(target) or not target.has_method("get_grab_body"):
		return false
	var node := target.get_grab_body() as Node3D
	if node == null or not is_instance_valid(node):
		return false

	var mode: StringName = MODE_DRAG
	if target.has_method("get_grab_mode"):
		mode = target.get_grab_mode()
	if mode == MODE_RAGDOLL:
		var rag: Ragdoll = target.get_ragdoll() if target.has_method("get_ragdoll") else null
		if rag == null or rag.parts.is_empty():
			return false
		_ragdoll = rag
		node = rag.nearest_part(hit_point if hit_point.is_finite() else rag.root_part.global_position)
	if mode == MODE_CARRY and not node is RigidBody3D:
		mode = MODE_DRAG  # only physics bodies can be lifted
	var weight := 10.0
	if target.has_method("get_grab_weight"):
		weight = maxf(float(target.get_grab_weight()), 0.0)

	if mode != MODE_CARRY and stats != null and stats.stamina <= 0.0:
		grab_failed.emit(&"exhausted")
		return false

	_target = target
	_node = node
	_mode = mode
	_weight = weight
	_strain = 0.0
	if _mode == MODE_CARRY:
		_begin_carry()
	elif _mode == MODE_RAGDOLL:
		_begin_ragdoll(hit_point)
	else:
		_begin_drag(hit_point)
	grabbed.emit(target)
	return true


func release(reason: StringName = &"released") -> void:
	if _target == null:
		return
	var held := _target
	if _mode == MODE_CARRY:
		_end_carry()
	elif _mode == MODE_RAGDOLL:
		_end_ragdoll()
	_target = null
	_node = null
	_strain = 0.0
	released.emit(held, reason)


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	if not is_instance_valid(_target) or not is_instance_valid(_node) or not _node.is_inside_tree():
		_target = null  # picked up or deleted by something else, nothing to restore
		_node = null
		return
	if stats != null and stats.is_dead:
		release(&"dead")
		return
	if _mode == MODE_CARRY:
		_tick_carry(delta)
	elif _mode == MODE_RAGDOLL:
		_tick_ragdoll(delta)
	else:
		_tick_drag(delta)


# 1.0 = effortless, smaller = heavy
func _effort() -> float:
	var capacity := stats.get_stat("carry_capacity") if stats != null else 200.0
	var load_ratio := _weight / maxf(capacity, 1.0)
	var slowdown := carry_slowdown if _mode == MODE_CARRY else (ragdoll_slowdown if _mode == MODE_RAGDOLL else drag_slowdown)
	return 1.0 / (1.0 + load_ratio * slowdown)


func _strained(distance: float, limit: float, delta: float) -> bool:
	if distance > limit:
		_strain += delta
	else:
		_strain = maxf(_strain - delta * 2.0, 0.0)
	return _strain >= strain_tolerance


# ---------------------------------------------------------------- carry

func _begin_carry() -> void:
	var rb := _node as RigidBody3D
	_saved_gravity = rb.gravity_scale
	_saved_can_sleep = rb.can_sleep
	rb.gravity_scale = 0.0
	rb.can_sleep = false
	rb.sleeping = false
	if _player != null:
		rb.add_collision_exception_with(_player)  # a held item must never shove you around


func _end_carry() -> void:
	var rb := _node as RigidBody3D
	if rb == null or not is_instance_valid(rb):
		return
	rb.gravity_scale = _saved_gravity
	rb.can_sleep = _saved_can_sleep
	if _player != null:
		rb.remove_collision_exception_with(_player)
	rb.linear_velocity = rb.linear_velocity.limit_length(release_speed_limit)


func _tick_carry(delta: float) -> void:
	var rb := _node as RigidBody3D
	var to := _hold_point() - rb.global_position
	if _strained(to.length(), carry_break_distance, delta):
		release(&"too_far")
		return
	var effort := _effort()
	var desired := (to * carry_gain * effort).limit_length(carry_max_speed * effort)
	rb.linear_velocity = rb.linear_velocity.lerp(desired, clampf(10.0 * effort * delta, 0.0, 1.0))
	rb.angular_velocity = rb.angular_velocity.lerp(Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0))


func _hold_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _player.global_position + Vector3.UP if _player != null else _node.global_position
	return cam.global_position - cam.global_transform.basis.z * carry_distance + Vector3.UP * carry_height_offset


# ---------------------------------------------------------------- ragdoll

func _begin_ragdoll(hit_point: Vector3) -> void:
	var rb := _node as RigidBody3D
	_local_grab = Vector3.ZERO
	if hit_point.is_finite():
		_local_grab = rb.global_transform.affine_inverse() * hit_point
	# The hand holds this limb firmly: it is made heavy while held, so the joints drag the rest of
	# the body after it instead of the other way round
	_saved_mass = rb.mass
	rb.mass = maxf(rb.mass, _ragdoll.total_mass() * 0.8)
	_ragdoll_parts.clear()
	for p in _ragdoll.parts.values():
		var part := p as RigidBody3D
		_ragdoll_parts.append(part)
		part.sleeping = false
		part.can_sleep = false
		if _player != null:
			part.add_collision_exception_with(_player)  # the body must never shove you around


func _end_ragdoll() -> void:
	var held := _node as RigidBody3D
	if held != null and is_instance_valid(held) and _saved_mass > 0.0:
		held.mass = _saved_mass
	_saved_mass = 0.0
	for part in _ragdoll_parts:
		if not is_instance_valid(part):
			continue
		part.can_sleep = true
		if _player != null:
			part.remove_collision_exception_with(_player)
		part.linear_velocity = part.linear_velocity.limit_length(4.0)
	_ragdoll_parts.clear()
	_ragdoll = null


func _tick_ragdoll(delta: float) -> void:
	var rb := _node as RigidBody3D
	var cam := get_viewport().get_camera_3d()
	if cam == null or _player == null:
		release(&"lost")
		return
	var fwd := -cam.global_transform.basis.z
	var hold := cam.global_position + fwd * ragdoll_distance + Vector3.UP * ragdoll_height_offset
	var grip := rb.global_transform * _local_grab
	var error := hold - grip
	if _strained(error.length(), ragdoll_break_distance, delta):
		release(&"too_far")
		return
	var effort := _effort()
	var desired := (error * ragdoll_gain * effort).limit_length(ragdoll_max_speed * effort)
	# A firm hand: push the held limb toward the hold point hard enough to lift what hangs from it
	rb.apply_central_impulse((desired - rb.linear_velocity) * _ragdoll.total_mass() * clampf(8.0 * delta, 0.0, 0.6))
	rb.angular_velocity = rb.angular_velocity.lerp(Vector3.ZERO, clampf(4.0 * delta, 0.0, 1.0))
	# The rest of the body follows along the ground
	var pull := Vector3(desired.x, minf(desired.y, 0.0), desired.z) * 0.5
	for part in _ragdoll_parts:
		if part != rb and is_instance_valid(part):
			part.linear_velocity = part.linear_velocity.lerp(Vector3(pull.x, part.linear_velocity.y, pull.z), clampf(3.0 * delta, 0.0, 1.0))
	if stats != null and ragdoll_stamina_per_kg > 0.0 and rb.linear_velocity.length() > 0.6:
		stats.modify_vital("stamina", -_weight * ragdoll_stamina_per_kg * delta)
		if stats.stamina <= 0.0:
			release(&"exhausted")


# ---------------------------------------------------------------- drag

func _begin_drag(hit_point: Vector3) -> void:
	_local_grab = Vector3.ZERO
	if hit_point.is_finite():
		_local_grab = _node.global_transform.affine_inverse() * hit_point
	var ground := _probe_ground(_node.global_position)
	_has_ground = not ground.is_empty()
	_ground_offset = _node.global_position.y - ground["position"].y if _has_ground else 0.0


func _tick_drag(delta: float) -> void:
	if _player == null:
		release(&"lost")
		return
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var goal := _player.global_position + forward * drag_distance
	var grip := _node.global_transform * _local_grab
	var error := goal - grip
	error.y = 0.0
	if _strained(error.length(), drag_break_distance, delta):
		release(&"too_far")
		return

	var effort := _effort()
	var step := (error * drag_gain * effort * delta).limit_length(drag_max_speed * effort * delta)
	if step.length() > 0.0005:
		_move_dragged(step)
		# Pulling costs stamina in proportion to weight; standing still is free
		if stats != null and drag_stamina_per_weight > 0.0:
			stats.modify_vital("stamina", -_weight * drag_stamina_per_weight * delta)
			if stats.stamina <= 0.0:
				release(&"exhausted")
				return
	_turn_dragged(delta)


# Tries the full step, then sliding along each axis, so you can drag along a wall
func _move_dragged(step: Vector3) -> void:
	var tries: Array[Vector3] = [step, Vector3(step.x, 0.0, 0.0), Vector3(0.0, 0.0, step.z)]
	for s: Vector3 in tries:
		if s.length() < 0.0005 or _blocked(s):
			continue
		var pos := _node.global_position + s
		if _has_ground:
			var ground := _probe_ground(pos)
			if not ground.is_empty():
				pos.y = ground["position"].y + _ground_offset
		_node.global_position = pos
		return


func _turn_dragged(delta: float) -> void:
	if not align_dragged_body:
		return
	var to_player := _player.global_position - _node.global_position
	to_player.y = 0.0
	if to_player.length() < 0.5:
		return
	# The fallen Enemy lies with its head along local +Z, so this points the head at you
	var yaw := atan2(to_player.x, to_player.z)
	_node.rotation.y = lerp_angle(_node.rotation.y, yaw, clampf(drag_turn_speed * delta, 0.0, 1.0))


func _blocked(step: Vector3) -> bool:
	var from := _node.global_position + Vector3.UP * 0.6
	var to := from + step.normalized() * (step.length() + 0.35)
	return not _ray(from, to).is_empty()


func _probe_ground(pos: Vector3) -> Dictionary:
	return _ray(pos + Vector3.UP * 0.8, pos + Vector3.DOWN * 3.0)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, world_mask, _exclude)
	return _node.get_world_3d().direct_space_state.intersect_ray(query)


func _find_player() -> CharacterBody3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as CharacterBody3D
		n = n.get_parent()
	return null
