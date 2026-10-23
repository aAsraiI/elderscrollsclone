class_name FavoritesMenu
extends CanvasLayer
## Q: a quick list of your favorite spells and items (mark them with F in the Inventory or the
## Magic page). Click one, or press its number: spells go into the off hand, weapons and armor are
## equipped, potions and food are used. The game is paused while it is open.
##
## Quick slots: point at a favorite in the list and press 1-8 to put it on that number key (press
## the same number again to take it off). While playing, that key uses it without opening the list.
## Nothing extra is shown on screen; the list shows which key each favorite is on.

const ACTION := "favorites"
const QUICK_SLOTS := 8

var _root: Control
var _list: VBoxContainer
var _is_open := false
var _book: Spellbook
var _hover_key := ""  # the favorite the mouse is over in the list


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	_book = get_parent().get_node_or_null("Spellbook") as Spellbook
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_Q
		InputMap.action_add_event(ACTION, ev)
	_root = MarginContainer.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_root.offset_left = 40
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	_root.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UITheme.heading("Favorites"))
	_list = VBoxContainer.new()
	v.add_child(_list)
	v.add_child(UITheme.hint("[1-9] or click to use    [Q / Esc] Close\nPoint at one and press [1-8] to put it on that key\nMark favorites with F in the Inventory or Magic page"))
	_root.visible = false


func is_open() -> bool:
	return _is_open


func _unhandled_input(event: InputEvent) -> void:
	var number := _number_key(event)
	# While playing: a number key uses whatever sits on that quick slot
	if not _is_open and number > 0 and number <= QUICK_SLOTS and not get_tree().paused:
		if use_quick_slot(number):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION) and not _is_open:
		if get_tree().paused:
			return
		_set_open(true)
		get_viewport().set_input_as_handled()
	elif _is_open and (event.is_action_pressed(ACTION) or event.is_action_pressed("ui_cancel")):
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif _is_open and number > 0:
		if _hover_key != "" and number <= QUICK_SLOTS and _book != null:
			_book.set_quick_slot(number, _hover_key)  # pointing at one: put it on that key
			_refresh()
		else:
			var keys := _keys()
			if number - 1 < keys.size():
				_use(keys[number - 1])
		get_viewport().set_input_as_handled()


# 1-9 from a key press (not with Ctrl, not a held repeat), else 0
func _number_key(event: InputEvent) -> int:
	if not (event is InputEventKey) or not event.pressed or event.echo or (event as InputEventKey).ctrl_pressed:
		return 0
	var k := (event as InputEventKey).physical_keycode
	return k - KEY_1 + 1 if k >= KEY_1 and k <= KEY_9 else 0


## Uses the favorite on number key `slot` (1-8). False if nothing usable is on it.
func use_quick_slot(slot: int) -> bool:
	if _book == null:
		return false
	var key := String(_book.quick_slots.get(str(slot), ""))
	if key == "" or not _keys().has(key):
		return false  # empty, or no longer carried / known
	_use(key)
	return true


func _set_open(open: bool) -> void:
	_is_open = open
	_root.visible = open
	_hover_key = ""
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_refresh()


func _keys() -> Array[String]:
	var out: Array[String] = []
	if _book == null:
		return out
	var inv := get_parent().get_node_or_null("Inventory") as Inventory
	for k in _book.favorites:
		if k.begins_with("spell:"):
			if _book.knows(k.trim_prefix("spell:")):
				out.append(k)
		else:
			var it := SaveUtil.path_to_item(k)
			if it != null and inv != null and inv.has_item(it):
				out.append(k)
	return out


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var keys := _keys()
	if keys.is_empty():
		_list.add_child(UITheme.hint("No favorites yet."))
		return
	var inv := get_parent().get_node_or_null("Inventory") as Inventory
	var eq := get_parent().get_node_or_null("Equipment") as Equipment
	for i in keys.size():
		var k := keys[i]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		var slot := _book.quick_slot_of(k)
		var on_key := "    [key %d]" % slot if slot > 0 else ""
		if k.begins_with("spell:"):
			var s := _book.get_spell(k.trim_prefix("spell:"))
			b.text = "%d.  ✦ %s%s%s" % [i + 1, s.display_name, "  (equipped)" if s.id == _book.equipped_id else "", on_key]
		else:
			var it := SaveUtil.path_to_item(k)
			var worn := eq != null and eq.is_equipped(it)
			b.text = "%d.  %s  x%d%s%s" % [i + 1, it.display_name, inv.get_count(it), "  (equipped)" if worn else "", on_key]
		b.pressed.connect(_use.bind(k))
		b.mouse_entered.connect(func() -> void: _hover_key = k)
		b.mouse_exited.connect(func() -> void: if _hover_key == k: _hover_key = "")
		_list.add_child(b)


func _use(k: String) -> void:
	var player := get_parent()
	if k.begins_with("spell:"):
		var id := k.trim_prefix("spell:")
		if _book.equipped_id == id:
			_book.unequip_spell()
		else:
			_book.equip_spell(id)
	else:
		var it := SaveUtil.path_to_item(k)
		if it == null:
			return
		if it.is_consumable():
			var fx := player.get_node_or_null("StatusEffects") as StatusEffects
			if fx != null:
				fx.use_item(it)
		elif ItemUse.verb(player, it) != "":
			ItemUse.use(player, it)
		else:
			var eq := player.get_node_or_null("Equipment") as Equipment
			if eq != null:
				eq.toggle(it)
	if _is_open:
		_set_open(false)
