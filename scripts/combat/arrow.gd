class_name Arrow
extends Node3D
## An arrow in flight: drops under gravity, checks what it passes through every physics step,
## hurts the first creature it meets (through its MeleeCombat, so blocking and armor work) or
## sticks where it hits the world. A stuck player arrow can often be picked up again.

const GRAVITY := 7.0
const LIFETIME := 6.0
const RECOVER_CHANCE := 0.5
## 1.27: thrown weapons are found again more often (and sometimes after a hit)
const THROWN_RECOVER := 0.85
const THROWN_RECOVER_HIT := 0.6

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
	if item != null and item.is_thrown:
		_build_thrown()
		return
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.42) if item != null and item.is_bolt else Vector3(0.02, 0.02, 0.7)  # 1.27: bolts are short and thick
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
	_world_react(at)  # 1.24: a fire arrow lights oil and dry grass; frost and shock arrows too
	var target: Node = null
	if collider != null and collider.has_meta("damageable"):
		var d: Variant = collider.get_meta("damageable")
		if is_instance_valid(d) and d.has_method("take_damage"):
			target = d
	if target != null:
		if shooter != null and is_instance_valid(shooter):
			shooter.on_arrow_hit(self, target, at)
		_drop_thrown(at, THROWN_RECOVER_HIT)  # 1.27: a knife or axe falls where it struck
		queue_free()
		return
	# Stuck in the world
	global_position = at
	_stuck = true
	_age = 0.0
	if shooter != null and is_instance_valid(shooter) and shooter.host != null and shooter.host.is_in_group("player") \
			and shooter.npc_arrow == null and randf() < (THROWN_RECOVER if item.is_thrown else RECOVER_CHANCE):
		var w := WorldItem.spawn(item, 1, get_tree().current_scene, at + Vector3.UP * 0.1)
		if w != null:
			w.freeze = true
		queue_free()


func _world_react(at: Vector3) -> void:
	if item == null or not is_inside_tree():
		return
	var ws := WorldSurfaces.of(get_tree())
	if ws == null:
		return
	for e in item.enchant_effects + item.magic_effects:
		match String(e.get("id", "")):
			"fire_damage":
				ws.react(at, &"fire", 1.0, shooter.host if shooter != null and is_instance_valid(shooter) else null, 0.8)
			"frost_damage":
				ws.react(at, &"frost", 1.0, null, 0.8)
			"shock_damage":
				ws.react(at, &"shock", 1.0, null, 0.8)


# 1.27: a throwing knife, a hand axe or a javelin, spinning (knives and axes) or point first
func _build_thrown() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.62, 0.66)
	metal.metallic = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.18)
	var spin := Node3D.new()
	spin.name = "Spin"
	add_child(spin)
	match String(item.animation_set):
		"spear":
			_part(spin, Vector3(0.03, 0.03, 1.5), Vector3.ZERO, wood)
			_part(spin, Vector3(0.05, 0.02, 0.18), Vector3(0, 0, -0.82), metal)
		"waraxe":
			_part(spin, Vector3(0.03, 0.03, 0.45), Vector3.ZERO, wood)
			_part(spin, Vector3(0.02, 0.16, 0.12), Vector3(0, 0.06, -0.2), metal)
		_:
			_part(spin, Vector3(0.012, 0.03, 0.18), Vector3(0, 0, -0.05), metal)
			_part(spin, Vector3(0.02, 0.03, 0.09), Vector3(0, 0, 0.09), wood)
	_face()


func _part(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


func _process(delta: float) -> void:
	if _stuck or item == null or not item.is_thrown or String(item.animation_set) == "spear":
		set_process(false)
		return
	var spin := get_node_or_null("Spin") as Node3D
	if spin != null:
		spin.rotate_x(-delta * 18.0)


func _drop_thrown(at: Vector3, chance: float) -> void:
	if item == null or not item.is_thrown or shooter == null or not is_instance_valid(shooter) or shooter.host == null \
			or not shooter.host.is_in_group("player") or shooter.npc_arrow != null or randf() >= chance:
		return
	WorldItem.spawn(item, 1, get_tree().current_scene, at + Vector3.UP * 0.2)
