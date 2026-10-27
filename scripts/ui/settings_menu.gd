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
var _rebinding := ""
var _rebind_button: Button
const KEYS_FIXED := [
	["Left mouse / right trigger", "Attack (hold: heavy, or draw a bow)"], ["Right mouse / left trigger", "Block, slam, cast, or aim a bow"],
	["Tab / controller Y", "Menu"], ["I M C J P, 1-5", "Menu pages"], ["F (Shift+F)", "Feed / devour / fill a bottle"],
	["F10", "Save and load slots"], ["Esc / Start", "Pause, close a menu"],
]


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
	if _rebinding != "" and event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k != KEY_ESCAPE:
			Bindings.set_key(_rebinding, k)
		if _rebind_button != null:
			_rebind_button.text = Bindings.key_name(_rebinding)
		_rebinding = ""
		get_viewport().set_input_as_handled()
		return
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
	tab_names.append("Models")
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
		if tab_name == "Models":
			grid.columns = 1
			_build_models_page(grid)
			continue
		if tab_name == "Controls":
			for r: Array in Bindings.REBINDABLE:
				var what := Label.new()
				what.text = r[1]
				what.custom_minimum_size = Vector2(260, 0)
				grid.add_child(what)
				var b := Button.new()
				b.text = Bindings.key_name(r[0])
				b.custom_minimum_size = Vector2(160, 0)
				var action: String = r[0]
				b.pressed.connect(func() -> void:
					_rebinding = action
					_rebind_button = b
					b.text = "Press a key...")
				grid.add_child(b)
			for k: Array in KEYS_FIXED:
				var what2 := Label.new()
				what2.text = k[1]
				grid.add_child(what2)
				var key := Label.new()
				key.text = k[0]
				key.add_theme_color_override("font_color", UITheme.GOLD)
				grid.add_child(key)
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
		Bindings.reset()
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


# Models: people made from your own copy of Morrowind (MwImport)
func _build_models_page(grid: GridContainer) -> void:
	var about := Label.new()
	about.text = "Use Morrowind's look: if you own Morrowind, the game can build its people, creatures, furniture, clutter, weapons, armour, items, trees, rocks, skies and ground and wall textures from your copy. They are saved in your own models folder, never in the game itself. Point it at Morrowind's \"Data Files\" folder."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(560, 0)
	grid.add_child(about)
	var path := LineEdit.new()
	path.text = MwData.find_install()
	path.placeholder_text = "...\\Morrowind\\Data Files"
	path.custom_minimum_size = Vector2(560, 0)
	grid.add_child(path)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	grid.add_child(row)
	var import := Button.new()
	import.text = "Import from Morrowind"
	row.add_child(import)
	var remove := Button.new()
	remove.text = "Remove Morrowind's look"
	row.add_child(remove)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(560, 0)
	grid.add_child(status)
	var show_count := func() -> void:
		var n := MwImport.count()
		status.text = "%d Morrowind models in use." % n if n > 0 else "Using the game's own models."
		remove.disabled = n == 0
	show_count.call()
	import.pressed.connect(func() -> void:
		if MwData.open(path.text.strip_edges()) == null:
			status.text = "No Morrowind.esm in that folder. Choose Morrowind's \"Data Files\" folder."
			return
		import.disabled = true
		status.text = "Building from Morrowind (about half a minute)..."
		await get_tree().process_frame
		await get_tree().process_frame
		var r := MwImport.run(path.text.strip_edges())
		import.disabled = false
		status.text = "Made %d models. What is already around you changes when you next enter a place or load a game." % r["made"].size()
		if not r["problems"].is_empty():
			status.text += " (%d parts could not be built.)" % r["problems"].size()
		remove.disabled = r["made"].is_empty())
	remove.pressed.connect(func() -> void:
		var n := MwImport.remove()
		show_count.call()
		status.text = "Removed %d. %s" % [n, status.text])


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
				GameSettings.set_value(key, values[i] if i < values.size() else i, get_tree())
				_sync_if_preset(key))
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
					GameSettings.set_value(key, v, get_tree())
					_sync_if_preset(key))
			grid.add_child(row)
			_controls[key] = slider


func _format(o: Dictionary, v: float) -> String:
	if v == 0.0 and o.has("zero"):
		return o["zero"]
	return String(o["fmt"]) % (v * float(o.get("scale", 1.0)))


# A preset changes several rows, and changing one of them by hand sets the preset to Custom
func _sync_if_preset(key: String) -> void:
	if key == "graphics_preset" or GameSettings.PRESET_KEYS.has(key):
		_sync_controls.call_deferred()


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
