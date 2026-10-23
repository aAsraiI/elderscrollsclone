class_name ContainerUI
extends CanvasLayer
## Loot screen: container contents on the left, your inventory on the right.
## Built entirely in code. Setup: add a CanvasLayer node named ContainerUI as a child of the
## Player (next to Inventory / Equipment / Stats) and attach this script. ContainerComponents
## find it on their own.

@export var inventory: Inventory
@export var equipment: Equipment

var _root: Control
var _title_label: Label
var _left: Tree
var _right: Tree
var _details: RichTextLabel
var _weight_label: Label
var _container: ContainerComponent
var _is_open := false
var _open_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	add_to_group("container_ui")

	var parent := get_parent()
	if inventory == null:
		inventory = parent.get_node_or_null("Inventory")
	if equipment == null:
		equipment = parent.get_node_or_null("Equipment")
	if inventory == null:
		push_error("ContainerUI: could not find the player's Inventory. Make this node a child of the Player (next to it) or assign it in the Inspector.")
		return

	_build_ui()
	_root.visible = false

	inventory.changed.connect(_refresh)
	if equipment != null:
		equipment.equipped.connect(func(_slot, _item): _refresh())
		equipment.unequipped.connect(func(_slot, _item): _refresh())


## Returns false if it couldn't open (e.g. another menu is already open).
func open(container: ContainerComponent) -> bool:
	if _root == null or _is_open or get_tree().paused:
		return false
	_container = container
	_title_label.text = container.display_name
	if not container.inventory.changed.is_connected(_refresh):
		container.inventory.changed.connect(_refresh)

	_is_open = true
	_open_frame = Engine.get_process_frames()
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	if container.inventory.stacks.is_empty():
		_right.grab_focus()
	else:
		_left.grab_focus()
	_update_details()
	return true


func _close() -> void:
	_is_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _container != null:
		if _container.inventory.changed.is_connected(_refresh):
			_container.inventory.changed.disconnect(_refresh)
		_container.closed.emit()
		_container = null


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	# The same key press that opened the container must not also trigger a transfer
	if Engine.get_process_frames() == _open_frame:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_transfer_selected(Input.is_key_pressed(KEY_SHIFT))
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_take_all()
	else:
		return
	get_viewport().set_input_as_handled()


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
	panel.custom_minimum_size = Vector2(1000, 580)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	vbox.add_child(columns)

	# Left: the container
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_box)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	left_box.add_child(_title_label)
	_left = _make_tree()
	left_box.add_child(_left)
	var take_all := Button.new()
	take_all.text = "Take All (R)"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.pressed.connect(_take_all)
	left_box.add_child(take_all)

	# Right: the player
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_box)
	var right_title := Label.new()
	right_title.text = "Inventory"
	right_title.add_theme_font_size_override("font_size", 20)
	right_box.add_child(right_title)
	_right = _make_tree()
	right_box.add_child(_right)

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(_details)

	_weight_label = Label.new()
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_weight_label)

	var hints := Label.new()
	hints.text = "[Enter / E / double-click] Move stack   [Shift+Enter / Shift+E] Move one   [R] Take all   [Tab] Switch list   [Esc] Close"
	hints.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(hints)


func _make_tree() -> Tree:
	var t := Tree.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.columns = 4
	t.hide_root = true
	t.hide_folding = true
	t.column_titles_visible = true
	t.select_mode = Tree.SELECT_ROW
	t.allow_search = false  # so typing E / R doesn't jump around the list
	t.set_column_title(0, "")
	t.set_column_title(1, "Name")
	t.set_column_title(2, "Wt")
	t.set_column_title(3, "Value")
	t.set_column_expand(0, false)
	t.set_column_custom_minimum_width(0, 30)
	t.set_column_expand(2, false)
	t.set_column_custom_minimum_width(2, 60)
	t.set_column_expand(3, false)
	t.set_column_custom_minimum_width(3, 60)
	t.item_selected.connect(_update_details)
	t.focus_entered.connect(_update_details)
	t.item_activated.connect(_on_activated)  # Enter or double-click
	return t


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	if not _is_open or _container == null:
		return
	_fill(_left, _container.inventory, false)
	_fill(_right, inventory, true)
	_update_details()

	var w := inventory.get_total_weight()
	var text := "Carry Weight: %.1f" % w
	var over := false
	if inventory.stats != null:
		var cap := inventory.stats.get_stat("carry_capacity")
		text += " / %.0f" % cap
		over = w > cap
	_weight_label.text = text
	_weight_label.add_theme_color_override("font_color", Color.INDIAN_RED if over else Color.WHITE)


# Rebuilds one list and keeps the selection at the same row, so you can keep pressing Enter
func _fill(tree: Tree, source: Inventory, mark_equipped: bool) -> void:
	var idx := 0
	var selected := tree.get_selected()
	if selected != null:
		idx = selected.get_index()

	tree.clear()
	var root := tree.create_item()
	var marked: Array[ItemData] = []
	for s in source.stacks:
		var item: ItemData = s.item
		var row := tree.create_item(root)
		row.set_metadata(0, {"item": item, "count": s.count})
		var show_e := false
		if mark_equipped and equipment != null:
			show_e = equipment.is_equipped(item) and not marked.has(item)
			if show_e:
				marked.append(item)
		row.set_text(0, "E" if show_e else "")
		row.set_text(1, item.display_name + (" (%d)" % s.count if s.count > 1 else ""))
		row.set_text(2, "%.1f" % item.weight)
		row.set_text(3, str(item.value))
		row.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		row.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		row.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)

	var n := root.get_child_count()
	if n > 0:
		var target := root.get_child(clampi(idx, 0, n - 1))
		target.select(0)
		tree.scroll_to_item(target)


func _update_details() -> void:
	if _details == null:
		return
	var row := _active_tree().get_selected()
	if row == null:
		_details.text = ""
		return
	var item: ItemData = row.get_metadata(0)["item"]
	var t := "[b][font_size=20]%s[/font_size][/b]  " % item.display_name
	t += "[color=gray]" + String(ItemData.ItemType.keys()[item.item_type]).capitalize()
	if item.equip_slot != ItemData.EquipSlot.NONE:
		t += " · " + String(ItemData.EquipSlot.keys()[item.equip_slot]).capitalize()
	t += "[/color]\n"
	if item.description != "":
		t += item.description + "\n"
	for stat in item.stat_modifiers:
		var v: float = item.stat_modifiers[stat]
		t += "%s %s%s   " % [String(stat).capitalize(), "+" if v >= 0.0 else "", String.num(v)]
	_details.text = t


# ---------------------------------------------------------------- actions

func _active_tree() -> Tree:
	return _right if _right.has_focus() else _left


func _on_activated() -> void:
	_transfer_selected(Input.is_key_pressed(KEY_SHIFT))


func _transfer_selected(single: bool) -> void:
	if _container == null:
		return
	var tree := _active_tree()
	var row := tree.get_selected()
	if row == null:
		return
	var data: Dictionary = row.get_metadata(0)
	var item: ItemData = data["item"]
	var amount: int = 1 if single else data["count"]
	var from_inv: Inventory = _container.inventory if tree == _left else inventory
	var to_inv: Inventory = inventory if tree == _left else _container.inventory
	if from_inv.remove_item(item, amount):
		to_inv.add_item(item, amount)
		_note_ownership(item, amount, tree == _left)


# Taking from someone else's container is theft (CrimeManager); putting it back undoes the mark
func _note_ownership(item: ItemData, amount: int, taken: bool) -> void:
	if _container == null or _container.owner_id == "":
		return
	var crime := get_tree().get_first_node_in_group("crime") as CrimeManager
	if crime == null:
		return
	if taken:
		crime.on_taken(item, amount)
	else:
		crime.on_returned(item, amount)


func _take_all() -> void:
	if _container == null:
		return
	# Total per item first, because stacks change while we move things
	var totals := {}
	for s in _container.inventory.stacks:
		totals[s.item] = totals.get(s.item, 0) + s.count
	for item in totals:
		var amount: int = totals[item]
		if _container.inventory.remove_item(item, amount):
			inventory.add_item(item, amount)
			_note_ownership(item, amount, true)
