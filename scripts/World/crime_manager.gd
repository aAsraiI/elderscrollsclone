class_name CrimeManager
extends Node
## Crime and punishment. Created by WorldManager, nothing to add by hand.
##
## A crime only counts if someone sees it: a person (not a hostile creature) whose awareness of
## the player (see Stealth) is high enough at that moment. The victim of an assault always knows.
##   trespass   being inside a closed home or shop and not leaving when told    5
##   lockpick   picking a lock while watched                                    5
##   theft      taking from an owned chest ("Steal") while watched        its value
##   assault    hitting someone who wasn't hostile                              40
##   murder     killing someone who wasn't hostile                            1000
##   resist     resisting arrest                                                5
## Bounty is kept per town ("bounty/<town id>" in WorldState) and only that town's guards care.
## Stolen goods stay marked as stolen even if nobody saw ("stolen" in WorldState): ordinary
## merchants won't buy them, and guards take them back.
##
## Guards: when a guard of a town where you have a bounty sees you, they come over and you choose:
## pay the fine, go to jail (days pass, some skill progress is lost) or resist (they attack). With
## a murder on your head (1000+) they attack on sight. Guards also fight hostile creatures that
## come into town.

signal crime_reported(kind: String, town_id: String, bounty: int, witnessed: bool)
signal bounty_changed(town_id: String, bounty: int)

const BOUNTY := {"trespass": 5, "lockpick": 5, "assault": 40, "murder": 1000, "resist": 5}
## At this bounty guards attack instead of arresting
const ATTACK_ON_SIGHT := 1000
## Awareness (see Stealth) a person needs to count as a witness
const WITNESS := 0.6
const TICK := 0.25
const ARREST_RANGE := 3.0
const CHASE_RANGE := 35.0
## Seconds you get to leave after being told to get out
const TRESPASS_GRACE := 10.0
const STOLEN := "stolen"

var world: WorldManager

var _ui: ArrestUI
var _timer := 0.0
var _creature_timer := 0.0
var _time := 0.0
var _arrester: Enemy
var _arrest_town := ""
var _recent := {}   # "kind|thing" -> time of the last report (no double counting)
var _trespass_id := ""
var _warned_at := -1.0
var _trespass_reported := false


func _ready() -> void:
	add_to_group("crime")
	world = get_parent() as WorldManager
	_ui = ArrestUI.new()
	_ui.name = "ArrestUI"
	add_child(_ui)
	_ui.chosen.connect(_on_arrest_choice)
	if world != null and world.dungeons != null:
		world.dungeons.entered.connect(func(id: String) -> void:
			_trespass_id = id
			_warned_at = -1.0
			_trespass_reported = false)


# ---------------------------------------------------------------- bounty

static func get_bounty(town_id: String) -> int:
	return int(WorldState.get_record("bounty/" + town_id).get("gold", 0))


static func set_bounty_raw(town_id: String, amount: int) -> void:
	if amount <= 0:
		WorldState.erase_record("bounty/" + town_id)
	else:
		WorldState.set_record("bounty/" + town_id, {"gold": amount})


## Every town where you are wanted: town id -> gold
static func bounties() -> Dictionary:
	var out := {}
	for key: String in WorldState.records:
		if key.begins_with("bounty/"):
			out[key.trim_prefix("bounty/")] = int(WorldState.records[key].get("gold", 0))
	return out


func set_bounty(town_id: String, amount: int) -> void:
	set_bounty_raw(town_id, amount)
	bounty_changed.emit(town_id, maxi(amount, 0))


func add_bounty(town_id: String, amount: int) -> void:
	set_bounty(town_id, get_bounty(town_id) + amount)


# ---------------------------------------------------------------- stolen goods

## item path -> how many of that item are stolen
static func stolen_ledger() -> Dictionary:
	return WorldState.get_record(STOLEN).get("items", {})


static func add_stolen(item: ItemData, count: int) -> void:
	var path := SaveUtil.item_to_path(item)
	if path == "" or count <= 0:
		return
	var ledger := stolen_ledger().duplicate()
	ledger[path] = int(ledger.get(path, 0)) + count
	WorldState.set_record(STOLEN, {"items": ledger})


static func remove_stolen(item: ItemData, count: int) -> void:
	var path := SaveUtil.item_to_path(item)
	var ledger := stolen_ledger().duplicate()
	if not ledger.has(path):
		return
	var left := int(ledger[path]) - count
	if left > 0:
		ledger[path] = left
	else:
		ledger.erase(path)
	WorldState.set_record(STOLEN, {"items": ledger})


## How many of the item in this inventory are stolen
static func stolen_count(inv: Inventory, item: ItemData) -> int:
	return mini(int(stolen_ledger().get(SaveUtil.item_to_path(item), 0)), inv.get_count(item))


## Takes every stolen thing out of the inventory. Returns how many were taken.
static func confiscate(inv: Inventory) -> int:
	var taken := 0
	for path: String in stolen_ledger():
		var item := SaveUtil.path_to_item(path)
		if item == null:
			continue
		var n := mini(int(stolen_ledger()[path]), inv.get_count(item))
		if n > 0 and inv.remove_item(item, n):
			taken += n
	WorldState.erase_record(STOLEN)
	return taken


# ---------------------------------------------------------------- reporting

## The town a crime right now belongs to (the building you are in, or the town you stand in)
func crime_town() -> PlacedPOI:
	var dm := world.dungeons if world != null else null
	if dm != null and dm.is_in_building():
		var b := world.get_building(dm.current_entrance_id)
		if b != null:
			return world.get_poi(b.town_id)
	var p := _player()
	return world.get_town_at(p.global_position, 150.0) if p != null and world != null else null


## The people who are aware of the player right now (not hostile creatures, not sleepers)
func witnesses(exclude: Node = null) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var p := _player()
	if p == null:
		return out
	var stealth := p.get_node_or_null("Stealth") as Stealth
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == exclude or e.is_dead() or e.disposition == Enemy.Disposition.HOSTILE or e.get_meta("asleep", false):
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d > 40.0:
			continue
		var aware := stealth.awareness_of(e) if stealth != null else (1.0 if d < 12.0 else 0.0)
		if aware >= WITNESS:
			out.append(e)
	return out


## Reports a crime by the player. Returns {"witnessed": bool, "bounty": added, "town": id}
func report(kind: String, value: int = 0, victim: Enemy = null) -> Dictionary:
	var town := crime_town()
	var list := witnesses(victim if kind == "murder" else null)
	if kind == "assault" and victim != null and not victim.is_dead() and not list.has(victim):
		list.append(victim)  # the victim knows who hit them
	var amount: int = value if kind == "theft" else int(BOUNTY.get(kind, 0))
	var town_id := town.id if town != null else ""
	if list.is_empty() or amount <= 0:
		crime_reported.emit(kind, town_id, 0, false)
		return {"witnessed": false, "bounty": 0, "town": town_id}
	if town_id != "":
		add_bounty(town_id, amount)
	var p := _player()
	for w in list:
		var npc_id := String(w.get_meta("npc_id", ""))
		if npc_id != "" and world.life != null:
			var r := world.life.get_resident(npc_id)
			if r != null:
				DialogueState.change_disposition(npc_id, r.data.base_disposition, -30 if kind == "murder" else -10)
		if (kind == "assault" or kind == "murder") and w != victim and w.disposition == Enemy.Disposition.FRIENDLY and p != null:
			w.flee_from(p, 10.0)
	var where := " in %s" % town.town.display_name if town != null and town.town != null else ""
	Locks.toast(get_tree(), "%s was seen! Bounty%s: %d" % [String(kind).capitalize(), where, get_bounty(town_id) if town_id != "" else amount], true)
	crime_reported.emit(kind, town_id, amount, true)
	return {"witnessed": true, "bounty": amount, "town": town_id}


func _once(key: String, seconds: float) -> bool:
	if _time - float(_recent.get(key, -INF)) < seconds:
		return false
	_recent[key] = _time
	return true


## MeleeCombat calls this when the player hits someone who wasn't hostile
func on_player_hurt(victim: Enemy, killed: bool) -> void:
	if killed:
		report("murder", 0, victim)
	elif _once("assault|%d" % victim.get_instance_id(), 15.0):
		report("assault", 0, victim)


## ContainerUI calls this when the player takes from an owned container
func on_taken(item: ItemData, count: int) -> void:
	add_stolen(item, count)
	report("theft", item.value * count)


## ...and this when the player puts something back
func on_returned(item: ItemData, count: int) -> void:
	remove_stolen(item, count)


## BuildingDoor calls this after a try at picking a lock
func on_lock_attempt(lock_id: String) -> void:
	if _once("lock|" + lock_id, 30.0):
		report("lockpick")


# ---------------------------------------------------------------- every moment

func _process(delta: float) -> void:
	_time += delta
	if get_tree().paused or world == null:
		return
	_timer += delta
	if _timer < TICK:
		return
	var dt := _timer
	_timer = 0.0
	var p := _player()
	if p == null or _ui.is_open():
		return
	var stats := p.get_node_or_null("Stats") as Stats
	if stats != null and stats.is_dead:
		return
	_check_trespass()
	_check_guards(p)
	_creature_timer += dt
	if _creature_timer >= 1.0:
		_creature_timer = 0.0
		_defend_town(p)


# Inside a closed home or shop: the people there tell you to leave, then report you
func _check_trespass() -> void:
	var dm := world.dungeons
	if dm == null or not dm.is_in_building() or dm.current_entrance_id != _trespass_id or _trespass_reported:
		return
	var b := world.get_building(_trespass_id)
	if b == null or not is_closed(b):
		return
	var seen_by: Enemy = null
	for w in witnesses():
		if w.is_inside_tree() and w.global_position.y < DungeonManager.DUNGEON_Y + 500.0:
			seen_by = w
			break
	if seen_by == null:
		return
	if _warned_at < 0.0:
		_warned_at = _time
		Locks.toast(get_tree(), "%s: What are you doing in here? Get out!" % seen_by.display_name, true)
	elif _time - _warned_at > TRESPASS_GRACE:
		_trespass_reported = true
		report("trespass")


## Is this building closed to visitors right now? (Its owner asleep, a shop after hours, or a
## private house that is normally kept locked)
func is_closed(b: BuildingPlot) -> bool:
	var owner: TownLife.Resident = world.life.get_owner_of(b.id) if world.life != null else null
	if owner == null:
		return false
	if owner.activity == NpcData.Activity.SLEEP:
		return true
	if b.is_public():
		return owner.activity != NpcData.Activity.WORK
	return b.starts_locked


func _check_guards(p: Node3D) -> void:
	var dm := world.dungeons
	if dm != null and dm.is_inside():
		_cancel_arrest()
		return
	var town := world.get_town_at(p.global_position, 60.0)
	if town == null or get_bounty(town.id) <= 0:
		_cancel_arrest()
		return
	var stealth := p.get_node_or_null("Stealth") as Stealth
	var bounty := get_bounty(town.id)
	for g in _guards(town):
		var sees := stealth == null or stealth.is_detected_by(g) or g.global_position.distance_to(p.global_position) < 4.0
		if not sees:
			continue
		if bounty >= ATTACK_ON_SIGHT:
			if g.disposition != Enemy.Disposition.HOSTILE:
				g.disposition = Enemy.Disposition.HOSTILE
				g.aggro(p)
		elif _arrester == null and g.disposition != Enemy.Disposition.HOSTILE and g.global_position.distance_to(p.global_position) < CHASE_RANGE:
			_arrester = g
			_arrest_town = town.id
			Locks.toast(get_tree(), "%s: Stop right there!" % g.display_name, true)
	if _arrester == null or not is_instance_valid(_arrester) or _arrester.is_dead() or _arrester.disposition == Enemy.Disposition.HOSTILE:
		_arrester = null
		return
	var d := _arrester.global_position.distance_to(p.global_position)
	if d > CHASE_RANGE * 1.5:
		_cancel_arrest()
	elif d <= ARREST_RANGE:
		_arrester.stop_route()
		var gold := Currency.get_gold(p.get_node("Inventory") as Inventory)
		_ui.open_for(_arrester.display_name, town.town.display_name, bounty, gold, jail_days(bounty))
	else:
		_arrester.follow_route(PackedVector3Array([p.global_position]), false, 0.85)


func _cancel_arrest() -> void:
	if _arrester != null and is_instance_valid(_arrester) and _arrester.is_on_route():
		_arrester.stop_route()
	_arrester = null


# Guards go for hostile creatures that come into town
func _defend_town(p: Node3D) -> void:
	var town := world.get_town_at(p.global_position, 150.0)
	if town == null:
		return
	var guards := _guards(town)
	if guards.is_empty():
		return
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or e.disposition != Enemy.Disposition.HOSTILE or e.has_meta("npc_id"):
			continue
		if not town.town.contains(e.global_position, 25.0):
			continue
		var best: Enemy = null
		for g in guards:
			if g.disposition == Enemy.Disposition.HOSTILE or g.state == Enemy.State.CHASE or g.state == Enemy.State.ATTACK:
				continue
			if g.global_position.distance_to(e.global_position) < 60.0 and (best == null or g.global_position.distance_to(e.global_position) < best.global_position.distance_to(e.global_position)):
				best = g
		if best != null:
			best.fight(e)


func _guards(town: PlacedPOI) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if world.life == null:
		return out
	for r: TownLife.Resident in world.life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.GUARD and r.node != null and is_instance_valid(r.node) and not r.node.is_dead() and not r.node_inside:
			out.append(r.node)
	return out


# ---------------------------------------------------------------- arrest

## Days in jail for a bounty
static func jail_days(bounty: int) -> int:
	return clampi(ceili(float(bounty) / 100.0), 1, 7)


func _on_arrest_choice(choice: String) -> void:
	var p := _player()
	var town := world.get_poi(_arrest_town)
	if p == null or town == null:
		return
	var inv := p.get_node("Inventory") as Inventory
	var bounty := get_bounty(town.id)
	match choice:
		"pay":
			Currency.spend_gold(inv, bounty)
			var taken := confiscate(inv)
			set_bounty(town.id, 0)
			Locks.toast(get_tree(), "You paid %d gold.%s" % [bounty, " Your stolen goods were taken." if taken > 0 else ""])
		"jail":
			serve_jail(town, bounty)
		"resist":
			add_bounty(town.id, BOUNTY["resist"])
			for g in _guards(town):
				g.disposition = Enemy.Disposition.HOSTILE
				g.aggro(p)
			Locks.toast(get_tree(), "You resist arrest!", true)
	_arrester = null


## Days pass, some skill progress is lost, stolen goods are taken, and you are let out at the gate
func serve_jail(town: PlacedPOI, bounty: int) -> Dictionary:
	var p := _player()
	var days := jail_days(bounty)
	var inv := p.get_node("Inventory") as Inventory
	confiscate(inv)
	set_bounty(town.id, 0)
	var lost := PackedStringArray()
	var skills := p.get_node_or_null("Skills") as Skills
	if skills != null:
		var with_xp: Array = []
		for id in skills.xp:
			if float(skills.xp[id]) > 0.0:
				with_xp.append(id)
		with_xp.shuffle()
		for i in mini(days, with_xp.size()):
			skills.xp[with_xp[i]] = 0.0
			var def := SkillDatabase.get_skill(with_xp[i])
			lost.append(def.display_name if def != null else String(with_xp[i]))
	if world.clock != null:
		world.clock.advance_hours(float(days) * 24.0)
	var layout := town.town
	var gate := layout.get_gates_world()[0]
	var out := layout.get_gate_outward(0)
	var at := gate + out * 8.0
	world.ensure_area_loaded(at, 1)
	p.global_position = Vector3(at.x, world.get_height_at(at.x, at.z) + 1.0, at.z)
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	var text := "You served %d day%s in jail." % [days, "" if days == 1 else "s"]
	if not lost.is_empty():
		text += " Your %s skill%s grew rusty." % [", ".join(lost), "" if lost.size() == 1 else "s"]
	Locks.toast(get_tree(), text, true)
	return {"days": days, "lost": lost}


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
