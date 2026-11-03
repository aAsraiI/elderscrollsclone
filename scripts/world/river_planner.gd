class_name RiverPlanner
extends RefCounted
## Works out where water runs, the way the land itself would send it (the method of terrain tools
## and of games that grow their rivers from the ground: priority flood, flow directions, flow
## accumulation):
##  1. The land's height on a coarse grid (WorldSettings.river_grid meters per cell).
##  2. Priority flood from the sea inward: every cell gets the cell it drains into, and every hollow
##     is filled up to the level where it spills over. Hollows deep enough stay as lakes.
##  3. Rain falls on every cell (less in dry lands, more in wet ones) and runs downhill; where enough
##     has gathered a stream starts, and where much more has, it is a river.
##  4. Each stream is followed down to the sea, a lake or the stream it joins, smoothed into curves
##     with a gentle meander, and its water level walked downhill so it never runs uphill.
## Pure data in, RiverNetwork out, the same for the same seed.

## Rain by climate (how many streams a land feeds)
const RAIN := {"temperate": 1.0, "wet": 1.35, "cold": 0.8, "arid": 0.22}
## Meters between the points of a finished river
const SPACING := 8.0
## Meters the water sits below the land at the head of a stream
const DROP := 0.7


static func plan(map: WorldMap) -> RiverNetwork:
	var net := RiverNetwork.new()
	var settings := map.settings
	if not settings.rivers_enabled or not settings.is_regions() or map.placements.is_empty():
		return net
	var cell := settings.river_grid
	var b := map.get_bounds()
	var origin := b.position
	var w := ceili(b.size.x / cell)
	var h := ceili(b.size.y / cell)
	var n := w * h
	var sea := settings.sea_level

	# 1. heights and rain, a row per worker
	var rows: Array = []
	rows.resize(h)
	var task := WorkerThreadPool.add_group_task(func(j: int) -> void:
		var s := WorldMap.Sample.new()
		var rh := PackedFloat32Array()
		var rr := PackedFloat32Array()
		rh.resize(w)
		rr.resize(w)
		for i in w:
			map.sample(origin.x + (float(i) + 0.5) * cell, origin.y + (float(j) + 0.5) * cell, s)
			rh[i] = s.height
			var rain := 0.0
			if s.biome_index >= 0 and s.edge < 0.05:
				rain = float(RAIN.get(map.placements[s.biome_index].biome.get_climate(), 1.0))
			rr[i] = rain
		rows[j] = [rh, rr], h, -1, true, "river heights")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var height := PackedFloat32Array()
	var rain := PackedFloat32Array()
	height.resize(n)
	rain.resize(n)
	for j in h:
		var rh: PackedFloat32Array = rows[j][0]
		var rr: PackedFloat32Array = rows[j][1]
		for i in w:
			height[j * w + i] = rh[i]
			rain[j * w + i] = rr[i]

	# 2. priority flood (bucketed by height: 5 cm buckets, each a linked list)
	const BUCKET := 0.05
	var lo := INF
	var hi := -INF
	for v in height:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var nb := int((hi - lo) / BUCKET) + 64
	var head := PackedInt32Array()
	var tail := PackedInt32Array()
	head.resize(nb)
	tail.resize(nb)
	head.fill(-1)
	tail.fill(-1)
	var nxt := PackedInt32Array()
	nxt.resize(n)
	nxt.fill(-1)
	var filled := height.duplicate()
	var rcv := PackedInt32Array()
	rcv.resize(n)
	rcv.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	var order := PackedInt32Array()
	order.resize(n)
	var count := 0
	# the sea and the edge of the grid are where water leaves
	for k in n:
		var i := k % w
		var j := k / w
		if height[k] < sea - 0.2 or i == 0 or j == 0 or i == w - 1 or j == h - 1:
			done[k] = 1
			var bi := clampi(int((filled[k] - lo) / BUCKET), 0, nb - 1)
			if tail[bi] < 0:
				head[bi] = k
			else:
				nxt[tail[bi]] = k
			tail[bi] = k
	var cur := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	while cur < nb:
		var c := head[cur]
		if c < 0:
			cur += 1
			continue
		head[cur] = nxt[c]
		if head[cur] < 0:
			tail[cur] = -1
		order[count] = c
		count += 1
		var ci := c % w
		var cj := c / w
		for d: Vector2i in dirs:
			var ni := ci + d.x
			var nj := cj + d.y
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var k := nj * w + ni
			if done[k] == 1:
				continue
			done[k] = 1
			rcv[k] = c
			filled[k] = maxf(height[k], filled[c] + 0.002)
			var bi := clampi(int((filled[k] - lo) / BUCKET), cur, nb - 1)
			if tail[bi] < 0:
				head[bi] = k
			else:
				nxt[tail[bi]] = k
			tail[bi] = k

	# lakes: hollows filled deeper than lake_min_depth, big enough, above the sea
	var lake_of := PackedInt32Array()
	lake_of.resize(n)
	lake_of.fill(-1)
	var lake_levels := PackedFloat32Array()
	lake_levels.resize(n)
	lake_levels.fill(-INF)
	var lake_list: Array[Dictionary] = []
	var seen := PackedByteArray()
	seen.resize(n)
	var candidates: Array[Dictionary] = []
	for k in n:
		if seen[k] == 1 or filled[k] - height[k] < 0.3 or height[k] < sea:
			continue
		# gather the hollow (connected cells sitting under the filled level)
		var group := PackedInt32Array([k])
		seen[k] = 1
		var gi := 0
		var deepest := 0.0
		var level := -INF
		while gi < group.size():
			var c := group[gi]
			gi += 1
			deepest = maxf(deepest, filled[c] - height[c])
			level = maxf(level, filled[c])
			var ci := c % w
			var cj := c / w
			for d: Vector2i in dirs:
				var ni := ci + d.x
				var nj := cj + d.y
				if ni < 0 or nj < 0 or ni >= w or nj >= h:
					continue
				var q := nj * w + ni
				if seen[q] == 0 and filled[q] - height[q] >= 0.3:
					seen[q] = 1
					group.append(q)
		if deepest < settings.lake_min_depth or group.size() < settings.lake_min_cells or group.size() > settings.lake_max_cells or level < sea + 0.5:
			continue
		candidates.append({"group": group, "level": level})
	# the biggest hollows become lakes
	candidates.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return (a["group"] as PackedInt32Array).size() > (b2["group"] as PackedInt32Array).size())
	for cand: Dictionary in candidates.slice(0, settings.max_lakes):
		var group: PackedInt32Array = cand["group"]
		var level: float = cand["level"]
		var id := lake_list.size()
		var center := Vector2.ZERO
		for c in group:
			lake_of[c] = id
			lake_levels[c] = level
			center += Vector2(origin.x + (float(c % w) + 0.5) * cell, origin.y + (float(c / w) + 0.5) * cell)
		lake_list.append({"center": center / float(group.size()), "level": level, "cells": group.size()})
	net.set_lakes(origin, cell, w, h, lake_levels, lake_list)

	# 3. rain gathers downhill (upstream cells come later in the flood order)
	var area := cell * cell / 1.0e6
	var acc := PackedFloat32Array()
	acc.resize(n)
	for k in n:
		acc[k] = rain[k] * area if height[k] >= sea else 0.0
	for o in range(count - 1, -1, -1):
		var c := order[o]
		if rcv[c] >= 0:
			acc[rcv[c]] += acc[c]

	# 4. follow every stream from its head
	var stream_min := settings.stream_catchment
	var is_stream := PackedByteArray()
	is_stream.resize(n)
	var upstream := PackedInt32Array()
	upstream.resize(n)
	for k in n:
		if acc[k] >= stream_min and lake_of[k] < 0 and height[k] >= sea:
			is_stream[k] = 1
	for k in n:
		if is_stream[k] == 1 and rcv[k] >= 0:
			upstream[rcv[k]] += 1
	var heads: Array[int] = []
	for k in n:
		if is_stream[k] == 1 and upstream[k] == 0:
			heads.append(k)
	# the longest-draining heads first, so the main rivers are traced whole and the rest join them
	var reach := PackedFloat32Array()
	reach.resize(n)
	for k in heads:
		var c := k
		var steps := 0
		while c >= 0 and steps < 4000:
			steps += 1
			if rcv[c] < 0 or lake_of[c] >= 0 or height[c] < sea:
				break
			c = rcv[c]
		reach[k] = acc[c] if c >= 0 else 0.0
	heads.sort_custom(func(a: int, b2: int) -> bool: return reach[a] > reach[b2])
	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	var traced: Array[Dictionary] = []  # {"cells", "end", "join" (river index), "join_cell"}
	for k in heads:
		var cells := PackedInt32Array()
		var c := k
		var end := "dry"
		var join := -1
		while c >= 0:
			if owner[c] >= 0:
				end = "join"
				join = owner[c]
				cells.append(c)
				break
			if lake_of[c] >= 0:
				end = "lake"
				cells.append(c)
				break
			if height[c] < sea:
				end = "sea"
				cells.append(c)
				break
			cells.append(c)
			owner[c] = traced.size()
			c = rcv[c]
		if cells.size() < 3 or (cells.size() < 4 and end != "join"):
			for q in cells:
				if owner[q] == traced.size():
					owner[q] = -1  # too short to keep: its cells are free for the next stream
			continue
		traced.append({"cells": cells, "end": end, "join": join})

	# 5. smooth curves, water levels walked downhill, widths from the water gathered
	var meander := FastNoiseLite.new()
	meander.seed = ("%d|meander" % map.world_seed).hash()
	meander.frequency = 1.0 / 170.0
	var made: Array[Dictionary] = []  # per traced river: {"points", "widths"} (or {} when dropped)
	var s := WorldMap.Sample.new()
	for ti in traced.size():
		var t: Dictionary = traced[ti]
		var cells: PackedInt32Array = t["cells"]
		var pts := PackedVector2Array()
		var accs := PackedFloat32Array()
		for c in cells:
			pts.append(Vector2(origin.x + (float(c % w) + 0.5) * cell, origin.y + (float(c / w) + 0.5) * cell))
			accs.append(acc[c])
		# the end of a tributary sits on the river it joins
		if t["end"] == "join" and int(t["join"]) < made.size() and not (made[int(t["join"])] as Dictionary).is_empty():
			pts[pts.size() - 1] = _nearest_point(made[int(t["join"])]["points"], pts[pts.size() - 1])
		var smooth := _chaikin(pts, 3)
		var smooth_acc := _resample_values(accs, smooth.size())
		var line := _resample(smooth, smooth_acc, SPACING)
		var p2: PackedVector2Array = line[0]
		var a2: PackedFloat32Array = line[1]
		# meander: a gentle sideways wander, none at the ends
		var total := p2.size()
		for i in range(1, total - 1):
			var dir := (p2[i + 1] - p2[i - 1]).normalized()
			var side := Vector2(-dir.y, dir.x)
			var fade := minf(float(i), float(total - 1 - i)) / 6.0
			p2[i] += side * meander.get_noise_2d(p2[i].x, p2[i].y) * cell * 0.3 * clampf(fade, 0.0, 1.0)
		# water levels: the land minus a drop, never rising downstream
		var points := PackedVector3Array()
		var widths := PackedFloat32Array()
		var level := INF
		for i in total:
			map.sample(p2[i].x, p2[i].y, s)
			var hw := clampf(0.8 + 1.7 * sqrt(a2[i]), 1.0, 13.0)
			var want := s.height - DROP - hw * 0.06
			level = minf(level - 0.004 * SPACING, want) if level < INF else want
			if level < sea:
				level = sea
			points.append(Vector3(p2[i].x, level, p2[i].y))
			widths.append(hw)
		# the last stretch eases into the water it runs into
		var end_level := -INF
		if t["end"] == "lake":
			end_level = lake_levels[cells[cells.size() - 1]]
		elif t["end"] == "join" and int(t["join"]) < made.size() and not (made[int(t["join"])] as Dictionary).is_empty():
			var other: PackedVector3Array = made[int(t["join"])]["points"]
			end_level = other[_nearest_index(other, p2[total - 1])].y
		elif t["end"] == "sea":
			end_level = sea
		if end_level > -INF:
			var span := mini(10, total - 1)
			var from := points[total - 1 - span].y
			for q in span + 1:
				var k := total - 1 - span + q
				var v := lerpf(from, end_level, float(q) / float(span))
				points[k] = Vector3(points[k].x, minf(points[k].y, v) if t["end"] != "lake" else v, points[k].z)
		made.append({"points": points, "widths": widths})
		net.add_polyline(points, widths, widths[total - 1] >= 3.2, String(t["end"]))
	return net


static func _chaikin(pts: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var cur := pts
	for r in rounds:
		if cur.size() < 3:
			return cur
		var out := PackedVector2Array([cur[0]])
		for i in cur.size() - 1:
			out.append(cur[i].lerp(cur[i + 1], 0.25))
			out.append(cur[i].lerp(cur[i + 1], 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


static func _resample_values(values: PackedFloat32Array, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in count:
		var f := float(i) / float(maxi(count - 1, 1)) * float(values.size() - 1)
		var k := mini(int(f), values.size() - 2)
		out.append(lerpf(values[k], values[k + 1], f - float(k)) if values.size() > 1 else values[0])
	return out


# Points every `step` meters along a line, carrying a value along
static func _resample(pts: PackedVector2Array, values: PackedFloat32Array, step: float) -> Array:
	var out := PackedVector2Array([pts[0]])
	var vals := PackedFloat32Array([values[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			vals.append(lerpf(values[i], values[i + 1], d / seg))
			d += step
		carry = seg - (d - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3:
		out.append(pts[pts.size() - 1])
		vals.append(values[values.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return [out, vals]


static func _nearest_index(points: PackedVector3Array, p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d := Vector2(points[i].x, points[i].z).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


static func _nearest_point(points: PackedVector3Array, p: Vector2) -> Vector2:
	var q := points[_nearest_index(points, p)]
	return Vector2(q.x, q.z)
