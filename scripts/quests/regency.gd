class_name Regency
extends Node
## The Regency Council (lore bible): eight great houses race to rule for Princess Elowen once
## the King dies. Each house's influence is worked out from what the player has done (its quests,
## the city questlines' choices, being sworn to it), so it is always up to date and needs no saving
## of its own. The council is settled when a house finishes its capstone quest, when the Velvet
## Court takes it, or when the King dies (the house with most influence wins, unless the player
## belongs to one). Then the epilogue plays. Result saved in WorldState "regency_result".

const RESULT := "regency_result"
const KING_SAVED := "regency_king_saved_day"
## A saved King lives this many more days (one game year)
const KING_EXTRA_DAYS := 360

## The 8 joinable great houses, with their influence before the player does anything
const HOUSES := {"valcourt": 15, "tidewell": 14, "brannoch": 13, "morvaine": 12, "sahrim": 11, "kjellvar": 11, "ashgrove": 10, "vyrel": 6}
## Each house's capstone quest, and how its ending reads (by the choice made in it)
const CAPSTONES := {
	"valcourt": ["H-VA08", {"full": "Lord Regent Lucan Valcourt rules, and Elowen is promised to his son Adrien.",
		"guarantee": "Lord Regent Lucan Valcourt rules, bound by a signed promise of Elowen's freedom.",
		"exposed": "Lucan Valcourt's plot was exposed; the Chancellor holds the regency in his place.", "": "Lord Regent Lucan Valcourt rules for Elowen."}],
	"tidewell": ["H-TW08", {"": "The Merchant Regency: Duchess Isra Tidewell holds the Crown's purse and its throne."}],
	"ashgrove": ["H-AG08", {"guardian": "Rowan Ashgrove is Elowen's sworn guardian, and she is raised in the Forest.",
		"crown": "Maren Ashgrove's elder-line claim took the crown itself, after a short and bitter war.", "": "House Ashgrove guards the throne."}],
	"morvaine": ["H-MO08", {"": "The Shadow Regency of Odile Morvaine: a realm that knows its monsters."}],
	"brannoch": ["H-BR08", {"storm": "Duke Brannoch stormed Dawnhold and rules as Lord Protector.",
		"terms": "Kingsreach surrendered on terms; Duke Brannoch rules as Lord Protector.",
		"callum": "Callum Brannoch turned on his father and rules as Lord Protector.", "": "A Brannoch Protectorate rules Caldreth."}],
	"sahrim": ["H-SA08", {"exposed": "Prince Rashid is betrothed to Elowen, and the Emir rules as regent-in-law.",
		"joined": "Princess Leyla al-Sahrim is Regent of Caldreth.", "": "The Sahrim Regency rules from Sunhold and Kingsreach."}],
	"kjellvar": ["H-KJ08", {"regency": "High Jarl Sigrun Kjellvar sits by the Crown's fire as Regent.",
		"free": "The Northmarch is free, and Sigrun Kjellvar is its queen.", "": "The Northern Regency rules."}],
	"vyrel": ["H-VY08", {"": "The Ashen Regency: Archon Seraphine Vyrel rules, the house that saved the sun."}],
}

var world: WorldManager
var _timer := 0.0


func _ready() -> void:
	world = get_parent() as WorldManager


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 5.0
	if world == null or world.clock == null or is_settled():
		return
	# The King was saved for a year: remember the day it started
	if QuestBook.flag("S-KR08:saved") and not WorldState.has_record(KING_SAVED):
		WorldState.set_record(KING_SAVED, {"day": world.clock.day})
	var result := outcome(world.clock.day)
	if not result.is_empty():
		WorldState.set_record(RESULT, result)
		Locks.toast(get_tree(), "The Regency Council has chosen.")
		Epilogue.play(get_tree(), "The Regency of Caldreth")


# ---------------------------------------------------------------- reading the council

static func is_settled() -> bool:
	return WorldState.has_record(RESULT)


## {"house", "text"} once the council has chosen, else {}
static func result() -> Dictionary:
	return WorldState.get_record(RESULT)


## "alive", "saved" (a year more) or "dead"
static func king_state(today: int) -> String:
	if QuestBook.flag("S-KR08:peace"):
		return "dead"
	if QuestBook.flag("S-KR08:saved"):
		var since := int(WorldState.get_record(KING_SAVED).get("day", today))
		return "dead" if today - since >= KING_EXTRA_DAYS else "saved"
	return "alive"


## The player's house, or ""
static func player_house() -> String:
	for h in HOUSES:
		if Factions.is_member(h):
			return h
	return ""


## Houses that left the council (Sahrim broke the Accord, the Northmarch voted to leave)
static func left_council() -> Array[String]:
	var out: Array[String] = []
	if QuestBook.flag("S-SH07:broken"):
		out.append("sahrim")
	if QuestBook.flag("S-WG05:free"):
		out.append("kjellvar")
	return out


## Each house's influence now: {house: int}. Houses that left the council aren't in it.
static func influence() -> Dictionary:
	var out := HOUSES.duplicate()
	var add := func(h: String, n: int) -> void:
		if out.has(h):
			out[h] = maxi(0, int(out[h]) + n)
	# The city questlines (lore bible: S-KR07's accusation, S-MW05's marriage, S-WG05's vote, S-SH07's accord)
	if QuestBook.flag("S-KR07:morvaine"):
		add.call("morvaine", -8)
	if QuestBook.flag("S-KR07:framed"):
		add.call("morvaine", 3)
		add.call(_leader(out, ["morvaine"]), -6)  # the accusation lands on the strongest rival
	if QuestBook.flag("S-MW05:married"):
		add.call("valcourt", 4)
	if QuestBook.flag("S-MW05:eloped"):
		add.call("valcourt", -3)
	if QuestBook.flag("S-MW05:told"):
		add.call("valcourt", 2)
	if QuestBook.flag("S-MW07:duke"):
		add.call("valcourt", 4)
	if QuestBook.flag("S-SM02:duchess"):
		add.call("tidewell", 4)
	if QuestBook.flag("S-SM02:crown"):
		add.call("tidewell", -3)
	if QuestBook.flag("S-SH07:loyal"):
		add.call("sahrim", 3)
	if QuestBook.flag("S-WG05:loyal"):
		add.call("kjellvar", 3)
	if QuestBook.is_done("S-TH07"):
		add.call("ashgrove", 4)  # the Thornheart letters clear Ashgrove at court
	if QuestBook.flag("S-BF05:freed"):
		add.call("morvaine", 2)
	# The houses' own work, and the player's sword
	for h in HOUSES:
		for id in QuestBook.ids():
			if id.begins_with("H-") and String(QuestBook.get_def(id).get("faction", "")) == h and QuestBook.is_done(id):
				add.call(h, 2)
	var mine := player_house()
	if mine != "":
		add.call(mine, 6)
		if QuestBook.is_done("S-KR08"):
			add.call(mine, 10)  # the King's will names the player's house as a council voice
	for h in left_council():
		out.erase(h)
	return out


static func _leader(scores: Dictionary, skip: Array) -> String:
	var best := ""
	for h in scores:
		if not skip.has(h) and (best == "" or int(scores[h]) > int(scores[best])):
			best = h
	return best


## What the council would decide now, or {} while it is still open
static func outcome(today: int) -> Dictionary:
	if QuestBook.flag("V-VC08:regency"):
		return {"house": "velvet_court", "text": "The Velvet Regency: Caldreth is ruled by night, through thralled councillors."}
	for h in CAPSTONES:
		var c: Array = CAPSTONES[h]
		if QuestBook.is_done(String(c[0])):
			var forms: Dictionary = c[1]
			for f in forms:
				if f != "" and QuestBook.flag("%s:%s" % [c[0], f]):
					return {"house": h, "text": forms[f]}
			return {"house": h, "text": forms[""]}
	if king_state(today) == "dead":
		var mine := player_house()
		var winner := mine if mine != "" and not left_council().has(mine) else _leader(influence(), [])
		return {"house": winner, "text": "King Aldren is dead. The Regency Council names %s to rule for Elowen." % Factions.display_name(winner)}
	return {}
