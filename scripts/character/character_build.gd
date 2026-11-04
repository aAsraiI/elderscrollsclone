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
		if not bool(PerkDatabase.get_perk(id).get("feat", false)):
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
		for k in p["stats"]:
			perks[k] = float(perks.get(k, 0.0)) + float(p["stats"][k]) * int(owned[id])
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
		"bonus": bonus_perk_points, "respecs": respecs}


func from_dict(d: Dictionary) -> void:
	owned.clear()
	for id in d.get("owned", {}):
		if not PerkDatabase.get_perk(String(id)).is_empty():
			owned[String(id)] = int(d["owned"][id])
	attr_spent = (d.get("attr", {}) as Dictionary).duplicate()
	vitals = (d.get("vitals", {}) as Dictionary).duplicate()
	bonus_perk_points = int(d.get("bonus", 0))
	respecs = int(d.get("respecs", 0))
	apply()
