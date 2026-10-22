class_name MagicEffects
extends RefCounted
## Every magic effect in the game, in one table (like SkillDatabase is for skills). Spells, potions,
## poisons, enchantments and food are all lists of these:  {"id": "fire_damage", "mag": 20, "dur": 0}
##
## Kinds of effect:
##   INSTANT  damage / restore / absorb. dur 0 = all at once, dur > 0 = `mag` points every second
##   BUFF     changes a stat (Stats modifier) for `dur` seconds: fortify, resist, weakness, shield
##   CONTROL  works on a creature's mind or body for `dur` seconds: paralyze, calm, fear, frenzy
##   SPECIAL  everything else (summons, bound weapons, light, mark and recall...), see SpellCaster
##
## Balance lives here: "cost" is the base magicka cost (see SpellData.get_cost for the formula).

enum Kind { INSTANT, BUFF, CONTROL, SPECIAL }

const SCHOOLS: Array[StringName] = [&"destruction", &"restoration", &"alteration", &"conjuration", &"illusion", &"mysticism"]
const SCHOOL_NAMES := {
	&"destruction": "Destruction", &"restoration": "Restoration", &"alteration": "Alteration",
	&"conjuration": "Conjuration", &"illusion": "Illusion", &"mysticism": "Mysticism",
}
## Glow of the casting hand and the spell's projectile
const SCHOOL_COLORS := {
	&"destruction": Color(1.0, 0.45, 0.15), &"restoration": Color(1.0, 0.9, 0.5), &"alteration": Color(0.55, 0.85, 1.0),
	&"conjuration": Color(0.7, 0.4, 1.0), &"illusion": Color(1.0, 0.45, 0.85), &"mysticism": Color(0.4, 1.0, 0.8),
}
const ELEMENT_COLORS := {
	&"fire": Color(1.0, 0.42, 0.12), &"frost": Color(0.55, 0.85, 1.0), &"shock": Color(0.75, 0.7, 1.0),
	&"poison": Color(0.45, 0.85, 0.25), &"magic": Color(0.8, 0.35, 1.0),
}
## Resistances never go above this (a fire spirit is immune because it is set to 1.0 directly)
const MAX_RESIST := 0.85
const MAX_REFLECT := 0.5

static var _defs: Dictionary = {}
static var _order: Array[StringName] = []


## The definition of one effect (a Dictionary, see _add), or an empty one
static func get_def(id: StringName) -> Dictionary:
	_ensure()
	return _defs.get(id, {})


static func has(id: StringName) -> bool:
	_ensure()
	return _defs.has(id)


static func all_ids() -> Array[StringName]:
	_ensure()
	return _order


static func ids_of_school(school: StringName) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for id in _order:
		if _defs[id]["school"] == school:
			out.append(id)
	return out


static func display_name(id: StringName) -> String:
	return String(get_def(id).get("name", String(id).capitalize()))


static func is_harmful(id: StringName) -> bool:
	return bool(get_def(id).get("harm", false))


static func color_of(id: StringName) -> Color:
	var d := get_def(id)
	if d.get("element", &"") != &"":
		return ELEMENT_COLORS.get(d["element"], Color.WHITE)
	return SCHOOL_COLORS.get(d.get("school", &"destruction"), Color.WHITE)


## "Fire Damage 20 pts", "Fire Damage 5 pts for 4 s", "Resist Fire 30% for 60 s", "Paralyze for 5 s"
static func describe(e: Dictionary, with_area: bool = false) -> String:
	var id := StringName(e.get("id", ""))
	var d := get_def(id)
	if d.is_empty():
		return String(id)
	var mag := float(e.get("mag", 0.0))
	var dur := float(e.get("dur", 0.0))
	var t: String = d["name"]
	if d["mag"]:
		var unit: String = d.get("unit", " pts")
		var shown := roundi(mag)
		t += " %d%s" % [shown, unit]
		if d["kind"] == Kind.INSTANT and dur > 0.0:
			t += " per second"
	if dur > 0.0 and (d["kind"] != Kind.INSTANT or d["mag"]):
		t += " for %s" % _time_text(dur)
	var area := float(e.get("area", 0.0))
	if with_area and area > 0.0:
		t += " in %d m" % roundi(area)
	return t


static func _time_text(seconds: float) -> String:
	if seconds >= 120.0:
		return "%d min" % roundi(seconds / 60.0)
	return "%d s" % roundi(seconds)


## Can this effect be put on yourself / on something else?
static func allows_self(id: StringName) -> bool:
	var d := get_def(id)
	return not d.get("no_self", false) and not d.get("harm", false)


static func allows_others(id: StringName) -> bool:
	return not get_def(id).get("self_only", false)


# ---------------------------------------------------------------- the table

static func _ensure() -> void:
	if not _defs.is_empty():
		return
	var D := &"destruction"
	var R := &"restoration"
	var A := &"alteration"
	var C := &"conjuration"
	var I := &"illusion"
	var M := &"mysticism"

	# ---- Destruction
	_add(&"fire_damage", "Fire Damage", D, 1.0, Kind.INSTANT, {"harm": true, "element": &"fire", "alch": true, "ench_w": true,
		"desc": "Burns the target."})
	_add(&"frost_damage", "Frost Damage", D, 1.0, Kind.INSTANT, {"harm": true, "element": &"frost", "alch": true, "ench_w": true,
		"desc": "Freezes the target. Also drains stamina and slows it for a moment."})
	_add(&"shock_damage", "Shock Damage", D, 1.0, Kind.INSTANT, {"harm": true, "element": &"shock", "alch": true, "ench_w": true,
		"desc": "Lightning. Also drains magicka."})
	_add(&"poison_damage", "Poison", D, 0.9, Kind.INSTANT, {"harm": true, "element": &"poison", "alch": true, "ench_w": true,
		"desc": "Poisons the target. Cure Poison ends it."})
	_add(&"damage_health", "Wither", D, 1.2, Kind.INSTANT, {"harm": true, "element": &"magic", "alch": true,
		"desc": "Raw magical harm. Only Resist Magic protects from it."})
	_add(&"damage_stamina", "Damage Stamina", D, 0.5, Kind.INSTANT, {"harm": true, "alch": true, "ench_w": true, "vital": "stamina"})
	_add(&"damage_magicka", "Damage Magicka", D, 0.5, Kind.INSTANT, {"harm": true, "alch": true, "ench_w": true, "vital": "magicka"})
	for el in ["fire", "frost", "shock", "poison"]:
		_add(StringName("weakness_" + el), "Weakness to %s" % el.capitalize(), D, 0.06, Kind.BUFF,
			{"harm": true, "stat": "resist_" + el, "per": -0.01, "unit": "%", "alch": true})
	_add(&"weakness_magic", "Weakness to Magic", D, 0.09, Kind.BUFF, {"harm": true, "stat": "resist_magic", "per": -0.01, "unit": "%", "alch": true})
	_add(&"sunder", "Sunder Armor", D, 0.08, Kind.BUFF, {"harm": true, "stat": "armor", "per": -1.0, "alch": true,
		"desc": "Lowers the target's armor."})

	# ---- Restoration
	_add(&"restore_health", "Restore Health", R, 0.8, Kind.INSTANT, {"vital": "health", "alch": true})
	_add(&"restore_stamina", "Restore Stamina", R, 0.4, Kind.INSTANT, {"vital": "stamina", "alch": true})
	_add(&"restore_magicka", "Restore Magicka", R, 0.6, Kind.INSTANT, {"vital": "magicka", "alch": true})
	_add(&"fortify_health", "Fortify Health", R, 0.05, Kind.BUFF, {"stat": "max_health", "per": 1.0, "alch": true, "ench_a": true})
	_add(&"fortify_magicka", "Fortify Magicka", R, 0.05, Kind.BUFF, {"stat": "max_magicka", "per": 1.0, "alch": true, "ench_a": true})
	_add(&"fortify_stamina", "Fortify Stamina", R, 0.04, Kind.BUFF, {"stat": "max_stamina", "per": 1.0, "alch": true, "ench_a": true})
	for attr in ["strength", "agility", "endurance", "wisdom", "charisma"]:
		_add(StringName("fortify_" + attr), "Fortify %s" % attr.capitalize(), R, 0.08, Kind.BUFF,
			{"stat": attr, "per": 1.0, "alch": true, "ench_a": true})
	_add(&"fortify_attack", "Fortify Attack", R, 0.15, Kind.BUFF, {"stat": "damage_pct", "per": 0.01, "unit": "%", "alch": true, "ench_a": true,
		"desc": "More damage with weapons and fists."})
	_add(&"regenerate_health", "Regenerate Health", R, 0.12, Kind.BUFF, {"stat": "health_regen", "per": 0.1, "unit": "", "alch": true, "ench_a": true,
		"desc": "Health comes back on its own (10 = 1 point a second)."})
	_add(&"regenerate_magicka", "Regenerate Magicka", R, 0.1, Kind.BUFF, {"stat": "magicka_regen_pct", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"regenerate_stamina", "Regenerate Stamina", R, 0.08, Kind.BUFF, {"stat": "stamina_regen_mult", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	for el in ["fire", "frost", "shock", "poison"]:
		_add(StringName("resist_" + el), "Resist %s" % el.capitalize(), R, 0.05, Kind.BUFF,
			{"stat": "resist_" + el, "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"resist_magic", "Resist Magic", R, 0.09, Kind.BUFF, {"stat": "resist_magic", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"cure_poison", "Cure Poison", R, 12.0, Kind.SPECIAL, {"mag": false, "dur": false, "alch": true, "desc": "Ends every poison."})
	_add(&"cure_disease", "Cure Disease", R, 14.0, Kind.SPECIAL, {"mag": false, "dur": false, "alch": true, "desc": "Ends every disease (not a curse that has already taken hold)."})
	_add(&"resist_disease", "Resist Disease", R, 0.05, Kind.BUFF, {"stat": "resist_disease", "per": 0.01, "unit": "%", "ench_a": true})
	_add(&"well_rested", "Well Rested", R, 0.2, Kind.BUFF, {"stat": "skill_xp_pct", "per": 0.01, "unit": "%", "self_only": true, "desc": "Skills improve faster."})
	_add(&"fortify_block", "Fortify Block", R, 0.1, Kind.BUFF, {"stat": "block_strength", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"fortify_sneak", "Fortify Sneak", R, 0.1, Kind.BUFF, {"stat": "sneak_attack_bonus", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"fortify_speech", "Fortify Barter", R, 0.1, Kind.BUFF, {"stat": "buy_price_mult", "per": -0.01, "unit": "%", "alch": true, "ench_a": true,
		"desc": "Better prices when buying."})
	_add(&"fortify_lockpicking", "Fortify Lockpicking", R, 0.1, Kind.BUFF, {"stat": "security_bonus", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"fortify_smithing", "Fortify Smithing", R, 0.1, Kind.BUFF, {"stat": "smithing_potency", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"fortify_alchemy", "Fortify Alchemy", R, 0.1, Kind.BUFF, {"stat": "alchemy_potency", "per": 0.01, "unit": "%", "ench_a": true})
	_add(&"fortify_enchanting", "Fortify Enchanting", R, 0.1, Kind.BUFF, {"stat": "enchanting_potency", "per": 0.01, "unit": "%", "alch": true})
	_add(&"fortify_magic", "Fortify Spell Power", R, 0.15, Kind.BUFF, {"stat": "spell_power", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})

	# ---- Alteration
	_add(&"shield", "Shield", A, 0.1, Kind.BUFF, {"stat": "armor", "per": 1.0, "alch": true, "ench_a": true, "desc": "Extra armor."})
	_add(&"feather", "Feather", A, 0.03, Kind.BUFF, {"stat": "carry_capacity", "per": 1.0, "alch": true, "ench_a": true, "desc": "Carry more."})
	_add(&"haste", "Haste", A, 0.12, Kind.BUFF, {"stat": "move_speed_mult", "per": 0.01, "unit": "%", "alch": true, "ench_a": true})
	_add(&"slow", "Slow", A, 0.1, Kind.BUFF, {"harm": true, "stat": "move_speed_mult", "per": -0.01, "unit": "%", "alch": true, "max": 80.0})
	_add(&"jump", "Jump", A, 0.06, Kind.BUFF, {"stat": "jump_mult", "per": 0.01, "unit": "%", "alch": true, "ench_a": true, "self_only": true})
	_add(&"slowfall", "Slowfall", A, 2.5, Kind.SPECIAL, {"mag": false, "self_only": true, "alch": true, "desc": "Fall gently and take no falling damage."})
	_add(&"open_lock", "Open", A, 0.6, Kind.SPECIAL, {"dur": false, "no_self": true, "unit": "", "max": 100.0,
		"desc": "Opens a lock up to this level."})
	_add(&"paralyze", "Paralyze", A, 12.0, Kind.CONTROL, {"harm": true, "mag": false, "alch": true, "ench_w": true, "max_dur": 15.0})
	_add(&"light", "Light", A, 0.25, Kind.SPECIAL, {"self_only": true, "unit": " m", "max": 30.0, "desc": "A glowing light follows you."})

	# ---- Conjuration
	var summons := [
		[&"summon_wolf", "Summon Wolf", 3.5, "Calls a wolf to fight for you."],
		[&"summon_skeleton", "Summon Skeleton", 4.6, "Raises a skeleton warrior to fight for you."],
		[&"summon_ember", "Summon Ember Spirit", 5.6, "Calls a spirit of fire. It throws flames."],
		[&"summon_frost", "Summon Frost Wraith", 6.6, "Calls a wraith of ice. It throws frost."],
		[&"summon_bear", "Summon Frost Bear", 7.6, "Calls a great bear."],
		[&"summon_troll", "Summon Cave Troll", 9.0, "Calls a cave troll."],
	]
	for s in summons:
		_add(s[0], s[1], C, s[2], Kind.SPECIAL, {"mag": false, "self_only": true, "desc": s[3], "max_dur": 300.0})
	var bounds := [
		[&"bound_dagger", "Bound Dagger", 2.2], [&"bound_sword", "Bound Sword", 3.0],
		[&"bound_waraxe", "Bound War Axe", 3.0], [&"bound_greatsword", "Bound Greatsword", 4.0],
	]
	for b in bounds:
		_add(b[0], b[1], C, b[2], Kind.SPECIAL, {"mag": false, "self_only": true, "max_dur": 300.0,
			"desc": "A weapon of pure magic appears in your hand. It weighs nothing."})
	_add(&"reanimate", "Reanimate Corpse", C, 0.35, Kind.SPECIAL, {"no_self": true, "unit": "", "max": 100.0,
		"desc": "A corpse up to this level gets up and fights for you, then crumbles."})

	# ---- Illusion
	_add(&"calm", "Calm", I, 0.3, Kind.CONTROL, {"harm": true, "unit": "", "max": 100.0, "desc": "A foe up to this level stops fighting."})
	_add(&"fear", "Fear", I, 0.3, Kind.CONTROL, {"harm": true, "unit": "", "max": 100.0, "alch": true, "ench_w": true,
		"desc": "A foe up to this level runs away."})
	_add(&"frenzy", "Frenzy", I, 0.35, Kind.CONTROL, {"harm": true, "unit": "", "max": 100.0, "alch": true,
		"desc": "A creature up to this level attacks anything near it."})
	_add(&"charm", "Charm", I, 0.2, Kind.CONTROL, {"no_self": true, "unit": "", "max": 100.0, "desc": "A person likes you more while it lasts."})
	_add(&"invisibility", "Invisibility", I, 5.0, Kind.SPECIAL, {"mag": false, "self_only": true, "alch": true,
		"desc": "Nobody can see you. Attacking or casting ends it."})
	_add(&"muffle", "Muffle", I, 2.0, Kind.SPECIAL, {"mag": false, "self_only": true, "alch": true, "ench_a": true,
		"desc": "Your steps make no sound."})
	_add(&"night_eye", "Night Eye", I, 1.0, Kind.SPECIAL, {"mag": false, "self_only": true, "alch": true, "ench_a": true,
		"desc": "See in the dark."})

	# ---- Mysticism
	_add(&"soul_trap", "Soul Trap", M, 2.0, Kind.CONTROL, {"harm": true, "mag": false, "ench_w": true,
		"desc": "If the target dies while this lasts, its soul fills an empty soul gem you carry."})
	_add(&"detect_life", "Detect Life", M, 0.06, Kind.SPECIAL, {"self_only": true, "unit": " m", "max": 150.0, "alch": true,
		"desc": "Shows living creatures through walls."})
	_add(&"telekinesis", "Telekinesis", M, 2.2, Kind.SPECIAL, {"mag": false, "self_only": true,
		"desc": "Reach and take things from far away."})
	_add(&"dispel", "Dispel", M, 0.4, Kind.SPECIAL, {"dur": false, "unit": "", "max": 100.0, "desc": "Ends spell effects up to this strength."})
	_add(&"absorb_health", "Absorb Health", M, 1.6, Kind.INSTANT, {"harm": true, "element": &"magic", "ench_w": true, "absorb": "health"})
	_add(&"absorb_stamina", "Absorb Stamina", M, 0.8, Kind.INSTANT, {"harm": true, "ench_w": true, "absorb": "stamina", "vital": "stamina"})
	_add(&"absorb_magicka", "Absorb Magicka", M, 1.0, Kind.INSTANT, {"harm": true, "ench_w": true, "absorb": "magicka", "vital": "magicka"})
	_add(&"spell_absorption", "Spell Absorption", M, 0.12, Kind.BUFF, {"stat": "spell_absorb", "per": 0.01, "unit": "%", "ench_a": true, "self_only": true})
	_add(&"reflect", "Reflect", M, 0.14, Kind.BUFF, {"stat": "reflect", "per": 0.01, "unit": "%", "ench_a": true, "self_only": true})
	_add(&"mark", "Mark", M, 15.0, Kind.SPECIAL, {"mag": false, "dur": false, "self_only": true,
		"desc": "Remembers this place (outdoors). Recall brings you back."})
	_add(&"recall", "Recall", M, 20.0, Kind.SPECIAL, {"mag": false, "dur": false, "self_only": true,
		"desc": "Takes you back to where you cast Mark."})


static func _add(id: StringName, name: String, school: StringName, cost: float, kind: int, opts: Dictionary = {}) -> void:
	var d := {
		"id": id, "name": name, "school": school, "cost": cost, "kind": kind,
		"mag": opts.get("mag", true), "dur": opts.get("dur", true),
		"harm": opts.get("harm", false), "element": opts.get("element", &""),
		"stat": opts.get("stat", ""), "per": opts.get("per", 1.0), "unit": opts.get("unit", " pts"),
		"vital": opts.get("vital", ""), "absorb": opts.get("absorb", ""),
		"self_only": opts.get("self_only", false), "no_self": opts.get("no_self", false),
		"alch": opts.get("alch", false), "ench_w": opts.get("ench_w", false), "ench_a": opts.get("ench_a", false),
		"max": opts.get("max", 200.0), "max_dur": opts.get("max_dur", 600.0),
		"desc": opts.get("desc", ""),
	}
	if d["kind"] == Kind.INSTANT and d["vital"] == "" and d["element"] != &"" :
		d["vital"] = "health"
	_defs[id] = d
	_order.append(id)
