class_name StatsUI
extends CanvasLayer
## Character screen, built entirely in code (no scene needed).
## Setup: add a CanvasLayer node named StatsUI as a child of the Player (next to
## Stats, Inventory, Equipment and Skills) and attach this script. Press C to open.
## Without a Skills node it still works as the plain stats screen.

@export var stats: Stats
@export var equipment: Equipment
@export var inventory: Inventory
@export var skills: Skills

const VITALS := [
	{"id": "health", "label": "Health", "max": "max_health", "color": Color(0.75, 0.15, 0.15)},
	{"id": "magicka", "label": "Magicka", "max": "max_magicka", "color": Color(0.2, 0.35, 0.85)},
	{"id": "stamina", "label": "Stamina", "max": "max_stamina", "color": Color(0.2, 0.65, 0.3)},
]

## Rows of the "Vitals & Combat" section. Attributes come from SkillDatabase.ATTRIBUTES;
## the passive skill stats (price multipliers, security bonus, ...) are shown on the Skills tab.
const CORE_STATS: Array[String] = ["max_health", "max_magicka", "max_stamina", "carry_capacity", "armor", "damage", "health_regen", "stamina_regen_mult", "move_speed_mult"]
const STAT_LABELS := {"move_speed_mult": "Move Speed", "health_regen": "Health Regen /s", "stamina_regen_mult": "Stamina Regen"}
## Shown as a percentage (1.05 -> 105%)
const PERCENT_STATS: Array[String] = ["move_speed_mult", "stamina_regen_mult"]
const GOLD := Color(1.0, 0.85, 0.35)

var _root: Control
var _vital_rows: Dictionary = {}
var _tabs: TabBar
var _attr_page: Control
var _skills_page: Control
var _tree: Tree
var _skill_tree: Tree
var _skill_details: RichTextLabel
var _equipped_label: Label
var _weight_label: Label
var _hint_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	var parent := get_parent()
	if stats == null:
		stats = parent.get_node_or_null("Stats")
	if equipment == null:
		equipment = parent.get_node_or_null("Equipment")
	if inventory == null:
		inventory = parent.get_node_or_null("Inventory")
	if skills == null:
		skills = parent.get_node_or_null("Skills") as Skills
	if stats == null or equipment == null:
		push_error("StatsUI: could not find Stats/Equipment. Make this node a child of the Player (next to them) or assign them in the Inspector.")
		return

	if not InputMap.has_action("character_sheet"):
		InputMap.add_action("character_sheet")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_C
		InputMap.action_add_event("character_sheet", ev)

	_build_ui()
	_root.visible = false

	stats.stat_changed.connect(func(_stat): _refresh())
	stats.vital_changed.connect(func(_vital, _cur, _max): _refresh())
	equipment.equipped.connect(func(_slot, _item): _refresh())
	equipment.unequipped.connect(func(_slot, _item): _refresh())
	if inventory != null:
		inventory.changed.connect(_refresh)
	if skills != null:
		skills.skill_xp_gained.connect(func(_id, _amount): _refresh())
		skills.skill_leveled_up.connect(func(_id, _level): _refresh())
		skills.player_leveled_up.connect(func(_level): _refresh())


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
	if event.is_action_pressed("character_sheet"):
		if not _is_open and get_tree().paused:
			return  # another menu (e.g. the inventory) is already open
		_set_open(not _is_open)
	elif not _is_open:
		return
	elif event.is_action_pressed("ui_cancel"):
		_set_open(false)
	elif _is_key(event, KEY_Q) or _is_key(event, KEY_E):
		if skills == null:
			return
		_tabs.current_tab = 1 - _tabs.current_tab
	elif _is_key(event, KEY_X):
		# Debug training: X = +XP, Shift+X = +1 level for the selected skill
		if skills == null or _tabs.current_tab != 1 or not skills.is_debug_enabled():
			return
		var id := _selected_skill_id()
		if id == &"":
			return
		if Input.is_key_pressed(KEY_SHIFT):
			skills.debug_level_up(id)
		else:
			skills.add_xp(id, skills.debug_xp_amount)
	else:
		return
	get_viewport().set_input_as_handled()


func _is_key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode


func _set_open(opening: bool) -> void:
	_is_open = opening
	_root.visible = opening
	get_tree().paused = opening
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
	if opening:
		_refresh()
		if skills != null and _tabs.current_tab == 1:
			_skill_tree.grab_focus()


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
	center.offset_top = UITheme.HUB_BAR_HEIGHT  # room for the Tab menu's bar

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 540)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_build_header(vbox)

	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.add_tab("Attributes")
	_tabs.add_tab("Skills")
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.visible = skills != null
	vbox.add_child(_tabs)

	_attr_page = _build_attributes_page()
	vbox.add_child(_attr_page)

	_skills_page = _build_skills_page()
	_skills_page.visible = false
	vbox.add_child(_skills_page)

	_hint_label = UITheme.hint("")
	vbox.add_child(_hint_label)
	_update_hint()


func _build_header(vbox: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var title := UITheme.heading("Character")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	if skills == null:
		return

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 16)
	_level_label.add_theme_color_override("font_color", GOLD)
	header.add_child(_level_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(220, 6)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.7, 0.25)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_xp_bar.add_theme_stylebox_override("background", back)
	header.add_child(_xp_bar)

	_xp_label = Label.new()
	_xp_label.custom_minimum_size = Vector2(110, 0)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_xp_label)


func _build_attributes_page() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)

	# Vitals: name, bar, current / max
	for v in VITALS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		page.add_child(row)

		var name_label := Label.new()
		name_label.text = v["label"]
		name_label.custom_minimum_size = Vector2(80, 0)
		row.add_child(name_label)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = v["color"]
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.08, 0.08, 0.08, 0.9)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		row.add_child(bar)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(110, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		_vital_rows[v["id"]] = {"bar": bar, "label": value_label}

	page.add_child(HSeparator.new())

	# Stat table on the left, equipped gear on the right
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	page.add_child(split)

	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_stretch_ratio = 1.8
	_tree.columns = 5
	_tree.hide_root = true
	_tree.hide_folding = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.set_column_title(0, "Stat")
	_tree.set_column_title(1, "Total")
	_tree.set_column_title(2, "Base")
	_tree.set_column_title(3, "Gear")
	_tree.set_column_title(4, "Skills")
	for col in [1, 2, 3, 4]:
		_tree.set_column_expand(col, false)
		_tree.set_column_custom_minimum_width(col, 62)
	split.add_child(_tree)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	split.add_child(side)

	var equipped_title := Label.new()
	equipped_title.text = "Equipped"
	equipped_title.add_theme_font_size_override("font_size", 14)
	equipped_title.add_theme_color_override("font_color", GOLD)
	side.add_child(equipped_title)

	_equipped_label = Label.new()
	side.add_child(_equipped_label)

	_weight_label = Label.new()
	page.add_child(_weight_label)
	return page


func _build_skills_page() -> Control:
	var page := HBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)

	_skill_tree = Tree.new()
	_skill_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_tree.size_flags_stretch_ratio = 1.4
	_skill_tree.columns = 4
	_skill_tree.hide_root = true
	_skill_tree.hide_folding = true
	_skill_tree.column_titles_visible = true
	_skill_tree.select_mode = Tree.SELECT_ROW
	_skill_tree.allow_search = false  # so typing Q / E / X doesn't jump around the list
	_skill_tree.set_column_title(0, "Skill")
	_skill_tree.set_column_title(1, "Lvl")
	_skill_tree.set_column_title(2, "XP")
	_skill_tree.set_column_title(3, "Next")
	for col in [1, 2, 3]:
		_skill_tree.set_column_expand(col, false)
	_skill_tree.set_column_custom_minimum_width(1, 45)
	_skill_tree.set_column_custom_minimum_width(2, 90)
	_skill_tree.set_column_custom_minimum_width(3, 60)
	_skill_tree.item_selected.connect(_update_skill_details)
	page.add_child(_skill_tree)

	_skill_details = RichTextLabel.new()
	_skill_details.bbcode_enabled = true
	_skill_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_details.size_flags_stretch_ratio = 1.0
	page.add_child(_skill_details)
	return page


func _update_hint() -> void:
	var t := "[C / Tab / Esc] Close"
	if skills != null:
		t += "   [Q / E] Switch tab"
		if _tabs.current_tab == 1 and skills.is_debug_enabled():
			t += "   [X] Debug: +%d XP   [Shift+X] Debug: +1 level" % int(skills.debug_xp_amount)
	_hint_label.text = t


func _on_tab_changed(_index: int) -> void:
	_attr_page.visible = _tabs.current_tab == 0
	_skills_page.visible = _tabs.current_tab == 1
	_update_hint()
	if not _is_open:
		return
	_refresh()
	if _tabs.current_tab == 1:
		_skill_tree.grab_focus()


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	if not _is_open:
		return
	_refresh_header()
	if skills != null and _tabs.current_tab == 1:
		_refresh_skills()
	else:
		_refresh_attributes()


func _refresh_header() -> void:
	if skills == null:
		return
	var current := skills.get_player_xp_in_level()
	var needed := skills.get_player_xp_for_next()
	_level_label.text = "Level %d" % skills.get_player_level()
	_xp_bar.max_value = maxf(needed, 1.0)
	_xp_bar.value = current
	_xp_label.text = "XP %d / %d" % [current, needed]


func _refresh_attributes() -> void:
	for v in VITALS:
		var cur: float = stats.get(v["id"])
		var mx: float = stats.get_stat(v["max"])
		var parts: Dictionary = _vital_rows[v["id"]]
		var bar: ProgressBar = parts["bar"]
		bar.max_value = maxf(mx, 1.0)
		bar.value = cur
		var label: Label = parts["label"]
		label.text = "%.0f / %.0f" % [cur, mx]

	_tree.clear()
	var root := _tree.create_item()
	_add_section(root, "Vitals & Combat")
	for stat in CORE_STATS:
		_add_stat_row(root, stat)
	_add_section(root, "Attributes")
	for stat in SkillDatabase.ATTRIBUTES:
		_add_stat_row(root, stat)
	var others := _gear_only_stats()
	if not others.is_empty():
		_add_section(root, "Other")
		for stat in others:
			_add_stat_row(root, stat)

	var lines := PackedStringArray()
	for slot_name in ItemData.EquipSlot.keys():
		var slot: int = ItemData.EquipSlot[slot_name]
		if slot == ItemData.EquipSlot.NONE:
			continue
		var item := equipment.get_equipped(slot)
		var item_name := item.display_name if item != null else "-"
		lines.append("%s: %s" % [String(slot_name).capitalize(), item_name])
	_equipped_label.text = "\n".join(lines)

	if inventory != null:
		var w := inventory.get_total_weight()
		var cap := stats.get_stat("carry_capacity")
		_weight_label.text = "Carry Weight: %.1f / %.0f" % [w, cap]
		_weight_label.add_theme_color_override("font_color", Color.INDIAN_RED if w > cap else Color.WHITE)
	else:
		_weight_label.text = ""


func _add_section(root: TreeItem, title: String) -> void:
	var row := _tree.create_item(root)
	row.set_text(0, title)
	row.set_custom_color(0, GOLD)
	for col in 5:
		row.set_selectable(col, false)


func _add_stat_row(root: TreeItem, stat: String) -> void:
	var total := stats.get_stat(stat)
	var base: float = stats.base_stats.get(stat, 0.0)
	var gear := stats.get_flat_from("equip_", stat)
	var row := _tree.create_item(root)
	row.set_text(0, _stat_label(stat))
	row.set_text(1, _fmt(stat, total))
	row.set_text(2, _fmt(stat, base))
	_set_bonus_cell(row, 3, stat, gear)
	# Everything that isn't base or gear flat: skill bonuses, attribute effects, percentages
	_set_bonus_cell(row, 4, stat, total - base - gear)
	for col in [1, 2, 3, 4]:
		row.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)


func _set_bonus_cell(row: TreeItem, col: int, stat: String, bonus: float) -> void:
	if is_zero_approx(bonus):
		row.set_text(col, "-")
		row.set_custom_color(col, Color(1, 1, 1, 0.35))
	elif bonus > 0.0:
		row.set_text(col, "+" + _fmt(stat, bonus))
		row.set_custom_color(col, Color.LIGHT_GREEN)
	else:
		row.set_text(col, _fmt(stat, bonus))
		row.set_custom_color(col, Color.INDIAN_RED)


# Stats that only exist because of equipped gear (not in the lists above)
func _gear_only_stats() -> Array[String]:
	var names: Array[String] = []
	for item in equipment.slots.values():
		for k in item.stat_modifiers.keys():
			var stat := String(k).trim_suffix("_pct")
			if names.has(stat) or CORE_STATS.has(stat) or SkillDatabase.ATTRIBUTES.has(stat):
				continue
			names.append(stat)
	return names


func _stat_label(stat: String) -> String:
	return STAT_LABELS.get(stat, stat.capitalize())


func _fmt(stat: String, v: float) -> String:
	if PERCENT_STATS.has(stat):
		return "%d%%" % roundi(v * 100.0)
	return String.num(snappedf(v, 0.01)).trim_suffix(".0")


# ---------------------------------------------------------------- skills tab

func _refresh_skills() -> void:
	var keep := _selected_skill_id()
	_skill_tree.clear()
	var root := _skill_tree.create_item()
	var first_row: TreeItem = null
	var keep_row: TreeItem = null

	for group in SkillDatabase.GROUPS:
		var header := _skill_tree.create_item(root)
		header.set_text(0, group)
		header.set_custom_color(0, GOLD)
		for col in 4:
			header.set_selectable(col, false)
		for def in SkillDatabase.get_all():
			if def.group != group:
				continue
			var level := skills.get_level(def.id)
			var next_level := skills.get_next_milestone_level(def.id)
			var row := _skill_tree.create_item(root)
			row.set_metadata(0, def.id)
			row.set_text(0, def.display_name)
			row.set_text(1, str(level))
			if level >= SkillDatabase.MAX_LEVEL:
				row.set_text(2, "MAX")
			else:
				row.set_text(2, "%d / %d" % [int(skills.get_xp(def.id)), int(skills.get_xp_to_next(def.id))])
			row.set_text(3, "Lv %d" % next_level if next_level > 0 else "-")
			for col in [1, 2, 3]:
				row.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)
			if first_row == null:
				first_row = row
			if def.id == keep and keep_row == null:
				keep_row = row

	var target: TreeItem = keep_row if keep_row != null else first_row
	if target != null:
		target.select(0)
		_skill_tree.scroll_to_item(target)
	_update_skill_details()


func _selected_skill_id() -> StringName:
	if _skill_tree == null:
		return &""
	var row := _skill_tree.get_selected()
	if row == null:
		return &""
	var meta: Variant = row.get_metadata(0)
	return meta if meta is StringName else &""


func _update_skill_details() -> void:
	if _skill_details == null or skills == null:
		return
	var def := SkillDatabase.get_skill(_selected_skill_id())
	if def == null:
		_skill_details.text = ""
		return

	var level := skills.get_level(def.id)
	var tier := skills.get_tier(def.id)
	var t := "[b][font_size=22]%s[/font_size][/b]\n" % def.display_name
	t += "[color=gray]%s  ·  Level %d / %d[/color]\n\n" % [def.group, level, SkillDatabase.MAX_LEVEL]
	t += def.description + "\n\n"

	if not def.tier_effects.is_empty():
		t += "[b]Current bonus[/b]  [color=gray](%d of %d milestones)[/color]\n" % [tier, SkillDatabase.MAX_TIER]
		t += (def.describe_effects(tier) if tier > 0 else "None yet") + "\n"
		if def.weapon_conditional:
			t += "[color=gray]Applies while you wield this type of weapon.[/color]\n"
		var next_level := skills.get_next_milestone_level(def.id)
		if next_level > 0:
			t += "\n[b]At level %d[/b]\n%s\n" % [next_level, def.describe_effects(tier + 1)]
		t += "\n[color=gray]Every 5 levels: %s[/color]\n" % def.describe_effects(1)

	if not def.attributes.is_empty():
		t += "\n[b]Raises[/b]\n"
		for attr in def.attributes:
			var per_level: float = def.attributes[attr]
			var points := floori((level - SkillDatabase.START_LEVEL) * per_level)
			t += "%s +%d  [color=gray](%s per level)[/color]\n" % [String(attr).capitalize(), points, String.num(per_level).trim_suffix(".0")]

	t += "\n[b]Trains by[/b]\n%s\n" % def.trains_by
	_skill_details.text = t
