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
	## Fast travel reaches only towns and wayside inns (1.26), and long trips may be waylaid
	"fast_travel_towns": false,
	## Where the story starts (1.26): "gate" (outside a town), "inn" (a wayside inn), "shipwreck" (washed up on a shore), "wilds" (alone, far from the roads)
	"start": "gate",
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
	## Long falls hurt (Acrobatics makes them hurt less)
	"fall_damage": true,
	## What dying costs (1.26, DeathRules): "reload", "gold", "grave" (permadeath is Ironman)
	"death": "reload",
	## How many creatures: dungeon rooms, the wild, encounters (1.0 = normal)
	"spawn_density": 1.0,
	## Days before a cleared dungeon has new occupants
	"respawn_days": 21,
	## Raids on your homestead and blood-moon hordes (0 = never, 1 = normal, 2 = often)
	"raid_rate": 1.0,
}

static var _rules: Dictionary = {}


## World Creation presets (1.26): a set of the rules above, then fine-tune
const PRESETS := {
	"Story": {"survival": false, "afflictions": false, "ironman": false, "difficulty": 1, "death": "reload", "quest_markers": true, "fast_travel": true, "fast_travel_towns": false, "spawn_density": 0.7, "raid_rate": 0.0, "enemy_toughness": 0.8, "encounter_rate": 0.6},
	"Adventurer": {"survival": false, "afflictions": true, "ironman": false, "difficulty": 2, "death": "reload", "quest_markers": true, "fast_travel": true, "fast_travel_towns": false, "spawn_density": 1.0, "raid_rate": 1.0, "enemy_toughness": 1.0, "encounter_rate": 1.0},
	"Survivor": {"survival": true, "afflictions": true, "ironman": false, "difficulty": 2, "death": "grave", "quest_markers": true, "fast_travel": true, "fast_travel_towns": true, "spawn_density": 1.2, "raid_rate": 1.2, "enemy_toughness": 1.1, "encounter_rate": 1.2},
	"Hardcore": {"survival": true, "afflictions": true, "ironman": true, "difficulty": 3, "death": "grave", "quest_markers": false, "fast_travel": false, "fast_travel_towns": true, "spawn_density": 1.5, "raid_rate": 1.5, "enemy_toughness": 1.25, "encounter_rate": 1.5},
}


static func apply_preset(rules: Dictionary, name: String) -> void:
	for k in PRESETS.get(name, {}):
		rules[k] = PRESETS[name][k]


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
