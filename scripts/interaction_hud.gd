class_name InteractionHUD
extends CanvasLayer
## Crosshair + "what am I looking at" prompt. Built entirely in code.
## Setup: add a CanvasLayer node named InteractionHUD as a child of the Player and attach
## this script. It finds your Interactor on its own. The prompt text comes from whatever the
## ray is pointing at (WorldItem, ContainerComponent, or anything with get_prompt()).

@export var interactor: Interactor
## Show the key in front of the text, e.g. "[E] Open Old Chest"
@export var show_key_hint := true

var _root: Control
var _crosshair: Crosshair
var _label: Label


# Small dot in the middle of the screen; grows a gold ring when you're looking at something usable
class Crosshair extends Control:
	var active := false

	func set_active(value: bool) -> void:
		if value != active:
			active = value
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 4.0 if active else 3.0, Color(0, 0, 0, 0.55))  # dark outline for contrast
		draw_circle(c, 2.5 if active else 1.8, Color(1.0, 0.85, 0.35) if active else Color(1, 1, 1, 0.9))
		if active:
			draw_arc(c, 9.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.35, 0.9), 1.5, true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # so it can hide itself while a menu pauses the game
	layer = 5  # below the menus (layer 10)
	_build_ui()

	if interactor == null:
		interactor = _find_interactor(get_parent())
	if interactor == null:
		push_warning("InteractionHUD: could not find an Interactor under the Player. Assign one in the Inspector.")
		return
	interactor.prompt_changed.connect(_on_prompt_changed)
	_on_prompt_changed("")


func _process(_delta: float) -> void:
	_root.visible = not get_tree().paused  # hidden behind inventory / stats / loot screens


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_crosshair = Crosshair.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -12
	_crosshair.offset_right = 12
	_crosshair.offset_top = -12
	_crosshair.offset_bottom = 12
	_root.add_child(_crosshair)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.5
	_label.anchor_bottom = 0.5
	_label.offset_left = 0
	_label.offset_right = 0
	_label.offset_top = 26
	_label.offset_bottom = 60
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_root.add_child(_label)


func _on_prompt_changed(text: String) -> void:
	if text == "":
		_label.text = ""
		_crosshair.set_active(false)
		return
	_label.text = "[%s] %s" % [_key_name(), text] if show_key_hint else text
	# Taking it is a crime: say so in red
	_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if text.begins_with("Steal") else Color.WHITE)
	_crosshair.set_active(true)


func _key_name() -> String:
	if InputMap.has_action("interact"):
		for ev in InputMap.action_get_events("interact"):
			if ev is InputEventKey:
				# Physical keys are stored by keyboard position; ask for the label on the player's layout
				var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
				var labeled: Key = DisplayServer.keyboard_get_keycode_from_physical(code)
				return OS.get_keycode_string(labeled if labeled != KEY_NONE else code)
			return ev.as_text().get_slice(" (", 0)  # mouse / gamepad buttons
	return "E"


func _find_interactor(node: Node) -> Interactor:
	for child in node.get_children():
		if child is Interactor:
			return child
		var deeper := _find_interactor(child)
		if deeper != null:
			return deeper
	return null
