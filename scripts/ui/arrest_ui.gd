class_name ArrestUI
extends CanvasLayer
## "Stop right there!" A guard has caught you: pay the fine, go to jail, or resist. Made by
## CrimeManager. The game is paused while it is open.

signal chosen(choice: String)  # "pay", "jail" or "resist"

var _open := false
var _root: Control
var _title: Label
var _text: Label
var _pay: Button
var _jail: Button
var _resist: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 18
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


func open_for(guard_name: String, town_name: String, bounty: int, gold: int, days: int) -> void:
	if _open:
		return
	_open = true
	_title.text = "%s: Stop right there!" % guard_name
	_text.text = "You have committed crimes against %s.\nYour bounty is %d gold." % [town_name, bounty]
	_pay.text = "Pay the fine (%d gold)" % bounty
	_pay.disabled = gold < bounty
	if gold < bounty:
		_pay.text += "  - not enough gold"
	_jail.text = "Go to jail (%d day%s)" % [days, "" if days == 1 else "s"]
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_jail if _pay.disabled else _pay).grab_focus()


## Picks an answer (what the buttons do)
func choose(choice: String) -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(choice)


func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	vbox.add_child(_title)
	_text = Label.new()
	vbox.add_child(_text)
	_pay = _button("pay")
	vbox.add_child(_pay)
	_jail = _button("jail")
	vbox.add_child(_jail)
	_resist = _button("resist")
	_resist.text = "Resist arrest"
	vbox.add_child(_resist)


func _button(choice: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(choose.bind(choice))
	return b
