class_name WildLife
extends Node
## Alpha 1.24: the animals of the land (data/world/wildlife.json). Created by WorldManager.
##   - a few groups live in a ring around you (out of sight, 90-170 m off), picked by the land you are
##     in, the time of day and the season; groups too far behind are let go
##   - herds follow their lead animal; packs have a bigger alpha (a named one on the islands)
##   - deer and elk run from you when they see, hear or smell you (sneaking and the wind help), and
##     from wolves and bears; predators hunt them (CreatureFactions: beasts and prey are at war)
##   - a cleared den or nest keeps its land free of predators for a week
##   - now and then a legend: the white stag, the Old Tusker, the Ancient Bear (one of each in a game),
##     and hunters talk about it
## Everything runs on a slow tick and spawns through SpawnQueue, so it never costs a frame.

const PATH := "res://data/world/wildlife.json"
const MAX_GROUPS := 3
const RING_NEAR := 90.0
const RING_FAR := 170.0
const LET_GO := 320.0
const TOWN_CLEAR := 140.0
const PREY_EVERY := 0.5
const SPAWN_EVERY := 6.0
const LEGEND_CHANCE := 0.03
const DEN_QUIET_DAYS := 7
const DEN_RADIUS := 350.0
const PREDATORS := ["wolf", "frost_bear", "ash_hound", "dune_stalker", "fox", "ancient_bear"]

var world: WorldManager
var enabled := true
var groups: Array = []  # {"kind", "members": Array[Enemy], "leader": Enemy, "prey": bool}
var _data := {}
var _spawn_t := 3.0
var _prey_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("wild_life")
	world = get_parent() as WorldManager
	_rng.randomize()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_data = d


func _process(delta: float) -> void:
	if world == null or world.map == null or get_tree().paused:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var inside := world.dungeons != null and world.dungeons.is_inside()
	_prey_t -= delta
	if _prey_t <= 0.0:
		_prey_t = PREY_EVERY
		_tend(p)
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t = SPAWN_EVERY
	_let_go(p)
	if not enabled or inside or groups.size() >= MAX_GROUPS or _near_town(p.global_position):
		return
	_spawn_group(p)


# ---------------------------------------------------------------- spawning

func _spawn_group(p: Node3D) -> void:
	var at := _spot(p)
	if not at.is_finite():
		return
	var land := _land_at(at)
	var legend := _maybe_legend(land, at)
	var entry: Dictionary = legend if not legend.is_empty() else _pick(land, at)
	if entry.is_empty():
		return
	spawn(entry, at, not legend.is_empty())


## One group of entry["kind"] (a wildlife.json entry) around `at`; returns the group
func spawn(entry: Dictionary, at: Vector3, is_legend: bool = false) -> Dictionary:
	var legend := entry if is_legend else {}
	var data := _data_for(String(entry["kind"]))
	if data == null:
		return {}
	var span: Array = entry.get("group", [1, 1])
	var n := 1 if not legend.is_empty() else _rng.randi_range(int(span[0]), int(span[1]))
	var zone := LevelCurve.zone_range(world.map, at)
	var g := {"kind": String(entry["kind"]), "members": [], "leader": null, "prey": CreatureFactions.relation(String(_faction_of(String(entry["kind"]))), "beasts") == CreatureFactions.Rel.HOSTILE}
	var was := SpawnQueue.defer
	SpawnQueue.defer = true
	for i in n:
		var pos := at + Vector3(_rng.randf_range(-4.0, 4.0), 0.0, _rng.randf_range(-4.0, 4.0))
		pos.y = world.get_height_at(pos.x, pos.z) + 0.6
		var e := Population.spawn_enemy(data, _rng.randi_range(zone.x, zone.y), world, pos, _rng, {"persist_mode": Enemy.PersistMode.NEVER})
		e.set_meta("wild", true)
		if i == 0:
			g["leader"] = e
			if bool(entry.get("pack", false)) and n > 1:
				_make_alpha(e, zone.y)
		elif bool(entry.get("herd", false)) or bool(entry.get("pack", false)):
			e.set_meta("follows", true)
		if not legend.is_empty():
			e.set_meta("legend", String(entry["kind"]))
		(g["members"] as Array).append(e)
	SpawnQueue.defer = was
	groups.append(g)
	return g


func _make_alpha(e: Enemy, level: int) -> void:
	e.body_scale *= 1.25
	e.max_health *= 1.5
	e.damage_mult *= 1.2
	var islands := level >= 100
	e.display_name = ("%s the %s" % [NameGen.person(_rng).get_slice(" ", 0), "Alpha"]) if islands else "Pack Alpha"
	e.set_meta("alpha", true)


# A spot on open ground in the ring around you, behind or beside you (not straight ahead, where you
# would see it appear), dry, not too steep
func _spot(p: Node3D) -> Vector3:
	var fwd := -p.global_transform.basis.z
	var face := atan2(fwd.x, fwd.z)
	for attempt in 6:
		var ang := face + PI + _rng.randf_range(-1.9, 1.9)
		var d := _rng.randf_range(RING_NEAR, RING_FAR)
		var x := p.global_position.x + sin(ang) * d
		var z := p.global_position.z + cos(ang) * d
		var y := world.get_height_at(x, z)
		if y < world.map.get_water_level(x, z) + 0.3:
			continue
		var slope := absf(world.get_height_at(x + 2.0, z) - y) + absf(world.get_height_at(x, z + 2.0) - y)
		if slope > 2.2:
			continue
		return Vector3(x, y, z)
	return Vector3.INF


func _land_at(at: Vector3) -> String:
	var b := world.get_biome_at(at.x, at.z)
	return String(b.id) if b != null else "default"


# A weighted pick of what lives in this land now (time of day, season, a cleared den nearby)
func _pick(land: String, at: Vector3) -> Dictionary:
	var lands: Dictionary = _data.get("lands", {})
	var list: Array = lands.get(land, lands.get("default", []))
	var night := world.clock != null and world.clock.is_night()
	var season := world.clock.get_season() if world.clock != null else 1
	var quiet := _den_quiet(at)
	var ok: Array = []
	var total := 0
	for en: Dictionary in list:
		var t := String(en.get("time", "any"))
		if (t == "day" and night) or (t == "night" and not night):
			continue
		if en.has("seasons") and not (en["seasons"] as Array).has(season):
			continue  # bears sleep through the winter
		if quiet and PREDATORS.has(String(en["kind"])):
			continue
		ok.append(en)
		total += int(en.get("weight", 1))
	if ok.is_empty():
		return {}
	var roll := _rng.randi_range(0, total - 1)
	for en: Dictionary in ok:
		roll -= int(en.get("weight", 1))
		if roll < 0:
			return en
	return ok[0]


func _maybe_legend(land: String, at: Vector3) -> Dictionary:
	if _rng.randf() > LEGEND_CHANCE:
		return {}
	for lg: Dictionary in _data.get("legends", []):
		var kind := String(lg["kind"])
		if not (lg.get("lands", []) as Array).has(land) or WorldState.has_record("legend/" + kind):
			continue
		var alive := false
		for g in groups:
			if String(g["kind"]) == kind:
				alive = true
		if alive:
			continue
		var town := _nearest_town_name(at)
		if town != "" and lg.has("rumor"):
			Rumors.add("legend", String(lg["rumor"]) % town, at, Rumors._day())
		return {"kind": kind, "group": [1, 1]}
	return {}


func _data_for(kind: String) -> EnemyData:
	for dir in ["enemies", "npcs"]:
		var path := "res://data/%s/%s.tres" % [dir, kind]
		if ResourceLoader.exists(path):
			return load(path) as EnemyData
	return null


func _faction_of(kind: String) -> String:
	CreatureFactions.all()
	return String(CreatureFactions._members.get(kind, "beasts"))


# ---------------------------------------------------------------- living

# Herds follow the lead animal; prey run from you and from predators; a legend's death is remembered
func _tend(p: Node3D) -> void:
	var ppos := p.global_position
	var sneaking := p.has_meta("stealth") and is_instance_valid(p.get_meta("stealth")) and bool(p.get_meta("stealth").get("sneaking"))
	var wind := wind_dir()
	for g in groups:
		var leader: Enemy = g["leader"]
		var lead_ok := leader != null and is_instance_valid(leader) and not leader.is_dead() and leader.is_inside_tree()
		for e in g["members"]:
			if not is_instance_valid(e) or not (e as Enemy).is_inside_tree():
				continue
			var en := e as Enemy
			if en.is_dead():
				if en.has_meta("legend") and not WorldState.has_record("legend/" + String(en.get_meta("legend"))):
					WorldState.set_record("legend/" + String(en.get_meta("legend")), {"day": Rumors._day()})
				continue
			if ActorLOD.is_frozen(en):
				continue
			if lead_ok and en != leader and en.has_meta("follows") and en.get_fight_target() == null:
				en._home = leader.global_position  # wander around the lead animal
				if en.global_position.distance_to(leader.global_position) > 12.0 and en.state == Enemy.State.IDLE:
					en.follow_route(PackedVector3Array([leader.global_position]), false, 0.8)
			if bool(g["prey"]):
				_prey_watch(en, ppos, sneaking, wind)


# A deer notices you further off upwind of it, less when you sneak; and a predator near it
func _prey_watch(e: Enemy, ppos: Vector3, sneaking: bool, wind: Vector2) -> void:
	if e.state == Enemy.State.FLEE:
		return
	var to_me := Vector2(ppos.x - e.global_position.x, ppos.z - e.global_position.z)
	var d := to_me.length()
	var reach := e.detection_range * (0.45 if sneaking else 1.0)
	if d > 0.01:
		# the wind blowing from you to it carries your scent: further; from it to you: nearer
		var carried := -to_me.normalized().dot(wind)
		reach *= 1.0 + 0.5 * carried
	if d < reach:
		e.flee_from(get_tree().get_first_node_in_group("player") as Node3D, 7.0)
		return
	for other in ActorRegistry.near(e.global_position, 20.0):
		if other != e and not other.is_dead() and CreatureFactions.relation(CreatureFactions.of(other), CreatureFactions.of(e)) == CreatureFactions.Rel.HOSTILE:
			e.flee_from(other, 7.0)
			return


## Where the wind blows (x, z): it turns slowly through the day
func wind_dir() -> Vector2:
	var h := world.clock.hour + float(world.clock.day) * 24.0 if world != null and world.clock != null else 0.0
	return Vector2.from_angle(h * 0.31 + sin(h * 0.07) * 1.3)


func _let_go(p: Node3D) -> void:
	var keep: Array = []
	for g in groups:
		var alive: Array = []
		for e in g["members"]:
			if is_instance_valid(e) and not (e as Enemy).is_queued_for_deletion():
				alive.append(e)
		g["members"] = alive
		var far := true
		var any_alive := false
		for e in alive:
			var en := e as Enemy
			if not en.is_inside_tree():
				far = false  # still on its way in
				any_alive = true
				continue
			if not en.is_dead():
				any_alive = true
			if en.global_position.distance_to(p.global_position) < LET_GO:
				far = false
		if far:
			for e in alive:
				(e as Node).queue_free()
			continue
		if any_alive:
			keep.append(g)
	groups = keep


# ---------------------------------------------------------------- places

func _near_town(pos: Vector3) -> bool:
	for t in world.towns:
		if Vector2(t.position.x - pos.x, t.position.z - pos.z).length() < TOWN_CLEAR:
			return true
	return false


func _nearest_town_name(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for t in world.towns:
		var d := t.position.distance_to(pos)
		if d < best_d and t.town != null:
			best_d = d
			best = t.town.display_name
	return best


# A den or nest cleared within the last week keeps predators away from the land around it
func _den_quiet(at: Vector3) -> bool:
	var today := Rumors._day()
	for poi in world.pois:
		var key := String(poi.poi.get_key())
		if not (key.contains("den") or key.contains("nest")):
			continue
		if Vector2(poi.position.x - at.x, poi.position.z - at.z).length() > DEN_RADIUS:
			continue
		if not Discovery.is_cleared(poi.id):
			continue
		var rec := WorldState.get_record("den_quiet/" + poi.id)
		if rec.is_empty():
			WorldState.set_record("den_quiet/" + poi.id, {"day": today})
			return true
		if today - int(rec.get("day", today)) < DEN_QUIET_DAYS:
			return true
	return false
