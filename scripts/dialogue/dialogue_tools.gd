class_name DialogueTools
extends RefCounted
## Checks for the dialogue, run from the debug console (and the lint at startup):
##   dialogue.audit     the person nearest you: every topic they list and why, the ones they don't,
##                      and their buttons
##   dialogue.report    every person of the nearest town: flags too many or too few topics
##   dialogue.lint      hand-written dialogue: empty answers, unknown {placeholders}, topics that
##                      can never be reached
##   dialogue.dupes     lines that are nearly the same (to merge into one topic with variants)

const TOO_FEW := 3
const TOO_MANY := 14


static func run(cmd: String, world: WorldManager, player: Node3D) -> String:
	match cmd:
		"audit":
			var s := nearest_speaker(world, player)
			return "\n".join(audit(s, world, player)) if s != null else "Nobody to talk to nearby."
		"report":
			var lines := report(world, world.get_nearest_town(player.global_position))
			return "\n".join(lines) if not lines.is_empty() else "Everyone has a sensible number of topics."
		"lint":
			var probs := lint()
			return "\n".join(probs) if not probs.is_empty() else "No problems in the hand-written dialogue."
		"dupes":
			var d := duplicates(world)
			return "\n".join(d) if not d.is_empty() else "No near-identical lines."
	return "dialogue.audit, dialogue.report, dialogue.lint, dialogue.dupes"


static func nearest_speaker(world: WorldManager, player: Node3D) -> DialogueEngine.Speaker:
	var best: Enemy = null
	for e in ActorRegistry.near(player.global_position, 12.0):
		if e.disposition != Enemy.Disposition.HOSTILE and not e.is_dead() and e.talk_name != "":
			if best == null or e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = e
	return DialogueEngine.speaker_for(best, world) if best != null else null


## Every known topic, and whether this person lists it (and why)
static func audit(s: DialogueEngine.Speaker, world: WorldManager, player: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var prof := DialogueEngine.profile_for(s, world)
	out.append("%s (%s): profile %s, cap %d, towns %d" % [s.name, NpcData.role_name(s.role), ", ".join(prof.roles), prof.cap, prof.towns])
	var shown := DialogueEngine.topics_for(s, world)
	var near := DialogueEngine._near_towns(s, world, prof.towns)
	for t in DialogueState.known_topics():
		var why := DialogueEngine._reason(s, t, world, prof, near)
		if shown.has(t):
			out.append("  + %s  (%s)" % [t, why])
		elif why == "named":
			out.append("  - %s  (cut by the cap)" % t)
	var buttons := PackedStringArray()
	for sv: Dictionary in Services.for_speaker(s, world, player):
		buttons.append(String(sv["label"]) + ("" if sv["why"] == "" else " (%s)" % sv["why"]))
	out.append("  buttons: " + (", ".join(buttons) if not buttons.is_empty() else "none"))
	return out


## People of a town whose topic list is too short or too long (if the player knew everything)
static func report(world: WorldManager, town: PlacedPOI) -> PackedStringArray:
	var out := PackedStringArray()
	if town == null or world.life == null:
		return out
	var known := DialogueState.known_topics()
	for e: Dictionary in DialogueEngine.index(world).entries.values():
		DialogueState.learn(String(e["name"]))
	for r: TownLife.Resident in world.life.get_town_residents(town.id):
		var s := DialogueEngine.Speaker.new()
		s.data = r.data
		s.id = r.data.id
		s.name = r.data.display_name
		s.role = r.data.role
		s.faction = r.data.faction
		s.town = r.town
		s.home = world.get_building(r.data.home_id)
		s.base_disposition = 100
		var n := DialogueEngine.topics_for(s, world).size()
		if n < TOO_FEW or n > TOO_MANY:
			out.append("%s (%s): %d topics" % [s.name, NpcData.role_name(s.role), n])
	WorldState.set_record(DialogueState.KNOWN, {"topics": Array(known)})
	return out


## Problems in the hand-written dialogue (DialogueData files and custom people)
static func lint() -> PackedStringArray:
	var out := PackedStringArray()
	var all: Array[DialogueData] = DialogueEngine._custom_data().duplicate()
	for c in CustomNpcs.all():
		if c.dialogue != null:
			all.append(c.dialogue)
	for d in all:
		var where := d.resource_path.get_file() if d.resource_path != "" else "custom NPC dialogue"
		var reachable := {}
		for t in d.topics:
			if t != null and t.learn_on_greeting:
				reachable[t.topic.to_lower()] = true
		for t in d.topics:
			if t == null:
				continue
			for r in t.responses:
				if r == null:
					continue
				for l in r.learn_topics:
					reachable[String(l).to_lower()] = true
				for l in r.choices:
					reachable[String(l).to_lower()] = true
				for t2 in d.topics:
					if t2 != null and r.text.to_lower().contains(t2.topic.to_lower()):
						reachable[t2.topic.to_lower()] = true
		for t in d.topics:
			if t == null:
				out.append("%s: an empty topic slot" % where)
				continue
			if t.topic.strip_edges() == "":
				out.append("%s: a topic with no name" % where)
			if t.responses.is_empty():
				out.append("%s: \"%s\" has no answers" % [where, t.topic])
			var generated := DialogueEngine.GENERIC.has(t.topic)
			if not reachable.has(t.topic.to_lower()) and not generated:
				out.append("%s: \"%s\" can never be learned (not learned on greeting, never mentioned)" % [where, t.topic])
			for r in t.responses:
				if r != null and r.text.strip_edges() == "":
					out.append("%s: \"%s\" has an empty answer" % [where, t.topic])
				if r != null:
					for ph in _placeholders(r.text):
						if not DialogueEngine.PLACEHOLDERS.has(ph):
							out.append("%s: \"%s\" uses an unknown placeholder %s" % [where, t.topic, ph])
	return out


static func _placeholders(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var at := text.find("{")
	while at >= 0:
		var end := text.find("}", at)
		if end < 0:
			break
		out.append(text.substr(at, end - at + 1))
		at = text.find("{", end)
	return out


## Pairs of lines that say nearly the same thing (by shared words)
static func duplicates(world: WorldManager) -> PackedStringArray:
	var lines: Array[String] = []
	for d in DialogueEngine._custom_data():
		for t in d.topics:
			if t != null:
				for r in t.responses:
					if r != null and r.text != "":
						lines.append(r.text)
	# a sample of generated answers from one town's people
	if world != null and world.life != null and not world.towns.is_empty():
		for r: TownLife.Resident in world.life.get_town_residents(world.towns[0].id).slice(0, 12):
			var s := DialogueEngine.Speaker.new()
			s.data = r.data
			s.id = r.data.id
			s.name = r.data.display_name
			s.role = r.data.role
			s.town = r.town
			s.home = world.get_building(r.data.home_id)
			s.base_disposition = 100
			for topic in ["background", "my trade", "small talk"]:
				lines.append(DialogueEngine._generic(s, topic, world))
	var out := PackedStringArray()
	var seen := {}
	for i in lines.size():
		for j in range(i + 1, lines.size()):
			if lines[i] == lines[j] or seen.has(lines[j]):
				continue
			if similarity(lines[i], lines[j]) >= 0.8:
				out.append("\"%s\"  ~  \"%s\"" % [lines[i].left(60), lines[j].left(60)])
				seen[lines[j]] = true
	return out


## 0..1: how many words two lines share
static func similarity(a: String, b: String) -> float:
	var wa := _words(a)
	var wb := _words(b)
	if wa.is_empty() or wb.is_empty():
		return 0.0
	var common := 0
	for w in wa:
		if wb.has(w):
			common += 1
	return float(common) / float(maxi(wa.size(), wb.size()))


static func _words(t: String) -> Dictionary:
	var out := {}
	for w in t.to_lower().replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").split(" ", false):
		out[w] = true
	return out
