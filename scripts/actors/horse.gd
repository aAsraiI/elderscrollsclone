class_name Horse
extends CharacterBody3D
## Your horse. Bought as a Horse Deed (general stores and provisioners); using the deed brings
## the horse to you. E on it to ride (E again, or jumping off with Space while still, to get down).
## While you ride, the horse carries you: WASD steer it, Shift gallops (the horse has its own
## stamina), the mouse turns your view. It has a four-legged CreatureBody like the wolves.
## Its place is saved (WorldState "horse"); it waits where you left it.

const LAYER := 1 | 4

var state := 0
var combat: MeleeCombat = null
var equipment: Equipment = null
var display_name := "Horse"
var body_scale := 1.7
var placeholder_color := Color(0.42, 0.28, 0.16)
var stamina := 100.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _goal := Vector3.INF


static func spawn_at(parent: Node, pos: Vector3, yaw: float = 0.0) -> Horse:
	var h := Horse.new()
	h.name = "Horse"
	h.position = pos
	parent.add_child(h)
	h.global_position = pos
	h.rotation.y = yaw
	return h


func _ready() -> void:
	add_to_group("horse")
	collision_layer = LAYER
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 2.6
	shape.shape = cap
	shape.rotation.x = PI * 0.5
	shape.position = Vector3(0, 1.1, 0)
	add_child(shape)
	var body := CreatureBody.build_for(self, CreatureBody.Kind.BEAST, 4242)
	add_child(body)


func get_prompt() -> String:
	return "Ride your horse"


func interact(_actor: Inventory) -> void:
	var rider := get_tree().get_first_node_in_group("player").get_node_or_null("Rider") as Rider
	if rider != null:
		if rider.is_riding():
			rider.dismount()
		else:
			rider.mount(self)


## Runs to a point (called by the deed)
func come_to(pos: Vector3) -> void:
	_goal = pos


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if has_meta("ridden"):
		return  # the Rider moves it
	stamina = minf(stamina + delta * 8.0, 100.0)
	var v := Vector3.ZERO
	if _goal.is_finite():
		var to := _goal - global_position
		to.y = 0.0
		if to.length() < 3.0:
			_goal = Vector3.INF
		else:
			v = to.normalized() * 9.0
			global_rotation.y = lerp_angle(global_rotation.y, atan2(-to.x, -to.z), clampf(delta * 5.0, 0.0, 1.0))
	velocity.x = move_toward(velocity.x, v.x, 20.0 * delta)
	velocity.z = move_toward(velocity.z, v.z, 20.0 * delta)
	move_and_slide()
