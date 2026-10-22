class_name Rider
extends Node
## Riding (see Horse). Under the Player: while riding you sit in the saddle, the horse moves, and
## you can't fight. Also owns your horse: brings it back after a load and remembers where it is.

const DEED := "res://scripts/Resources/Misc/horse_deed.tres"
const WALK := 6.0
const GALLOP := 13.0

var horse: Horse
var _player: CharacterBody3D
var _save_timer := 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_restore.call_deferred()


func is_riding() -> bool:
	return horse != null and is_instance_valid(horse) and horse.has_meta("ridden")


static func owns_horse() -> bool:
	return WorldState.has_record("horse")


## The deed: the first use gives you the horse, later uses call it to you
func use_deed() -> void:
	var p := _player.global_position - _player.global_transform.basis.z * 4.0 + Vector3.UP * 0.5
	if horse == null or not is_instance_valid(horse):
		horse = Horse.spawn_at(get_tree().current_scene, p, _player.rotation.y)
		_remember()
		Locks.toast(get_tree(), "Your horse is here. Press E on it to ride.")
		return
	if horse.global_position.distance_to(_player.global_position) > 150.0:
		var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
		if world != null:
			world.ensure_area_loaded(p)
		horse.global_position = p
	else:
		horse.come_to(_player.global_position)
	Locks.toast(get_tree(), "You whistle for your horse")


func mount(h: Horse) -> void:
	if is_riding() or _player.has_meta("beast_form"):
		return
	horse = h
	h.set_meta("ridden", true)
	_player.set_meta("riding", h)
	h.add_collision_exception_with(_player)
	_player.add_collision_exception_with(h)


func dismount() -> void:
	if not is_riding():
		return
	var h := horse
	h.remove_meta("ridden")
	_player.remove_meta("riding")
	var side := h.global_transform.basis.x * 1.4
	_player.global_position = h.global_position + side + Vector3.UP * 0.6
	_player.velocity = Vector3.ZERO
	h.velocity = Vector3.ZERO
	h.remove_collision_exception_with(_player)
	_player.remove_collision_exception_with(h)
	_remember()


func _unhandled_input(event: InputEvent) -> void:
	if is_riding() and event.is_action_pressed("interact") and not get_tree().paused:
		dismount()
		get_viewport().set_input_as_handled()


## player.gd calls this instead of walking
func ride(delta: float, input_dir: Vector2, gallop: bool) -> void:
	var h := horse
	# The horse turns with your view
	var yaw := _player.rotation.y
	h.rotation.y = lerp_angle(h.rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
	var fwd := -h.global_transform.basis.z
	var right := h.global_transform.basis.x
	var speed := WALK
	if gallop and h.stamina > 1.0 and input_dir.y < 0.0:
		speed = GALLOP
		h.stamina -= 12.0 * delta
	else:
		h.stamina = minf(h.stamina + 6.0 * delta, 100.0)
	var want := (fwd * -input_dir.y + right * input_dir.x * 0.4) * speed
	h.velocity.x = move_toward(h.velocity.x, want.x, 14.0 * delta)
	h.velocity.z = move_toward(h.velocity.z, want.z, 14.0 * delta)
	if Input.is_action_just_pressed("jump") and h.is_on_floor():
		h.velocity.y = 5.0
	h.move_and_slide()
	_player.global_position = h.global_position + Vector3.UP * 1.25
	_player.velocity = Vector3.ZERO


func _process(delta: float) -> void:
	_save_timer -= delta
	if _save_timer <= 0.0 and horse != null and is_instance_valid(horse):
		_save_timer = 5.0
		_remember()


func _remember() -> void:
	if horse != null and is_instance_valid(horse):
		WorldState.set_record("horse", {"pos": SaveUtil.vec3_to_array(horse.global_position), "yaw": horse.rotation.y})


func _restore() -> void:
	if not owns_horse() or (horse != null and is_instance_valid(horse)):
		return
	await get_tree().create_timer(1.0, false).timeout
	if horse != null and is_instance_valid(horse):
		return
	var rec := WorldState.get_record("horse")
	var pos := SaveUtil.array_to_vec3(rec.get("pos"), _player.global_position)
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null:
		world.ensure_area_loaded(pos)
	horse = Horse.spawn_at(get_tree().current_scene, pos + Vector3.UP * 0.5, float(rec.get("yaw", 0.0)))
