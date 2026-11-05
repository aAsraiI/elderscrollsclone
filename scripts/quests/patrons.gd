class_name Patrons
extends RefCounted
## Alpha 1.28.5: the eight Patrons, otherworldly beings with shrines in the wilds (the glowing
## shrines). Kneel at one (E) and its patron asks a deed of you; do it and come back to any of its
## shrines, and its artifact is yours, one of a kind. A patron speaks only to those of its level.
## The deed is counted from the moment you take it, with the same counters the achievements use.
## Kept in WorldState "patron/<id>" {"state": "active" | "done", "start": count}.

## id -> [name, title, level, counter, how many, the deed, artifact file, artifact name]
const LIST := {
	"vael": ["Vael", "the Ember Queen", 10, "n:cast", 40, "Burn bright: cast forty spells", "vael_emberheart", "Emberheart"],
	"morrowgast": ["Morrowgast", "Lord of Rot", 12, "n:kill", 30, "Feed the rot: kill thirty foes or beasts", "morrowgast_rotfang", "Rotfang"],
	"ilsira": ["Ilsira", "of the Veiled Moon", 14, "n:lockpick", 12, "Open what was closed: pick twelve locks", "ilsira_moonveil", "Moonveil Cowl"],
	"kharn": ["Kharn", "the Unbroken", 18, "n:parry", 15, "Stand and turn steel: parry fifteen blows", "kharn_maul", "Maul of the Unbroken"],
	"sythara": ["Sythara", "the Weaver", 20, "n:combo", 5, "Weave the elements: set off five spell combos", "sythara_loom", "Loom of Sythara"],
	"dorun": ["Dorun", "the Deepfather", 15, "n:harvest", 40, "Take from the earth: gather forty times", "dorun_heart", "Heart of the Deep"],
	"choir": ["The Hollow Choir", "who sing the end", 22, "n:sneak_attack", 12, "Strike unseen twelve times", "choir_whisper", "Whisper of the Choir"],
	"thornwood": ["Mother Thornwood", "of the Wild Root", 16, "tally:beasts", 20, "Thin the herds: kill twenty beasts", "thornwood_band", "Thornmother's Band"],
}
const IDS := ["vael", "morrowgast", "ilsira", "kharn", "sythara", "dorun", "choir", "thornwood"]
const ARTIFACT_DIR := "res://data/artifacts/"


static func for_place(poi_id: String) -> String:
	return IDS[absi(poi_id.hash()) % IDS.size()]


static func state(id: String) -> String:
	return String(WorldState.get_record("patron/" + id).get("state", ""))


static func count_now(id: String) -> int:
	var check := String(LIST[id][3])
	if check.begins_with("tally:"):
		return Takedowns.tally(check.substr(6))
	return Achievements.count(check.substr(2))


static func progress(id: String) -> int:
	return count_now(id) - int(WorldState.get_record("patron/" + id).get("start", 0))


static func artifact(id: String) -> ItemData:
	var path := ARTIFACT_DIR + String(LIST[id][6]) + ".tres"
	return load(path) as ItemData if ResourceLoader.exists(path) else null


static func prompt(id: String) -> String:
	var d: Array = LIST[id]
	match state(id):
		"done":
			return "Shrine of %s (your patron's gift is given)" % d[0]
		"active":
			return "Shrine of %s: %d of %d" % [d[0], mini(progress(id), int(d[4])), int(d[4])]
	return "Kneel at the shrine of %s, %s" % [d[0], d[1]]


## Kneeling. Returns what is said.
static func kneel(id: String, player: Node) -> String:
	var d: Array = LIST[id]
	var sk := player.get_node_or_null("Skills") as Skills
	var lvl := sk.get_player_level() if sk != null else 1
	match state(id):
		"done":
			return "%s is silent. You have had their gift." % d[0]
		"active":
			if progress(id) < int(d[4]):
				return "%s waits. %s (%d of %d)." % [d[0], d[5], mini(progress(id), int(d[4])), int(d[4])]
			var it := artifact(id)
			if it != null:
				(player.get_node("Inventory") as Inventory).add_item(it, 1)
			WorldState.set_record("patron/" + id, {"state": "done"})
			Achievements.note("patron")
			DialogueState.system_entry("Quest", "%s, %s, is pleased. Their gift is mine: %s." % [d[0], d[1], d[7]], "")
			Notices.quest(player.get_tree(), "Patron's Gift", String(d[7]))
			return "%s is pleased. %s is yours." % [d[0], d[7]]
	if lvl < int(d[2]):
		return "The shrine is cold to you. %s speaks only to those of level %d." % [d[0], int(d[2])]
	WorldState.set_record("patron/" + id, {"state": "active", "start": count_now(id)})
	DialogueState.system_entry("Quest", "I knelt at a shrine of %s, %s. A voice in my head: \"%s.\" Then return to any of my shrines." % [d[0], d[1], d[5]], "")
	Notices.quest(player.get_tree(), "Patron", "%s: %s" % [d[0], d[5]])
	return "A voice fills your head: \"%s.\"" % d[5]
