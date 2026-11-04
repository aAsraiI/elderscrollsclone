class_name CreatureFactions
extends RefCounted
## Alpha 1.24: who every creature sides with, and how the sides get on (data/world/creature_factions.json).
##   SAME      one faction: never fight, not even when a stray swing or spell lands
##   FRIENDLY  never fight; a hit is an accident, and they help each other when attacked
##   NEUTRAL   leave each other alone; whoever is hit (even by accident) fights back its attacker only
##   HOSTILE   fight on sight
## Relations can change during a game (quests, events): set_relation() keeps the change in WorldState.
## The player has a standing with each faction too: help one long enough and its members stop
## attacking you on sight (STANDING_TRUCE); kill its members and it falls again.

enum Rel { SAME, FRIENDLY, NEUTRAL, HOSTILE }

const PATH := "res://data/world/creature_factions.json"
const REL_RECORD := "faction_rel"
const STANDING_RECORD := "faction_standing"
## Standing at which a hostile faction stops attacking you on sight
const STANDING_TRUCE := 25
## Standing for killing one of a faction's enemies / one of its own
const STANDING_HELP := 1
const STANDING_HARM := -6

const NAMES_FALLBACK := {"bandits": "Bandits", "town": "Town guards", "beasts": "Beasts"}

static var _loaded := false
static var _names := {}
static var _members := {}
static var _base := {}  # "a|b" (sorted) -> Rel
static var _hostile_to := {}  # faction -> Array of factions it fights on sight (base + changes)
static var _stamp := 0


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("CreatureFactions: %s is missing" % PATH)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		push_warning("CreatureFactions: %s is not valid JSON" % PATH)
		return
	_names = d.get("factions", {})
	_members = d.get("members", {})
	for pair in d.get("relations", {}):
		var p := String(pair).split("|")
		if p.size() == 2:
			_base[_key(p[0], p[1])] = _rel_of(String(d["relations"][pair]))
	_rebuild_hostile()


static func _rel_of(word: String) -> Rel:
	match word.to_lower():
		"friendly":
			return Rel.FRIENDLY
		"hostile":
			return Rel.HOSTILE
	return Rel.NEUTRAL


static func rel_name(r: Rel) -> String:
	return ["same", "friendly", "neutral", "hostile"][r]


static func _key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func all() -> Array:
	_load()
	return _names.keys()


static func display_name(faction: String) -> String:
	_load()
	return String(_names.get(faction, NAMES_FALLBACK.get(faction, faction.capitalize())))


## out from what it is (friendly folk side with the town, beasts with beasts, the rest are outlaws)
static func of(e: Node) -> String:
	if e == null or not (e is Enemy):
		return ""
	var en := e as Enemy
	if en.faction != "":
		return en.faction
	_load()
	var id := String(en.enemy_id)
	if id == "" and not en.has_meta("animal"):
		return ""  # made by hand, not from a data file (tests, props): on no side
	var out := ""
	if _members.has(id):
		out = String(_members[id])
	elif en.has_meta("animal"):
		out = "livestock"
	elif en.disposition != Enemy.Disposition.HOSTILE:
		out = "town"
	elif en.body_kind == CreatureBody.Kind.BEAST or en.body_kind == CreatureBody.Kind.CRAWLER:
		out = "beasts"
	elif en.body_kind == CreatureBody.Kind.SPIRIT:
		out = "spirits"
	else:
		out = "bandits"
	en.faction = out
	return out


static func relation(a: String, b: String) -> Rel:
	if a == "" or b == "":
		return Rel.NEUTRAL
	if a == b:
		return Rel.SAME
	_load()
	var k := _key(a, b)
	var changed := WorldState.get_record(REL_RECORD)
	if changed.has(k):
		return int(changed[k]) as Rel
	return _base.get(k, Rel.NEUTRAL)


static func between(x: Node, y: Node) -> Rel:
	return relation(of(x), of(y))


## Two creatures that must never hurt each other (one faction, or friends)
static func allies(x: Node, y: Node) -> bool:
	var r := between(x, y)
	return r == Rel.SAME or r == Rel.FRIENDLY


## Changes how two factions get on from now on (quests, events). Kept in the save.
static func set_relation(a: String, b: String, r: Rel) -> void:
	if a == b:
		return
	_load()
	var changed := WorldState.get_record(REL_RECORD).duplicate()
	changed[_key(a, b)] = int(r)
	WorldState.set_record(REL_RECORD, changed)
	_rebuild_hostile()


## The factions this one fights on sight (empty = it never starts a fight with other creatures)
static func hostile_to(faction: String) -> Array:
	_load()
	var stamp := WorldState.get_record(REL_RECORD).hash()
	if stamp != _stamp:
		_rebuild_hostile()  # a save was loaded, or a quest changed how the sides get on
	return _hostile_to.get(faction, [])


static func _rebuild_hostile() -> void:
	_stamp = WorldState.get_record(REL_RECORD).hash()
	_hostile_to.clear()
	var fs: Array = _names.keys()
	for a in fs:
		var out: Array = []
		for b in fs:
			if a != b and relation(a, b) == Rel.HOSTILE:
				out.append(b)
		_hostile_to[a] = out


## Called when WorldState is cleared or a game is loaded (relations from the save take over)
static func refresh() -> void:
	_load()
	_rebuild_hostile()


# ---------------------------------------------------------------- the player's standing

static func standing(faction: String) -> int:
	return int(WorldState.get_record(STANDING_RECORD).get(faction, 0))


static func add_standing(tree: SceneTree, faction: String, amount: int) -> void:
	if faction == "" or faction == "town":
		return  # the town has its own law (bounty, CrimeManager)
	var s := WorldState.get_record(STANDING_RECORD).duplicate()
	var before := int(s.get(faction, 0))
	var now := clampi(before + amount, -100, 100)
	s[faction] = now
	WorldState.set_record(STANDING_RECORD, s)
	if tree != null and before < STANDING_TRUCE and now >= STANDING_TRUCE:
		Locks.toast(tree, "%s no longer attack you on sight." % display_name(faction), true)
	elif tree != null and before >= STANDING_TRUCE and now < STANDING_TRUCE:
		Locks.toast(tree, "%s are after your blood again." % display_name(faction), true)


## A hostile creature of this faction leaves you alone unless you start it
static func tolerates_player(faction: String) -> bool:
	return faction != "" and standing(faction) >= STANDING_TRUCE


## The player killed a creature: its faction thinks less of you, its enemies more
static func on_player_kill(tree: SceneTree, victim: Enemy) -> void:
	var f := of(victim)
	if f == "":
		return
	add_standing(tree, f, STANDING_HARM)
	for other in all():
		if other != f and relation(other, f) == Rel.HOSTILE:
			add_standing(tree, other, STANDING_HELP)
