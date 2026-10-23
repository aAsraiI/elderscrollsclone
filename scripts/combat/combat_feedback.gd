class_name CombatFeedback
extends CanvasLayer
## Everything that tells you what a hit did, built entirely in code. Created by PlayerCombat.
## Layers the same hit with several cues, scaled to how big the hit was:
##   hitstop        the game freezes for a few hundredths of a second on impact
##   camera shake   and a roll when you are hit, a FOV punch when you swing
##   hit marker     around the crosshair: white = hit, gold = heavy, orange = stagger, red = kill
##   charge ring    around the crosshair while you hold left click, flashes when it is ready
##   damage vignette + a red arc showing which direction you were hit from
##   enemy bar      health (and a thin poise line) of the last enemy you hit
##   short messages "PARRY!", "Out of stamina"
## Each one can be turned down with the exports below.

@export var combat: MeleeCombat
@export var camera: Camera3D
@export var hitstop_enabled := true
@export var shake_enabled := true
@export_range(0.0, 2.0, 0.05) var shake_strength := 1.0
@export var show_enemy_bar := true

const GOLD := Color(1.0, 0.85, 0.35)
const BAR_W := 340.0

# Draws markers, rings and the bar on top of everything else on this layer
class Overlay extends Control:
	var owner_fx: CombatFeedback

	func _draw() -> void:
		if owner_fx != null:
			owner_fx.draw_overlay(self)


var _root: Control
var _vignette: TextureRect
var _overlay: Overlay
var _toast: Label
var _trauma := 0.0
var _roll := 0.0
var _fov_kick := 0.0
var _base_fov := 75.0
var _vig := 0.0
var _flash := 0.0
var _toast_time := 0.0
var _hitstop_until_msec := 0
var _markers: Array[Dictionary] = []
var _hit_dirs: Array[Dictionary] = []
var _bar_target: MeleeCombat
var _bar_time := 0.0
var _ready_pulse := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # so it can hide itself while a menu pauses the game
	layer = 4  # under the crosshair HUD (5) and the menus (10)
	var parent := get_parent()
	if combat == null:
		combat = parent.get_node_or_null("MeleeCombat") as MeleeCombat
	if camera == null:
		camera = parent.get_node_or_null("Head/Camera3D") as Camera3D
	if camera != null:
		_base_fov = camera.fov
	_build_ui()
	if combat == null:
		push_warning("CombatFeedback: could not find the player's MeleeCombat.")
		return
	combat.hit_dealt.connect(_on_hit_dealt)
	combat.damaged.connect(_on_damaged)
	combat.blocked.connect(_on_blocked)
	combat.block_broken.connect(_on_block_broken)
	combat.parried.connect(_on_parried)
	combat.attack_failed.connect(_on_attack_failed)
	combat.phase_changed.connect(_on_phase_changed)
	combat.charge_ready.connect(_on_charge_ready)
	if combat.stats != null:
		combat.stats.died.connect(_on_died)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if camera != null and is_instance_valid(camera):
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0
		camera.fov = _base_fov


func _process(delta: float) -> void:
	# Hitstop is measured in real time: `delta` is slowed down by the very thing we are timing
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _hitstop_until_msec:
		Engine.time_scale = 1.0
	var paused := get_tree().paused
	_root.visible = not paused
	if paused:
		return

	var d := delta / maxf(Engine.time_scale, 0.05)  # real seconds, so effects fade at a steady pace
	_trauma = maxf(_trauma - 2.2 * d, 0.0)
	_roll = lerpf(_roll, 0.0, 1.0 - exp(-9.0 * d))
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-10.0 * d))
	_vig = maxf(_vig - 1.1 * d, 0.0)
	_flash = maxf(_flash - 3.5 * d, 0.0)
	_ready_pulse = maxf(_ready_pulse - 4.0 * d, 0.0)
	_toast_time = maxf(_toast_time - d, 0.0)
	_toast.modulate.a = clampf(_toast_time / 0.35, 0.0, 1.0)
	_vignette.modulate.a = clampf(_vig, 0.0, 0.9)

	for i in range(_markers.size() - 1, -1, -1):
		_markers[i]["life"] = float(_markers[i]["life"]) - d
		if float(_markers[i]["life"]) <= 0.0:
			_markers.remove_at(i)
	for i in range(_hit_dirs.size() - 1, -1, -1):
		_hit_dirs[i]["life"] = float(_hit_dirs[i]["life"]) - d
		if float(_hit_dirs[i]["life"]) <= 0.0:
			_hit_dirs.remove_at(i)

	if _bar_target != null:
		if not is_instance_valid(_bar_target):
			_bar_target = null
		else:
			_bar_time -= d
			if not _bar_target.is_alive():
				_bar_time = minf(_bar_time, 1.0)
			if _bar_time <= 0.0:
				_bar_target = null

	_apply_camera()
	_overlay.queue_redraw()


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Red screen edges, made from a radial gradient so no shader is needed
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.8, 0.0, 0.0, 0.0), Color(0.8, 0.0, 0.0, 0.0), Color(0.7, 0.0, 0.0, 0.85)])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_overlay = Overlay.new()
	_overlay.owner_fx = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_toast = Label.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.5
	_toast.anchor_bottom = 0.5
	_toast.offset_top = 70
	_toast.offset_bottom = 104
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


# ---------------------------------------------------------------- reactions

func _on_hit_dealt(target: Node, info: DamageInfo, final_amount: float) -> void:
	var color := Color.WHITE
	var size := 7.0
	var stop := 0.04
	var trauma := 0.14
	if info.heavy:
		color = GOLD
		size = 10.0
		stop = 0.075
		trauma = 0.3
	if info.kind == &"slam":
		color = GOLD
		size = 12.0
		stop = 0.09
		trauma = 0.45
	if info.kind == &"bash":
		trauma = 0.2
		stop = 0.05
	if info.staggered:
		color = Color(1.0, 0.6, 0.2)
		size += 3.0
		stop += 0.03
		trauma += 0.1
	if info.punish:
		trauma += 0.05
	if info.killed:
		color = Color(1.0, 0.25, 0.2)
		size += 4.0
		stop += 0.05
		trauma += 0.15
	if final_amount <= 0.0 and not info.killed:
		color = Color(0.6, 0.8, 1.0)
		stop = 0.03
	_markers.append({"life": 0.22, "max": 0.22, "color": color, "size": size})
	_hitstop(stop)
	_add_trauma(trauma)
	if target is MeleeCombat and target != combat and show_enemy_bar:
		_bar_target = target as MeleeCombat
		_bar_time = 4.0


func _on_damaged(info: DamageInfo, final_amount: float) -> void:
	var max_hp := 100.0
	if combat != null and combat.stats != null:
		max_hp = maxf(combat.stats.get_stat("max_health"), 1.0)
	var frac := clampf(final_amount / max_hp, 0.0, 1.0)
	_add_trauma(0.22 + frac * 1.2)
	_vig = clampf(0.3 + frac * 2.0, 0.3, 0.85)
	_hitstop(clampf(0.03 + frac * 0.1, 0.03, 0.09))
	var to_attacker := -info.direction
	_hit_dirs.append({"dir": to_attacker, "life": 1.0})
	# Tilt the view away from the side the hit came from
	var body := combat.body
	if body != null:
		var side := to_attacker.dot(body.global_transform.basis.x)
		_roll += -signf(side) * (0.03 + frac * 0.08)


func _on_blocked(_info: DamageInfo, _absorbed: float) -> void:
	_add_trauma(0.18)
	_hitstop(0.035)
	_markers.append({"life": 0.22, "max": 0.22, "color": Color(0.6, 0.8, 1.0), "size": 8.0})


func _on_block_broken() -> void:
	_add_trauma(0.5)
	_hitstop(0.08)
	_show_toast("Guard broken", Color(1.0, 0.45, 0.4))


func _on_parried(_info: DamageInfo) -> void:
	_add_trauma(0.3)
	_hitstop(0.11)
	_flash = 1.0
	_markers.append({"life": 0.35, "max": 0.35, "color": Color(0.7, 0.9, 1.0), "size": 14.0})
	_show_toast("PARRY!", Color(0.7, 0.9, 1.0))


func _on_attack_failed(reason: StringName) -> void:
	if reason == &"stamina":
		_show_toast("Out of stamina", Color(1.0, 0.45, 0.4))


func _on_phase_changed(phase: int, _duration: float) -> void:
	if phase != MeleeCombat.Phase.ACTIVE:
		return
	# A swing "whoosh": the view punches forward a little, more for a heavy swing
	if combat.is_heavy_action():
		_fov_kick += 3.5
		_add_trauma(0.06)
	else:
		_fov_kick += 1.4


func _on_charge_ready() -> void:
	_ready_pulse = 1.0


func _on_died() -> void:
	_vig = 0.9


func _show_toast(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 0.8
	_toast.modulate.a = 1.0


func _add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


# A short freeze on impact (real time, see _process)
func _hitstop(duration: float) -> void:
	if not hitstop_enabled or duration <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	_hitstop_until_msec = maxi(_hitstop_until_msec, until)
	Engine.time_scale = 0.05


func _apply_camera() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var shake := _trauma * _trauma * shake_strength if shake_enabled else 0.0
	camera.h_offset = randf_range(-1.0, 1.0) * 0.07 * shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.07 * shake
	camera.rotation.z = _roll + randf_range(-1.0, 1.0) * 0.035 * shake
	camera.fov = _base_fov + _fov_kick


# ---------------------------------------------------------------- drawing

func draw_overlay(c: Control) -> void:
	if combat == null:
		return
	var center := c.size * 0.5

	if _flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.7, 0.85, 1.0, _flash * 0.28))

	# Charge ring: fills while you hold the button, gold and pulsing when a release is a heavy attack
	var ratio := combat.get_charge_ratio()
	if ratio > 0.08:
		var charged := ratio >= 1.0
		var col := Color.WHITE.lerp(GOLD, ratio)
		col.a = 0.55 + ratio * 0.45
		c.draw_arc(center, 20.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 48, col, 3.0, true)
		if charged:
			c.draw_arc(center, 20.0 + _ready_pulse * 8.0, 0.0, TAU, 48, Color(GOLD, 0.8 * _ready_pulse), 2.0, true)

	# Hit markers: four little ticks around the crosshair that flick outward and fade
	for m in _markers:
		var t := float(m["life"]) / float(m["max"])
		var inner := 7.0 + (1.0 - t) * 6.0
		var outer := inner + float(m["size"])
		var col: Color = m["color"]
		col.a = t
		for i in 4:
			var dir := Vector2.from_angle(PI * 0.25 + float(i) * PI * 0.5)
			c.draw_line(center + dir * inner, center + dir * outer, col, 2.5, true)

	# Red arcs pointing at whatever hit you, kept pointing at the right spot as you turn
	if not _hit_dirs.is_empty() and combat.body != null:
		var forward := -combat.body.global_transform.basis.z
		forward.y = 0.0
		for h in _hit_dirs:
			var to_att: Vector3 = h["dir"]
			to_att.y = 0.0
			if forward.length() < 0.001 or to_att.length() < 0.001:
				continue
			var ang := forward.normalized().signed_angle_to(to_att.normalized(), Vector3.UP)
			var screen_angle := -ang - PI * 0.5
			var col := Color(0.9, 0.1, 0.1, clampf(float(h["life"]), 0.0, 1.0) * 0.8)
			c.draw_arc(center, 95.0, screen_angle - 0.4, screen_angle + 0.4, 16, col, 6.0, true)

	# Health and poise of the last enemy you hit
	if _bar_target != null and is_instance_valid(_bar_target) and _bar_target.stats != null:
		_draw_enemy_bar(c, _bar_target)


func _draw_enemy_bar(c: Control, t: MeleeCombat) -> void:
	var s := t.stats
	var max_hp := maxf(s.get_stat("max_health"), 1.0)
	var hp := clampf(s.health / max_hp, 0.0, 1.0)
	var x := (c.size.x - BAR_W) * 0.5
	var y := 52.0
	var fade := clampf(_bar_time / 0.5, 0.0, 1.0)
	var enemy_name := "Enemy"
	if t.body != null and "display_name" in t.body:
		enemy_name = String(t.body.get("display_name"))
		if "level" in t.body:
			enemy_name += "   Lv %d" % int(t.body.get("level"))
	var font := ThemeDB.fallback_font
	c.draw_string_outline(font, Vector2(x, y - 8.0), enemy_name, HORIZONTAL_ALIGNMENT_CENTER, BAR_W, 18, 5, Color(0, 0, 0, fade))
	c.draw_string(font, Vector2(x, y - 8.0), enemy_name, HORIZONTAL_ALIGNMENT_CENTER, BAR_W, 18, Color(1, 1, 1, fade))
	c.draw_rect(Rect2(x - 2.0, y - 2.0, BAR_W + 4.0, 16.0), Color(0, 0, 0, 0.7 * fade))
	c.draw_rect(Rect2(x, y, BAR_W, 12.0), Color(0.12, 0.05, 0.05, 0.9 * fade))
	c.draw_rect(Rect2(x, y, BAR_W * hp, 12.0), Color(0.75, 0.13, 0.13, fade))
	if t.max_poise > 0.0 and t.staggerable:
		var poise_ratio := clampf(t.poise / t.max_poise, 0.0, 1.0)
		var poise_color := Color(1.0, 0.75, 0.2, 0.9 * fade) if not t.is_stunned() else Color(1.0, 0.4, 0.2, fade)
		c.draw_rect(Rect2(x, y + 14.0, BAR_W * poise_ratio, 3.0), poise_color)
