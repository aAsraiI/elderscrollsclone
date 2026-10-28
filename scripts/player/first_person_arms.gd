class_name FirstPersonArms
extends Node3D
## Your own arms in first person (1.17, Skyrim-style in 1.18): the first-person arms of your race and sex
## from your Morrowind import ("fp/<race>_<m|f>", MwImport.FP_RACES), placed where Morrowind's eye is.
## Each arm is animated on its own, so the hands can do different things at once:
##   idles, finger grips and the shield block are Morrowind's own first-person clips; the left hand
##   always keeps Morrowind's own left-hand poses (its fist when it holds something), never a mirror
##   of the right's, and holds a weapon where its fist closes (_mirrored_grip)
##   everything else is our own: each move is a path the hand or weapon takes in front of you (SWINGS)
##   and the arm reaches along it (two-bone IK): a diagonal slash and a backhand that alternate, an
##   overhead power chop, wide two-handed sweeps, spear thrusts, punches, weapon blocks; the off hand
##   swings the mirror of them, and a two-handed weapon's second hand stays on the grip. The bow is
##   held out in the left hand while the right draws the string to the cheek; a hand holding a spell is
##   raised palm out, draws back as it charges and thrusts out as it goes off (both hands together for
##   a dual cast), glowing in the spell's colour.
## The arms sway as you look around and bob as you walk. Without the import there are no arms and the
## ViewModel draws the weapons as before.

## Morrowind's idle for each hand
const IDLE := {"one": "Idle1h", "two": "Idle2c", "spear": "Idle2w", "none": "Idlehh", "spell": "Idlespell"}
## Seconds into Morrowind's shield block (from its text keys) where the shield is up
const BLOCK_HELD := 0.333
const BLEND := 0.12
## The left hand's fingers whenever it holds something: Morrowind's own left fist (from its bare-fist idle;
## the left hand is never mirrored from the right, which would bend it out of shape)
const LEFT_FIST := "Idlehh"
## Where the second hand holds a two-handed weapon: this far down the grip from the first (m)
const GRIP_2H := 0.17
const GRIP_SPEAR := -0.2  # ahead of the back hand

## The weapon's path for each move, in front of the eye (metres; x right, y up, -z ahead), as if in the
## right hand (the left hand makes the mirror image). The blade turns about n (degrees from d, the
## blade's direction at the moment of the hit); its edge leads. keys: [time 0..1, grip, angle]; the
## windup ends at 0.35, the strike runs to 0.65, then the recovery.
const SWINGS := {
	# a light swing: right shoulder down across to the left hip
	"slash": {"n": Vector3(-0.89, 0.29, 0.36), "d": Vector3(-0.3, 0.2, -0.93), "keys": [
		[0.0, Vector3(0.26, -0.14, -0.36), -100.0], [0.35, Vector3(0.34, 0.0, -0.32), -105.0],
		[0.5, Vector3(0.08, -0.10, -0.44), 0.0], [0.65, Vector3(-0.12, -0.34, -0.32), 75.0],
		[1.0, Vector3(0.10, -0.30, -0.38), 60.0]]},
	# the next light swing: back across from the left shoulder to the right
	"backhand": {"n": Vector3(-0.25, -0.965, -0.07), "d": Vector3(-0.1, 0.1, -0.99), "keys": [
		[0.0, Vector3(0.10, -0.18, -0.38), -90.0], [0.35, Vector3(-0.10, -0.02, -0.34), -105.0],
		[0.5, Vector3(0.12, -0.16, -0.44), 0.0], [0.65, Vector3(0.36, -0.26, -0.26), 80.0],
		[1.0, Vector3(0.24, -0.26, -0.36), 60.0]]},
	# a power attack: raised high over the head and brought straight down
	"power": {"n": Vector3(-1, 0, 0), "d": Vector3(0, 0.05, -1), "keys": [
		[0.0, Vector3(0.20, -0.12, -0.34), -110.0], [0.35, Vector3(0.16, 0.14, -0.26), -140.0],
		[0.5, Vector3(0.06, -0.04, -0.47), -10.0], [0.65, Vector3(0.02, -0.36, -0.36), 70.0],
		[1.0, Vector3(0.12, -0.30, -0.36), 50.0]]},
	# two-handed: a wide sweep right to left, and back (kept within reach of the second hand)
	"sweep": {"n": Vector3(0, 0.96, 0.25), "d": Vector3(-0.1, 0.25, -0.96), "two": GRIP_2H, "keys": [
		[0.0, Vector3(0.14, -0.18, -0.38), -90.0], [0.35, Vector3(0.16, -0.08, -0.36), -115.0],
		[0.5, Vector3(0.0, -0.16, -0.44), 0.0], [0.65, Vector3(-0.14, -0.22, -0.34), 80.0],
		[1.0, Vector3(0.06, -0.24, -0.38), 60.0]]},
	"sweep_back": {"n": Vector3(0, -0.96, -0.25), "d": Vector3(0.1, 0.25, -0.96), "two": GRIP_2H, "keys": [
		[0.0, Vector3(0.10, -0.18, -0.38), -90.0], [0.35, Vector3(-0.10, -0.08, -0.36), -115.0],
		[0.5, Vector3(0.08, -0.16, -0.44), 0.0], [0.65, Vector3(0.24, -0.22, -0.32), 80.0],
		[1.0, Vector3(0.14, -0.24, -0.38), 60.0]]},
	"power_2h": {"n": Vector3(-1, 0, 0), "d": Vector3(0, 0.05, -1), "two": GRIP_2H, "keys": [
		[0.0, Vector3(0.12, -0.16, -0.36), -110.0], [0.35, Vector3(0.04, 0.06, -0.30), -140.0],
		[0.5, Vector3(0.02, -0.06, -0.46), -10.0], [0.65, Vector3(0.0, -0.32, -0.38), 70.0],
		[1.0, Vector3(0.08, -0.26, -0.38), 50.0]]},
	# spears: the front hand ahead on the shaft; drawn back and driven straight ahead
	"thrust": {"n": Vector3(-1, 0, 0), "d": Vector3(0, 0.1, -1), "two": GRIP_SPEAR, "keys": [
		[0.0, Vector3(0.12, -0.20, -0.26), -10.0], [0.35, Vector3(0.12, -0.18, -0.16), -15.0],
		[0.5, Vector3(0.06, -0.14, -0.42), 0.0], [0.65, Vector3(0.06, -0.14, -0.42), 0.0],
		[1.0, Vector3(0.12, -0.20, -0.26), -10.0]]},
	# fists: a straight punch, and a heavier one from further back
	"punch": {"n": Vector3(-1, 0, 0), "d": Vector3(0, 0.6, -0.8), "keys": [
		[0.0, Vector3(0.20, -0.22, -0.32), 0.0], [0.35, Vector3(0.22, -0.20, -0.22), 10.0],
		[0.5, Vector3(0.06, -0.12, -0.48), -20.0], [0.65, Vector3(0.06, -0.12, -0.46), -20.0],
		[1.0, Vector3(0.20, -0.22, -0.32), 0.0]]},
	"haymaker": {"n": Vector3(0, 1, 0), "d": Vector3(-0.3, 0.6, -0.74), "keys": [
		[0.0, Vector3(0.22, -0.22, -0.30), -30.0], [0.35, Vector3(0.30, -0.16, -0.18), -50.0],
		[0.5, Vector3(0.04, -0.12, -0.48), 0.0], [0.65, Vector3(-0.06, -0.14, -0.44), 20.0],
		[1.0, Vector3(0.20, -0.22, -0.32), 0.0]]},
	# blocks, held: the blade across you, edge out; a two-handed weapon held high and level
	"block": {"n": Vector3(-0.47, -0.88, 0), "d": Vector3(-0.85, 0.45, -0.25), "keys": [
		[0.0, Vector3(0.12, -0.12, -0.36), 0.0]]},
	"block_2h": {"n": Vector3(-0.45, 0.89, 0), "d": Vector3(0.88, 0.45, -0.15), "two": GRIP_2H, "keys": [
		[0.0, Vector3(0.02, -0.10, -0.38), 0.0]]},
	"block_spear": {"n": Vector3(-0.45, 0.89, 0), "d": Vector3(0.88, 0.45, -0.15), "two": GRIP_SPEAR, "keys": [
		[0.0, Vector3(0.10, -0.10, -0.38), 0.0]]},
	# a hand holding a spell, palm out: at rest, drawn back as it charges (0.35), thrust out as it goes off
	"spell": {"n": Vector3(0.035, -0.635, -0.63), "d": Vector3(-0.85, 0.35, -0.4), "keys": [
		[0.0, Vector3(0.20, -0.19, -0.42), 0.0], [0.35, Vector3(0.22, -0.11, -0.36), 0.0],
		[0.5, Vector3(0.10, -0.08, -0.52), 0.0], [0.65, Vector3(0.12, -0.10, -0.50), 0.0],
		[1.0, Vector3(0.20, -0.19, -0.42), 0.0]]},
	# at the ready with a two-handed weapon or a spear
	"ready_2h": {"n": Vector3(1, 0, 0), "d": Vector3(-0.35, 0.8, -0.5), "two": GRIP_2H, "keys": [
		[0.0, Vector3(0.10, -0.06, -0.44), 0.0]]},
	"ready_spear": {"n": Vector3(1, 0, 0), "d": Vector3(-0.2, 0.3, -0.93), "two": GRIP_SPEAR, "keys": [
		[0.0, Vector3(0.12, -0.19, -0.26), 0.0]]},
	"guard": {"n": Vector3(-1, 0, 0), "d": Vector3(0, 0.9, -0.4), "keys": [
		[0.0, Vector3(0.10, -0.10, -0.30), 0.0]]},
}
## Where each elbow points as the arm reaches (x right, y up, z back)
const POLE := Vector3(0.8, -1.0, 0.4)
## The raised shield, moved from where Morrowind holds it (m)
const SHIELD_NUDGE := Vector3(-0.08, -0.08, 0.0)
## The bow in the left hand: held low, and raised to shoot; the right hand draws the string to the cheek
const BOW_LOW := Vector3(-0.16, -0.24, -0.40)
const BOW_UP := Vector3(-0.13, -0.08, -0.46)
const CHEEK := Vector3(0.11, -0.13, -0.19)

## true while the arms are shown (the ViewModel then hides its own weapons)
var active := false
## side -> [wanted grip, wanted blade] for the last move (tools/capture_fp)
var debug := {}

var _player: Node3D
var _camera: Camera3D
var _combat: MeleeCombat
var _equipment: Equipment
var _ranged: RangedCombat
var _book: Spellbook
var _casters := {}  # side (1 right, -1 left) -> SpellCaster
var _model: Node3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _weapon_holder: Node3D
var _shield_holder: Node3D
var _left_holder: Node3D
var _glow_at := {}  # side -> where a spell glows (the grip of that hand)
var _shown_main: ItemData
var _shown_off: ItemData
var _dressed := false
var _placed := false
var _base_pos := Vector3.ZERO
var _base_basis := Basis()
var _to_skel := Transform3D()  # from this node (unswayed) to the skeleton's space
var _rot_to_skel := Basis()

var _side_bones := {1: PackedInt32Array(), -1: PackedInt32Array(), 0: PackedInt32Array()}
var _chain := {}  # side -> [upper arm, forearm, hand]
var _wb_local := Transform3D()  # the weapon bone on the right hand
var _left_grip := Transform3D()  # where the left fist holds a weapon (see _mirrored_grip)
var _tracks := {}  # Animation -> {bone: [rot track, pos track]}
var _mirrors := {}  # clip -> mirrored Animation
var _ch := {}  # side -> channel {a, t, pa, pt, k}
var _ik := {}  # side -> {w, from, k, last, swing}
var _idle_t := 0.0
var _release := {1: -1.0, -1: -1.0}  # time since the spell left that hand (-1: none)
var _bow_follow := -1.0
var _was_drawing := false
var _charge_u := 0.0
var _glows := {}  # side -> Node3D
var _time := 0.0
var _sway := Vector3.ZERO
var _last_cam := Basis()
var _jolt := 0.0
var _bow_aim := 0.0  # 0 the bow held low, 1 raised to shoot
var _dual := false  # both hands cast one spell together
var _arrow: Node3D


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
	_ranged = _player.get_node_or_null("RangedCombat") as RangedCombat
	_book = _player.get_node_or_null("Spellbook") as Spellbook
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
	_anim.active = false  # the arms are posed here, each on its own
	for side in [1, -1]:
		var s := "R" if side == 1 else "L"
		var chain := [_skel.find_bone("Bip01 %s UpperArm" % s), _skel.find_bone("Bip01 %s Forearm" % s), _skel.find_bone("Bip01 %s Hand" % s)]
		if chain.has(-1):
			_model.queue_free()
			return
		_chain[side] = chain
		_ch[side] = {"a": null, "t": 0.0, "pa": null, "pt": 0.0, "k": 1.0}
		_ik[side] = {"w": 0.0, "from": Transform3D(), "k": 1.0, "last": Transform3D(), "swing": ""}
	_ch[0] = {"a": null, "t": 0.0, "pa": null, "pt": 0.0, "k": 1.0}
	for b in _skel.get_bone_count():
		_side_bones[ClipTools.side_of(_skel, b)].append(b)
	var wb := _skel.find_bone("Weapon Bone")
	if wb >= 0:
		_wb_local = _skel.get_bone_rest(wb)
	_left_grip = _mirrored_grip()
	_weapon_holder = _holder("Weapon Bone")
	_shield_holder = _holder("Shield Bone")
	_left_holder = _holder("Bip01 L Hand", _left_grip)
	_glow_at[1] = _holder("Weapon Bone")
	_glow_at[-1] = _holder("Bip01 L Hand", _left_grip)
	for side in [1, -1]:
		var caster := _player.get_node_or_null("SpellCaster" if side == -1 else "SpellCasterRight") as SpellCaster
		if caster != null:
			_casters[side] = caster
			caster.spell_cast.connect(func(_s: SpellData) -> void: _release[side] = 0.0)
	if _combat != null:
		_combat.blocked.connect(func(_i: DamageInfo, _a: float) -> void: _jolt = 1.0)
		_combat.staggered.connect(func(_i: DamageInfo) -> void: _jolt = 1.4)
	active = true


# The left hand's grip, in the left hand's space: the left fist (Morrowind's own, LEFT_FIST) holds a
# weapon as the right fist holds one in its idle, mirrored. The two hands are not each other's mirror,
# so each fist is measured from its own finger joints (_fist) and the weapon placed the same way in it.
func _mirrored_grip() -> Transform3D:
	var right_clip := _clip("Idle1h")
	var left_clip := _clip(LEFT_FIST)
	if right_clip == null or left_clip == null:
		return _wb_local
	var gr := ClipTools._pose_at(right_clip, _skel, ClipTools._tracks_by_bone(right_clip, _skel), 0.0)
	var gl := ClipTools._pose_at(left_clip, _skel, ClipTools._tracks_by_bone(left_clip, _skel), 0.0)
	var wb := _skel.find_bone("Weapon Bone")
	if wb < 0:
		return _wb_local
	var in_fist := _fist(gr, "R").affine_inverse() * gr[wb]  # the weapon, as the right fist holds it
	var flip := Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3.ZERO)  # the mirror image
	return gl[_chain[-1][2]].affine_inverse() * _fist(gl, "L") * flip * in_fist * flip


# A frame in a hand that holds something, from its bones (however far the fingers curl): at the
# knuckles, along them from little finger to index, from the wrist out to the knuckles, and the third
# way round
func _fist(pose: Array[Transform3D], s: String) -> Transform3D:
	var roots := Vector3.ZERO
	for i in [1, 2, 3, 4]:
		roots += pose[_skel.find_bone("Bip01 %s Finger%d" % [s, i])].origin / 4.0
	var a := (pose[_skel.find_bone("Bip01 %s Finger1" % s)].origin - pose[_skel.find_bone("Bip01 %s Finger4" % s)].origin).normalized()
	var b := roots - pose[_skel.find_bone("Bip01 %s Hand" % s)].origin
	b = (b - a * b.dot(a)).normalized()
	return Transform3D(Basis(a, b, a.cross(b)), roots)


# A node on a bone (at `offset` from it, in the bone's units) that undoes the skeleton's scale, so
# things hang there at their real size
func _holder(bone: String, offset: Transform3D = Transform3D()) -> Node3D:
	if _skel.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skel.add_child(att)
	var at := Node3D.new()
	at.transform = offset
	att.add_child(at)
	var h := Node3D.new()
	var s := ModelLibrary.relative_transform(self, _skel).basis.get_scale()
	h.scale = Vector3.ONE / s.max(Vector3.ONE * 0.00001)
	at.add_child(h)
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
	_time += delta
	_idle_t += delta
	_animate(delta)
	_glow(delta)
	_move(delta)


# Morrowind's eye (its "Camera" bone) on ours: the arms then sit where they did in Morrowind
func _place() -> void:
	var cam_bone := _skel.find_bone("Camera")
	if cam_bone < 0:
		cam_bone = _skel.find_bone("Bip01 Head")
	if cam_bone >= 0:
		_model.position -= ModelLibrary.relative_transform(self, _skel) * _skel.get_bone_global_rest(cam_bone).origin
	_base_pos = _model.position
	_base_basis = _model.basis
	_to_skel = ModelLibrary.relative_transform(self, _skel).affine_inverse()
	_rot_to_skel = _to_skel.basis.orthonormalized()
	_last_cam = _camera.global_basis
	_placed = true


# The weapon, shield, bow or second weapon in hand follow what is equipped
func _dress() -> void:
	var main := _equipment.get_main_hand() if _equipment != null else null
	var off := _equipment.get_off_hand() if _equipment != null else null
	if _dressed and main == _shown_main and off == _shown_off:
		return
	_dressed = true
	_shown_main = main
	_shown_off = off
	for h in [_weapon_holder, _shield_holder, _left_holder]:
		_clear(h)
	if main != null:
		_hang(_left_holder if main.is_bow else _weapon_holder, _held_model(main))  # a bow is held in the left hand
	if off != null and _is_shield(off):
		_hang(_shield_holder, _held_model(off))
	elif off != null and off.item_type == ItemData.ItemType.WEAPON and (main == null or not main.is_bow):
		_hang(_left_holder, _held_model(off))


func _clear(h: Node3D) -> void:
	if h != null:
		for c in h.get_children():
			c.queue_free()


func _hang(h: Node3D, m: Node3D) -> void:
	if h != null and m != null:
		h.add_child(m)


func _is_shield(item: ItemData) -> bool:
	return item != null and item.secondary_action == ItemData.SecondaryAction.BLOCK and item.item_type != ItemData.ItemType.WEAPON


# Morrowind's own weapon or shield model as made for the bone; anything else built for the view
func _held_model(item: ItemData) -> Node3D:
	var key := ModelLibrary.first(ItemModels.model_keys(item))
	if key != "" and String(ModelLibrary.entry(key).get("source", "")) == "morrowind":
		var raw := ModelLibrary.instance(key)
		if raw != null and raw.get_child_count() > 0:
			(raw.get_child(0) as Node3D).rotation = Vector3.ZERO  # as authored for the bone (no display turn)
		return raw
	return ItemModels.build_view(item)


# ---------------------------------------------------------------- what each hand is doing

## "one", "two", "spear", "bow", "spell" or "none" for the right hand
func _right_style() -> String:
	if _ranged != null and _ranged.has_bow():
		return "bow"
	if _book != null and _book.get_right() != null:
		return "spell"
	var w := _equipment.get_main_hand() if _equipment != null else null
	if w == null:
		return "none"
	if String(w.animation_set) == "spear":
		return "spear"
	return "two" if w.two_handed else "one"


## "shield", "weapon", "spell" or "none" for the left hand
func _left_style() -> String:
	if _book != null and _book.get_equipped() != null:
		return "spell"
	var off := _equipment.get_off_hand() if _equipment != null else null
	if off == null:
		return "none"
	if _is_shield(off):
		return "shield"
	return "weapon" if off.item_type == ItemData.ItemType.WEAPON else "none"


func _animate(delta: float) -> void:
	var right := _right_style()
	var left := _left_style()
	var whole := right in ["two", "spear", "bow"] or (right == "none" and left == "none")
	var swing := {1: "", -1: ""}
	var u := {1: 0.0, -1: 0.0}
	# Idles: each hand its own; two-handed weapons, bows and bare fists use the whole body's
	var r_clip := String(IDLE.get(right, "Idle1h")) if right != "bow" else "Idlehh"
	var r_t := _idle_t
	var l_clip := "Idle1h"
	var l_t := _idle_t
	match left:
		"spell":
			l_clip = "Idlespell"
		"weapon":
			l_clip = LEFT_FIST
	if whole:
		# a hand that holds something (a two-handed grip, the bow) keeps Morrowind's own left fist
		l_clip = LEFT_FIST if right in ["two", "spear", "bow"] else r_clip
	if right == "bow":
		# the bow in the left hand; the right draws the string back to the cheek and lets go
		var drawing := _ranged.is_drawing()
		_bow_aim = move_toward(_bow_aim, 1.0 if drawing or _bow_follow >= 0.0 else 0.0, delta * 4.0)
		swing[-1] = "bow"
		if drawing:
			_bow_follow = -1.0
			swing[1] = "draw"
			u[1] = _ranged.get_draw_ratio()
		elif _was_drawing:
			_bow_follow = 0.0
		if _bow_follow >= 0.0:
			_bow_follow += delta
			swing[1] = "loose"
			u[1] = _bow_follow / 0.35
			if _bow_follow >= 0.35:
				_bow_follow = -1.0
		_was_drawing = drawing
	# Spells: the hand that holds one is raised before you, palm out; it draws back as the spell
	# charges, thrusts out as it goes off, and stays out while a spray or beam runs
	var dual := false
	for side in [1, -1]:
		if (right if side == 1 else left) != "spell" or not _casters.has(side):
			continue
		var caster: SpellCaster = _casters[side]
		dual = dual or caster.dual
		swing[side] = "spell"
		u[side] = 0.0
		if caster.is_charging():
			u[side] = 0.35 * ease(caster.get_charge_ratio(), 0.6) + (sin(_time * 35.0) * 0.004 if caster.get_charge_ratio() >= 1.0 else 0.0)
			_release[side] = -1.0
		elif caster.is_channeling():
			u[side] = 0.55 + sin(_time * 9.0) * 0.01
		elif _release[side] >= 0.0:
			_release[side] += delta
			u[side] = 0.35 + _release[side] * 1.6
			if u[side] >= 1.0:
				_release[side] = -1.0
				u[side] = 0.0
	_dual = dual
	# Melee: swings and weapon blocks are paths the arms reach along
	var kind := _combat.get_action_kind()
	var phase := _combat.get_phase()
	var attacking := phase != MeleeCombat.Phase.IDLE and _combat.is_attacking() and kind != MeleeCombat.Kind.BASH
	if attacking:
		var side := 1 if _combat.get_action_hand() == MeleeCombat.MAIN else -1
		var style := right if side == 1 else "one"
		if right == "none" and left == "none" and side == 1 and _combat.get_combo_step() % 2 == 1:
			side = -1  # bare fists take turns
		swing[side] = _swing_for(style, _combat.is_heavy_action() or kind == MeleeCombat.Kind.SLAM, _combat.get_combo_step())
		var p := _combat.get_phase_progress()
		match phase:
			MeleeCombat.Phase.WINDUP:
				u[side] = lerpf(_charge_u, 0.35, ease(p, 0.6))
			MeleeCombat.Phase.ACTIVE:
				u[side] = 0.35 + 0.3 * p
			_:
				u[side] = 0.65 + 0.35 * ease(p, 0.5)
				_charge_u = 0.0
	elif _combat.is_charging() and right != "bow" and right != "spell":
		# holding for a power attack: the weapon draws back and waits, trembling once it is ready
		var r := _combat.get_charge_ratio()
		swing[1] = _swing_for(right, true, 0)
		_charge_u = 0.33 * ease(r, 0.5)
		u[1] = _charge_u + (sin(_time * 40.0) * 0.004 if r >= 1.0 else 0.0)
	else:
		_charge_u = 0.0
		if _combat.is_blocking() or kind == MeleeCombat.Kind.BASH:
			if left == "shield":
				l_clip = "Shield_Block"
				l_t = BLOCK_HELD
				swing[-1] = "shield"  # held a little lower and to the left, so you can see past it
			elif right in ["one", "two", "spear", "none"]:
				swing[1] = {"one": "block", "two": "block_2h", "spear": "block_spear", "none": "guard"}[right]
				if right == "none" and left == "none":
					swing[-1] = "guard"
	if swing[-1] == "" and left == "weapon":
		swing[-1] = "mirror"  # the second weapon held as the right hand holds the first, mirrored
	if swing[1] == "" and (right == "two" or right == "spear"):
		swing[1] = "ready_2h" if right == "two" else "ready_spear"  # held before you, both hands on it
	# a two-handed weapon's second hand is on the grip: it is the left arm's whole job
	if whole and SWINGS.has(swing[1]) and SWINGS[swing[1]].has("two"):
		swing[-1] = ""
	_channel(1, r_clip, r_t, delta)
	_channel(-1, l_clip, l_t, delta)
	_channel(0, r_clip, r_t, delta)
	_apply_clips()
	_reach(swing, u, delta)


func _swing_for(style: String, heavy: bool, step: int) -> String:
	match style:
		"two":
			return "power_2h" if heavy else ("sweep" if step % 2 == 0 else "sweep_back")
		"spear":
			return "thrust"
		"none":
			return "haymaker" if heavy else "punch"
	return "power" if heavy else ("slash" if step % 2 == 0 else "backhand")


# ---------------------------------------------------------------- clips

func _clip(name: String) -> Animation:
	if name.begins_with("L:"):
		var base := name.substr(2)
		if not _mirrors.has(base):
			_mirrors[base] = ClipTools.mirror(_anim.get_animation(base), _skel) if _anim.has_animation(base) else null
		return _mirrors[base]
	if _anim.has_animation(name):
		return _anim.get_animation(name)
	return _anim.get_animation("Idle") if _anim.has_animation("Idle") else null


# One hand's clip and moment; a change of clip crossfades from where the old one was
func _channel(side: int, clip: String, t: float, delta: float) -> void:
	var ch: Dictionary = _ch[side]
	var a := _clip(clip)
	if a == null:
		return
	if a.loop_mode != Animation.LOOP_NONE or clip.begins_with("Idle") or clip.begins_with("L:Idle"):
		t = fmod(t, a.length)
	t = clampf(t, 0.0, a.length)
	if a != ch["a"]:
		ch["pa"] = ch["a"]
		ch["pt"] = ch["t"]
		ch["k"] = 0.0 if ch["a"] != null else 1.0
	ch["a"] = a
	ch["t"] = t
	ch["k"] = minf(float(ch["k"]) + delta / BLEND, 1.0)


func _apply_clips() -> void:
	for side in [1, -1, 0]:
		var ch: Dictionary = _ch[side]
		var a: Animation = ch["a"]
		if a == null:
			continue
		var pa: Animation = ch["pa"]
		var k := smoothstep(0.0, 1.0, float(ch["k"]))
		for b in _side_bones[side]:
			var pose := _sample(a, float(ch["t"]), b)
			if k < 1.0 and pa != null:
				var from := _sample(pa, float(ch["pt"]), b)
				pose = [(from[0] as Quaternion).slerp(pose[0], k), (from[1] as Vector3).lerp(pose[1], k)]
			_skel.set_bone_pose_rotation(b, pose[0])
			_skel.set_bone_pose_position(b, pose[1])


func _sample(a: Animation, t: float, b: int) -> Array:
	if not _tracks.has(a):
		var by := {}
		var raw := ClipTools._tracks_by_bone(a, _skel)
		for bone in raw:
			by[bone] = [int(raw[bone].get("rot", -1)), int(raw[bone].get("pos", -1))]
		_tracks[a] = by
	var tr: Array = _tracks[a].get(b, [-1, -1])
	var rest := _skel.get_bone_rest(b)
	var q: Quaternion = a.rotation_track_interpolate(tr[0], t) if tr[0] >= 0 else rest.basis.get_rotation_quaternion()
	var p: Vector3 = a.position_track_interpolate(tr[1], t) if tr[1] >= 0 else rest.origin
	return [q, p]


# ---------------------------------------------------------------- reaching (the Skyrim-style moves)

# The move's weapon at moment u: [grip, blade direction, edge direction], in front of the eye
func _weapon_at(swing: String, u: float) -> Array:
	var sw: Dictionary = SWINGS[swing]
	var keys: Array = sw["keys"]
	var d0: Vector3 = (sw["d"] as Vector3).normalized()
	var n: Vector3 = sw["n"]
	n = (n - d0 * n.dot(d0)).normalized()
	var pos: Vector3 = keys[0][1]
	var ang: float = keys[0][2]
	if keys.size() > 1:
		var i := 0
		while i < keys.size() - 2 and u > float(keys[i + 1][0]):
			i += 1
		var k0: Array = keys[maxi(i - 1, 0)]
		var k1: Array = keys[i]
		var k2: Array = keys[i + 1]
		var k3: Array = keys[mini(i + 2, keys.size() - 1)]
		var f := clampf((u - float(k1[0])) / maxf(float(k2[0]) - float(k1[0]), 0.001), 0.0, 1.0)
		pos = (k1[1] as Vector3).cubic_interpolate(k2[1], k0[1], k3[1], f)
		ang = cubic_interpolate(float(k1[2]), float(k2[2]), float(k0[2]), float(k3[2]), f)
	var d := d0.rotated(n, deg_to_rad(ang))
	return [pos, d, n.cross(d).normalized()]


# The hand's place (skeleton space) that puts the weapon there
func _hand_for(side: int, grip: Vector3, d: Vector3, e: Vector3) -> Transform3D:
	var w := Basis(e, d, e.cross(d))
	var hold := _left_grip
	if side == 1:
		var wb := _skel.find_bone("Weapon Bone")
		hold = _skel.get_bone_pose(wb) if wb >= 0 else _wb_local  # as the clip holds it now
	var basis := (_rot_to_skel * w) * hold.basis.inverse()
	var at := _to_skel * grip
	return Transform3D(basis.orthonormalized(), at - basis * hold.origin)


func _reach(swing: Dictionary, u: Dictionary, delta: float) -> void:
	# the right weapon as its idle holds it (before any swing moves it), for the left hand to mirror
	var right_idle := _to_skel.affine_inverse() * _skel.get_bone_global_pose(_skel.find_bone("Weapon Bone"))
	var grip2 := ""  # a two-handed move: the left hand goes to the grip
	if SWINGS.has(swing[1]) and SWINGS[swing[1]].has("two"):
		grip2 = swing[1]
	for side in [1, -1]:
		var ik: Dictionary = _ik[side]
		var name: String = swing[side]
		var target := Transform3D()
		var want := 0.0
		if name == "bow":
			# held out in the left hand, raised as you draw
			target = _hand_for(-1, _bow_grip(), Vector3(0.12, 1.0, 0.05).normalized(), Vector3(0, 0, -1))
			want = 1.0
		elif name == "draw" or name == "loose":
			# the right hand on the string, drawn back to the cheek; let go, it flicks back and away
			var nock := _bow_grip() + Vector3(0.03, 0.0, 0.07)
			var pos := nock.lerp(CHEEK, ease(float(u[1]), 0.6))
			if name == "loose":
				pos = CHEEK + Vector3(0.07, 0.03, 0.07) * sin(clampf(float(u[1]), 0.0, 1.0) * PI)
			target = _hand_for(1, pos, Vector3(0, 0.6, -0.8), Vector3(0, -0.8, -0.6))
			want = 1.0
		elif SWINGS.has(name):
			var at := _weapon_at(name, float(u[side]))
			var grip: Vector3 = at[0]
			var d: Vector3 = at[1]
			var e: Vector3 = at[2]
			if name == "spell" and _dual:
				grip.x -= 0.09  # both hands together before you
			if side == -1:  # the off hand moves the mirror image
				grip.x = -grip.x
				d.x = -d.x
				e.x = -e.x
			target = _hand_for(side, grip, d, e)
			debug[side] = [grip, d]
			want = 1.0
		elif name == "mirror":
			var m := Vector3(-1, 1, 1)
			target = _hand_for(-1, right_idle.origin * m, right_idle.basis.y.normalized() * m, right_idle.basis.x.normalized() * m)
			want = 1.0
		elif name == "shield":
			var gh := _skel.get_bone_global_pose(_chain[-1][2])
			target = Transform3D(gh.basis, gh.origin + _to_skel.basis * SHIELD_NUDGE)
			want = 1.0
		elif side == -1 and grip2 != "":
			var at := _weapon_at(grip2, float(u[1]))
			var d: Vector3 = at[1]
			# lower down the grip, knuckles the same way as the first hand's
			target = _hand_for(-1, (at[0] as Vector3) - d * float(SWINGS[grip2]["two"]), d, at[2])
			debug[-1] = [(at[0] as Vector3) - d * float(SWINGS[grip2]["two"]), d]
			name = grip2 + ":grip"
			want = 1.0
		if name != String(ik["swing"]):
			# a new path: ease over from wherever the hand was going
			ik["from"] = ik["last"]
			ik["k"] = 0.0 if float(ik["w"]) > 0.01 else 1.0
			ik["swing"] = name
		ik["k"] = minf(float(ik["k"]) + delta / 0.08, 1.0)
		if want > 0.0:
			if float(ik["k"]) < 1.0:
				target = (ik["from"] as Transform3D).interpolate_with(target, smoothstep(0.0, 1.0, float(ik["k"])))
			ik["last"] = target
		ik["w"] = move_toward(float(ik["w"]), want, delta * (10.0 if want > 0.0 else 5.0))
		if float(ik["w"]) > 0.001:
			_ik_arm(_chain[side], ik["last"], _rot_to_skel * Vector3(POLE.x * side, POLE.y, POLE.z), smoothstep(0.0, 1.0, float(ik["w"])))
	_show_arrow(swing[1] == "draw")


# Two-bone IK: the upper arm and forearm bend so the hand reaches `target`, the elbow toward `pole`
func _ik_arm(chain: Array, target: Transform3D, pole: Vector3, w: float) -> void:
	var gu := _skel.get_bone_global_pose(chain[0])
	var gf := _skel.get_bone_global_pose(chain[1])
	var gh := _skel.get_bone_global_pose(chain[2])
	var a := gu.origin
	var b := gf.origin
	var c := gh.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to := target.origin - a
	var dist := clampf(to.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var dir := to.normalized()
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.000001:
		bend = (b - a) - dir * (b - a).dot(dir)
	bend = bend.normalized()
	var elbow := a + dir * (l1 * ca) + bend * (l1 * sqrt(1.0 - ca * ca))
	var wrist := a + dir * dist
	var q1 := Basis(Quaternion((b - a).normalized(), (elbow - a).normalized()))
	var gu2 := Transform3D(q1 * gu.basis, a)
	var gf2 := Transform3D(q1 * gf.basis, elbow)
	var c2 := elbow + q1 * (c - b)
	gf2.basis = Basis(Quaternion((c2 - elbow).normalized(), (wrist - elbow).normalized())) * gf2.basis
	var gh2 := Transform3D(target.basis.orthonormalized(), wrist)
	# the forearm takes most of the wrist's turn about its own length, as a real one does (else the
	# skin between them twists like a sweet wrapper)
	var axis := (gf.basis.inverse() * (c - b)).normalized()
	var turned := (gf2.basis.orthonormalized().inverse() * gh2.basis).get_rotation_quaternion()
	var delta := turned * _skel.get_bone_pose_rotation(chain[2]).inverse()
	var along := Vector3(delta.x, delta.y, delta.z).dot(axis)
	var twist := Quaternion(axis.x * along, axis.y * along, axis.z * along, delta.w).normalized()
	gf2.basis = gf2.basis * Basis(Quaternion.IDENTITY.slerp(twist, 0.7))
	var parent := _skel.get_bone_parent(chain[0])
	var gp := _skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	_turn(chain[0], (gp.affine_inverse() * gu2).basis, w)
	_turn(chain[1], (gu2.affine_inverse() * gf2).basis, w)
	_turn(chain[2], (gf2.affine_inverse() * gh2).basis, w)


func _turn(bone: int, basis: Basis, w: float) -> void:
	var q := basis.orthonormalized().get_rotation_quaternion()
	_skel.set_bone_pose_rotation(bone, _skel.get_bone_pose_rotation(bone).slerp(q, w))


func _bow_grip() -> Vector3:
	return BOW_LOW.lerp(BOW_UP, smoothstep(0.0, 1.0, _bow_aim))


# An arrow on the string while you draw: from the right hand through the bow
func _show_arrow(on: bool) -> void:
	if not on:
		if _arrow != null:
			_arrow.visible = false
		return
	if _arrow == null:
		_arrow = Node3D.new()
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.42, 0.3, 0.18)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.55, 0.56, 0.6)
		steel.metallic = 0.7
		var shaft := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.004
		c.bottom_radius = 0.004
		c.height = 0.72
		c.radial_segments = 5
		c.material = wood
		shaft.mesh = c
		shaft.rotation.x = -PI * 0.5
		shaft.position.z = -0.36
		_arrow.add_child(shaft)
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.009
		cone.height = 0.045
		cone.radial_segments = 5
		cone.material = steel
		tip.mesh = cone
		tip.rotation.x = -PI * 0.5
		tip.position.z = -0.74
		_arrow.add_child(tip)
		for g in _arrow.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_arrow)
	_arrow.visible = true
	var hand := _skel.get_bone_global_pose(_skel.find_bone("Weapon Bone"))
	var sway := _model.position - _base_pos
	var nock := _to_skel.affine_inverse() * hand.origin + sway
	var aim := (_bow_grip() + sway - nock).normalized()
	_arrow.transform = Transform3D(Basis.looking_at(aim, Vector3.UP), nock)


# ---------------------------------------------------------------- the hands' glow and the arms' sway

# A spell in a hand: that hand glows in its colour, brighter as it charges
func _glow(delta: float) -> void:
	for side in [1, -1]:
		var spell: SpellData = null
		if _book != null:
			spell = _book.get_right() if side == 1 else _book.get_equipped()
		var g: Node3D = _glows.get(side)
		if spell == null or _glow_at.get(side) == null:
			if g != null:
				g.queue_free()
				_glows.erase(side)
			continue
		var color := spell.get_color()
		if g == null or g.get_meta("color", Color.BLACK) != color:
			if g != null:
				g.queue_free()
			g = SpellFX.hand_glow(color)
			g.set_meta("color", color)
			(_glow_at[side] as Node3D).add_child(g)
			_glows[side] = g
		var caster: SpellCaster = _casters.get(side)
		var charge := caster.get_charge_ratio() if caster != null and caster.is_charging() else 0.0
		var channel := caster != null and caster.is_channeling()
		SpellFX.set_hand_glow(g, charge, channel, _time, delta)


# The arms lag a little behind the view as you look around and bob as you walk; a blocked hit or a
# stagger jolts them; a shield bash shoves them forward
func _move(delta: float) -> void:
	var cam := _camera.global_basis
	var turn := _last_cam.inverse() * cam
	_last_cam = cam
	var e := turn.get_euler()
	var lag := Vector3(-e.y * 0.6, e.x * 0.6, 0.0).limit_length(0.05)
	_sway = _sway.lerp(lag, clampf(delta * 8.0, 0.0, 1.0))
	var speed := 0.0
	if _player is CharacterBody3D:
		var v := (_player as CharacterBody3D).velocity
		speed = Vector2(v.x, v.z).length()
	var bob := minf(speed / 6.0, 1.0)
	var step := _time * (6.0 + speed * 1.2)
	var offset := _sway + Vector3(sin(step * 0.5) * 0.008, -absf(sin(step * 0.5)) * 0.012, 0.0) * bob
	offset.y += sin(_time * 1.6) * 0.002
	_jolt = move_toward(_jolt, 0.0, delta * 5.0)
	offset.z += _jolt * 0.05
	if _combat.get_action_kind() == MeleeCombat.Kind.BASH and _combat.get_phase() != MeleeCombat.Phase.IDLE:
		var p := _combat.get_phase_progress()
		match _combat.get_phase():
			MeleeCombat.Phase.WINDUP:
				offset.z += 0.04 * p
			MeleeCombat.Phase.ACTIVE:
				offset.z -= 0.16 * p
			_:
				offset.z -= 0.16 * (1.0 - p)
	_model.position = _base_pos + offset
	_model.basis = Basis(Vector3.BACK, -_sway.x * 0.6) * _base_basis


func _third_person() -> bool:
	var tp := _player.get_node_or_null("ThirdPerson") as ThirdPerson
	return tp != null and tp.third


## Where the weapon (or the left hand's grip) really is, in this node's space, unswayed: [grip, blade]
func actual(side: int) -> Array:
	var bone: int = _skel.find_bone("Weapon Bone") if side == 1 else int(_chain[-1][2])
	var g := _skel.get_bone_global_pose(bone)
	if side == -1:
		g = g * _left_grip
	var t := _to_skel.affine_inverse() * g
	return [t.origin, t.basis.y.normalized()]
