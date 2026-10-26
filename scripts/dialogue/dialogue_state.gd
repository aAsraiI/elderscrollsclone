class_name DialogueState
extends RefCounted
## What the player has picked up from talking, all kept in WorldState so it is saved with the game:
##   "dialogue/known"     the topics the player knows (learned when someone mentions them)
##   "disp/<npc id>"      how much a person's liking for the player has changed (+/-)
##   "flag/<name>"        flags set by hand-written dialogue (DialogueResponse.set_flag)
##   "journal"            what people told the player, one entry per topic (see add_journal)
##   "journal_notes"      the player's own notes (see add_note)

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
## anyone). Returns true if it was added or changed.
## One entry per topic: what someone says about a topic (outside a quest) replaces what was
## written about it before, so asking ten people about the same town leaves one entry, not ten
## slightly different ones. The entry moves to the end (newest) and remembers who said it.
static func add_journal(entry: Dictionary) -> bool:
	var text := String(entry.get("text", "")).strip_edges()
	if text == "":
		return false
	var entries := journal().duplicate()
	for e in entries:
		if String(e.get("text", "")) == text:
			return false
	var topic := String(entry.get("topic", ""))
	var keyed := topic != "" and String(entry.get("quest_id", "")) == ""
	var heard: Array = []
	if keyed:
		for i in range(entries.size() - 1, -1, -1):
			var old: Dictionary = entries[i]
			if String(old.get("topic", "")) == topic and String(old.get("quest_id", "")) == "":
				heard = old.get("heard", [old.get("speaker", "")])
				entries.remove_at(i)
	var clean := {
		"text": text,
		"speaker": String(entry.get("speaker", "")),
		"topic": String(entry.get("topic", "")),
		"place": String(entry.get("place", "")),
		"day": int(entry.get("day", 1)),
		"time": String(entry.get("time", "")),
		"quest_id": String(entry.get("quest_id", "")),
		"quest_name": String(entry.get("quest_name", "")),
		"id": _next_entry_id(),
		"type": String(entry.get("type", "Quest" if String(entry.get("quest_id", "")) != "" else ("System" if String(entry.get("topic", "")) == "" else "Knowledge"))),
		"npc_id": String(entry.get("npc_id", "")),
		"read": false,
	}
	if keyed:
		var who := String(entry.get("speaker", ""))
		if who != "" and not heard.has(who):
			heard.append(who)
		clean["heard"] = heard.filter(func(h: Variant) -> bool: return String(h) != "")
	entries.append(clean)
	entries = _prune(entries)
	WorldState.set_record(JOURNAL, {"entries": entries})
	return true


## Cleans an old journal (saves from before Alpha 1.12): every topic outside a quest keeps only
## its newest entry. Returns how many entries went.
static func compact_journal() -> int:
	var entries := journal()
	var seen := {}
	var keep: Array = []
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var topic := String(e.get("topic", ""))
		if topic != "" and String(e.get("quest_id", "")) == "":
			if seen.has(topic):
				var heard: Array = seen[topic].get("heard", [seen[topic].get("speaker", "")])
				if not heard.has(e.get("speaker", "")) and String(e.get("speaker", "")) != "":
					heard.append(e["speaker"])
				seen[topic]["heard"] = heard
				continue
			e = e.duplicate()
			seen[topic] = e
		keep.push_front(e)
	var gone := entries.size() - keep.size()
	if gone > 0:
		WorldState.set_record(JOURNAL, {"entries": keep})
	return gone


# ---------------------------------------------------------------- the player's own notes

const NOTES := "journal_notes"
const NOTE_MAX := 4000


## The player's notes, oldest first: {"id", "title", "text", "day", "time", "place"}
static func notes() -> Array:
	return WorldState.get_record(NOTES).get("list", [])


static func get_note(id: int) -> Dictionary:
	for n: Dictionary in notes():
		if int(n["id"]) == id:
			return n
	return {}


## Writes a new note. Returns its id.
static func add_note(title: String, text: String, day: int, time: String, place: String) -> int:
	var rec := WorldState.get_record(NOTES)
	var id := int(rec.get("next", 1))
	var list: Array = rec.get("list", []).duplicate()
	list.append({"id": id, "title": _note_title(title, text), "text": text.left(NOTE_MAX), "day": day, "time": time, "place": place})
	WorldState.set_record(NOTES, {"list": list, "next": id + 1})
	return id


## Rewrites a note's title and words (the date and place it was written stay)
static func edit_note(id: int, title: String, text: String) -> bool:
	var rec := WorldState.get_record(NOTES)
	var list: Array = rec.get("list", []).duplicate(true)
	for n: Dictionary in list:
		if int(n["id"]) == id:
			n["title"] = _note_title(title, text)
			n["text"] = text.left(NOTE_MAX)
			WorldState.set_record(NOTES, {"list": list, "next": int(rec.get("next", 1))})
			return true
	return false


static func delete_note(id: int) -> bool:
	var rec := WorldState.get_record(NOTES)
	var list: Array = rec.get("list", []).filter(func(n: Dictionary) -> bool: return int(n["id"]) != id)
	if list.size() == rec.get("list", []).size():
		return false
	WorldState.set_record(NOTES, {"list": list, "next": int(rec.get("next", 1))})
	return true


# A note with no title is named after its first words
static func _note_title(title: String, text: String) -> String:
	title = title.strip_edges()
	if title != "":
		return title.left(60)
	var first := text.strip_edges().get_slice("\n", 0)
	return first.left(40) + ("..." if first.length() > 40 else "") if first != "" else "Note"


# ---------------------------------------------------------------- what gets written down

## Journal entry types (JournalUI tabs): Quest, Rumor, Place, Person, Knowledge, Note, System
const ENTRY_TYPES := ["Quest", "Rumor", "Place", "Person", "Knowledge", "Note", "System"]
## Small talk is never written down: greetings, chatter, shop talk, the weather
const NOT_JOURNALED := ["background", "my trade", "small talk", "the weather", "local business", "rooms",
	"food and drink", "little advice", "directions", "duties", "membership", "advancement", "report back"]
## The journal keeps at most this many entries: past it, the oldest rumors and knowledge go first
const JOURNAL_MAX := 600


## The type an answer is written down as, or "" when it isn't worth writing down at all.
## index_kind: the topic's kind in DialogueEngine's index (town, place, person, poi, faction, generic)
static func entry_type(topic: String, quest_id: String, index_kind: String) -> String:
	if quest_id != "":
		return "Quest"
	if NOT_JOURNALED.has(topic):
		return ""
	match index_kind:
		"town", "place", "poi":
			return "Place"
		"person":
			return "Person"
		"generic":
			return "Rumor"
	return "Knowledge"


static func _next_entry_id() -> int:
	var rec := WorldState.get_record("journal_next")
	var n := int(rec.get("n", 1))
	WorldState.set_record("journal_next", {"n": n + 1})
	return n


# Past JOURNAL_MAX: drop the oldest rumors and knowledge (quests, places, notes stay)
static func _prune(entries: Array) -> Array:
	var over := entries.size() - JOURNAL_MAX
	if over <= 0:
		return entries
	var out: Array = []
	for e: Dictionary in entries:
		if over > 0 and String(e.get("type", "")) in ["Rumor", "Knowledge"]:
			over -= 1
			continue
		out.append(e)
	return out


## Marks every entry read (the journal's "Mark all read"), or one by id
static func mark_read(id: int = -1) -> void:
	var entries := journal().duplicate(true)
	for e: Dictionary in entries:
		if id < 0 or int(e.get("id", 0)) == id:
			e["read"] = true
	WorldState.set_record(JOURNAL, {"entries": entries})


static func unread_count() -> int:
	var n := 0
	for e: Dictionary in journal():
		if not bool(e.get("read", true)):
			n += 1
	return n


# ---------------------------------------------------------------- topics already asked about

static func mark_asked(topic: String) -> void:
	var rec := WorldState.get_record("dialogue/asked")
	var list: Array = rec.get("topics", [])
	if not list.has(topic):
		list = list.duplicate()
		list.append(topic)
		WorldState.set_record("dialogue/asked", {"topics": list})


static func was_asked(topic: String) -> bool:
	return (WorldState.get_record("dialogue/asked").get("topics", []) as Array).has(topic)
