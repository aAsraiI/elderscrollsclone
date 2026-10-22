class_name Skills
extends Node
## Skill levels, XP, milestone bonuses and the player level.
## Setup: add a Node named Skills as a child of the Player (next to Stats / Equipment) and
## attach this script. It finds Stats and Equipment on its own.
##
## Skill levels (and their XP) are the ONLY thing stored. Everything else is derived and pushed
## into Stats under the sources "skill_<id>", so saving = to_dict(), loading = from_dict().
## Other systems train a skill with:  skills.add_xp(&"one_handed", 3.0)

signal skill_xp_gained(skill_id: StringName, amount: float)
signal skill_leveled_up(skill_id: StringName, level: int)
## Fired when a skill reaches level 5, 10, 15, ... (tier = level / 5)
signal milestone_reached(skill_id: StringName, tier: int)
signal player_leveled_up(level: int)

@export var stats: Stats
@export var equipment: Equipment
## Lets the Stats screen add XP to the selected skill (X = +XP, Shift+X = +1 level).
## Only works when running from the editor, never in an exported game.
@export var debug_keys := true
@export var debug_xp_amount := 50.0

const SOURCE_PREFIX := "skill_"

var levels: Dictionary = {}  # StringName -> int
var xp: Dictionary = {}  # StringName -> float, progress inside the current level
var _applied: Dictionary = {}  # StringName -> Dictionary, last modifiers pushed to Stats
var _player_level := 1
## Player XP from deeds, see add_deed_xp()
var deed_xp := 0

const DEED_KEY := "_deeds"


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
	_grant(def, amount * def.xp_mult)


## Debug helper: gives exactly the XP needed for the next level.
func debug_level_up(skill_id: StringName) -> void:
	var def := SkillDatabase.get_skill(skill_id)
	if def == null or not levels.has(skill_id) or levels[skill_id] >= SkillDatabase.MAX_LEVEL:
		return
	_grant(def, get_xp_to_next(skill_id) - float(xp[skill_id]) + 0.01)


func is_debug_enabled() -> bool:
	return debug_keys and OS.is_debug_build()


func _grant(def: SkillData, amount: float) -> void:
	var id := def.id
	if levels[id] >= SkillDatabase.MAX_LEVEL:
		return
	xp[id] = float(xp[id]) + amount
	skill_xp_gained.emit(id, amount)

	var leveled := false
	while levels[id] < SkillDatabase.MAX_LEVEL and float(xp[id]) >= get_xp_to_next(id):
		xp[id] = float(xp[id]) - get_xp_to_next(id)
		levels[id] = int(levels[id]) + 1
		leveled = true
		skill_leveled_up.emit(id, levels[id])
		if int(levels[id]) % SkillDatabase.MILESTONE_INTERVAL == 0:
			milestone_reached.emit(id, get_tier(id))
	if levels[id] >= SkillDatabase.MAX_LEVEL:
		xp[id] = 0.0

	if leveled:
		_apply_skill(def)
		var new_level := get_player_level()
		while _player_level < new_level:
			_player_level += 1
			player_leveled_up.emit(_player_level)


# ---------------------------------------------------------------- queries

func get_level(skill_id: StringName) -> int:
	return levels.get(skill_id, 0)


## Completed milestones: level 14 = tier 2, level 15 = tier 3
func get_tier(skill_id: StringName) -> int:
	return floori(float(get_level(skill_id)) / SkillDatabase.MILESTONE_INTERVAL)


## The level of the next milestone, or -1 if the skill is maxed
func get_next_milestone_level(skill_id: StringName) -> int:
	var next := (get_tier(skill_id) + 1) * SkillDatabase.MILESTONE_INTERVAL
	return next if next <= SkillDatabase.MAX_LEVEL else -1


func get_xp(skill_id: StringName) -> float:
	return xp.get(skill_id, 0.0)


func get_xp_to_next(skill_id: StringName) -> float:
	return SkillDatabase.xp_to_next_level(get_level(skill_id))


## For dialogue / lock / recipe checks: skills.meets(&"speech", 40)
func meets(skill_id: StringName, required_level: int) -> bool:
	return get_level(skill_id) >= required_level


## Player XP from deeds (quests, bosses, new places) on top of skills. Skills alone reach about
## level 80; deeds carry you the rest of the way to 100.
func add_deed_xp(amount: int) -> void:
	if amount <= 0:
		return
	deed_xp += amount
	var new_level := get_player_level()
	while _player_level < new_level:
		_player_level += 1
		player_leveled_up.emit(_player_level)


func get_player_xp() -> int:
	var total := deed_xp
	for id in levels:
		total += SkillDatabase.skill_player_xp(levels[id])
	return total


func get_player_level() -> int:
	var total := get_player_xp()
	var level := 1
	while level < LevelCurve.MAX_LEVEL and total >= SkillDatabase.player_xp_to_reach(level + 1):
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
	return out


func from_dict(data: Dictionary) -> void:
	for id in levels:
		var entry: Dictionary = data.get(String(id), {})
		levels[id] = clampi(int(entry.get("level", SkillDatabase.START_LEVEL)), SkillDatabase.START_LEVEL, SkillDatabase.MAX_LEVEL)
		xp[id] = float(entry.get("xp", 0.0))
	deed_xp = int(data.get(DEED_KEY, 0))
	_player_level = get_player_level()
	_apply_all()


# ---------------------------------------------------------------- applying to Stats

func _apply_all() -> void:
	for def in SkillDatabase.get_all():
		_apply_skill(def)


# Works out what this skill is worth right now and hands it to Stats as one named source.
# Nothing is pushed if nothing changed, so equipping a sword doesn't spam every UI.
func _apply_skill(def: SkillData) -> void:
	var mods := {}
	var tier := get_tier(def.id)
	if tier > 0 and (not def.weapon_conditional or _wielded_skill() == def.id):
		for stat in def.tier_effects:
			mods[stat] = float(def.tier_effects[stat]) * tier

	var steps := get_level(def.id) - SkillDatabase.START_LEVEL
	for attr in def.attributes:
		var points := floori(steps * float(def.attributes[attr]))
		if points > 0:
			mods[attr] = float(points)

	var previous: Dictionary = _applied.get(def.id, {})
	if previous == mods:
		return
	_applied[def.id] = mods
	var source: String = SOURCE_PREFIX + String(def.id)
	if mods.is_empty():
		stats.remove_modifiers(source)
	else:
		stats.add_modifiers(source, mods)


func _wielded_skill() -> StringName:
	if equipment == null:
		return &""
	var item := equipment.get_equipped(ItemData.EquipSlot.MAIN_HAND)
	if item == null:
		return &""
	return StringName(item.governing_skill)
