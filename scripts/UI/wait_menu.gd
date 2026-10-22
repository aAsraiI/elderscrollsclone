class_name WaitMenu
extends CanvasLayer
## T: wait (or rest) a number of hours. Not while enemies are hunting you. Waiting heals a little
## each hour. The world catches up at once: people are where the clock says, the weather moves on.

const ACTION := "wait"

var _root: Control
var _slider: HSlider
var _label: Label
var _date: Label
var _is_open := false
## Sleeping in a bed (null = just waiting)
var _bed: RestSpot
var _heading: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event(ACTION, ev)
	_build()
	_root.visible = false


func is_open() -> bool:
	return _is_open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not _is_open:
		if get_tree().paused:
			return
		var why := _cant_wait()
		if why != "":
			Locks.toast(get_tree(), why, true)
		else:
			_bed = null
			_set_open(true)
		get_viewport().set_input_as_handled()
	elif _is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed(ACTION)):
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed("ui_accept"):
		_wait()
		get_viewport().set_input_as_handled()


func _cant_wait() -> String:
	var aff := get_parent().get_node_or_null("Afflictions") as Afflictions
	if aff != null and aff.blocks_rest():
		return "The beast will not rest"
	var player := get_parent() as Node3D
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e.disposition == Enemy.Disposition.HOSTILE and e.is_alerted() \
				and e.global_position.distance_to(player.global_position) < 40.0:
			return "You can't wait with enemies nearby"
	var stats := player.get_node_or_null("Stats") as Stats
	if stats != null and stats.is_dead:
		return "You are dead"
	if get_tree().get_first_node_in_group("world_clock") == null:
		return "Time doesn't pass here"
	return ""


func _set_open(open: bool) -> void:
	_is_open = open
	if _heading != null:
		_heading.text = "SLEEP" if _bed != null else "WAIT"
	_root.visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_update_label(_slider.value)
		_slider.grab_focus()


func _build() -> void:
	_root = CenterContainer.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_heading = UITheme.heading("Wait")
	v.add_child(_heading)
	_date = Label.new()
	v.add_child(_date)
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = 24
	_slider.step = 1
	_slider.value = 1
	_slider.value_changed.connect(_update_label)
	v.add_child(_slider)
	_label = Label.new()
	v.add_child(_label)
	var row := HBoxContainer.new()
	v.add_child(row)
	var go := Button.new()
	go.text = "Wait"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_wait)
	row.add_child(go)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: _set_open(false))
	row.add_child(cancel)
	v.add_child(UITheme.hint("[Enter] Wait    [Esc / T] Cancel"))


## E on a bed: the same screen, but sleeping (fatigue, Well Rested, full health)
func open_sleep(bed: RestSpot) -> void:
	var why := _cant_wait()
	if why != "":
		Locks.toast(get_tree(), why, true)
		return
	_bed = bed
	_slider.value = 8
	_set_open(true)


func _update_label(hours: float) -> void:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock == null:
		return
	_date.text = "%s, %s" % [clock.get_date_text(), clock.get_time_text()]
	var until := fposmod(clock.hour + hours, 24.0)
	_label.text = "%d hour%s  (until %02d:%02d)" % [int(hours), "" if hours == 1.0 else "s", int(until), int(fmod(until, 1.0) * 60.0)]


func _wait() -> void:
	var hours := _slider.value
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	_set_open(false)
	if clock == null:
		return
	clock.advance_hours(hours)
	clock.apply_now()
	var weather := Weather.get_instance(get_tree())
	if weather != null:
		weather.hours_left -= hours
	var stats := get_parent().get_node_or_null("Stats") as Stats
	if stats != null:
		var part := clampf(hours * 0.1, 0.0, 1.0)
		stats.modify_vital("health", stats.get_stat("max_health") * part)
		stats.modify_vital("magicka", stats.get_stat("max_magicka"))
		stats.modify_vital("stamina", stats.get_stat("max_stamina"))
	if _bed != null and is_instance_valid(_bed):
		_bed.on_slept()
		var surv := get_parent().get_node_or_null("Survival") as Survival
		if surv != null:
			surv.on_sleep(hours)
		if stats != null:
			stats.modify_vital("health", stats.get_stat("max_health"))
		var aff := get_parent().get_node_or_null("Afflictions") as Afflictions
		var magic := ActiveMagic.of(get_parent())
		if magic != null and hours >= 4.0 and (aff == null or not aff.werewolf):
			magic.remove_effect(&"well_rested")
			magic.apply_list([{"id": &"well_rested", "mag": 10, "dur": 480.0}], null, "Well Rested", "potion")
		Locks.toast(get_tree(), "You slept %d hours and feel rested." % int(hours))
		_bed = null
		return
	Locks.toast(get_tree(), "You waited %d hour%s. %s" % [int(hours), "" if hours == 1.0 else "s", clock.get_time_text()])
