class_name SpellCatalog
extends RefCounted
## The premade spells: the ones you start with, the ones spell tomes teach and the ones enemy mages
## cast. Each has a rank (0 novice .. 4 master) that decides its tome's price and where it shows up.
## Spell tomes are item files made by tools/generate_stage10.gd: Resources/Books/tome_<spell id>.tres

const F := SpellData.Form
const TOME_DIR := "res://data/books/"
const RANK_NAMES := ["Novice", "Apprentice", "Adept", "Expert", "Master"]
## What a player starts the game knowing
const STARTING := ["flames", "healing"]

static var _spells: Dictionary = {}   # id -> SpellData
static var _rank: Dictionary = {}     # id -> int
static var _order: Array[String] = []


static func get_spell(id: String) -> SpellData:
	_ensure()
	var s: SpellData = _spells.get(id)
	return s.duplicate_spell() if s != null else null


static func has(id: String) -> bool:
	_ensure()
	return _spells.has(id)


static func rank_of(id: String) -> int:
	_ensure()
	return int(_rank.get(id, 0))


static func all_ids() -> Array[String]:
	_ensure()
	return _order


## Tome item for a spell (null if the file is missing)
static func get_tome(id: String) -> ItemData:
	var path := TOME_DIR + "tome_" + id + ".tres"
	return load(path) as ItemData if ResourceLoader.exists(path) else null


## Spells of a school up to a rank (merchants stock tomes from these)
static func ids_for(school: StringName, max_rank: int) -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id in _order:
		if rank_of(id) <= max_rank and (school == &"" or _spells[id].get_school() == school):
			out.append(id)
	return out


static func _ensure() -> void:
	if not _spells.is_empty():
		return
	# ---- Destruction
	_add(0, "flames", "Flames", F.SPRAY, [["fire_damage", 8, 0]])
	_add(0, "frostbite", "Frostbite", F.SPRAY, [["frost_damage", 7, 0]])
	_add(0, "sparks", "Sparks", F.SPRAY, [["shock_damage", 7, 0]])
	_add(1, "firebolt", "Firebolt", F.TARGET, [["fire_damage", 25, 0]])
	_add(1, "ice_spike", "Ice Spike", F.TARGET, [["frost_damage", 25, 0]])
	_add(1, "lightning_bolt", "Lightning Bolt", F.BEAM, [["shock_damage", 26, 0]])
	_add(1, "fire_rune", "Fire Rune", F.RUNE, [["fire_damage", 45, 0]], 4.0)
	_add(1, "wither", "Wither", F.TOUCH, [["damage_health", 30, 0]])
	_add(2, "fireball", "Fireball", F.TARGET, [["fire_damage", 40, 0]], 4.0)
	_add(2, "frost_rune", "Frost Rune", F.RUNE, [["frost_damage", 50, 0]], 4.0)
	_add(2, "lightning_rune", "Lightning Rune", F.RUNE, [["shock_damage", 50, 0]], 4.0)
	_add(2, "poison_cloud", "Poison Cloud", F.TARGET, [["poison_damage", 6, 8]], 4.0)
	_add(2, "flame_nova", "Flame Nova", F.NOVA, [["fire_damage", 35, 0]])
	_add(3, "ice_storm", "Ice Storm", F.SPRAY, [["frost_damage", 18, 0]])
	_add(3, "chain_lightning", "Thunderbolt", F.BEAM, [["shock_damage", 60, 0]], 2.0)
	_add(4, "incinerate", "Incinerate", F.TARGET, [["fire_damage", 80, 0], ["weakness_fire", 25, 10]], 3.0)
	_add(4, "blizzard", "Blizzard", F.NOVA, [["frost_damage", 15, 6], ["slow", 50, 6]], 9.0)

	# ---- Restoration
	_add(0, "healing", "Healing", F.SELF, [["restore_health", 30, 0]])
	_add(0, "rejuvenate", "Rejuvenate", F.SELF, [["restore_stamina", 40, 0]])
	_add(1, "healing_hands", "Healing Hands", F.TOUCH, [["restore_health", 40, 0]])
	_add(1, "resist_fire_spell", "Resist Fire", F.SELF, [["resist_fire", 40, 60]])
	_add(1, "resist_frost_spell", "Resist Frost", F.SELF, [["resist_frost", 40, 60]])
	_add(1, "resist_shock_spell", "Resist Shock", F.SELF, [["resist_shock", 40, 60]])
	_add(1, "cure_poison_spell", "Cure Poison", F.SELF, [["cure_poison", 0, 0]])
	_add(1, "cure_disease_spell", "Cure Disease", F.SELF, [["cure_disease", 0, 0]])
	_add(2, "fast_healing", "Fast Healing", F.SELF, [["restore_health", 70, 0]])
	_add(2, "heal_other", "Heal Other", F.TARGET, [["restore_health", 50, 0]])
	_add(2, "fortify_strength_spell", "Strength of the Bull", F.SELF, [["fortify_strength", 15, 120], ["feather", 50, 120]])
	_add(3, "close_wounds", "Close Wounds", F.SELF, [["restore_health", 140, 0]])
	_add(3, "battle_blessing", "Battle Blessing", F.SELF, [["fortify_attack", 20, 60], ["fortify_block", 15, 60]])
	_add(4, "grand_healing", "Grand Healing", F.NOVA, [["restore_health", 150, 0]])

	# ---- Alteration
	_add(0, "candlelight", "Candlelight", F.SELF, [["light", 10, 90]])
	_add(0, "oakflesh", "Oakflesh", F.SELF, [["shield", 20, 60]])
	_add(1, "feather_spell", "Feather", F.SELF, [["feather", 100, 120]])
	_add(1, "open_easy_lock", "Open Easy Lock", F.TOUCH, [["open_lock", 25, 0]])
	_add(1, "leap", "Leap", F.SELF, [["jump", 60, 60], ["slowfall", 0, 60]])
	_add(2, "stoneflesh", "Stoneflesh", F.SELF, [["shield", 40, 60]])
	_add(2, "haste_spell", "Haste", F.SELF, [["haste", 30, 30]])
	_add(2, "slow_spell", "Slow", F.TARGET, [["slow", 40, 10]])
	_add(2, "open_average_lock", "Open Average Lock", F.TOUCH, [["open_lock", 50, 0]])
	_add(3, "ironflesh", "Ironflesh", F.SELF, [["shield", 60, 60]])
	_add(3, "paralyze_spell", "Paralyze", F.TARGET, [["paralyze", 0, 5]])
	_add(3, "open_hard_lock", "Open Hard Lock", F.TOUCH, [["open_lock", 75, 0]])
	_add(4, "mass_paralysis", "Mass Paralysis", F.NOVA, [["paralyze", 0, 6]], 8.0)

	# ---- Conjuration
	_add(0, "summon_wolf_spell", "Conjure Wolf", F.SELF, [["summon_wolf", 0, 60]])
	_add(0, "bound_dagger_spell", "Bound Dagger", F.SELF, [["bound_dagger", 0, 120]])
	_add(1, "bound_sword_spell", "Bound Sword", F.SELF, [["bound_sword", 0, 120]])
	_add(1, "summon_skeleton_spell", "Raise Skeleton", F.SELF, [["summon_skeleton", 0, 60]])
	_add(1, "raise_zombie", "Raise Zombie", F.TARGET, [["reanimate", 10, 60]])
	_add(2, "summon_ember_spell", "Conjure Ember Spirit", F.SELF, [["summon_ember", 0, 60]])
	_add(2, "bound_waraxe_spell", "Bound War Axe", F.SELF, [["bound_waraxe", 0, 120]])
	_add(2, "revenant", "Revenant", F.TARGET, [["reanimate", 25, 60]])
	_add(3, "summon_frost_spell", "Conjure Frost Wraith", F.SELF, [["summon_frost", 0, 60]])
	_add(3, "bound_greatsword_spell", "Bound Greatsword", F.SELF, [["bound_greatsword", 0, 120]])
	_add(3, "summon_bear_spell", "Conjure Frost Bear", F.SELF, [["summon_bear", 0, 60]])
	_add(4, "summon_troll_spell", "Conjure Cave Troll", F.SELF, [["summon_troll", 0, 60]])
	_add(4, "dread_zombie", "Dread Zombie", F.TARGET, [["reanimate", 60, 60]])

	# ---- Illusion
	_add(0, "muffle_spell", "Muffle", F.SELF, [["muffle", 0, 60]])
	_add(0, "night_eye_spell", "Night Eye", F.SELF, [["night_eye", 0, 60]])
	_add(1, "calm_spell", "Calm", F.TARGET, [["calm", 10, 30]])
	_add(1, "fear_spell", "Fear", F.TARGET, [["fear", 10, 20]])
	_add(1, "fury", "Fury", F.TARGET, [["frenzy", 10, 30]])
	_add(1, "charm_spell", "Charm", F.TOUCH, [["charm", 20, 60]])
	_add(2, "pacify", "Pacify", F.TARGET, [["calm", 25, 30]])
	_add(2, "rout", "Rout", F.TARGET, [["fear", 25, 20]])
	_add(3, "invisibility_spell", "Invisibility", F.SELF, [["invisibility", 0, 30]])
	_add(3, "mayhem", "Mayhem", F.NOVA, [["frenzy", 30, 30]], 12.0)
	_add(4, "harmony", "Harmony", F.NOVA, [["calm", 60, 60]], 15.0)

	# ---- Mysticism
	_add(0, "detect_life_spell", "Detect Life", F.SELF, [["detect_life", 50, 30]])
	_add(0, "soul_trap_spell", "Soul Trap", F.TARGET, [["soul_trap", 0, 30]])
	_add(1, "telekinesis_spell", "Telekinesis", F.SELF, [["telekinesis", 0, 30]])
	_add(1, "absorb_health_spell", "Absorb Health", F.TOUCH, [["absorb_health", 20, 0]])
	_add(1, "mark_spell", "Mark", F.SELF, [["mark", 0, 0]])
	_add(1, "recall_spell", "Recall", F.SELF, [["recall", 0, 0]])
	_add(2, "dispel_spell", "Dispel", F.SELF, [["dispel", 50, 0]])
	_add(2, "drain_vitality", "Drain Vitality", F.TARGET, [["absorb_stamina", 30, 0], ["absorb_magicka", 20, 0]])
	_add(3, "spell_absorption_spell", "Spell Absorption", F.SELF, [["spell_absorption", 30, 60]])
	_add(3, "reflect_spell", "Reflect", F.SELF, [["reflect", 25, 60]])
	_add(4, "soul_harvest", "Soul Harvest", F.BEAM, [["absorb_health", 50, 0], ["soul_trap", 0, 30]])

	# ---- Vampire powers (learned by becoming a vampire, no tomes)
	_add(9, "vampiric_drain", "Vampiric Drain", F.TOUCH, [["absorb_health", 18, 0], ["absorb_stamina", 10, 0]])
	_add(9, "vampires_sight", "Vampire's Sight", F.SELF, [["night_eye", 0, 120]])
	_add(9, "mesmerize", "Mesmerize", F.NOVA, [["calm", 40, 30]], 10.0)
	_add(9, "embrace_of_shadows", "Embrace of Shadows", F.SELF, [["invisibility", 0, 60], ["night_eye", 0, 60]])

	# ---- Enemy-only spells (no tomes)
	_add(9, "e_firebolt", "Firebolt", F.TARGET, [["fire_damage", 1, 0]])
	_add(9, "e_icebolt", "Ice Spike", F.TARGET, [["frost_damage", 1, 0]])
	_add(9, "e_shock", "Lightning", F.BEAM, [["shock_damage", 1, 0]])
	_add(9, "e_drain", "Drain Life", F.TARGET, [["absorb_health", 1, 0]])
	_add(9, "e_heal", "Heal", F.SELF, [["restore_health", 1, 0]])
	_add(9, "e_ward", "Ward", F.SELF, [["shield", 1, 20]])


static func _add(rank: int, id: String, name: String, form: SpellData.Form, effects: Array, area: float = 0.0) -> void:
	var s := SpellData.make(id, name, form, effects, area)
	_spells[id] = s
	_rank[id] = rank
	_order.append(id)


## Tome ids that a learner may buy (rank <= 4)
static func tome_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id in _order:
		if rank_of(id) <= 4:
			out.append(id)
	return out
