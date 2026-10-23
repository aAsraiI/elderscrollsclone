class_name SkillData
extends RefCounted
## Definition of one skill. Built in code by SkillDatabase, so there are no .tres files to make.
## Balance numbers live in SkillDatabase.gd, not here.

var id: StringName
var display_name: String
var group: String
var description: String
## How this skill gains XP (shown on the Stats screen)
var trains_by: String
## Multiplier on all XP this skill receives (>1 = levels faster)
var xp_mult := 1.0
## Stat key -> amount gained PER TIER (every 5 levels). Keys follow Stats rules:
## "max_health" is flat, "damage_pct" is a percentage (0.04 = +4%).
var tier_effects: Dictionary = {}
## Stat key -> text for the UI, e.g. "damage with one-handed weapons"
var tier_labels: Dictionary = {}
## true = the tier effects only apply while a weapon of this skill is in the main hand
var weapon_conditional := false
## Attribute -> points gained per skill level above the starting level (rounded down)
var attributes: Dictionary = {}


func _init(p_id: StringName, p_name: String, p_group: String, p_description: String, p_trains_by: String) -> void:
	id = p_id
	display_name = p_name
	group = p_group
	description = p_description
	trains_by = p_trains_by


# Builder helpers so SkillDatabase can read like a table
func effect(stat: String, per_tier: float, label: String) -> SkillData:
	tier_effects[stat] = per_tier
	tier_labels[stat] = label
	return self


func attribute(attr: String, per_level: float) -> SkillData:
	attributes[attr] = per_level
	return self


func weapon_only() -> SkillData:
	weapon_conditional = true
	return self


func rate(mult: float) -> SkillData:
	xp_mult = mult
	return self


## Text for the bonus at a given tier, e.g. "+20% damage with one-handed weapons"
func describe_effects(tier: int) -> String:
	if tier_effects.is_empty():
		return "-"
	var parts := PackedStringArray()
	for stat in tier_effects:
		var per_tier: float = tier_effects[stat]
		parts.append(format_effect(stat, per_tier, per_tier * tier, tier_labels.get(stat, stat)))
	return ", ".join(parts)


## "+8 Max magicka", "+20% damage", "-5% buy prices"
static func format_effect(stat: String, per_tier: float, amount: float, label: String) -> String:
	var percent := stat.ends_with("_pct") or absf(per_tier) < 1.0
	var shown := absf(amount) * (100.0 if percent else 1.0)
	var sign_text := "-" if amount < 0.0 else "+"
	var number := String.num(snappedf(shown, 0.1)).trim_suffix(".0")
	return "%s%s%s %s" % [sign_text, number, "%" if percent else "", label]
