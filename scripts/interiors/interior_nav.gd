class_name InteriorNav
extends Node3D
## How the living find their way round a stitched dungeon: the rooms joined at their doorways
## (the plan's links) make a graph, and a path is the doorways between one room and another, so
## enemies chase you through doorways and up stairs and followers keep up. It also gives the
## dungeon's people something to do:
##   patrols    one or two walk a loop between their room and the next ones
##   guards     stand at their post facing the way in
##   sleepers   lie in the barracks' bunks until you come close or hit them
##   sitters    sit at the mess and kitchen tables
##   ambushers  wait quietly in side rooms (and up on galleries) until you walk past
##   fall back  a hurt one runs back to a deeper room, where its friends are
##   doors      a locked door bangs open for an enemy hunting you through it
## DungeonManager adds one to every stitched dungeon.

const THINK := 0.25

var plan: DungeonAssembler
var rooms: Array[RoomModule] = []
var _adjacent := {}   # room -> [[other room, door position (local)], ...]
var _player_room := -1
var _clock := 0.0
var ambushers: Array[Enemy] = []
var patrols: Array[Enemy] = []
var dungeon_id := ""


static func make(root: Node3D, p_plan: DungeonAssembler, nav_seed: int) -> InteriorNav:
	var n := InteriorNav.new()
	n.name = "Nav"
	n.plan = p_plan
	for c in root.get_children():
		if c is RoomModule:
			n.rooms.append(c)
	for l: Array in p_plan.links:
		var a := int(l[0])
		var b := int(l[2])
		var door: Vector3 = p_plan.door_world(p_plan.placed[a], int(l[1]))["pos"]
		n._adjacent[a] = n._adjacent.get(a, []) + [[b, door]]
		n._adjacent[b] = n._adjacent.get(b, []) + [[a, door]]
	root.add_child(n)
	n._give_roles(nav_seed)
	return n


## Which room a point (in the dungeon's space) is in, or -1
func room_at(local: Vector3) -> int:
	var cell := Vector3i(floori(local.x / RoomModule.CELL), floori((local.y + 0.5) / RoomModule.LEVEL), floori(local.z / RoomModule.CELL))
	return int(plan.occupied.get(cell, -1))


func room_of(node: Node3D) -> int:
	return room_at((get_parent() as Node3D).to_local(node.global_position))


## The way from one point to another (world space): through each doorway between their rooms,
## ending at `to`. Straight there when they share a room (or either is outside every room).
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var root := get_parent() as Node3D
	var a := room_at(root.to_local(from))
	var b := room_at(root.to_local(to))
	var out := PackedVector3Array()
	if a >= 0 and b >= 0 and a != b:
		var prev := {a: [-1, Vector3.ZERO]}
		var queue := [a]
		while not queue.is_empty() and not prev.has(b):
			var r: int = queue.pop_front()
			for e: Array in _adjacent.get(r, []):
				if not prev.has(int(e[0])):
					prev[int(e[0])] = [r, e[1]]
					queue.append(int(e[0]))
		if prev.has(b):
			var doors: Array = []
			var r := b
			while r != a:
				doors.push_front(prev[r][1])
				r = int(prev[r][0])
			for d: Vector3 in doors:
				out.append(root.to_global(d + Vector3(0, 0.3, 0)))
	out.append(to)
	return out


## The centre of a room (world space), on its floor
func room_center(i: int) -> Vector3:
	var room := rooms[i]
	return room.global_transform * Vector3(0, 0.2, 0)


# Hands the dungeon's people their roles, from their socket tags and their rooms
func _give_roles(nav_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nav_seed
	var deepest := 0
	for p in plan.placed:
		deepest = maxi(deepest, p.depth)
	var side_rooms := {}
	for i in rooms.size():
		var links: Array = _adjacent.get(i, [])
		if links.size() == 1 and i > 0 and plan.placed[i].entry.role in [RoomModule.Role.ROOM, RoomModule.Role.DEAD_END] and rng.randf() < 0.45:
			side_rooms[i] = true
	var patrol_left := 2
	for i in rooms.size():
		var room := rooms[i]
		for e in room.find_children("*", "Enemy", true, false):
			var enemy := e as Enemy
			if enemy == null or enemy.is_dead():
				continue
			enemy.path_provider = path
			enemy.path_always = true
			# a deeper room to fall back to
			var back := _deeper_neighbour(i)
			if back >= 0:
				enemy.set_meta("fallback", room_center(back))
			var tags := _socket_tags(enemy)
			if tags.has("sleeper") and enemy.body_kind == CreatureBody.Kind.HUMANOID:
				enemy.sleep()
			elif (tags.has("eating") or tags.has("cook")) and enemy.body != null:
				enemy.body.pose = &"sit" if tags.has("eating") else &""
				enemy.wander_radius = 0.0
			elif tags.has("guard") or tags.has("officer"):
				enemy.wander_radius = 0.0
				var way_in := _way_in(i)
				if way_in != Vector3.INF:
					var to := way_in - enemy.global_position
					enemy.rotation.y = atan2(-to.x, -to.z)
			elif tags.has("ambush") or side_rooms.has(i):
				_ambusher(enemy, i)
			elif patrol_left > 0 and plan.placed[i].entry.role in [RoomModule.Role.CORRIDOR, RoomModule.Role.JUNCTION] and not _adjacent.get(i, []).is_empty():
				_patrol(enemy, i)
				patrol_left -= 1


func _socket_tags(e: Enemy) -> PackedStringArray:
	var s := e.get_parent() as SpawnSocket
	if s == null:
		var key := e.spawn_key  # "<room id>/<socket name>/<n>"
		var parts := key.split("/")
		if parts.size() >= 2:
			var room := e.get_parent()
			s = room.get_node_or_null(NodePath(parts[parts.size() - 2])) as SpawnSocket if room != null else null
	return s.tags if s != null else PackedStringArray()


func _deeper_neighbour(i: int) -> int:
	var best := -1
	for e: Array in _adjacent.get(i, []):
		var j := int(e[0])
		if plan.placed[j].depth > plan.placed[i].depth and (best < 0 or plan.placed[j].depth > plan.placed[best].depth):
			best = j
	return best


# The doorway a room is entered by from the entrance side (world space)
func _way_in(i: int) -> Vector3:
	for e: Array in _adjacent.get(i, []):
		if plan.placed[int(e[0])].depth < plan.placed[i].depth:
			return (get_parent() as Node3D).to_global(e[1])
	return Vector3.INF


func _ambusher(e: Enemy, room: int) -> void:
	e.set_meta("ambush_room", room)
	e.wander_radius = 0.0
	e.lurk(true)
	ambushers.append(e)


func _patrol(e: Enemy, room: int) -> void:
	var pts := PackedVector3Array([room_center(room)])
	var next: Array = _adjacent[room][0]
	var root := get_parent() as Node3D
	pts.append(root.to_global(Vector3(next[1]) + Vector3(0, 0.3, 0)))
	pts.append(room_center(int(next[0])))
	pts.append(root.to_global(Vector3(next[1]) + Vector3(0, 0.3, 0)))
	e.follow_route(pts, true, 0.4)
	patrols.append(e)


func _physics_process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = THINK
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var here := room_of(p)
	if here != _player_room and here >= 0:
		_player_room = here
		_spring_ambush(here)
		_mark_explored(here)
	_open_doors_for_hunters()


# You walk into or past an ambusher's room: they all come at once
func _spring_ambush(here: int) -> void:
	var near := {here: true}
	for e: Array in _adjacent.get(here, []):
		near[int(e[0])] = true
	var p := get_tree().get_first_node_in_group("player") as Node3D
	for e in ambushers.duplicate():
		if not is_instance_valid(e) or e.is_dead():
			ambushers.erase(e)
			continue
		if near.has(int(e.get_meta("ambush_room", -1))):
			e.lurk(false)
			e.aggro(p)
			ambushers.erase(e)


# A locked door gives way to an enemy hunting you through it (not a lever's gate)
func _open_doors_for_hunters() -> void:
	var root := get_parent() as Node3D
	for d in root.find_children("*", "InteriorDoor", true, false):
		var door := d as InteriorDoor
		if door.is_gate or door.is_queued_for_deletion():
			continue
		for e in ActorRegistry.near(door.global_position, 1.8):
			if e.disposition == Enemy.Disposition.HOSTILE and e.state == Enemy.State.CHASE and not e.has_meta("player_ally"):
				Locks.toast(get_tree(), "A door bangs open somewhere")
				door.open()
				break


## Is room i of this kind ("boss", "entrance", or a room kind like "war_room")?
func room_is(i: int, kind: String) -> bool:
	var e = plan.placed[i].entry
	match kind:
		"boss":
			return e.role == RoomModule.Role.BOSS
		"entrance":
			return e.role == RoomModule.Role.ENTRANCE
	return e.kind == kind


## The boss's room, or -1
func boss_room() -> int:
	for p in plan.placed:
		if p.entry.role == RoomModule.Role.BOSS:
			return p.index
	return -1


## The rooms you have walked into here (the dungeon map shows these)
func explored() -> Array:
	return WorldState.get_record("explored/" + dungeon_id).get("rooms", [])


func _mark_explored(i: int) -> void:
	if dungeon_id == "":
		return
	var rooms_seen: Array = explored()
	if not rooms_seen.has(i):
		rooms_seen.append(i)
		WorldState.set_record("explored/" + dungeon_id, {"rooms": rooms_seen})
