class_name ViewModel
extends Node3D
## The weapons you see in your hands, built from boxes and animated in code (no animations or
## models needed). Created by PlayerCombat as a child of the camera. It shows what is in your main
## hand and off hand, and animates them from the combat state so the picture matches the rules:
##   charging   the weapon is drawn back further the longer you hold
##   windup     drawn back, the hit has not started yet
##   active     the swing, fast. This is the moment the hit window is open
##   recovery   returning to rest
##   blocking   the shield comes up to the middle; a parry window shows as a fast raise
## Slashes alternate direction down a combo. Hits kick the weapon back; blocks and parries kick the
## shield. It also lowers the weapons when you stand close to a wall, so they never poke through it.
## To use your own models, set "View Scene" on the ItemData (see ItemModels): boxes are only the placeholder.

@export var combat: MeleeCombat
@export var bob_enabled := true
@export var avoid_walls := true
@export var wall_check_distance := 0.95

enum Swing { SLASH, THRUST, CHOP }

const MAIN := ItemData.EquipSlot.MAIN_HAND
const OFF := ItemData.EquipSlot.OFF_HAND

# Poses are [position, rotation in degrees], relative to the camera. Blades point along +Y.
const REST_MAIN := [Vector3(0.30, -0.28, -0.55), Vector3(-20.0, 0.0, -14.0)]
const REST_FIST := [Vector3(0.28, -0.30, -0.50), Vector3(0.0, 0.0, 0.0)]
const REST_SHIELD := [Vector3(-0.34, -0.30, -0.50), Vector3(0.0, 25.0, 0.0)]
const BLOCK_SHIELD := [Vector3(-0.06, -0.12, -0.42), Vector3(0.0, 0.0, 0.0)]
const BASH_WIND := [Vector3(-0.22, -0.22, -0.30), Vector3(0.0, 15.0, 0.0)]
const BASH_STRIKE := [Vector3(-0.04, -0.10, -0.86), Vector3(0.0, 0.0, 0.0)]
const SLASH_WIND := [Vector3(0.50, -0.10, -0.35), Vector3(-5.0, 15.0, -75.0)]
const SLASH_STRIKE := [Vector3(-0.32, -0.22, -0.62), Vector3(-80.0, -30.0, 60.0)]
const THRUST_WIND := [Vector3(0.28, -0.30, -0.15), Vector3(-82.0, 0.0, -4.0)]
const THRUST_STRIKE := [Vector3(0.10, -0.20, -0.88), Vector3(-88.0, 0.0, 0.0)]
const CHOP_WIND := [Vector3(0.30, 0.20, -0.25), Vector3(35.0, 0.0, -12.0)]
const CHOP_STRIKE := [Vector3(0.12, -0.36, -0.72), Vector3(-105.0, 0.0, 0.0)]

var _hands := {}  # hand slot -> {"node", "item", "p", "r"}
var _kick := {MAIN: Vector3.ZERO, OFF: Vector3.ZERO}
var _exclude: Array[RID] = []
var _player: CharacterBody3D
var _bob_t := 0.0
var _bob_amp := 0.0


func _ready() -> void:
	add_to_group("settings_listener")
	apply_settings()
	if combat == null:
		combat = _find_combat()
	var n: Node = get_parent()
	while n != null and _player == null:
		_player = n as CharacterBody3D
		n = n.get_parent()
	if _player != null:
		_exclude.append(_player.get_rid())
	for slot in [MAIN, OFF]:
		var holder := Node3D.new()
		holder.name = "MainHand" if slot == MAIN else "OffHand"
		add_child(holder)
		_hands[slot] = {"node": holder, "item": null, "p": Vector3.ZERO, "r": Vector3.ZERO, "built": false}
	if combat == null:
		push_warning("ViewModel: could not find the player's MeleeCombat.")
		set_process(false)
		return
	if combat.equipment != null:
		combat.equipment.equipped.connect(func(_slot, _item): _refresh_models())
		combat.equipment.unequipped.connect(func(_slot, _item): _refresh_models())
	combat.hit_dealt.connect(_on_hit_dealt)
	combat.blocked.connect(_on_blocked)
	combat.parried.connect(_on_parried)
	_refresh_models()
	for slot in _hands:
		var rest := _rest_pose(slot, _hands[slot]["item"])
		_hands[slot]["p"] = rest[0]
		_hands[slot]["r"] = rest[1]


func _find_combat() -> MeleeCombat:
	var n: Node = get_parent()
	while n != null:
		var c := n.get_node_or_null("MeleeCombat") as MeleeCombat
		if c != null:
			return c
		n = n.get_parent()
	return null


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	visible = combat.is_alive()
	var phase := combat.get_phase()
	var action_hand := combat.get_action_hand()
	var retract := _wall_retract() if avoid_walls else 0.0
	var bob := _bob(delta)

	for slot in _hands:
		var h: Dictionary = _hands[slot]
		var node: Node3D = h["node"]
		node.visible = h["item"] != null or slot == MAIN
		var item: ItemData = h["item"]
		var target := _target_pose(slot, item)
		var acting: bool = phase != MeleeCombat.Phase.IDLE and action_hand == slot
		var rate := 12.0
		if acting:
			match phase:
				MeleeCombat.Phase.WINDUP:
					rate = 28.0
				MeleeCombat.Phase.ACTIVE:
					rate = 55.0
				_:
					rate = 14.0
		elif combat.is_blocking() and slot == OFF:
			rate = 24.0
		var k := 1.0 - exp(-rate * delta)
		h["p"] = (h["p"] as Vector3).lerp(target[0], k)
		h["r"] = (h["r"] as Vector3).lerp(target[1], k)

		var pos: Vector3 = h["p"]
		var rot: Vector3 = h["r"]
		var kick: Vector3 = _kick[slot]
		_kick[slot] = kick.lerp(Vector3.ZERO, 1.0 - exp(-16.0 * delta))
		var wall := retract * (0.5 if acting and phase == MeleeCombat.Phase.ACTIVE else 1.0)
		pos += kick + bob + Vector3(0.0, -wall * 0.12, wall * 0.35)
		rot.x += wall * 35.0
		if slot == MAIN and combat.get_charge_ratio() >= 1.0:
			pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.004  # a held, ready weapon trembles
		node.position = pos
		node.rotation_degrees = rot


# The pose a hand wants to be in right now
func _target_pose(slot: int, item: ItemData) -> Array:
	if slot == MAIN and item != null and item.is_bow:
		# A bow: held upright to the left, drawn toward the middle of the view
		var ranged := get_tree().get_first_node_in_group("player").get_node_or_null("RangedCombat") as RangedCombat
		var d := ranged.get_draw_ratio() if ranged != null else 0.0
		return _mix([Vector3(0.12, -0.28, -0.55), Vector3(0.0, 0.0, 10.0)], [Vector3(0.02, -0.12, -0.5), Vector3(0.0, 0.0, -4.0)], d)
	var rest := _rest_pose(slot, item)
	var phase := combat.get_phase()
	if phase != MeleeCombat.Phase.IDLE and combat.get_action_hand() == slot:
		var poses := _action_poses(slot, item, combat.get_action_kind(), combat.get_swing_dir())
		var t := combat.get_phase_progress()
		match phase:
			MeleeCombat.Phase.WINDUP:
				return _mix(rest, poses[0], 1.0 - pow(1.0 - t, 2.0))
			MeleeCombat.Phase.ACTIVE:
				return _mix(poses[0], poses[1], t * t * (3.0 - 2.0 * t))
			_:
				return _mix(poses[1], rest, t * t * (3.0 - 2.0 * t))
	if slot == OFF and item != null and item.secondary_action == ItemData.SecondaryAction.BLOCK and combat.is_blocking():
		return BLOCK_SHIELD
	if slot == MAIN and combat.is_charging():
		# Drawn back a little at once (so a tap already looks like a swing), further as you keep holding
		var light := _action_poses(MAIN, item, MeleeCombat.Kind.LIGHT, 1.0)[0] as Array
		var heavy := _action_poses(MAIN, item, MeleeCombat.Kind.HEAVY, 1.0)[0] as Array
		var drawn := _mix(rest, light, clampf(combat.get_charge_time() / 0.15, 0.0, 1.0))
		return _mix(drawn, heavy, combat.get_charge_ratio())
	return rest


func _rest_pose(slot: int, item: ItemData) -> Array:
	if slot == MAIN:
		if item == null:
			return REST_FIST
		return _shift(REST_MAIN, -0.14) if item.two_handed else REST_MAIN
	if item != null and item.secondary_action == ItemData.SecondaryAction.BLOCK:
		return REST_SHIELD
	return _mirror(REST_MAIN)


# [windup pose, strike pose] for a swing of this kind with this hand
func _action_poses(slot: int, item: ItemData, kind: int, dir: float) -> Array:
	if kind == MeleeCombat.Kind.BASH:
		return [BASH_WIND, BASH_STRIKE]
	var wind: Array
	var strike: Array
	match _swing_type(item, kind):
		Swing.SLASH:
			wind = SLASH_WIND
			strike = SLASH_STRIKE
			if dir < 0.0:
				wind = SLASH_STRIKE  # the way back: from the left across to the right
				strike = SLASH_WIND
		Swing.THRUST:
			wind = THRUST_WIND
			strike = THRUST_STRIKE
		_:
			wind = CHOP_WIND
			strike = CHOP_STRIKE
	if slot == OFF:
		wind = _mirror(wind)
		strike = _mirror(strike)
	if item != null and item.two_handed:
		wind = _shift(wind, -0.14)
		strike = _shift(strike, -0.14)
	return [wind, strike]


func _swing_type(item: ItemData, kind: int) -> int:
	if kind == MeleeCombat.Kind.HEAVY or kind == MeleeCombat.Kind.SLAM:
		return Swing.CHOP
	if item == null:
		return Swing.THRUST
	if item.animation_set == &"hammer" or item.animation_set == &"mace":
		return Swing.CHOP
	if item.attack_style == ItemData.AttackStyle.ARC:
		return Swing.SLASH
	return Swing.THRUST


func _mix(a: Array, b: Array, t: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0], t), (a[1] as Vector3).lerp(b[1], t)]


func _mirror(pose: Array) -> Array:
	var p: Vector3 = pose[0]
	var r: Vector3 = pose[1]
	return [Vector3(-p.x, p.y, p.z), Vector3(r.x, -r.y, -r.z)]


func _shift(pose: Array, dx: float) -> Array:
	var p: Vector3 = pose[0]
	return [Vector3(p.x + dx, p.y, p.z), pose[1]]


# Walking sways the weapons a little
func _bob(delta: float) -> Vector3:
	if not bob_enabled or _player == null:
		return Vector3.ZERO
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var moving := _player.is_on_floor() and speed > 0.5
	_bob_amp = lerpf(_bob_amp, clampf(speed / 7.0, 0.0, 1.0) * 0.012 if moving else 0.0, 1.0 - exp(-8.0 * delta))
	if moving:
		_bob_t += delta * (5.0 + speed * 0.8)
	return Vector3(sin(_bob_t) * _bob_amp, -absf(cos(_bob_t)) * _bob_amp * 0.8, 0.0)


# 0..1: how close a wall is in front of the camera
func _wall_retract() -> float:
	if not is_inside_tree():
		return 0.0
	var from := global_position
	var to := from + (-global_transform.basis.z) * wall_check_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return clampf(1.0 - from.distance_to(hit["position"]) / wall_check_distance, 0.0, 1.0)


# ---------------------------------------------------------------- reactions

func _on_hit_dealt(_target: Node, info: DamageInfo, _final: float) -> void:
	var slot := combat.get_action_hand() if combat.get_action_kind() >= 0 else MAIN
	var amount := 0.14 if info.heavy or info.kind == &"slam" else 0.07
	_kick[slot] = (_kick[slot] as Vector3) + Vector3(0.0, 0.02, amount)  # recoil


func _on_blocked(_info: DamageInfo, _absorbed: float) -> void:
	_kick[OFF] = (_kick[OFF] as Vector3) + Vector3(0.0, 0.0, 0.07)


func _on_parried(_info: DamageInfo) -> void:
	_kick[OFF] = (_kick[OFF] as Vector3) + Vector3(0.0, 0.0, -0.20)  # the shield snaps forward


# ---------------------------------------------------------------- models

func _refresh_models() -> void:
	for slot in _hands:
		var h: Dictionary = _hands[slot]
		var item: ItemData = combat.equipment.get_equipped(slot) if combat.equipment != null else null
		if slot == MAIN and item != null and item.item_type != ItemData.ItemType.WEAPON and item.view_scene == null:
			item = null
		if bool(h["built"]) and h["item"] == item:
			continue
		var node: Node3D = h["node"]
		for c in node.get_children():
			c.queue_free()
		h["item"] = item
		h["built"] = true
		if item != null or slot == MAIN:
			node.add_child(_build_model(item))


# The model itself comes from ItemModels: the item's View Scene, or a placeholder
func _build_model(item: ItemData) -> Node3D:
	var root := ItemModels.build_view(item)
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## GameSettings changed (weapon sway)
func apply_settings() -> void:
	bob_enabled = bool(GameSettings.get_value("head_bob"))
