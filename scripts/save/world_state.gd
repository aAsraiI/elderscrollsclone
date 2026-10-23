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


static func has_record(id: String) -> bool:
	return records.has(id)


static func get_record(id: String) -> Dictionary:
	return records.get(id, {})


static func set_record(id: String, data: Dictionary) -> void:
	records[id] = data


static func erase_record(id: String) -> void:
	records.erase(id)


static func clear() -> void:
	records = {}


static func to_dict() -> Dictionary:
	return records.duplicate(true)


static func from_dict(data: Dictionary) -> void:
	records = data.duplicate(true)
