class_name SkillDatabase
extends RefCounted
## Every skill, in one table, plus the XP curves. This is the file to edit when balancing.
##
## Each skill can have:
##   .effect(stat, amount_per_tier, label)  permanent bonus for every 5 levels
##   .attribute(name, points_per_level)     raises an attribute every level (rounded down)
##   .weapon_only() / .only_when(When.X)    bonuses only while wielding that weapon, unarmed, ...
##   .at(level, name, desc, {stats})        a big named upgrade at that level (10, 25, 50, 75, 100)
##   .mastered({stats})                     added again for every 25 levels past 100
##   .rate(mult)                            XP multiplier (1.0 = normal)
##   .weight(w)                             how much it counts toward the player level
##
## Alpha 1.22: skills and the player level have no cap. Past level 100 a skill keeps getting its
## tier bonus (at half strength, see TIER_FALLOFF) plus its mastery bonus every 25 levels.

## The old cap. Skills keep going past it; it is still where the last named milestone sits.
const MASTER_LEVEL := 100
## Kept for old code: there is no real maximum any more
const MAX_LEVEL := 1000000
const START_LEVEL := 1
## A "tier" is one small step: every 5 skill levels
const MILESTONE_INTERVAL := 5
## Tiers up to level 100 (the bar on the Stats screen)
const MAX_TIER := 20
## Tier bonuses past MAX_TIER count this much each
const TIER_FALLOFF := 0.5
## The levels of the big named milestones
const MAJOR_LEVELS: Array[int] = [10, 25, 50, 75, 100]
## Past MASTERY_START every MASTERY_STEP levels adds the skill's mastery bonus
const MASTERY_START := 100
const MASTERY_STEP := 25

const GROUPS: Array[String] = ["Weapons", "Defense", "Magic", "Stealth", "Movement", "Social", "Crafting", "Wilderness"]
const ATTRIBUTES: Array[String] = ["strength", "agility", "endurance", "wisdom", "stealth", "charisma"]

## Rank names by skill level (Morrowind/Oblivion style)
const RANKS: Array = [[0, "Novice"], [10, "Apprentice"], [25, "Journeyman"], [50, "Adept"], [75, "Expert"], [100, "Master"],
	[150, "Grandmaster"], [200, "Legend"], [300, "Mythic"], [500, "Ascendant"]]

static var _skills: Array[SkillData] = []
static var _by_id: Dictionary = {}


static func get_all() -> Array[SkillData]:
	_ensure_built()
	return _skills


static func get_skill(skill_id: StringName) -> SkillData:
	_ensure_built()
	return _by_id.get(skill_id) as SkillData


static func rank_name(level: int) -> String:
	var out: String = RANKS[0][1]
	for r in RANKS:
		if level >= int(r[0]):
			out = r[1]
	return out


## Tiers that count, with the half-strength falloff past level 100: level 150 = 20 + 10 * 0.5 = 25
static func effective_tiers(level: int) -> float:
	var t := floori(float(level) / MILESTONE_INTERVAL)
	return float(mini(t, MAX_TIER)) + float(maxi(t - MAX_TIER, 0)) * TIER_FALLOFF


## How many mastery bonuses a skill of this level has (125 = 1, 150 = 2, ...)
static func mastery_count(level: int) -> int:
	return maxi(0, (level - MASTERY_START) / MASTERY_STEP)


# ---------------------------------------------------------------- XP curves

## XP needed to go from `level` to `level + 1` in one skill. The squared part makes high skill
## levels slower and slower: level 10 needs 55, level 50 needs 335, level 100 needs 910,
## level 200 needs 2810.
static func xp_to_next_level(level: int) -> float:
	return 10.0 + 4.0 * level + 0.05 * level * level


## Player XP earned when a skill reaches `level` (Skyrim style: reaching level N is worth N).
## Level 1 is worth 0, so this is 2 + 3 + ... + level.
static func skill_player_xp(level: int) -> int:
	return ((level * (level + 1)) >> 1) - 1


## Total player XP needed to be player level `level` (level 1 = 0, level 2 = 100, level 3 = 225, ...).
## Up to level 100 each level costs 25 more than the one before. Past 100 the step only grows by 10
## a level, so leveling slows but never stops (there is no cap). Skills and deeds (quests, bosses,
## new places: Skills.add_deed_xp) both count.
static func player_xp_to_reach(level: int) -> int:
	var n := level - 1
	if n <= 99:
		return 75 * n + ((25 * n * (n + 1)) >> 1)
	var base := 75 * 99 + ((25 * 99 * 100) >> 1)
	var m := n - 99
	# step at level 100 is 75 + 25 * 100 = 2575, then +10 each level
	return base + 2575 * m + 5 * m * (m - 1)


## Player XP for a deed at this level: a finished quest, a dungeon boss, a newly found place.
## size: 1 = finding a place, 3 = a boss, 5 = a quest
static func deed_xp(level: int, size: float) -> int:
	return int(round((10.0 + 2.0 * level) * size))


# ---------------------------------------------------------------- the table

static func _ensure_built() -> void:
	if not _skills.is_empty():
		return
	_weapons()
	_defense()
	_magic()
	_stealth()
	_movement()
	_social()
	_crafting()
	_wilderness()


static func _weapons() -> void:
	# Weapons: damage multiplier on (base damage + weapon damage), only with that weapon type
	_add(SkillData.new(&"one_handed", "One-Handed", "Weapons",
			"Swords, axes, maces and daggers held in one hand.",
			"Dealing damage with one-handed weapons")
		.effect("damage_pct", 0.04, "damage with one-handed weapons").weapon_only()
		.attribute("strength", 0.15).attribute("agility", 0.10)
		.at(10, "Quick Hands", "Your swings cost less stamina.", {"attack_cost_mult": -0.10})
		.at(25, "Keen Edge", "You find the gaps in armor.", {"crit_chance": 0.05})
		.at(50, "Bladesman", "Heavy attacks hit much harder.", {"power_attack_pct": 0.25})
		.at(75, "Bloodletter", "Critical hits bite deeper.", {"crit_mult": 0.25})
		.at(100, "Master of Arms", "The blade is part of you.", {"damage_pct": 0.15, "crit_chance": 0.05})
		.mastered({"damage_pct": 0.05}))
	_add(SkillData.new(&"two_handed", "Two-Handed", "Weapons",
			"Greatswords, battleaxes, warhammers, spears and halberds.",
			"Dealing damage with two-handed weapons")
		.effect("damage_pct", 0.05, "damage with two-handed weapons").weapon_only()
		.attribute("strength", 0.20)
		.at(10, "Heavy Swings", "Your blows stagger foes sooner.", {"poise_bonus": 0.15})
		.at(25, "Cleave", "Heavy attacks hit much harder.", {"power_attack_pct": 0.25})
		.at(50, "Armor Breaker", "Your blows crush through armor.", {"armor_pen": 0.20})
		.at(75, "Devastating Blow", "Critical hits land like a falling tree.", {"crit_mult": 0.35, "crit_chance": 0.03})
		.at(100, "Warlord", "Nothing stands before your swing.", {"damage_pct": 0.15, "power_attack_pct": 0.25})
		.mastered({"damage_pct": 0.05}))
	_add(SkillData.new(&"archery", "Archery", "Weapons",
			"Bows and arrows.",
			"Hitting things with arrows")
		.effect("damage_pct", 0.05, "damage with bows").weapon_only()
		.attribute("agility", 0.20)
		.at(10, "Steady Hand", "Your aim is surer.", {"crit_chance": 0.03})
		.at(25, "Eagle Eye", "Critical shots strike deeper.", {"crit_mult": 0.25})
		.at(50, "Piercing Shots", "Arrows punch through armor.", {"armor_pen": 0.20})
		.at(75, "Deadeye", "You rarely miss the heart.", {"crit_chance": 0.07})
		.at(100, "Master Archer", "Your arrows are legend.", {"damage_pct": 0.20, "crit_mult": 0.25})
		.mastered({"damage_pct": 0.05}))
	_add(SkillData.new(&"hand_to_hand", "Hand-to-Hand", "Weapons",
			"Fighting with fists and feet, no weapon in hand.",
			"Dealing damage with your bare hands")
		.effect("unarmed_damage", 1.5, "unarmed damage").only_when(SkillData.When.UNARMED)
		.attribute("strength", 0.10).attribute("agility", 0.10)
		.at(10, "Iron Fists", "Your punches land like clubs.", {"unarmed_damage": 5.0})
		.at(25, "Flurry", "Punches barely tire you.", {"attack_cost_mult": -0.20})
		.at(50, "Pressure Points", "You know where it hurts.", {"crit_chance": 0.08})
		.at(75, "Stunning Blows", "Your blows stagger even big foes.", {"poise_bonus": 0.40})
		.at(100, "Fists of Stone", "Your hands are weapons.", {"unarmed_damage": 25.0, "crit_mult": 0.5})
		.mastered({"unarmed_damage": 8.0}))
	_add(SkillData.new(&"dual_wielding", "Dual Wielding", "Weapons",
			"A weapon in each hand.",
			"Hitting things while holding a weapon in each hand")
		.effect("damage_pct", 0.02, "damage while dual wielding").only_when(SkillData.When.DUAL_WIELD)
		.attribute("agility", 0.15)
		.at(10, "Twin Strikes", "Two blades cost less effort.", {"attack_cost_mult": -0.10})
		.at(25, "Whirlwind Blades", "You find openings everywhere.", {"crit_chance": 0.05})
		.at(50, "Flowing Steel", "Your heavy strikes come from both sides.", {"power_attack_pct": 0.30})
		.at(75, "Bladestorm", "Two blades, two wounds.", {"damage_pct": 0.10, "life_leech": 0.02})
		.at(100, "Twin Fang", "A storm of steel.", {"damage_pct": 0.15, "crit_mult": 0.30})
		.mastered({"damage_pct": 0.04}))


static func _defense() -> void:
	# Defense: armor skills raise max health, always on; their milestones make you tougher
	_add(SkillData.new(&"heavy_armor", "Heavy Armor", "Defense",
			"Fighting in plate and other heavy armor.",
			"Taking hits while wearing heavy armor")
		.effect("max_health", 10.0, "max health")
		.attribute("strength", 0.15).attribute("endurance", 0.10)
		.at(10, "Plated", "You wear plate well.", {"armor_pct": 0.05})
		.at(25, "Juggernaut's Stance", "Blows glance off.", {"damage_reduction": 0.05})
		.at(50, "Unyielding", "Your armor is a wall.", {"armor_pct": 0.10, "max_health": 25.0})
		.at(75, "Iron Wall", "Hardly anything gets through.", {"damage_reduction": 0.05})
		.at(100, "Living Fortress", "You are the castle.", {"armor_pct": 0.15, "max_health": 50.0})
		.mastered({"max_health": 20.0}))
	_add(SkillData.new(&"light_armor", "Light Armor", "Defense",
			"Fighting in leather and other light armor.",
			"Taking hits while wearing light armor")
		.effect("max_health", 6.0, "max health")
		.attribute("agility", 0.15).attribute("stealth", 0.10)
		.at(10, "Supple", "Light armor never slows you.", {"move_speed_mult": 0.03})
		.at(25, "Agile Defense", "You roll with the blows.", {"damage_reduction": 0.04})
		.at(50, "Wind Walker", "You catch your breath quickly.", {"stamina_regen_mult": 0.20})
		.at(75, "Deft Movement", "Light as a cat.", {"move_speed_mult": 0.05, "damage_reduction": 0.03})
		.at(100, "Shadowskin", "Leather that turns steel.", {"armor_pct": 0.15, "damage_reduction": 0.05})
		.mastered({"max_health": 12.0}))
	_add(SkillData.new(&"block", "Block", "Defense",
			"Turning attacks aside with a shield or weapon.",
			"Blocking attacks")
		.effect("block_strength", 0.03, "block strength")
		.attribute("endurance", 0.10)
		.at(10, "Steady Guard", "Blocking tires you less.", {"block_cost_mult": -0.15})
		.at(25, "Shield Wall", "Your guard covers you well.", {"armor": 10.0})
		.at(50, "Deflect", "Blows slide off your shield.", {"block_cost_mult": -0.15, "block_strength": 0.05})
		.at(75, "Quick Reflexes", "You turn even the hits you don't block.", {"damage_reduction": 0.03})
		.at(100, "Bulwark", "An unbreakable guard.", {"block_strength": 0.10, "armor": 20.0})
		.mastered({"armor": 5.0}))
	_add(SkillData.new(&"unarmored", "Unarmored", "Defense",
			"Dodging and turning blows in plain clothes, wearing no armor at all.",
			"Taking hits while wearing no armor")
		.effect("armor", 3.0, "armor while wearing no armor").only_when(SkillData.When.UNARMORED)
		.attribute("agility", 0.15).attribute("endurance", 0.10)
		.at(10, "Light Footed", "Nothing weighs you down.", {"move_speed_mult": 0.03})
		.at(25, "Evasion", "You sway out of harm's way.", {"damage_reduction": 0.05})
		.at(50, "Iron Skin", "Your body is its own armor.", {"armor": 20.0})
		.at(75, "Mind over Body", "Wounds close by themselves.", {"health_regen": 0.5})
		.at(100, "Untouchable", "Blades find only air.", {"damage_reduction": 0.10, "armor": 30.0})
		.mastered({"armor": 8.0}))


static func _magic() -> void:
	# Magic: the six schools. Each raises max magicka and makes its spells stronger; spells of a
	# school also get cheaper with its level (SpellData.skill_discount) and its milestones. Casting trains them.
	var schools := [
		[&"destruction", "Destruction", "Fire, frost and lightning; weaknesses and withering.", "strength",
			["Augmented Flames", "The elements answer you.", {"spell_power": 0.05, "resist_fire": 0.1}]],
		[&"restoration", "Restoration", "Healing, fortifying and resisting; curing poison.", "endurance",
			["Regeneration", "Your body mends itself.", {"health_regen": 0.5}]],
		[&"alteration", "Alteration", "Shields of magic, feather, haste, light, opening locks, paralysis.", "agility",
			["Mage Armor", "A shell of magic always surrounds you.", {"armor": 15.0}]],
		[&"conjuration", "Conjuration", "Summoned creatures, bound weapons, raising the dead.", "wisdom",
			["Summoner's Bond", "Your summons fight harder.", {"follower_damage": 0.15, "follower_health": 0.15}]],
		[&"illusion", "Illusion", "Calm, fear and frenzy; invisibility, muffle, night eye, charm.", "charisma",
			["Quiet Casting", "Your spells make no sound.", {"noise_mult": -0.10, "persuade_bonus": 0.05}]],
		[&"mysticism", "Mysticism", "Soul trap, telekinesis, detect life, dispel, absorb, reflect, mark and recall.", "wisdom",
			["Spell Ward", "Hostile spells slide off you.", {"spell_absorb": 0.05, "resist_magic": 0.05}]],
	]
	for s in schools:
		var sid: String = String(s[0])
		var nm: String = s[1]
		var special: Array = s[4]
		_add(SkillData.new(s[0], nm, "Magic", s[2], "Casting %s spells (magicka spent)" % nm.to_lower())
			.effect("max_magicka", 5.0, "max magicka")
			.effect("power_" + sid, 0.03, "%s spell strength" % nm.to_lower())
			.attribute("wisdom", 0.15).attribute(s[3], 0.05)
			.at(10, "Apprentice of %s" % nm, "%s spells cost less." % nm, {"cost_" + sid: -0.05})
			.at(25, "%s Focus" % nm, "%s spells are stronger." % nm, {"power_" + sid: 0.10})
			.at(50, special[0], special[1], special[2])
			.at(75, "Expert of %s" % nm, "%s spells are much cheaper and stronger." % nm, {"cost_" + sid: -0.10, "power_" + sid: 0.15})
			.at(100, "Master of %s" % nm, "You have mastered %s." % nm.to_lower(), {"power_" + sid: 0.20, "cost_" + sid: -0.10, "max_magicka": 50.0})
			.mastered({"power_" + sid: 0.05, "max_magicka": 10.0}))


static func _stealth() -> void:
	_add(SkillData.new(&"sneak", "Sneak", "Stealth",
			"Moving unseen and striking from the shadows.",
			"Moving while sneaking near enemies")
		.effect("sneak_attack_bonus", 0.05, "sneak attack damage")
		.attribute("stealth", 0.50)
		.at(10, "Light Steps", "You make less noise.", {"noise_mult": -0.10})
		.at(25, "Assassin's Strike", "Sneak attacks hit much harder.", {"sneak_attack_bonus": 0.25})
		.at(50, "Silent Stride", "You sneak almost as fast as you walk.", {"sneak_speed_mult": 0.25})
		.at(75, "Shadow Dance", "Even your armor is quiet.", {"noise_mult": -0.15})
		.at(100, "Unseen", "Death from nowhere.", {"sneak_attack_bonus": 0.50, "crit_chance": 0.05}, true)
		.mastered({"sneak_attack_bonus": 0.10}))
	_add(SkillData.new(&"security", "Security", "Stealth",
			"Lockpicking and trap disarming.",
			"Picking locks and disarming traps")
		.effect("security_bonus", 0.03, "lockpicking and disarming forgiveness")
		.attribute("agility", 0.10)
		.at(10, "Nimble Picks", "Your picks find the pins quickly.", {"security_bonus": 0.05})
		.at(25, "Trap Sense", "You feel the tripwire before you touch it.", {"security_bonus": 0.05, "fall_resist": 0.05})
		.at(50, "Locksmith", "Few locks keep you out.", {"security_bonus": 0.10})
		.at(75, "Safecracker", "Even master locks yield.", {"security_bonus": 0.10, "agility": 5.0})
		.at(100, "Master Locksmith", "No lock in the realm holds you.", {"security_bonus": 0.20})
		.mastered({"security_bonus": 0.05}))
	_add(SkillData.new(&"pickpocket", "Pickpocket", "Stealth",  # 1.29
			"Lifting purses and slipping things into pockets.",
			"Picking pockets (sneak up on someone unaware and press E)")
		.effect("pickpocket_bonus", 0.004, "pickpocket chance")
		.attribute("agility", 0.15)
		.at(10, "Light Touch", "Your fingers are quick.", {"pickpocket_bonus": 0.05})
		.at(25, "Plant", "You can slip things into pockets, too.", {"pickpocket_bonus": 0.05})
		.at(50, "Cutpurse", "Heavy purses come away easily.", {"pickpocket_bonus": 0.10})
		.at(75, "Misdirection", "Nobody feels a thing.", {"pickpocket_bonus": 0.10})
		.at(100, "Master Thief", "You can lift even what they wear and wield.", {"pickpocket_bonus": 0.15}, true)
		.mastered({"pickpocket_bonus": 0.03}))


static func _movement() -> void:
	_add(SkillData.new(&"athletics", "Athletics", "Movement",
			"Running far and fast.",
			"Sprinting")
		.effect("move_speed_mult", 0.01, "movement speed")
		.effect("max_stamina", 4.0, "max stamina")
		.attribute("endurance", 0.20).attribute("agility", 0.10)
		.at(10, "Runner", "You catch your breath faster.", {"stamina_regen_mult": 0.10})
		.at(25, "Long Stride", "Your stride lengthens.", {"move_speed_mult": 0.03})
		.at(50, "Tireless", "You can run all day.", {"max_stamina": 40.0, "stamina_regen_mult": 0.15})
		.at(75, "Fleet Foot", "Few can keep up with you.", {"move_speed_mult": 0.04})
		.at(100, "Windrunner", "You run like the wind.", {"move_speed_mult": 0.06, "stamina_regen_mult": 0.30})
		.mastered({"move_speed_mult": 0.01, "max_stamina": 10.0}))
	_add(SkillData.new(&"acrobatics", "Acrobatics", "Movement",
			"Jumping high and landing well.",
			"Jumping, and falling without breaking your legs")
		.effect("jump_mult", 0.03, "jump height")
		.effect("fall_resist", 0.02, "less falling damage")
		.attribute("agility", 0.25)
		.at(10, "Spring Step", "You jump higher.", {"jump_mult": 0.10})
		.at(25, "Soft Landing", "Falls hurt you much less.", {"fall_resist": 0.25})
		.at(50, "Leaper", "You leap like a deer.", {"jump_mult": 0.15})
		.at(75, "Cat's Grace", "You land on your feet.", {"fall_resist": 0.35})
		.at(100, "Featherfall", "The ground is your friend.", {"jump_mult": 0.25, "fall_resist": 0.40})
		.mastered({"jump_mult": 0.05})
		.rate(1.2).weight(0.5))
	_add(SkillData.new(&"swimming", "Swimming", "Movement",
			"Swimming fast and holding your breath.",
			"Swimming")
		.effect("swim_speed_mult", 0.03, "swimming speed")
		.effect("breath_mult", 0.05, "breath under water")
		.attribute("endurance", 0.10).attribute("agility", 0.05)
		.at(10, "Strong Strokes", "You swim faster.", {"swim_speed_mult": 0.10})
		.at(25, "Deep Lungs", "You hold your breath much longer.", {"breath_mult": 0.50})
		.at(50, "Sea Legs", "Water hardly tires you.", {"swim_speed_mult": 0.10, "stamina_regen_mult": 0.10})
		.at(75, "Otter", "You glide through water.", {"swim_speed_mult": 0.20})
		.at(100, "Child of the Tide", "You breathe water like air.", {"water_breathing": 1.0, "swim_speed_mult": 0.25})
		.mastered({"swim_speed_mult": 0.05})
		.weight(0.5))
	_add(SkillData.new(&"riding", "Riding", "Movement",
			"Riding horses and fighting from the saddle.",
			"Riding a horse")
		.effect("horse_speed_mult", 0.01, "horse speed")
		.attribute("agility", 0.05).attribute("endurance", 0.05)
		.at(10, "Steady Seat", "Your horse runs faster under you.", {"horse_speed_mult": 0.03})
		.at(25, "Horse Whisperer", "Your horse tires less.", {"horse_stamina_mult": 0.30})
		.at(50, "Mounted Combat", "You strike hard from the saddle.", {"mounted_damage": 0.25})
		.at(75, "Cavalier", "You and your horse are one.", {"horse_speed_mult": 0.05})
		.at(100, "Master Rider", "Your horse never tires.", {"horse_speed_mult": 0.10, "horse_stamina_mult": 0.50, "mounted_damage": 0.25})
		.mastered({"horse_speed_mult": 0.02})
		.weight(0.5))


static func _social() -> void:
	_add(SkillData.new(&"speech", "Speech", "Social",
			"Persuasion, charm, threats and dialogue checks.",
			"Persuading people and passing speech checks")
		.effect("persuade_bonus", 0.01, "persuasion chance")
		.attribute("charisma", 0.50)
		.at(10, "Silver Tongue", "People listen to you.", {"persuade_bonus": 0.05})
		.at(25, "Pleasant Company", "You are easy to like.", {"charisma": 5.0})
		.at(50, "Persuasive", "Few can say no to you.", {"persuade_bonus": 0.10})
		.at(75, "Commanding Voice", "You speak and people obey.", {"charisma": 10.0})
		.at(100, "Legendary Orator", "Kings ask your counsel.", {"persuade_bonus": 0.15, "buy_price_mult": -0.05})
		.mastered({"persuade_bonus": 0.02}))
	_add(SkillData.new(&"mercantile", "Mercantile", "Social",
			"Haggling over prices with merchants.",
			"Buying and selling")
		.effect("buy_price_mult", -0.01, "buy prices")
		.effect("sell_price_mult", 0.01, "sell prices")
		.attribute("charisma", 0.20)
		.at(10, "Haggler", "You talk prices down.", {"buy_price_mult": -0.03})
		.at(25, "Bargain Hunter", "You talk prices up.", {"sell_price_mult": 0.03})
		.at(50, "Trade Network", "Merchants respect you.", {"buy_price_mult": -0.05, "sell_price_mult": 0.05})
		.at(75, "Investor", "You always get a fair deal.", {"buy_price_mult": -0.05, "sell_price_mult": 0.05})
		.at(100, "Merchant Prince", "The markets bend to you.", {"buy_price_mult": -0.10, "sell_price_mult": 0.10})
		.mastered({"buy_price_mult": -0.01, "sell_price_mult": 0.01})
		.weight(0.6))
	_add(SkillData.new(&"leadership", "Leadership", "Social",
			"Leading followers and summoned allies.",
			"Your followers and summons fighting and killing")
		.effect("follower_damage", 0.02, "damage by followers and summons")
		.effect("follower_health", 0.03, "health of followers and summons")
		.attribute("charisma", 0.20)
		.at(10, "Rallying Presence", "Your allies are tougher.", {"follower_health": 0.10})
		.at(25, "Inspire", "Your allies hit harder.", {"follower_damage": 0.10})
		.at(50, "Tactician", "Your allies fight as one.", {"follower_damage": 0.15, "follower_health": 0.15})
		.at(75, "Warband", "They would die for you.", {"follower_health": 0.20})
		.at(100, "Lord Commander", "An army at your back.", {"follower_damage": 0.25, "follower_health": 0.25})
		.mastered({"follower_damage": 0.03, "follower_health": 0.03})
		.rate(1.5).weight(0.6))
	_add(SkillData.new(&"devotion", "Devotion", "Social",
			"Faith in the gods: blessings at shrines, wards against the dead.",
			"Praying at shrines and slaying the undead")
		.effect("resist_magic", 0.005, "magic resistance")
		.effect("bane_undead", 0.01, "damage to the undead")
		.attribute("wisdom", 0.10).attribute("charisma", 0.05)
		.at(10, "Faithful", "Sickness passes you by.", {"resist_disease": 0.25})
		.at(25, "Blessed", "Shrine blessings are stronger.", {"blessing_mult": 0.25})
		.at(50, "Warded", "The gods turn spells from you.", {"resist_magic": 0.10})
		.at(75, "Sanctified", "The dead fear you.", {"bane_undead": 0.20})
		.at(100, "Saint", "The gods walk with you.", {"blessing_mult": 0.50, "resist_magic": 0.10, "health_regen": 0.5})
		.mastered({"bane_undead": 0.05})
		.rate(2.0).weight(0.6))
	_add(SkillData.new(&"lore", "Lore", "Social",
			"Books, history and the knowledge of places.",
			"Reading books for the first time and finding new places")
		.effect("skill_xp_pct", 0.01, "skill XP")
		.attribute("wisdom", 0.15)
		.at(10, "Bookworm", "Study sharpens the mind.", {"max_magicka": 10.0})
		.at(25, "Scholar", "You learn faster.", {"skill_xp_pct": 0.03})
		.at(50, "Loremaster", "Magic flows easily to you.", {"magicka_regen_pct": 0.10})
		.at(75, "Sage", "Everything teaches you something.", {"skill_xp_pct": 0.05})
		.at(100, "Keeper of Knowledge", "You know the old secrets.", {"skill_xp_pct": 0.10, "spell_power": 0.05})
		.mastered({"skill_xp_pct": 0.01})
		.rate(1.5).weight(0.6))


static func _crafting() -> void:
	_add(SkillData.new(&"smithing", "Smithing", "Crafting",
			"Forging and improving weapons and armor, smelting ore, tanning hides.",
			"Forging, smelting, tanning, improving gear")
		.effect("smithing_potency", 0.03, "smithing potency")
		.attribute("strength", 0.05).attribute("wisdom", 0.05)
		.at(10, "Apprentice Smith", "Your work is cleaner.", {"smithing_potency": 0.05})
		.at(25, "Armorsmith", "You keep your armor in top shape.", {"armor_pct": 0.03})
		.at(50, "Steelsmith", "You improve gear one step further.", {"smithing_potency": 0.10})
		.at(75, "Weaponsmith", "Your blades stay keen.", {"damage_pct": 0.03})
		.at(100, "Master Smith", "Your forge work is the best in the realm.", {"smithing_potency": 0.25})
		.mastered({"smithing_potency": 0.05}))
	_add(SkillData.new(&"alchemy", "Alchemy", "Crafting",
			"Brewing potions and poisons from ingredients.",
			"Brewing potions and poisons at an alchemy lab, eating ingredients")
		.effect("alchemy_potency", 0.03, "alchemy potency")
		.attribute("wisdom", 0.10)
		.at(10, "Concentrated Brews", "Your potions are stronger.", {"alchemy_potency": 0.05})
		.at(25, "Apothecary", "Potions heal you more.", {"potion_mult": 0.10})
		.at(50, "Benefactor", "Your brews are potent.", {"alchemy_potency": 0.10})
		.at(75, "Poisoner", "Your poisons hold you safe from others'.", {"alchemy_potency": 0.10, "resist_poison": 0.25})
		.at(100, "Master Alchemist", "Anything can be brewed.", {"alchemy_potency": 0.25, "potion_mult": 0.15})
		.mastered({"alchemy_potency": 0.05}))
	_add(SkillData.new(&"enchanting", "Enchanting", "Crafting",
			"Binding magical effects into gear.",
			"Enchanting and disenchanting at an arcane enchanter")
		.effect("enchanting_potency", 0.03, "enchanting potency")
		.attribute("wisdom", 0.10)
		.at(10, "Soul Binder", "Your enchantments are stronger.", {"enchanting_potency": 0.05})
		.at(25, "Arcane Insight", "Magic comes easier.", {"max_magicka": 20.0})
		.at(50, "Runesmith", "Your runes bite deep.", {"enchanting_potency": 0.10})
		.at(75, "Spellweaver", "Magic hums in everything you touch.", {"enchanting_potency": 0.10, "spell_power": 0.03})
		.at(100, "Master Enchanter", "Your work rivals the ancients.", {"enchanting_potency": 0.25, "max_magicka": 30.0})
		.mastered({"enchanting_potency": 0.05}))
	_add(SkillData.new(&"tinkering", "Tinkering", "Crafting",
			"Miscellaneous crafting: tools, lockpicks, rings, amulets and clever packs.",
			"Making things at a workbench")
		.effect("carry_capacity", 3.0, "carry weight")
		.attribute("agility", 0.05).attribute("wisdom", 0.05)
		.at(10, "Handy", "Your picks are well made.", {"security_bonus": 0.03})
		.at(25, "Packrat", "Clever straps and pockets.", {"carry_capacity": 25.0})
		.at(50, "Clockwork Mind", "Mechanisms make sense to you.", {"security_bonus": 0.05})
		.at(75, "Gadgeteer", "Your pack is a marvel.", {"carry_capacity": 25.0})
		.at(100, "Master Tinker", "There is a tool for everything.", {"security_bonus": 0.10, "carry_capacity": 50.0})
		.mastered({"carry_capacity": 10.0}))
	_add(SkillData.new(&"cooking", "Cooking", "Crafting",
			"Turning raw food into hearty meals.",
			"Cooking at a cooking pot")
		.effect("cooking_potency", 0.03, "meal strength")
		.attribute("endurance", 0.05).attribute("charisma", 0.05)
		.at(10, "Home Cook", "A good meal keeps you going.", {"health_regen": 0.2})
		.at(25, "Hearty Meals", "Your meals are stronger.", {"cooking_potency": 0.10})
		.at(50, "Chef", "You are well fed.", {"max_health": 20.0})
		.at(75, "Feastmaster", "Your cooking is famous.", {"cooking_potency": 0.15})
		.at(100, "Master Chef", "Kings would hire you.", {"cooking_potency": 0.25, "stamina_regen_mult": 0.20})
		.mastered({"cooking_potency": 0.05})
		.weight(0.8))


static func _wilderness() -> void:
	_add(SkillData.new(&"survival", "Survival", "Wilderness",
			"Living off the land: cold, hunger and the long road.",
			"Spending time in the wilds, away from towns")
		.effect("hunger_mult", -0.01, "hunger and tiredness")
		.effect("resist_frost", 0.01, "frost resistance")
		.attribute("endurance", 0.15)
		.at(10, "Forager", "You pack light and carry more.", {"carry_capacity": 15.0})
		.at(25, "Hardy", "Weather hardly bothers you.", {"resist_frost": 0.15, "resist_fire": 0.10})
		.at(50, "Iron Stomach", "You can eat anything.", {"resist_poison": 0.20, "hunger_mult": -0.15})
		.at(75, "Pathfinder", "You know the land.", {"move_speed_mult": 0.03})
		.at(100, "One with the Wild", "The wild is your home.", {"max_health": 40.0, "stamina_regen_mult": 0.20, "resist_disease": 0.50})
		.mastered({"max_health": 10.0})
		.weight(0.5))
	_add(SkillData.new(&"fishing", "Fishing", "Wilderness",  # 1.30
			"Patience, a line and a good spot.",
			"Catching fish (use a Fishing Pole facing water)")
		.effect("fishing_bonus", 0.005, "bite speed and rare fish")
		.attribute("wisdom", 0.10)
		.at(10, "Steady Hands", "Fish bite sooner.", {"fishing_bonus": 0.05})
		.at(25, "Good Spots", "You find the fish where others don't.", {"fishing_bonus": 0.05})
		.at(50, "Angler", "Rare fish come to your line.", {"fishing_bonus": 0.10})
		.at(75, "Old Salt", "You land two where others land one.", {"fishing_bonus": 0.10})
		.at(100, "Master Angler", "The legends of the deep rise for you.", {"fishing_bonus": 0.15}, true)
		.mastered({"fishing_bonus": 0.03})
		.weight(0.5))
	_add(SkillData.new(&"hunting", "Hunting", "Wilderness",
			"Tracking and killing beasts.",
			"Killing beasts and monsters of the wild")
		.effect("bane_beast", 0.02, "damage to beasts")
		.attribute("agility", 0.05).attribute("stealth", 0.10)
		.at(10, "Tracker", "You move quietly in the wild.", {"noise_mult": -0.05})
		.at(25, "Trapper", "You know where beasts are weak.", {"crit_chance": 0.02})
		.at(50, "Beast Slayer", "Beasts fall before you.", {"bane_beast": 0.15})
		.at(75, "Apex Predator", "You are the hunter, they the prey.", {"bane_beast": 0.15, "crit_mult": 0.10})
		.at(100, "Master Hunter", "No beast escapes you.", {"bane_beast": 0.25, "crit_chance": 0.03})
		.mastered({"bane_beast": 0.05})
		.rate(1.5).weight(0.6))
	_add(SkillData.new(&"herbalism", "Herbalism", "Wilderness",
			"Finding and picking plants, herbs and mushrooms.",
			"Picking herbs")
		.effect("harvest_bonus", 0.02, "extra herbs")
		.attribute("wisdom", 0.05)
		.at(10, "Green Thumb", "You pick more from each plant.", {"harvest_bonus": 0.10})
		.at(25, "Herb Lore", "Your potions are stronger.", {"alchemy_potency": 0.05})
		.at(50, "Bountiful", "Plants give you all they have.", {"harvest_bonus": 0.15})
		.at(75, "Wild Healer", "You know which leaves heal.", {"potion_mult": 0.10})
		.at(100, "Master Herbalist", "The forest feeds you.", {"harvest_bonus": 0.25, "alchemy_potency": 0.10})
		.mastered({"harvest_bonus": 0.05})
		.rate(1.5).weight(0.5))
	_add(SkillData.new(&"mining", "Mining", "Wilderness",
			"Swinging a pickaxe at veins of ore.",
			"Mining ore with a pickaxe")
		.effect("mining_bonus", 0.02, "extra ore")
		.attribute("strength", 0.10).attribute("endurance", 0.05)
		.at(10, "Prospector", "You get more ore from each vein.", {"mining_bonus": 0.10})
		.at(25, "Strong Arms", "Swinging a pick builds muscle.", {"carry_capacity": 20.0, "strength": 3.0})
		.at(50, "Deep Veins", "You find the richest seams.", {"mining_bonus": 0.15})
		.at(75, "Gem Cutter", "Gems hide in the rock for you.", {"gem_find": 0.08})
		.at(100, "Master Miner", "Mountains open for you.", {"mining_bonus": 0.25, "gem_find": 0.07})
		.mastered({"mining_bonus": 0.05})
		.rate(1.5).weight(0.5))
	_add(SkillData.new(&"farming", "Farming", "Wilderness",
			"Planting and harvesting crops in planters.",
			"Planting and harvesting crops")
		.effect("farming_bonus", 0.03, "bigger harvests")
		.attribute("endurance", 0.05).attribute("strength", 0.05)
		.at(10, "Green Fields", "Your harvests are bigger.", {"farming_bonus": 0.20})
		.at(25, "Fast Growth", "Your crops grow faster.", {"crop_growth": 0.15})
		.at(50, "Harvest Moon", "Your fields overflow.", {"farming_bonus": 0.30})
		.at(75, "Fertile Soil", "Anything grows for you.", {"crop_growth": 0.25})
		.at(100, "Master Farmer", "Your fields feed a city.", {"farming_bonus": 0.50, "crop_growth": 0.25})
		.mastered({"farming_bonus": 0.10})
		.rate(3.0).weight(0.4))
	_add(SkillData.new(&"medicine", "Medicine", "Wilderness",
			"Treating wounds with potions, poultices and food.",
			"Healing yourself with potions and food")
		.effect("potion_mult", 0.01, "healing from potions and food")
		.attribute("wisdom", 0.05).attribute("endurance", 0.05)
		.at(10, "Field Dressing", "Your wounds close faster.", {"health_regen": 0.2})
		.at(25, "Physician", "Potions do more for you.", {"potion_mult": 0.10})
		.at(50, "Antidote", "Poison and sickness pass quickly.", {"resist_poison": 0.20, "resist_disease": 0.25})
		.at(75, "Surgeon", "You patch yourself up in moments.", {"potion_mult": 0.15})
		.at(100, "Master Healer", "Death has to work hard to take you.", {"potion_mult": 0.25, "health_regen": 1.0})
		.mastered({"potion_mult": 0.03})
		.weight(0.5))


static func _add(def: SkillData) -> void:
	_skills.append(def)
	_by_id[def.id] = def
