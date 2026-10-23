class_name SkillDatabase
extends RefCounted
## Every skill, in one table, plus the XP curves. This is the file to edit when balancing.
##
## Each skill can have:
##   .effect(stat, amount_per_tier, label)  permanent bonus for every 5 levels
##   .attribute(name, points_per_level)     raises an attribute every level (rounded down)
##   .weapon_only()                         tier bonus only while that weapon type is in the main hand
##   .rate(mult)                            XP multiplier (1.0 = normal)

const MAX_LEVEL := 100
const START_LEVEL := 1
## A "tier" is one milestone: every 5 skill levels
const MILESTONE_INTERVAL := 5
## MAX_LEVEL / MILESTONE_INTERVAL (change it if you change either of those)
const MAX_TIER := 20

const GROUPS: Array[String] = ["Weapons", "Defense", "Magic", "Utility", "Crafting"]
const ATTRIBUTES: Array[String] = ["strength", "agility", "endurance", "wisdom", "stealth", "charisma"]

static var _skills: Array[SkillData] = []
static var _by_id: Dictionary = {}


static func get_all() -> Array[SkillData]:
	_ensure_built()
	return _skills


static func get_skill(skill_id: StringName) -> SkillData:
	_ensure_built()
	return _by_id.get(skill_id) as SkillData


# ---------------------------------------------------------------- XP curves

## XP needed to go from `level` to `level + 1` in one skill. The squared part makes high skill
## levels slower and slower: level 10 needs 55, level 50 needs 335, level 90 needs 775.
static func xp_to_next_level(level: int) -> float:
	return 10.0 + 4.0 * level + 0.05 * level * level


## Player XP earned when a skill reaches `level` (Skyrim style: reaching level N is worth N).
## Level 1 is worth 0, so this is 2 + 3 + ... + level.
static func skill_player_xp(level: int) -> int:
	return ((level * (level + 1)) >> 1) - 1


## Total player XP needed to be player level `level` (level 1 = 0, level 2 = 100, level 3 = 225, ...).
## Each level costs 25 more than the one before. Skills alone reach about level 80; the rest of
## the way to LevelCurve.MAX_LEVEL (100) comes from deeds (Skills.add_deed_xp: quests, bosses,
## new places).
static func player_xp_to_reach(level: int) -> int:
	var n := level - 1
	return 75 * n + ((25 * n * (n + 1)) >> 1)


## Player XP for a deed at this level: a finished quest, a dungeon boss, a newly found place.
## size: 1 = finding a place, 3 = a boss, 5 = a quest
static func deed_xp(level: int, size: float) -> int:
	return int(round((10.0 + 2.0 * level) * size))


# ---------------------------------------------------------------- the table

static func _ensure_built() -> void:
	if not _skills.is_empty():
		return

	# ---- Weapons: damage multiplier on (base damage + weapon damage), only with that weapon type
	_add(SkillData.new(&"one_handed", "One-Handed", "Weapons",
			"Swords, axes and maces held in one hand.",
			"Dealing damage with one-handed weapons (coming with combat)")
		.effect("damage_pct", 0.04, "damage with one-handed weapons").weapon_only()
		.attribute("strength", 0.15).attribute("agility", 0.10))
	_add(SkillData.new(&"two_handed", "Two-Handed", "Weapons",
			"Greatswords, battleaxes and warhammers.",
			"Dealing damage with two-handed weapons (coming with combat)")
		.effect("damage_pct", 0.05, "damage with two-handed weapons").weapon_only()
		.attribute("strength", 0.20))
	_add(SkillData.new(&"archery", "Archery", "Weapons",
			"Bows and crossbows.",
			"Dealing damage with ranged weapons (coming with combat)")
		.effect("damage_pct", 0.05, "damage with ranged weapons").weapon_only()
		.attribute("agility", 0.20))

	# ---- Defense: armor skills raise max health, always on
	_add(SkillData.new(&"heavy_armor", "Heavy Armor", "Defense",
			"Fighting in plate and other heavy armor.",
			"Taking hits while wearing heavy armor (coming with combat)")
		.effect("max_health", 10.0, "max health")
		.attribute("strength", 0.15).attribute("endurance", 0.10))
	_add(SkillData.new(&"light_armor", "Light Armor", "Defense",
			"Fighting in leather and other light armor.",
			"Taking hits while wearing light armor (coming with combat)")
		.effect("max_health", 6.0, "max health")
		.attribute("agility", 0.15).attribute("stealth", 0.10))
	_add(SkillData.new(&"block", "Block", "Defense",
			"Turning attacks aside with a shield or weapon.",
			"Blocking attacks (coming with combat)")
		.effect("block_strength", 0.03, "block strength")
		.attribute("endurance", 0.10))

	# ---- Magic: the six schools. Each raises max magicka and makes its spells stronger; spells of a
	# school also get cheaper with its level (SpellData.skill_discount). Casting trains them.
	var schools := [
		[&"destruction", "Destruction", "Fire, frost and lightning; weaknesses and withering.", 0.15, "strength"],
		[&"restoration", "Restoration", "Healing, fortifying and resisting; curing poison.", 0.15, "endurance"],
		[&"alteration", "Alteration", "Shields of magic, feather, haste, light, opening locks, paralysis.", 0.15, "agility"],
		[&"conjuration", "Conjuration", "Summoned creatures, bound weapons, raising the dead.", 0.15, "wisdom"],
		[&"illusion", "Illusion", "Calm, fear and frenzy; invisibility, muffle, night eye, charm.", 0.15, "charisma"],
		[&"mysticism", "Mysticism", "Soul trap, telekinesis, detect life, dispel, absorb, reflect, mark and recall.", 0.15, "wisdom"],
	]
	for s in schools:
		_add(SkillData.new(s[0], s[1], "Magic", s[2], "Casting %s spells (magicka spent)" % String(s[1]).to_lower())
			.effect("max_magicka", 5.0, "max magicka")
			.effect("power_" + String(s[0]), 0.03, "%s spell strength" % String(s[1]).to_lower())
			.attribute("wisdom", s[3]).attribute(s[4], 0.05))

	# ---- Utility
	_add(SkillData.new(&"sneak", "Sneak", "Utility",
			"Moving unseen and striking from the shadows.",
			"Moving while sneaking (needs a crouch input and enemy AI)")
		.effect("sneak_attack_bonus", 0.05, "sneak attack damage")
		.attribute("stealth", 0.50))
	_add(SkillData.new(&"athletics", "Athletics", "Utility",
			"Running and jumping.",
			"Sprinting and jumping")
		.effect("max_stamina", 8.0, "max stamina")
		.attribute("endurance", 0.30))
	_add(SkillData.new(&"speech", "Speech", "Utility",
			"Haggling, persuasion and dialogue checks.",
			"Trading goods and passing speech checks (coming with vendors and dialogue)")
		.effect("buy_price_mult", -0.01, "buy prices")
		.effect("sell_price_mult", 0.01, "sell prices")
		.attribute("charisma", 0.50))
	_add(SkillData.new(&"security", "Security", "Utility",
			"Lockpicking and trap disarming.",
			"Picking locks and disarming traps (coming with locks and traps)")
		.effect("security_bonus", 0.03, "lockpicking and disarming forgiveness")
		.attribute("agility", 0.10))

	# ---- Crafting
	_add(SkillData.new(&"smithing", "Smithing", "Crafting",
			"Forging and improving weapons and armor, smelting ore, tanning hides.",
			"Forging, smelting, tanning, improving gear, mining")
		.effect("smithing_potency", 0.03, "smithing potency")
		.attribute("strength", 0.05).attribute("wisdom", 0.05))
	_add(SkillData.new(&"alchemy", "Alchemy", "Crafting",
			"Brewing potions and poisons from ingredients.",
			"Brewing potions and poisons at an alchemy lab, eating ingredients")
		.effect("alchemy_potency", 0.03, "alchemy potency")
		.attribute("wisdom", 0.10))
	_add(SkillData.new(&"enchanting", "Enchanting", "Crafting",
			"Binding magical effects into gear.",
			"Enchanting and disenchanting at an arcane enchanter")
		.effect("enchanting_potency", 0.03, "enchanting potency")
		.attribute("wisdom", 0.10))
	_add(SkillData.new(&"tinkering", "Tinkering", "Crafting",
			"Miscellaneous crafting: tools, lockpicks, rings and amulets.",
			"Making things at a workbench")
		.effect("tinkering_potency", 0.03, "tinkering potency")
		.attribute("agility", 0.05).attribute("wisdom", 0.05))
	_add(SkillData.new(&"cooking", "Cooking", "Crafting",
			"Turning raw food into hearty meals.",
			"Cooking at a cooking pot")
		.effect("cooking_potency", 0.03, "meal strength")
		.attribute("endurance", 0.05).attribute("charisma", 0.05))


static func _add(def: SkillData) -> void:
	_skills.append(def)
	_by_id[def.id] = def
