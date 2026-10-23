class_name CouncilUI
extends CanvasLayer
## The Regency Council board, a page of the Tab menu (K): each great house's influence on the
## council that will rule for Princess Elowen, the King's health, the player's own house, and the
## council's decision once it is made. "The Chronicle" plays the epilogue so far.

const ACTION := "council"

var _root: Control
var _body: VBoxContainer
var _open := false
var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 16
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_K
		InputMap.action_add_event(ACTION, ev)
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if not _was_paused:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		if _open:
			close()
		elif not get_tree().paused:
			open()
		else:
			return
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = UITheme.HUB_BAR_HEIGHT
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	v.add_child(UITheme.heading("The Regency Council", 20))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	v.add_child(_body)
	var row := HBoxContainer.new()
	v.add_child(row)
	var chronicle := Button.new()
	chronicle.text = "The Chronicle"
	chronicle.tooltip_text = "Your story so far, as it would be told"
	chronicle.pressed.connect(func() -> void:
		close()
		Epilogue.play(get_tree(), "The Chronicle of Caldreth"))
	row.add_child(chronicle)
	v.add_child(UITheme.hint("When King Aldren dies, the house with the most influence rules for Elowen, unless you are sworn to a house.\nA house that finishes its last quest takes the council at once.    [K / Tab / Esc] Close"))


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var today := clock.day if clock != null else 1
	var king := Regency.king_state(today)
	var king_text: String = {"alive": "King Aldren IV is alive, and failing.", "saved": "King Aldren IV lives on, cured for one more year.",
		"dead": "King Aldren IV is dead."}[king]
	_body.add_child(_line(king_text, Color(0.86, 0.82, 0.74)))
	if Regency.is_settled():
		_body.add_child(_line(String(Regency.result()["text"]), UITheme.GOLD))
	var mine := Regency.player_house()
	_body.add_child(_line("You are sworn to %s." % Factions.display_name(mine) if mine != "" else "You are sworn to no house.", Color(0.7, 0.7, 0.68)))
	_body.add_child(HSeparator.new())
	var inf := Regency.influence()
	var houses := inf.keys()
	houses.sort_custom(func(a: String, b: String) -> bool: return int(inf[a]) > int(inf[b]))
	var top := float(inf[houses[0]]) if not houses.is_empty() else 1.0
	for h: String in houses:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var name_l := _line(Factions.display_name(h) + ("  (yours)" if h == mine else ""), UITheme.GOLD if h == mine else Color(0.9, 0.88, 0.82), false)
		name_l.custom_minimum_size = Vector2(220, 0)
		r.add_child(name_l)
		var bar := ProgressBar.new()
		bar.max_value = maxf(top, 1.0)
		bar.value = int(inf[h])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(380, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(bar)
		var num := _line(str(inf[h]), Color(0.8, 0.8, 0.78), false)
		num.custom_minimum_size = Vector2(32, 0)
		r.add_child(num)
		_body.add_child(r)
	for h in Regency.left_council():
		_body.add_child(_line("%s has left the council." % Factions.display_name(h), Color(0.75, 0.5, 0.45)))


func _line(text: String, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	return l
