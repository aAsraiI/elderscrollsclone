class_name Roamers
extends Node
## Alpha 1.31.3: big things on the move, under WorldManager. Every few minutes in the wilds something
## crosses the land near you, walking a line from one horizon to the other, not looking for you:
##   caravan  a merchant and guards heading between towns (friendly; they keep walking)
##   giant    a frost giant on the march (level 15 and up)
##   dragon   a dragon crossing the land (level 30 and up; rare)
## They come for you only if they notice you. They are not saved, and are gone once far behind you.

const GAP_MIN := 240.0
const GAP_MAX := 480.0
const SPAWN_DIST := 140.0
const GONE_DIST := 420.0

var enabled := true
var world: WorldManager
var _t := 120.0
var _alive: Array[Enemy] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("roamers")
	world = get_parent() as WorldManager
	_rng.randomize()


static func of(tree: SceneTree) -> Roamers:
	return tree.get_first_node_in_group("roamers") as Roamers


func _process(delta: float) -> void:
	if not enabled or get_tree().paused:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = _rng.randf_range(GAP_MIN, GAP_MAX) / maxf(float(GameRules.get_rule("encounter_rate")), 0.1)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or world == null or (world.dungeons != null and world.dungeons.is_inside()):
		return
	_tidy(player)
	if not _alive.is_empty() or float(GameRules.get_rule("encounter_rate")) <= 0.0:
		return
	var town := world.get_nearest_town(player.global_position)
	if town != null and town.position.distance_to(player.global_position) < town.poi.footprint_radius + 80.0:
		return
	send(pick_kind(player), player)


func _tidy(player: Node3D) -> void:
	for e in _alive.duplicate():
		if not is_instance_valid(e) or e.is_dead():
			_alive.erase(e)
		elif e.global_position.distance_to(player.global_position) > GONE_DIST:
			e.queue_free()
			_alive.erase(e)


func pick_kind(player: Node) -> String:
	var sk := player.get_node_or_null("Skills") as Skills
	var lvl := sk.get_player_level() if sk != null else 1
	var r := _rng.randf()
	if lvl >= 30 and r < 0.15:
		return "dragon"
	if lvl >= 15 and r < 0.5:
		return "giant"
	return "caravan"


## Sends one across. Returns who walks.
func send(kind: String, player: Node3D) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var a := _rng.randf() * TAU
	var from := player.global_position + Vector3(cos(a), 0, sin(a)) * SPAWN_DIST
	var side := Vector3(-sin(a), 0, cos(a)) * _rng.randf_range(-50.0, 50.0)
	var to := player.global_position - Vector3(cos(a), 0, sin(a)) * (GONE_DIST + 60.0) + side
	from.y = world.get_height_at(from.x, from.z) + 0.6
	to.y = world.get_height_at(to.x, to.z)
	if from.y < world.map.get_water_level(from.x, from.z) + 0.3:
		return out
	var sk := player.get_node_or_null("Skills") as Skills
	var lvl := sk.get_player_level() if sk != null else 5
	var who: Array = []
	match kind:
		"caravan":
			who = [["merchant", "Caravan Merchant", Enemy.Disposition.FRIENDLY], ["caravan_guard", "Caravan Guard", Enemy.Disposition.FRIENDLY], ["caravan_guard", "Caravan Guard", Enemy.Disposition.FRIENDLY]]
		"giant":
			who = [["frost_giant", "", Enemy.Disposition.HOSTILE]]
		"dragon":
			who = [["dragon", "", Enemy.Disposition.HOSTILE]]
	var i := 0
	for w in who:
		var data := load("res://data/enemies/%s.tres" % w[0]) as EnemyData
		if data == null:
			continue
		var at := from + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)) - Vector3(cos(a), 0, sin(a)) * 3.0 * i
		var e := Population.spawn_enemy(data, lvl, world, at, _rng, {"persist_mode": Enemy.PersistMode.NEVER})
		if e == null:
			continue
		if String(w[1]) != "":
			e.display_name = String(w[1])
		e.disposition = w[2]
		e.set_meta("roamer", kind)
		e.follow_route.call_deferred(PackedVector3Array([to]), false, 0.7)
		out.append(e)
		_alive.append(e)
		i += 1
	if kind != "caravan" and not out.is_empty():
		Locks.toast(get_tree(), "The ground shakes. Something big is moving out there." if kind == "giant" else "A great shadow passes overhead...")
	return out
