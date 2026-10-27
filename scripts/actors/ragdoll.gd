class_name Ragdoll
extends Node
## Turns a CreatureBody into physics when its owner dies: every big bone becomes a RigidBody3D,
## joined to its parent bone by a ConeTwistJoint3D at the joint, so the body crumples, slides down
## slopes and can be dragged around by any limb (Grabber, Skyrim style).
##
## The parts live on the interactable layer (3, value 4) and only collide with the world, so the
## Interactor can aim at any of them ("Search" / hold to grab) and the player walks through them.
## The Enemy node follows the pelvis around, so saving, distance checks and the loot container all
## still work. A body that was loaded from a save is laid down flat first (lying=true).

const PART_LAYER := 4
const WORLD_MASK := 1

## part bone -> [parent part bone, swing degrees, twist degrees, mass, collision radius, length]
const HUMANOID := {
	"hips": ["", 0.0, 0.0, 12.0, 0.15, 0.2],
	"spine": ["hips", 25.0, 20.0, 18.0, 0.17, 0.5],
	"neck": ["spine", 35.0, 30.0, 5.0, 0.13, 0.28],
	"l_shoulder": ["spine", 75.0, 30.0, 3.0, 0.07, 0.3],
	"l_elbow": ["l_shoulder", 55.0, 10.0, 2.0, 0.06, 0.34],
	"r_shoulder": ["spine", 75.0, 30.0, 3.0, 0.07, 0.3],
	"r_elbow": ["r_shoulder", 55.0, 10.0, 2.0, 0.06, 0.34],
	"l_hip": ["hips", 55.0, 15.0, 7.0, 0.085, 0.42],
	"l_knee": ["l_hip", 55.0, 5.0, 4.0, 0.07, 0.46],
	"r_hip": ["hips", 55.0, 15.0, 7.0, 0.085, 0.42],
	"r_knee": ["r_hip", 55.0, 5.0, 4.0, 0.07, 0.46],
}
const BEAST := {
	"torso": ["", 0.0, 0.0, 30.0, 0.2, 0.9],
	"neck": ["torso", 40.0, 20.0, 4.0, 0.1, 0.3],
	"head": ["neck", 35.0, 20.0, 4.0, 0.12, 0.3],
	"fl_hip": ["torso", 50.0, 10.0, 3.0, 0.06, 0.4],
	"fr_hip": ["torso", 50.0, 10.0, 3.0, 0.06, 0.4],
	"bl_hip": ["torso", 50.0, 10.0, 3.0, 0.06, 0.4],
	"br_hip": ["torso", 50.0, 10.0, 3.0, 0.06, 0.4],
}

var enemy: Enemy
var parts: Dictionary = {}     # bone name -> RigidBody3D
var root_part: RigidBody3D
var _offset := Vector3.ZERO
var _settle := 0.0
var _start_y := 0.0


## Makes the ragdoll. impulse = the killing blow's push (world space).
static func create(e: Enemy, body: CreatureBody, impulse: Vector3 = Vector3.ZERO, lying: bool = false) -> Ragdoll:
	var r := Ragdoll.new()
	r.name = "Ragdoll"
	r.enemy = e
	e.add_child(r)
	if body.model_body != null:
		r._build_model_corpse(body, impulse, lying)
		return r
	if lying:
		# Saved corpses come back flat on their back, a little above the ground
		body.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		body.position = Vector3(0.0, 0.25 * e.body_scale, 0.9 * e.body_scale)
	var table := HUMANOID
	if body.kind == CreatureBody.Kind.BEAST or body.kind == CreatureBody.Kind.CRAWLER:
		table = BEAST
	if body.kind == CreatureBody.Kind.SPIRIT or (body.kind == CreatureBody.Kind.CRAWLER):
		r._build_single(body, impulse)
	else:
		r._build(body, table, impulse)
	return r


func _build(body: CreatureBody, table: Dictionary, impulse: Vector3) -> void:
	var scale_f := body.scale.x
	# 1. A rigid body at every part bone, taking over the bone's meshes (and its non-part children)
	for bone_name in table:
		var bone: Node3D = body.bones.get(bone_name)
		if bone == null:
			continue
		var spec: Array = table[bone_name]
		var rb := RigidBody3D.new()
		rb.name = "Part_" + bone_name
		rb.top_level = true
		rb.collision_layer = PART_LAYER
		rb.collision_mask = WORLD_MASK
		rb.mass = float(spec[3]) * scale_f * scale_f
		rb.linear_damp = 0.4
		rb.angular_damp = 3.0
		rb.can_sleep = true
		rb.continuous_cd = bone_name == "hips" or bone_name == "torso"
		rb.set_meta("ragdoll_owner", enemy)
		enemy.add_child(rb)
		var xf := bone.global_transform.orthonormalized()
		rb.global_transform = xf
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(spec[4]) * scale_f
		cap.height = maxf(float(spec[5]) * scale_f, cap.radius * 2.0 + 0.01)
		shape.shape = cap
		var down := -1.0
		if bone_name == "spine" or bone_name == "neck":
			down = 1.0  # the torso and head reach up from their joint
		if body.kind == CreatureBody.Kind.BEAST and (bone_name == "torso" or bone_name == "neck" or bone_name == "head"):
			shape.rotation = Vector3(PI * 0.5, 0.0, 0.0)  # lies along the body
			shape.position = Vector3(0.0, 0.05, -0.1 if bone_name != "torso" else 0.0)
		else:
			shape.position = Vector3(0.0, down * float(spec[5]) * 0.5, 0.0)
		rb.add_child(shape)
		parts[bone_name] = rb
	# 2. Hand the meshes over: everything under a part bone that is not itself a part
	for bone_name in parts:
		var bone: Node3D = body.bones[bone_name]
		var rb: RigidBody3D = parts[bone_name]
		for c in bone.get_children():
			if c is Node3D and not parts.has(String(c.name)):
				var keep := (c as Node3D).global_transform
				bone.remove_child(c)
				rb.add_child(c)
				(c as Node3D).global_transform = keep
	# 3. Joints at each child's joint position
	for bone_name in parts:
		var spec: Array = table[bone_name]
		var parent_name: String = spec[0]
		if parent_name == "" or not parts.has(parent_name):
			continue
		var j := ConeTwistJoint3D.new()
		j.name = "Joint_" + bone_name
		enemy.add_child(j)
		j.top_level = true
		var at: Vector3 = (parts[bone_name] as RigidBody3D).global_position
		var limb_dir := (parts[bone_name] as RigidBody3D).global_transform.basis.y
		# The twist axis (local X) runs along the limb
		var x_axis := -limb_dir.normalized()
		var helper := Vector3.FORWARD if absf(x_axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var z_axis := x_axis.cross(helper).normalized()
		var y_axis := z_axis.cross(x_axis).normalized()
		j.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), at)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(float(spec[1])))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(float(spec[2])))
		j.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
		j.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
		j.node_a = j.get_path_to(parts[parent_name])
		j.node_b = j.get_path_to(parts[bone_name])
		j.exclude_nodes_from_collision = true
	root_part = parts.get("hips", parts.get("torso"))
	_start_y = root_part.global_position.y if root_part != null else 0.0
	body.visible = false
	body.set_process(false)
	_push(impulse)


# A real model plays its death clip and then lies as one piece, its collision fitted to how it lies
func _build_model_corpse(body: CreatureBody, impulse: Vector3, lying: bool) -> void:
	var mb := body.model_body
	mb.die(lying)
	var rb := RigidBody3D.new()
	rb.name = "Part_remains"
	rb.top_level = true
	rb.collision_layer = PART_LAYER
	rb.collision_mask = WORLD_MASK
	rb.mass = 40.0 * body.scale.x
	rb.linear_damp = 0.6
	rb.angular_damp = 4.0
	rb.lock_rotation = true  # the death clip lays it down; physics only slides and drags it
	rb.set_meta("ragdoll_owner", enemy)
	enemy.add_child(rb)
	rb.global_transform = Transform3D(Basis(Vector3.UP, body.global_rotation.y), body.global_position)
	# A flat box the size of the body lying down (the clip is still playing, so guess from standing)
	var box := ModelLibrary.bounds(mb)
	var s := body.scale.x
	var long := maxf(box.size.y, maxf(box.size.x, box.size.z)) * s
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var lying_down := body.kind == CreatureBody.Kind.HUMANOID
	bs.size = Vector3(maxf(box.size.x * s, 0.3), 0.3 * s, long * 0.85) if lying_down else Vector3(maxf(box.size.x, 0.2) * s, maxf(box.size.y * s * 0.6, 0.2), maxf(box.size.z * s, 0.3))
	shape.shape = bs
	shape.position = Vector3(0.0, bs.size.y * 0.5, 0.0)
	rb.add_child(shape)
	var keep := body.global_transform
	enemy.remove_child(body)
	rb.add_child(body)
	body.global_transform = keep
	body.set_process(false)
	parts["remains"] = rb
	root_part = rb
	_start_y = rb.global_position.y
	_push(impulse)


# Spirits and crawlers just collapse in one piece
func _build_single(body: CreatureBody, impulse: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.name = "Part_remains"
	rb.top_level = true
	rb.collision_layer = PART_LAYER
	rb.collision_mask = WORLD_MASK
	rb.mass = 40.0
	rb.linear_damp = 0.6
	rb.angular_damp = 4.0
	rb.set_meta("ragdoll_owner", enemy)
	enemy.add_child(rb)
	var root_bone := body.get_root_bone()
	rb.global_transform = Transform3D(Basis.IDENTITY, root_bone.global_position)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 0.35, 0.9) * body.scale.x
	shape.shape = box
	rb.add_child(shape)
	var keep := body.global_transform
	enemy.remove_child(body)
	rb.add_child(body)
	body.global_transform = keep
	body.set_process(false)
	if body.kind == CreatureBody.Kind.SPIRIT:
		# The spirit fades into a small glowing heap
		var tw := body.create_tween()
		tw.tween_property(body, "scale", body.scale * Vector3(1.3, 0.15, 1.3), 0.8)
	else:
		body.rotation.z = PI  # on its back, legs up
		body.position.y += 0.2
	parts["remains"] = rb
	root_part = rb
	_start_y = rb.global_position.y
	_push(impulse)


func _push(impulse: Vector3) -> void:
	_offset = Vector3(0.0, -0.3 * enemy.body_scale, 0.0)
	var v := enemy.velocity
	for p in parts.values():
		(p as RigidBody3D).linear_velocity = v
	if impulse.length() > 0.01 and root_part != null:
		root_part.apply_central_impulse(impulse * root_part.mass * 0.35)
		var top: RigidBody3D = parts.get("spine", parts.get("neck"))
		if top != null:
			top.apply_central_impulse(impulse * top.mass * 0.6)


## Everything a grab or a container needs to know: the "interactable" meta on every part
func set_interactable(component: Object) -> void:
	for p in parts.values():
		(p as Node).set_meta("interactable", component)


## The part closest to a point (what you grabbed)
func nearest_part(point: Vector3) -> RigidBody3D:
	var best: RigidBody3D = root_part
	var best_d := INF
	for p in parts.values():
		var rb := p as RigidBody3D
		var d := rb.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = rb
	return best


func total_mass() -> float:
	var m := 0.0
	for p in parts.values():
		m += (p as RigidBody3D).mass
	return m


func is_resting() -> bool:
	for p in parts.values():
		if not (p as RigidBody3D).sleeping and (p as RigidBody3D).linear_velocity.length() > 0.05:
			return false
	return true


## Takes the physics apart again (Reanimate): the parts and joints are freed
func dismantle() -> void:
	for c in enemy.get_children():
		if c is ConeTwistJoint3D or (c is RigidBody3D and c.has_meta("ragdoll_owner")):
			c.queue_free()
	parts.clear()
	root_part = null
	queue_free()


func _physics_process(delta: float) -> void:
	if root_part == null or not is_instance_valid(root_part):
		return
	# The Enemy node (saved position, loot container, distance checks) follows the pelvis
	if root_part.sleeping:
		_settle += delta
		if _settle > 1.0:
			return
	else:
		_settle = 0.0
	var p := root_part.global_position
	if p.y < _start_y - 400.0:  # fell out of the world (dungeons sit far below it, so relative)
		for part in parts.values():
			(part as RigidBody3D).freeze = true
		return
	enemy.global_position = p + _offset
