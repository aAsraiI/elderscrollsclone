class_name SpellData
extends RefCounted
## One spell: a name, how it is delivered (its form) and a list of magic effects, Morrowind style.
## Premade spells come from SpellCatalog; the player makes their own at an Altar of Spellmaking.
## Saved as a plain Dictionary (to_dict / from_dict).
##
## Forms (how the spell reaches its target):
##   SELF    on yourself                 TOUCH  whatever is in arm's reach
##   TARGET  a bolt that flies           SPRAY  a stream from your hand while you hold the button
##   RUNE    a trap on the ground        NOVA   a burst around you
##   BEAM    an instant ray

enum Form { SELF, TOUCH, TARGET, SPRAY, RUNE, NOVA, BEAM }

const FORM_NAMES := ["Self", "Touch", "Target", "Spray", "Rune", "Nova", "Beam"]
const FORM_HINTS := [
	"Cast on yourself.",
	"Touch what is right in front of you.",
	"A bolt that flies where you aim.",
	"Hold the button: a stream from your hand. Costs magicka every second.",
	"Place a glowing trap on the ground. It bursts when a foe steps on it.",
	"A burst all around you.",
	"An instant ray that hits the first thing in its path.",
]
## Magicka cost multiplier for each form (spray is per second, see get_cost)
const FORM_COST := [1.0, 1.0, 1.25, 0.6, 1.35, 1.6, 1.3]
## How far each form reaches (m)
const TOUCH_RANGE := 3.0
const SPRAY_RANGE := 6.5
const BEAM_RANGE := 40.0
const RUNE_RANGE := 14.0
const NOVA_RADIUS := 5.0
const MAX_EFFECTS := 6

var id := ""
var display_name := "Spell"
var form: Form = Form.TARGET
## Each: {"id": StringName, "mag": float, "dur": float}
var effects: Array[Dictionary] = []
## Radius of the burst where it lands (target, rune, touch) in meters. Nova uses NOVA_RADIUS at least.
var area := 0.0
## Made at an altar (can be deleted; sold back for nothing)
var custom := false


static func make(p_id: String, p_name: String, p_form: Form, p_effects: Array, p_area: float = 0.0) -> SpellData:
	var s := SpellData.new()
	s.id = p_id
	s.display_name = p_name
	s.form = p_form
	for e in p_effects:
		s.effects.append({"id": StringName(e[0]), "mag": float(e[1]), "dur": float(e[2])})
	s.area = p_area
	return s


# ---------------------------------------------------------------- cost and school

## Magicka per cast (per SECOND for a spray). skill_level = the caster's level in the spell's school
## (0 = don't discount). The same formula prices spells at the altar.
func get_cost(skill_level: int = 0) -> float:
	var total := 0.0
	for e in effects:
		total += effect_cost(e, form)
	total *= 1.0 + area * 0.12
	total *= FORM_COST[form]
	if skill_level > 0:
		total *= skill_discount(skill_level)
	return maxf(total, 1.0)


## 1.15 at level 1 down to 0.55 at level 100: practice makes spells cheaper
static func skill_discount(level: int) -> float:
	return clampf(1.15 - float(level) * 0.006, 0.55, 1.15)


static func effect_cost(e: Dictionary, f: int = Form.SELF) -> float:
	var d := MagicEffects.get_def(StringName(e.get("id", "")))
	if d.is_empty():
		return 0.0
	var base: float = d["cost"]
	var mag := maxf(float(e.get("mag", 0.0)), 1.0) if d["mag"] else 1.0
	var dur := float(e.get("dur", 0.0))
	match int(d["kind"]):
		MagicEffects.Kind.INSTANT:
			if f == Form.SPRAY:
				return base * mag  # mag = points per second while spraying
			return base * mag * (pow(dur, 0.85) if dur > 0.0 else 1.0)
		_:
			var dur_part := pow(maxf(dur, 1.0), 0.6) if d["dur"] else 1.0
			return base * mag * dur_part


## The school of the most expensive effect: it decides which skill casts it and trains
func get_school() -> StringName:
	var best: StringName = &"destruction"
	var best_cost := -1.0
	for e in effects:
		var c := effect_cost(e, form)
		if c > best_cost:
			best_cost = c
			best = MagicEffects.get_def(StringName(e["id"])).get("school", &"destruction")
	return best


func get_color() -> Color:
	if effects.is_empty():
		return Color.WHITE
	var first := StringName(effects[0]["id"])
	return MagicEffects.color_of(first)


## Does any effect hurt? Harmful spells can't be cast on yourself and count as attacks.
func is_harmful() -> bool:
	for e in effects:
		if MagicEffects.is_harmful(StringName(e["id"])):
			return true
	return false


## Seconds to hold the button before it goes off (spray starts at once)
func get_charge_time() -> float:
	match form:
		Form.SPRAY:
			return 0.0
		Form.SELF, Form.TOUCH:
			return 0.35
		Form.NOVA:
			return 0.7
	return 0.55


func get_area() -> float:
	if form == Form.NOVA:
		return maxf(area, NOVA_RADIUS)
	return area


## Every effect valid for this form? Returns "" or the reason it is not
func validate() -> String:
	if effects.is_empty():
		return "Add at least one effect."
	if effects.size() > MAX_EFFECTS:
		return "At most %d effects." % MAX_EFFECTS
	for e in effects:
		var eid := StringName(e["id"])
		if form == Form.SELF and not MagicEffects.allows_self(eid):
			return "%s can't be cast on yourself." % MagicEffects.display_name(eid)
		if form != Form.SELF and not MagicEffects.allows_others(eid):
			return "%s only works on yourself." % MagicEffects.display_name(eid)
	return ""


# ---------------------------------------------------------------- text

func describe(skill_level: int = 0) -> String:
	var lines := PackedStringArray()
	for e in effects:
		lines.append(MagicEffects.describe(e))
	var t := "\n".join(lines)
	t += "\n%s%s" % [FORM_NAMES[form], (", %d m burst" % roundi(get_area())) if get_area() > 0.0 else ""]
	t += "\nCost: %d magicka%s" % [roundi(get_cost(skill_level)), " per second" if form == Form.SPRAY else ""]
	return t


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var list: Array = []
	for e in effects:
		list.append({"id": String(e["id"]), "mag": e.get("mag", 0.0), "dur": e.get("dur", 0.0)})
	return {"id": id, "name": display_name, "form": int(form), "effects": list, "area": area, "custom": custom}


static func from_dict(d: Dictionary) -> SpellData:
	var s := SpellData.new()
	s.id = String(d.get("id", ""))
	s.display_name = String(d.get("name", "Spell"))
	s.form = clampi(int(d.get("form", 0)), 0, Form.size() - 1) as Form
	for e in d.get("effects", []):
		var eid := StringName(e.get("id", ""))
		if MagicEffects.has(eid):
			s.effects.append({"id": eid, "mag": float(e.get("mag", 0.0)), "dur": float(e.get("dur", 0.0))})
	s.area = float(d.get("area", 0.0))
	s.custom = bool(d.get("custom", false))
	return s


func duplicate_spell() -> SpellData:
	return SpellData.from_dict(to_dict())
