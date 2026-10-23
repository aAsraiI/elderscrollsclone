class_name PauseMenu
extends CanvasLayer
## The pause screen (Esc): Resume, Save Game, Load Game, Settings, Main Menu, Quit Game. Built in code and created by
## player.gd. Save and Load open the slot screen from SaveManager (the F10 screen) and come back
## here when it closes. Quit asks you to press it twice.
##
## Esc only opens this when nothing else is open. If the same Esc press just closed another menu
## (inventory, loot, stats, slots), the pause screen must not pop up on top of it.

signal opened
signal closed
signal quit_requested

const CONFIRM_SECONDS := 3.0
const GOLD := Color(1.0, 0.85, 0.35)

var _root: Control
var _info: Label
var _resume: Button
var _save: Button
var _load: Button
var _quit: Button
var _settings_button: Button
var _menu_button: Button
var _menu_confirming := false
var _settings: SettingsMenu
var _status: Label
var _open := false
var _paused_last := false
var _confirm_time := 0.0
var _confirming := false
var _stats: Stats


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	add_to_group("pause_menu")
	_stats = get_parent().get_node_or_null("Stats") as Stats
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_confirm()
	_status.text = ""
	_refresh_info()
	var sm := _save_manager()
	_save.disabled = sm == null or sm.menu == null
	_load.disabled = _save.disabled
	_resume.grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_clear_confirm()
	closed.emit()


func _process(delta: float) -> void:
	var paused_now := get_tree().paused
	# _paused_last: the game was paused last frame, so this Esc belonged to the menu that just closed
	if Input.is_action_just_pressed("ui_cancel") and not _open and not paused_now and not _paused_last and _can_open():
		open()
	_paused_last = get_tree().paused
	if _confirming:
		_confirm_time -= delta
		if _confirm_time <= 0.0:
			_clear_confirm()


# Runs before the GUI, so Esc still resumes while a button has focus
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if _stats != null and _stats.is_dead:
		return false
	var sm := _save_manager()
	return sm == null or not sm.is_loading()


func _save_manager() -> SaveManager:
	return get_tree().get_first_node_in_group("save_manager") as SaveManager


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := UITheme.heading("Paused", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_color_override("font_color", GOLD)
	vbox.add_child(_info)

	_resume = _make_button("Resume", close)
	vbox.add_child(_resume)
	_save = _make_button("Save Game", _on_save)
	vbox.add_child(_save)
	_load = _make_button("Load Game", _on_load)
	vbox.add_child(_load)
	_settings_button = _make_button("Settings", _on_settings)
	vbox.add_child(_settings_button)
	_menu_button = _make_button("Main Menu", _on_main_menu)
	vbox.add_child(_menu_button)
	_quit = _make_button("Quit Game", _on_quit)
	vbox.add_child(_quit)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	vbox.add_child(_status)

	var hint := UITheme.hint("[Esc] Resume    [F5] Quicksave    [F9] Quickload")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(handler)
	return b


func _refresh_info() -> void:
	var text := ""
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock != null:
		text = "Day %d   %s" % [clock.day, clock.get_time_text()]
	text += ("    " if text != "" else "") + "Played " + SaveUtil.format_duration(SaveSession.playtime)
	# Where you are wanted
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var wanted := PackedStringArray()
	var all := CrimeManager.bounties()
	for town_id: String in all:
		var t: PlacedPOI = world.get_poi(town_id) if world != null else null
		wanted.append("%s %d" % [t.town.display_name if t != null and t.town != null else town_id, all[town_id]])
	if not wanted.is_empty():
		text += "\nBounty: " + ", ".join(wanted)
	_info.text = text


# ---------------------------------------------------------------- buttons

func _on_save() -> void:
	_open_slots("Pick a slot, then press Save.")


func _on_load() -> void:
	_open_slots("Pick a slot, then press Load.")


# Hands over to the slot screen and takes the game back when it closes
func _open_slots(hint: String) -> void:
	var sm := _save_manager()
	if sm == null or sm.menu == null:
		_status.text = "No SaveManager in the scene."
		return
	_open = false
	_root.visible = false
	if not sm.menu.closed.is_connected(_on_slots_closed):
		sm.menu.closed.connect(_on_slots_closed, CONNECT_ONE_SHOT)
	sm.menu.open_menu(hint)


func _on_slots_closed() -> void:
	if not is_inside_tree():
		return
	open()  # the slot screen unpaused the game: pause again and show this menu


func _on_quit() -> void:
	if not _confirming or _menu_confirming:
		_clear_confirm()
		_confirming = true
		_confirm_time = CONFIRM_SECONDS
		_quit.text = "Quit? Unsaved progress is lost"
		return
	_clear_confirm()
	quit_requested.emit()
	get_tree().quit()


func _clear_confirm() -> void:
	_confirming = false
	_menu_confirming = false
	if _quit != null:
		_quit.text = "Quit Game"
		_menu_button.text = "Main Menu"


# Same two-press confirmation as Quit
func _on_main_menu() -> void:
	if not _menu_confirming:
		_clear_confirm()
		_menu_confirming = true
		_confirming = true  # runs the same timer
		_confirm_time = CONFIRM_SECONDS
		_menu_button.text = "Leave? Unsaved progress is lost"
		return
	_clear_confirm()
	SaveManager.go_to_main_menu(get_tree())


# The Settings screen sits on top; this menu comes back when it closes
func _on_settings() -> void:
	if _settings == null:
		_settings = SettingsMenu.new()
		_settings.name = "SettingsMenu"
		add_child(_settings)
		_settings.closed.connect(func() -> void:
			if is_inside_tree():
				open())
	_open = false
	_root.visible = false
	_settings.open()
