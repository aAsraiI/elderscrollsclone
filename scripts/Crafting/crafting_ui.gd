class_name CraftingUI
extends CanvasLayer
## The screen every workstation opens (CraftingStation.interact -> open_station). One window,
## different modes:
##   forge / smelter / tanning_rack / cooking_pot / workbench "Tinker"   recipes (Recipes)
##   grindstone / workbench "Improve"    raise a weapon's or armor piece's quality
##   alchemy_lab                         pick 2-3 ingredients and brew (Alchemy)
##   enchanter "Enchant" / "Disenchant"  (Enchanting)
##   spell_altar                         make your own spells, Morrowind style (costs gold)
## The game is paused while it is open. E / Enter does the main action, Esc closes.

const MODES := {
	"forge": ["Forge"], "smelter": ["Smelt"], "tanning_rack": ["Tan"], "cooking_pot": ["Cook"],
	"workbench": ["Tinker", "Improve Armor"], "grindstone": ["Improve Weapons"], "alchemy_lab": ["Brew"],
	"enchanter": ["Enchant", "Disenchant"], "spell_altar": ["Make a Spell"],
}

var station := ""
var _mode := ""
var _root: Control
var _title: Label
var _tabs: TabBar
var _only_can := CheckBox.new()
var _tree: Tree
var _details: RichTextLabel
var _controls: VBoxContainer
var _action: Button
var _action2: Button
var _is_open := false
var _player: Node
var _inv: Inventory
var _skills: Skills
var _book: Spellbook

# alchemy / enchant picks
var _picked: Array = []
var _ench_item: ItemData
var _ench_effect: StringName = &""
var _ench_gem: ItemData
var _ench_name := LineEdit.new()
# spellmaking
var _sm_effects: Array = []   # [{id, mag, dur}]
var _sm_form := SpellData.Form.TARGET
var _sm_area := 0.0
var _sm_name := LineEdit.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	add_to_group("crafting_ui")
	_player = get_parent()
	_inv = _player.get_node_or_null("Inventory") as Inventory
	_skills = _player.get_node_or_null("Skills") as Skills
	_book = _player.get_node_or_null("Spellbook") as Spellbook
	_build()
	_root.visible = false


func is_open() -> bool:
	return _is_open


func open_station(kind: String) -> void:
	if not MODES.has(kind) or _is_open:
		return
	station = kind
	_tabs.clear_tabs()
	for m in MODES[kind]:
		_tabs.add_tab(m)
	_tabs.visible = MODES[kind].size() > 1
	_tabs.current_tab = 0
	_mode = MODES[kind][0]
	_title.text = Recipes.STATIONS.get(kind, kind).to_upper()
	_picked.clear()
	_ench_item = null
	_ench_effect = &""
	_ench_gem = null
	_sm_effects.clear()
	_is_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_tree.grab_focus()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit:
			return
		_do_action()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- layout

func _build() -> void:
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
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 580)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = UITheme.heading("")
	top.add_child(_title)
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(i: int) -> void:
		_mode = MODES[station][i]
		_refresh())
	top.add_child(_tabs)
	_only_can.text = "Only what I can make"
	_only_can.focus_mode = Control.FOCUS_NONE
	_only_can.toggled.connect(func(_b: bool) -> void: _refresh())
	top.add_child(_only_can)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	v.add_child(split)
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.columns = 2
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_search = false
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 90)
	_tree.item_selected.connect(_on_select)
	_tree.item_activated.connect(func() -> void:
		if not _mode in ["Brew", "Enchant", "Make a Spell"]:
			_do_action())
	split.add_child(_tree)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(side)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_details)
	_controls = VBoxContainer.new()
	side.add_child(_controls)
	var row := HBoxContainer.new()
	side.add_child(row)
	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.pressed.connect(_do_action)
	row.add_child(_action)
	_action2 = Button.new()
	_action2.focus_mode = Control.FOCUS_NONE
	_action2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action2.pressed.connect(_do_action2)
	row.add_child(_action2)
	var close_b := Button.new()
	close_b.text = "Close (Esc)"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	row.add_child(close_b)
	_ench_name.placeholder_text = "Name (optional)"
	_sm_name.placeholder_text = "Spell name"


func _row(parent: TreeItem, text: String, right: String, meta: Variant, color: Color = UITheme.TEXT) -> TreeItem:
	var r := _tree.create_item(parent)
	r.set_text(0, text)
	r.set_text(1, right)
	r.set_metadata(0, meta)
	r.set_custom_color(0, color)
	return r


func _group(root: TreeItem, text: String) -> TreeItem:
	var g := _tree.create_item(root)
	g.set_text(0, text)
	g.set_custom_color(0, UITheme.GOLD)
	g.set_selectable(0, false)
	g.set_selectable(1, false)
	return g


func _sel() -> Variant:
	var r := _tree.get_selected()
	return r.get_metadata(0) if r != null else null


func _clear_controls() -> void:
	for c in _controls.get_children():
		_controls.remove_child(c)
		if c != _ench_name and c != _sm_name:
			c.queue_free()


# ---------------------------------------------------------------- refreshing

func _refresh() -> void:
	_tree.clear()
	_clear_controls()
	_only_can.visible = _mode in ["Forge", "Smelt", "Tan", "Cook", "Tinker"]
	_action2.visible = false
	match _mode:
		"Forge", "Smelt", "Tan", "Cook", "Tinker":
			_list_recipes()
		"Improve Armor", "Improve Weapons":
			_list_improve()
		"Brew":
			_list_alchemy()
		"Enchant":
			_list_enchant()
		"Disenchant":
			_list_disenchant()
		"Make a Spell":
			_list_spellmaking()
	_on_select()


func _station_of_mode() -> String:
	return "workbench" if _mode == "Tinker" else station


func _list_recipes() -> void:
	var root := _tree.create_item()
	var groups := {}
	var first: TreeItem = null
	for r in Recipes.for_station(_station_of_mode()):
		var n := Recipes.can_make(r, _inv)
		var skill_ok := _skills == null or _skills.get_level(StringName(r["skill"])) >= int(r["level"])
		if _only_can.button_pressed and (n <= 0 or not skill_ok):
			continue
		var res := Recipes.item(r["result"])
		if res == null:
			continue
		var gname := _recipe_group(res)
		if not groups.has(gname):
			groups[gname] = _group(root, gname)
		var col := UITheme.TEXT if n > 0 and skill_ok else UITheme.TEXT_DIM
		var label := res.display_name + (" x%d" % int(r["count"]) if int(r["count"]) > 1 else "")
		var row := _row(groups[gname], label, ("can make %d" % n) if n > 0 and skill_ok else ("needs %d" % int(r["level"]) if not skill_ok else ""), r, col)
		if first == null:
			first = row
	if first != null:
		first.select(0)


func _recipe_group(res: ItemData) -> String:
	if station == "forge":
		var t := clampi(res.tier - 1, 0, 6)
		if res.governing_skill == "light_armor":
			return LevelCurve.LIGHT_NAMES[t]
		return LevelCurve.TIER_NAMES[t]
	if _mode == "Tinker":
		return "Jewelry" if res.equip_slot in [ItemData.EquipSlot.RING, ItemData.EquipSlot.AMULET] else "Tools"
	return Recipes.STATIONS.get(station, "")


func _list_improve() -> void:
	var root := _tree.create_item()
	var target := "grindstone" if _mode == "Improve Weapons" else "workbench"
	var first: TreeItem = null
	for s in _inv.stacks:
		var it: ItemData = s.item
		if Recipes.can_improve_at(it, target):
			var r := _row(root, it.display_name, CraftedItems.QUALITY_NAMES[it.quality] if it.quality > 0 else "", it)
			if first == null:
				first = r
	if first != null:
		first.select(0)


func _list_alchemy() -> void:
	var root := _tree.create_item()
	for s in _inv.stacks:
		var it: ItemData = s.item
		if not Alchemy.is_ingredient(it):
			continue
		var picked := _picked.has(it)
		_row(root, ("✔ " if picked else "    ") + it.display_name, "x%d" % s.count, it, UITheme.GOLD if picked else UITheme.TEXT)


func _list_enchant() -> void:
	var root := _tree.create_item()
	var g1 := _group(root, "1. Item")
	for s in _inv.stacks:
		var it: ItemData = s.item
		if Enchanting.can_enchant(it):
			_row(g1, ("✔ " if it == _ench_item else "") + it.display_name, "", {"item": it}, UITheme.GOLD if it == _ench_item else UITheme.TEXT)
	var g2 := _group(root, "2. Enchantment")
	var any := false
	if _book != null:
		for id in _book.enchantments:
			var e := StringName(id)
			if _ench_item == null or Enchanting.fits(e, _ench_item):
				any = true
				_row(g2, ("✔ " if e == _ench_effect else "") + MagicEffects.display_name(e), "weapon" if Enchanting.WEAPON.has(e) else "worn", {"effect": e}, UITheme.GOLD if e == _ench_effect else UITheme.TEXT)
	if not any:
		_row(g2, "None learned yet: disenchant enchanted gear", "", null, UITheme.TEXT_DIM)
	var g3 := _group(root, "3. Filled soul gem")
	for s in _inv.stacks:
		var it: ItemData = s.item
		if SoulGems.filled_size(it) >= 0:
			_row(g3, ("✔ " if it == _ench_gem else "") + it.display_name, "x%d" % s.count, {"gem": it}, UITheme.GOLD if it == _ench_gem else UITheme.TEXT)
	_controls.add_child(_ench_name)


func _list_disenchant() -> void:
	var root := _tree.create_item()
	var first: TreeItem = null
	for s in _inv.stacks:
		var it: ItemData = s.item
		if not it.enchant_effects.is_empty():
			var known := true
			for e in it.enchant_effects:
				known = known and _book != null and _book.knows_enchantment(StringName(e["id"]))
			var r := _row(root, it.display_name, "known" if known else "NEW", it, UITheme.TEXT_DIM if known else UITheme.TEXT)
			if first == null:
				first = r
	if first != null:
		first.select(0)


func _list_spellmaking() -> void:
	var root := _tree.create_item()
	var g := _group(root, "Effects you know (click to add)")
	if _book != null:
		for id in _book.known_effects():
			_row(g, MagicEffects.display_name(id), String(MagicEffects.SCHOOL_NAMES.get(MagicEffects.get_def(id)["school"], "")), {"add": id})
	var g2 := _group(root, "In your spell (click to remove)")
	for i in _sm_effects.size():
		_row(g2, MagicEffects.describe(_sm_effects[i]), "", {"remove": i}, UITheme.GOLD)
	_build_spellmaking_controls()


# ---------------------------------------------------------------- details

func _on_select() -> void:
	var m: Variant = _sel()
	var t := ""
	_action.disabled = true
	match _mode:
		"Forge", "Smelt", "Tan", "Cook", "Tinker":
			_action.text = "Make (E)"
			_action2.visible = true
			_action2.text = "Make 5"
			if m is Dictionary:
				t = _recipe_text(m)
				var ok := Recipes.can_make(m, _inv) > 0 and (_skills == null or _skills.get_level(StringName(m["skill"])) >= int(m["level"]))
				_action.disabled = not ok
				_action2.disabled = not ok
		"Improve Armor", "Improve Weapons":
			_action.text = "Improve (E)"
			if m is ItemData:
				t = _improve_text(m)
				_action.disabled = m.quality >= Recipes.max_quality(_player) or not _has_all(Recipes.improve_cost(m))
		"Brew":
			_action.text = "Brew (E)"
			_action2.visible = true
			_action2.text = "Clear"
			t = _alchemy_text(m as ItemData)
			_action.disabled = _picked.size() < 2
		"Enchant":
			_action.text = "Enchant (E)"
			t = _enchant_text()
			_action.disabled = _ench_item == null or _ench_effect == &"" or _ench_gem == null
		"Disenchant":
			_action.text = "Disenchant (E)"
			if m is ItemData:
				t = "[b]%s[/b]\n\n%s\nDisenchanting destroys it, but you learn its enchantment for good." % [m.display_name, m.get_combat_description()]
				_action.disabled = false
		"Make a Spell":
			_action.text = "Create spell (E)"
			t = _spell_text()
			_action.disabled = _make_spell_problem() != ""
	_details.text = t


func _recipe_text(r: Dictionary) -> String:
	var res := Recipes.item(r["result"])
	var t := "[b][font_size=18]%s[/font_size][/b]%s\n" % [res.display_name, (" x%d" % int(r["count"])) if int(r["count"]) > 1 else ""]
	t += "[color=gray]%s %d needed (you: %d)[/color]\n\n" % [String(r["skill"]).capitalize(), int(r["level"]), _skills.get_level(StringName(r["skill"])) if _skills != null else 0]
	t += "Needs:\n"
	for i in r["inputs"]:
		var it := Recipes.item(i[0])
		var have := _inv.get_count(it) if it != null else 0
		var c := "#9f9" if have >= int(i[1]) else "#f88"
		t += "  [color=%s]%s  %d / %d[/color]\n" % [c, it.display_name if it != null else String(i[0]).get_file(), have, int(i[1])]
	t += "\n" + res.description + "\n" + res.get_combat_description()
	for stat in res.stat_modifiers:
		t += "%s %+.0f\n" % [String(stat).capitalize(), float(res.stat_modifiers[stat])]
	return t


func _has_all(cost: Array) -> bool:
	for c in cost:
		var it := Recipes.item(c[0])
		if it == null or _inv.get_count(it) < int(c[1]):
			return false
	return true


func _improve_text(it: ItemData) -> String:
	var maxq := Recipes.max_quality(_player)
	var t := "[b][font_size=18]%s[/font_size][/b]\n\n" % it.display_name
	t += "Quality: %s\n" % (CraftedItems.QUALITY_NAMES[it.quality] if it.quality > 0 else "Plain")
	if it.quality >= maxq:
		return t + "\n[color=#f88]Your Smithing allows no better (a level every 15 Smithing).[/color]"
	t += "Next: %s (%s)\n\nNeeds:\n" % [CraftedItems.QUALITY_NAMES[it.quality + 1],
		"+10% damage" if it.item_type == ItemData.ItemType.WEAPON else "+8% armor"]
	for c in Recipes.improve_cost(it):
		var m := Recipes.item(c[0])
		t += "  %s  %d / %d\n" % [m.display_name if m != null else "?", _inv.get_count(m) if m != null else 0, int(c[1])]
	return t


func _alchemy_text(hover: ItemData) -> String:
	var t := "[b]Picked (%d of 3):[/b]\n" % _picked.size()
	for it in _picked:
		t += "  %s\n" % (it as ItemData).display_name
	if _picked.size() >= 2:
		t += "\n[b]This mix:[/b]\n"
		var shared := Alchemy.shared_effects(_picked)
		if shared.is_empty():
			t += "  [color=#f88]Nothing in common that you know of. The ingredients may be wasted.[/color]\n"
		for id in shared:
			var known := false
			for it in _picked:
				known = known or (_book != null and _book.known_ingredient_effects(it).has(Alchemy.effects_of(it).find(String(id))))
			var e := Alchemy.make_effect(id, Alchemy.skill_mult(_player))
			t += "  %s\n" % (MagicEffects.describe(e) if known else "an unknown effect")
	if hover != null:
		t += "\n[b]%s[/b]\n" % hover.display_name
		var known_list := _book.known_ingredient_effects(hover) if _book != null else []
		var effs := Alchemy.effects_of(hover)
		for i in effs.size():
			t += "  %s\n" % (MagicEffects.display_name(StringName(effs[i])) if known_list.has(i) else "?")
	t += "\n[color=gray]Click ingredients to pick 2 or 3. Effects two of them share go into the potion. Eat an ingredient to learn its first effect.[/color]"
	return t


func _enchant_text() -> String:
	var t := "[b]Item:[/b] %s\n[b]Enchantment:[/b] %s\n[b]Soul gem:[/b] %s\n\n" % [
		_ench_item.display_name if _ench_item != null else "-", MagicEffects.display_name(_ench_effect) if _ench_effect != &"" else "-",
		_ench_gem.display_name if _ench_gem != null else "-"]
	if _ench_item != null and _ench_effect != &"" and _ench_gem != null:
		var on_w := _ench_item.item_type == ItemData.ItemType.WEAPON
		var e := Enchanting.make_effect(_ench_effect, SoulGems.filled_size(_ench_gem), Enchanting.skill_mult(_player), on_w)
		t += "Result: %s\n%s\n" % [MagicEffects.describe(e), ("Charge: %d" % roundi(SoulGems.CHARGE[SoulGems.filled_size(_ench_gem)])) if on_w else "Always on while worn"]
	t += "\n[color=gray]Weapons take enchantments that strike on a hit; everything worn takes ones that are always on. Learn enchantments by disenchanting.[/color]"
	return t


# ---------------------------------------------------------------- spellmaking

func _build_spellmaking_controls() -> void:
	_controls.add_child(_sm_name)
	var form := OptionButton.new()
	for i in SpellData.FORM_NAMES.size():
		form.add_item(SpellData.FORM_NAMES[i], i)
	form.selected = int(_sm_form)
	form.focus_mode = Control.FOCUS_NONE
	form.item_selected.connect(func(i: int) -> void:
		_sm_form = i as SpellData.Form
		_on_select())
	_controls.add_child(form)
	_controls.add_child(_slider("Burst size (m)", 0.0, 10.0, _sm_area, func(v: float) -> void:
		_sm_area = v
		_on_select()))
	for i in _sm_effects.size():
		var e: Dictionary = _sm_effects[i]
		var d := MagicEffects.get_def(e["id"])
		var box := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = String(d["name"])
		name_l.custom_minimum_size = Vector2(150, 0)
		box.add_child(name_l)
		if d["mag"]:
			box.add_child(_slider("mag", 1.0, minf(float(d["max"]), 100.0), float(e["mag"]), func(v: float) -> void:
				e["mag"] = v
				_on_select()))
		if d["dur"]:
			box.add_child(_slider("s", 0.0 if int(d["kind"]) == MagicEffects.Kind.INSTANT else 1.0, minf(float(d["max_dur"]), 120.0), float(e["dur"]), func(v: float) -> void:
				e["dur"] = v
				_on_select()))
		_controls.add_child(box)


func _slider(label: String, lo: float, hi: float, value: float, cb: Callable) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = "%s %d" % [label, roundi(value)]
	l.custom_minimum_size = Vector2(70, 0)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1.0
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v: float) -> void:
		l.text = "%s %d" % [label, roundi(v)]
		cb.call(v))
	box.add_child(l)
	box.add_child(s)
	return box


func _draft() -> SpellData:
	var s := SpellData.new()
	s.form = _sm_form
	s.area = _sm_area
	for e in _sm_effects:
		s.effects.append({"id": e["id"], "mag": float(e["mag"]), "dur": float(e["dur"])})
	s.display_name = _sm_name.text.strip_edges() if _sm_name.text.strip_edges() != "" else "My Spell"
	return s


func _spell_price(s: SpellData) -> int:
	return roundi(s.get_cost() * 6.0 + 20.0)


func _make_spell_problem() -> String:
	var s := _draft()
	var why := s.validate()
	if why != "":
		return why
	if Currency.get_gold(_inv) < _spell_price(s):
		return "Not enough gold."
	return ""


func _spell_text() -> String:
	var s := _draft()
	var level := _skills.get_level(s.get_school()) if _skills != null else 0
	var t := "[b][font_size=18]%s[/font_size][/b]\n\n" % s.display_name
	if s.effects.is_empty():
		t += "Pick effects from the list. You can use any effect of a spell you know.\n"
	else:
		t += s.describe(level) + "\n\n"
		t += "School: %s\nPrice: %d gold\n" % [MagicEffects.SCHOOL_NAMES.get(s.get_school(), ""), _spell_price(s)]
		var why := _make_spell_problem()
		if why != "":
			t += "\n[color=#f88]%s[/color]\n" % why
	t += "\n[color=gray]Forms: Self, Touch, Target (a bolt), Spray (a stream while held), Rune (a trap on the ground), Nova (a burst around you), Beam (an instant ray).[/color]"
	return t


# ---------------------------------------------------------------- actions

func _do_action() -> void:
	var m: Variant = _sel()
	match _mode:
		"Forge", "Smelt", "Tan", "Cook", "Tinker":
			if m is Dictionary:
				var made := Recipes.make(m, _player)
				if made != null:
					Locks.toast(get_tree(), "Made %s" % made.display_name)
				_refresh_keep(m)
		"Improve Armor", "Improve Weapons":
			if m is ItemData:
				var better := Recipes.improve(_player, m)
				if better != null:
					Locks.toast(get_tree(), "Improved: %s" % better.display_name)
				_refresh()
				_select_meta(better)
		"Brew":
			if _picked.size() >= 2:
				var potion := Alchemy.brew(_player, _picked)
				Locks.toast(get_tree(), ("You brewed: %s" % potion.display_name) if potion != null else "The mix fizzles. Nothing came of it.", potion == null)
				_picked = _picked.filter(func(it: ItemData) -> bool: return _inv.has_item(it))
				_refresh()
			elif m is ItemData:
				_toggle_pick(m)
		"Enchant":
			if _ench_item != null and _ench_effect != &"" and _ench_gem != null:
				var made := Enchanting.enchant(_player, _ench_item, _ench_effect, _ench_gem, _ench_name.text.strip_edges())
				if made != null:
					Locks.toast(get_tree(), "Enchanted: %s" % made.display_name)
				_ench_item = null
				_ench_gem = null
				_ench_name.text = ""
				_refresh()
		"Disenchant":
			if m is ItemData:
				var learned := Enchanting.disenchant(_player, m)
				Locks.toast(get_tree(), ("Learned: " + ", ".join(learned.map(func(id: StringName) -> String: return MagicEffects.display_name(id)))) if not learned.is_empty() else "You already knew that enchantment.")
				_refresh()
		"Make a Spell":
			if _make_spell_problem() == "":
				var s := _draft()
				s.id = _book.new_custom_id()
				s.custom = true
				Currency.spend_gold(_inv, _spell_price(s))
				_book.learn(s)
				Locks.toast(get_tree(), "You made the spell %s" % s.display_name)
				_sm_effects.clear()
				_sm_name.text = ""
				_refresh()


func _do_action2() -> void:
	match _mode:
		"Forge", "Smelt", "Tan", "Cook", "Tinker":
			var m: Variant = _sel()
			if m is Dictionary:
				for i in 5:
					if Recipes.make(m, _player) == null:
						break
				_refresh_keep(m)
		"Brew":
			_picked.clear()
			_refresh()


func _toggle_pick(it: ItemData) -> void:
	if _picked.has(it):
		_picked.erase(it)
	elif _picked.size() < 3:
		_picked.append(it)
	_refresh()
	_select_meta(it)


func _refresh_keep(m: Variant) -> void:
	_refresh()
	_select_meta(m)


func _select_meta(m: Variant) -> void:
	var it := _tree.get_root().get_first_child() if _tree.get_root() != null else null
	while it != null:
		if it.get_metadata(0) == m:
			it.select(0)
			_tree.scroll_to_item(it)
			return
		it = it.get_next_in_tree()


# Single clicks pick things in the alchemy, enchanting and spellmaking lists
func _input(event: InputEvent) -> void:
	if not _is_open or not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _tree.get_global_rect().has_point(event.position):
		return
	_handle_click.call_deferred()


func _handle_click() -> void:
	var m: Variant = _sel()
	match _mode:
		"Brew":
			if m is ItemData:
				_toggle_pick(m)
		"Enchant":
			if m is Dictionary:
				if m.has("item"):
					_ench_item = null if _ench_item == m["item"] else m["item"]
					if _ench_item != null and _ench_effect != &"" and not Enchanting.fits(_ench_effect, _ench_item):
						_ench_effect = &""
				elif m.has("effect"):
					_ench_effect = &"" if _ench_effect == m["effect"] else m["effect"]
				elif m.has("gem"):
					_ench_gem = null if _ench_gem == m["gem"] else m["gem"]
				_refresh()
		"Make a Spell":
			if m is Dictionary:
				if m.has("add") and _sm_effects.size() < SpellData.MAX_EFFECTS:
					var id: StringName = m["add"]
					var d := MagicEffects.get_def(id)
					_sm_effects.append({"id": id, "mag": 10.0 if d["mag"] else 0.0, "dur": 0.0 if int(d["kind"]) == MagicEffects.Kind.INSTANT or not d["dur"] else 30.0})
					if not MagicEffects.allows_others(id):
						_sm_form = SpellData.Form.SELF
					elif MagicEffects.is_harmful(id) and _sm_form == SpellData.Form.SELF:
						_sm_form = SpellData.Form.TARGET
					_refresh()
				elif m.has("remove"):
					_sm_effects.remove_at(int(m["remove"]))
					_refresh()
