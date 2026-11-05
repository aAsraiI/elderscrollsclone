class_name CharacterBuild
extends RefCounted
## The choices you make as you level (Alpha 1.22). Owned by Skills and saved inside its dictionary,
## so there is no extra node or save key.
##
## Every player level gives:
##   1 perk point       spend it on a perk (PerkDatabase, 8 trees)
##   1 attribute point  +ATTR_PER_POINT to an attribute you pick (Oblivion style)
##   1 vital point      +VITAL_PER_POINT to max health, magicka or stamina (Skyrim style)
## and the big milestone levels (10, 25, 50, 75, 100, then every 25) give a feat point too.
## Points are worked out from the player level, so they can never get out of step with it:
## what you have = what the level earned - what you spent.
##
## Everything is pushed into Stats as three sources: "build_perks", "build_attributes", "build_vitals".
## The Character screen (StatsUI, "Perks" and "Level Up" tabs) is where you spend them.

const ATTR_PER_POINT := 2.0
const VITAL_PER_POINT := 10.0
const VITALS := {"health": "max_health", "magicka": "max_magicka", "stamina": "max_stamina"}
## Gold per player level to undo every choice (perks, feats, attributes, vitals) and pick again
const RESPEC_GOLD_PER_LEVEL := 50
## 1.27: taking up a saved loadout at a shrine costs this much per level
const LOADOUT_GOLD_PER_LEVEL := 15
const LOADOUT_SLOTS := ["A", "B"]
const SHRINE_REACH := 5.0

var skills: Skills
## perk id -> rank
var owned: Dictionary = {}
## attribute -> points spent
var attr_spent: Dictionary = {}
## "health" / "magicka" / "stamina" -> points spent
var vitals: Dictionary = {}
## Extra perk points from quests, books and the like
var bonus_perk_points := 0
var respecs := 0
## 1.27: saved builds, "A" and "B": {"owned", "attr", "vitals"}
var loadouts: Dictionary = {}


func _init(p_skills: Skills = null) -> void:
	skills = p_skills


func _level() -> int:
	return skills.get_player_level() if skills != null else 1


# ---------------------------------------------------------------- points

func perk_points_earned() -> int:
	return (_level() - 1) + bonus_perk_points


func perk_points_spent() -> int:
	var n := 0
	for id in owned:
		if not bool(PerkDatabase.get_perk(id).get("feat", false)) and not PerkDatabase.SHIFT_TREES.has(String(PerkDatabase.get_perk(id).get("tree", ""))):
			n += int(owned[id])
	return n


func perk_points() -> int:
	return perk_points_earned() - perk_points_spent()


func feat_points() -> int:
	var spent := 0
	for id in owned:
		if bool(PerkDatabase.get_perk(id).get("feat", false)):
			spent += int(owned[id])
	return PerkDatabase.feats_by_level(_level()) - spent


func attribute_points() -> int:
	var spent := 0
	for a in attr_spent:
		spent += int(attr_spent[a])
	return (_level() - 1) - spent


func vital_points() -> int:
	var spent := 0
	for v in vitals:
		spent += int(vitals[v])
	return (_level() - 1) - spent


## Anything left to spend? (the Character screen shows a marker)
func has_unspent() -> bool:
	return perk_points() > 0 or feat_points() > 0 or attribute_points() > 0 or vital_points() > 0


func rank_of(id: String) -> int:
	return int(owned.get(id, 0))


# ---------------------------------------------------------------- perks

## "" when you can take the next rank of this perk, else why not
func why_not(id: String) -> String:
	var p := PerkDatabase.get_perk(id)
	if p.is_empty():
		return "Unknown perk"
	var rank := rank_of(id)
	var max_ranks := int(p["ranks"])
	if max_ranks != PerkDatabase.UNLIMITED and rank >= max_ranks:
		return "Already at its highest rank"
	var need := PerkDatabase.level_for_rank(p, rank + 1)
	if _level() < need:
		return "Needs player level %d" % need
	var sk := String(p["skill"])
	if sk != "" and skills != null and skills.get_level(StringName(sk)) < int(p["skill_level"]):
		var def := SkillDatabase.get_skill(StringName(sk))
		return "Needs %s %d" % [def.display_name if def != null else sk, int(p["skill_level"])]
	for r in p["requires"]:
		if rank_of(String(r)) <= 0:
			return "Needs the perk %s" % PerkDatabase.get_perk(String(r)).get("name", r)
	var shift := String(PerkDatabase.SHIFT_TREES.get(String(p["tree"]), ""))
	if shift != "":  # 1.28: the shapeshifters' trees are bought with blood
		if not cursed(shift):
			return "Only for a %s" % shift
		if shift_points(shift) <= 0:
			return "No blood points (%s)" % ("feed to earn them" if shift == "vampire" else "devour bodies in beast form to earn them")
		return ""
	if bool(p["feat"]):
		if feat_points() <= 0:
			return "No feat points (one at levels 10, 25, 50, 75, 100, then every 25)"
	elif perk_points() <= 0:
		return "No perk points (one every level)"
	return ""


func take(id: String) -> bool:
	if why_not(id) != "":
		return false
	owned[id] = rank_of(id) + 1
	apply()
	announce_synergies(skills.get_tree() if skills != null and skills.is_inside_tree() else null)  # 1.27
	return true


func spend_attribute(attr: String) -> bool:
	if not SkillDatabase.ATTRIBUTES.has(attr) or attribute_points() <= 0:
		return false
	attr_spent[attr] = int(attr_spent.get(attr, 0)) + 1
	apply()
	return true


func spend_vital(v: String) -> bool:
	if not VITALS.has(v) or vital_points() <= 0:
		return false
	vitals[v] = int(vitals.get(v, 0)) + 1
	apply()
	return true


func respec_cost() -> int:
	return RESPEC_GOLD_PER_LEVEL * _level()


## Undo every perk, feat, attribute and vital choice (the points come back). Pays from the inventory.
func respec(inventory: Inventory) -> String:
	var cost := respec_cost()
	if inventory != null and Currency.get_gold(inventory) < cost:
		return "You need %d gold" % cost
	if inventory != null:
		Currency.spend_gold(inventory, cost)
	owned.clear()
	attr_spent.clear()
	vitals.clear()
	respecs += 1
	apply()
	return ""


# ---------------------------------------------------------------- applying

## Everything the choices are worth right now, pushed into Stats
func apply() -> void:
	if skills == null or skills.stats == null:
		return
	var perks := {}
	for id in owned:
		var p := PerkDatabase.get_perk(id)
		if p.is_empty():
			continue
		var shift := String(PerkDatabase.SHIFT_TREES.get(String(p.get("tree", "")), ""))
		if shift != "" and not shift_active(shift):
			continue  # 1.28: a vampire's perks while a vampire, a werewolf's in beast form
		for k in p["stats"]:
			perks[k] = float(perks.get(k, 0.0)) + float(p["stats"][k]) * int(owned[id])
	for syn in synergies():  # 1.27: two perks from different trees give a hidden third
		for k in syn[4]:
			perks[k] = float(perks.get(k, 0.0)) + float(syn[4][k])
	_push("build_perks", perks)
	var attrs := {}
	for a in attr_spent:
		attrs[a] = float(attr_spent[a]) * ATTR_PER_POINT
	_push("build_attributes", attrs)
	var vit := {}
	for v in vitals:
		vit[VITALS[v]] = float(vitals[v]) * VITAL_PER_POINT
	_push("build_vitals", vit)


func _push(source: String, mods: Dictionary) -> void:
	if mods.is_empty():
		skills.stats.remove_modifiers(source)
	else:
		skills.stats.add_modifiers(source, mods)


# ---------------------------------------------------------------- 1.27: talent synergies

## [id, name, perk a, perk b, stats, what it does]: own both and the third is yours
const SYNERGIES := [
	["spellblade", "Spellblade", "w_brawn", "s_spell_mastery", {"damage_pct": 0.05, "spell_power": 0.05}, "Steel and spell: weapons and spells both a little stronger."],
	["shadow_archer", "Shadow Archer", "m_overdraw", "sh_backstab", {"bow_damage": 0.10, "sneak_attack_bonus": 0.15}, "Arrows from the dark hit harder."],
	["battlemage", "Battlemage", "g_armor_training", "s_reserves", {"max_magicka": 25.0, "armor_pct": 0.05}, "Armour and magicka both."],
	["juggernaut", "Juggernaut", "w_battle_hardened", "g_toughness", {"max_health": 30.0, "poise_bonus": 0.10}, "Hard to hurt, hard to stop."],
	["ranger_stride", "Ranger's Stride", "m_ranger", "wa_fleet", {"move_speed_mult": 0.04, "bow_damage": 0.05}, "Light on your feet with a bow in hand."],
	["poison_master", "Poison Master", "sh_poisoner", "a_alchemist", {"alchemy_potency": 0.10, "resist_poison": 0.10}, "Poisons that bite, and a body that shrugs them off."],
	["warlord", "Warlord", "w_precision", "l_commander", {"crit_chance": 0.02, "follower_damage": 0.10}, "You and yours strike true."],
	["holy_warrior", "Holy Warrior", "g_spell_ward", "l_devout", {"resist_magic": 0.05, "bane_undead": 0.10}, "Faith as armour against the dark."],
	["wandering_smith", "Wandering Smith", "a_forgemaster", "wa_pack_mule", {"carry_capacity": 25.0, "smithing_potency": 0.05}, "Carry your forge on your back."],
	["nightblade", "Nightblade", "sh_stealthy", "s_mesmerist", {"power_illusion": 0.10, "noise_mult": -0.05}, "Quiet steps and quieter minds."],
]


## The synergies you have
func synergies() -> Array:
	var out := []
	for syn in SYNERGIES:
		if rank_of(syn[2]) > 0 and rank_of(syn[3]) > 0:
			out.append(syn)
	return out


## Says so the first time each one is earned (CharacterBuild.take calls it)
func announce_synergies(tree: SceneTree) -> void:
	var known: Array = (WorldState.get_record("synergies").get("ids", []) as Array).duplicate()
	for syn in synergies():
		if not known.has(syn[0]):
			known.append(syn[0])
			Achievements.note("synergy")
			if tree != null:
				Notices.quest(tree, "Synergy", "%s: %s" % [syn[1], syn[5]])
				DialogueState.system_entry("Knowledge", "Synergy: %s. %s" % [syn[1], syn[5]], "")
	WorldState.set_record("synergies", {"ids": known})


# ---------------------------------------------------------------- 1.27: titles

## A name people call you by, from your build (level 10 and up)
const TITLES := {
	"Warrior": "the Bold", "Knight": "the Unbroken", "Mage": "Stormcaller", "Thief": "the Unseen", "Scout": "Swiftfoot",
	"Diplomat": "Silvertongue", "Artisan": "Steelhand", "Ranger": "the Wild", "Spellsword": "the Spellblade",
	"Assassin": "the Quiet Knife", "Skirmisher": "the Restless", "Warlord": "the Iron Voice", "Weaponsmith": "Forgeborn",
	"Hunter": "the Huntsman", "Battlemage": "Spellshield", "Sentinel": "the Watchful", "Vanguard": "the First Through",
	"Paladin": "the Righteous", "Armorer": "Ironclad", "Warden": "the Warden", "Nightblade": "Nightblade",
	"Windcaller": "Windcaller", "Sage": "the Wise", "Enchanter": "Runeweaver", "Druid": "Greenwarden", "Acrobat": "the Nimble",
	"Agent": "the Many-Faced", "Saboteur": "the Saboteur", "Stalker": "Shadowstalker", "Bard": "Songweaver",
	"Pilgrim": "the Pilgrim", "Wayfarer": "the Wayfarer", "Merchant": "Goldpurse", "Shepherd": "the Shepherd",
	"Homesteader": "Hearthkeeper", "Adventurer": "the Adventurer",
}
const TITLE_LEVEL := 10


static func title(sk: Skills) -> String:
	if sk == null or sk.get_player_level() < TITLE_LEVEL:
		return ""
	return String(TITLES.get(archetype(sk), ""))


# ---------------------------------------------------------------- what kind of hero

## Names for the two groups your best skills are in (Oblivion style class names)
const ARCHETYPES := {
	"Weapons": "Warrior", "Defense": "Knight", "Magic": "Mage", "Stealth": "Thief", "Movement": "Scout",
	"Social": "Diplomat", "Crafting": "Artisan", "Wilderness": "Ranger",
	"Weapons+Defense": "Knight", "Weapons+Magic": "Spellsword", "Weapons+Stealth": "Assassin",
	"Weapons+Movement": "Skirmisher", "Weapons+Social": "Warlord", "Weapons+Crafting": "Weaponsmith",
	"Weapons+Wilderness": "Hunter", "Defense+Magic": "Battlemage", "Defense+Stealth": "Sentinel",
	"Defense+Movement": "Vanguard", "Defense+Social": "Paladin", "Defense+Crafting": "Armorer",
	"Defense+Wilderness": "Warden", "Magic+Stealth": "Nightblade", "Magic+Movement": "Windcaller",
	"Magic+Social": "Sage", "Magic+Crafting": "Enchanter", "Magic+Wilderness": "Druid",
	"Stealth+Movement": "Acrobat", "Stealth+Social": "Agent", "Stealth+Crafting": "Saboteur",
	"Stealth+Wilderness": "Stalker", "Movement+Social": "Bard", "Movement+Crafting": "Pilgrim",
	"Movement+Wilderness": "Wayfarer", "Social+Crafting": "Merchant", "Social+Wilderness": "Shepherd",
	"Crafting+Wilderness": "Homesteader",
}


## The player's best skills, highest first: [[SkillData, level], ...]
static func top_skills(sk: Skills, count: int = 3) -> Array:
	var list: Array = []
	for def in SkillDatabase.get_all():
		list.append([def, sk.get_level(def.id)])
	list.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	return list.slice(0, count)


## "Spellsword" from your two strongest skill groups
static func archetype(sk: Skills) -> String:
	if sk == null:
		return "Adventurer"
	var by_group := {}
	for def in SkillDatabase.get_all():
		var lvl := sk.get_level(def.id) - SkillDatabase.START_LEVEL
		by_group[def.group] = float(by_group.get(def.group, 0.0)) + float(lvl * lvl)
	var groups: Array = by_group.keys()
	groups.sort_custom(func(a: String, b: String) -> bool: return float(by_group[a]) > float(by_group[b]))
	if groups.is_empty() or float(by_group[groups[0]]) <= 0.0:
		return "Adventurer"
	var first: String = groups[0]
	var second: String = groups[1] if groups.size() > 1 else first
	if float(by_group.get(second, 0.0)) < float(by_group[first]) * 0.35:
		return ARCHETYPES.get(first, "Adventurer")
	var a := SkillDatabase.GROUPS.find(first)
	var b := SkillDatabase.GROUPS.find(second)
	var key := (first + "+" + second) if a < b else (second + "+" + first)
	return ARCHETYPES.get(key, ARCHETYPES.get(first, "Adventurer"))


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {"owned": owned.duplicate(), "attr": attr_spent.duplicate(), "vitals": vitals.duplicate(),
		"bonus": bonus_perk_points, "respecs": respecs, "loadouts": loadouts.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	owned.clear()
	for id in d.get("owned", {}):
		if not PerkDatabase.get_perk(String(id)).is_empty():
			owned[String(id)] = int(d["owned"][id])
	attr_spent = (d.get("attr", {}) as Dictionary).duplicate()
	vitals = (d.get("vitals", {}) as Dictionary).duplicate()
	bonus_perk_points = int(d.get("bonus", 0))
	respecs = int(d.get("respecs", 0))
	loadouts = (d.get("loadouts", {}) as Dictionary).duplicate(true)
	apply()


# ---------------------------------------------------------------- 1.27: loadouts

## Keeps the perks, feats and points you have now as loadout A or B (free, anywhere)
func save_loadout(slot: String) -> void:
	loadouts[slot] = {"owned": owned.duplicate(), "attr": attr_spent.duplicate(), "vitals": vitals.duplicate()}


func loadout_cost() -> int:
	return LOADOUT_GOLD_PER_LEVEL * _level()


## Is the player at a temple shrine? (taking up a loadout needs one)
static func at_shrine(player: Node3D) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	for s in player.get_tree().get_nodes_in_group("shrines"):
		if (s as Node3D).global_position.distance_to(player.global_position) <= SHRINE_REACH:
			return true
	return false


## Takes up a saved loadout: every choice now is undone and the saved ones made. "" = done.
func load_loadout(slot: String, inventory: Inventory, player: Node3D) -> String:
	if not loadouts.has(slot):
		return "Nothing is saved as loadout %s." % slot
	if player != null and not at_shrine(player):
		return "Pray at a temple shrine to change your build."
	var cost := loadout_cost()
	if inventory != null and Currency.get_gold(inventory) < cost:
		return "You need %d gold for the offering." % cost
	if inventory != null:
		Currency.spend_gold(inventory, cost)
	var l: Dictionary = loadouts[slot]
	owned = (l["owned"] as Dictionary).duplicate()
	attr_spent = (l["attr"] as Dictionary).duplicate()
	vitals = (l["vitals"] as Dictionary).duplicate()
	apply()
	Achievements.note("loadout")
	return ""


# ---------------------------------------------------------------- 1.28: the shapeshifters' points

## One blood point per feeding (vampire) or body devoured (werewolf): Afflictions calls this
static func earn_shift_point(kind: String) -> void:
	var rec: Dictionary = WorldState.get_record("shift_points").duplicate()
	rec[kind] = int(rec.get(kind, 0)) + 1
	WorldState.set_record("shift_points", rec)


func shift_points(kind: String) -> int:
	var spent := 0
	for id in owned:
		if String(PerkDatabase.SHIFT_TREES.get(String(PerkDatabase.get_perk(id).get("tree", "")), "")) == kind:
			spent += int(owned[id])
	return int(WorldState.get_record("shift_points").get(kind, 0)) - spent


func _afflictions() -> Afflictions:
	var p := skills.get_parent() if skills != null else null
	return p.get_node_or_null("Afflictions") as Afflictions if p != null else null


## Does the player carry this curse?
func cursed(kind: String) -> bool:
	var a := _afflictions()
	return a != null and (a.vampire if kind == "vampire" else a.werewolf)


## Do this curse's perks work right now? (a vampire always; a werewolf in beast form)
func shift_active(kind: String) -> bool:
	if not cursed(kind):
		return false
	return kind == "vampire" or (skills != null and skills.get_parent() != null and skills.get_parent().has_meta("beast_form"))
