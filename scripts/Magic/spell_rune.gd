class_name SpellRune
extends Node3D
## A rune spell lying on the ground: a glowing circle that bursts when a foe of its caster steps
## on it (or after 5 minutes). Each caster keeps at most SpellCaster.MAX_RUNES at a time.

const TRIGGER_RADIUS := 1.4
const LIFETIME := 300.0

var caster: SpellCaster
var spell: SpellData
var power := 1.0
var _age := 0.0
var _check := 0.0
var _ring: MeshInstance3D


static func place(from: SpellCaster, p_spell: SpellData, p_power: float, at: Vector3) -> SpellRune:
	var r := SpellRune.new()
	r.caster = from
	r.spell = p_spell
	r.power = p_power
	from.get_tree().current_scene.add_child(r)
	r.global_position = at + Vector3.UP * 0.04
	return r


func _ready() -> void:
	var color := spell.get_color()
	_ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.03
	disc.radial_segments = 24
	disc.rings = 1
	_ring.mesh = disc
	_ring.material_override = SpellFX.glow_material(color, 0.55)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var inner := MeshInstance3D.new()
	var star := TorusMesh.new()
	star.inner_radius = 0.55
	star.outer_radius = 0.7
	star.rings = 24
	star.ring_segments = 4
	inner.mesh = star
	inner.material_override = SpellFX.glow_material(color.lightened(0.3))
	inner.position.y = 0.03
	add_child(inner)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.9
	light.omni_range = 3.0
	light.position.y = 0.4
	add_child(light)


func _physics_process(delta: float) -> void:
	_age += delta
	if _ring != null:
		_ring.rotation.y += delta * 0.8
		var s := 1.0 + sin(_age * 3.0) * 0.05
		_ring.scale = Vector3(s, 1.0, s)
	if _age >= LIFETIME:
		_burst()
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.1
	var owner_body: Node = caster.host if caster != null and is_instance_valid(caster) else null
	for c in MagicHit.creatures_in(get_world_3d(), global_position + Vector3.UP * 0.6, TRIGGER_RADIUS):
		if c == owner_body or MagicHit.friendly(owner_body, c):
			continue
		_burst()
		return


func _burst() -> void:
	set_physics_process(false)
	var radius := maxf(spell.get_area(), 3.0)
	var center := global_position + Vector3.UP * 0.5
	if caster != null and is_instance_valid(caster) and caster.is_inside_tree():
		SpellFX.burst(caster, center, radius, spell.get_color())
		caster.apply_area(spell, power, center, radius, null)
	queue_free()
