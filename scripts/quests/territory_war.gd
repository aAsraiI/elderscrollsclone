class_name TerritoryWar
extends Node
## The clans' monthly war events (the lore bible's territory war). Once per game month, if the
## player is sworn to a vampire clan, a rival clan attacks one of the lands their clan rules.
## Raiders gather at a spot in that land (a compass target): kill them within DAYS days and the land
## holds; otherwise the player's clan loses LOSS control there. Saved in WorldState "clan_war".

const RECORD := "clan_war"
const DAYS := 3
const LOSS := 20
const RAIDERS := 4
const SPAWN_NEAR := 150.0

var world: WorldManager
var _timer := 0.0
var _spawned := {}  # key -> Enemy


func _ready() -> void:
	world = get_parent() as WorldManager


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 3.0
	if world == null or world.clock == null or world.map == null:
		return
	var clan := ClanTerritory.player_clan()
	var war := WorldState.get_record(RECORD)
	if String(war.get("state", "")) == "active":
		_tick_active(war)
	elif clan != "" and int(war.get("month", -1)) != _month():
		_start(clan)


# Months since the start of the calendar, so each month has its own event
func _month() -> int:
	return (world.clock.day - 1 + WorldClock.START_MONTH * WorldClock.DAYS_PER_MONTH) / WorldClock.DAYS_PER_MONTH


## A rival attacks one land the player's clan rules (nothing happens if it rules none)
func _start(clan: String) -> void:
	var month := _month()
	var held: Array[int] = []
	for i in world.map.placements.size():
		var key := world.map.placements[i].biome.get_key()
		if ClanTerritory.START.has(key) and ClanTerritory.ruler(key) == clan:
			held.append(i)
	if held.is_empty():
		WorldState.set_record(RECORD, {"month": month, "state": "none"})
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|clanwar|%d" % [world.world_seed, month]).hash()
	var i: int = held[rng.randi_range(0, held.size() - 1)]
	var land := world.map.placements[i].biome
	var scores := ClanTerritory.scores(land.get_key())
	var attacker := ""
	for c in ClanTerritory.CLANS:
		if c != clan and (attacker == "" or int(scores[c]) > int(scores[attacker])):
			attacker = c
	var rect := world.map.get_placement_rect(i)
	var spot := rect.position + rect.size * Vector2(rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7))
	WorldState.set_record(RECORD, {"month": month, "state": "active", "land": land.get_key(), "land_name": land.display_name,
		"attacker": attacker, "clan": clan, "pos": [spot.x, spot.y], "until": world.clock.day + DAYS})
	var text := "The %s are moving on the %s. Their raiders gather there: kill them within %d days or our hold on the land slips." % [
		Factions.display_name(attacker), land.display_name, DAYS]
	Locks.toast(get_tree(), "Clan war: the %s attack the %s" % [Factions.display_name(attacker), land.display_name], true)
	_journal(text)


func _tick_active(war: Dictionary) -> void:
	var keys := _keys(war)
	var dead := 0
	for k in keys:
		if WorldState.has_record("kill/" + k):
			dead += 1
	if dead >= keys.size():
		war["state"] = "won"
		WorldState.set_record(RECORD, war)
		ClanTerritory.gain(String(war["land"]), String(war["clan"]), ClanTerritory.GAIN / 2)
		Locks.toast(get_tree(), "The %s raid on the %s is broken." % [Factions.display_name(String(war["attacker"])), war["land_name"]])
		_journal("The raiders are dead and the %s still answers to the %s." % [war["land_name"], Factions.display_name(String(war["clan"]))])
		return
	if world.clock.day > int(war["until"]):
		war["state"] = "lost"
		WorldState.set_record(RECORD, war)
		ClanTerritory.lose(String(war["land"]), String(war["clan"]), LOSS)
		for e in _spawned.values():
			if is_instance_valid(e):
				e.queue_free()
		_spawned.clear()
		Locks.toast(get_tree(), "The %s hold the night in the %s now." % [Factions.display_name(String(war["attacker"])), war["land_name"]], true)
		_journal("Too late. The %s took the %s's nights while we waited." % [Factions.display_name(String(war["attacker"])), war["land_name"]])
		return
	_spawn_raiders(war, keys)


func _keys(war: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for n in RAIDERS:
		out.append("clanwar/%d/%d" % [int(war["month"]), n])
	return out


# The raiders appear once the player is close, like quest foes
func _spawn_raiders(war: Dictionary, keys: Array[String]) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var at := Vector3(float(war["pos"][0]), 0.0, float(war["pos"][1]))
	if p == null or Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() > SPAWN_NEAR:
		return
	var body := load("res://data/enemies/vampire.tres") as EnemyData
	if body == null:
		return
	var zone := LevelCurve.zone_range(world.map, at)
	for n in keys.size():
		var key := keys[n]
		if WorldState.has_record("kill/" + key) or (_spawned.has(key) and is_instance_valid(_spawned[key])):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = key.hash()
		var ang := rng.randf() * TAU
		var pos := at + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(3.0, 10.0)
		pos.y = world.get_height_at(pos.x, pos.z) + 0.6
		var e := Population.spawn_enemy(body, zone.y + 1, world, pos, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
		e.display_name = "%s Raider" % Factions.display_name(String(war["attacker"])).trim_prefix("The ")
		_spawned[key] = e


func _journal(text: String) -> void:
	DialogueState.add_journal({"text": text, "speaker": Factions.display_name(ClanTerritory.player_clan()), "topic": "the territory war",
		"day": world.clock.day, "time": world.clock.get_time_text(), "quest_id": "clan_war", "quest_name": "The Territory War"})


## The raid to stop (a compass and map target), or {}
static func target() -> Dictionary:
	var war := WorldState.get_record(RECORD)
	if String(war.get("state", "")) != "active":
		return {}
	return {"pos": Vector2(float(war["pos"][0]), float(war["pos"][1])), "name": "Clan raid on the %s" % war["land_name"], "id": "clan_war"}
