class_name Classes
extends RefCounted
## Character classes, the quiz that picks one (Daggerfall style), the advantages and disadvantages
## you can take, and the birthsigns. All tables; CharacterSetup applies the choices to the player.
##
## Class: 5 major skills (+10 levels each) and 4 minor ones (+5), starting gear and spells.
## Advantages cost points and disadvantages give them back; the balance changes how fast you level
## (the "dagger" of Daggerfall): more advantages than drawbacks = slower leveling.

const W := "res://scripts/Resources/Weapons/"
const A := "res://scripts/Resources/Armor/"
const R := "res://scripts/Resources/"
const C := "res://scripts/Resources/Consumables/"
const B := "res://scripts/Resources/Ranged/"

const LIST := {
	"warrior": {"name": "Warrior", "desc": "A soldier who trusts steel and plate.",
		"major": ["one_handed", "two_handed", "block", "heavy_armor", "athletics"], "minor": ["smithing", "archery", "restoration", "speech"],
		"gear": [[R + "iron_sword.tres", 1], [R + "iron_shield.tres", 1], [R + "iron_chestplate.tres", 1], [A + "iron_helmet.tres", 1], [A + "iron_greaves.tres", 1], [C + "health_potion.tres", 2]], "spells": []},
	"barbarian": {"name": "Barbarian", "desc": "A wild fighter from the edges of the world, with a greatsword and furs.",
		"major": ["two_handed", "light_armor", "athletics", "block", "smithing"], "minor": ["archery", "sneak", "cooking", "alchemy"],
		"gear": [[R + "steel_greatsword.tres", 1], [A + "hide_cuirass.tres", 1], [A + "hide_boots.tres", 1], [C + "roast_meat.tres", 3]], "spells": []},
	"knight": {"name": "Knight", "desc": "Sworn to an order: mace, shield, heavy armor and a little healing.",
		"major": ["one_handed", "heavy_armor", "block", "restoration", "speech"], "minor": ["two_handed", "smithing", "athletics", "enchanting"],
		"gear": [[W + "iron_mace.tres", 1], [R + "iron_shield.tres", 1], [R + "iron_chestplate.tres", 1], [A + "iron_helmet.tres", 1]], "spells": ["healing_hands"]},
	"spellsword": {"name": "Spellsword", "desc": "A swordsman who backs the blade with spells.",
		"major": ["one_handed", "destruction", "restoration", "light_armor", "block"], "minor": ["alteration", "athletics", "enchanting", "smithing"],
		"gear": [[R + "iron_sword.tres", 1], [A + "leather_cuirass.tres", 1], [C + "magicka_potion.tres", 2]], "spells": ["firebolt", "oakflesh"]},
	"battlemage": {"name": "Battlemage", "desc": "War wizard: destruction and conjuration in heavy armor.",
		"major": ["destruction", "conjuration", "heavy_armor", "two_handed", "alteration"], "minor": ["restoration", "enchanting", "block", "athletics"],
		"gear": [[R + "iron_warhammer.tres", 1], [R + "iron_chestplate.tres", 1], [C + "magicka_potion.tres", 3]], "spells": ["firebolt", "summon_wolf_spell", "oakflesh"]},
	"mage": {"name": "Mage", "desc": "A scholar of every school of magic.",
		"major": ["destruction", "alteration", "conjuration", "mysticism", "enchanting"], "minor": ["restoration", "illusion", "alchemy", "speech"],
		"gear": [[R + "iron_dagger.tres", 1], [C + "magicka_potion.tres", 4], ["res://scripts/Resources/SoulGems/petty_soul_gem.tres", 2]],
		"spells": ["firebolt", "frostbite", "sparks", "candlelight", "summon_wolf_spell", "soul_trap_spell"]},
	"healer": {"name": "Healer", "desc": "A temple healer who mends wounds and brews cures.",
		"major": ["restoration", "alchemy", "illusion", "speech", "alteration"], "minor": ["one_handed", "mysticism", "cooking", "light_armor"],
		"gear": [[W + "iron_mace.tres", 1], [C + "health_potion.tres", 3], ["res://scripts/Resources/Ingredients/lavender.tres", 4], ["res://scripts/Resources/Ingredients/swamp_lily.tres", 4]],
		"spells": ["healing_hands", "fast_healing", "calm_spell", "cure_poison_spell"]},
	"nightblade": {"name": "Nightblade", "desc": "A spellcaster of the shadows: illusion, mysticism and a short blade.",
		"major": ["illusion", "mysticism", "sneak", "one_handed", "light_armor"], "minor": ["destruction", "alchemy", "security", "athletics"],
		"gear": [[R + "iron_dagger.tres", 2], [A + "leather_cuirass.tres", 1], [R + "Misc/lockpick.tres", 5]], "spells": ["muffle_spell", "fear_spell", "absorb_health_spell"]},
	"thief": {"name": "Thief", "desc": "Light fingers, soft steps and a nose for locked doors.",
		"major": ["sneak", "security", "speech", "light_armor", "one_handed"], "minor": ["archery", "athletics", "alchemy", "illusion"],
		"gear": [[R + "iron_dagger.tres", 2], [A + "leather_cuirass.tres", 1], [A + "leather_boots.tres", 1], [R + "Misc/lockpick.tres", 15]], "spells": []},
	"assassin": {"name": "Assassin", "desc": "Daggers, poison and a bow from the dark.",
		"major": ["sneak", "one_handed", "alchemy", "archery", "light_armor"], "minor": ["security", "athletics", "illusion", "speech"],
		"gear": [[R + "iron_dagger.tres", 2], [B + "hunting_bow.tres", 1], [B + "iron_arrow.tres", 30], [A + "leather_cuirass.tres", 1], ["res://scripts/Resources/Ingredients/nightshade.tres", 3], ["res://scripts/Resources/Ingredients/venom_sac.tres", 2]], "spells": []},
	"ranger": {"name": "Ranger", "desc": "Hunter and scout: bow, short blade, leather and the wild.",
		"major": ["archery", "light_armor", "sneak", "one_handed", "athletics"], "minor": ["alchemy", "cooking", "restoration", "smithing"],
		"gear": [[B + "hunting_bow.tres", 1], [B + "iron_arrow.tres", 50], [W + "iron_waraxe.tres", 1], [A + "hide_cuirass.tres", 1], [A + "hide_boots.tres", 1]], "spells": []},
	"crafter": {"name": "Artisan", "desc": "A smith, alchemist and cook who sells what they make.",
		"major": ["smithing", "alchemy", "enchanting", "cooking", "tinkering"], "minor": ["speech", "one_handed", "light_armor", "security"],
		"gear": [[W + "iron_mace.tres", 1], ["res://scripts/Resources/Materials/pickaxe.tres", 1], ["res://scripts/Resources/Materials/iron_ingot.tres", 6], ["res://scripts/Resources/Materials/leather_strips.tres", 4]], "spells": []},
}

## The quiz. Each answer leans warrior (w), mage (m) or thief (t). The two strongest leanings pick the class.
const QUIZ := [
	["A stranger draws steel on you in an alley. You:", ["Draw yours and meet him head on.", "Speak a word of power and freeze him where he stands.", "Slip into the shadows and come at him from behind."]],
	["Your village is short of food in a hard winter. You:", ["Hunt the bear that has been raiding the stores.", "Study the old texts for a way to make the soil yield.", "Lift a few sacks from the rich lord's granary."]],
	["A locked chest lies in an old ruin. You:", ["Smash it open.", "Cast a spell to open it.", "Pick the lock without a sound."]],
	["Your hero as a child was:", ["The champion of the arena.", "The court wizard who saw the future.", "The thief who stole the Emperor's crown."]],
	["In a fight you most value:", ["Strong armor and a heavy blow.", "Distance, and the right spell at the right time.", "Never being seen at all."]],
	["A merchant cheats you. You:", ["Make him regret it in public.", "Curse his goods to rot on the shelf.", "Help yourself to his strongbox tonight."]],
	["The guild you would join first:", ["The Fighters Guild.", "The Mages Guild.", "The Thieves Guild."]],
	["You find a strange old book. You:", ["Use it to prop up the table.", "Read it cover to cover by candlelight.", "Sell it to the highest bidder."]],
	["A troll blocks the bridge. You:", ["Fight it.", "Burn it.", "Sneak past it."]],
	["People should remember you as:", ["Brave.", "Wise.", "Clever."]],
]

const ADVANTAGES := {
	"athletic": {"name": "Athletic", "cost": 2, "desc": "+10% speed, +20 stamina", "stats": {"move_speed_mult": 0.1, "max_stamina": 20.0}},
	"rapid_healing": {"name": "Rapid Healing", "cost": 3, "desc": "Regain 0.5 health a second", "stats": {"health_regen": 0.5}},
	"increased_magery": {"name": "Increased Magery", "cost": 3, "desc": "+50 max magicka", "stats": {"max_magicka": 50.0}},
	"strong_back": {"name": "Strong Back", "cost": 2, "desc": "+60 carry weight", "stats": {"carry_capacity": 60.0}},
	"disease_immunity": {"name": "Immunity to Disease", "cost": 3, "desc": "Never catch a disease", "stats": {"resist_disease": 1.0}},
	"resist_fire": {"name": "Resistance to Fire", "cost": 2, "desc": "+40% fire resistance", "stats": {"resist_fire": 0.4}},
	"resist_frost": {"name": "Resistance to Frost", "cost": 2, "desc": "+40% frost resistance", "stats": {"resist_frost": 0.4}},
	"resist_shock": {"name": "Resistance to Shock", "cost": 2, "desc": "+40% shock resistance", "stats": {"resist_shock": 0.4}},
	"resist_poison": {"name": "Resistance to Poison", "cost": 1, "desc": "+40% poison resistance", "stats": {"resist_poison": 0.4}},
	"spell_absorption": {"name": "Spell Absorption", "cost": 4, "desc": "15% chance to soak up a hostile spell", "stats": {"spell_absorb": 0.15}},
	"bane_of_undead": {"name": "Bane of the Dead", "cost": 1, "desc": "+20% damage against undead", "stats": {"bane_undead": 0.2}},
	"bane_of_beasts": {"name": "Hunter's Eye", "cost": 1, "desc": "+20% damage against beasts", "stats": {"bane_beast": 0.2}},
	"iron_skin": {"name": "Iron Skin", "cost": 3, "desc": "+15 armor", "stats": {"armor": 15.0}},
	"quick_learner": {"name": "Quick Learner", "cost": 4, "desc": "Skills level 15% faster", "stats": {}, "xp": 0.15},
}
const DISADVANTAGES := {
	"frail": {"name": "Frail", "gain": 2, "desc": "-20 max health", "stats": {"max_health": -20.0}},
	"clumsy": {"name": "Clumsy", "gain": 1, "desc": "-8% speed", "stats": {"move_speed_mult": -0.08}},
	"weak_back": {"name": "Weak Back", "gain": 1, "desc": "-50 carry weight", "stats": {"carry_capacity": -50.0}},
	"weak_fire": {"name": "Critical Weakness to Fire", "gain": 2, "desc": "Fire does 50% more damage", "stats": {"resist_fire": -0.5}},
	"weak_frost": {"name": "Critical Weakness to Frost", "gain": 2, "desc": "Frost does 50% more damage", "stats": {"resist_frost": -0.5}},
	"weak_shock": {"name": "Critical Weakness to Shock", "gain": 2, "desc": "Shock does 50% more damage", "stats": {"resist_shock": -0.5}},
	"weak_magic": {"name": "Weakness to Magic", "gain": 3, "desc": "All harmful magic is 30% stronger on you", "stats": {"resist_magic": -0.3}},
	"slow_magicka": {"name": "Stunted Magicka", "gain": 2, "desc": "Magicka comes back half as fast", "stats": {"magicka_regen_pct": -0.5}},
	"forbid_heavy": {"name": "Forbidden: Heavy Armor", "gain": 2, "desc": "You can't wear heavy armor", "stats": {}, "forbid": "heavy_armor"},
	"forbid_two_handed": {"name": "Forbidden: Two-Handed Weapons", "gain": 2, "desc": "You can't wield two-handed weapons", "stats": {}, "forbid": "two_handed"},
	"forbid_shields": {"name": "Forbidden: Shields", "gain": 1, "desc": "You can't use a shield", "stats": {}, "forbid": "shield"},
	"phobia_undead": {"name": "Fear of the Dead", "gain": 1, "desc": "-20% damage against undead", "stats": {"bane_undead": -0.2}},
	"sun_sick": {"name": "Sun Sickness", "gain": 2, "desc": "Stamina comes back half as fast in daylight", "stats": {}, "sun_sick": true},
	"slow_learner": {"name": "Slow Learner", "gain": 3, "desc": "Skills level 15% slower", "stats": {}, "xp": -0.15},
}
const SIGNS := {
	"sword": {"name": "The Sword", "desc": "+10 strength, +10 endurance", "stats": {"strength": 10.0, "endurance": 10.0}},
	"staff": {"name": "The Staff", "desc": "+40 max magicka", "stats": {"max_magicka": 40.0}},
	"shadow": {"name": "The Shadow", "desc": "+10 stealth, +15% sneak attack damage", "stats": {"stealth": 10.0, "sneak_attack_bonus": 0.15}},
	"hearth": {"name": "The Hearth", "desc": "Health and stamina come back faster", "stats": {"health_regen": 0.3, "stamina_regen_mult": 0.25}},
	"wind": {"name": "The Wind", "desc": "+8% speed, +5 agility", "stats": {"move_speed_mult": 0.08, "agility": 5.0}},
	"tower": {"name": "The Tower", "desc": "+15% lockpicking, +10% better prices", "stats": {"security_bonus": 0.15, "buy_price_mult": -0.1}},
	"serpent": {"name": "The Serpent", "desc": "+25% poison resistance, +10% spell power", "stats": {"resist_poison": 0.25, "spell_power": 0.1}},
}


static func get_class_data(id: String) -> Dictionary:
	return LIST.get(id, LIST["warrior"])


## answers: one index (0 warrior, 1 mage, 2 thief) per question -> class id
static func class_from_quiz(answers: Array) -> String:
	var s := [0, 0, 0]
	for a in answers:
		s[clampi(int(a), 0, 2)] += 1
	var order := [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return s[a] > s[b])
	var top: int = order[0]
	var second: int = order[1]
	var pure: bool = s[top] >= 7
	match top:
		0:
			if pure:
				return "warrior"
			return "spellsword" if second == 1 else ("ranger" if s[second] >= 3 else "barbarian")
		1:
			if pure:
				return "mage"
			return "battlemage" if second == 0 else ("nightblade" if s[second] >= 3 else "healer")
		_:
			if pure:
				return "thief"
			return "assassin" if second == 0 else "nightblade"


## How fast this character levels: advantages slow it, disadvantages speed it up
static func xp_mult(advantages: Array, disadvantages: Array) -> float:
	var net := 0
	var extra := 0.0
	for a in advantages:
		var d: Dictionary = ADVANTAGES.get(a, {})
		net += int(d.get("cost", 0))
		extra += float(d.get("xp", 0.0))
	for a in disadvantages:
		var d: Dictionary = DISADVANTAGES.get(a, {})
		net -= int(d.get("gain", 0))
		extra += float(d.get("xp", 0.0))
	return clampf(1.0 - float(net) * 0.04 + extra, 0.5, 1.6)
