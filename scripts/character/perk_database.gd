class_name PerkDatabase
extends RefCounted
## Every perk and feat (Alpha 1.22), in one table. CharacterBuild buys them with points.
##
##   PERKS  bought with perk points (1 every player level). Grouped in eight trees. A perk can have
##          several ranks; rank r needs player level  level + (r - 1) * step . Some need a skill
##          level or another perk first. A few (the "Paragon" ones) have no rank limit, so there
##          is always something to spend points on.
##   FEATS  bought with feat points, given at the big player-level milestones (FEAT_LEVELS, then
##          every 25 levels forever). Feats are the strong, build-defining choices; some have a
##          price (Juggernaut is slower, Glass Cannon is frail).
##
## A perk: {id, name, tree, desc, stats (per rank), ranks, level, step, skill, skill_level, requires,
##          feat}. ranks = 0 means no limit.

const TREES: Array[String] = ["Warrior", "Guardian", "Marksman", "Spellcaster", "Shadow", "Wanderer", "Artisan", "Leader"]
## Player levels that give a feat point; past the last one, every FEAT_EVERY levels
const FEAT_LEVELS: Array[int] = [10, 25, 50, 75, 100]
const FEAT_EVERY := 25
const UNLIMITED := 0

static var _list: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	_ensure()
	return _list


static func get_perk(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func perks_in(tree: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in all():
		if not bool(p["feat"]) and p["tree"] == tree:
			out.append(p)
	return out


static func feats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in all():
		if bool(p["feat"]):
			out.append(p)
	return out


## Is this player level a feat milestone? (10, 25, 50, 75, 100, 125, 150, ...)
static func is_feat_level(level: int) -> bool:
	if FEAT_LEVELS.has(level):
		return true
	var last: int = FEAT_LEVELS[FEAT_LEVELS.size() - 1]
	return level > last and (level - last) % FEAT_EVERY == 0


## Feat points earned by the time you reach this level
static func feats_by_level(level: int) -> int:
	var n := 0
	for l in FEAT_LEVELS:
		if level >= l:
			n += 1
	var last: int = FEAT_LEVELS[FEAT_LEVELS.size() - 1]
	if level > last:
		n += (level - last) / FEAT_EVERY
	return n


## The player level rank r (1 = first) of this perk needs
static func level_for_rank(p: Dictionary, rank: int) -> int:
	return int(p["level"]) + maxi(rank - 1, 0) * int(p["step"])


## "+5% damage, +20 max health"
static func describe(p: Dictionary, ranks: int = 1) -> String:
	var scaled := {}
	for k in p["stats"]:
		scaled[k] = float(p["stats"][k]) * maxi(ranks, 1)
	var t := SkillData.describe_stats(scaled)
	return t if t != "" else String(p["desc"])


# ---------------------------------------------------------------- the table

static func _ensure() -> void:
	if not _list.is_empty():
		return
	_warrior()
	_guardian()
	_marksman()
	_spellcaster()
	_shadow()
	_wanderer()
	_artisan()
	_leader()
	_feats()


static func _p(id: String, name: String, tree: String, desc: String, stats: Dictionary, ranks: int = 1, level: int = 1,
		step: int = 10, requires: Array = [], skill: String = "", skill_level: int = 0, feat: bool = false) -> void:
	var d := {"id": id, "name": name, "tree": tree, "desc": desc, "stats": stats, "ranks": ranks, "level": level, "step": step,
		"requires": requires, "skill": skill, "skill_level": skill_level, "feat": feat}
	_list.append(d)
	_by_id[id] = d


static func _warrior() -> void:
	var t := "Warrior"
	_p("w_brawn", "Brawn", t, "Every weapon hits harder.", {"damage_pct": 0.05}, 3, 2, 8)
	_p("w_battle_hardened", "Battle Hardened", t, "Years of fighting have toughened you.", {"max_health": 20.0}, 3, 3, 10)
	_p("w_second_wind", "Second Wind", t, "Swinging a weapon tires you less.", {"attack_cost_mult": -0.07}, 2, 6, 12)
	_p("w_power_strikes", "Power Strikes", t, "Heavy attacks hit harder.", {"power_attack_pct": 0.15}, 2, 5, 15, ["w_brawn"])
	_p("w_precision", "Precision", t, "You strike where it hurts.", {"crit_chance": 0.02}, 3, 10, 10)
	_p("w_brutal", "Brutal Criticals", t, "Critical hits do more damage.", {"crit_mult": 0.15}, 2, 20, 15, ["w_precision"])
	_p("w_shockwave", "Shockwave", t, "Your blows stagger foes sooner.", {"poise_bonus": 0.15}, 2, 15, 15)
	_p("w_long_arms", "Long Arms", t, "Your reach is a little longer.", {"reach_bonus": 0.15}, 1, 20)
	_p("w_bloodlust", "Bloodlust", t, "You finish off the wounded: more damage to foes below 30% health.", {"execute_bonus": 0.15}, 2, 25, 15)
	_p("w_armor_breaker", "Armor Breaker", t, "Your weapons ignore part of the foe's armor.", {"armor_pen": 0.10}, 2, 30, 20)
	_p("w_vampiric_steel", "Vampiric Steel", t, "A little of every wound you deal heals you.", {"life_leech": 0.02}, 2, 35, 20, ["w_bloodlust"])
	_p("w_brawler", "Brawler", t, "Your fists are dangerous.", {"unarmed_damage": 6.0}, 3, 5, 10, [], "hand_to_hand", 10)
	_p("w_warlords_might", "Warlord's Might", t, "The strength of a seasoned general.", {"damage_pct": 0.10, "crit_chance": 0.03}, 1, 60, 10, ["w_power_strikes"])
	_p("w_titans_grip", "Titan's Grip", t, "Weapons feel weightless in your hands.", {"damage_pct": 0.15, "power_attack_pct": 0.20}, 1, 90, 10, ["w_warlords_might"])
	_p("w_godslayer", "Godslayer", t, "Even gods would fear your blade.", {"damage_pct": 0.25, "crit_mult": 0.25}, 1, 150, 10, ["w_titans_grip"])
	_p("w_paragon", "Paragon of War", t, "No limit to how many times you can take this.", {"damage_pct": 0.02, "max_health": 5.0}, UNLIMITED, 50, 0, ["w_brawn"])


static func _guardian() -> void:
	var t := "Guardian"
	_p("g_toughness", "Toughness", t, "You can take a beating.", {"max_health": 15.0}, 5, 1, 8)
	_p("g_armor_training", "Armor Training", t, "You get more from the armor you wear.", {"armor_pct": 0.05}, 3, 4, 10)
	_p("g_shield_wall", "Shield Wall", t, "Your blocks stop more.", {"block_strength": 0.05}, 2, 6, 12)
	_p("g_iron_guard", "Iron Guard", t, "Blocking tires you less.", {"block_cost_mult": -0.10}, 2, 10, 12, ["g_shield_wall"])
	_p("g_regeneration", "Regeneration", t, "Your wounds close on their own.", {"health_regen": 0.3}, 3, 12, 12)
	_p("g_resolute", "Resolute", t, "You shrug off part of every blow.", {"damage_reduction": 0.03}, 3, 15, 15, ["g_toughness"])
	_p("g_fireproof", "Fireproof", t, "Fire bites you less.", {"resist_fire": 0.10}, 3, 8, 10)
	_p("g_frostbound", "Frostbound", t, "Frost bites you less.", {"resist_frost": 0.10}, 3, 8, 10)
	_p("g_grounded", "Grounded", t, "Lightning bites you less.", {"resist_shock": 0.10}, 3, 8, 10)
	_p("g_antivenom", "Antivenom", t, "Poison does less to you.", {"resist_poison": 0.15}, 2, 5, 10)
	_p("g_spell_ward", "Spell Ward", t, "Hostile magic is weaker on you.", {"resist_magic": 0.05}, 3, 20, 15)
	_p("g_colossus", "Colossus", t, "A mountain of a warrior.", {"max_health": 100.0, "armor_pct": 0.10}, 1, 70, 10, ["g_resolute"])
	_p("g_undying", "Undying", t, "Death keeps missing you.", {"damage_reduction": 0.08, "health_regen": 1.5}, 1, 120, 10, ["g_colossus"])
	_p("g_paragon", "Paragon of Iron", t, "No limit to how many times you can take this.", {"max_health": 10.0, "armor": 2.0}, UNLIMITED, 50, 0, ["g_toughness"])


static func _marksman() -> void:
	var t := "Marksman"
	_p("m_overdraw", "Overdraw", t, "Bows hit harder.", {"bow_damage": 0.10}, 3, 3, 10)
	_p("m_eagle_eye", "Eagle Eye", t, "You spot the weak point.", {"crit_chance": 0.03}, 2, 12, 15, ["m_overdraw"])
	_p("m_hunters_discipline", "Hunter's Discipline", t, "You know how beasts die.", {"bane_beast": 0.10}, 2, 6, 15)
	_p("m_ranger", "Ranger", t, "You move fast through any country.", {"move_speed_mult": 0.03}, 1, 18)
	_p("m_piercing", "Piercing Arrows", t, "Arrows find the gaps in armor.", {"armor_pen": 0.10}, 1, 25, 10, ["m_overdraw"])
	_p("m_sniper", "Sniper", t, "Arrows from far away kill.", {"bow_damage": 0.20, "crit_mult": 0.20}, 1, 40, 10, ["m_eagle_eye"])
	_p("m_arrow_storm", "Arrow Storm", t, "The sky darkens with your arrows.", {"bow_damage": 0.30, "crit_chance": 0.05}, 1, 100, 10, ["m_sniper"])
	_p("m_paragon", "Paragon of the Bow", t, "No limit to how many times you can take this.", {"bow_damage": 0.03}, UNLIMITED, 50, 0, ["m_overdraw"])


static func _spellcaster() -> void:
	var t := "Spellcaster"
	_p("s_reserves", "Arcane Reserves", t, "A deeper well of magicka.", {"max_magicka": 20.0}, 5, 1, 8)
	_p("s_flow", "Arcane Flow", t, "Magicka comes back faster.", {"magicka_regen_pct": 0.10}, 3, 5, 10)
	_p("s_spell_mastery", "Spell Mastery", t, "All your spells are stronger.", {"spell_power": 0.05}, 4, 8, 10)
	_p("s_efficient", "Efficient Casting", t, "All spells cost less.", {"magicka_cost_mult": -0.05}, 3, 10, 12)
	_p("s_elementalist", "Elementalist", t, "Destruction spells are stronger.", {"power_destruction": 0.10}, 2, 15, 15, [], "destruction", 20)
	_p("s_healers_gift", "Healer's Gift", t, "Restoration spells are stronger.", {"power_restoration": 0.10}, 2, 15, 15, [], "restoration", 20)
	_p("s_stability", "Stability", t, "Alteration spells are stronger.", {"power_alteration": 0.10}, 2, 15, 15, [], "alteration", 20)
	_p("s_dark_pact", "Dark Pact", t, "Conjured allies are stronger.", {"power_conjuration": 0.10, "follower_health": 0.10}, 2, 15, 15, [], "conjuration", 20)
	_p("s_mesmerist", "Mesmerist", t, "Illusion spells are stronger.", {"power_illusion": 0.10}, 2, 15, 15, [], "illusion", 20)
	_p("s_mystic", "Mystic", t, "Mysticism spells are stronger.", {"power_mysticism": 0.10}, 2, 15, 15, [], "mysticism", 20)
	_p("s_absorption", "Atronach's Blood", t, "You sometimes drink in hostile spells.", {"spell_absorb": 0.05}, 2, 30, 15)
	_p("s_mirror_ward", "Mirror Ward", t, "Hostile spells sometimes bounce back.", {"reflect": 0.05}, 2, 35, 15, ["s_absorption"])
	_p("s_archmage", "Archmage", t, "The power of a guild master.", {"spell_power": 0.15, "max_magicka": 100.0, "magicka_cost_mult": -0.10}, 1, 80, 10, ["s_spell_mastery"])
	_p("s_ascended_mind", "Ascended Mind", t, "Magic is as easy as breathing.", {"spell_power": 0.25, "magicka_regen_pct": 0.50}, 1, 140, 10, ["s_archmage"])
	_p("s_paragon", "Paragon of the Arcane", t, "No limit to how many times you can take this.", {"spell_power": 0.02, "max_magicka": 5.0}, UNLIMITED, 50, 0, ["s_reserves"])


static func _shadow() -> void:
	var t := "Shadow"
	_p("sh_stealthy", "Stealthy", t, "You make less noise.", {"noise_mult": -0.08}, 3, 2, 8)
	_p("sh_backstab", "Backstab", t, "Sneak attacks hit much harder.", {"sneak_attack_bonus": 0.25}, 3, 5, 10)
	_p("sh_light_fingers", "Light Fingers", t, "Locks give way more easily.", {"security_bonus": 0.05}, 3, 3, 10)
	_p("sh_silent_steps", "Silent Steps", t, "You sneak faster.", {"sneak_speed_mult": 0.10}, 2, 10, 12, ["sh_stealthy"])
	_p("sh_poisoner", "Poisoner", t, "Poisons do less to you and yours do more.", {"resist_poison": 0.10, "alchemy_potency": 0.05}, 2, 12, 12)
	_p("sh_cats_eyes", "Cat's Eyes", t, "You see in the dark.", {"night_eye": 1.0}, 1, 20)
	_p("sh_evasion", "Evasion", t, "You slip away from part of each blow.", {"damage_reduction": 0.03}, 2, 20, 15)
	_p("sh_assassins_blade", "Assassin's Blade", t, "One strike from the dark.", {"sneak_attack_bonus": 0.50, "crit_chance": 0.03}, 1, 30, 10, ["sh_backstab"])
	_p("sh_shadow_walker", "Shadow Walker", t, "You move like a ghost.", {"noise_mult": -0.15, "move_speed_mult": 0.03}, 1, 50, 10, ["sh_silent_steps"])
	_p("sh_master", "Master of Shadows", t, "The night itself hides you.", {"sneak_attack_bonus": 0.75, "noise_mult": -0.20}, 1, 90, 10, ["sh_assassins_blade"])
	_p("sh_paragon", "Paragon of Shadow", t, "No limit to how many times you can take this.", {"sneak_attack_bonus": 0.05, "noise_mult": -0.005}, UNLIMITED, 50, 0, ["sh_stealthy"])


static func _wanderer() -> void:
	var t := "Wanderer"
	_p("wa_fleet", "Fleet", t, "You move faster.", {"move_speed_mult": 0.03}, 3, 2, 10)
	_p("wa_spring_heel", "Spring Heel", t, "You jump higher.", {"jump_mult": 0.10}, 3, 3, 10)
	_p("wa_rolling_landing", "Rolling Landing", t, "Falls hurt less.", {"fall_resist": 0.15}, 2, 6, 10, ["wa_spring_heel"])
	_p("wa_pack_mule", "Pack Mule", t, "You carry more.", {"carry_capacity": 25.0}, 4, 1, 8)
	_p("wa_endurance_runner", "Endurance Runner", t, "More stamina.", {"max_stamina": 20.0}, 5, 1, 8)
	_p("wa_deep_breaths", "Deep Breaths", t, "Stamina comes back faster.", {"stamina_regen_mult": 0.10}, 3, 5, 10)
	_p("wa_strong_swimmer", "Strong Swimmer", t, "You swim faster and hold your breath longer.", {"swim_speed_mult": 0.15, "breath_mult": 0.50}, 1, 8)
	_p("wa_born_in_saddle", "Born in the Saddle", t, "Your horse runs faster and tires less.", {"horse_speed_mult": 0.10, "horse_stamina_mult": 0.25}, 1, 10)
	_p("wa_survivor", "Survivor", t, "Hunger and cold come slower.", {"hunger_mult": -0.10, "resist_frost": 0.10}, 2, 10, 15)
	_p("wa_forager", "Forager", t, "More from every plant.", {"harvest_bonus": 0.15}, 2, 4, 10)
	_p("wa_prospector", "Prospector", t, "More from every vein of ore.", {"mining_bonus": 0.15, "gem_find": 0.03}, 2, 4, 10)
	_p("wa_farmhand", "Farmhand", t, "Bigger, faster harvests.", {"farming_bonus": 0.25, "crop_growth": 0.10}, 1, 4)
	_p("wa_field_medic", "Field Medic", t, "Potions and food heal you more.", {"potion_mult": 0.10}, 2, 6, 12)
	_p("wa_windwalker", "Windwalker", t, "The wind carries you.", {"move_speed_mult": 0.06, "jump_mult": 0.20, "stamina_regen_mult": 0.20}, 1, 60, 10, ["wa_fleet"])
	_p("wa_eternal_traveler", "Eternal Traveler", t, "No road is too long.", {"move_speed_mult": 0.08, "carry_capacity": 100.0, "max_stamina": 100.0}, 1, 130, 10, ["wa_windwalker"])
	_p("wa_paragon", "Paragon of the Road", t, "No limit to how many times you can take this.", {"max_stamina": 10.0, "carry_capacity": 5.0}, UNLIMITED, 50, 0, ["wa_fleet"])


static func _artisan() -> void:
	var t := "Artisan"
	_p("a_forgemaster", "Forgemaster", t, "Your smithing is better.", {"smithing_potency": 0.10}, 3, 5, 10, [], "smithing", 10)
	_p("a_alchemist", "Alchemist", t, "Your potions are stronger.", {"alchemy_potency": 0.10}, 3, 5, 10, [], "alchemy", 10)
	_p("a_enchanter", "Enchanter", t, "Your enchantments are stronger.", {"enchanting_potency": 0.10}, 3, 5, 10, [], "enchanting", 10)
	_p("a_gourmet", "Gourmet", t, "Your meals are stronger.", {"cooking_potency": 0.10}, 2, 3, 10, [], "cooking", 5)
	_p("a_quick_study", "Quick Study", t, "All skills learn faster.", {"skill_xp_pct": 0.03}, 3, 10, 12)
	_p("a_master_artisan", "Master Artisan", t, "A master of every craft.", {"smithing_potency": 0.15, "alchemy_potency": 0.15, "enchanting_potency": 0.15}, 1, 75, 10, ["a_quick_study"])
	_p("a_polymath", "Polymath", t, "You learn anything quickly.", {"skill_xp_pct": 0.10}, 1, 110, 10, ["a_master_artisan"])
	_p("a_paragon", "Paragon of Craft", t, "No limit to how many times you can take this.", {"skill_xp_pct": 0.005}, UNLIMITED, 50, 0, ["a_quick_study"])


static func _leader() -> void:
	var t := "Leader"
	_p("l_haggler", "Haggler", t, "Better prices everywhere.", {"buy_price_mult": -0.04, "sell_price_mult": 0.04}, 3, 2, 10)
	_p("l_persuasion", "Persuasion", t, "People are easier to sway.", {"persuade_bonus": 0.05}, 3, 3, 10)
	_p("l_charming", "Charming", t, "You are easy to like.", {"charisma": 5.0}, 2, 5, 10)
	_p("l_commander", "Commander", t, "Your followers and summons hit harder.", {"follower_damage": 0.10}, 3, 8, 10)
	_p("l_bonds_of_war", "Bonds of War", t, "Your followers and summons are tougher.", {"follower_health": 0.15}, 2, 12, 12, ["l_commander"])
	_p("l_devout", "Devout", t, "Shrine blessings are stronger and sickness passes you by.", {"blessing_mult": 0.25, "resist_disease": 0.25}, 2, 6, 12)
	_p("l_undead_bane", "Bane of the Dead", t, "More damage against the undead.", {"bane_undead": 0.10}, 3, 10, 10)
	_p("l_noble_bearing", "Noble Bearing", t, "You carry yourself like a lord.", {"charisma": 15.0, "persuade_bonus": 0.10, "buy_price_mult": -0.05}, 1, 40, 10, ["l_charming"])
	_p("l_kings_authority", "King's Authority", t, "Armies follow you.", {"follower_damage": 0.30, "follower_health": 0.30, "persuade_bonus": 0.10}, 1, 100, 10, ["l_noble_bearing"])
	_p("l_paragon", "Paragon of Command", t, "No limit to how many times you can take this.", {"follower_damage": 0.02, "persuade_bonus": 0.005}, UNLIMITED, 50, 0, ["l_haggler"])


static func _f(id: String, name: String, level: int, desc: String, stats: Dictionary, ranks: int = 1) -> void:
	_p(id, name, "Feats", desc, stats, ranks, level, 0, [], "", 0, true)


static func _feats() -> void:
	# level 10
	_f("f_juggernaut", "Juggernaut", 10, "A wall of muscle and steel, if a little slower.", {"max_health": 60.0, "armor_pct": 0.10, "move_speed_mult": -0.03})
	_f("f_glass_cannon", "Glass Cannon", 10, "Hit far harder, but you are frail.", {"spell_power": 0.20, "damage_pct": 0.10, "max_health": -30.0})
	_f("f_duelist", "Duelist", 10, "Every cut finds its mark.", {"crit_chance": 0.05, "crit_mult": 0.25})
	_f("f_arcane_battery", "Arcane Battery", 10, "A vast store of magicka.", {"max_magicka": 80.0, "magicka_regen_pct": 0.25})
	_f("f_shadowborn", "Shadowborn", 10, "Born for the dark.", {"sneak_attack_bonus": 0.50, "noise_mult": -0.15})
	_f("f_pathfinder", "Pathfinder", 10, "Fast and sure-footed over any ground.", {"move_speed_mult": 0.08, "jump_mult": 0.20, "fall_resist": 0.20})
	_f("f_born_merchant", "Born Merchant", 10, "You could sell sand in the desert.", {"buy_price_mult": -0.10, "sell_price_mult": 0.10})
	_f("f_beastmaster", "Beastmaster", 10, "Beasts fear you; allies love you.", {"follower_damage": 0.25, "follower_health": 0.25, "bane_beast": 0.15})
	# level 25
	_f("f_berserker", "Berserker", 25, "Blood makes you stronger.", {"execute_bonus": 0.30, "life_leech": 0.03})
	_f("f_spellblade", "Spellblade", 25, "Steel and sorcery as one.", {"damage_pct": 0.10, "spell_power": 0.10})
	_f("f_bulwark", "Bulwark", 25, "An unbreakable guard.", {"block_strength": 0.15, "block_cost_mult": -0.30, "armor": 30.0})
	_f("f_prodigy", "Prodigy", 25, "You learn everything faster.", {"skill_xp_pct": 0.15})
	_f("f_stormcaller", "Stormcaller", 25, "Lightning answers you.", {"power_destruction": 0.25, "resist_shock": 0.30})
	_f("f_lifebinder", "Lifebinder", 25, "Life flows through you.", {"power_restoration": 0.25, "health_regen": 1.0})
	# level 50
	_f("f_titan", "Titan", 50, "Strength out of legend.", {"strength": 20.0, "endurance": 20.0, "max_health": 100.0})
	_f("f_archmage_insight", "Archmage's Insight", 50, "Spells come cheap and strong.", {"magicka_cost_mult": -0.20, "spell_power": 0.15})
	_f("f_phantom", "Phantom", 50, "Here, then gone.", {"damage_reduction": 0.10, "move_speed_mult": 0.05, "noise_mult": -0.20})
	_f("f_deadeye", "Deadeye", 50, "You never miss.", {"bow_damage": 0.30, "crit_chance": 0.05})
	_f("f_vanguard", "Vanguard", 50, "You break shield walls.", {"armor_pen": 0.25, "poise_bonus": 0.30})
	# level 75
	_f("f_undying", "Deathless", 75, "Your body refuses to die.", {"health_regen": 2.0, "damage_reduction": 0.08})
	_f("f_warlord", "Warlord", 75, "You and your warband are unstoppable.", {"damage_pct": 0.20, "follower_damage": 0.20})
	_f("f_avatar", "Avatar of Magic", 75, "Magic made flesh.", {"max_magicka": 200.0, "spell_power": 0.20})
	_f("f_reaper", "Reaper", 75, "You end fights.", {"crit_mult": 0.50, "execute_bonus": 0.25})
	# level 100
	_f("f_living_legend", "Living Legend", 100, "Songs are sung of you.", {"strength": 10.0, "agility": 10.0, "endurance": 10.0, "wisdom": 10.0,
		"stealth": 10.0, "charisma": 10.0, "max_health": 50.0, "max_magicka": 50.0, "max_stamina": 50.0})
	_f("f_dragonheart", "Dragonheart", 100, "The heart of a dragon beats in you.", {"resist_fire": 0.30, "resist_frost": 0.30, "resist_shock": 0.30, "damage_pct": 0.10})
	_f("f_the_unseen", "The Unseen", 100, "A whisper in the dark.", {"sneak_attack_bonus": 0.75, "sneak_speed_mult": 0.30, "noise_mult": -0.25})
	_f("f_eternal", "Eternal", 100, "Time is on your side.", {"skill_xp_pct": 0.20, "health_regen": 1.0})
	# the islands and beyond
	_f("f_demigod", "Demigod", 125, "Half mortal, half something more.", {"damage_pct": 0.25, "spell_power": 0.25, "damage_reduction": 0.05})
	_f("f_worldwalker", "Worldwalker", 125, "The whole world is your road.", {"move_speed_mult": 0.10, "jump_mult": 0.30, "carry_capacity": 150.0, "horse_speed_mult": 0.20})
	_f("f_godhand", "Godhand", 150, "Every strike could be the last.", {"crit_chance": 0.10, "crit_mult": 0.50})
	_f("f_aegis", "Aegis", 150, "Nothing gets through.", {"damage_reduction": 0.12, "armor_pct": 0.20})
	_f("f_ascended", "Ascended", 175, "You have outgrown mortal limits.", {"strength": 20.0, "agility": 20.0, "endurance": 20.0, "wisdom": 20.0,
		"stealth": 20.0, "charisma": 20.0})
	_f("f_mythic_hero", "Mythic Hero", 200, "The stuff of myth.", {"damage_pct": 0.30, "spell_power": 0.30, "max_health": 200.0})
	# always one more to take
	_f("f_paragon", "Paragon", 100, "Take it as often as you like.", {"damage_pct": 0.02, "spell_power": 0.02, "max_health": 10.0, "max_magicka": 10.0, "max_stamina": 10.0}, UNLIMITED)
