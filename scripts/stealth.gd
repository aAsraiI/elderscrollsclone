class_name Stealth
extends Node
## Sneaking, and how aware everyone around is of the player. Created by player.gd.
##
## Ctrl switches sneaking on and off: you move slower and lower, and you are much harder to see.
## Every person and creature nearby has an AWARENESS of you that grows while they can see or hear
## you and fades when they can't (0 = no idea, 1 = they have seen you):
##   seeing   inside their view cone (all around once alert), in line of sight, closer than their
##            sight range. That range shrinks with darkness (night, dim interiors, dungeons), with
##            sneaking and your Sneak skill, and grows when you sprint.
##   hearing  sprinting and fighting are loud and carry through walls; sneaking is silent
## The eye at the top of the screen (shown while sneaking) says how seen you are: Hidden,
## Noticed or Seen. Hostile creatures only come for you once they have seen you, and crimes only
## count when someone is aware of you (see CrimeManager).
##
## Sneak attacks: hitting someone who isn't aware of you (or asleep) does x2 damage, x3 with a
## dagger, plus the Sneak skill's sneak_attack_bonus.

signal sneak_changed(sneaking: bool)
## Fired when a hit is a sneak attack (for the popup and tests)
signal sneak_attack(victim: Node3D, mult: float)

const ACTION := "sneak"
## Only creatures this close are tracked (meters)
const RANGE := 30.0
const TICK := 0.1
## How far someone sees a player standing in daylight, not sneaking (meters)
const SEE_RANGE := 22.0
const FOV_DEG := 150.0
const NOTICED := 0.35
const SEEN := 1.0
const HEAD_STAND := 1.6
const HEAD_SNEAK := 1.15
const SNEAK_SPEED := 0.55

var sneaking := false
## Instance id -> awareness (0..1.2)
var awareness := {}

var _player: CharacterBody3D
var _head: Node3D
var _skills: Skills
var _stats: Stats
var _time := 0.0
var _timer := 0.0
var _noise_until := 0.0
var _xp_timer := 0.0
var _hud: CanvasLayer
var _eye: Control
var _eye_label: Label


class Eye extends Control:
	var level := 0
	var fill := 0.0

	func _draw() -> void:
		var c := size / 2.0
		var col: Color = [Color(0.75, 0.75, 0.78, 0.9), Color(1.0, 0.8, 0.25, 0.95), Color(1.0, 0.3, 0.25, 1.0)][level]
		var pts := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0 * PI
			pts.append(c + Vector2(cos(t) * 26.0, sin(t) * 12.0))
		for i in 25:
			var t := PI + float(i) / 24.0 * PI
			pts.append(c + Vector2(cos(t) * 26.0, sin(t) * 12.0 * clampf(fill, 0.15, 1.0)))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
		draw_polyline(pts, col, 2.0, true)
		draw_circle(c, 6.5, col if level > 0 else Color(col, 0.5))


func _ready() -> void:
	add_to_group("stealth")
	process_mode = Node.PROCESS_MODE_ALWAYS  # so the eye hides itself while a menu pauses the game
	_player = get_parent() as CharacterBody3D
	if _player != null:
		_player.set_meta("stealth", self)
		_head = _player.get_node_or_null("Head") as Node3D
		_skills = _player.get_node_or_null("Skills") as Skills
		_stats = _player.get_node_or_null("Stats") as Stats
		var combat := _player.get_node_or_null("MeleeCombat") as MeleeCombat
		if combat != null:
			combat.attack_started.connect(func(_h: int, _w: ItemData) -> void: make_noise(1.0))
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_CTRL
		InputMap.action_add_event(ACTION, ev)
	sneak_attack.connect(func(victim: Node3D, mult: float) -> void:
		if victim is Enemy:
			(victim as Enemy)._popup("SNEAK ATTACK x%d" % roundi(mult), victim.global_position + Vector3.UP * 2.3, Color(1.0, 0.35, 0.3), 44))
	_build_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo() and not get_tree().paused:
		set_sneaking(not sneaking)
		get_viewport().set_input_as_handled()


func set_sneaking(on: bool) -> void:
	if on == sneaking:
		return
	sneaking = on
	sneak_changed.emit(on)


## Movement speed multiplier (player.gd uses it)
func get_speed_mult() -> float:
	return SNEAK_SPEED if sneaking else 1.0


## Something loud happened (a swing): heard for a moment
func make_noise(seconds: float) -> void:
	_noise_until = _time + seconds


# ---------------------------------------------------------------- awareness

func awareness_of(e: Node) -> float:
	return float(awareness.get(e.get_instance_id(), 0.0)) if e != null else 0.0


func is_detected_by(e: Node) -> bool:
	return awareness_of(e) >= SEEN


## 0 = hidden, 1 = noticed, 2 = seen (by the most aware living creature nearby)
func detection_level() -> int:
	var best := 0.0
	for id in awareness:
		var n := instance_from_id(id) as Enemy
		if n != null and is_instance_valid(n) and not n.is_dead():
			best = maxf(best, float(awareness[id]))
	return 2 if best >= SEEN else (1 if best >= NOTICED else 0)


## How easy the player is to see right now (1 = standing in daylight)
func visibility() -> float:
	var light := 1.0
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		light = 0.75 if dm.is_in_building() else 0.5
	else:
		var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
		if clock != null:
			light = 0.3 + 0.7 * clock.get_daylight()
	var v := light
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length() if _player != null else 0.0
	if sneaking:
		var skill := _skills.get_level(&"sneak") if _skills != null else 1
		v *= 0.45 * (1.0 - float(skill) / 200.0)
		if speed < 0.2:
			v *= 0.8
	elif speed > 6.0:
		v *= 1.3
	elif speed < 0.2:
		v *= 0.85
	return v


## How far away the player can be heard right now (meters, through walls)
func noise_radius() -> float:
	if _time < _noise_until:
		return 6.0 if sneaking else 12.0
	if sneaking or _player == null:
		return 0.0
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed > 6.0:
		return 14.0
	if speed > 0.5:
		return 5.0
	return 0.0


func _process(delta: float) -> void:
	_time += delta
	if _head != null:
		_head.position.y = lerpf(_head.position.y, HEAD_SNEAK if sneaking else HEAD_STAND, clampf(delta * 10.0, 0.0, 1.0))
	_timer += delta
	if _timer >= TICK and not get_tree().paused:
		update_awareness(_timer)
		_timer = 0.0
	_update_hud()


## One step of everyone's awareness (dt seconds). Runs on its own; tests call it directly.
func update_awareness(dt: float) -> void:
	if _player == null:
		return
	var vis := visibility()
	var noise := noise_radius()
	var seen_ids := {}
	var watched_unseen := false
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or not e.is_inside_tree():
			continue
		var d := e.global_position.distance_to(_player.global_position)
		if d > RANGE:
			continue
		var id := e.get_instance_id()
		seen_ids[id] = true
		var a := float(awareness.get(id, 0.0))
		if e.get_meta("asleep", false):
			awareness[id] = maxf(a - dt, 0.0)
			continue
		if e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK:
			awareness[id] = 1.2  # in a fight with someone: fully aware of everything
			continue
		var gain := 0.0
		var reach := maxf(SEE_RANGE * vis, 1.5)
		if d < reach and _can_see(e, d):
			gain += 0.6 + 3.0 * (1.0 - d / reach)
		if d < noise:
			gain += 2.0
		a = clampf(a + gain * dt if gain > 0.0 else a - 0.25 * dt, 0.0, 1.2)
		awareness[id] = a
		if d < 15.0 and a < SEEN:
			watched_unseen = true
	for id in awareness.keys():
		if not seen_ids.has(id):
			awareness.erase(id)
	# Sneaking near people without being seen trains Sneak
	if sneaking and watched_unseen and _skills != null and Vector2(_player.velocity.x, _player.velocity.z).length() > 0.3:
		_xp_timer += dt
		if _xp_timer >= 1.0:
			_xp_timer -= 1.0
			_skills.add_xp(&"sneak", 0.6)


func _can_see(e: Enemy, d: float) -> bool:
	if d > 0.5 and not e.is_alerted():
		var forward := -e.global_transform.basis.z
		forward.y = 0.0
		var to := _player.global_position - e.global_position
		to.y = 0.0
		if forward.length() > 0.01 and to.length() > 0.01 and forward.normalized().angle_to(to.normalized()) > deg_to_rad(FOV_DEG * 0.5):
			return false
	var from := e.head.global_position if e.head != null else e.global_position + Vector3.UP * 1.4
	var target := _head.global_position if _head != null else _player.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, target, Enemy.WORLD_LAYER, [e.get_rid(), _player.get_rid()])
	var hit := e.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or not (hit["collider"] is StaticBody3D)


# ---------------------------------------------------------------- sneak attacks

## Damage multiplier for a hit on `victim` (1 = not a sneak attack)
func sneak_attack_mult(victim: Node, weapon: ItemData) -> float:
	var e := victim as Enemy
	if e == null or e.is_dead():
		return 1.0
	var asleep := bool(e.get_meta("asleep", false))
	if not asleep:
		if e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK or e.state == Enemy.State.FLEE or e.state == Enemy.State.STAGGER:
			return 1.0
		if is_detected_by(e):
			return 1.0
	var m := 3.0 if weapon != null and weapon.animation_set == &"dagger" else 2.0
	if _stats != null:
		m *= 1.0 + _stats.get_stat("sneak_attack_bonus")
	return m


# ---------------------------------------------------------------- the eye

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_eye = Eye.new()
	_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye.anchor_left = 0.5
	_eye.anchor_right = 0.5
	_eye.offset_left = -40
	_eye.offset_right = 40
	_eye.offset_top = 70
	_eye.offset_bottom = 104
	_hud.add_child(_eye)
	_eye_label = Label.new()
	_eye_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eye_label.anchor_left = 0.5
	_eye_label.anchor_right = 0.5
	_eye_label.offset_left = -80
	_eye_label.offset_right = 80
	_eye_label.offset_top = 104
	_eye_label.offset_bottom = 128
	_eye_label.add_theme_constant_override("outline_size", 5)
	_eye_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_eye_label)


func _update_hud() -> void:
	var show := sneaking and not get_tree().paused
	_eye.visible = show
	_eye_label.visible = show
	if not show:
		return
	var level := detection_level()
	var best := 0.0
	for id in awareness:
		best = maxf(best, float(awareness[id]))
	var eye := _eye as Eye
	if eye.level != level or absf(eye.fill - best) > 0.02:
		eye.level = level
		eye.fill = best
		eye.queue_redraw()
	_eye_label.text = ["Hidden", "Noticed", "Seen"][level]
	_eye_label.add_theme_color_override("font_color", [Color(0.8, 0.8, 0.85), Color(1.0, 0.8, 0.25), Color(1.0, 0.35, 0.3)][level])
