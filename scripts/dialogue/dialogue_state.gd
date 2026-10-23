class_name DialogueState
extends RefCounted
## What the player has picked up from talking, all kept in WorldState so it is saved with the game:
##   "dialogue/known"     the topics the player knows (learned when someone mentions them)
##   "disp/<npc id>"      how much a person's liking for the player has changed (+/-)
##   "flag/<name>"        flags set by hand-written dialogue (DialogueResponse.set_flag)
##   "journal"            every unique line people have told the player (see add_journal)

const START_TOPICS := ["background", "my trade", "latest rumors", "little advice", "duties"]
const KNOWN := "dialogue/known"
const JOURNAL := "journal"

## Disposition changes for people who have no saved id (travelers on the road), this session only
static var _temp_disp := {}


# ---------------------------------------------------------------- topics

static func known_topics() -> PackedStringArray:
	var rec := WorldState.get_record(KNOWN)
	if not rec.has("topics"):
		return PackedStringArray(START_TOPICS)
	return PackedStringArray(rec["topics"])


static func knows(topic: String) -> bool:
	return known_topics().has(topic)


## Adds a topic to what the player knows. Returns true if it was new.
static func learn(topic: String) -> bool:
	var list := known_topics()
	if list.has(topic):
		return false
	list.append(topic)
	WorldState.set_record(KNOWN, {"topics": Array(list)})
	return true


# ---------------------------------------------------------------- disposition

## Forgets the disposition changes of passing strangers (GameState.reset)
static func clear_temp() -> void:
	_temp_disp.clear()


static func get_disposition(npc_id: String, base: int) -> int:
	var delta := 0
	if npc_id == "":
		return clampi(base, 0, 100)
	if npc_id.begins_with("temp:"):
		delta = int(_temp_disp.get(npc_id, 0))
	else:
		delta = int(WorldState.get_record("disp/" + npc_id).get("d", 0))
	return clampi(base + delta, 0, 100)


## Changes how much someone likes the player. Returns the new disposition (0-100).
static func change_disposition(npc_id: String, base: int, amount: int) -> int:
	if npc_id == "":
		return clampi(base, 0, 100)
	var now := get_disposition(npc_id, base)
	var target := clampi(now + amount, 0, 100)
	var delta := target - base
	if npc_id.begins_with("temp:"):
		_temp_disp[npc_id] = delta
	else:
		WorldState.set_record("disp/" + npc_id, {"d": delta})
	return target


# ---------------------------------------------------------------- flags

static func has_flag(flag: String) -> bool:
	return bool(WorldState.get_record("flag/" + flag).get("on", false))


static func set_flag(flag: String, on: bool = true) -> void:
	WorldState.set_record("flag/" + flag, {"on": on})


# ---------------------------------------------------------------- journal

## Every journal entry, oldest first: {"text", "speaker", "topic", "place", "day", "time",
## "quest_id", "quest_name"}
static func journal() -> Array:
	return WorldState.get_record(JOURNAL).get("entries", [])


## Writes a line into the journal, unless the very same words are already in it (said by
## anyone). Returns true if it was added.
static func add_journal(entry: Dictionary) -> bool:
	var text := String(entry.get("text", "")).strip_edges()
	if text == "":
		return false
	var entries := journal().duplicate()
	for e in entries:
		if String(e.get("text", "")) == text:
			return false
	var clean := {
		"text": text,
		"speaker": String(entry.get("speaker", "")),
		"topic": String(entry.get("topic", "")),
		"place": String(entry.get("place", "")),
		"day": int(entry.get("day", 1)),
		"time": String(entry.get("time", "")),
		"quest_id": String(entry.get("quest_id", "")),
		"quest_name": String(entry.get("quest_name", "")),
	}
	entries.append(clean)
	WorldState.set_record(JOURNAL, {"entries": entries})
	return true
