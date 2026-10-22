class_name TownLayout
extends RefCounted
## The plan of one settlement: its streets, its buildings (BuildingPlot) and where roads come in
## (gates). Pure data, made once from the seed when the world is planned, so the same world always
## has the same town. TownBuilder turns it into boxes when the town's chunk loads.
##
## Town local space: the origin is the middle of the town (the plaza), the main street runs along X
## and ends in the two gates, side streets run along Z. The whole town turns with the POI's yaw.

class Street:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var half_width := 3.0
	var main := false

	func get_rect() -> Rect2:
		var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(half_width, half_width)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(half_width, half_width)
		return Rect2(lo, hi - lo)


const SETBACK := 1.5     # meters between a street's edge and a building's front
const GAP := 2.5         # meters kept free between two buildings
const ANCHOR_STEP := 2.5

var town_id := ""
var display_name := ""
var data: TownData
## World position of the town's middle, and its turn
var origin := Vector3.ZERO
var yaw := 0.0
## Buildings stay inside this radius (meters, local)
var radius := 40.0
## > 0: a square wall of this half size surrounds the town
var wall_half := 0.0
## Nothing is built inside this circle around the middle
var plaza_radius := 8.0
var buildings: Array[BuildingPlot] = []
var streets: Array[Street] = []
## Local points at the ends of the main street, where roads join the town
var gates: Array[Vector3] = []

var _rects: Array[Rect2] = []
# Street network for walking (built the first time someone asks for a route)
var _stops: Array[Vector3] = []          # crossings and street ends, local
var _street_stops: Array = []            # per street: Array[int] of stop indices, in order
var _adj: Array = []                     # per stop: Array of [other stop, meters]


static func generate(p_data: TownData, placed: PlacedPOI, town_name: String, map: WorldMap) -> TownLayout:
	var t := TownLayout.new()
	t.data = p_data
	t.town_id = placed.id
	t.display_name = town_name
	t.origin = placed.position
	t.yaw = placed.yaw
	var rng := RandomNumberGenerator.new()
	rng.seed = placed.seed_value ^ 0x70E7
	t._make_streets()
	t._place_buildings(rng)
	for b in t.buildings:
		b.town_id = t.town_id
		b.town_name = town_name
		var w := t.to_world(b.local_pos)
		b.world_pos = Vector3(w.x, map.get_height(w.x, w.z) if map != null else w.y, w.z)
		b.world_yaw = t.yaw + b.local_yaw
	return t


# ---------------------------------------------------------------- queries

func to_world(local: Vector3) -> Vector3:
	return origin + Basis(Vector3.UP, yaw) * local


func to_local(world: Vector3) -> Vector3:
	return Basis(Vector3.UP, yaw).inverse() * (world - origin)


func get_gates_world() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for g in gates:
		var w := to_world(g)
		out.append(Vector3(w.x, origin.y, w.z))
	return out


## Direction a road leaves the town through gate i (world space, flat)
func get_gate_outward(i: int) -> Vector3:
	var g := gates[i]
	return (Basis(Vector3.UP, yaw) * Vector3(g.x, 0.0, g.z)).normalized()


func get_building(index: int) -> BuildingPlot:
	return buildings[index] if index >= 0 and index < buildings.size() else null


func count_kind(kind: BuildingPlot.Kind) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind:
			n += 1
	return n


## Is a world position inside the town (plus a margin)?
func contains(world: Vector3, margin: float = 0.0) -> bool:
	var dx := world.x - origin.x
	var dz := world.z - origin.z
	var r := data.footprint_radius + margin
	return dx * dx + dz * dz <= r * r


## A random spot on the plaza (local), the same for the same `pick`
func get_plaza_spot(pick: int) -> Vector3:
	var a := float(pick % 97) / 97.0 * TAU
	var r := plaza_radius * (0.45 + 0.4 * float((pick / 97) % 7) / 6.0)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## A walking route through the town from one local point to another, along the streets (so it
## never cuts through a house). Local points, starting with `from` and ending with `to`.
func find_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _stops.is_empty():
		_build_street_graph()
	var out := PackedVector3Array([from])
	var pa := _project(from)
	var pb := _project(to)
	if pa.is_empty() or pb.is_empty():
		out.append(to)
		return out
	var sa: int = pa["street"]
	var sb: int = pb["street"]
	var a_pt: Vector3 = pa["point"]
	var b_pt: Vector3 = pb["point"]
	out.append(a_pt)
	if sa != sb:
		# Dijkstra over the crossings, starting from every stop on the first street
		var n := _stops.size()
		var dist := PackedFloat32Array()
		dist.resize(n)
		dist.fill(INF)
		var prev := PackedInt32Array()
		prev.resize(n)
		prev.fill(-1)
		var done := PackedByteArray()
		done.resize(n)
		for i: int in _street_stops[sa]:
			dist[i] = a_pt.distance_to(_stops[i])
		while true:
			var best := -1
			for i in n:
				if done[i] == 0 and dist[i] < INF and (best < 0 or dist[i] < dist[best]):
					best = i
			if best < 0:
				break
			done[best] = 1
			for e in _adj[best]:
				var nd: float = dist[best] + float(e[1])
				if nd < dist[e[0]]:
					dist[e[0]] = nd
					prev[e[0]] = best
		var end := -1
		var end_cost := INF
		for i: int in _street_stops[sb]:
			var c: float = dist[i] + _stops[i].distance_to(b_pt)
			if c < end_cost:
				end_cost = c
				end = i
		var chain: Array[Vector3] = []
		while end >= 0:
			chain.push_front(_stops[end])
			end = prev[end]
		for p in chain:
			if p.distance_to(out[out.size() - 1]) > 0.3:
				out.append(p)
	if b_pt.distance_to(out[out.size() - 1]) > 0.3:
		out.append(b_pt)
	out.append(to)
	return out


# The nearest point on any street: {"street": index, "point": Vector3}
func _project(p: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for i in streets.size():
		var s := streets[i]
		var ab := s.b - s.a
		var t := clampf((p - s.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := s.a + ab * t
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < best_d:
			best_d = d
			best = {"street": i, "point": Vector3(q.x, 0.0, q.z)}
	return best


func _build_street_graph() -> void:
	_stops.clear()
	_street_stops.clear()
	_adj.clear()
	for i in streets.size():
		var s := streets[i]
		var ts: Array[float] = [0.0, 1.0]
		for j in streets.size():
			if j == i:
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(Vector2(s.a.x, s.a.z), Vector2(s.b.x, s.b.z), Vector2(streets[j].a.x, streets[j].a.z), Vector2(streets[j].b.x, streets[j].b.z))
			if hit != null:
				var h: Vector2 = hit
				ts.append(Vector2(s.a.x, s.a.z).distance_to(h) / s.a.distance_to(s.b))
		ts.sort()
		var ids: Array[int] = []
		for t in ts:
			var p := s.a.lerp(s.b, t)
			var id := -1
			for k in _stops.size():
				if _stops[k].distance_to(p) < 0.5:
					id = k
					break
			if id < 0:
				id = _stops.size()
				_stops.append(p)
				_adj.append([])
			if ids.is_empty() or ids[ids.size() - 1] != id:
				ids.append(id)
		_street_stops.append(ids)
		for k in range(1, ids.size()):
			var d := _stops[ids[k - 1]].distance_to(_stops[ids[k]])
			_adj[ids[k - 1]].append([ids[k], d])
			_adj[ids[k]].append([ids[k - 1], d])


# ---------------------------------------------------------------- streets

func _make_streets() -> void:
	radius = maxf(data.flatten_radius, 20.0) * 0.95
	var r := radius
	var main_hw := 3.5 if data.kind == TownData.Kind.CITY else 3.0
	_add_street(Vector3(-r, 0, 0), Vector3(r, 0, 0), main_hw, true)
	gates = [Vector3(-r, 0, 0), Vector3(r, 0, 0)]
	match data.layout_style:
		TownData.LayoutStyle.CLUSTER:
			plaza_radius = 11.0
			_add_street(Vector3(0, 0, -r * 0.6), Vector3(0, 0, r * 0.6), 2.2)
		TownData.LayoutStyle.STREET:
			plaza_radius = 9.0
			for x in [-r * 0.45, r * 0.45]:
				_add_street(Vector3(x, 0, -r * 0.62), Vector3(x, 0, r * 0.62), 2.4)
		TownData.LayoutStyle.GRID:
			plaza_radius = 12.0
			wall_half = r * 0.9
			var l := wall_half - 3.0
			_add_street(Vector3(0, 0, -l), Vector3(0, 0, l), 3.0)
			for k in [-0.5, 0.5]:
				_add_street(Vector3(l * k, 0, -l), Vector3(l * k, 0, l), 2.5)
				_add_street(Vector3(-l, 0, l * k), Vector3(l, 0, l * k), 2.5)
	if data.walls and wall_half <= 0.0:
		wall_half = r * 0.9


func _add_street(a: Vector3, b: Vector3, half_width: float, main: bool = false) -> void:
	var s := Street.new()
	s.a = a
	s.b = b
	s.half_width = half_width
	s.main = main
	streets.append(s)


# ---------------------------------------------------------------- buildings

# Spots beside the streets where a building's front can sit: {"pos", "out", "dist", "dead"}
func _make_anchors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in streets:
		var length := s.a.distance_to(s.b)
		var dir := (s.b - s.a) / length
		var normal := Vector3(-dir.z, 0.0, dir.x)
		var t := ANCHOR_STEP
		while t < length - ANCHOR_STEP:
			var p := s.a + dir * t
			for side in [-1.0, 1.0]:
				var away: Vector3 = normal * side
				out.append({"pos": p + away * (s.half_width + SETBACK), "out": away, "dist": p.length(), "dead": false})
			t += ANCHOR_STEP
	return out


func _place_buildings(rng: RandomNumberGenerator) -> void:
	var d := data
	var wanted: Array[Dictionary] = []  # {"kind", "guild", "trade"}
	for i in d.roll_count(rng, d.temples_min, d.temples_max):
		wanted.append({"kind": BuildingPlot.Kind.TEMPLE})
	var halls := mini(d.roll_count(rng, d.guild_halls_min, d.guild_halls_max), d.guilds.size())
	var guild_order := Array(d.guilds)
	if halls < guild_order.size():  # a town with one hall gets a random guild
		for i in range(guild_order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = guild_order[i]
			guild_order[i] = guild_order[j]
			guild_order[j] = tmp
	for i in halls:
		wanted.append({"kind": BuildingPlot.Kind.GUILD_HALL, "guild": guild_order[i]})
	for i in d.roll_count(rng, d.inns_min, d.inns_max):
		wanted.append({"kind": BuildingPlot.Kind.INN})
	var trades := NameGen.TRADES.keys()
	for i in d.roll_count(rng, d.shops_min, d.shops_max):
		var trade: String = "general" if i == 0 else trades[rng.randi_range(1, trades.size() - 1)]
		wanted.append({"kind": BuildingPlot.Kind.SHOP, "trade": trade})
	for i in d.roll_count(rng, d.smithies_min, d.smithies_max):
		wanted.append({"kind": BuildingPlot.Kind.SMITHY})
	for i in d.roll_count(rng, d.houses_min, d.houses_max):
		wanted.append({"kind": BuildingPlot.Kind.HOUSE})
	for i in d.roll_count(rng, d.farms_min, d.farms_max):
		wanted.append({"kind": BuildingPlot.Kind.FARM})

	var anchors := _make_anchors()
	var used_names := {}
	for w in wanted:
		var plot := _make_plot(w, rng, used_names)
		var order := _anchor_order(anchors, plot.kind, rng)
		for ai in order:  # no spot fits: the town simply has one building less
			var a: Dictionary = anchors[ai]
			if a["dead"]:
				continue
			var away: Vector3 = a["out"]
			plot.local_yaw = atan2(away.x, away.z)  # the front (-Z) looks back at the street
			plot.local_pos = a["pos"] + away * plot.size.z * 0.5
			var rect := plot.get_local_rect()
			if _fits(rect):
				_rects.append(rect)
				plot.index = buildings.size()
				plot.id = "%s/b%d" % [town_id, plot.index]
				buildings.append(plot)
				var dead_zone := rect.grow(GAP + 1.0)
				for other in anchors:
					var p: Vector3 = other["pos"]
					if dead_zone.has_point(Vector2(p.x, p.z)):
						other["dead"] = true
				break


# Which anchors a kind of building tries first: important buildings near the middle, farms at
# the edge, houses anywhere
func _anchor_order(anchors: Array[Dictionary], kind: BuildingPlot.Kind, rng: RandomNumberGenerator) -> Array[int]:
	var keyed: Array = []
	for i in anchors.size():
		if anchors[i]["dead"]:
			continue
		var dist: float = anchors[i]["dist"]
		var key := 0.0
		match kind:
			BuildingPlot.Kind.TEMPLE, BuildingPlot.Kind.GUILD_HALL, BuildingPlot.Kind.INN, BuildingPlot.Kind.SHOP:
				key = dist + rng.randf() * 6.0
			BuildingPlot.Kind.SMITHY:
				key = absf(dist - radius * 0.5) + rng.randf() * 8.0
			BuildingPlot.Kind.FARM:
				key = -dist + rng.randf() * 10.0
			_:
				key = rng.randf()
		keyed.append([key, i])
	keyed.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: Array[int] = []
	for k in keyed:
		out.append(k[1])
	return out


func _fits(rect: Rect2) -> bool:
	# inside the town
	if wall_half > 0.0:
		var inner := wall_half - 2.5
		if rect.position.x < -inner or rect.position.y < -inner or rect.end.x > inner or rect.end.y > inner:
			return false
	else:
		var lim := radius * 1.02
		for c in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			if (c as Vector2).length() > lim:
				return false
	# not on the plaza
	var closest := Vector2(clampf(0.0, rect.position.x, rect.end.x), clampf(0.0, rect.position.y, rect.end.y))
	if closest.length() < plaza_radius:
		return false
	# not on a street
	for s in streets:
		if s.get_rect().grow(0.5).intersects(rect):
			return false
	# not touching another building
	var grown := rect.grow(GAP)
	for other in _rects:
		if grown.intersects(other):
			return false
	return true


func _make_plot(w: Dictionary, rng: RandomNumberGenerator, used_names: Dictionary) -> BuildingPlot:
	var p := BuildingPlot.new()
	p.kind = w["kind"]
	p.guild = String(w.get("guild", ""))
	p.trade = String(w.get("trade", ""))
	var owner := NameGen.person(rng)
	for i in 8:
		if not used_names.has(owner):
			break
		owner = NameGen.person(rng)
	used_names[owner] = true
	p.owner_name = owner
	var first := NameGen.first_name(owner)
	var last := NameGen.last_name(owner)
	var city := data.kind == TownData.Kind.CITY
	match p.kind:
		BuildingPlot.Kind.HOUSE:
			p.size = Vector3(rng.randf_range(6.0, 8.0), 6.0 if city else rng.randf_range(3.2, 3.6), rng.randf_range(5.5, 7.0))
			p.display_name = "%s's House" % first
		BuildingPlot.Kind.FARM:
			p.size = Vector3(rng.randf_range(7.0, 8.5), 3.4, rng.randf_range(6.0, 7.0))
			p.field_size = Vector2(rng.randf_range(16.0, 22.0), rng.randf_range(12.0, 16.0))
			p.display_name = "%s Farm" % last
		BuildingPlot.Kind.SHOP:
			p.size = Vector3(8.0, 6.0 if city else 3.8, 7.0)
			p.display_name = "%s's %s" % [first, NameGen.TRADES.get(p.trade, "Goods")]
		BuildingPlot.Kind.INN:
			p.size = Vector3(12.0, 6.2, 10.0)
			p.display_name = NameGen.inn(rng)
		BuildingPlot.Kind.SMITHY:
			p.size = Vector3(8.0, 3.8, 7.0)
			p.display_name = "%s Smithy" % last
		BuildingPlot.Kind.TEMPLE:
			p.size = Vector3(11.0, 7.5, 15.0)
			p.display_name = NameGen.temple(rng)
		BuildingPlot.Kind.GUILD_HALL:
			p.size = Vector3(14.0, 6.5, 11.0)
			p.display_name = NameGen.GUILD_HALLS.get(p.guild, "Guild Hall")
	if p.is_public():
		p.lock_level = clampi(data.house_lock_max + 10, 1, 99)
		p.starts_locked = false
	else:
		p.lock_level = rng.randi_range(mini(data.house_lock_min, data.house_lock_max), maxi(data.house_lock_min, data.house_lock_max))
		p.starts_locked = rng.randf() < data.house_locked_chance
	return p
