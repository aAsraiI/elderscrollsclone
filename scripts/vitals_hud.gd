class_name VitalsHUD
extends CanvasLayer
## Skyrim-inspired Health, Magicka and Stamina bars.
## Setup: add a CanvasLayer named VitalsHUD as a child of Player and attach this script.
## It automatically finds the Player's Stats node, or you can assign Stats in the Inspector.

@export var stats: Stats
@export var show_values := true
@export var hide_when_paused := true
@export var bottom_offset := 28.0
@export var bar_width := 230.0
@export var fade_delay := 4.0
@export var fade_duration := 1.0

const VITALS := [
	{"id": "health", "label": "HEALTH", "max": "max_health", "color": Color(0.72, 0.12, 0.13)},
	{"id": "magicka", "label": "MAGICKA", "max": "max_magicka", "color": Color(0.16, 0.34, 0.78)},
	{"id": "stamina", "label": "STAMINA", "max": "max_stamina", "color": Color(0.18, 0.58, 0.25)},
]

var _root: Control
var _bars: Dictionary = {}
var _value_labels: Dictionary = {}
var _time_since_activity := 0.0


func _ready() -> void:
	# Keep the HUD responsive while menus pause the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 6

	if stats == null:
		stats = get_parent().get_node_or_null("Stats") as Stats
	if stats == null:
		stats = _find_stats(get_parent())
	if stats == null:
		push_error("VitalsHUD: couldn't find a Stats node. Add this CanvasLayer under Player or assign Stats in the Inspector.")
		return

	_build_ui()
	stats.vital_changed.connect(_on_vital_changed)
	stats.stat_changed.connect(_on_stat_changed)
	_refresh_all()


func _process(delta: float) -> void:
	if _root == null:
		return

	if hide_when_paused:
		_root.visible = not get_tree().paused

	_time_since_activity += delta
	var target_alpha := 1.0 if _time_since_activity < fade_delay else 0.0
	var tint := _root.modulate
	tint.a = move_toward(tint.a, target_alpha, delta / maxf(fade_duration, 0.001))
	_root.modulate = tint


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "VitalsHUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var panel := PanelContainer.new()
	panel.name = "VitalsPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	# Three bars plus two row gaps, inner margins and panel borders.
	# The previous width calculation was too small for three full-width bars,
	# which caused the panel contents to extend off-center.
	var panel_width := bar_width * 3.0 + 24.0 + 12.0 + 2.0
	panel.offset_left = -panel_width / 2.0
	panel.offset_right = panel_width / 2.0
	panel.offset_top = -bottom_offset - 42.0
	panel.offset_bottom = -bottom_offset
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.025, 0.03, 0.72)
	panel_style.border_color = Color(0.65, 0.58, 0.40, 0.65)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	for vital in VITALS:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(bar_width, 25)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(holder)

		var bar := ProgressBar.new()
		bar.name = String(vital["id"]).capitalize() + "Bar"
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = vital["color"]
		fill.set_corner_radius_all(3)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.055, 0.055, 0.06, 0.98)
		back.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		holder.add_child(bar)

		var label := Label.new()
		label.name = "ValueLabel"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		label.add_theme_constant_override("outline_size", 4)
		holder.add_child(label)

		_bars[vital["id"]] = bar
		_value_labels[vital["id"]] = label


func _on_vital_changed(vital: String, _current: float, _maximum: float) -> void:
	_refresh_vital(vital)
	_reveal_hud()


func _on_stat_changed(_stat: String) -> void:
	# Maximum vitals can change when equipment or effects modify stats.
	_refresh_all()
	_reveal_hud()


func _reveal_hud() -> void:
	_time_since_activity = 0.0
	if _root != null:
		var tint := _root.modulate
		tint.a = 1.0
		_root.modulate = tint


func _refresh_all() -> void:
	if stats == null:
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
	var bar: ProgressBar = _bars[vital_id]
	bar.max_value = maxf(maximum, 1.0)
	bar.value = clampf(current, 0.0, maximum)

	var label: Label = _value_labels[vital_id]
	if show_values:
		label.text = "%s  %.0f / %.0f" % [definition["label"], current, maximum]
	else:
		label.text = definition["label"]


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
