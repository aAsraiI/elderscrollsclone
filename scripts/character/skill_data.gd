class_name SkillData
extends RefCounted
## Definition of one skill. Built in code by SkillDatabase, so there are no .tres files to make.
## Balance numbers live in SkillDatabase.gd, not here.
##
## A skill gives three kinds of bonus (Alpha 1.22):
##   * tier effects: small, every 5 levels (MILESTONE_INTERVAL), forever (half strength past 100)
##   * milestones: big named upgrades at levels 10, 25, 50, 75 and 100 (SkillDatabase.MAJOR_LEVELS)
##   * mastery: past level 100, every 25 levels adds the skill's mastery bonus once more

## When the bonuses of a skill count
enum When { ALWAYS, WEAPON, UNARMED, UNARMORED, DUAL_WIELD }

var id: StringName
var display_name: String
var group: String
var description: String
## How this skill gains XP (shown on the Stats screen)
var trains_by: String
## Multiplier on all XP this skill receives (>1 = levels faster)
var xp_mult := 1.0
## How much this skill's levels count toward the PLAYER level (1 = full). The many small life
## skills (swimming, farming...) count for less, so having more skills doesn't level you faster.
var player_xp_weight := 1.0
## Stat key -> amount gained PER TIER (every 5 levels). Keys follow Stats rules:
## "max_health" is flat, "damage_pct" is a percentage (0.04 = +4%).
var tier_effects: Dictionary = {}
## Stat key -> text for the UI, e.g. "damage with one-handed weapons"
var tier_labels: Dictionary = {}
## When the tier effects and milestones apply (see When)
var condition: When = When.ALWAYS
## true = the tier effects only apply while a weapon of this skill is in the main hand (old name
## for condition == WEAPON, kept for code that reads it)
var weapon_conditional := false
## Attribute -> points gained per skill level above the starting level (rounded down)
var attributes: Dictionary = {}
## level -> {"name", "desc", "stats": {stat: amount}, "always": bool}
var milestones: Dictionary = {}
## Stats added once for every MASTERY_STEP levels past MASTERY_START
var mastery: Dictionary = {}


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
	condition = When.WEAPON
	return self


func only_when(w: When) -> SkillData:
	condition = w
	weapon_conditional = w == When.WEAPON
	return self


func rate(mult: float) -> SkillData:
	xp_mult = mult
	return self


func weight(w: float) -> SkillData:
	player_xp_weight = w
	return self


## A big upgrade at a skill level. always = it counts even when the skill's condition is not met
## (a one-handed perk that raises max stamina, say).
func at(level: int, p_name: String, desc: String, stats: Dictionary, always: bool = false) -> SkillData:
	milestones[level] = {"name": p_name, "desc": desc, "stats": stats, "always": always}
	return self


func mastered(stats: Dictionary) -> SkillData:
	mastery = stats
	return self


## Milestone levels, lowest first
func milestone_levels() -> Array:
	var out := milestones.keys()
	out.sort()
	return out


## Text for the bonus at a given tier, e.g. "+20% damage with one-handed weapons"
func describe_effects(tier: float) -> String:
	if tier_effects.is_empty():
		return "-"
	var parts := PackedStringArray()
	for stat in tier_effects:
		var per_tier: float = tier_effects[stat]
		parts.append(format_effect(stat, per_tier, per_tier * tier, tier_labels.get(stat, stat)))
	return ", ".join(parts)


## "+5% critical chance, -10% stamina per swing"
static func describe_stats(stats: Dictionary) -> String:
	var parts := PackedStringArray()
	for stat in stats:
		var amount := float(stats[stat])
		parts.append(format_effect(stat, amount, amount, stat_label(stat)))
	return ", ".join(parts)


## "+8 Max magicka", "+20% damage", "-5% buy prices"
static func format_effect(stat: String, per_tier: float, amount: float, label: String) -> String:
	var percent := stat.ends_with("_pct") or stat.ends_with("_mult") or PERCENT_STATS.has(stat) or (absf(per_tier) < 1.0 and not FLAT_STATS.has(stat))
	var shown := absf(amount) * (100.0 if percent else 1.0)
	var sign_text := "-" if amount < 0.0 else "+"
	var number := String.num(snappedf(shown, 0.1)).trim_suffix(".0")
	return "%s%s%s %s" % [sign_text, number, "%" if percent else "", label]


## Stats always shown as a percentage, and stats always shown as plain points
const PERCENT_STATS: Array[String] = ["crit_chance", "crit_mult", "armor_pen", "life_leech", "execute_bonus", "damage_reduction",
	"poise_bonus", "fall_resist", "harvest_bonus", "mining_bonus", "farming_bonus", "gem_find", "crop_growth", "follower_damage",
	"follower_health", "persuade_bonus", "blessing_mult", "skill_xp_pct", "sneak_attack_bonus", "security_bonus", "pickpocket_bonus", "block_strength",
	"spell_power", "spell_absorb", "reflect", "bane_undead", "bane_beast", "mounted_damage"]
const FLAT_STATS: Array[String] = ["max_health", "max_magicka", "max_stamina", "carry_capacity", "armor", "damage", "unarmed_damage",
	"strength", "agility", "endurance", "wisdom", "stealth", "charisma", "health_regen", "magicka_regen", "reach_bonus"]

## Plain-language names of stats, for perk and milestone text
const LABELS := {
	"max_health": "max health", "max_magicka": "max magicka", "max_stamina": "max stamina", "carry_capacity": "carry weight",
	"armor": "armor", "armor_pct": "armor", "damage": "damage", "damage_pct": "damage", "health_regen": "health per second",
	"magicka_regen": "magicka per second", "magicka_regen_pct": "magicka regeneration", "stamina_regen_mult": "stamina regeneration",
	"move_speed_mult": "movement speed", "jump_mult": "jump height", "fall_resist": "less falling damage",
	"crit_chance": "critical hit chance", "crit_mult": "critical damage", "power_attack_pct": "heavy attack damage",
	"attack_cost_mult": "stamina per swing", "block_cost_mult": "stamina when blocking", "armor_pen": "of armor ignored",
	"life_leech": "of melee damage healed", "execute_bonus": "damage to foes below 30% health", "damage_reduction": "less damage taken",
	"poise_bonus": "stagger power", "swim_speed_mult": "swimming speed", "breath_mult": "breath under water",
	"horse_speed_mult": "horse speed", "horse_stamina_mult": "horse stamina", "mounted_damage": "damage from the saddle",
	"harvest_bonus": "extra herbs", "mining_bonus": "extra ore", "gem_find": "chance of a gem when mining",
	"farming_bonus": "bigger harvests", "crop_growth": "faster growing crops", "potion_mult": "healing from potions and food",
	"hunger_mult": "hunger and tiredness", "follower_damage": "damage by followers and summons",
	"follower_health": "health of followers and summons", "persuade_bonus": "persuasion chance",
	"magicka_cost_mult": "spell cost", "blessing_mult": "shrine blessing strength", "sneak_speed_mult": "speed while sneaking",
	"noise_mult": "noise", "unarmed_damage": "unarmed damage", "block_strength": "block strength",
	"sneak_attack_bonus": "sneak attack damage", "buy_price_mult": "buy prices", "sell_price_mult": "sell prices",
	"security_bonus": "lockpicking forgiveness", "pickpocket_bonus": "pickpocket chance", "smithing_potency": "smithing", "alchemy_potency": "potion strength",
	"enchanting_potency": "enchantment strength", "cooking_potency": "meal strength", "skill_xp_pct": "skill XP",
	"spell_power": "spell strength", "spell_absorb": "chance to absorb spells", "reflect": "chance to reflect spells",
	"resist_fire": "fire resistance", "resist_frost": "frost resistance", "resist_shock": "shock resistance",
	"resist_poison": "poison resistance", "resist_magic": "magic resistance", "resist_disease": "disease resistance",
	"bane_undead": "damage to the undead", "bane_beast": "damage to beasts", "water_breathing": "water breathing",
	"reach_bonus": "m weapon reach", "strength": "strength", "agility": "agility", "endurance": "endurance",
	"wisdom": "wisdom", "stealth": "stealth", "charisma": "charisma", "night_eye": "night eye",
}


static func stat_label(stat: String) -> String:
	if LABELS.has(stat):
		return LABELS[stat]
	if stat.begins_with("power_"):
		return "%s spell strength" % stat.trim_prefix("power_")
	if stat.begins_with("cost_"):
		return "%s spell cost" % stat.trim_prefix("cost_")
	return stat.replace("_", " ")
