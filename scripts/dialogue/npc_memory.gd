class_name NpcMemory
extends RefCounted
## What people remember about the player: crimes they saw (CrimeManager), gifts and bribes they
## took (Persuasion), quests the player did for them (QuestBook). When you next speak to them, the
## newest memory replaces their usual greeting, at most TELLS times each, so they don't repeat
## themselves forever. People are known by name and town; saved in WorldState "mem/<name>|<town>".

const KEEP := 5
const TELLS := 2


static func _key(person: String, town: String) -> String:
	return "mem/%s|%s" % [person, town]


## Remembers something: kind is "theft", "assault", "murder", "trespass", "gift" or "quest";
## what is the thing itself (a building, an amount of gold, a quest's name)
static func remember(person: String, town: String, kind: String, what: String, day: int) -> void:
	if person == "":
		return
	var list: Array = (WorldState.get_record(_key(person, town)).get("list", []) as Array).duplicate(true)
	list.append({"kind": kind, "what": what, "day": day, "told": 0})
	while list.size() > KEEP:
		list.remove_at(0)
	WorldState.set_record(_key(person, town), {"list": list})


static func memories(person: String, town: String) -> Array:
	return WorldState.get_record(_key(person, town)).get("list", [])


## The words a person greets you with because of something they remember ("" = nothing to say)
static func greeting(s: DialogueEngine.Speaker, today: int) -> String:
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	var list: Array = (memories(s.name, town) as Array).duplicate(true)
	for i in range(list.size() - 1, -1, -1):
		var m: Dictionary = list[i]
		if int(m.get("told", 0)) >= TELLS:
			continue
		m["told"] = int(m.get("told", 0)) + 1
		WorldState.set_record(_key(s.name, town), {"list": list})
		return _line(m, today)
	return ""


static func _line(m: Dictionary, today: int) -> String:
	var ago := today - int(m.get("day", today))
	var when := "today" if ago <= 0 else ("yesterday" if ago == 1 else ("the other day" if ago < 7 else "a while back"))
	var what := String(m.get("what", ""))
	match String(m.get("kind", "")):
		"theft":
			return "I saw what you took %s. Keep your hands where I can see them." % when
		"assault":
			return "You. I saw you strike someone %s. I've not forgotten." % when
		"murder":
			return "Stay back! I saw what you did. Murderer."
		"trespass":
			return "You were somewhere you shouldn't have been %s%s. Don't let me catch you again." % [when, (", in " + what) if what != "" else ""]
		"gift":
			return "Ah, it's you. Thank you again for the %s gold. Generous of you." % what
		"quest":
			return "You! You helped with %s. I won't forget it. What can I do for you?" % ("\"" + what + "\"" if what != "" else "that business")
	return ""
