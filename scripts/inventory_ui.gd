class_name InventoryUI
extends CanvasLayer
## Skyrim-style list inventory, built entirely in code (no scene needed).
## Setup: add a CanvasLayer node named InventoryUI as a child of the Player,
## attach this script. Press I (or Tab) to open. It finds the sibling Inventory / Equipment /
## Stats nodes automatically, or you can assign them in the Inspector.
##
##   category tabs     what kind of item to list          search box   only names with these letters
##   click a column    sort by it (again = the other way)  right side   turning 3D model + details,
##   E / Enter / double-click   equip, eat, drink              compared with what you have on
##   Q   drop one     Shift+Q   drop the whole stack

@export var inventory: Inventory
@export var equipment: Equipment
@export var stats: Stats

const CATEGORIES := [
	{"name": "All", "types": []},
	{"name": "Weapons", "types": [ItemData.ItemType.WEAPON]},
	{"name": "Apparel", "types": [ItemData.ItemType.ARMOR]},
	{"name": "Food & Drink", "types": [ItemData.ItemType.CONSUMABLE]},
	{"name": "Ingredients", "types": [ItemData.ItemType.INGREDIENT]},
	{"name": "Misc", "types": [ItemData.ItemType.MISC, ItemData.ItemType.KEY]},
]
const COLUMN_TITLES := ["", "Name", "Wt", "Value"]
const GOOD := Color(0.5, 0.85, 0.5)
const BAD := Color(0.9, 0.45, 0.4)

var _root: Control
var _tabs: TabBar
var _search: LineEdit
var _tree: Tree
var _details: RichTextLabel
var _equip_button: Button
var _drop_button: Button
var _weight_label: Label
var _weight_bar: ProgressBar
var _stats_label: Label
var _is_open := false
var _effects: StatusEffects
var _sort_column := -1  # -1 = the order you picked things up
var _sort_desc := false

# The turning model of the selected item
var _preview_holder: Node3D
var _preview_item: ItemData


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps working while the game is paused
	layer = 10

	var parent := get_parent()
	if inventory == null:
		inventory = parent.get_node_or_null("Inventory")
	if equipment == null:
		equipment = parent.get_node_or_null("Equipment")
	if stats == null:
		stats = parent.get_node_or_null("Stats")
	if inventory == null or equipment == null or stats == null:
		push_error("InventoryUI: could not find Inventory/Equipment/Stats. Make this node a child of the Player (next to them) or assign them in the Inspector.")
		return

	if not InputMap.has_action("inventory"):
		InputMap.add_action("inventory")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_I
		InputMap.action_add_event("inventory", ev)

	_build_ui()
	_root.visible = false

	inventory.changed.connect(_refresh)
	equipment.equipped.connect(func(_slot, _item): _refresh())
	equipment.unequipped.connect(func(_slot, _item): _refresh())
	stats.stat_changed.connect(func(_stat): _update_footer())
	stats.vital_changed.connect(func(_vital, _cur, _max): _update_footer())


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _root != null and not _is_open:
		_set_open(true)


func close() -> void:
	if _root != null and _is_open:
		_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if _root == null:
		return
	if event.is_action_pressed("inventory"):
		if not _is_open and get_tree().paused:
			return  # another menu is already open
		_set_open(not _is_open)
	elif not _is_open:
		return
	elif event.is_action_pressed("ui_cancel"):
		_set_open(false)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_activate_selected()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_drop_selected((event as InputEventKey).shift_pressed)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F and event.ctrl_pressed:
		_search.grab_focus()
	else:
		return
	get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_is_open = open
	_root.visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_refresh()
		_tree.grab_focus()


func _process(delta: float) -> void:
	if _is_open and _preview_holder != null:
		_preview_holder.rotate_y(delta * 0.8)


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
	center.offset_top = UITheme.HUB_BAR_HEIGHT  # room for the Tab menu's bar

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 540)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Category tabs and the search box
	var top := HBoxContainer.new()
	vbox.add_child(top)
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in CATEGORIES:
		_tabs.add_tab(c["name"])
	_tabs.tab_changed.connect(func(_i): _refresh())
	top.add_child(_tabs)
	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.custom_minimum_size = Vector2(200, 0)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _refresh())
	_search.text_submitted.connect(func(_t: String) -> void: _tree.grab_focus())
	top.add_child(_search)

	# List on the left, model + details on the right
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)

	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_stretch_ratio = 1.5
	_tree.columns = 4
	_tree.hide_root = true
	_tree.hide_folding = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_search = false  # so typing E / Q doesn't jump around the list
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 30)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 60)
	_tree.set_column_expand(3, false)
	_tree.set_column_custom_minimum_width(3, 64)
	_tree.item_selected.connect(_update_details)
	_tree.item_activated.connect(_activate_selected)  # Enter or double-click
	_tree.column_title_clicked.connect(_on_column_clicked)
	_update_column_titles()
	split.add_child(_tree)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	side.add_theme_constant_override("separation", 6)
	split.add_child(side)

	side.add_child(_build_preview())

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_details)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	side.add_child(buttons)
	_equip_button = Button.new()
	_equip_button.focus_mode = Control.FOCUS_NONE
	_equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_button.pressed.connect(_activate_selected)
	buttons.add_child(_equip_button)
	_drop_button = Button.new()
	_drop_button.text = "Drop (Q)"
	_drop_button.focus_mode = Control.FOCUS_NONE
	_drop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_button.pressed.connect(func() -> void: _drop_selected(Input.is_key_pressed(KEY_SHIFT)))
	buttons.add_child(_drop_button)

	# Footer: weight, key stats
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	vbox.add_child(footer)
	_weight_label = Label.new()
	footer.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(140, 4)
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_weight_bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_stats_label = Label.new()
	footer.add_child(_stats_label)

	vbox.add_child(UITheme.hint("[E / Enter] Equip, eat, drink    [Q] Drop one    [Shift+Q] Drop all    [Ctrl+F] Search    click a column to sort    [Tab / I / Esc] Close"))


# A small 3D stage of its own (own World3D) with a camera and two lights
func _build_preview() -> Control:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(0, 170)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(vp)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.6
	var cam := Camera3D.new()
	cam.environment = env
	cam.position = Vector3(0.0, 0.25, 1.9)
	cam.fov = 35.0
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(1.0, 0.85, 0.6)
	vp.add_child(rim)
	_preview_holder = Node3D.new()
	vp.add_child(_preview_holder)
	return box


func _show_preview(item: ItemData) -> void:
	if item == _preview_item:
		return
	_preview_item = item
	for c in _preview_holder.get_children():
		c.queue_free()
	if item == null:
		return
	var model := ItemModels.build_world(item)
	if item.world_scene == null and (item.item_type == ItemData.ItemType.WEAPON or item.equip_slot == ItemData.EquipSlot.OFF_HAND):
		model.rotation_degrees = Vector3(0, 0, -50) if item.secondary_action != ItemData.SecondaryAction.BLOCK else Vector3.ZERO
	var fit := Node3D.new()
	fit.add_child(model)
	var bounds := ItemModels.get_bounds(fit)
	var longest := maxf(bounds.size[bounds.get_longest_axis_index()], 0.01)
	fit.scale = Vector3.ONE * (1.0 / longest)
	model.position -= bounds.get_center()
	_preview_holder.add_child(fit)


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	if not _is_open:
		return
	var keep := _selected_item()
	_tree.clear()
	var root := _tree.create_item()
	var marked: Array[ItemData] = []
	var types: Array = CATEGORIES[_tabs.current_tab]["types"]
	var query := _search.text.strip_edges().to_lower()
	var first_row: TreeItem = null
	var keep_row: TreeItem = null

	var shown: Array = []
	for s in inventory.stacks:
		var item: ItemData = s.item
		if not types.is_empty() and not types.has(item.item_type):
			continue
		if query != "" and not item.display_name.to_lower().contains(query):
			continue
		shown.append(s)
	if _sort_column >= 0:
		shown.sort_custom(_sort_less)

	for s in shown:
		var item: ItemData = s.item
		var row := _tree.create_item(root)
		row.set_metadata(0, item)
		# Show the "E" marker once even if you carry duplicates of the equipped item
		var show_e := equipment.is_equipped(item) and not marked.has(item)
		if show_e:
			marked.append(item)
		# "E2" = the same item worn in both hands (a pair of daggers)
		var worn := equipment.equipped_count(item)
		row.set_text(0, ("E" if worn < 2 else "E%d" % worn) if show_e else "")
		row.set_custom_color(0, UITheme.GOLD)
		row.set_text(1, item.display_name + (" (%d)" % s.count if s.count > 1 else ""))
		if item.treasure:
			row.set_custom_color(1, Color(0.75, 0.85, 1.0))
		row.set_text(2, "%.1f" % item.weight)
		row.set_text(3, str(item.value))
		row.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		row.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		row.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
		if first_row == null:
			first_row = row
		if item == keep and keep_row == null:
			keep_row = row

	var target: TreeItem = keep_row if keep_row != null else first_row
	if target != null:
		target.select(0)
		_tree.scroll_to_item(target)
	_update_details()
	_update_footer()


func _sort_less(a, b) -> bool:
	var ia: ItemData = a.item
	var ib: ItemData = b.item
	var va: Variant
	var vb: Variant
	match _sort_column:
		0:
			va = 0 if equipment.is_equipped(ia) else 1
			vb = 0 if equipment.is_equipped(ib) else 1
		2:
			va = ia.weight
			vb = ib.weight
		3:
			va = ia.value
			vb = ib.value
		_:
			va = ia.display_name.to_lower()
			vb = ib.display_name.to_lower()
	if va == vb:
		return ia.display_name.to_lower() < ib.display_name.to_lower()
	return (va > vb) if _sort_desc else (va < vb)


func _on_column_clicked(column: int, _mouse_button: int) -> void:
	if _sort_column == column and _sort_desc == (column >= 2):
		_sort_desc = not _sort_desc  # second click: the other way round
	elif _sort_column == column:
		_sort_column = -1  # third click: back to pick-up order
	else:
		_sort_column = column
		_sort_desc = column >= 2  # heaviest / most valuable first
	_update_column_titles()
	_refresh()


func _update_column_titles() -> void:
	for i in COLUMN_TITLES.size():
		var t: String = COLUMN_TITLES[i] if i != 0 else "E"
		if i == _sort_column:
			t += " ▼" if _sort_desc else " ▲"
		_tree.set_column_title(i, t)


func _update_details() -> void:
	var item := _selected_item()
	_show_preview(item)
	if item == null:
		_details.text = "[color=#ffffff70]Nothing here.[/color]" if _search.text != "" else ""
		_equip_button.text = "Equip (E)"
		_equip_button.disabled = true
		_drop_button.disabled = true
		return

	var t := "[b][font_size=18]%s[/font_size][/b]\n" % item.display_name
	var type_name: String = ItemData.ItemType.keys()[item.item_type].capitalize()
	t += "[color=gray]" + type_name
	if item.equip_slot != ItemData.EquipSlot.NONE:
		t += " · " + String(ItemData.EquipSlot.keys()[item.equip_slot]).capitalize()
	t += "   ·   Weight %s   ·   Value %d[/color]\n" % [String.num(item.weight), item.value]
	var compare := _compare_text(item)
	if compare != "":
		t += compare + "\n"
	t += "\n"
	if item.description != "":
		t += item.description + "\n\n"
	var combat_text := item.get_combat_description()
	if combat_text != "":
		t += combat_text + "\n"
	for stat in item.stat_modifiers:
		var v: float = item.stat_modifiers[stat]
		t += "%s %s%s\n" % [String(stat).capitalize(), "+" if v >= 0.0 else "", String.num(v)]
	_details.text = t

	if item.is_consumable():
		_equip_button.disabled = _get_effects() == null
		_equip_button.text = "%s (E)" % item.use_verb
	else:
		var equippable := item.equip_slot != ItemData.EquipSlot.NONE
		_equip_button.disabled = not equippable
		_equip_button.text = "Unequip (E)" if equipment.is_equipped(item) else "Equip (E)"
	_drop_button.disabled = false


## "+3 damage compared with your Iron Sword" for gear you are not wearing
func _compare_text(item: ItemData) -> String:
	if item.equip_slot == ItemData.EquipSlot.NONE or equipment.is_equipped(item):
		return ""
	var slot := item.equip_slot
	if item.item_type == ItemData.ItemType.WEAPON and slot == ItemData.EquipSlot.OFF_HAND:
		slot = ItemData.EquipSlot.MAIN_HAND
	var worn := equipment.get_equipped(slot)
	var parts := PackedStringArray()
	if item.item_type == ItemData.ItemType.WEAPON:
		var mine := worn.weapon_damage if worn != null and worn.item_type == ItemData.ItemType.WEAPON else 0.0
		parts.append(_delta(item.weapon_damage - mine, "damage"))
	var armor_now := float(worn.stat_modifiers.get("armor", 0.0)) if worn != null else 0.0
	var armor_new := float(item.stat_modifiers.get("armor", 0.0))
	if armor_new != 0.0 or armor_now != 0.0:
		parts.append(_delta(armor_new - armor_now, "armor"))
	if parts.is_empty():
		return ""
	return "%s  [color=gray]vs %s[/color]" % ["   ".join(parts), worn.display_name if worn != null else "nothing"]


func _delta(d: float, what: String) -> String:
	if is_zero_approx(d):
		return "[color=gray]same %s[/color]" % what
	var c := GOOD if d > 0.0 else BAD
	return "[color=#%s]%s%s %s[/color]" % [c.to_html(false), "+" if d > 0.0 else "", String.num(d, 1).trim_suffix(".0"), what]


func _update_footer() -> void:
	var w := inventory.get_total_weight()
	var cap := stats.get_stat("carry_capacity")
	_weight_label.text = "Weight %.1f / %.0f" % [w, cap]
	_weight_label.add_theme_color_override("font_color", Color.INDIAN_RED if w > cap else UITheme.TEXT)
	_weight_bar.max_value = maxf(cap, 1.0)
	_weight_bar.value = minf(w, cap)
	_weight_bar.modulate = Color.INDIAN_RED if w > cap else Color.WHITE
	# Damage shown is what a swing of the main-hand weapon does (fists if empty)
	var main := equipment.get_main_hand()
	var swing := stats.get_stat_plus("damage", main.weapon_damage if main != null else 0.0)
	_stats_label.text = ("Gold %d    " % Currency.get_gold(inventory)) + "Armor %.0f    Damage %.0f    Health %.0f / %.0f" % [
		stats.get_stat("armor"), swing, stats.health, stats.get_stat("max_health")]


# ---------------------------------------------------------------- actions

func _selected_item() -> ItemData:
	var row := _tree.get_selected()
	if row == null:
		return null
	return row.get_metadata(0)


# Enter / E / double-click: eat or drink a consumable, otherwise equip or unequip
func _activate_selected() -> void:
	var item := _selected_item()
	if item != null and item.is_consumable():
		var fx := _get_effects()
		if fx != null:
			fx.use_item(item)
		return
	_toggle_equip_selected()


func _get_effects() -> StatusEffects:
	if not is_instance_valid(_effects):
		_effects = get_parent().get_node_or_null("StatusEffects") as StatusEffects
	return _effects


func _toggle_equip_selected() -> void:
	var item := _selected_item()
	if item == null or item.equip_slot == ItemData.EquipSlot.NONE:
		return
	equipment.toggle(item)


## Drops one (or the whole stack) in front of you. Items collide with each other, so each
## lands a little to the side of the last.
func _drop_selected(whole_stack: bool = false) -> void:
	var item := _selected_item()
	if item == null:
		return
	var amount := inventory.get_count(item) if whole_stack else 1
	if amount <= 0 or not inventory.remove_item(item, amount):
		return
	# Spawn just in front of the camera (Equipment auto-unequips if that was the last copy)
	var pos := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		pos = cam.global_position - cam.global_transform.basis.z * 1.2
	elif get_parent() is Node3D:
		pos = (get_parent() as Node3D).global_position + Vector3.UP
	pos += Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	WorldItem.spawn(item, amount, get_tree().current_scene, pos)
