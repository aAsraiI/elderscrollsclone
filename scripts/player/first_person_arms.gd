class_name FirstPersonArms
extends Node3D
## Your own arms in first person, Morrowind's way (1.17): the first-person arms of your race and sex from
## your Morrowind import ("fp/<race>_<m|f>", MwImport.FP_RACES), placed where Morrowind's eye is and
## playing its first-person clips from what you are doing: the idle for your weapon, its chop, slash or
## thrust in step with each attack, the block, the cast. Your weapon is in the weapon bone, your shield on
## the shield bone. Without the import there are no arms and the ViewModel draws the weapons as before.

## Clips for each moment (Morrowind's first-person names)
const IDLE := {"one": "Idle1h", "two": "Idle2c", "spear": "Idle2w", "none": "Idlehh"}
const ATTACKS := {"one": ["WeaponOneHand_Chop", "WeaponOneHand_Slash", "WeaponOneHand_Thrust"],
	"two": ["WeaponTwoHand_Chop", "WeaponTwoHand_Slash"], "spear": ["WeaponTwoWide_Chop"], "none": ["HandToHand_Chop", "HandToHand_Slash"]}

## true while the arms are shown (the ViewModel then hides its own weapons)
var active := false

var _player: Node3D
var _camera: Camera3D
var _combat: MeleeCombat
var _equipment: Equipment
var _model: Node3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _weapon_holder: Node3D
var _shield_holder: Node3D
var _shown_main: ItemData
var _shown_off: ItemData
var _placed := false
var _clip := ""
var _attack_clip := ""


static func attach(camera: Camera3D) -> FirstPersonArms:
	var a := FirstPersonArms.new()
	a.name = "FirstPersonArms"
	camera.add_child(a)
	return a


func _ready() -> void:
	_camera = get_parent() as Camera3D
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or _camera == null:
		return
	_combat = _player.get_node_or_null("MeleeCombat") as MeleeCombat
	_equipment = _player.get_node_or_null("Equipment") as Equipment
	var c: Dictionary = _player.get_meta("character", {})
	var key := "fp/%s_%s" % [String(c.get("race", "heartlander")), "f" if int(c.get("sex", 0)) == 1 else "m"]
	if not ModelLibrary.has(key):
		key = "fp/heartlander_m"
	if not ModelLibrary.has(key):
		return
	_model = ModelLibrary.instance(key)
	if _model == null:
		return
	add_child(_model)
	for g in _model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(g as GeometryInstance3D).layers = 1
	_skel = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skel == null or _anim == null:
		_model.queue_free()
		return
	_weapon_holder = _holder("Weapon Bone")
	_shield_holder = _holder("Shield Bone")
	active = true


# A node on a bone that undoes the skeleton's scale, so things hang there at their real size
func _holder(bone: String) -> Node3D:
	if _skel.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skel.add_child(att)
	var h := Node3D.new()
	var s := ModelLibrary.relative_transform(self, _skel).basis.get_scale()
	h.scale = Vector3.ONE / s.max(Vector3.ONE * 0.00001)
	att.add_child(h)
	return h


func _process(delta: float) -> void:
	if not active or _combat == null:
		return
	visible = _combat.is_alive() and not _third_person()
	if not visible:
		return
	if not _placed:
		_place()
	_dress()
	_animate(delta)


# Morrowind's eye (its "Camera" bone) on ours: the arms then sit where they did in Morrowind
func _place() -> void:
	var cam_bone := _skel.find_bone("Camera")
	if cam_bone < 0:
		cam_bone = _skel.find_bone("Bip01 Head")
	if cam_bone < 0:
		_placed = true
		return
	var eye := global_transform.affine_inverse() * (_skel.global_transform * _skel.get_bone_global_rest(cam_bone).origin)
	_model.position -= eye
	_placed = true


# The weapon and shield in hand follow what is equipped
func _dress() -> void:
	var main := _equipment.get_main_hand() if _equipment != null else null
	var off := _equipment.get_off_hand() if _equipment != null else null
	if main != _shown_main and _weapon_holder != null:
		_shown_main = main
		for c in _weapon_holder.get_children():
			c.queue_free()
		if main != null:
			var m := _held_model(main)
			if m != null:
				_weapon_holder.add_child(m)
	if off != _shown_off and _shield_holder != null:
		_shown_off = off
		for c in _shield_holder.get_children():
			c.queue_free()
		if off != null and off.secondary_action == ItemData.SecondaryAction.BLOCK and off.item_type != ItemData.ItemType.WEAPON:
			var s := _held_model(off)
			if s != null:
				_shield_holder.add_child(s)


# Morrowind's own weapon or shield model as made for the bone; anything else built for the view
func _held_model(item: ItemData) -> Node3D:
	var key := ModelLibrary.first(ItemModels.model_keys(item))
	if key != "" and String(ModelLibrary.entry(key).get("source", "")) == "morrowind":
		var raw := ModelLibrary.instance(key)
		if raw != null and raw.get_child_count() > 0:
			(raw.get_child(0) as Node3D).rotation = Vector3.ZERO  # as authored for the bone (no display turn)
		return raw
	return ItemModels.build_view(item)


func _style() -> String:
	var w := _equipment.get_main_hand() if _equipment != null else null
	if w == null:
		return "none"
	if String(w.animation_set) == "spear":
		return "spear"
	return "two" if w.two_handed else "one"


func _animate(_delta: float) -> void:
	var style := _style()
	var phase := _combat.get_phase()
	var want := String(IDLE[style])
	var at := -1.0
	if phase != MeleeCombat.Phase.IDLE and _combat.is_attacking():
		if _attack_clip == "":
			var list: Array = ATTACKS[style]
			_attack_clip = String(list[_combat.get_combo_step() % list.size()])
		want = _attack_clip
		# windup, strike and recovery run through the clip in step with the swing
		var p := _combat.get_phase_progress()
		match phase:
			MeleeCombat.Phase.WINDUP:
				at = p * 0.45  # the arm draws back
			MeleeCombat.Phase.ACTIVE:
				at = 0.45 + p * 0.35  # the strike (Morrowind's hit comes about three quarters in)
			_:
				at = 0.8 + p * 0.2
	else:
		_attack_clip = ""
		if _combat.is_blocking() and _anim.has_animation("Shield_Block"):
			want = "Shield_Block"
			at = 0.27  # held up
		elif _player.has_node("SpellCaster") and _player.get_node("SpellCaster").get("casting") == true and _anim.has_animation("SpellCast_Target"):
			want = "SpellCast_Target"
	if not _anim.has_animation(want):
		want = "Idle"
	if want != _clip:
		_clip = want
		_anim.play(want, 0.12)
	if at >= 0.0:
		_anim.pause()
		_anim.seek(_anim.current_animation_length * clampf(at, 0.0, 1.0), true)
	elif not _anim.is_playing():
		_anim.play(want)


func _third_person() -> bool:
	var tp := _player.get_node_or_null("ThirdPerson") as ThirdPerson
	return tp != null and tp.third
