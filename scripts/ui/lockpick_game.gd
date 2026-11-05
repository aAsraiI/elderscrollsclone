class_name LockpickGame
extends CanvasLayer
## Alpha 1.29.1: the lockpicking minigame (Settings > Interface > Lockpicking minigame; off = the
## old roll). A lock has 1 to 5 pins (by its level). For each, a marker sweeps along the bar: press
## E, Space or click while it is inside the bright gap to set the pin. Miss and the pick breaks.
## Security (and its perks) widen the gap; harder locks narrow it and speed the marker up. Esc
## gives up. The game pauses while you pick.

signal finished(result: int)

var lock_level := 0
var pins := 1
var set_pins := 0
var _inv: Inventory
var _pos := 0.0
var _dir := 1.0
var _speed := 0.6
var _gap_at := 0.5
var _gap := 0.2
var _bar: Control
var _label: Label
var _rng := RandomNumberGenerator.new()


## Is the minigame on? (Doors call this before picking.)
static func wanted() -> bool:
	return bool(GameSettings.get_value("lock_minigame"))


## Opens the minigame for a lock. on_done gets a Locks.PickResult. Returns false (and calls
## nothing) if picking can't even start: then the caller says why as before.
static func start(tree: SceneTree, inv: Inventory, level: int, on_done: Callable) -> bool:
	if level >= 100 or inv == null or Locks.get_lockpick() == null or not inv.has_item(Locks.get_lockpick()):
		return false
	var g := LockpickGame.new()
	g.lock_level = level
	g._inv = inv
	g.finished.connect(on_done, CONNECT_ONE_SHOT)
	tree.root.add_child(g)
	return true


static func gap_for(level: int, inv: Inventory) -> float:
	var owner := inv.get_parent() if inv != null else null
	var sk := owner.get_node_or_null("Skills") as Skills if owner != null else null
	var st := owner.get_node_or_null("Stats") as Stats if owner != null else null
	var sec := float(sk.get_level(&"security")) if sk != null else 15.0
	var bonus := st.get_stat("security_bonus") if st != null else 0.0
	return clampf(0.10 + sec * 0.0025 + bonus * 0.4 - float(level) * 0.0012, 0.05, 0.6)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	pins = clampi(1 + lock_level / 25, 1, 5)
	_speed = 0.55 + float(lock_level) * 0.008
	_gap = gap_for(lock_level, _inv)
	_rng.randomize()
	_place_gap()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -240
	box.offset_right = 240
	box.offset_top = -60
	box.offset_bottom = 60
	add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(480, 36)
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	var hint := Label.new()
	hint.text = "[E / Space / click] set the pin when the marker is in the gap    [Esc] give up"
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_update_label()


func _place_gap() -> void:
	_gap_at = _rng.randf_range(_gap * 0.5 + 0.02, 1.0 - _gap * 0.5 - 0.02)


func _update_label() -> void:
	_label.text = "%s lock: pin %d of %d    (%d picks)" % [Locks.tier_name(lock_level), set_pins + 1, pins, _inv.get_count(Locks.get_lockpick())]


func _process(delta: float) -> void:
	_pos += _dir * _speed * delta
	if _pos >= 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos <= 0.0:
		_pos = 0.0
		_dir = 1.0
	_bar.queue_redraw()


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	_bar.draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.1, 0.08))
	_bar.draw_rect(Rect2((_gap_at - _gap * 0.5) * w, 2, _gap * w, h - 4), Color(0.85, 0.75, 0.35))
	for i in pins:
		var c := Color(0.5, 0.8, 0.5) if i < set_pins else Color(0.35, 0.35, 0.35)
		_bar.draw_rect(Rect2(4 + i * 12, -10, 8, 6), c)
	_bar.draw_rect(Rect2(_pos * w - 2, 0, 4, h), Color(0.95, 0.95, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_end(-1)  # gave up
	elif (event is InputEventKey and event.pressed and not event.echo and (event.keycode in [KEY_E, KEY_SPACE])) \
			or (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		press()
	else:
		return
	get_viewport().set_input_as_handled()


## Sets the pin if the marker is in the gap; else the pick breaks. (Tests call it too.)
func press() -> void:
	var sk := _inv.get_parent().get_node_or_null("Skills") as Skills if _inv.get_parent() != null else null
	if absf(_pos - _gap_at) <= _gap * 0.5:
		set_pins += 1
		if set_pins >= pins:
			if sk != null:
				sk.add_xp(&"security", 4.0 + float(lock_level) * 0.1)
			Achievements.note("lockpick")
			_end(Locks.PickResult.OPENED)
			return
		_place_gap()
	else:
		_inv.remove_item(Locks.get_lockpick(), 1)
		if sk != null:
			sk.add_xp(&"security", 1.0)
		if not _inv.has_item(Locks.get_lockpick()):
			_end(Locks.PickResult.FAILED)
			return
		set_pins = maxi(set_pins - 1, 0)  # a slip drops the last pin
	_update_label()


func _end(result: int) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit(result)
	queue_free()
