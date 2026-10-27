class_name StatusHUD
extends CanvasLayer
## Small readout in the top-left corner: the day and time, the food and potion effects that are
## running (with a countdown), and short messages ("Ate Bread"). Built in code and created by
## StatusEffects, so there is nothing to add.

@export var effects: StatusEffects

const GOLD := Color(1.0, 0.85, 0.35)

var _root: Control
var _time_label: Label
var _date_label: Label
var _list_label: Label
var _toast: Label
var _toast_time := 0.0
var _clock: WorldClock
var _clock_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_build_ui()
	if effects == null:
		effects = get_parent() as StatusEffects
	if effects != null:
		effects.item_used.connect(_on_item_used)
		effects.use_failed.connect(_on_use_failed)


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(16, 12)
	_root.add_child(box)

	_time_label = _make_label(14, GOLD)
	box.add_child(_time_label)
	_date_label = _make_label(11, Color(0.85, 0.82, 0.7))
	box.add_child(_date_label)
	_list_label = _make_label(12, Color(0.85, 1.0, 0.85))
	box.add_child(_list_label)

	_toast = _make_label(15, Color.WHITE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -120
	_toast.offset_bottom = -90
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


func _process(delta: float) -> void:
	_root.visible = not get_tree().paused
	if not _root.visible:
		return
	_clock_timer -= delta
	if (_clock == null or not is_instance_valid(_clock)) and _clock_timer <= 0.0:
		_clock_timer = 0.5
		_clock = get_tree().get_first_node_in_group("world_clock") as WorldClock
	_time_label.text = "Day %d   %s" % [_clock.day, _clock.get_time_text()] if _clock != null else ""
	_date_label.text = ""
	if _clock != null and bool(GameSettings.get_value("show_date")):
		var w := Weather.get_instance(get_tree())
		_date_label.text = "%s, %s, %s%s" % [_clock.get_short_date(), _clock.get_season_name(), _clock.get_moon_name(), ("   " + w.get_name_text()) if w != null and w.enabled else ""]
		var fest := Festivals.current(_clock)
		if not fest.is_empty():
			_date_label.text += "   ·   " + String(fest["name"])

	var lines := PackedStringArray()
	if effects != null:
		for fx in effects.get_active():
			var item: ItemData = fx["item"]
			var parts := PackedStringArray()
			var mods: Dictionary = fx["mods"]
			if mods.has("health_regen"):
				parts.append("+%s HP/s" % String.num(snappedf(float(mods["health_regen"]), 0.1)).trim_suffix(".0"))
			if mods.has("stamina_regen_mult"):
				parts.append("+%d%% stamina regen" % roundi(float(mods["stamina_regen_mult"]) * 100.0))
			lines.append("%s   %s   %ds" % [item.display_name, ", ".join(parts), ceili(float(fx["remaining"]))])
	var magic := ActiveMagic.of(get_parent().get_parent()) if effects != null else null
	if magic != null:
		for fx in magic.effects:
			if String(fx["source"]).begins_with("_"):
				continue
			var harm := MagicEffects.is_harmful(fx["id"])
			lines.append("%s%s   %ds" % ["✖ " if harm else "", MagicEffects.display_name(fx["id"]), ceili(float(fx["left"]))])
	var me := get_parent().get_parent() if effects != null else null
	if me != null:
		for n in ["Survival", "Afflictions"]:
			var node := me.get_node_or_null(n)
			if node != null:
				lines.append_array(node.status_lines())
	var pz: Dictionary = get_parent().get_parent().get_meta("weapon_poison", {}) if effects != null else {}
	if not pz.is_empty():
		lines.append("Poisoned blade: %d hits" % int(pz.get("hits", 0)))
	# Wanted in the town you are in
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if world != null and player != null:
		var town := world.get_town_at(player.global_position, 60.0)
		if town != null and town.town != null and CrimeManager.get_bounty(town.id) > 0:
			lines.append("Wanted in %s: %d gold" % [town.town.display_name, CrimeManager.get_bounty(town.id)])
	_list_label.text = "\n".join(lines)

	_toast_time = maxf(_toast_time - delta, 0.0)
	_toast.modulate.a = clampf(_toast_time / 0.4, 0.0, 1.0)


func _on_item_used(item: ItemData) -> void:
	var verb := "Used"
	match item.use_verb:
		"Eat":
			verb = "Ate"
		"Drink":
			verb = "Drank"
	_show("%s %s" % [verb, item.display_name], Color.WHITE)


func _on_use_failed(reason: StringName) -> void:
	match reason:
		&"no_potion":
			_show("No health potions", Color(1.0, 0.45, 0.4))
		&"missing":
			_show("You don't have that", Color(1.0, 0.45, 0.4))


func _show(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 1.6
	_toast.modulate.a = 1.0
