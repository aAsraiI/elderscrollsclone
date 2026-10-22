class_name GameRules
extends RefCounted
## The rules of one playthrough, chosen on the World Creation screen and kept in its saves
## (unlike Settings, which are shared by every game). Read anywhere: GameRules.get_rule("survival").
## A game started without the screen (the editor, tests) plays with DEFAULTS.

const DEFAULTS := {
	## Hunger, fatigue and cold, and catching diseases (see Survival / Afflictions)
	"survival": false,
	## Diseases, vampirism and lycanthropy can be caught at all
	"afflictions": true,
	## One life: dying deletes the save. Saving still works (one slot), loading old saves does not.
	"ironman": false,
	## 0 Novice .. 4 Master (copied into Settings when the game starts)
	"difficulty": 2,
	## Fast travel by clicking the map twice
	"fast_travel": true,
	## Quest targets on the map and compass
	"quest_markers": true,
	## How fast skills level (1.0 = normal)
	"xp_rate": 1.0,
	## How much loot and gold turns up (1.0 = normal)
	"loot_rate": 1.0,
	## Random encounters on the road (0 = none, 1 = normal, 2 = many)
	"encounter_rate": 1.0,
	## Real minutes for one in-game day
	"day_minutes": 24.0,
	## Enemies hit harder and have more health as well as the difficulty (1.0 = normal)
	"enemy_toughness": 1.0,
}

static var _rules: Dictionary = {}


static func get_rule(key: String) -> Variant:
	return _rules.get(key, DEFAULTS.get(key))


static func set_rule(key: String, value: Variant) -> void:
	_rules[key] = value


static func reset() -> void:
	_rules = DEFAULTS.duplicate()


static func to_dict() -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in _rules:
		out[k] = _rules[k]
	return out


static func from_dict(d: Dictionary) -> void:
	reset()
	for k in d:
		if DEFAULTS.has(k):
			_rules[k] = d[k]


static func survival() -> bool:
	return bool(get_rule("survival"))


static func ironman() -> bool:
	return bool(get_rule("ironman"))


static func afflictions() -> bool:
	return bool(get_rule("afflictions"))
