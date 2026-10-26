class_name QuestDebug
extends RefCounted
## What the debug console's quest.* commands and its quest overlay show: every active quest, the
## step it is on, what that step wants, who it is handed in to, and what is still blocking it.
## Covers guild jobs and bounties (QuestManager) and the written quests (QuestBook).
##
##   quest.list                    every active quest (quest.list all: finished and failed too)
##   quest.why                     the same, with what is blocking each one
##   quest.start <id>              start a written quest (S-KR01...), or quest.start <guild> <kind>
##                                 for a guild job (fighters kill, thieves steal, mages persuade...)
##   quest.setstage <id> <step>    jump a written quest to a step (1 = the first)
##   quest.complete <id>           finish it now, rewards and all
##   quest.fail <id>               end it as failed
##   quest.reset <id>              forget it, so it can be offered again
##   quest.check                   look for quests that could never be finished (QuestCheck)
##   quest.overlay                 show or hide the overlay


static func run(cmd: String, args: Array, world: WorldManager) -> String:
	if world == null or world.quests == null or world.book == null:
		return "No world."
	var qm := world.quests
	var book := world.book
	match cmd:
		"list":
			var lines := report(world, false, not args.is_empty() and args[0] == "all")
			return "\n".join(lines) if not lines.is_empty() else "No active quests."
		"why":
			var lines := report(world, true)
			return "\n".join(lines) if not lines.is_empty() else "No active quests."
		"check":
			var probs := QuestCheck.problems(world)
			return "No problems found." if probs.is_empty() else "\n".join(probs)
		"start":
			if args.is_empty():
				return "quest.start <id>  or  quest.start <guild> <kind>"
			if QuestRunner.get_data(String(args[0])) != null:
				var rid := String(args[0])
				QuestRunner._store(rid, {})  # test mode: from the start, whatever it needs
				QuestRunner._store(rid, {"state": "available", "stage": 0, "done": {}, "flags": [], "t0": world.runner._hours()})
				world.runner.set_state(rid, "active")
				world.runner._begin_stage(rid, 0)
				return "%s: %s" % [rid, world.runner.status(rid)]
			var id := String(args[0]).to_upper()
			if not QuestBook.get_def(id).is_empty():
				book.start(id)
				return "%s: %s" % [id, QuestBook.status(id)]
			var faction := String(args[0]).to_lower()
			if Factions.get_data(faction) == null:
				return "No quest or guild '%s'." % args[0]
			var giver := DialogueEngine.Speaker.new()
			giver.id = "debug"
			giver.name = "the %s" % Factions.display_name(faction)
			var p := world.get_tree().get_first_node_in_group("player") as Node3D
			giver.position = p.global_position if p != null else Vector3.ZERO
			var old := QuestManager.active_for(faction)
			if not old.is_empty():
				qm.fail(old, "Replaced from the console.")
			var q := qm.offer(faction, giver, String(args[1]) if args.size() > 1 else "")
			return "Nothing fits here." if q.is_empty() else "%s: %s" % [q["id"], q["objective"]]
		"setstage":
			if args.size() >= 2 and QuestRunner.get_data(String(args[0])) != null:
				var rid := String(args[0])
				if not (world.runner.status(rid) in ["active", "ready"]):
					run("start", [rid], world)
				var rec := QuestRunner.record(rid).duplicate(true)
				rec["state"] = "active"
				QuestRunner._store(rid, rec)
				world.runner._begin_stage(rid, int(args[1]) - 1)
				return "%s: %s, stage %d" % [rid, world.runner.status(rid), int(QuestRunner.record(rid).get("stage", 0)) + 1]
			if args.size() < 2 or QuestBook.get_def(String(args[0]).to_upper()).is_empty():
				return "quest.setstage <book quest id> <step>"
			var id := String(args[0]).to_upper()
			book.debug_set_step(id, int(args[1]) - 1)
			return "%s: %s, step %d" % [id, QuestBook.status(id), int(QuestBook.state(id).get("step", 0)) + 1]
		"complete", "fail", "reset":
			if args.is_empty():
				return "quest.%s <id>" % cmd
			var id := String(args[0])
			if not QuestBook.get_def(id.to_upper()).is_empty():
				id = id.to_upper()
				match cmd:
					"complete": book.debug_complete(id)
					"fail": book.fail(id, "Failed from the console.")
					"reset": book.reset(id)
				return "%s: %s" % [id, QuestBook.status(id) if QuestBook.status(id) != "" else "not started"]
			var q := QuestManager.get_quest(id.to_lower())
			if q.is_empty():
				return "No quest '%s'." % id
			match cmd:
				"complete":
					if q["status"] == "active":
						qm.complete(q)
				"fail":
					qm.fail(q, "Failed from the console.")
				"reset":
					var list := QuestManager.all_quests().filter(func(x: Dictionary) -> bool: return x["id"] != q["id"])
					QuestManager._save_list(list, QuestManager._counter())
					QuestManager.log_quest(q, "reset")
					return "%s forgotten." % q["id"]
			return "%s: %s" % [q["id"], QuestManager.get_quest(q["id"]).get("status", "")]
	return "Unknown quest command. Try quest.list, quest.why, quest.start, quest.setstage, quest.complete, quest.fail, quest.reset, quest.check, quest.overlay."


## One block of lines per quest. why: add what blocks it. finished: list ended quests too.
static func report(world: WorldManager, why: bool, finished: bool = false) -> PackedStringArray:
	var out := PackedStringArray()
	var qm := world.quests
	for q: Dictionary in QuestManager.all_quests():
		var st := String(q["status"])
		if st != "active" and not finished:
			continue
		var ready := st == "active" and qm.is_ready(q)
		out.append("%s  %s  [%s%s]" % [q["id"], q["name"], st, ", ready" if ready else ""])
		out.append("    %s" % q.get("objective", ""))
		out.append("    hand in: %s%s" % [q.get("giver_name", "?"), (", " + String(q["giver_town"])) if String(q.get("giver_town", "")) != "" else ""])
		if why and st == "active":
			out.append("    blocking: %s" % ("nothing, report back" if ready else job_blocker(world, q)))
	var book := world.book
	for id in QuestBook.ids():
		var st := QuestBook.status(id)
		if st == "" or (st != "active" and not finished):
			continue
		var d := QuestBook.get_def(id)
		var steps: Array = d["steps"]
		var i := int(QuestBook.state(id).get("step", 0))
		out.append("%s  %s  [%s, step %d of %d]" % [id, d["name"], st, mini(i + 1, steps.size()), steps.size()])
		if st == "active":
			out.append("    %s" % book_step_text(book, id))
			if why:
				out.append("    blocking: %s" % book_blocker(world, id))
	return out


## Why a guild job isn't ready yet
static func job_blocker(world: WorldManager, q: Dictionary) -> String:
	var gone := QuestCheck.job_problem(world, q)
	if gone != "":
		return gone + " (it can't be finished: quest.fail it)"
	match String(q["type"]):
		"retrieve", "steal", "excavate":
			var where := "the %s" % q.get("target_name", "place")
			return "%s not carried (it is placed in %s: %s)" % [q.get("item_name", "item"), where, "yes" if bool(q.get("placed", false)) or q["type"] == "excavate" else "not yet, go there"]
		"kill", "hunt":
			return "%s still alive at the %s" % [q.get("chief", "the target"), q.get("target_name", "place")]
		"survey":
			return "the master of the %s still lives" % q.get("target_name", "place")
		"persuade":
			var r: TownLife.Resident = world.life.get_resident(String(q["target"])) if world.life != null else null
			if r != null:
				return "%s's disposition %d of %d" % [r.data.display_name, DialogueState.get_disposition(r.data.id, r.data.base_disposition), QuestManager.PERSUADE_GOAL]
		"deliver":
			return "talk to %s about \"a delivery\" (with the package)" % q.get("target_name", "them")
		"assassinate":
			return "%s still alive" % q.get("target_name", "the target")
	return "unknown"


## What the current step of a written quest asks for
static func book_step_text(book: QuestBook, id: String) -> String:
	var d := QuestBook.get_def(id)
	var step := book._step(d)
	if step.is_empty():
		return "(no step)"
	var who := _who_text(step.get("who", {}), d)
	match String(step["do"]):
		"talk":
			return "talk to %s about \"%s\"%s" % [who, step["topic"], (" carrying the " + String(step["carry"])) if step.has("carry") else ""]
		"choice":
			var topics := PackedStringArray()
			for o: Dictionary in step["options"]:
				topics.append("\"%s\"" % o["topic"])
			return "tell %s: %s" % [who, " or ".join(topics)]
		"clear":
			return "defeat the master of a dungeon"
		"fetch":
			return "find the %s in a dungeon's deepest chest" % step["item"]
		"fight":
			return "kill the foes at a place"
		"visit":
			return "go to a place"
		"collect":
			return "carry %d of %s" % [int(step["count"]), String(step["item"]).get_file().get_basename()]
		"wait":
			return "wait %d hours" % int(step["hours"])
		"realm":
			return "conquer the realm %s" % RealmManager.display_name(String(step["realm"]))
		"site":
			return "clear site %d of the realm %s" % [int(step["site"]) + 1, RealmManager.display_name(String(step["realm"]))]
	return String(step["do"])


## Why a written quest's step isn't done yet
static func book_blocker(world: WorldManager, id: String) -> String:
	var book := world.book
	var d := QuestBook.get_def(id)
	var step := book._step(d)
	if step.is_empty():
		return "no step"
	var st := QuestBook.state(id)
	var place: Dictionary = st.get("places", {}).get(str(int(st.get("step", 0))), {})
	match String(step["do"]):
		"talk", "choice":
			var problems := PackedStringArray()
			var towns := {}
			for t in world.towns:
				if t.town != null:
					towns[t.town.display_name] = t
			QuestCheck._check_who(world, towns, id, "now", step.get("who", {}), d, problems)
			if not problems.is_empty():
				return problems[0]
			if step.has("carry") and book._talk_blocked(d, step) != "":
				return book._talk_blocked(d, step)
			return "waiting for you to talk to %s" % _who_text(step.get("who", {}), d)
		"clear", "fetch", "fight", "visit":
			if place.is_empty() or not place.has("pos"):
				return "its place could not be found in this world (quest.setstage or quest.fail it)"
			if step["do"] == "fetch":
				return "item not carried (placed in the chest: %s)" % ("yes" if bool(place.get("placed", false)) else "not yet")
			return "at %.0f, %.0f" % [float(place["pos"][0]), float(place["pos"][2])]
		"collect":
			var it := load(String(step["item"])) as ItemData if ResourceLoader.exists(String(step["item"])) else null
			if it == null:
				return "the item %s doesn't exist" % step["item"]
			var inv := world.get_tree().get_first_node_in_group("player").get_node("Inventory") as Inventory
			return "carrying %d of %d" % [inv.get_count(it), int(step["count"])]
		"wait":
			return "%.0f of %d hours" % [book._hours() - float(st.get("t0", 0.0)), int(step["hours"])]
	return "in progress"


static func _who_text(who: Dictionary, d: Dictionary) -> String:
	if who.has("giver"):
		who = d["giver"]
	if who.has("lord"):
		return "the lord of %s" % who["lord"]
	if who.has("cast"):
		return "%s in %s" % [who["cast"], who["town"]]
	if who.has("guild"):
		return "a leader of the %s" % Factions.display_name(String(who["guild"]))
	if who.has("leader"):
		var fd := Factions.get_data(String(who["leader"]))
		return "%s in %s" % [fd.leader_name, fd.leader_town] if fd != null else String(who["leader"])
	if who.has("spawn") or who.has("realm_npc"):
		return String(who.get("name", who.get("realm_npc", "someone")))
	return "someone"
