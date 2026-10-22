class_name SettingsMenu
extends CanvasLayer
## The Settings screen, opened from the main menu and the pause menu. Built in code from
## GameSettings.OPTIONS, so a new option only needs a line there. Every change is saved and
## applied at once. The Controls tab lists the keys.

signal closed

const KEYS := [
	["W A S D", "Move"], ["Shift", "Sprint"], ["Space", "Jump"], ["Ctrl", "Sneak"],
	["E (tap)", "Use / take / talk"], ["E (hold)", "Grab and carry"],
	["Left mouse", "Attack (hold: heavy attack)"], ["Right mouse", "Block / slam"],
	["H", "Quick health potion"],
	["Tab", "Menu (inventory, map, character, journal)"],
	["I / M / C / J", "Open that page of the menu directly"],
	["1 - 4", "Switch menu page"],
	["F5 / F9", "Quicksave / quickload"], ["F10", "Save and load slots"],
	["Esc", "Pause / close a menu"],
]

var _root: Control
var _tabs: TabBar
var _pages: Array[Control] = []
var _controls := {}  # option key -> the control showing it
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_controls()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 440)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(UITheme.heading("Settings"))
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	vbox.add_child(_tabs)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(holder)

	var tab_names: Array[String] = []
	for o: Dictionary in GameSettings.OPTIONS:
		if not tab_names.has(o["tab"]):
			tab_names.append(o["tab"])
	tab_names.append("Controls")
	for tab_name in tab_names:
		_tabs.add_tab(tab_name)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		holder.add_child(scroll)
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
		_pages.append(scroll)
		if tab_name == "Controls":
			for k: Array in KEYS:
				var key := Label.new()
				key.text = k[0]
				key.add_theme_color_override("font_color", UITheme.GOLD)
				key.custom_minimum_size = Vector2(150, 0)
				grid.add_child(key)
				var what := Label.new()
				what.text = k[1]
				grid.add_child(what)
			continue
		for o: Dictionary in GameSettings.OPTIONS:
			if o["tab"] == tab_name:
				_add_option(grid, o)
	_tabs.tab_changed.connect(_show_page)
	_show_page(0)

	vbox.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func() -> void:
		GameSettings.reset_to_defaults(get_tree())
		_sync_controls())
	buttons.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(100, 0)
	back.pressed.connect(close)
	buttons.add_child(back)


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index


func _add_option(grid: GridContainer, o: Dictionary) -> void:
	var key: String = o["key"]
	var label := Label.new()
	label.text = o["label"]
	label.custom_minimum_size = Vector2(250, 0)
	grid.add_child(label)
	match String(o["kind"]):
		"check":
			var cb := CheckBox.new()
			cb.toggled.connect(func(on: bool) -> void: GameSettings.set_value(key, on, get_tree()))
			grid.add_child(cb)
			_controls[key] = cb
		"choice":
			var ob := OptionButton.new()
			for c: String in o["choices"]:
				ob.add_item(c)
			ob.custom_minimum_size = Vector2(220, 0)
			ob.item_selected.connect(func(i: int) -> void:
				var values: Array = o.get("values", [])
				GameSettings.set_value(key, values[i] if i < values.size() else i, get_tree()))
			grid.add_child(ob)
			_controls[key] = ob
		_:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var slider := HSlider.new()
			slider.min_value = o["min"]
			slider.max_value = o["max"]
			slider.step = o["step"]
			slider.custom_minimum_size = Vector2(200, 0)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(slider)
			var value := Label.new()
			value.custom_minimum_size = Vector2(60, 0)
			row.add_child(value)
			slider.value_changed.connect(func(v: float) -> void:
				value.text = _format(o, v)
				if _open:
					GameSettings.set_value(key, v, get_tree()))
			grid.add_child(row)
			_controls[key] = slider


func _format(o: Dictionary, v: float) -> String:
	if v == 0.0 and o.has("zero"):
		return o["zero"]
	return String(o["fmt"]) % (v * float(o.get("scale", 1.0)))


# Shows the stored values (after opening, or after Reset)
func _sync_controls() -> void:
	var was_open := _open
	_open = false  # so setting the sliders does not save them again
	for o: Dictionary in GameSettings.OPTIONS:
		var key: String = o["key"]
		var c: Control = _controls.get(key)
		var v: Variant = GameSettings.get_value(key)
		if c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(v))
		elif c is OptionButton:
			var values: Array = o.get("values", [])
			(c as OptionButton).select(values.find(v) if not values.is_empty() else int(v))
		elif c is HSlider:
			(c as HSlider).value = float(v)
			((c as HSlider).get_parent().get_child(1) as Label).text = _format(o, float(v))
	_open = was_open
