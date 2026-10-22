class_name VitalsHUD
extends CanvasLayer
## Skyrim-style Health, Magicka and Stamina bars, each on its own: magicka bottom-left,
## health bottom-middle, stamina bottom-right. Thin bars, a pale "trail" shows what you just
## lost, and each bar fades away on its own once it is full again (Settings > Interface can keep
## them showing, and turn the numbers off).
## Setup: add a CanvasLayer named VitalsHUD as a child of Player and attach this script.
## It automatically finds the Player's Stats node, or you can assign Stats in the Inspector.

@export var stats: Stats
@export var show_values := true
@export var hide_when_paused := true
@export var bottom_offset := 30.0
@export var side_offset := 40.0
@export var bar_width := 240.0
@export var health_width := 300.0
@export var bar_height := 6.0
## Seconds a full bar stays on screen after it last changed
@export var fade_delay := 3.0
@export var fade_duration := 0.6
## Never fade the bars
@export var always_visible := false

const VITALS := [
	{"id": "health", "label": "Health", "max": "max_health", "color": Color(0.78, 0.16, 0.16)},
	{"id": "magicka", "label": "Magicka", "max": "max_magicka", "color": Color(0.22, 0.42, 0.90)},
	{"id": "stamina", "label": "Stamina", "max": "max_stamina", "color": Color(0.24, 0.66, 0.30)},
]


# One thin bar: a dark track, the pale trail of what was just lost, the colored fill
class VitalBar extends Control:
	var color := Color.WHITE
	var value := 1.0
	var max_value := 1.0
	var trail := 1.0
	var _trail_wait := 0.0

	func set_values(v: float, m: float) -> void:
		var old := value
		value = v
		max_value = maxf(m, 1.0)
		if v < old:
			_trail_wait = 0.5  # hold the trail a moment, then let it drain
		if trail < v:
			trail = v
		queue_redraw()

	func _process(delta: float) -> void:
		if trail > value:
			_trail_wait -= delta
			if _trail_wait <= 0.0:
				trail = move_toward(trail, value, max_value * delta * 0.6)
				queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.55))
		draw_rect(r, Color(0.06, 0.06, 0.07, 0.85))
		var t := clampf(trail / max_value, 0.0, 1.0)
		var f := clampf(value / max_value, 0.0, 1.0)
		# Bars shrink toward the middle, like Skyrim's
		var mid := size.x * 0.5
		if t > f:
			draw_rect(Rect2(mid - mid * t, 0.0, size.x * t, size.y), Color(1.0, 0.92, 0.75, 0.55))
		if f > 0.0:
			draw_rect(Rect2(mid - mid * f, 0.0, size.x * f, size.y), color)
			draw_rect(Rect2(mid - mid * f, 0.0, size.x * f, 1.0), color.lightened(0.35))  # a thin highlight on top
		draw_rect(r.grow(1.0), Color(0.93, 0.80, 0.48, 0.30), false, 1.0)


var _root: Control
var _bars: Dictionary = {}
var _value_labels: Dictionary = {}
var _groups: Dictionary = {}  # vital id -> the Control holding its bar and label
var _since: Dictionary = {}  # vital id -> seconds since it last changed


func _ready() -> void:
	# Keep the HUD responsive while menus pause the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 6
	add_to_group("settings_listener")

	if stats == null:
		stats = get_parent().get_node_or_null("Stats") as Stats
	if stats == null:
		stats = _find_stats(get_parent())
	if stats == null:
		push_error("VitalsHUD: couldn't find a Stats node. Add this CanvasLayer under Player or assign Stats in the Inspector.")
		return

	_build_ui()
	apply_settings()
	stats.vital_changed.connect(_on_vital_changed)
	stats.stat_changed.connect(_on_stat_changed)
	_refresh_all()
	for vital in VITALS:
		_since[vital["id"]] = 0.0


## GameSettings changed (numbers on the bars, never fade)
func apply_settings() -> void:
	show_values = bool(GameSettings.get_value("hud_values"))
	always_visible = bool(GameSettings.get_value("hud_always"))
	_refresh_all()


func _process(delta: float) -> void:
	if _root == null:
		return
	if hide_when_paused:
		_root.visible = not get_tree().paused
	for vital in VITALS:
		var id: String = vital["id"]
		_since[id] = float(_since.get(id, 0.0)) + delta
		var full := _get_current_vital(id) >= stats.get_stat(vital["max"]) - 0.01
		var want := always_visible or not full or float(_since[id]) < fade_delay
		var g: Control = _groups[id]
		g.modulate.a = move_toward(g.modulate.a, 1.0 if want else 0.0, delta / maxf(fade_duration, 0.001))


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "VitalsHUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	for vital in VITALS:
		var id: String = vital["id"]
		var width := health_width if id == "health" else bar_width
		var group := Control.new()
		group.name = id.capitalize() + "Group"
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.anchor_top = 1.0
		group.anchor_bottom = 1.0
		group.offset_top = -bottom_offset - bar_height - 18.0
		group.offset_bottom = -bottom_offset
		match id:
			"health":
				group.anchor_left = 0.5
				group.anchor_right = 0.5
				group.offset_left = -width / 2.0
				group.offset_right = width / 2.0
			"magicka":
				group.offset_left = side_offset
				group.offset_right = side_offset + width
			_:
				group.anchor_left = 1.0
				group.anchor_right = 1.0
				group.offset_left = -side_offset - width
				group.offset_right = -side_offset
		_root.add_child(group)

		var label := Label.new()
		label.name = "ValueLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.anchor_right = 1.0
		label.offset_bottom = 16.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 3)
		group.add_child(label)

		var bar := VitalBar.new()
		bar.name = id.capitalize() + "Bar"
		bar.color = vital["color"]
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.anchor_right = 1.0
		bar.offset_top = -bar_height
		group.add_child(bar)

		_bars[id] = bar
		_value_labels[id] = label
		_groups[id] = group


func _on_vital_changed(vital: String, _current: float, _maximum: float) -> void:
	_refresh_vital(vital)
	_since[vital] = 0.0


func _on_stat_changed(_stat: String) -> void:
	# Maximum vitals can change when equipment or effects modify stats.
	_refresh_all()


func _refresh_all() -> void:
	if stats == null or _bars.is_empty():
		return
	for vital in VITALS:
		_refresh_vital(vital["id"])


func _refresh_vital(vital_id: String) -> void:
	if stats == null or not _bars.has(vital_id):
		return
	var definition: Dictionary = {}
	for entry in VITALS:
		if entry["id"] == vital_id:
			definition = entry
			break
	if definition.is_empty():
		return

	var current := _get_current_vital(vital_id)
	var maximum := maxf(stats.get_stat(definition["max"]), 0.0)
	var bar: VitalBar = _bars[vital_id]
	bar.set_values(clampf(current, 0.0, maximum), maximum)

	var label: Label = _value_labels[vital_id]
	label.text = "%.0f / %.0f" % [current, maximum] if show_values else ""


func _get_current_vital(vital_id: String) -> float:
	match vital_id:
		"health":
			return stats.health
		"magicka":
			return stats.magicka
		"stamina":
			return stats.stamina
	return 0.0


func _find_stats(node: Node) -> Stats:
	for child in node.get_children():
		if child is Stats:
			return child as Stats
		var found := _find_stats(child)
		if found != null:
			return found
	return null
