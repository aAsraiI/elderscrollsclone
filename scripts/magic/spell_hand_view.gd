class_name SpellHandView
extends Node3D
## Your left hand in first person while a spell is in the off hand: it glows in the spell's color,
## swells while charging, throws itself forward when the spell goes off, and streams particles while
## a spray spell runs. Lives under the camera (MagicUI adds it).

const REST := Vector3(-0.32, -0.3, -0.55)

var _book: Spellbook
var _caster: SpellCaster
var _hand: Node3D
var _orb: Node3D
var _orb_mat: StandardMaterial3D
var _light: OmniLight3D
var _spray: GPUParticles3D
var _color := Color.WHITE
var _kick := 0.0
var _time := 0.0


func _ready() -> void:
	var player := get_parent().get_parent().get_parent()
	_book = player.get_node_or_null("Spellbook") as Spellbook
	_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	_hand = Node3D.new()
	add_child(_hand)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.3, 0.25, 0.35)
	_box(_hand, Vector3(0.09, 0.06, 0.32), Vector3(0, -0.02, 0.2), sleeve)  # forearm
	_box(_hand, Vector3(0.09, 0.04, 0.1), Vector3(0, 0, 0), skin)  # palm
	for i in 4:
		_box(_hand, Vector3(0.018, 0.02, 0.07), Vector3(-0.033 + i * 0.022, 0.005, -0.08), skin)
	_box(_hand, Vector3(0.02, 0.02, 0.06), Vector3(0.055, 0.0, -0.02), skin)
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	(_orb as MeshInstance3D).mesh = sm
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_orb_mat.emission_enabled = true
	(_orb as MeshInstance3D).material_override = _orb_mat
	_orb.position = Vector3(0, 0.07, -0.05)
	_hand.add_child(_orb)
	_light = OmniLight3D.new()
	_light.omni_range = 2.5
	_light.light_energy = 0.6
	_light.shadow_enabled = false
	_orb.add_child(_light)
	for c in _hand.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(c as MeshInstance3D).layers = 1
	_hand.position = REST
	if _caster != null:
		_caster.spell_cast.connect(func(_s: SpellData) -> void: _kick = 1.0)
		_caster.cast_failed.connect(func(reason: StringName) -> void:
			if reason == &"magicka":
				Locks.toast(get_tree(), "Not enough magicka", true))


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)


func _process(delta: float) -> void:
	_time += delta
	var spell := _book.get_equipped() if _book != null else null
	var tp := get_parent().get_parent().get_parent().get_node_or_null("ThirdPerson")
	visible = spell != null and not (tp != null and tp.third)
	if spell == null:
		if _spray != null:
			_spray.emitting = false
		return
	if spell.get_color() != _color:
		_color = spell.get_color()
		_orb_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.85)
		_orb_mat.emission = _color
		_light.light_color = _color
		if _spray != null:
			_spray.queue_free()
		_spray = SpellFX.make_spray(_color)
		_hand.add_child(_spray)
		_spray.position = Vector3(0, 0.05, -0.12)
	var charge := _caster.get_charge_ratio() if _caster != null else 0.0
	var channel := _caster != null and _caster.is_channeling()
	_spray.emitting = channel
	_kick = maxf(_kick - delta * 5.0, 0.0)
	var raise := maxf(charge, 1.0 if channel else 0.0)
	var target := REST + Vector3(0.08 * raise, 0.1 * raise + sin(_time * 2.0) * 0.006, -0.12 * raise - 0.18 * _kick)
	_hand.position = _hand.position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
	_hand.rotation = Vector3(0.35 * raise - 0.1, 0.2, 0.1)
	var s := 0.6 + charge * 0.9 + (0.5 if channel else 0.0) + sin(_time * 6.0) * 0.06
	_orb.scale = Vector3.ONE * s
	_light.light_energy = 0.4 + charge * 1.5 + (1.2 if channel else 0.0) + _kick * 2.0
