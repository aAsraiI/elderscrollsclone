class_name MainMenu
extends Control
## The title screen (main_menu.tscn, the scene the game starts in).
##   Continue    loads the most recent save (hidden when there are none)
##   New Game    pick a world seed (blank = the default world, Random = a fresh one), then Start
##   Load Game   the save slots (the same screen as F10 in game, without Save)
##   Settings    mouse, field of view, window, volume, HUD options
##   Quit
## Everything is built in code. It owns a SaveManager whose game_scene is the game, so loading
## switches to the game scene instead of reloading this one.

@export_file("*.tscn") var game_scene := SaveManager.GAME_SCENE
@export var title := "The Elder Realms"
@export var subtitle := "an open world adventure"

var _saves: SaveManager
var _settings: SettingsMenu
var _continue: Button
var _continue_info: Label
var _load: Button
var _new_button: Button
var _new_panel: PanelContainer
var _seed_edit: LineEdit
var _buttons: VBoxContainer
var _backdrop: Backdrop
var _loading: ColorRect


# Dark sky with a soft glow and slowly rising embers
class Backdrop extends Control:
	var _embers: Array[Vector3] = []  # x, y (0..1), speed
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 70:
			_embers.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.01, 0.04)))

	func _process(delta: float) -> void:
		_t += delta
		for i in _embers.size():
			var e := _embers[i]
			e.y -= e.z * delta
			if e.y < -0.02:
				e.y = 1.02
			_embers[i] = e
		queue_redraw()

	func _draw() -> void:
		var s := size
		for e in _embers:
			var flicker := 0.5 + 0.5 * sin(_t * 3.0 + e.x * 40.0)
			draw_circle(Vector2(e.x * s.x + sin(_t + e.y * 9.0) * 6.0, e.y * s.y), 1.0 + e.z * 30.0, Color(1.0, 0.65, 0.3, 0.15 + 0.35 * flicker * (1.0 - e.y)))
		# left side darker so the menu reads well
		var shade := PackedColorArray([Color(0, 0, 0, 0.65), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.65)])
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x * 0.55, 0), Vector2(s.x * 0.55, s.y), Vector2(0, s.y)]), shade)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.apply(get_tree())

	_saves = SaveManager.new()
	_saves.name = "SaveManager"
	_saves.game_scene = game_scene
	_saves.autosave_minutes = 0.0
	add_child(_saves)
	_saves.menu.closed.connect(_on_sub_closed)
	_saves.load_failed.connect(func(_slot: String, reason: String) -> void: _saves.menu.show_toast(reason, true))

	_settings = SettingsMenu.new()
	_settings.name = "SettingsMenu"
	add_child(_settings)
	_settings.closed.connect(_on_sub_closed)

	_build_ui()
	_refresh_continue()
	_first_button().grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _new_panel.visible:
		_new_panel.visible = false
		_first_button().grab_focus()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var scene3d := MenuBackdrop.new()  # the ruined keep at dusk, behind everything
	scene3d.name = "MenuBackdrop"
	add_child(scene3d)
	_backdrop = Backdrop.new()  # embers and the shade behind the buttons, over the 3D scene
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	margin.add_child(row)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(300, 0)
	row.add_child(col)

	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(t)
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 50)
	col.add_child(gap)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	col.add_child(_buttons)
	_continue = _menu_button("Continue", _on_continue)
	_new_button = _menu_button("New Game", _on_new_game)
	_load = _menu_button("Load Game", _on_load)
	_menu_button("Settings", _on_settings)
	_menu_button("Quit", func() -> void: get_tree().quit())
	_continue_info = UITheme.hint("")
	_buttons.add_child(_continue_info)
	_buttons.move_child(_continue_info, 1)

	_new_panel = _build_new_game_panel()
	_new_panel.visible = false
	_new_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_new_panel)

	var version := UITheme.hint("v" + _saves.game_version + "    Godot " + Engine.get_version_info()["string"])
	add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -260
	version.offset_top = -28
	version.offset_right = -16
	version.offset_bottom = -10
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _menu_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(240, 34)
	b.add_theme_font_size_override("font_size", 16)
	b.flat = false
	b.pressed.connect(handler)
	b.mouse_entered.connect(b.grab_focus)
	_buttons.add_child(b)
	return b


func _build_new_game_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.heading("New Game", 16))
	var info := Label.new()
	info.text = "The world is made from a seed. The same seed always makes the same world."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(340, 0)
	info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	v.add_child(info)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	v.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "blank = the default world"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _start_new_game())
	seed_row.add_child(_seed_edit)
	var random := Button.new()
	random.text = "Random"
	random.pressed.connect(func() -> void: _seed_edit.text = str(randi() % 1000000))
	seed_row.add_child(random)
	var start := Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(0, 32)
	start.pressed.connect(_start_new_game)
	v.add_child(start)
	return panel


func _refresh_continue() -> void:
	var slot := _saves.latest_slot()
	_continue.visible = slot != ""
	_load.disabled = slot == ""
	_continue_info.visible = slot != ""
	if slot == "":
		return
	for s in _saves.list_slots():
		if s["id"] == slot:
			var meta: Dictionary = s["meta"]
			_continue_info.text = "   %s  ·  Level %d  ·  %s" % [s["label"], int(meta.get("level", 1)), String(meta.get("location", ""))]


# ---------------------------------------------------------------- buttons

func _on_continue() -> void:
	var slot := _saves.latest_slot()
	if slot == "":
		return
	await show_loading()
	if not _saves.load_game(slot):
		hide_loading()
		_saves.menu.show_toast("Could not load: " + _saves.get_last_error(), true)


## A plain screen saying the world is being built (it takes a few seconds), drawn before the
## game scene starts loading
func show_loading() -> void:
	if _loading == null:
		_loading = ColorRect.new()
		_loading.color = Color(0.02, 0.02, 0.03)
		add_child(_loading)
		_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var l := UITheme.heading("Building the world...", 18)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_loading.add_child(l)
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame


func hide_loading() -> void:
	if _loading != null:
		_loading.visible = false


func _on_new_game() -> void:
	# World Creation, then Character Creation (NewGameWizard)
	_new_panel.visible = false
	_buttons.visible = false
	var wiz := NewGameWizard.new()
	wiz.saves = _saves
	add_child(wiz)
	wiz.cancelled.connect(func() -> void:
		wiz.queue_free()
		_on_sub_closed())
	wiz.begin.connect(func(seed_text: String, rules: Dictionary, character: Dictionary) -> void:
		wiz.visible = false
		await show_loading()
		_saves.new_game(seed_text, rules, character))


func _start_new_game() -> void:
	await show_loading()
	_saves.new_game(_seed_edit.text)


func _on_load() -> void:
	_new_panel.visible = false
	_buttons.visible = false
	_saves.menu.open_menu("Pick a save, then press Load.", true)


func _on_settings() -> void:
	_new_panel.visible = false
	_buttons.visible = false
	_settings.open()


# A sub screen (slots or settings) closed: back to the buttons
func _on_sub_closed() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_buttons.visible = true
	_refresh_continue()
	_first_button().grab_focus()


func _first_button() -> Button:
	return _continue if _continue.visible else _new_button
