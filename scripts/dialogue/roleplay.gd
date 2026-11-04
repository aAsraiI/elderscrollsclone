class_name Roleplay
extends RefCounted
## Alpha 1.26: dialogue that knows who you are, and gives you room to play a part.
##   asides     now and then a greeting has a word about your race, your class or your past (the
##              same person always says the same thing)
##   lying      someone who saw you commit a crime can be lied to ("what you saw"): a Speech and
##              charisma check, the chance shown. It works: they doubt their eyes and forget it.
##              It fails: they like you less and the guard hears of it (a small bounty)
##   vows       a priest will hear a vow ("take a vow"): peace (kill nothing for three days) or
##              poverty (give the temple your gold beyond 50, then carry no more than 100 for three
##              days). Keep it and come back ("my vow") for a blessing and Devotion; break it and
##              the vow is gone
##   courting   anyone you could marry who likes you (60+) can be courted once a day ("spend time
##              together"): they like you more, and after three days of it they will marry you
##              at 65 instead of 80
##   leads      "latest rumors" sometimes ends in a lead: treasure said to be in a nearby dungeon.
##              It goes on your map and in the journal, and the treasure is there in the boss chest
## Topics come through QuestManager.extra_topics / respond, like Settlers and Marriage.

const ASIDE_CHANCE := 0.35
## Topics from here and RoadEvents: not quest steps (QuestMarkers puts no mark for them)
const SIDE_TOPICS := ["what you saw", "take a vow", "my vow", "spend time together", "pay the toll", "refuse the toll", "the broken cart"]
const VOW_DAYS := 3
const COURT_NEEDED := 3
const COURT_DISP := 60
const LEAD_CHANCE := 0.3
const LEAD_ITEMS := ["res://data/clutter/silver_goblet.tres", "res://data/materials/gold_ingot.tres"]

const RACE_LINES := {
	"northlander": "A northlander, this far south? You'll find our winters soft.",
	"heartlander": "You've the look of the old empire about you. Tax collector? No? Good.",
	"sandwalker": "Desert-born, by the look of you. Is it true you sleep with a sword in your hand?",
	"marchborn": "Half-elf from the marches, are you? Neither one thing nor the other. Like most of us.",
	"highborn": "One of the tall folk. Don't look down your nose at me, I'll get a crick in my neck.",
	"ashborn": "Ashborn. You smell of smoke, did you know? Not unpleasant. Just... smoke.",
	"woodborn": "A woodborn! Mind you don't go shooting the chickens.",
	"sandcat": "Don't see many of your kind about. Your eyes catch the light something fierce.",
	"marshfolk": "Marshfolk. You'll want to stay out of the market's fish barrel, ha.",
	"ironblood": "Ironblood. My cousin bought an axe from one of your smiths. Still has it. Still has both hands, too.",
}
const CLASS_LINES := {
	"warrior": "You carry yourself like someone who's been in a fight or ten.",
	"mage": "You've ink on your fingers and something odd about the eyes. A spell-worker?",
	"thief": "I'll keep a hand on my purse while we talk, if it's all the same to you.",
}
const BACKGROUND_LINES := {
	"soldier": "Old soldier? You still stand like you're waiting for an order.",
	"scholar": "A scholar, out here? Mind the books don't get wet.",
	"urchin": "Grew up on the streets, didn't you? Takes one to know one.",
	"farmhand": "You've a farmhand's hands. Honest work, that.",
	"noble": "Fine clothes, fine manners. Slumming it, my lord?",
	"sailor": "You walk like the ground's moving under you. A sailor?",
	"hermit": "You've been a long time on your own, I think. You talk like you've forgotten how.",
	"acolyte": "Temple-trained? I can always tell. It's the patience.",
	"hunter": "You move quiet. A hunter's child, I'd wager.",
	"miner": "Stone dust in the creases. A miner, once?",
	"performer": "I know your face! Did you play the fair last summer?",
	"squire": "Squire to some knight, were you? Where's your knight now?",
}


# ---------------------------------------------------------------- asides

## A word about who you are, for the end of a greeting ("" = not this person, not now)
static func aside(s: DialogueEngine.Speaker, player: Node) -> String:
	if s == null or player == null or s.asleep or s.role in [NpcData.Role.GUARD, NpcData.Role.LORD]:
		return ""
	var ch: Dictionary = player.get_meta("character", {})
	if ch.is_empty():
		return ""
	var h := absi(("%s|aside" % s.name).hash())
	if float(h % 1000) / 1000.0 >= ASIDE_CHANCE:
		return ""
	var options: Array[String] = []
	if RACE_LINES.has(String(ch.get("race", ""))):
		options.append(RACE_LINES[String(ch["race"])])
	var arche := archetype(String(ch.get("class", "")))
	if CLASS_LINES.has(arche):
		options.append(CLASS_LINES[arche])
	if BACKGROUND_LINES.has(String(ch.get("background", ""))):
		options.append(BACKGROUND_LINES[String(ch["background"])])
	if options.is_empty():
		return ""
	return options[(h / 1000) % options.size()]


## "warrior", "mage" or "thief": what a class leans toward (custom classes by their skills)
static func archetype(class_id: String) -> String:
	var id := class_id.to_lower()
	for w in ["warrior", "knight", "barbarian", "crusader", "archer", "scout", "soldier", "guard"]:
		if id.contains(w):
			return "warrior"
	for m in ["mage", "sorcer", "battlemage", "healer", "spellsword", "witch", "night", "nightblade"]:
		if id.contains(m):
			return "mage"
	for t in ["thief", "rogue", "assassin", "agent", "acrobat", "bard", "pilgrim", "monk"]:
		if id.contains(t):
			return "thief"
	return ""


# ---------------------------------------------------------------- topics

static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s == null or s.asleep:
		return out
	if not _crimes_seen(s).is_empty():
		out.append("what you saw")
	if s.role == NpcData.Role.PRIEST:
		out.append("my vow" if not WorldState.get_record("vow").is_empty() else "take a vow")
	if Marriage.can_marry(s) and DialogueEngine.get_disposition(s) >= COURT_DISP and not Marriage.is_spouse(s):
		out.append("spend time together")
	return out


static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, world: WorldManager) -> Dictionary:
	if not topics_for(s).has(topic):
		return {}
	var today := world.clock.day if world != null and world.clock != null else 1
	match topic:
		"what you saw":
			return _lie(s, player, world, today)
		"take a vow":
			return _take_vow(s, player, today)
		"my vow":
			return _check_vow(s, player, today)
		"spend time together":
			return _court(s, today)
	return {}


# ---------------------------------------------------------------- lying

static func _crimes_seen(s: DialogueEngine.Speaker) -> Array:
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	return (NpcMemory.memories(s.name, town) as Array).filter(func(m): return String(m.get("kind", "")) in ["theft", "assault", "trespass"])


## The chance a lie works: Speech and charisma, and how much they like you
static func lie_chance(s: DialogueEngine.Speaker, player: Node) -> float:
	var skills := player.get_node_or_null("Skills") as Skills
	var stats := player.get_node_or_null("Stats") as Stats
	var speech := float(skills.get_level(&"speech")) if skills != null else 15.0
	var cha := stats.get_stat("charisma") if stats != null else 10.0
	var c := 0.2 + speech / 220.0 + cha / 250.0 + float(DialogueEngine.get_disposition(s) - 50) / 300.0
	if s.personality == NpcData.Personality.NERVOUS:
		c += 0.1
	elif s.personality == NpcData.Personality.PROUD:
		c -= 0.08
	return clampf(c, 0.05, 0.9)


static func _lie(s: DialogueEngine.Speaker, player: Node, world: WorldManager, today: int) -> Dictionary:
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	if int(WorldState.get_record("lied/%s|%s" % [s.name, town]).get("day", -99)) == today:
		return _say("I've heard your story already. I know what I saw.")
	WorldState.set_record("lied/%s|%s" % [s.name, town], {"day": today})
	var c := lie_chance(s, player)
	BuildHooks.train(player.get_tree(), &"speech", 6.0)
	if randf() < c:
		var keep := (NpcMemory.memories(s.name, town) as Array).filter(func(m): return not String(m.get("kind", "")) in ["theft", "assault", "trespass"])
		WorldState.set_record("mem/%s|%s" % [s.name, town], {"list": keep})
		return _say("[Lie %d%%: believed] ...Was it? The light was bad. I suppose it could have been someone else. Forget I said anything." % int(c * 100.0))
	DialogueState.change_disposition(s.id, s.base_disposition, -10)
	if world != null and world.crime != null and s.town != null:
		world.crime.add_bounty(s.town.id, 20)
	return _say("[Lie %d%%: not believed] Don't insult me. I know what I saw, and so will the guard." % int(c * 100.0))


# ---------------------------------------------------------------- vows

static func _take_vow(s: DialogueEngine.Speaker, player: Node, today: int) -> Dictionary:
	var inv := player.get_node("Inventory") as Inventory
	var gold := Currency.get_gold(inv)
	var kind := "peace" if absi(today + s.name.hash()) % 2 == 0 or gold <= 50 else "poverty"
	var rec := {"kind": kind, "day": today, "kills": Takedowns.tally("kills") + Takedowns.tally("beasts")}
	if kind == "poverty":
		Currency.spend_gold(inv, gold - 50)
		rec["gave"] = gold - 50
	WorldState.set_record("vow", rec)
	DialogueState.system_entry("Vows", "I took a vow of %s at the temple. Three days, then back to a priest." % kind, "")
	if kind == "peace":
		return _say("Then swear it: for three days you will take no life, man or beast. Come back to any of us when the days are done.")
	return _say("Your gold beyond fifty goes to the poor, %d of it. For three days carry no more than a hundred. Then come back to us." % (gold - 50))


static func _check_vow(s: DialogueEngine.Speaker, player: Node, today: int) -> Dictionary:
	var rec := WorldState.get_record("vow")
	var kept := true
	if String(rec.get("kind", "")) == "peace":
		kept = Takedowns.tally("kills") + Takedowns.tally("beasts") <= int(rec.get("kills", 0))
	elif String(rec.get("kind", "")) == "poverty":
		kept = Currency.get_gold(player.get_node("Inventory") as Inventory) <= 100
	if not kept:
		WorldState.erase_record("vow")
		return _say("You broke it. I can see it on you. The vow is ended. You may take another, when you're ready.")
	if today - int(rec.get("day", today)) < VOW_DAYS:
		return _say("Not yet. %d more day%s." % [VOW_DAYS - (today - int(rec["day"])), "" if VOW_DAYS - (today - int(rec["day"])) == 1 else "s"])
	WorldState.erase_record("vow")
	var done := int(WorldState.get_record("vows_kept").get("n", 0)) + 1
	WorldState.set_record("vows_kept", {"n": done})
	var m := ActiveMagic.of(player)
	if m != null:
		m.apply_list([{"id": &"fortify_health", "mag": 25, "dur": 3600}, {"id": &"fortify_magicka", "mag": 25, "dur": 3600}], null, "Vow Kept", "spell")
	BuildHooks.train(player.get_tree(), &"devotion", 60.0)
	DialogueState.system_entry("Vows", "I kept my vow of %s. The priests blessed me." % rec.get("kind", ""), "")
	return _say("You kept it. Kneel. ...Go with the gods' blessing. It is no small thing, a vow kept.")


# ---------------------------------------------------------------- courting

static func courted(s: DialogueEngine.Speaker) -> int:
	return int(WorldState.get_record("court/%s" % s.id).get("n", 0)) if s != null else 0


static func _court(s: DialogueEngine.Speaker, today: int) -> Dictionary:
	var rec := WorldState.get_record("court/%s" % s.id)
	if int(rec.get("day", -1)) == today:
		return _say("Again? I've chores, you know. ...Tomorrow, then.")
	var n := int(rec.get("n", 0)) + 1
	WorldState.set_record("court/%s" % s.id, {"n": n, "day": today})
	DialogueState.change_disposition(s.id, s.base_disposition, 6)
	var lines := [
		"We walked to the edge of town and back, and talked about nothing much. It was nice.",
		"You listened to me go on about my day. Nobody does that.",
		"I showed you my favourite spot. Don't tell anyone about it.",
		"I think about you, when you're out on those roads. Come back safe.",
	]
	var tail := "" if n < COURT_NEEDED else " ...If you ever asked me something, with a ring, I don't think I'd say no."
	return _say(lines[mini(n - 1, lines.size() - 1)] + tail)


# ---------------------------------------------------------------- leads

## After the news: sometimes a lead on treasure in a dungeon near them ("" = none today)
static func lead(s: DialogueEngine.Speaker, world: WorldManager) -> String:
	if world == null or s == null or s.town == null:
		return ""
	var today := world.clock.day if world.clock != null else 1
	var key := "lead_told/%s|%d" % [s.name, today / 3]
	if WorldState.has_record(key):
		return ""
	if float(absi(("%s|lead|%d" % [s.name, today / 3]).hash()) % 1000) / 1000.0 >= LEAD_CHANCE:
		return ""
	var best: PlacedPOI = null
	var bd := INF
	for poi in world.pois:
		if not (poi.poi is DungeonEntrancePOIData) or Discovery.is_cleared(poi.id) or WorldState.has_record("lead/%s" % poi.id):
			continue
		var d := poi.position.distance_to(s.town.position)
		if d < bd and d < 2500.0:
			bd = d
			best = poi
	if best == null:
		return ""
	var item_path := ""
	for p in LEAD_ITEMS:
		if ResourceLoader.exists(p):
			item_path = p
			break
	if item_path == "":
		return ""
	WorldState.set_record(key, {"day": today})
	WorldState.set_record("lead/%s" % best.id, {"item": item_path, "placed": false})
	if world.discovery != null:
		world.discovery.mark_found(best)
	var name := Discovery.place_name(world, best)
	DialogueState.system_entry("Leads", "%s told me of treasure in %s. It's on my map." % [s.name, name], "")
	return " And here's one for you: they say there's something worth having at the bottom of %s. Old %s, from before the war. Nobody's brave enough to look." % [name, load(item_path).display_name.to_lower() if load(item_path) is ItemData else "treasure"]


static func _say(text: String) -> Dictionary:
	return {"text": text, "journal": false, "learn": PackedStringArray()}


## A boss chest in a dungeon you have a lead on holds the treasure (ContainerComponent asks, once)
static func fill_container(c: ContainerComponent) -> void:
	if c.save_id == "" or not c.save_id.ends_with("/chest_boss"):
		return
	var poi_id := c.save_id.trim_prefix("dungeon/").trim_suffix("/chest_boss")
	var rec := WorldState.get_record("lead/%s" % poi_id)
	if rec.is_empty() or bool(rec.get("placed", false)) or not ResourceLoader.exists(String(rec.get("item", ""))):
		return
	c.inventory.add_item(load(String(rec["item"])), 3 if String(rec["item"]).contains("ingot") else 1)
	var r := rec.duplicate()
	r["placed"] = true
	WorldState.set_record("lead/%s" % poi_id, r)
