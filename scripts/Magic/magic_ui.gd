class_name MagicUI
extends CanvasLayer
## The Magic page of the Tab menu (P opens it directly): every spell you know by school, what it
## does and costs, and the effects on you right now. E puts a spell in your off hand (right mouse
## button casts it); F adds it to the favorites (Q in game). Self-made spells can be forgotten.
## Also adds the casting hand you see in first person (SpellHandView).

const ACTION := "magic_menu"

var _root: Control
var _tree: Tree
var _details: RichTextLabel
var _effects: RichTextLabel
var _equipped: Label
var _equip_button: Button
var _fav_button: Button
var _forget_button: Button
var _is_open := false
var _book: Spellbook
var _skills: Skills


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_book = get_parent().get_node_or_null("Spellbook") as Spellbook
	_skills = get_parent().get_node_or_null("Skills") as Skills
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_P
		InputMap.action_add_event(ACTION, ev)
	_build_ui()
	_root.visible = false
	if _book != null:
		_book.changed.connect(func() -> void:
			if _is_open:
				_refresh())
		_book.learned.connect(func(s: SpellData) -> void: Locks.toast(get_tree(), "New spell: %s" % s.display_name))
	_add_hand.call_deferred()


func _add_hand() -> void:
	var cam := get_parent().get_node_or_null("Head/Camera3D") as Node3D
	if cam != null and cam.get_node_or_null("SpellHandView") == null:
		var hand := SpellHandView.new()
		hand.name = "SpellHandView"
		cam.add_child(hand)


func is_open() -> bool:
	return _is_open


func open() -> void:
	if not _is_open:
		_set_open(true)


func close() -> void:
	if _is_open:
		_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		if not _is_open and get_tree().paused:
			return
		var hub := get_parent().get_node_or_null("MenuHub") as MenuHub
		if not _is_open and hub != null:
			hub.open_page(hub.page_index("magic"))
		else:
			_set_open(not _is_open)
	elif not _is_open:
		return
	elif event.is_action_pressed("ui_cancel"):
		_set_open(false)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_equip_selected()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_fav_selected()
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
	center.offset_top = UITheme.HUB_BAR_HEIGHT
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 540)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var top := HBoxContainer.new()
	vbox.add_child(top)
	top.add_child(UITheme.heading("Spells"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_equipped = Label.new()
	top.add_child(_equipped)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.columns = 3
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Spell")
	_tree.set_column_title(1, "Form")
	_tree.set_column_title(2, "Cost")
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 80)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 60)
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_search = false
	_tree.item_selected.connect(_update_details)
	_tree.item_activated.connect(_equip_selected)
	split.add_child(_tree)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(side)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_details)
	var buttons := HBoxContainer.new()
	side.add_child(buttons)
	_equip_button = _button(buttons, "Equip (E)", _equip_selected)
	_fav_button = _button(buttons, "Favorite (F)", _fav_selected)
	_forget_button = _button(buttons, "Forget", _forget_selected)
	side.add_child(UITheme.heading("Active effects", 14))
	_effects = RichTextLabel.new()
	_effects.bbcode_enabled = true
	_effects.custom_minimum_size = Vector2(0, 140)
	side.add_child(_effects)
	vbox.add_child(UITheme.hint("[E] Equip in the off hand (right click casts)    [F] Favorite (Q in game)    Learn spells from tomes; make your own at an Altar of Spellmaking    [Tab / P / Esc] Close"))


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _refresh() -> void:
	if _book == null:
		return
	var keep := _selected()
	_tree.clear()
	var root := _tree.create_item()
	var groups := {}
	var select: TreeItem = null
	for s in _book.sorted_spells():
		var school := s.get_school()
		if not groups.has(school):
			var g := _tree.create_item(root)
			g.set_text(0, MagicEffects.SCHOOL_NAMES.get(school, "Magic"))
			g.set_custom_color(0, MagicEffects.SCHOOL_COLORS.get(school, Color.WHITE))
			g.set_selectable(0, false)
			g.set_selectable(1, false)
			g.set_selectable(2, false)
			groups[school] = g
		var row := _tree.create_item(groups[school])
		var mark := "● " if s.id == _book.equipped_id else ""
		var star := "  ★" if _book.is_favorite("spell:" + s.id) else ""
		row.set_text(0, mark + s.display_name + star)
		row.set_text(1, SpellData.FORM_NAMES[s.form])
		row.set_text(2, str(roundi(s.get_cost(_level(s)))) + ("/s" if s.form == SpellData.Form.SPRAY else ""))
		row.set_metadata(0, s.id)
		if s.id == keep or (keep == "" and select == null):
			select = row
	if select != null:
		select.select(0)
	var eq := _book.get_equipped()
	_equipped.text = "Off hand: %s" % (eq.display_name if eq != null else "nothing")
	_update_details()
	_update_effects()


func _level(s: SpellData) -> int:
	return _skills.get_level(s.get_school()) if _skills != null else 0


func _selected() -> String:
	var row := _tree.get_selected() if _tree != null else null
	return String(row.get_metadata(0)) if row != null and row.get_metadata(0) != null else ""


func _update_details() -> void:
	var s := _book.get_spell(_selected()) if _book != null else null
	_equip_button.disabled = s == null
	_fav_button.disabled = s == null
	_forget_button.disabled = s == null or not s.custom
	if s == null:
		_details.text = ""
		return
	var school := s.get_school()
	var t := "[b][font_size=18]%s[/font_size][/b]\n[color=gray]%s · %s[/color]\n\n" % [s.display_name, MagicEffects.SCHOOL_NAMES.get(school, ""), SpellData.FORM_NAMES[s.form]]
	t += s.describe(_level(s)) + "\n\n"
	t += "[color=gray]%s[/color]\n" % SpellData.FORM_HINTS[s.form]
	for e in s.effects:
		var d := MagicEffects.get_def(StringName(e["id"]))
		if String(d.get("desc", "")) != "":
			t += "[color=gray]%s: %s[/color]\n" % [d["name"], d["desc"]]
	_details.text = t
	_equip_button.text = "Unequip (E)" if s.id == _book.equipped_id else "Equip (E)"


func _update_effects() -> void:
	var m := ActiveMagic.of(get_parent())
	var lines := PackedStringArray()
	if m != null:
		for fx in m.effects:
			lines.append("%s  [color=gray](%s, %ds left)[/color]" % [MagicEffects.describe({"id": fx["id"], "mag": fx["mag"], "dur": 0.0}),
				fx["source"] if String(fx["source"]) != "" and not String(fx["source"]).begins_with("_") else String(fx["group"]).capitalize(), maxi(int(fx["left"]), 0)])
	var poison: Dictionary = get_parent().get_meta("weapon_poison", {})
	if not poison.is_empty():
		lines.append("[color=#8f8]Weapon poisoned:[/color] %s (%d hits)" % [poison.get("name", ""), int(poison.get("hits", 0))])
	_effects.text = "\n".join(lines) if not lines.is_empty() else "[color=gray]None[/color]"


func _equip_selected() -> void:
	var id := _selected()
	if id == "" or _book == null:
		return
	if _book.equipped_id == id:
		_book.unequip_spell()
	else:
		_book.equip_spell(id)
	_refresh()


func _fav_selected() -> void:
	var id := _selected()
	if id != "":
		_book.toggle_favorite("spell:" + id)
		_refresh()


func _forget_selected() -> void:
	var id := _selected()
	var s := _book.get_spell(id)
	if s != null and s.custom:
		_book.forget(id)
		_refresh()
