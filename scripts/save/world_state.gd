class_name WorldState
extends RefCounted
## Everything the player has CHANGED in the world, keyed by a stable id. The world itself is
## rebuilt from the seed, so only differences need saving: this is that list of differences.
##
## Anything that wants to remember something writes a record under its own id and reads it
## back when it is created again:
##     WorldState.set_record("chest_castle_cellar", {"rolled": true, "inventory": {...}})
##     if WorldState.has_record(id): restore(WorldState.get_record(id))
## Records may only hold JSON-friendly values (numbers, strings, bools, arrays, dictionaries).
## ContainerComponent already does this when you give it a Save Id.
##
## Static, so it survives the scene reload a load performs. SaveManager clears it for a new
## game and fills it from the file for a load.

static var records: Dictionary = {}
## Goes up with every change (caches elsewhere use it to know they are stale)
static var version := 0


static func has_record(id: String) -> bool:
	return records.has(id)


static func get_record(id: String) -> Dictionary:
	return records.get(id, {})


static func set_record(id: String, data: Dictionary) -> void:
	records[id] = data
	version += 1


static func erase_record(id: String) -> void:
	records.erase(id)
	version += 1


static func clear() -> void:
	records = {}
	version += 1


static func to_dict() -> Dictionary:
	return records.duplicate(true)


## Record groups that the game works out again by itself, so a save file leaves them out. Empty for
## now: "npcact/" looked like one, but TownLife uses it after a load to know a lock you picked is yours
## to keep (without it, owners lock their doors again at once). Saves are compressed instead.
const NOT_SAVED: Array[String] = []


## What goes into a save file: every record except the ones the game rebuilds on its own
static func to_save_dict() -> Dictionary:
	var out := {}
	for k: String in records:
		var skip := false
		for p in NOT_SAVED:
			if k.begins_with(p):
				skip = true
				break
		if not skip:
			out[k] = records[k].duplicate(true) if records[k] is Dictionary else records[k]
	return out


static func from_dict(data: Dictionary) -> void:
	records = data.duplicate(true)
	version += 1
