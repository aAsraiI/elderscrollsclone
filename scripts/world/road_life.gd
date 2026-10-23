class_name RoadLife
extends Node
## People on the roads near the player. Created by WorldManager, nothing to add by hand.
##
## A few travellers are kept on the roads around you (never more than max_groups). Each appears
## on a road 90-180 m away, walks along it toward a town, and is removed once far behind you or
## at the end of the road. Nothing here is saved: the roads are simply busy.
##   road wardens        two guards on patrol; they fight creatures that come near
##   travelling merchant  barter with them (Barter, MerchantData "peddler")
##   traveller            a wanderer or pilgrim on their way somewhere

signal group_spawned(kind: String, members: Array)

@export var enabled := true
@export var max_groups := 3
## Seconds between checks
@export var interval := 6.0
## How far from the player a group may appear (m)
@export var spawn_min := 90.0
@export var spawn_max := 180.0
## Groups this far away are removed (m)
@export var despawn_distance := 320.0
## Only roads this close to the player count (m)
@export var road_reach := 250.0

const KINDS := ["wardens", "merchant", "traveller"]
const WEIGHTS := [0.4, 0.35, 0.25]
const GUARD_BODY := "res://data/npcs/town_guard.tres"
const FOLK_BODY := "res://data/npcs/townsfolk.tres"
const WALK := 0.42

var world: WorldManager
var groups: Array[Dictionary] = []  # {"kind", "members": Array[Enemy]}
var _timer := 3.0
var _rng := RandomNumberGenerator.new()
var _count := 0


func _ready() -> void:
	add_to_group("road_life")
	world = get_parent() as WorldManager
	_rng.randomize()


func _process(delta: float) -> void:
	if not enabled or world == null or world.map == null or world.map.roads == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	tick()


## One check: clean up, defend, and maybe add a group. Tests call it directly.
func tick(force: bool = false) -> Array:
	var p := _player()
	if p == null:
		return []
	_cleanup(p)
	_defend()
	if world.dungeons != null and world.dungeons.is_inside():
		return []
	if groups.size() >= max_groups or (not force and _rng.randf() < 0.35):
		return []
	return spawn_group(_pick_kind() if not force else KINDS[_count % KINDS.size()])


## Puts a group of this kind on a road near the player. Returns its members ([] if no road fits).
func spawn_group(kind: String) -> Array:
	var p := _player()
	var spot := _find_road_spot(p.global_position)
	if spot.is_empty():
		return []
	var pts: PackedVector3Array = spot["route"]
	var members: Array = []
	var count := 2 if kind == "wardens" else 1
	for i in count:
		var start: Vector3 = pts[0] + Vector3(float(i) * 1.5, 0.6, float(i) * 0.8)
		var e := _make(kind, start, i)
		if e == null:
			continue
		var route := PackedVector3Array()
		for q in pts:
			route.append(q + Vector3(float(i) * 1.2, 0.1, 0.0))
		e.follow_route(route, false, WALK)
		e.route_finished.connect(func() -> void:
			if is_instance_valid(e):
				e.queue_free())
		members.append(e)
	if members.is_empty():
		return []
	_count += 1
	groups.append({"kind": kind, "members": members})
	group_spawned.emit(kind, members)
	return members


# ---------------------------------------------------------------- where

# A road point out at the right distance, and the road ahead of it (toward the end further away)
func _find_road_spot(from: Vector3) -> Dictionary:
	var roads := world.map.roads.get_roads()
	var options: Array = []
	for r in roads:
		var road_pts: PackedVector3Array = r["points"]
		for i in range(0, road_pts.size(), 4):
			var d := Vector2(road_pts[i].x - from.x, road_pts[i].z - from.z).length()
			if d >= spawn_min and d <= spawn_max:
				options.append([road_pts, i])
	if options.is_empty():
		return {}
	var pick: Array = options[_rng.randi_range(0, options.size() - 1)]
	var pts: PackedVector3Array = pick[0]
	var i: int = pick[1]
	# walk toward the end that leads past the player, so they are seen
	var forward := pts.slice(i)
	var back := pts.slice(0, i + 1)
	back.reverse()
	var toward := forward if forward.size() > 3 and from.distance_to(forward[mini(10, forward.size() - 1)]) < from.distance_to(pts[i]) else back
	if toward.size() < 3:
		toward = forward if forward.size() >= back.size() else back
	var route := PackedVector3Array()
	for k in range(0, toward.size(), 3):
		var q := toward[k]
		route.append(Vector3(q.x, world.get_height_at(q.x, q.z), q.z))
	return {"route": route}


func _pick_kind() -> String:
	var roll := _rng.randf()
	for k in KINDS.size():
		roll -= WEIGHTS[k]
		if roll <= 0.0:
			return KINDS[k]
	return KINDS[0]


# ---------------------------------------------------------------- who

func _make(kind: String, at: Vector3, index: int) -> Enemy:
	var body := load(GUARD_BODY if kind == "wardens" else FOLK_BODY) as EnemyData
	if body == null:
		return null
	var level := LevelCurve.zone_range(world.map, at)
	var e := Enemy.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	body.apply(e, level.y + 2 if kind == "wardens" else level.x, rng)
	e.persist_mode = Enemy.PersistMode.NEVER
	e.wander_radius = 0.0
	var who := NameGen.person(rng)
	match kind:
		"wardens":
			e.display_name = "Road Warden"
			e.talk_name = "Road Warden"
			e.talk_lines = PackedStringArray(["Keep to the road. It's safer.", "We ride between the towns. Bandits think twice when they see us."])
			e.placeholder_color = Color(0.32, 0.38, 0.5)
			e.set_meta("road_warden", true)
		"merchant":
			e.display_name = "%s, Travelling Merchant" % NameGen.first_name(who)
			e.talk_name = e.display_name
			e.talk_lines = PackedStringArray(["Wares from every town on this road. Have a look!", "Buying and selling, friend. Mostly selling."])
			e.placeholder_color = Color(0.55, 0.4, 0.2)
			e.set_meta("merchant", "peddler")
			e.set_meta("shop_id", "road/%d" % _rng.randi())
		_:
			e.display_name = who if index == 0 else "Pilgrim"
			e.talk_name = e.display_name
			e.talk_lines = PackedStringArray(["Long road. Good weather, at least.", "Heading to the next town. You?"])
			e.placeholder_color = Color(0.4, 0.45, 0.35)
	e.position = at
	world.add_child(e)
	e.global_position = at
	return e


# Road wardens go for any creature that comes near them
func _defend() -> void:
	for g in groups:
		if g["kind"] != "wardens":
			continue
		for member in g["members"]:
			if not is_instance_valid(member):
				continue
			var w := member as Enemy
			if not is_instance_valid(w) or w.is_dead() or w.state == Enemy.State.CHASE or w.state == Enemy.State.ATTACK:
				continue
			for n in get_tree().get_nodes_in_group("enemies"):
				var foe := n as Enemy
				if foe != null and not foe.is_dead() and foe.disposition == Enemy.Disposition.HOSTILE and not foe.has_meta("npc_id") \
						and foe.global_position.distance_to(w.global_position) < 30.0:
					w.fight(foe)
					break


func _cleanup(p: Node3D) -> void:
	for gi in range(groups.size() - 1, -1, -1):
		var alive: Array = []
		for member in groups[gi]["members"]:  # untyped: a member may already be freed
			if not is_instance_valid(member) or (member as Enemy).is_queued_for_deletion():
				continue
			var e := member as Enemy
			if e.global_position.distance_to(p.global_position) > despawn_distance:
				e.queue_free()  # far behind: gone (a corpse too)
				continue
			if not e.is_dead():
				alive.append(e)
		if alive.is_empty():
			groups.remove_at(gi)
		else:
			groups[gi]["members"] = alive


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
