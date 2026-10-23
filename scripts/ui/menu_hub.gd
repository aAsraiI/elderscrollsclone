class_name MenuHub
extends CanvasLayer
## The Tab menu: one bar across the top that joins the Inventory, Map, Character and Journal
## screens, Skyrim style. Created by player.gd.
##
##   Tab           open the menu (on the page you used last), or close it
##   1 2 3 4 5     switch page (or click the buttons on the bar)
##   I M C J P     open that page directly, or switch to it while the menu is open
##   Esc           close
## Each page is still its own screen (InventoryUI, WorldDebugMap, StatsUI, JournalUI); this only
## switches between them and draws the bar. The bar also shows the time, your gold and weight.

const PAGES := [
	{"id": "inventory", "label": "Inventory", "key": KEY_I},
	{"id": "map", "label": "Map", "key": KEY_M},
	{"id": "character", "label": "Character", "key": KEY_C},
	{"id": "journal", "label": "Journal", "key": KEY_J},
	{"id": "magic", "label": "Magic", "key": KEY_P},
]

var _bar: PanelContainer
var _buttons: Array[Button] = []
var _info: Label
var _last := 0
var _player: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	add_to_group("menu_hub")
	_player = get_parent()
	_build_ui()
	_bar.visible = false


## Which page is open (-1 = none)
func current_page() -> int:
	for i in PAGES.size():
		var p := _page(i)
		if p != null and p.call("is_open"):
			return i
	return -1


func open_page(index: int) -> void:
	var now := current_page()
	if now == index:
		return
	var p := _page(index)
	if p == null:
		return
	# Closing a page captures the mouse, which jumps it to the middle of the screen:
	# put it back where it was once the next page is open
	var mouse := get_viewport().get_mouse_position()
	if now >= 0:
		_page(now).call("close")
	p.call("open")
	if p.call("is_open"):
		_last = index
	if now >= 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(mouse)


## The page number of a page id ("magic" -> 4)
func page_index(id: String) -> int:
	for i in PAGES.size():
		if PAGES[i]["id"] == id:
			return i
	return 0


func close_menu() -> void:
	var now := current_page()
	if now >= 0:
		_page(now).call("close")


func _page(index: int) -> Node:
	match String(PAGES[index]["id"]):
		"inventory":
			return _player.get_node_or_null("InventoryUI")
		"character":
			return _player.get_node_or_null("StatsUI")
		"journal":
			return _player.get_node_or_null("JournalUI")
		"magic":
			return _player.get_node_or_null("MagicUI")
		"map":
			var m := get_tree().get_first_node_in_group("world_map")
			return m if m != null and (m as WorldDebugMap)._manager != null and (m as WorldDebugMap)._manager.map != null else null
	return null


# Runs before the screens and the GUI see the key, so Tab never moves the focus around
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y:
		# Controller: Y opens and closes the menu like Tab
		if current_page() < 0:
			if not get_tree().paused and _can_open():
				open_page(_last)
		else:
			close_menu()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	var now := current_page()
	if now < 0:
		if key == KEY_TAB and not get_tree().paused and _can_open():
			open_page(_last)
			get_viewport().set_input_as_handled()
		return
	if _over_dialogue():
		return  # the journal opened from a conversation: leave it alone
	if key == KEY_TAB:
		close_menu()
		get_viewport().set_input_as_handled()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return  # typing in a search box
	var target := -1
	if key >= KEY_1 and key <= KEY_5:
		target = key - KEY_1
	else:
		for i in PAGES.size():
			if PAGES[i]["key"] == key and i != now:
				target = i
		if target == 2 and PAGES[now]["id"] == "map":
			target = -1  # C centers the map on you
	if target >= 0 and target < PAGES.size() and _page(target) != null:
		open_page(target)
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	var stats := _player.get_node_or_null("Stats") as Stats
	return stats == null or not stats.is_dead


func _over_dialogue() -> bool:
	var j := _player.get_node_or_null("JournalUI") as JournalUI
	return j != null and j.is_open() and bool(j.get("_was_paused"))


func _process(_delta: float) -> void:
	var now := current_page()
	_bar.visible = now >= 0 and not _over_dialogue()
	if not _bar.visible:
		return
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == now)
		_buttons[i].disabled = _page(i) == null
	_info.text = _info_text()


func _info_text() -> String:
	var parts := PackedStringArray()
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock != null:
		parts.append("Day %d  %s" % [clock.day, clock.get_time_text()])
	var inv := _player.get_node_or_null("Inventory") as Inventory
	var stats := _player.get_node_or_null("Stats") as Stats
	if inv != null:
		parts.append("%d gold" % Currency.get_gold(inv))
		if stats != null:
			parts.append("%.0f / %.0f weight" % [inv.get_total_weight(), stats.get_stat("carry_capacity")])
	return "     ".join(parts)


func _build_ui() -> void:
	_bar = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.96)
	style.border_color = UITheme.GOLD_DIM
	style.border_width_bottom = 1
	style.content_margin_left = 16
	style.content_margin_right = 16
	_bar.add_theme_stylebox_override("panel", style)
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = UITheme.HUB_BAR_HEIGHT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_bar.add_child(row)
	var hint := UITheme.hint("Tab  close")
	hint.custom_minimum_size = Vector2(200, 0)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in PAGES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.text = PAGES[i]["label"]
		b.custom_minimum_size = Vector2(104, 0)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var idx := i
		b.pressed.connect(func() -> void: open_page(idx))
		row.add_child(b)
		_buttons.append(b)
		# Selected page: gold underline instead of a box
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color(0, 0, 0, 0)
		sel.border_color = UITheme.GOLD
		sel.border_width_bottom = 2
		sel.content_margin_left = 10
		sel.content_margin_right = 10
		sel.content_margin_top = 6
		sel.content_margin_bottom = 6
		var off := StyleBoxEmpty.new()
		off.content_margin_top = 6
		off.content_margin_bottom = 6
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
		b.add_theme_stylebox_override("disabled", off)

	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_info = UITheme.hint("")
	_info.custom_minimum_size = Vector2(200, 0)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_info)
