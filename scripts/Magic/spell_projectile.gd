class_name SpellProjectile
extends Node3D
## A spell bolt (Target spells). Flies straight, checks what it passes through every physics step
## and hands the hit to its caster's SpellCaster.apply_at(). Goes off where it lands, or in mid air
## when its time runs out.

const LIFETIME := 3.0

var caster: SpellCaster
var spell: SpellData
var power := 1.0
var velocity := Vector3.ZERO
var _age := 0.0
var _exclude: Array[RID] = []
var _mask := MagicHit.LAYER_WORLD | MagicHit.LAYER_ENEMY


static func launch(from: SpellCaster, p_spell: SpellData, p_power: float, origin: Vector3, dir: Vector3, speed: float) -> SpellProjectile:
	var p := SpellProjectile.new()
	p.caster = from
	p.spell = p_spell
	p.power = p_power
	p.velocity = dir.normalized() * speed
	for e in p_spell.effects:
		if StringName(e["id"]) == &"reanimate" or StringName(e["id"]) == &"open_lock":
			p._mask |= MagicHit.LAYER_ITEMS  # corpses and doors live on the interactable layer
	if from.host is CollisionObject3D:
		p._exclude.append((from.host as CollisionObject3D).get_rid())
	var scene := from.get_tree().current_scene
	scene.add_child(p)
	p.global_position = origin + dir.normalized() * 0.7
	p.add_child(SpellFX.orb(p_spell.get_color(), 0.16, 5.0))
	var trail := SpellFX.make_spray(p_spell.get_color())
	trail.amount = 40
	trail.lifetime = 0.3
	(trail.process_material as ParticleProcessMaterial).initial_velocity_min = 0.5
	(trail.process_material as ParticleProcessMaterial).initial_velocity_max = 1.5
	(trail.process_material as ParticleProcessMaterial).spread = 180.0
	trail.emitting = true
	p.add_child(trail)
	return p


func _physics_process(delta: float) -> void:
	_age += delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, _mask, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_go_off(hit.get("collider"), hit["position"])
		return
	global_position = to
	if _age >= LIFETIME:
		_go_off(null, global_position)


func _go_off(collider: Object, at: Vector3) -> void:
	set_physics_process(false)
	if caster != null and is_instance_valid(caster) and caster.is_inside_tree():
		caster.apply_at(spell, power, collider, at)
	else:
		SpellFX.burst(self, at, maxf(spell.get_area(), 0.6), spell.get_color())
	if spell.get_area() <= 0.0:
		SpellFX.burst(self, at, 0.6, spell.get_color())
	queue_free()
