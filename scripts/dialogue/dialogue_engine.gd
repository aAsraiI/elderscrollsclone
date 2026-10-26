class_name DialogueEngine
extends RefCounted
## What people say. Answers are generated from templates and the world itself (towns, buildings,
## neighbors, guilds, places nearby), worded by the speaker's personality, and always the same
## for the same person on the same day. Hand-written DialogueData can add topics or replace answers.
##
## Topics, Morrowind style: the player starts knowing a few general ones. Every topic name that
## appears in something said (a town, a person, a shop, a cave nearby) becomes a link and is
## learned. Each speaker only lists the known topics that fit who they are (PROFILES: a guard
## talks about the law and nearby dangers, a merchant about trade and the towns on the road...),
## at most a few named ones, always the same for the same person. "duties" and the other guild
## topics only show for the guild leaders who have them (QuestManager.extra_topics).

const DIALOGUE_DIR := "res://data/dialogue"
## Below this, people won't share rumors, advice or gossip
const TALK_MIN := 30
## Meters around a speaker they know (and gossip) about
const RUMOR_RANGE := 1300.0
const FACTIONS := {
	"Fighters Guild": "fighters",
	"Mages Guild": "mages",
	"Knightly Order": "knights",
	"Thieves Guild": "thieves",
	"Assassins Cult": "assassins",
}
const GENERIC := ["background", "my trade", "latest rumors", "little advice", "duties", "membership", "advancement", "clear bounty", "a delivery", "the law"]


## Who is talking: built from an Enemy body (and its NpcData, for townspeople)
class Speaker:
	## Disposition key ("" = not remembered, "temp:..." = this session only)
	var id := ""
	var name := "Stranger"
	var role: NpcData.Role = NpcData.Role.COMMONER
	var personality: NpcData.Personality = NpcData.Personality.FRIENDLY
	var faction := ""
	var base_disposition := 50
	var level := 1
	var town: PlacedPOI
	var home: BuildingPlot
	var data: NpcData
	var enemy: Enemy
	var asleep := false
	## Where they are in the world (a building's position while indoors), for directions
	var position := Vector3.ZERO
	## Travelers' own lines (EnemyData talk lines)
	var lines: PackedStringArray = []
	## A hand-made person (CustomNpcData) who only talks about their own topics
	var own_topics_only := false


## The searchable list of every topic name in this world
class Index:
	var key := ""
	var entries := {}          # lower-case name -> {"name", "kind", ...}
	var by_length: Array[String] = []   # lower-case names, longest first (for finding them in text)


static var _index: Index
static var _custom: Array[DialogueData] = []
static var _custom_loaded := false


# ---------------------------------------------------------------- speakers

static func speaker_for(e: Enemy, world: WorldManager) -> Speaker:
	var s := Speaker.new()
	s.enemy = e
	s.name = e.display_name
	s.level = e.level
	s.position = e.global_position
	s.asleep = bool(e.get_meta("asleep", false))
	s.lines = e.talk_lines
	s.base_disposition = 55 if e.disposition == Enemy.Disposition.FRIENDLY else 45
	var custom := e.get_meta("custom_npc") as CustomNpcData if e.has_meta("custom_npc") else null
	if custom != null:
		# a hand-made person (CustomNpcs): their own sheet and dialogue
		s.data = custom.to_npc_data()
		s.id = s.data.id
		s.name = custom.display_name
		s.role = custom.role
		s.personality = custom.personality
		s.faction = custom.faction
		s.base_disposition = custom.base_disposition
		s.own_topics_only = not custom.generated_topics
		if world != null:
			s.town = world.get_nearest_town(s.position)
		return s
	var npc_id := String(e.get_meta("npc_id", ""))
	if npc_id != "" and world != null and world.life != null:
		var r := world.life.get_resident(npc_id)
		if r != null:
			s.data = r.data
			s.id = npc_id
			s.name = r.data.display_name
			s.role = r.data.role
			s.personality = r.data.personality
			s.faction = r.data.faction
			s.base_disposition = r.data.base_disposition
			s.town = r.town
			s.home = world.get_building(r.data.home_id)
			if r.inside != "":
				var b := world.get_building(r.inside)
				if b != null:
					s.position = b.world_pos
			return s
	# A traveler on the road: remembered for this session only
	s.id = "temp:%s" % (e.spawn_key if e.spawn_key != "" else str(e.get_instance_id()))
	s.personality = (absi(s.name.hash()) % NpcData.Personality.size()) as NpcData.Personality
	if world != null:
		s.town = world.get_nearest_town(s.position)
	return s


static func get_disposition(s: Speaker) -> int:
	return DialogueState.get_disposition(s.id, s.base_disposition)


# ---------------------------------------------------------------- the topic index

static func index(world: WorldManager) -> Index:
	var key := "none"
	if world != null:
		key = "%d|%d|%d" % [world.get_instance_id(), world.world_seed, world.pois.size()]
	if _index != null and _index.key == key:
		return _index
	var ix := Index.new()
	ix.key = key
	for g in GENERIC:
		_add(ix, g, {"kind": "generic"})
	for f in FACTIONS:
		_add(ix, f, {"kind": "faction", "faction": FACTIONS[f]})
	if world != null:
		for t in world.towns:
			if t.town == null:
				continue
			_add(ix, t.town.display_name, {"kind": "town", "town": t})
			for b in t.town.buildings:
				_add_list(ix, b.display_name, "place", "buildings", b)
				_add_list(ix, b.owner_name, "person", "people", b)
		for p in world.pois:
			if p.poi is TownData:
				continue
			var name := poi_topic_name(world, p)
			if name != "":
				_add_list(ix, name, "poi", "pois", p)
	for d in _custom_data():
		for t in d.topics:
			if t != null and t.topic != "" and not ix.entries.has(t.topic.to_lower()):
				_add(ix, t.topic, {"kind": "custom"})
	ix.by_length.assign(ix.entries.keys())
	ix.by_length.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	_index = ix
	return ix


static func _add(ix: Index, name: String, entry: Dictionary) -> void:
	if name.strip_edges() == "":
		return
	entry["name"] = name
	ix.entries[name.to_lower()] = entry


# Several things can share a name ("Fighters Guild Hall" in every city): keep them all
static func _add_list(ix: Index, name: String, kind: String, field: String, thing: Variant) -> void:
	var low := name.to_lower()
	if low.strip_edges() == "":
		return
	var e: Dictionary = ix.entries.get(low, {})
	if e.is_empty() or e.get("kind") != kind:
		if not e.is_empty():
			return  # the name is already something else (a generic topic or a faction)
		e = {"name": name, "kind": kind, field: []}
		ix.entries[low] = e
	(e[field] as Array).append(thing)


## "Bandit Camp east of Dunwatch": how people name a place out in the wild
static func poi_topic_name(world: WorldManager, p: PlacedPOI) -> String:
	var t := world.get_nearest_town(p.position)
	if t == null or t.town == null:
		return ""
	var d := Vector2(p.position.x - t.position.x, p.position.z - t.position.z)
	if d.length() > RUMOR_RANGE * 1.5:
		return ""
	return "%s %s of %s" % [p.poi.display_name, compass(d), t.town.display_name]


## Every topic name found in a piece of text (each once, in the order they appear)
static func find_topics(text: String, ix: Index) -> Array[Dictionary]:
	var low := text.to_lower()
	var taken := PackedByteArray()
	taken.resize(low.length())
	var found: Array[Dictionary] = []
	for name in ix.by_length:
		var from := 0
		while true:
			var at := low.find(name, from)
			if at < 0:
				break
			from = at + 1
			var end := at + name.length()
			var free := true
			for i in range(at, end):
				if taken[i] == 1:
					free = false
					break
			if not free:
				continue
			if at > 0 and _is_word_char(low[at - 1]):
				continue
			if end < low.length() and _is_word_char(low[end]):
				continue
			for i in range(at, end):
				taken[i] = 1
			found.append({"at": at, "end": end, "name": ix.entries[name]["name"]})
			break
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
	return found


static func _is_word_char(c: String) -> bool:
	return c.is_valid_identifier() or c.is_valid_int() or c == "'"


# ---------------------------------------------------------------- hand-written dialogue

static func _custom_data() -> Array[DialogueData]:
	if not _custom_loaded:
		_custom_loaded = true
		var names := PackedStringArray()
		for f in DirAccess.get_files_at(DIALOGUE_DIR):
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres") and not names.has(file):
				names.append(file)
		names.sort()
		for file in names:
			var d := load(DIALOGUE_DIR + "/" + file) as DialogueData
			if d != null:
				_custom.append(d)
	return _custom


static func _custom_for(s: Speaker) -> Array[DialogueData]:
	var out: Array[DialogueData] = []
	if s.data != null and s.data.dialogue != null:
		out.append(s.data.dialogue)
	for d in _custom_data():
		if d.applies_to(s.id, s.role):
			out.append(d)
	return out


## Hand-written topics a speaker has that the player learns just by greeting them
static func greeting_topics(s: Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	for d in _custom_for(s):
		for t in d.topics:
			if t != null and t.learn_on_greeting:
				out.append(t.topic)
	return out


# ---------------------------------------------------------------- what they know

## What each kind of person talks about (Alpha 1.12): their general topics, the kinds of named
## topic they know, how many other towns they talk about (the nearest), and the most named topics
## they list. Quest, guild and hand-written topics are always listed on top of these.
##   home: their own town   towns: other towns   place / person: buildings and people of their
##   town   poi: places in the wild nearby   guilds: every guild   own_guild: only their own
const PROFILES := {
	"commoner": {"generic": ["background", "my trade", "latest rumors", "little advice"], "kinds": ["home", "towns", "place", "person", "poi"], "towns": 2, "cap": 6},
	"worker": {"generic": ["background", "my trade", "latest rumors", "little advice"], "kinds": ["home", "towns", "person", "poi"], "towns": 1, "cap": 5},
	"merchant": {"generic": ["background", "my trade", "latest rumors"], "kinds": ["home", "towns", "place", "person"], "towns": 3, "cap": 6},
	"innkeeper": {"generic": ["background", "my trade", "latest rumors", "little advice"], "kinds": ["home", "towns", "place", "poi", "guilds"], "towns": 5, "cap": 8},
	"guard": {"generic": ["background", "my trade", "the law", "latest rumors"], "kinds": ["home", "towns", "place", "poi"], "towns": 3, "cap": 8},
	"priest": {"generic": ["background", "my trade", "little advice"], "kinds": ["home", "place", "person"], "towns": 0, "cap": 5},
	"guild": {"generic": ["background", "my trade", "latest rumors"], "kinds": ["home", "towns", "place", "own_guild"], "towns": 2, "cap": 6},
	"lord": {"generic": ["background", "my trade", "the law", "latest rumors"], "kinds": ["home", "towns", "place", "poi", "guilds"], "towns": 6, "cap": 10},
	"traveler": {"generic": ["background", "latest rumors", "little advice"], "kinds": ["towns", "poi"], "towns": 3, "cap": 5},
}


## The PROFILES entry for this speaker
static func profile_for(s: Speaker) -> Dictionary:
	if s.data == null:
		return PROFILES["traveler"]
	match s.role:
		NpcData.Role.MERCHANT, NpcData.Role.SMITH:
			return PROFILES["merchant"]
		NpcData.Role.INNKEEPER:
			return PROFILES["innkeeper"]
		NpcData.Role.GUARD:
			return PROFILES["guard"]
		NpcData.Role.PRIEST:
			return PROFILES["priest"]
		NpcData.Role.GUILD_MEMBER:
			return PROFILES["guild"]
		NpcData.Role.LORD:
			return PROFILES["lord"]
		NpcData.Role.FARMER, NpcData.Role.WOODCUTTER, NpcData.Role.FISHERMAN, NpcData.Role.HUNTER, NpcData.Role.MINER, NpcData.Role.HERBALIST:
			return PROFILES["worker"]
	return PROFILES["commoner"]


## The known topics this speaker can talk about, sorted (general ones first, then quest and
## hand-written ones, then named topics: at most the profile's cap, the same ones every visit)
static func topics_for(s: Speaker, world: WorldManager) -> PackedStringArray:
	var general := PackedStringArray()
	var special := PackedStringArray()
	var named: Array[String] = []
	# Quest topics (a written quest's hook, the next thing to ask) are known as soon as the person
	# who has them is met
	if world != null and world.book != null and not s.asleep:
		for t in world.book.topics_for(s):
			DialogueState.learn(t)
		if Factions.leader_of(s, world) in ClanTerritory.CLANS:
			DialogueState.learn("the territory war")
		if world.quests != null:
			for t in world.quests.extra_topics(s):  # a choice or a reward that just became possible
				DialogueState.learn(t)
	var prof := profile_for(s)
	var near := _near_towns(s, world, int(prof["towns"]))
	for t in DialogueState.known_topics():
		var why := _reason(s, t, world, prof, near)
		match why:
			"generic":
				general.append(t)
			"special":
				special.append(t)
			"named":
				named.append(t)
	# keep the cap: their own town and guild first, then a choice of their own (stable per person)
	named.sort_custom(func(a: String, b: String) -> bool:
		var pa := _priority(s, a)
		var pb := _priority(s, b)
		if pa != pb:
			return pa < pb
		return _stable(s, a) < _stable(s, b))
	named = named.slice(0, int(prof["cap"]))
	named.sort()
	special.sort()
	var ordered := PackedStringArray()
	for g in GENERIC:
		if general.has(g):
			ordered.append(g)
	ordered.append_array(special)
	ordered.append_array(PackedStringArray(named))
	return ordered


## Would this speaker list the topic (if the player knew it)? Named topics also have to make the cap.
static func can_discuss(s: Speaker, topic: String, world: WorldManager) -> bool:
	var prof := profile_for(s)
	var why := _reason(s, topic, world, prof, _near_towns(s, world, int(prof["towns"])))
	return why != "" and (why != "named" or topics_for(s, world).has(topic))


# Why this speaker lists a topic: "generic", "special" (quest, guild, hand-written: never cut),
# "named" (counts toward the cap) or "" (not theirs to talk about)
static func _reason(s: Speaker, topic: String, world: WorldManager, prof: Dictionary, near: Array) -> String:
	for d in _custom_for(s):
		var t := d.get_topic(topic)
		if t != null and t.pick(get_disposition(s)) != null:
			return "special"
	# Guild leaders' topics (membership, duties, advancement...), job topics and the main story's,
	# marriage's and the homestead's topics: only for those who have them, and never cut
	var extra := world.quests.extra_topics(s) if world != null and world.quests != null else PackedStringArray()
	if extra.has(topic):
		return "special"
	if QuestManager.TOPICS.has(topic):
		return ""
	if world != null and world.book != null and world.book.topics_for(s).has(topic):
		return "special"
	if s.own_topics_only:
		return ""
	var e: Dictionary = index(world).entries.get(topic.to_lower(), {})
	var kinds: Array = prof["kinds"]
	match String(e.get("kind", "")):
		"generic":
			return "generic" if (prof["generic"] as Array).has(topic) else ""
		"faction":
			if kinds.has("guilds") or (kinds.has("own_guild") and s.faction == String(e["faction"])):
				return "named"
			return ""
		"town":
			var t: PlacedPOI = e["town"]
			if s.town == t:
				return "named" if kinds.has("home") else ""
			return "named" if kinds.has("towns") and near.has(t) else ""
		"place", "person":
			if not kinds.has(String(e["kind"])):
				return ""
			var list: Array = e.get("buildings", e.get("people", []))
			for b: BuildingPlot in list:
				if s.town != null and b.town_id == s.town.id:
					return "named"
			return ""
		"poi":
			if not kinds.has("poi"):
				return ""
			for p: PlacedPOI in e["pois"]:
				if Vector2(p.position.x - s.position.x, p.position.z - s.position.z).length() < RUMOR_RANGE:
					return "named"
			return ""
	return ""


# The other towns this speaker knows about: the nearest few
static func _near_towns(s: Speaker, world: WorldManager, count: int) -> Array:
	if world == null or count <= 0:
		return []
	var others: Array = world.towns.filter(func(t: PlacedPOI) -> bool: return t != s.town)
	var at := s.town.position if s.town != null else s.position
	others.sort_custom(func(a: PlacedPOI, b: PlacedPOI) -> bool:
		return a.position.distance_squared_to(at) < b.position.distance_squared_to(at))
	return others.slice(0, count)


# Lower comes first when the cap cuts: their own town, their own guild, then the rest
static func _priority(s: Speaker, topic: String) -> int:
	if s.town != null and s.town.town != null and topic == s.town.town.display_name:
		return 0
	if s.faction != "" and FACTIONS.get(topic, "") == s.faction:
		return 1
	return 2


# A number from the person and the topic that never changes (their own choice of what to talk about)
static func _stable(s: Speaker, topic: String) -> int:
	return absi(("%s|%s|%s" % [s.id, s.name, topic]).hash())


# ---------------------------------------------------------------- greetings

static func greeting(s: Speaker, world: WorldManager) -> String:
	var disp := get_disposition(s)
	if s.enemy != null and is_instance_valid(s.enemy) and s.enemy.has_meta("greeting"):
		return String(s.enemy.get_meta("greeting"))  # a special person's own words (the Assassins Cult's contacts)
	if s.asleep:
		return "Wha-? Who's there? What are you doing in here? ...Fine. What do you want?"
	var clock: WorldClock = world.clock if world != null else null
	var remembered := NpcMemory.greeting(s, clock.day if clock != null else 1)
	if remembered != "":
		return remembered  # something they remember about you (NpcMemory)
	var hour := clock.hour if clock != null else 12.0
	var time_word := "Good morning" if hour < 12.0 else ("Good afternoon" if hour < 18.0 else "Good evening")
	if disp < TALK_MIN:
		return ["What do you want?", "Make it quick.", "I've nothing to say to you."][_pick(s, "greet", 3)]
	var where := s.town.town.display_name if s.town != null and s.town.town != null else "these parts"
	match s.personality:
		NpcData.Personality.GRUMPY:
			return "Hmph. %s, I suppose. What is it?" % time_word
		NpcData.Personality.NERVOUS:
			return "Oh! %s. You gave me a start." % time_word
		NpcData.Personality.PROUD:
			return "%s, stranger. You're not from %s, I take it." % [time_word, where]
		NpcData.Personality.PIOUS:
			return "%s, and blessings on you." % time_word
		NpcData.Personality.CHEERFUL:
			return "%s! Lovely to see a new face in %s!" % [time_word, where]
	return "%s, traveler. Welcome to %s." % [time_word, where]


# ---------------------------------------------------------------- answers

## The answer to a topic: {"text", "journal" (bool: worth writing down), "quest_id", "quest_name",
## "learn" (extra topics), "response" (DialogueResponse when hand-written)}
static func respond(s: Speaker, topic: String, world: WorldManager) -> Dictionary:
	var disp := get_disposition(s)
	if world != null and world.quests != null and not s.asleep:
		var job := world.quests.respond(s, topic)  # guild membership and jobs
		if not job.is_empty():
			return job
	for d in _custom_for(s):
		var t := d.get_topic(topic)
		var r: DialogueResponse = t.pick(disp) if t != null else null
		if r != null:
			return {"text": _fill(r.text, s), "journal": true, "quest_id": r.quest_id, "quest_name": r.quest_name,
				"learn": r.learn_topics, "response": r}
	if s.asleep and not ["background", "my trade"].has(topic):
		return _say("Mmh... ask me tomorrow. I'm trying to sleep.", false)
	if disp < TALK_MIN and not ["background", "my trade", "duties"].has(topic):
		return _say(["I don't have time for you.", "Why would I tell you anything?", "Go bother someone else."][_pick(s, topic, 3)], false)
	var e: Dictionary = index(world).entries.get(topic.to_lower(), {})
	var text := ""
	match String(e.get("kind", "")):
		"generic":
			text = _generic(s, topic, world)
		"town":
			text = _about_town(s, e["town"], world)
		"place":
			text = _about_place(s, e["buildings"], world)
		"person":
			text = _about_person(s, e["people"], world)
		"faction":
			text = _about_faction(s, String(e["faction"]), world)
		"poi":
			text = _about_poi(s, e["pois"])
	if text == "":
		return _say("I don't know anything about that.", false)
	return _say(_voice(s, text, topic), true)


static func _say(text: String, journal: bool) -> Dictionary:
	return {"text": text, "journal": journal, "quest_id": "", "quest_name": "", "learn": PackedStringArray()}


# Personality: a few words before or after
static func _voice(s: Speaker, text: String, topic: String) -> String:
	var k := _pick(s, "voice" + topic, 3)
	match s.personality:
		NpcData.Personality.GRUMPY:
			return text + ["", " Now leave me be.", " Happy?"][k]
		NpcData.Personality.NERVOUS:
			return ["W-well... ", "", "Um. "][k] + text
		NpcData.Personality.CHEERFUL:
			return ["Oh, ", "", "Ha! "][k] + text
		NpcData.Personality.PIOUS:
			return text + ["", " The gods see all.", ""][k]
		NpcData.Personality.PROUD:
			return ["Everyone knows this: ", "", ""][k] + text
	return text


static func _fill(text: String, s: Speaker) -> String:
	var town := s.town.town.display_name if s.town != null and s.town.town != null else "town"
	return text.replace("{name}", s.name).replace("{town}", town)


static func _generic(s: Speaker, topic: String, world: WorldManager) -> String:
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	var home := s.home.display_name if s.home != null else ""
	match topic:
		"background":
			if s.data == null:
				return s.lines[0] if not s.lines.is_empty() else "Just a traveler. The road is my home."
			match s.role:
				NpcData.Role.GUARD:
					return "I'm one of the guard of %s. Born here, and I'll likely die here." % town
				NpcData.Role.FARMER:
					return "I'm %s. I keep %s, just outside %s, same as my parents did." % [s.name, home, town]
			return "I'm %s, %s here in %s. I live at %s." % [s.name, NpcData.role_name(s.role).to_lower(), town, home]
		"my trade":
			match s.role:
				NpcData.Role.MERCHANT:
					return "I run %s. Have a look at my wares, and if you've anything worth selling, I'm buying." % home
				NpcData.Role.INNKEEPER:
					return "I keep %s: food, drink, and a warm hearth. Rooms soon." % home
				NpcData.Role.SMITH:
					return "I work the forge at %s. Blades, armor, horseshoes." % home
				NpcData.Role.PRIEST:
					return "I tend %s and the people who come to it." % home
				NpcData.Role.GUILD_MEMBER:
					var fname := _faction_name(s.faction)
					return "I'm with the %s. We keep %s." % [fname, home] if fname != "" else "I keep %s." % home
				NpcData.Role.WOODCUTTER:
					return "Wood for every hearth in %s. Somebody has to cut it." % town
				NpcData.Role.FISHERMAN:
					return "Out on the water at first light, nets mended by dark. The fish don't wait."
				NpcData.Role.HUNTER:
					return "Deer, boar, the odd wolf. I sell the hides and keep the stories."
				NpcData.Role.MINER:
					return "Iron and copper, mostly. The hills give up their ore, slowly."
				NpcData.Role.HERBALIST:
					return "Roots and leaves. Half the potions in %s start in my garden." % town
				NpcData.Role.FARMER:
					return "Crops and animals. Up before dawn, in bed after dark."
				NpcData.Role.GUARD:
					return "Keeping the peace in %s. Ask me about the law if you're unsure of it." % town
				NpcData.Role.LORD:
					if s.home != null and s.home.seat_type == "reeve":
						return "The village chose me as its reeve. I keep %s: the tithes, the disputes, the roof on the mill." % town
					return "I hold %s from %s. Petitions are heard here by day, and the law of these lands is mine to keep." % [town, home]
			if s.data == null:
				return "I go where the road takes me."
			return "Odd jobs around %s. Whatever pays." % town
		"latest rumors":
			return _rumor(s, world)
		"little advice":
			var tips := [
				"Carry lockpicks. Every one that breaks teaches your hands something.",
				"Eat a proper meal before a long walk. A full belly heals you slowly for a good while.",
				"Keep a potion handy and drink it quick when it counts.",
				"Doors get locked at night. If you need a shopkeeper, come by day.",
				"Follow the roads between towns. The wild has teeth.",
				"Caves and crypts hold treasure, and the things guarding it.",
				"Save your strength for a heavy swing when an enemy is staggered.",
			]
			return tips[_pick(s, "advice", tips.size())]
		"duties":
			if s.role == NpcData.Role.GUILD_MEMBER and s.faction != "":
				return "The %s may have work for you before long. Not yet, though." % _faction_name(s.faction)
			return "I've no work for you. Maybe another time."
		"the law":
			if s.role == NpcData.Role.GUARD:
				return "Steal or kill in %s and you'll answer to us. We see more than you think." % town
			if s.role == NpcData.Role.LORD:
				var owed := CrimeManager.get_bounty(s.town.id) if s.town != null else 0
				if owed > 0:
					return "You owe %d gold to %s. Pay my guards, or answer for it in my cells." % [owed, town]
				return "In %s the law is mine, and my guards carry it out. Keep to it and we will have no quarrel." % town
			return "Ask a guard about the law. They'll be glad to tell you."
	return ""


static func _rumor(s: Speaker, world: WorldManager) -> String:
	if world == null:
		return ""
	var near: Array[PlacedPOI] = []
	for p in world.get_pois_near(s.position, RUMOR_RANGE):
		if not p.poi is TownData and poi_topic_name(world, p) != "":
			near.append(p)
	var k := _pick(s, "rumor", 10)
	if not near.is_empty() and k < 7:
		var p := near[_pick(s, "rumor_poi", near.size())]
		var name := poi_topic_name(world, p)
		if p.poi.garrison != null:
			return "They say there's trouble at the %s. Folk have seen armed strangers about." % name
		if p.poi is DungeonEntrancePOIData:
			return "A hunter swore he heard voices from the %s. Nobody has gone to look." % name
		return "Have you been to the %s? Odd place. Quiet." % name
	# another town, or a neighbor
	var other := world.get_nearest_town(s.position + Vector3(900, 0, 0) if k % 2 == 0 else s.position - Vector3(900, 0, 0))
	if other != null and other != s.town and other.town != null:
		return "Merchants say %s is doing well these days. More folk on the road every week." % other.town.display_name
	if s.town != null and s.town.town != null and not s.town.town.buildings.is_empty():
		var list := s.town.town.buildings
		var first := _pick(s, "gossip", list.size())
		for step in list.size():  # skip their own house
			var b := list[(first + step) % list.size()]
			if b.owner_name != s.name:
				return "Between us, %s has been keeping odd hours lately." % b.owner_name
	return "Nothing worth repeating, I'm afraid."


static func _about_town(s: Speaker, t: PlacedPOI, world: WorldManager) -> String:
	var layout := t.town
	var kind: String = ["village", "town", "city"][int((t.poi as TownData).kind)]
	var biome: BiomeData = world.get_biome_at(t.position.x, t.position.z) if world != null else null
	var land := biome.display_name.to_lower() if biome != null else "wilds"
	if s.town == t:
		var notable := PackedStringArray()
		for b in layout.buildings:
			if b.is_public() and notable.size() < 3:
				notable.append(b.display_name)
		var text := "%s is a %s in the %s." % [layout.display_name, kind, land]
		if not notable.is_empty():
			text += " You'll find %s here." % _list(notable)
		return text
	var d := Vector2(t.position.x - s.position.x, t.position.z - s.position.z)
	return "%s? A %s %s to the %s. Follow the road and you can't miss it." % [layout.display_name, kind, distance_words(d.length()), compass(d)]


static func _about_place(s: Speaker, list: Array, world: WorldManager) -> String:
	var b: BuildingPlot = null
	for c: BuildingPlot in list:
		if s.town != null and c.town_id == s.town.id:
			b = c
	if b == null:
		return ""
	if s.home == b:
		return "That's my own place. You're welcome there when the door's open."
	var d := Vector2(b.world_pos.x - s.position.x, b.world_pos.z - s.position.z)
	var text := "%s is %s." % [b.display_name, "just here" if d.length() < 12.0 else "%s to the %s" % [distance_words(d.length()), compass(d)]]
	var owner: TownLife.Resident = world.life.get_owner_of(b.id) if world != null and world.life != null else null
	if b.is_public():
		text += " %s runs it" % b.owner_name
		if owner != null:
			text += ", open from %s to %s" % [Residents._hour(owner.data.work_start), Residents._hour(owner.data.work_end)]
		text += "."
	else:
		text += " That's where %s lives." % b.owner_name
	return text


static func _about_person(s: Speaker, list: Array, world: WorldManager) -> String:
	var b: BuildingPlot = null
	for c: BuildingPlot in list:
		if s.town != null and c.town_id == s.town.id:
			b = c
	if b == null:
		return ""
	if b.owner_name == s.name:
		return "That's me. What about me?"
	var owner: TownLife.Resident = world.life.get_owner_of(b.id) if world != null and world.life != null else null
	if owner != null and owner.dead:
		return "%s... was found dead. Terrible business. Nobody knows who did it." % b.owner_name
	var role := NpcData.role_name(NpcData.role_for(b.kind)).to_lower()
	var text := "%s? The %s at %s." % [b.owner_name, role, b.display_name] if b.is_public() else "%s lives at %s." % [b.owner_name, b.display_name]
	var opinions := ["Good sort.", "Keeps to themselves.", "Owes me money, still.", "We grew up together.", "I wouldn't trust them with my purse.", "Never a harsh word from them."]
	return text + " " + opinions[absi(("%s|%s" % [s.name, b.owner_name]).hash()) % opinions.size()]


static func _about_faction(s: Speaker, faction: String, world: WorldManager) -> String:
	var name := _faction_name(faction)
	var text := ""
	match faction:
		"fighters":
			text = "The %s hires out good swords for honest work: guarding, hunting, clearing out pests." % name
		"mages":
			text = "The %s keeps old books and older secrets. They study magic, though few of them will show you any." % name
		"knights":
			text = "The %s swears to protect the roads and the realm. Proud folk, but brave." % name
		"thieves":
			if Factions.leader_of(s, world) == "thieves" or Factions.is_member("thieves"):
				return "You're talking to the right person. Ask me about membership, quietly."
			return "Thieves? There's no such guild. Though they say the pawnbrokers in the cities hear things."
		"assassins":
			if Factions.leader_of(s, world) == "assassins":
				return "You found us. Or we found you. Ask about membership."
			return ["Don't say that name out loud.", "The Assassins Cult? A story to scare children. ...Isn't it?", "Some say they find you, after you kill. I'd rather not know."][_pick(s, "assassins", 3)]
	var hall := ""
	if s.town != null and s.town.town != null:
		for b in s.town.town.buildings:
			if b.guild == faction:
				hall = b.display_name
	if hall != "":
		text += " Their hall here is the %s." % hall
	else:
		text += " They keep a hall in every city."
	if s.faction == faction:
		text += " I'm a member myself."
	return text


static func _about_poi(s: Speaker, list: Array) -> String:
	var p: PlacedPOI = null
	for c: PlacedPOI in list:
		if Vector2(c.position.x - s.position.x, c.position.z - s.position.z).length() < RUMOR_RANGE:
			p = c
	if p == null:
		return ""
	var d := Vector2(p.position.x - s.position.x, p.position.z - s.position.z)
	var text := "It's %s to the %s." % [distance_words(d.length()), compass(d)]
	if p.poi.garrison != null:
		text += " Bandits or worse hole up there. Go armed, or don't go."
	elif p.poi is DungeonEntrancePOIData:
		text += " It goes deep underground. Nobody who goes down comes back quite the same."
	else:
		text += " A quiet spot. Some say it's older than the towns."
	return text


# ---------------------------------------------------------------- words

## "north", "south-east" ... for a flat direction (x = east, y = south)
static func compass(d: Vector2) -> String:
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var a := fposmod(atan2(d.y, d.x), TAU)
	return names[int(round(a / (TAU / 8.0))) % 8]


static func distance_words(m: float) -> String:
	if m < 150.0:
		return "a short walk"
	if m < 1000.0:
		return "about %d meters" % (int(round(m / 50.0)) * 50)
	return "about %.1f km" % (m / 1000.0)


static func _faction_name(faction: String) -> String:
	for f in FACTIONS:
		if FACTIONS[f] == faction:
			return f
	return ""


static func _list(items: PackedStringArray) -> String:
	if items.size() <= 1:
		return "".join(items)
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + items[items.size() - 1]


# A stable choice for this speaker, topic and day
static func _pick(s: Speaker, what: String, count: int) -> int:
	var day := 1
	var clock: WorldClock = s.enemy.get_tree().get_first_node_in_group("world_clock") as WorldClock if s.enemy != null and s.enemy.is_inside_tree() else null
	if clock != null:
		day = clock.day
	return absi(("%s|%s|%s|%d" % [s.id, s.name, what, day]).hash()) % maxi(count, 1)
