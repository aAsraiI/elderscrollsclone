class_name Arrow
extends Node3D
## An arrow in flight: drops under gravity, checks what it passes through every physics step,
## hurts the first creature it meets (through its MeleeCombat, so blocking and armor work) or
## sticks where it hits the world. A stuck player arrow can often be picked up again.

const GRAVITY := 7.0
const LIFETIME := 6.0
const RECOVER_CHANCE := 0.5

var shooter: RangedCombat
var item: ItemData
var bow: ItemData
var damage := 10.0
var velocity := Vector3.ZERO
var _age := 0.0
var _exclude: Array[RID] = []
var _stuck := false


static func launch(from: RangedCombat, p_item: ItemData, origin: Vector3, vel: Vector3, dmg: float, p_bow: ItemData) -> Arrow:
	var a := Arrow.new()
	a.shooter = from
	a.item = p_item
	a.bow = p_bow
	a.damage = dmg
	a.velocity = vel
	if from.host is CollisionObject3D:
		a._exclude.append((from.host as CollisionObject3D).get_rid())
	from.get_tree().current_scene.add_child(a)
	a.global_position = origin
	a._build()
	return a


func _build() -> void:
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, 0.7)
	shaft.mesh = bm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.38, 0.22)
	shaft.material_override = wood
	add_child(shaft)
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.04, 0.04, 0.08)
	tip.mesh = tm
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.6, 0.6, 0.65)
	metal.metallic = 0.6
	tip.material_override = metal
	tip.position.z = -0.38
	add_child(tip)
	_face()


func _face() -> void:
	if velocity.length() > 0.1:
		var up := Vector3.UP if absf(velocity.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		look_at(global_position + velocity, up)


func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck:
		if _age > 30.0:
			queue_free()
		return
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 16, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_hit(hit.get("collider"), hit["position"])
		return
	global_position = to
	_face()
	if _age > LIFETIME:
		queue_free()


func _hit(collider: Object, at: Vector3) -> void:
	var target: Node = null
	if collider != null and collider.has_meta("damageable"):
		var d: Variant = collider.get_meta("damageable")
		if is_instance_valid(d) and d.has_method("take_damage"):
			target = d
	if target != null:
		if shooter != null and is_instance_valid(shooter):
			shooter.on_arrow_hit(self, target, at)
		queue_free()
		return
	# Stuck in the world
	global_position = at
	_stuck = true
	_age = 0.0
	if shooter != null and is_instance_valid(shooter) and shooter.host != null and shooter.host.is_in_group("player") \
			and shooter.npc_arrow == null and randf() < RECOVER_CHANCE:
		var w := WorldItem.spawn(item, 1, get_tree().current_scene, at + Vector3.UP * 0.1)
		if w != null:
			w.freeze = true
		queue_free()
