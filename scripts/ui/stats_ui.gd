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
var _perks_page: Control
var _build_page: Control
var _perk_tree: Tree
var _perk_details: RichTextLabel
var _perk_button: Button
var _build_box: VBoxContainer
var _points_label: Label
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
		_tabs.current_tab = posmod(_tabs.current_tab + (1 if _is_key(event, KEY_E) else -1), _tabs.tab_count)
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
	_tabs.add_tab("Perks")
	_tabs.add_tab("Level Up")
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.visible = skills != null
	vbox.add_child(_tabs)

	_attr_page = _build_attributes_page()
	vbox.add_child(_attr_page)

	_skills_page = _build_skills_page()
	_skills_page.visible = false
	vbox.add_child(_skills_page)

	_perks_page = _build_perks_page()
	_perks_page.visible = false
	vbox.add_child(_perks_page)

	_build_page = _build_level_page()
	_build_page.visible = false
	vbox.add_child(_build_page)

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


## Perks tab: every perk tree and the feats, what you have and what it needs (Alpha 1.22)
func _build_perks_page() -> Control:
	var page := HBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	_perk_tree = Tree.new()
	_perk_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_perk_tree.size_flags_stretch_ratio = 1.3
	_perk_tree.columns = 3
	_perk_tree.hide_root = true
	_perk_tree.column_titles_visible = true
	_perk_tree.select_mode = Tree.SELECT_ROW
	_perk_tree.allow_search = false
	_perk_tree.set_column_title(0, "Perk")
	_perk_tree.set_column_title(1, "Rank")
	_perk_tree.set_column_title(2, "Needs")
	_perk_tree.set_column_expand(1, false)
	_perk_tree.set_column_expand(2, false)
	_perk_tree.set_column_custom_minimum_width(1, 55)
	_perk_tree.set_column_custom_minimum_width(2, 90)
	_perk_tree.item_selected.connect(_update_perk_details)
	_perk_tree.item_activated.connect(_take_selected_perk)
	page.add_child(_perk_tree)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(side)
	_perk_details = RichTextLabel.new()
	_perk_details.bbcode_enabled = true
	_perk_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_perk_details)
	_perk_button = Button.new()
	_perk_button.text = "Take perk"
	_perk_button.focus_mode = Control.FOCUS_NONE
	_perk_button.pressed.connect(_take_selected_perk)
	side.add_child(_perk_button)
	return page


## Level Up tab: attribute and vital points, your build at a glance, and starting over
func _build_level_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_box = VBoxContainer.new()
	_build_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_build_box)
	return scroll


func _update_hint() -> void:
	var t := "[C / Tab / Esc] Close"
	if skills != null:
		t += "   [Q / E] Switch tab"
		if _tabs.current_tab == 1 and skills.is_debug_enabled():
			t += "   [X] Debug: +%d XP   [Shift+X] Debug: +1 level" % int(skills.debug_xp_amount)
		if _tabs.current_tab == 2:
			t += "   [Enter / double click] Take perk"
	_hint_label.text = t


func _on_tab_changed(_index: int) -> void:
	_attr_page.visible = _tabs.current_tab == 0
	_skills_page.visible = _tabs.current_tab == 1
	_perks_page.visible = _tabs.current_tab == 2
	_build_page.visible = _tabs.current_tab == 3
	_update_hint()
	if not _is_open:
		return
	_refresh()
	if _tabs.current_tab == 1:
		_skill_tree.grab_focus()
	elif _tabs.current_tab == 2:
		_perk_tree.grab_focus()


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	if not _is_open:
		return
	_refresh_header()
	if skills != null and _tabs.current_tab == 1:
		_refresh_skills()
	elif skills != null and _tabs.current_tab == 2:
		_refresh_perks()
	elif skills != null and _tabs.current_tab == 3:
		_refresh_build()
	else:
		_refresh_attributes()


func _refresh_header() -> void:
	if skills == null:
		return
	var current := skills.get_player_xp_in_level()
	var needed := skills.get_player_xp_for_next()
	_level_label.text = "Level %d  %s%s" % [skills.get_player_level(), CharacterBuild.archetype(skills),
		"  (points to spend)" if skills.build != null and skills.build.has_unspent() else ""]
	if _tabs != null and skills.build != null:
		_tabs.set_tab_title(3, "Level Up (!)" if skills.build.has_unspent() else "Level Up")
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
			var next_level := skills.get_next_major_level(def.id)
			var row := _skill_tree.create_item(root)
			row.set_metadata(0, def.id)
			row.set_text(0, def.display_name)
			row.set_text(1, str(level))
			row.set_text(2, "%d / %d" % [int(skills.get_xp(def.id)), int(skills.get_xp_to_next(def.id))])
			row.set_text(3, "Lv %d" % next_level)
			if not skills.condition_met(def):
				row.set_custom_color(0, Color(1, 1, 1, 0.55))
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
	var tiers := SkillDatabase.effective_tiers(level)
	var t := "[b][font_size=22]%s[/font_size][/b]\n" % def.display_name
	t += "[color=gray]%s  ·  Level %d  ·  %s[/color]\n\n" % [def.group, level, SkillDatabase.rank_name(level)]
	t += def.description + "\n\n"
	const WHEN_TEXT := {SkillData.When.WEAPON: "Its bonuses count while you wield this type of weapon.",
		SkillData.When.UNARMED: "Its bonuses count while your hands are empty.",
		SkillData.When.UNARMORED: "Its bonuses count while you wear no armor.",
		SkillData.When.DUAL_WIELD: "Its bonuses count while you hold a weapon in each hand."}
	if WHEN_TEXT.has(def.condition):
		t += "[color=%s]%s[/color]\n\n" % ["light_green" if skills.condition_met(def) else "gray", WHEN_TEXT[def.condition]]

	if not def.tier_effects.is_empty():
		t += "[b]Passive bonus[/b]\n"
		t += (def.describe_effects(tiers) if tiers > 0.0 else "None yet") + "\n"
		t += "[color=gray]Every 5 levels: %s (half as much past level 100)[/color]\n" % def.describe_effects(1)

	# The big upgrades
	t += "\n[b]Milestones[/b]\n"
	for m in def.milestone_levels():
		var ms: Dictionary = def.milestones[m]
		var got: bool = level >= int(m)
		t += "[color=%s]%s %d  %s[/color]: %s  [color=gray]%s[/color]\n" % ["gold" if got else "gray", "✔" if got else "·", int(m), ms["name"],
			SkillData.describe_stats(ms["stats"]), ms["desc"]]
	if not def.mastery.is_empty():
		var n := SkillDatabase.mastery_count(level)
		t += "[color=%s]Mastery[/color]: %s every %d levels past %d  [color=gray](you have %d)[/color]\n" % ["gold" if n > 0 else "gray",
			SkillData.describe_stats(def.mastery), SkillDatabase.MASTERY_STEP, SkillDatabase.MASTERY_START, n]
	t += "[color=gray]Next big upgrade at level %d. There is no level cap.[/color]\n" % skills.get_next_major_level(def.id)

	if not def.attributes.is_empty():
		t += "\n[b]Raises[/b]\n"
		for attr in def.attributes:
			var per_level: float = def.attributes[attr]
			var points := floori((level - SkillDatabase.START_LEVEL) * per_level)
			t += "%s +%d  [color=gray](%s per level)[/color]\n" % [String(attr).capitalize(), points, String.num(per_level).trim_suffix(".0")]

	t += "\n[b]Trains by[/b]\n%s\n" % def.trains_by
	var fav := skills.favored_bonus(def)
	if fav > 0.0:
		t += "[color=light_green]Learns %d%% faster (your class or specialization)[/color]\n" % roundi(fav * 100.0)
	_skill_details.text = t


# ---------------------------------------------------------------- perks tab (Alpha 1.22)

func _selected_perk_id() -> String:
	if _perk_tree == null:
		return ""
	var row := _perk_tree.get_selected()
	if row == null:
		return ""
	var meta: Variant = row.get_metadata(0)
	return String(meta) if meta is String else ""


func _refresh_perks() -> void:
	var b := skills.build
	if b == null:
		return
	var keep := _selected_perk_id()
	_perk_tree.clear()
	var root := _perk_tree.create_item()
	var first_row: TreeItem = null
	var keep_row: TreeItem = null
	var fp := b.feat_points()
	var sections: Array = [["Feats  (%d feat point%s)" % [fp, "" if fp == 1 else "s"], PerkDatabase.feats()]]
	for tree_name in PerkDatabase.TREES:
		sections.append([tree_name, PerkDatabase.perks_in(tree_name)])
	for s in sections:
		var header := _perk_tree.create_item(root)
		header.set_text(0, String(s[0]))
		header.set_custom_color(0, GOLD)
		for col in 3:
			header.set_selectable(col, false)
		for p in s[1]:
			var row := _perk_tree.create_item(header)
			var id := String(p["id"])
			var rank := b.rank_of(id)
			var max_ranks := int(p["ranks"])
			row.set_metadata(0, id)
			row.set_text(0, String(p["name"]))
			row.set_text(1, ("%d" % rank) if max_ranks == PerkDatabase.UNLIMITED else ("%d/%d" % [rank, max_ranks]))
			var why := b.why_not(id)
			var done := max_ranks != PerkDatabase.UNLIMITED and rank >= max_ranks
			row.set_text(2, "taken" if done else ("Lv %d" % PerkDatabase.level_for_rank(p, rank + 1)))
			if done:
				row.set_custom_color(0, GOLD)
			elif why == "":
				row.set_custom_color(0, Color.LIGHT_GREEN)
			elif rank <= 0:
				row.set_custom_color(0, Color(1, 1, 1, 0.5))
			row.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
			row.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
			if first_row == null:
				first_row = row
			if id == keep:
				keep_row = row
	var target: TreeItem = keep_row if keep_row != null else first_row
	if target != null:
		target.select(0)
		_perk_tree.scroll_to_item(target)
	_update_perk_details()


func _update_perk_details() -> void:
	if _perk_details == null or skills == null or skills.build == null:
		return
	var b := skills.build
	var p := PerkDatabase.get_perk(_selected_perk_id())
	var head := "[color=gray]Perk points %d  ·  Feat points %d[/color]\n\n" % [b.perk_points(), b.feat_points()]
	if p.is_empty():
		_perk_details.text = head + "Pick a perk on the left."
		_perk_button.disabled = true
		return
	var id := String(p["id"])
	var rank := b.rank_of(id)
	var max_ranks := int(p["ranks"])
	var t := head + "[b][font_size=20]%s[/font_size][/b]\n" % p["name"]
	var kind_text := "Feat" if bool(p["feat"]) else String(p["tree"]) + " perk"
	var rank_text := ("rank %d (no limit)" % rank) if max_ranks == PerkDatabase.UNLIMITED else ("rank %d of %d" % [rank, max_ranks])
	t += "[color=gray]%s  ·  %s[/color]\n\n" % [kind_text, rank_text]
	t += String(p["desc"]) + "\n\n"
	t += "[b]Each rank[/b]\n%s\n" % PerkDatabase.describe(p, 1)
	if rank > 0:
		t += "\n[b]You have[/b]\n%s\n" % PerkDatabase.describe(p, rank)
	var needs := PackedStringArray()
	needs.append("player level %d" % PerkDatabase.level_for_rank(p, rank + 1))
	if String(p["skill"]) != "":
		var def := SkillDatabase.get_skill(StringName(p["skill"]))
		needs.append("%s %d" % [def.display_name if def != null else String(p["skill"]), int(p["skill_level"])])
	for r in p["requires"]:
		needs.append(String(PerkDatabase.get_perk(String(r)).get("name", r)))
	t += "\n[b]Needs[/b]\n%s\n" % ", ".join(needs)
	var why := b.why_not(id)
	if why != "":
		t += "\n[color=indian_red]%s[/color]\n" % why
	_perk_details.text = t
	_perk_button.disabled = why != ""
	_perk_button.text = "Take feat (1 feat point)" if bool(p["feat"]) else "Take perk (1 perk point)"


func _take_selected_perk() -> void:
	if skills == null or skills.build == null:
		return
	if skills.build.take(_selected_perk_id()):
		_refresh()


# ---------------------------------------------------------------- level up tab (Alpha 1.22)

func _refresh_build() -> void:
	var b := skills.build
	if b == null or _build_box == null:
		return
	for c in _build_box.get_children():
		c.queue_free()
	var top := CharacterBuild.top_skills(skills, 3)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	var t := "[b][font_size=20]%s[/font_size][/b]   [color=gray]level %d[/color]\n" % [CharacterBuild.archetype(skills), skills.get_player_level()]
	var best := PackedStringArray()
	for e in top:
		best.append("%s %d (%s)" % [(e[0] as SkillData).display_name, int(e[1]), SkillDatabase.rank_name(int(e[1]))])
	t += "Best skills: %s\n" % ", ".join(best)
	if CharacterBuild.title(skills) != "":
		t += "People call you [b]%s[/b].\n" % CharacterBuild.title(skills)  # 1.27
	if skills.build != null and not skills.build.synergies().is_empty():
		var syn := PackedStringArray()
		for s in skills.build.synergies():
			syn.append("%s (%s)" % [s[1], s[5]])
		t += "Synergies: %s\n" % "; ".join(syn)
	if not PerkAbilities.owned(get_parent()).is_empty():
		var mv := PackedStringArray()
		for id in PerkAbilities.owned(get_parent()):
			mv.append(String(PerkAbilities.LIST[id][0]))
		t += "Moves (G, Shift+G for the next): %s\n" % ", ".join(mv)
	var player := get_parent()
	if player != null and player.has_meta("character"):
		var data: Dictionary = player.get_meta("character")
		var spec := String(data.get("specialization", ""))
		var bg := String(data.get("background", ""))
		var line := CharacterSetup.title_of(data)
		if spec != "" and Classes.SPECIALIZATIONS.has(spec):
			line += "  ·  Specialization: " + String(Classes.SPECIALIZATIONS[spec]["name"])
		if bg != "" and Classes.BACKGROUNDS.has(bg):
			line += "  ·  " + String(Classes.BACKGROUNDS[bg]["name"])
		t += "[color=gray]%s[/color]\n" % line
	t += "\nEvery level gives a perk point, an attribute point (+%d) and a vital point (+%d). Levels 10, 25, 50, 75, 100 and every 25 after give a feat point. There is no level cap." % [int(CharacterBuild.ATTR_PER_POINT), int(CharacterBuild.VITAL_PER_POINT)]
	info.text = t
	_build_box.add_child(info)

	_points_label = Label.new()
	_points_label.add_theme_color_override("font_color", GOLD)
	_points_label.text = "Perk points %d   Feat points %d   Attribute points %d   Vital points %d" % [b.perk_points(), b.feat_points(), b.attribute_points(), b.vital_points()]
	_build_box.add_child(_points_label)

	_build_box.add_child(UITheme.heading("Attributes", 14))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	_build_box.add_child(grid)
	for attr in SkillDatabase.ATTRIBUTES:
		var l := Label.new()
		l.text = String(attr).capitalize()
		l.custom_minimum_size = Vector2(110, 0)
		grid.add_child(l)
		var v := Label.new()
		v.text = "%d" % roundi(stats.get_stat(attr))
		v.custom_minimum_size = Vector2(50, 0)
		grid.add_child(v)
		var effect := Label.new()
		effect.text = _attr_effect_text(attr)
		effect.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(effect)
		var plus := Button.new()
		plus.text = "+%d" % int(CharacterBuild.ATTR_PER_POINT)
		plus.focus_mode = Control.FOCUS_NONE
		plus.disabled = b.attribute_points() <= 0
		var a: String = attr
		plus.pressed.connect(func() -> void:
			if skills.build.spend_attribute(a):
				_refresh())
		grid.add_child(plus)

	_build_box.add_child(UITheme.heading("Vitals", 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_build_box.add_child(row)
	for vit in CharacterBuild.VITALS:
		var btn := Button.new()
		btn.text = "+%d %s  (%d)" % [int(CharacterBuild.VITAL_PER_POINT), String(vit).capitalize(), roundi(stats.get_stat(CharacterBuild.VITALS[vit]))]
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = b.vital_points() <= 0
		var key: String = vit
		btn.pressed.connect(func() -> void:
			if skills.build.spend_vital(key):
				_refresh())
		row.add_child(btn)

	_build_box.add_child(HSeparator.new())
	var respec := Button.new()
	respec.text = "Start over: undo every perk, feat and point (%d gold)" % b.respec_cost()
	respec.focus_mode = Control.FOCUS_NONE
	respec.disabled = b.owned.is_empty() and b.attr_spent.is_empty() and b.vitals.is_empty()
	var msg := Label.new()
	respec.pressed.connect(func() -> void:
		var err := skills.build.respec(inventory)
		if err != "":
			msg.text = err
			msg.add_theme_color_override("font_color", Color.INDIAN_RED)
		else:
			_refresh())
	_build_box.add_child(respec)
	_build_box.add_child(msg)


func _attr_effect_text(attr: String) -> String:
	var parts := PackedStringArray()
	var fx: Dictionary = Stats.ATTRIBUTE_EFFECTS.get(attr, {})
	for k in fx:
		parts.append(SkillData.format_effect(k, fx[k], fx[k], SkillData.stat_label(k)))
	return ("each point: " + ", ".join(parts)) if not parts.is_empty() else ""
