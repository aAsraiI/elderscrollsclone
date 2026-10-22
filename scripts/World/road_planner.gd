class_name RoadPlanner
extends RefCounted
## Joins the towns with roads. Pure data in, RoadNetwork out, the same for the same seed.
##
## Which towns get a road: the shortest set of roads that connects every town (a minimum spanning
## tree), plus every city to its two nearest neighbors so the network has a few loops.
## Where a road goes: A* over a grid laid across the whole map. Steep cells cost a lot more than
## flat ones, so roads wind around hills; the cliff ring and other towns are off limits; cells
## an earlier road already uses are cheap, so roads join up instead of running side by side.
## The path is then smoothed into curves, and its height is smoothed so the road never jumps.
## Town streets are added to the same network so they are leveled and colored the same way.

const ROAD_COLOR := Color(0.43, 0.36, 0.25)
## Meters a road runs straight out of a gate before it starts finding its own way
const LEAD := 14.0
## Meters between the points of a finished road
const SPACING := 6.0


static func plan(map: WorldMap, towns: Array[PlacedPOI]) -> RoadNetwork:
	var net := RoadNetwork.new()
	for t in towns:
		add_streets(net, t)
	var settings := map.settings
	if not settings.roads_enabled or towns.size() < 2:
		return net

	var cell := settings.road_grid
	var b := map.get_bounds()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(floori(b.position.x / cell), floori(b.position.y / cell), ceili(b.size.x / cell) + 1, ceili(b.size.y / cell) + 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	# Height of every cell, and whether it is inside the world at all
	var region := astar.region
	var w := region.size.x
	var h := region.size.y
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	var outside := PackedByteArray()
	outside.resize(w * h)
	var s := WorldMap.Sample.new()
	for j in h:
		for i in w:
			map.sample((float(region.position.x + i) + 0.5) * cell, (float(region.position.y + j) + 0.5) * cell, s)
			heights[j * w + i] = s.height
			outside[j * w + i] = 1 if s.edge > 0.02 else 0
	# Steep = expensive
	var base := PackedFloat32Array()
	base.resize(w * h)
	for j in h:
		for i in w:
			var k := j * w + i
			var c := Vector2i(region.position.x + i, region.position.y + j)
			if outside[k] == 1:
				astar.set_point_solid(c, true)
				base[k] = 1.0
				continue
			var grad := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				if ni >= 0 and nj >= 0 and ni < w and nj < h:
					grad = maxf(grad, absf(heights[nj * w + ni] - heights[k]) / cell)
			base[k] = 1.0 + 8.0 * grad + 120.0 * grad * grad
			astar.set_point_weight_scale(c, base[k])

	# The cells under each town
	var town_cells := {}  # town id -> Array[Vector2i]
	for t in towns:
		var list: Array[Vector2i] = []
		var r := t.poi.footprint_radius + cell
		for cz in range(floori((t.position.z - r) / cell), floori((t.position.z + r) / cell) + 1):
			for cx in range(floori((t.position.x - r) / cell), floori((t.position.x + r) / cell) + 1):
				var c := Vector2i(cx, cz)
				if not region.has_point(c):
					continue
				var center := Vector2((cx + 0.5) * cell, (cz + 0.5) * cell)
				if center.distance_to(Vector2(t.position.x, t.position.z)) <= r:
					list.append(c)
		town_cells[t.id] = list

	for e in _pick_links(towns):
		var a: PlacedPOI = towns[e.x]
		var bt: PlacedPOI = towns[e.y]
		var route := _route(map, net, astar, region, base, town_cells, towns, a, bt, cell)
		if route.is_empty() or (route["points"] as PackedVector3Array).size() < 2:
			push_warning("Roads: no way found from %s to %s" % [a.town.display_name, bt.town.display_name])
			continue
		# where it runs on top of an earlier road, that road's surface is used instead of a second one
		net.add_polyline(route["points"], settings.road_width * 0.5, ROAD_COLOR, false, a.id, bt.id, route["shared"])
	return net


## The streets of a town, leveled at the town's height
static func add_streets(net: RoadNetwork, t: PlacedPOI) -> void:
	if t.town == null:
		return
	var layout := t.town
	for st in layout.streets:
		var a := layout.to_world(st.a)
		var b := layout.to_world(st.b)
		a.y = layout.origin.y
		b.y = layout.origin.y
		net.add_polyline(PackedVector3Array([a, b]), st.half_width, layout.data.street_color, true, t.id, t.id)


# ---------------------------------------------------------------- which towns are joined

# Pairs of indices into towns, shortest first
static func _pick_links(towns: Array[PlacedPOI]) -> Array[Vector2i]:
	var n := towns.size()
	var links := {}
	# Prim's minimum spanning tree
	var in_tree := {0: true}
	while in_tree.size() < n:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for i in in_tree:
			for j in n:
				if in_tree.has(j):
					continue
				var d := towns[i].position.distance_squared_to(towns[j].position)
				if d < best_d:
					best_d = d
					best = Vector2i(i, j)
		in_tree[best.y] = true
		links[_link_key(best.x, best.y)] = Vector2i(mini(best.x, best.y), maxi(best.x, best.y))
	# Cities also go to their two nearest towns
	for i in n:
		if (towns[i].poi as TownData).kind != TownData.Kind.CITY:
			continue
		var order: Array = range(n)
		order.erase(i)
		order.sort_custom(func(x: int, y: int) -> bool:
			return towns[i].position.distance_squared_to(towns[x].position) < towns[i].position.distance_squared_to(towns[y].position))
		for k in mini(2, order.size()):
			var j: int = order[k]
			links[_link_key(i, j)] = Vector2i(mini(i, j), maxi(i, j))
	var out: Array[Vector2i] = []
	for v in links.values():
		out.append(v)
	out.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return towns[x.x].position.distance_squared_to(towns[x.y].position) < towns[y.x].position.distance_squared_to(towns[y.y].position))
	return out


static func _link_key(i: int, j: int) -> String:
	return "%d-%d" % [mini(i, j), maxi(i, j)]


# ---------------------------------------------------------------- one road

# Returns {"points": PackedVector3Array, "shared": PackedByteArray} or {} if there is no way
static func _route(map: WorldMap, net: RoadNetwork, astar: AStarGrid2D, region: Rect2i, base: PackedFloat32Array, town_cells: Dictionary, towns: Array[PlacedPOI], a: PlacedPOI, b: PlacedPOI, cell: float) -> Dictionary:
	var ga := _nearest_gate(a.town, b.position)
	var gb := _nearest_gate(b.town, a.position)
	var gate_a := a.town.get_gates_world()[ga]
	var gate_b := b.town.get_gates_world()[gb]
	var lead_a := gate_a + a.town.get_gate_outward(ga) * LEAD
	var lead_b := gate_b + b.town.get_gate_outward(gb) * LEAD

	# Other towns are walls for this road; its own two towns are just expensive to cross
	var changed: Array[Vector2i] = []
	for t in towns:
		for c: Vector2i in town_cells[t.id]:
			if astar.is_point_solid(c):
				continue
			if t == a or t == b:
				astar.set_point_weight_scale(c, astar.get_point_weight_scale(c) * 6.0)
			else:
				astar.set_point_solid(c, true)
			changed.append(c)
	var from := Vector2i(floori(lead_a.x / cell), floori(lead_a.z / cell))
	var to := Vector2i(floori(lead_b.x / cell), floori(lead_b.z / cell))
	var ids: Array[Vector2i] = []
	if region.has_point(from) and region.has_point(to) and not astar.is_point_solid(from) and not astar.is_point_solid(to):
		ids = astar.get_id_path(from, to)
	for c in changed:
		astar.set_point_solid(c, false)
		astar.set_point_weight_scale(c, base[(c.y - region.position.y) * region.size.x + (c.x - region.position.x)])
	if ids.is_empty():
		return {}

	# Later roads keep a little away from this one: two roads side by side on a slope would each
	# want the ground at a different height. (Where they must meet, at a gate or a crossing, the
	# later one takes over the earlier one's surface, see `shared` below.)
	var marked := {}
	for c in ids:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := Vector2i(c.x + dx, c.y + dz)
				if marked.has(n) or not region.has_point(n):
					continue
				marked[n] = true
				var k := (n.y - region.position.y) * region.size.x + (n.x - region.position.x)
				base[k] = base[k] * 2.5
				if not astar.is_point_solid(n):
					astar.set_point_weight_scale(n, base[k])

	# Grid cells -> corners only -> smooth curve
	var mid: Array[Vector2] = []
	for c in ids:
		mid.append(Vector2((c.x + 0.5) * cell, (c.y + 0.5) * cell))
	mid = _drop_straight(mid)
	var flat: Array[Vector2] = [Vector2(gate_a.x, gate_a.z), Vector2(lead_a.x, lead_a.z)]
	flat.append_array(mid)
	flat.append(Vector2(lead_b.x, lead_b.z))
	flat.append(Vector2(gate_b.x, gate_b.z))
	for i in 3:
		flat = _chaikin(flat)
	flat = _resample(flat, SPACING)

	# Heights from the land. Inside a town's leveled ground the road stays at street height; the
	# rest is smoothed, then held to the steepest grade a road may have (cutting into hills and
	# building up dips where the land is steeper)
	var hs := PackedFloat32Array()
	hs.resize(flat.size())
	var pinned := PackedByteArray()
	pinned.resize(flat.size())
	var shared := PackedByteArray()  # 1 = this point is on an earlier road and uses its surface
	shared.resize(flat.size())
	for i in flat.size():
		var p := flat[i]
		hs[i] = map.get_height(p.x, p.y)
		for t in [a, b]:
			if p.distance_to(Vector2(t.position.x, t.position.z)) < t.poi.flatten_radius * 0.98:
				hs[i] = t.position.y
				pinned[i] = 1
		if pinned[i] == 0:
			var on_road := net.height_at(p.x, p.y)
			if not is_nan(on_road):
				hs[i] = on_road
				pinned[i] = 1
				shared[i] = 1
	pinned[0] = 1
	pinned[flat.size() - 1] = 1
	hs[0] = gate_a.y
	hs[hs.size() - 1] = gate_b.y
	# A shared point the grade can't reach from the last fixed point (the earlier road climbed a
	# long way round) is not shared after all
	var grade := map.settings.road_max_grade
	var last := 0
	var walked := 0.0
	for i in range(1, flat.size()):
		walked += flat[i].distance_to(flat[i - 1])
		if pinned[i] == 0:
			continue
		if shared[i] == 1 and absf(hs[i] - hs[last]) > grade * walked + 0.05:
			shared[i] = 0
			pinned[i] = 0
			hs[i] = map.get_height(flat[i].x, flat[i].y)
			continue
		last = i
		walked = 0.0
	last = flat.size() - 1  # and the same looking back from the other end
	walked = 0.0
	for i in range(flat.size() - 2, -1, -1):
		walked += flat[i].distance_to(flat[i + 1])
		if pinned[i] == 0:
			continue
		if shared[i] == 1 and absf(hs[i] - hs[last]) > grade * walked + 0.05:
			shared[i] = 0
			pinned[i] = 0
			hs[i] = map.get_height(flat[i].x, flat[i].y)
			continue
		last = i
		walked = 0.0
	for pass_i in 4:
		var next := hs.duplicate()
		for i in hs.size():
			if pinned[i] == 1:
				continue
			var sum := 0.0
			var cnt := 0
			for k in range(maxi(i - 2, 0), mini(i + 3, hs.size())):
				sum += hs[k]
				cnt += 1
			next[i] = sum / float(cnt)
		hs = next
	for pass_i in 4:
		for i in range(1, hs.size()):
			if pinned[i] == 0:
				var lim := grade * flat[i].distance_to(flat[i - 1])
				hs[i] = clampf(hs[i], hs[i - 1] - lim, hs[i - 1] + lim)
		for i in range(hs.size() - 2, -1, -1):
			if pinned[i] == 0:
				var lim := grade * flat[i].distance_to(flat[i + 1])
				hs[i] = clampf(hs[i], hs[i + 1] - lim, hs[i + 1] + lim)
	var out := PackedVector3Array()
	for i in flat.size():
		out.append(Vector3(flat[i].x, hs[i], flat[i].y))
	return {"points": out, "shared": shared}


static func _nearest_gate(layout: TownLayout, target: Vector3) -> int:
	var gates := layout.get_gates_world()
	var best := 0
	for i in gates.size():
		if gates[i].distance_squared_to(target) < gates[best].distance_squared_to(target):
			best = i
	return best


static func _drop_straight(pts: Array[Vector2]) -> Array[Vector2]:
	if pts.size() < 3:
		return pts
	var out: Array[Vector2] = [pts[0]]
	for i in range(1, pts.size() - 1):
		var d1 := (pts[i] - pts[i - 1]).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		if d1.dot(d2) < 0.999:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


# Cuts every corner, keeping both ends where they are
static func _chaikin(pts: Array[Vector2]) -> Array[Vector2]:
	if pts.size() < 3:
		return pts
	var out: Array[Vector2] = [pts[0]]
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		if i > 0:
			out.append(p.lerp(q, 0.25))
		if i < pts.size() - 2:
			out.append(p.lerp(q, 0.75))
	out.append(pts[pts.size() - 1])
	return out


static func _resample(pts: Array[Vector2], spacing: float) -> Array[Vector2]:
	var out: Array[Vector2] = [pts[0]]
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := spacing - carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += spacing
		carry = seg - (t - spacing)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.5:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out
