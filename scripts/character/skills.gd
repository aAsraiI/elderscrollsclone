class_name Skills
extends Node
## Skill levels, XP, milestone bonuses and the player level.
## Setup: add a Node named Skills as a child of the Player (next to Stats / Equipment) and
## attach this script. It finds Stats and Equipment on its own.
##
## Skill levels (and their XP) are the ONLY thing stored. Everything else is derived and pushed
## into Stats under the sources "skill_<id>", so saving = to_dict(), loading = from_dict().
## Other systems train a skill with:  skills.add_xp(&"one_handed", 3.0)
##
## Alpha 1.22: there is no cap on skills or the player level. Each skill has small bonuses every
## 5 levels, big named milestones at 10/25/50/75/100 and a mastery bonus every 25 levels past 100
## (see SkillDatabase). The perks, feats and level-up points you choose live in `build`
## (CharacterBuild) and are saved with the skills.

signal skill_xp_gained(skill_id: StringName, amount: float)
signal skill_leveled_up(skill_id: StringName, level: int)
## Fired when a skill reaches level 5, 10, 15, ... (tier = level / 5)
signal milestone_reached(skill_id: StringName, tier: int)
## Fired at the big named milestones (10, 25, 50, 75, 100) and every mastery step (125, 150, ...)
signal major_milestone(skill_id: StringName, level: int, title: String)
signal player_leveled_up(level: int)

@export var stats: Stats
@export var equipment: Equipment
## Lets the Stats screen add XP to the selected skill (X = +XP, Shift+X = +1 level).
## Only works when running from the editor, never in an exported game.
@export var debug_keys := true
@export var debug_xp_amount := 50.0
## Show a short message for level-ups and big milestones
@export var announce := true

const SOURCE_PREFIX := "skill_"
## Extra XP for the class's skills (major, minor) and the chosen specialization's group
const MAJOR_XP := 0.20
const MINOR_XP := 0.10
const SPECIALIZATION_XP := 0.15

var levels: Dictionary = {}  # StringName -> int
var xp: Dictionary = {}  # StringName -> float, progress inside the current level
var _applied: Dictionary = {}  # StringName -> Dictionary, last modifiers pushed to Stats
var _player_level := 1
## Player XP from deeds, see add_deed_xp()
var deed_xp := 0
## Multiplier on all skill XP (World Creation's skill speed x the character's advantages)
var xp_rate := 1.0
## Player XP the character started with (class and race skill levels): it doesn't count toward the
## player level, so every new character starts at level 1
var start_offset := 0
## Perks, feats, attribute and vital points (saved with the skills)
var build: CharacterBuild

const DEED_KEY := "_deeds"
const BUILD_KEY := "_build"
const OLD_SKILLS := {"offensive_magic": "destruction", "healing_magic": "restoration", "utility_magic": "alteration"}


func _ready() -> void:
	var parent := get_parent()
	if stats == null:
		stats = parent.get_node_or_null("Stats") as Stats
	if equipment == null:
		equipment = parent.get_node_or_null("Equipment") as Equipment
	if stats == null:
		push_error("Skills: could not find the player's Stats. Make this node a child of the Player (next to it) or assign it in the Inspector.")
		return

	for def in SkillDatabase.get_all():
		levels[def.id] = SkillDatabase.START_LEVEL
		xp[def.id] = 0.0
	build = CharacterBuild.new(self)
	_player_level = get_player_level()

	if equipment != null:
		# The weapon in your main hand decides which weapon skill's damage bonus is active
		equipment.equipped.connect(func(_slot, _item): _apply_all())
		equipment.unequipped.connect(func(_slot, _item): _apply_all())
	_apply_all()


# ---------------------------------------------------------------- training

## Gives XP to a skill (scaled by the skill's xp_mult). Handles level-ups, milestones and player level.
func add_xp(skill_id: StringName, amount: float) -> void:
	var def := SkillDatabase.get_skill(skill_id)
	if def == null or not levels.has(skill_id) or amount <= 0.0:
		return
	var bonus := (stats.get_stat("skill_xp_pct") if stats != null else 0.0) + favored_bonus(def)
	_grant(def, amount * def.xp_mult * xp_rate * (1.0 + bonus))


## Extra XP share for a skill of your class (major +20%, minor +10%) and specialization (+15%)
func favored_bonus(def: SkillData) -> float:
	var parent := get_parent()
	if parent == null or not parent.has_meta("character"):
		return 0.0
	var data: Dictionary = parent.get_meta("character")
	var cls := Classes.get_class_data(String(data.get("class", "")))
	var b := 0.0
	if (cls.get("major", []) as Array).has(String(def.id)):
		b += MAJOR_XP
	elif (cls.get("minor", []) as Array).has(String(def.id)):
		b += MINOR_XP
	if String(Classes.SPECIALIZATIONS.get(String(data.get("specialization", "")), {}).get("group", "")) == def.group:
		b += SPECIALIZATION_XP
	return b


## A new character's class and race: these skills start this many levels higher. The player level
## stays 1 (the extra player XP is remembered in start_offset).
func set_starting_levels(bonus: Dictionary) -> void:
	for id in bonus:
		var sid := StringName(id)
		if levels.has(sid):
			levels[sid] = maxi(SkillDatabase.START_LEVEL + int(bonus[id]), SkillDatabase.START_LEVEL)
			xp[sid] = 0.0
	start_offset = 0
	start_offset = get_player_xp() - deed_xp
	_player_level = get_player_level()
	_apply_all()


## Debug helper: gives exactly the XP needed for the next level.
func debug_level_up(skill_id: StringName) -> void:
	var def := SkillDatabase.get_skill(skill_id)
	if def == null or not levels.has(skill_id):
		return
	_grant(def, get_xp_to_next(skill_id) - float(xp[skill_id]) + 0.01)


## Debug / test helper: puts a skill straight at a level (milestones and player level follow)
func set_level(skill_id: StringName, level: int) -> void:
	if not levels.has(skill_id):
		return
	levels[skill_id] = maxi(level, SkillDatabase.START_LEVEL)
	xp[skill_id] = 0.0
	var def := SkillDatabase.get_skill(skill_id)
	if def != null:
		_apply_skill(def)
	_catch_up_player_level()


func is_debug_enabled() -> bool:
	return debug_keys and OS.is_debug_build()


func _grant(def: SkillData, amount: float) -> void:
	var id := def.id
	xp[id] = float(xp[id]) + amount
	skill_xp_gained.emit(id, amount)

	var leveled := false
	var guard := 0
	while float(xp[id]) >= get_xp_to_next(id) and guard < 1000:
		guard += 1
		xp[id] = float(xp[id]) - get_xp_to_next(id)
		levels[id] = int(levels[id]) + 1
		leveled = true
		var lvl: int = levels[id]
		skill_leveled_up.emit(id, lvl)
		if lvl % SkillDatabase.MILESTONE_INTERVAL == 0:
			milestone_reached.emit(id, get_tier(id))
		var title := major_title(def, lvl)
		if title != "":
			major_milestone.emit(id, lvl, title)
			_announce("%s %d: %s" % [def.display_name, lvl, title])

	if leveled:
		_apply_skill(def)
		_catch_up_player_level()


func _catch_up_player_level() -> void:
	var new_level := get_player_level()
	while _player_level < new_level:
		_player_level += 1
		player_leveled_up.emit(_player_level)
		if build != null:
			var feat := PerkDatabase.is_feat_level(_player_level)
			_announce("Level %d! %s Open the Character screen (C) to spend your points." % [_player_level,
				"A feat point, too." if feat else ""])
	if new_level < _player_level:
		_player_level = new_level
	if build != null:
		build.apply()


## The name of the big milestone at exactly this level ("" when there is none)
static func major_title(def: SkillData, level: int) -> String:
	if def.milestones.has(level):
		return String(def.milestones[level]["name"])
	if level > SkillDatabase.MASTERY_START and (level - SkillDatabase.MASTERY_START) % SkillDatabase.MASTERY_STEP == 0 and not def.mastery.is_empty():
		return "%s %s" % [SkillDatabase.rank_name(level), "Mastery"]
	return ""


func _announce(text: String) -> void:
	if announce and is_inside_tree() and not Engine.is_editor_hint():
		Locks.toast(get_tree(), text)


# ---------------------------------------------------------------- queries

func get_level(skill_id: StringName) -> int:
	return levels.get(skill_id, 0)


## Completed small milestones: level 14 = tier 2, level 15 = tier 3
func get_tier(skill_id: StringName) -> int:
	return floori(float(get_level(skill_id)) / SkillDatabase.MILESTONE_INTERVAL)


## The level of the next small milestone (there is always one: no cap)
func get_next_milestone_level(skill_id: StringName) -> int:
	return (get_tier(skill_id) + 1) * SkillDatabase.MILESTONE_INTERVAL


## The next big named milestone or mastery step above the current level
func get_next_major_level(skill_id: StringName) -> int:
	var lvl := get_level(skill_id)
	for m in SkillDatabase.MAJOR_LEVELS:
		if m > lvl:
			return m
	var past := lvl - SkillDatabase.MASTERY_START
	return SkillDatabase.MASTERY_START + (past / SkillDatabase.MASTERY_STEP + 1) * SkillDatabase.MASTERY_STEP


func get_xp(skill_id: StringName) -> float:
	return xp.get(skill_id, 0.0)


func get_xp_to_next(skill_id: StringName) -> float:
	return SkillDatabase.xp_to_next_level(get_level(skill_id))


## For dialogue / lock / recipe checks: skills.meets(&"speech", 40)
func meets(skill_id: StringName, required_level: int) -> bool:
	return get_level(skill_id) >= required_level


## Player XP from deeds (quests, bosses, new places) on top of skills.
func add_deed_xp(amount: int) -> void:
	if amount <= 0:
		return
	deed_xp += amount
	_catch_up_player_level()


## Skill levels count toward the player level by their weight (the small life skills count less)
func get_player_xp() -> int:
	var total := deed_xp - start_offset
	for id in levels:
		var def := SkillDatabase.get_skill(id)
		var w := def.player_xp_weight if def != null else 1.0
		total += int(float(SkillDatabase.skill_player_xp(levels[id])) * w)
	return total


func get_player_level() -> int:
	var total := get_player_xp()
	var level := 1
	while total >= SkillDatabase.player_xp_to_reach(level + 1) and level < 100000:
		level += 1
	return level


## Player XP earned inside the current player level
func get_player_xp_in_level() -> int:
	return get_player_xp() - SkillDatabase.player_xp_to_reach(get_player_level())


## Player XP needed to finish the current player level
func get_player_xp_for_next() -> int:
	var level := get_player_level()
	return SkillDatabase.player_xp_to_reach(level + 1) - SkillDatabase.player_xp_to_reach(level)


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var out := {}
	for id in levels:
		out[String(id)] = {"level": levels[id], "xp": xp[id]}
	out[DEED_KEY] = deed_xp
	out["_start_offset"] = start_offset
	if build != null:
		out[BUILD_KEY] = build.to_dict()
	return out


func from_dict(data: Dictionary) -> void:
	# Saves from before stage 10 had three magic skills: they become Destruction, Restoration, Alteration
	data = data.duplicate()
	for old in OLD_SKILLS:
		if data.has(old) and not data.has(OLD_SKILLS[old]):
			data[OLD_SKILLS[old]] = data[old]
	for id in levels:
		var entry: Dictionary = data.get(String(id), {})
		levels[id] = maxi(int(entry.get("level", SkillDatabase.START_LEVEL)), SkillDatabase.START_LEVEL)
		xp[id] = float(entry.get("xp", 0.0))
	deed_xp = int(data.get(DEED_KEY, 0))
	start_offset = int(data.get("_start_offset", 0))
	_player_level = get_player_level()
	_apply_all()
	if build != null:
		build.from_dict(data.get(BUILD_KEY, {}))


# ---------------------------------------------------------------- applying to Stats

func _apply_all() -> void:
	for def in SkillDatabase.get_all():
		_apply_skill(def)


## Everything a skill gives at a level, as Stats modifiers. active = its condition is met
## (the weapon is in hand, you wear no armor, ...). Attributes always count.
static func modifiers_at(def: SkillData, level: int, active: bool) -> Dictionary:
	var mods := {}
	if active:
		var tiers := SkillDatabase.effective_tiers(level)
		if tiers > 0.0:
			for stat in def.tier_effects:
				mods[stat] = float(def.tier_effects[stat]) * tiers
	for m in def.milestones:
		if level < int(m):
			continue
		var ms: Dictionary = def.milestones[m]
		if not active and not bool(ms.get("always", false)):
			continue
		for stat in ms["stats"]:
			mods[stat] = float(mods.get(stat, 0.0)) + float(ms["stats"][stat])
	var masteries := SkillDatabase.mastery_count(level)
	if masteries > 0 and active:
		for stat in def.mastery:
			mods[stat] = float(mods.get(stat, 0.0)) + float(def.mastery[stat]) * masteries
	var steps := level - SkillDatabase.START_LEVEL
	for attr in def.attributes:
		var points := floori(steps * float(def.attributes[attr]))
		if points > 0:
			mods[attr] = float(mods.get(attr, 0.0)) + float(points)
	return mods


# Works out what this skill is worth right now and hands it to Stats as one named source.
# Nothing is pushed if nothing changed, so equipping a sword doesn't spam every UI.
func _apply_skill(def: SkillData) -> void:
	if stats == null:
		return
	var mods := modifiers_at(def, get_level(def.id), condition_met(def))
	var previous: Dictionary = _applied.get(def.id, {})
	if previous == mods:
		return
	_applied[def.id] = mods
	var source: String = SOURCE_PREFIX + String(def.id)
	if mods.is_empty():
		stats.remove_modifiers(source)
	else:
		stats.add_modifiers(source, mods)


## Is this skill's condition met right now?
func condition_met(def: SkillData) -> bool:
	match def.condition:
		SkillData.When.WEAPON:
			return _wielded_skill() == def.id
		SkillData.When.UNARMED:
			return _main_hand() == null and not _off_hand_is_weapon()
		SkillData.When.UNARMORED:
			return not _wears_armor()
		SkillData.When.DUAL_WIELD:
			return _main_hand() != null and _main_hand().item_type == ItemData.ItemType.WEAPON and not _main_hand().is_bow and _off_hand_is_weapon()
	return true


func _main_hand() -> ItemData:
	return equipment.get_equipped(ItemData.EquipSlot.MAIN_HAND) if equipment != null else null


func _off_hand_is_weapon() -> bool:
	if equipment == null:
		return false
	var off := equipment.get_equipped(ItemData.EquipSlot.OFF_HAND)
	return off != null and off.item_type == ItemData.ItemType.WEAPON


func _wears_armor() -> bool:
	if equipment == null:
		return false
	for item in equipment.slots.values():
		var it := item as ItemData
		if it != null and it.item_type == ItemData.ItemType.ARMOR and (it.governing_skill == "heavy_armor" or it.governing_skill == "light_armor"):
			return true
	return false


func _wielded_skill() -> StringName:
	var item := _main_hand()
	if item == null:
		return &""
	return StringName(item.governing_skill)
