class_name NewGameWizard
extends Control
## New Game: five pages, Back / Next at the bottom.
##   1 World      seed, difficulty, survival, afflictions, ironman, fast travel, quest markers,
##                leveling speed, loot, encounters, enemy toughness, day length (GameRules)
##   2 You        name, race (with its traits and power), look
##   3 Class      take the quiz (Daggerfall style) or pick one; see its skills and gear
##   4 Traits     advantages and disadvantages (they change how fast you level), birthsign,
##                and optionally starting as a vampire or werewolf
##   5 Begin      a summary; Begin starts the game (SaveManager.new_game)
## Esc or Cancel goes back to the main menu.

signal cancelled
signal begin(seed_text: String, rules: Dictionary, character: Dictionary)

var saves: SaveManager
var rules := GameRules.DEFAULTS.duplicate()
var character := CharacterSetup.default_data()
var seed_text := ""

var _page := 0
var _body: VBoxContainer
var _title: Label
var _back: Button
var _next: Button
var _quiz_i := -1
var _quiz_answers: Array = []

const PAGES := ["World", "You", "Class", "Traits", "Begin"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.97)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 600)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_title = UITheme.heading("")
	v.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	var row := HBoxContainer.new()
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: cancelled.emit())
	row.add_child(cancel)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(110, 0)
	_back.pressed.connect(func() -> void: _go(_page - 1))
	row.add_child(_back)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(140, 0)
	_next.pressed.connect(func() -> void:
		if _page == PAGES.size() - 1:
			_begin()
		else:
			_go(_page + 1))
	row.add_child(_next)
	_go(0)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _go(p: int) -> void:
	_page = clampi(p, 0, PAGES.size() - 1)
	_title.text = "%d of %d   %s" % [_page + 1, PAGES.size(), PAGES[_page]]
	_back.disabled = _page == 0
	_next.text = "Begin" if _page == PAGES.size() - 1 else "Next"
	for c in _body.get_children():
		c.queue_free()
	match _page:
		0:
			_world_page()
		1:
			_you_page()
		2:
			_class_page()
		3:
			_traits_page()
		4:
			_summary_page()


# ---------------------------------------------------------------- helpers

func _text(t: String, dim: bool = false) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim:
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_body.add_child(l)
	return l


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 8)
	_body.add_child(g)
	return g


func _label(g: GridContainer, t: String, tip: String = "") -> void:
	var l := Label.new()
	l.text = t
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" else Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(280, 0)
	g.add_child(l)


func _check(g: GridContainer, t: String, key: String, tip: String) -> void:
	_label(g, t, tip)
	var c := CheckBox.new()
	c.button_pressed = bool(rules[key])
	c.text = tip
	c.toggled.connect(func(on: bool) -> void: rules[key] = on)
	g.add_child(c)


func _slider(g: GridContainer, t: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	_label(g, t)
	var box := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(rules[key])
	s.custom_minimum_size = Vector2(260, 0)
	var v := Label.new()
	v.text = fmt % s.value
	s.value_changed.connect(func(x: float) -> void:
		rules[key] = x
		v.text = fmt % x)
	box.add_child(s)
	box.add_child(v)
	g.add_child(box)


func _choice(g: GridContainer, t: String, items: Array, selected: int, on_pick: Callable) -> OptionButton:
	_label(g, t)
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = selected
	o.item_selected.connect(on_pick)
	g.add_child(o)
	return o


# ---------------------------------------------------------------- 1 world

func _world_page() -> void:
	_text("How this world plays. These choices stay with this game and its saves.", true)
	var g := _grid()
	_label(g, "World seed")
	var seed_row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.text = seed_text
	edit.placeholder_text = "blank = the default world"
	edit.custom_minimum_size = Vector2(220, 0)
	edit.text_changed.connect(func(t: String) -> void: seed_text = t)
	seed_row.add_child(edit)
	var rnd := Button.new()
	rnd.text = "Random"
	rnd.pressed.connect(func() -> void:
		seed_text = str(randi() % 1000000)
		edit.text = seed_text)
	seed_row.add_child(rnd)
	g.add_child(seed_row)
	_choice(g, "Difficulty", Difficulty.NAMES, int(rules["difficulty"]), func(i: int) -> void: rules["difficulty"] = i)
	_check(g, "Survival mode", "survival", "Hunger, fatigue and cold")
	_check(g, "Afflictions", "afflictions", "Diseases, vampirism and lycanthropy")
	_check(g, "Ironman", "ironman", "One life: death deletes the save")
	_check(g, "Fast travel", "fast_travel", "Click the map twice to travel (carriages always work)")
	_check(g, "Quest markers", "quest_markers", "Quest targets on the map and compass")
	_slider(g, "Leveling speed", "xp_rate", 0.25, 3.0, 0.05, "x%.2f")
	_slider(g, "Loot and gold", "loot_rate", 0.25, 2.0, 0.05, "x%.2f")
	_slider(g, "Random encounters", "encounter_rate", 0.0, 2.0, 0.1, "x%.1f")
	_slider(g, "Enemy toughness", "enemy_toughness", 0.5, 2.5, 0.05, "x%.2f")
	_slider(g, "Length of a day (real minutes)", "day_minutes", 6.0, 96.0, 1.0, "%d min")


# ---------------------------------------------------------------- 2 you

func _you_page() -> void:
	var g := _grid()
	_label(g, "Name")
	var name_edit := LineEdit.new()
	name_edit.text = String(character["name"])
	name_edit.max_length = 24
	name_edit.text_changed.connect(func(t: String) -> void: character["name"] = t if t.strip_edges() != "" else "Traveler")
	g.add_child(name_edit)
	var ids := Races.ids()
	var names: Array = ids.map(func(id: String) -> String: return Races.get_race(id)["name"])
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(600, 0)
	var refresh := func() -> void:
		var r := Races.get_race(String(character["race"]))
		var skills := PackedStringArray()
		for s in r["skills"]:
			skills.append("%s +%d" % [SkillDatabase.get_skill(StringName(s)).display_name, int(r["skills"][s])])
		var traits := PackedStringArray()
		for k in r["stats"]:
			traits.append(_stat_text(k, float(r["stats"][k])))
		info.text = "%s\n\nSkills: %s\nTraits: %s\nPower (Z, once a day): %s" % [r["desc"], ", ".join(skills), ", ".join(traits), r["power_desc"]]
	_choice(g, "Race", names, ids.find(character["race"]), func(i: int) -> void:
		character["race"] = ids[i]
		refresh.call())
	_choice(g, "Body", ["Masculine", "Feminine"], int(character["sex"]), func(i: int) -> void: character["sex"] = i)
	_choice(g, "Skin", ["Light", "Dark"], int(character["skin"]), func(i: int) -> void: character["skin"] = i)
	_choice(g, "Hair", ["Black", "Brown", "Chestnut", "Blond", "Grey", "Red"], int(character["hair"]), func(i: int) -> void: character["hair"] = i)
	_label(g, "Height")
	var h := HSlider.new()
	h.min_value = 0.9
	h.max_value = 1.1
	h.step = 0.01
	h.value = float(character["height"])
	h.custom_minimum_size = Vector2(260, 0)
	h.value_changed.connect(func(x: float) -> void: character["height"] = x)
	g.add_child(h)
	_body.add_child(info)
	refresh.call()


func _stat_text(k: String, v: float) -> String:
	var pct := k.begins_with("resist_") or k.ends_with("_mult") or k.ends_with("_pct") or k in ["spell_absorb", "sneak_attack_bonus", "security_bonus", "spell_power", "bane_undead", "bane_beast"]
	var label := k.replace("resist_", "resist ").replace("_", " ")
	if pct:
		return "%s %+d%%" % [label, roundi(v * 100.0)]
	return "%s %+d" % [label, roundi(v)]


# ---------------------------------------------------------------- 3 class

func _class_page() -> void:
	if _quiz_i >= 0 and _quiz_i < Classes.QUIZ.size():
		_quiz_page()
		return
	var row := HBoxContainer.new()
	_body.add_child(row)
	var quiz := Button.new()
	quiz.text = "Take the quiz"
	quiz.pressed.connect(func() -> void:
		_quiz_i = 0
		_quiz_answers.clear()
		_go(2))
	row.add_child(quiz)
	row.add_child(_spacer())
	var ids := Classes.LIST.keys()
	var names: Array = ids.map(func(id: String) -> String: return Classes.get_class_data(id)["name"])
	var pick := OptionButton.new()
	for n in names:
		pick.add_item(n)
	pick.selected = ids.find(character["class"])
	row.add_child(pick)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(600, 0)
	_body.add_child(info)
	var refresh := func() -> void:
		var c := Classes.get_class_data(String(character["class"]))
		var gear := PackedStringArray()
		for gi in c["gear"]:
			var it := load(String(gi[0])) as ItemData if ResourceLoader.exists(String(gi[0])) else null
			if it != null:
				gear.append("%s%s" % [it.display_name, (" x%d" % int(gi[1])) if int(gi[1]) > 1 else ""])
		var spells := PackedStringArray()
		for s in c["spells"]:
			var sp := SpellCatalog.get_spell(s)
			if sp != null:
				spells.append(sp.display_name)
		info.text = "%s\n\n%s\n\nMajor skills (+10): %s\nMinor skills (+5): %s\nStarts with: %s%s" % [c["name"], c["desc"],
			", ".join(PackedStringArray(c["major"].map(func(s: String) -> String: return SkillDatabase.get_skill(StringName(s)).display_name))),
			", ".join(PackedStringArray(c["minor"].map(func(s: String) -> String: return SkillDatabase.get_skill(StringName(s)).display_name))),
			", ".join(gear), ("\nSpells: " + ", ".join(spells)) if not spells.is_empty() else ""]
	pick.item_selected.connect(func(i: int) -> void:
		character["class"] = ids[i]
		refresh.call())
	refresh.call()


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _quiz_page() -> void:
	var q: Array = Classes.QUIZ[_quiz_i]
	_text("Question %d of %d" % [_quiz_i + 1, Classes.QUIZ.size()], true)
	var ql := _text(String(q[0]))
	ql.add_theme_font_size_override("font_size", 18)
	for i in 3:
		var b := Button.new()
		b.text = String(q[1][i])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var choice := i
		b.pressed.connect(func() -> void:
			_quiz_answers.append(choice)
			_quiz_i += 1
			if _quiz_i >= Classes.QUIZ.size():
				character["class"] = Classes.class_from_quiz(_quiz_answers)
				_quiz_i = -1
			_go(2))
		_body.add_child(b)


# ---------------------------------------------------------------- 4 traits

func _traits_page() -> void:
	var speed := Label.new()
	_body.add_child(speed)
	var update := func() -> void:
		var m := Classes.xp_mult(character["advantages"], character["disadvantages"])
		var cost := 0
		for a in character["advantages"]:
			cost += int(Classes.ADVANTAGES[a]["cost"])
		var gain := 0
		for d in character["disadvantages"]:
			gain += int(Classes.DISADVANTAGES[d]["gain"])
		speed.text = "Advantages %d, disadvantages %d: you level at x%.2f speed%s" % [cost, gain, m, "  (more advantages = slower leveling)" if m < 1.0 else ""]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	_body.add_child(cols)
	for side in ["advantages", "disadvantages"]:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(v)
		v.add_child(UITheme.heading("Advantages" if side == "advantages" else "Disadvantages", 14))
		var table: Dictionary = Classes.ADVANTAGES if side == "advantages" else Classes.DISADVANTAGES
		for id in table:
			var d: Dictionary = table[id]
			var c := CheckBox.new()
			c.text = "%s (%s%d)  %s" % [d["name"], "-" if side == "advantages" else "+", int(d.get("cost", d.get("gain", 0))), d["desc"]]
			c.button_pressed = (character[side] as Array).has(id)
			var key: String = id
			var list_name: String = side
			c.toggled.connect(func(on: bool) -> void:
				var arr: Array = character[list_name]
				if on and not arr.has(key):
					arr.append(key)
				elif not on:
					arr.erase(key)
				update.call())
			v.add_child(c)
	var g := _grid()
	var signs := Classes.SIGNS.keys()
	_choice(g, "Birthsign", signs.map(func(s: String) -> String: return "%s (%s)" % [Classes.SIGNS[s]["name"], Classes.SIGNS[s]["desc"]]),
		signs.find(character["sign"]), func(i: int) -> void: character["sign"] = signs[i])
	if bool(rules["afflictions"]):
		var aff := ["", "vampire", "werewolf"]
		_choice(g, "Begin cursed", ["No", "As a vampire", "As a werewolf"], aff.find(character["affliction"]), func(i: int) -> void: character["affliction"] = aff[i])
	update.call()


# ---------------------------------------------------------------- 5 begin

func _summary_page() -> void:
	var r := Races.get_race(String(character["race"]))
	var c := Classes.get_class_data(String(character["class"]))
	var lines := PackedStringArray()
	lines.append("%s, a %s %s born under %s." % [character["name"], r["name"], c["name"], Classes.SIGNS[character["sign"]]["name"]])
	if not (character["advantages"] as Array).is_empty():
		lines.append("Advantages: " + ", ".join(PackedStringArray((character["advantages"] as Array).map(func(a: String) -> String: return Classes.ADVANTAGES[a]["name"]))))
	if not (character["disadvantages"] as Array).is_empty():
		lines.append("Disadvantages: " + ", ".join(PackedStringArray((character["disadvantages"] as Array).map(func(a: String) -> String: return Classes.DISADVANTAGES[a]["name"]))))
	if character["affliction"] != "":
		lines.append("Cursed: %s." % String(character["affliction"]).capitalize())
	lines.append("")
	var w := PackedStringArray()
	w.append("World: %s" % ("seed " + seed_text if seed_text.strip_edges() != "" else "the default world"))
	w.append("Difficulty: %s" % Difficulty.NAMES[int(rules["difficulty"])])
	for k in ["survival", "afflictions", "ironman", "fast_travel", "quest_markers"]:
		w.append("%s: %s" % [k.capitalize(), "on" if bool(rules[k]) else "off"])
	w.append("Leveling x%.2f, loot x%.2f, encounters x%.1f, enemies x%.2f, a day lasts %d min" % [float(rules["xp_rate"]),
		float(rules["loot_rate"]), float(rules["encounter_rate"]), float(rules["enemy_toughness"]), int(rules["day_minutes"])])
	lines.append("\n".join(w))
	if bool(rules["ironman"]):
		lines.append("\nIronman: if you die, this character and its save are gone for good.")
	_text("\n".join(lines))


func _begin() -> void:
	begin.emit(seed_text, rules.duplicate(), character.duplicate(true))
