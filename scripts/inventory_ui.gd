class_name InventoryUI
extends CanvasLayer
## Skyrim-style list inventory, built entirely in code (no scene needed).
## Setup: add a CanvasLayer node named InventoryUI as a child of the Player,
## attach this script. Press I to open. It finds the sibling Inventory / Equipment /
## Stats nodes automatically, or you can assign them in the Inspector.

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

var _root: Control
var _tabs: TabBar
var _tree: Tree
var _details: RichTextLabel
var _equip_button: Button
var _drop_button: Button
var _weight_label: Label
var _stats_label: Label
var _is_open := false
var _effects: StatusEffects


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
		_drop_selected()
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
	panel.custom_minimum_size = Vector2(920, 560)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Category tabs
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	for c in CATEGORIES:
		_tabs.add_tab(c["name"])
	_tabs.tab_changed.connect(func(_i): _refresh())
	vbox.add_child(_tabs)

	# List on the left, details on the right
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)

	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_stretch_ratio = 1.6
	_tree.columns = 4
	_tree.hide_root = true
	_tree.hide_folding = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_search = false  # so typing E / Q doesn't jump around the list
	_tree.set_column_title(0, "")
	_tree.set_column_title(1, "Name")
	_tree.set_column_title(2, "Wt")
	_tree.set_column_title(3, "Value")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 30)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 70)
	_tree.set_column_expand(3, false)
	_tree.set_column_custom_minimum_width(3, 70)
	_tree.item_selected.connect(_update_details)
	_tree.item_activated.connect(_activate_selected)  # Enter or double-click
	split.add_child(_tree)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	split.add_child(side)

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_details)

	_equip_button = Button.new()
	_equip_button.focus_mode = Control.FOCUS_NONE
	_equip_button.pressed.connect(_activate_selected)
	side.add_child(_equip_button)

	_drop_button = Button.new()
	_drop_button.text = "Drop (Q)"
	_drop_button.focus_mode = Control.FOCUS_NONE
	_drop_button.pressed.connect(_drop_selected)
	side.add_child(_drop_button)

	# Footer: weight, key stats, key hints
	var footer := HBoxContainer.new()
	vbox.add_child(footer)
	_weight_label = Label.new()
	_weight_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_weight_label)
	_stats_label = Label.new()
	footer.add_child(_stats_label)

	var hints := Label.new()
	hints.text = "[Enter / E] Equip / Eat / Drink   [Q] Drop one   [I / Esc] Close"
	hints.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(hints)


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	if not _is_open:
		return
	var keep := _selected_item()
	_tree.clear()
	var root := _tree.create_item()
	var marked: Array[ItemData] = []
	var types: Array = CATEGORIES[_tabs.current_tab]["types"]
	var first_row: TreeItem = null
	var keep_row: TreeItem = null

	for s in inventory.stacks:
		var item: ItemData = s.item
		if not types.is_empty() and not types.has(item.item_type):
			continue
		var row := _tree.create_item(root)
		row.set_metadata(0, item)
		# Show the "E" marker once even if you carry duplicates of the equipped item
		var show_e := equipment.is_equipped(item) and not marked.has(item)
		if show_e:
			marked.append(item)
		# "E2" = the same item worn in both hands (a pair of daggers)
		var worn := equipment.equipped_count(item)
		row.set_text(0, ("E" if worn < 2 else "E%d" % worn) if show_e else "")
		row.set_text(1, item.display_name + (" (%d)" % s.count if s.count > 1 else ""))
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


func _update_details() -> void:
	var item := _selected_item()
	if item == null:
		_details.text = ""
		_equip_button.text = "Equip (E)"
		_equip_button.disabled = true
		_drop_button.disabled = true
		return

	var t := "[b][font_size=22]%s[/font_size][/b]\n" % item.display_name
	var type_name: String = ItemData.ItemType.keys()[item.item_type].capitalize()
	t += "[color=gray]" + type_name
	if item.equip_slot != ItemData.EquipSlot.NONE:
		t += " · " + String(ItemData.EquipSlot.keys()[item.equip_slot]).capitalize()
	t += "[/color]\n\n"
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


func _update_footer() -> void:
	var w := inventory.get_total_weight()
	var cap := stats.get_stat("carry_capacity")
	_weight_label.text = "Weight: %.1f / %.0f" % [w, cap]
	_weight_label.add_theme_color_override("font_color", Color.INDIAN_RED if w > cap else Color.WHITE)
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


func _drop_selected() -> void:
	var item := _selected_item()
	if item == null:
		return
	if not inventory.remove_item(item, 1):
		return
	# Spawn just in front of the camera (Equipment auto-unequips if that was the last copy)
	var pos := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		pos = cam.global_position - cam.global_transform.basis.z * 1.2
	elif get_parent() is Node3D:
		pos = (get_parent() as Node3D).global_position + Vector3.UP
	WorldItem.spawn(item, 1, get_tree().current_scene, pos)
