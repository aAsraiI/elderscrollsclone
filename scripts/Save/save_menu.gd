class_name SaveMenu
extends CanvasLayer
## The Save / Load screen (F10), built entirely in code. Created by SaveManager.
## Pick a slot, then Save, Load or Delete. Loading, deleting and starting a new game ask you to
## press the button a second time. New Game takes a seed (blank = the default world, a number
## or any text = that world; the same seed always gives the same world).
## Also owns the small "Quicksaved" message and the black screen shown while loading.

## The slot screen was closed (the pause menu listens, to come back)
signal closed

const ACTION := "save_menu"
const CONFIRM_SECONDS := 3.0
const GOLD := Color(1.0, 0.85, 0.35)

var manager: SaveManager

var _root: Control
var _tree: Tree
var _seed_label: Label
var _seed_edit: LineEdit
var _save_button: Button
var _load_button: Button
var _delete_button: Button
var _new_button: Button
var _status: Label
var _toast: Label
var _overlay: ColorRect
var _is_open := false
var _slots: Array[Dictionary] = []
var _confirm := ""
var _confirm_time := 0.0
var _toast_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	manager = get_parent() as SaveManager
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F10
		InputMap.action_add_event(ACTION, ev)
	_build_ui()
	_root.visible = false


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.6, 0.0, 1.0)
		if _toast_time <= 0.0:
			_toast.visible = false
	if _confirm != "":
		_confirm_time -= delta
		if _confirm_time <= 0.0:
			_clear_confirm()


# Runs before the GUI sees the key, so F10 / Esc still work while the seed box has focus
func _input(event: InputEvent) -> void:
	if manager == null or manager.is_loading():
		return
	if event.is_action_pressed(ACTION):
		if not _is_open and get_tree().paused:
			return  # another menu is already open
		_set_open(not _is_open)
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed("ui_cancel"):
		if _seed_edit.has_focus():
			_seed_edit.release_focus()
		else:
			_set_open(false)
		get_viewport().set_input_as_handled()


## Opens the slot screen directly (the pause menu uses this). `hint` goes in the status line.
func open_menu(hint: String = "") -> void:
	if manager == null or manager.is_loading() or _is_open:
		return
	_set_open(true)
	_status.text = hint


## Small message at the top of the screen
func show_toast(text: String, is_error: bool = false) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if is_error else GOLD)
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_time = 2.5


## Black screen while a load is being applied
func set_loading(on: bool) -> void:
	_overlay.visible = on


func _set_open(open: bool) -> void:
	_is_open = open
	_root.visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	_clear_confirm()
	if open:
		_status.text = ""
		_refresh()
		_tree.grab_focus()
	else:
		closed.emit()


# ---------------------------------------------------------------- building

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
	panel.custom_minimum_size = Vector2(960, 560)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Save / Load"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_seed_label = Label.new()
	_seed_label.add_theme_color_override("font_color", GOLD)
	header.add_child(_seed_label)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 6
	_tree.hide_root = true
	_tree.hide_folding = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_search = false
	var titles := ["Slot", "Saved", "Played", "Level", "Location", "Seed"]
	for i in titles.size():
		_tree.set_column_title(i, titles[i])
	_tree.set_column_custom_minimum_width(0, 110)
	_tree.set_column_custom_minimum_width(1, 160)
	_tree.set_column_expand(1, false)
	for col in [2, 3, 5]:
		_tree.set_column_expand(col, false)
	_tree.set_column_custom_minimum_width(2, 80)
	_tree.set_column_custom_minimum_width(3, 55)
	_tree.set_column_custom_minimum_width(5, 100)
	_tree.item_selected.connect(_update_buttons)
	_tree.item_activated.connect(_on_activated)  # Enter or double-click
	vbox.add_child(_tree)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)
	_save_button = _make_button("Save", _on_save)
	buttons.add_child(_save_button)
	_load_button = _make_button("Load", _on_load)
	buttons.add_child(_load_button)
	_delete_button = _make_button("Delete", _on_delete)
	buttons.add_child(_delete_button)

	vbox.add_child(HSeparator.new())

	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 8)
	vbox.add_child(new_row)
	var seed_title := Label.new()
	seed_title.text = "New game seed:"
	new_row.add_child(seed_title)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "blank = default world, or a number / any text"
	_seed_edit.custom_minimum_size = Vector2(340, 0)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _on_new_game())
	new_row.add_child(_seed_edit)
	_new_button = _make_button("New Game", _on_new_game)
	new_row.add_child(_new_button)

	_status = Label.new()
	_status.add_theme_color_override("font_color", GOLD)
	vbox.add_child(_status)

	var hints := Label.new()
	hints.text = "[Enter / double-click] Load (or Save into an empty slot)   [F10 / Esc] Close   Load, Delete and New Game need a second press"
	hints.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(hints)

	# Toast and loading screen live on their own layer so they show even when this menu is closed
	var hud := CanvasLayer.new()
	hud.layer = 30
	add_child(hud)
	_toast = Label.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.offset_top = 36
	_toast.offset_bottom = 70
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(_toast)
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.visible = false
	hud.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 0)
	b.pressed.connect(handler)
	return b


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	var keep := _selected_id()
	_slots = manager.list_slots()
	_tree.clear()
	var root := _tree.create_item()
	var keep_row: TreeItem = null
	var first_row: TreeItem = null
	for s in _slots:
		var row := _tree.create_item(root)
		row.set_metadata(0, s["id"])
		row.set_text(0, s["label"])
		var meta: Dictionary = s["meta"]
		if s["exists"] and not meta.is_empty():
			row.set_text(1, String(meta.get("time_text", "")).replace("T", "  "))
			row.set_text(2, SaveUtil.format_duration(float(meta.get("playtime", 0.0))))
			row.set_text(3, str(int(meta.get("level", 1))))
			row.set_text(4, String(meta.get("location", "")))
			row.set_text(5, str(int(meta.get("seed", 0))))
		elif s["exists"]:
			row.set_text(1, "(details unreadable)")
		else:
			row.set_text(1, "- empty -")
			row.set_custom_color(1, Color(1, 1, 1, 0.4))
		for col in [2, 3, 5]:
			row.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)
		if first_row == null:
			first_row = row
		if s["id"] == keep and keep_row == null:
			keep_row = row
	var target := keep_row if keep_row != null else first_row
	if target != null:
		target.select(0)
		_tree.scroll_to_item(target)
	var world := manager.get_tree().get_first_node_in_group("world_manager") as WorldManager
	_seed_label.text = "Current world seed: %d" % world.world_seed if world != null else ""
	_update_buttons()


func _selected_id() -> String:
	if _tree == null:
		return ""
	var row := _tree.get_selected()
	return String(row.get_metadata(0)) if row != null else ""


func _selected_slot() -> Dictionary:
	var id := _selected_id()
	for s in _slots:
		if s["id"] == id:
			return s
	return {}


func _update_buttons() -> void:
	_clear_confirm()
	var s := _selected_slot()
	var has := not s.is_empty()
	var exists: bool = has and s["exists"]
	_save_button.disabled = not has or s["id"] == SaveManager.AUTOSAVE
	_load_button.disabled = not exists
	_delete_button.disabled = not exists


# ---------------------------------------------------------------- actions

func _on_activated() -> void:
	var s := _selected_slot()
	if s.is_empty():
		return
	if s["exists"]:
		_on_load()
	else:
		_on_save()


func _on_save() -> void:
	var s := _selected_slot()
	if s.is_empty() or s["id"] == SaveManager.AUTOSAVE:
		return
	if s["exists"] and not _confirmed("save", _save_button, "Overwrite?"):
		return
	if manager.save_game(s["id"]):
		_status.text = "Saved to %s." % s["label"]
		_refresh()
	else:
		_status.text = "Could not save: " + manager.get_last_error()


func _on_load() -> void:
	var s := _selected_slot()
	if s.is_empty() or not s["exists"]:
		return
	if not _confirmed("load", _load_button, "Load? Unsaved progress is lost"):
		return
	if not manager.load_game(s["id"]):
		_status.text = "Could not load: " + manager.get_last_error()
		_refresh()


func _on_delete() -> void:
	var s := _selected_slot()
	if s.is_empty() or not s["exists"]:
		return
	if not _confirmed("delete", _delete_button, "Delete?"):
		return
	manager.delete_slot(s["id"])
	_status.text = "Deleted %s." % s["label"]
	_refresh()


func _on_new_game() -> void:
	if not _confirmed("new", _new_button, "Start over?"):
		return
	manager.new_game(_seed_edit.text)


# First press only arms the button and changes its text; a second press within a few seconds goes through
func _confirmed(action: String, button: Button, ask_text: String) -> bool:
	if _confirm == action:
		_clear_confirm()
		return true
	_clear_confirm()
	_confirm = action
	_confirm_time = CONFIRM_SECONDS
	button.text = ask_text
	return false


func _clear_confirm() -> void:
	_confirm = ""
	if _save_button == null:
		return
	_save_button.text = "Save"
	_load_button.text = "Load"
	_delete_button.text = "Delete"
	_new_button.text = "New Game"
