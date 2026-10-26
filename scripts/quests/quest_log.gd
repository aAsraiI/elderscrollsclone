class_name QuestLog
extends RefCounted
## Every quest of every kind in one list, the same shape for each, for the journal's Quests tab,
## the on-screen tracker and the pause screen: guild jobs and bounties (QuestManager), written
## quests (QuestBook), handmade quests (QuestRunner) and the main story (Story).
##
## Each: {"id", "name", "status" (active / completed / failed / abandoned), "source" (job, book,
## runner, story), "guild", "giver", "description", "objectives": [{"text", "done"}],
## "next" (the next thing to do), "rewards", "why" (why it failed)}

static func all(world: WorldManager) -> Array:
	var out: Array = []
	for q: Dictionary in QuestManager.all_quests():
		var st := String(q["status"])
		var status := "completed" if st == "done" else st
		var ready := status == "active" and world != null and world.quests != null and world.quests.is_ready(q)
		out.append({"id": String(q["id"]), "name": String(q["name"]), "status": status, "source": "job",
			"guild": String(q.get("faction", "")), "giver": "%s, %s" % [q.get("giver_name", ""), q.get("giver_town", "")],
			"description": String(q.get("objective", "")),
			"objectives": [{"text": String(q.get("objective", "")), "done": ready or status == "completed"}],
			"next": ("Report back to %s (ask about \"report back\")." % q.get("giver_name", "them")) if ready else String(q.get("objective", "")),
			"rewards": "%d gold" % int(q.get("reward", 0)), "why": String(q.get("fail_reason", "")), "day": int(q.get("offered_day", 0))})
	for id in QuestBook.ids():
		var st := QuestBook.status(id)
		if st == "":
			continue
		var d := QuestBook.get_def(id)
		var steps: Array = d["steps"]
		var at := int(QuestBook.state(id).get("step", 0))
		var objectives: Array = []
		for i in steps.size():
			if i > at and st == "active":
				break
			var text := String(steps[i].get("text", ""))
			if text != "":
				objectives.append({"text": text, "done": i < at or st == "done"})
		var r: Dictionary = d.get("reward", {})
		out.append({"id": id, "name": String(d["name"]), "status": "completed" if st == "done" else st, "source": "book",
			"guild": String(d.get("faction", "")), "giver": String(d.get("group", "")), "description": String(d["intro"]),
			"objectives": objectives, "next": QuestDebug.book_step_text(world.book, id) if world != null and world.book != null and st == "active" else "",
			"rewards": "%d gold" % int(r.get("gold", 0)), "why": String(QuestBook.state(id).get("fail_reason", "")), "day": 0})
	if world != null and world.runner != null:
		for d in QuestRunner.all():
			var st := String(QuestRunner.record(d.id).get("state", ""))
			if st in ["", "available", "unavailable"]:
				continue
			var objectives: Array = []
			for o: Dictionary in world.runner.objectives_view(d.id):
				objectives.append({"text": String(o["text"]) + ("" if int(o["need"]) <= 1 else " (%d/%d)" % [o["have"], o["need"]]) + (" (optional)" if o["optional"] else ""), "done": o["done"]})
			if st == "completed":  # finished: every stage's objectives, all done
				for stage in d.stages:
					for o in stage.objectives:
						if not o.hidden:
							objectives.append({"text": world.runner._objective_text(d, o), "done": true})
			out.append({"id": d.id, "name": d.title, "status": "active" if st == "ready" else st, "source": "runner",
				"guild": d.reward_rep_with if Factions.get_data(d.reward_rep_with) != null else "", "giver": person_name(d.giver),
				"description": d.description if d.description != "" else d.intro, "objectives": objectives,
				"next": world.runner.next_step(d.id), "rewards": world.runner.reward_text(d), "why": String(QuestRunner.record(d.id).get("why", "")), "day": 0})
	var story := Story.stage()
	if story > 0:
		var steps := ["Take the sealed letter to the priest.", "Clear the dungeon where the Ash Cult hunts the Eclipse Codex.",
			"Take the Codex to a master of the Mages Guild.", "Kill the Ash Hierophant at the ritual site.", "Return to the priest."]
		var objectives: Array = []
		for i in mini(story, 5):
			objectives.append({"text": steps[i], "done": i + 1 < story})
		out.append({"id": Story.ID, "name": Story.NAME, "status": "completed" if story >= 6 else "active", "source": "story",
			"guild": "", "giver": "The main quest", "description": "The sun is in danger.", "objectives": objectives,
			"next": steps[mini(story, 5) - 1] if story < 6 else "", "rewards": "", "why": "", "day": 0})
	return out


static func find(world: WorldManager, id: String) -> Dictionary:
	for q: Dictionary in all(world):
		if q["id"] == id:
			return q
	return {}


## Gives up a quest of any kind
static func abandon(world: WorldManager, id: String) -> void:
	var job := QuestManager.get_quest(id)
	if not job.is_empty():
		world.quests.abandon(job)
	elif QuestBook.is_active(id):
		world.book.abandon(id)
	elif QuestRunner.get_data(id) != null:
		world.runner.abandon(id)


## A person id as a name ("custom/example_hermit" -> "Old Maudrey", "Name@Town" -> "Name")
static func person_name(who: String) -> String:
	for c in CustomNpcs.all():
		if c.save_id() == who:
			return c.display_name
	return who.get_slice("@", 0)
