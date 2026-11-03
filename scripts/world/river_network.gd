class_name RiverNetwork
extends RefCounted
## Every stream, river and lake, made by RiverPlanner. WorldMap asks it, for every spot of ground,
## whether water runs there: a river's channel is carved into the ground (a rounded bed under the
## water, banks sloping up to meet the land, a low bank raised where the land beside it is lower
## than the water) and the water surface's height is handed back so the chunk can draw it.
## Pure data, read-only once planned, so worker threads may use it.

## Meters of grid used to find the pieces near a spot quickly
const CELL := 64.0
## How steeply a bank climbs out of the water (rise per meter)
const BANK_SLOPE := 0.55
## Meters of bank beside a channel that the carving and the water reach
const BANK := 46.0
## The water surface reaches this far past the channel edge (it hides under the banks)
const WATER_REACH := 4.0
## Meters of the low bank raised beside a channel where the land is lower than the water
const LEVEE := 10.0
## How deep the ground under a lake may be at its middle before the shore lifts it (m)
const LAKE_SHELF := 7.0

## Whole rivers, for the map and the planners: {"points": PackedVector3Array (x, water level, z),
## "widths": PackedFloat32Array (half width per point), "river": bool (false = a stream),
## "end": "sea" / "lake" / "join" / "dry"}
var polylines: Array[Dictionary] = []

var _ax := PackedFloat64Array()
var _az := PackedFloat64Array()
var _bx := PackedFloat64Array()
var _bz := PackedFloat64Array()
var _al := PackedFloat64Array()  # water level at each end
var _bl := PackedFloat64Array()
var _ahw := PackedFloat64Array()  # half width at each end
var _bhw := PackedFloat64Array()
var _grid := {}  # Vector2i -> PackedInt32Array of segment indices

# Lakes: a coarse grid of water levels (-INF = no lake)
var _lake_grids: Array[Dictionary] = []  # one per island: {"min", "cell", "w", "h", "levels", "rect"}
var _lake_count := 0
## Lakes for the map and the planners: {"center": Vector2, "level": float, "cells": int}
var lakes: Array[Dictionary] = []


func river_count() -> int:
	return polylines.size()


func lake_count() -> int:
	return _lake_count


func total_length() -> float:
	var total := 0.0
	for p in polylines:
		var pts: PackedVector3Array = p["points"]
		for i in pts.size() - 1:
			total += Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[i + 1].x, pts[i + 1].z))
	return total


## Adds a river along these points (x, water level, z) with a half width at each point
func add_polyline(points: PackedVector3Array, widths: PackedFloat32Array, is_river: bool, end: String) -> void:
	if points.size() < 2:
		return
	polylines.append({"points": points, "widths": widths, "river": is_river, "end": end})
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var idx := _ax.size()
		_ax.append(a.x)
		_az.append(a.z)
		_al.append(a.y)
		_bx.append(b.x)
		_bz.append(b.z)
		_bl.append(b.y)
		_ahw.append(widths[i])
		_bhw.append(widths[i + 1])
		var reach := maxf(widths[i], widths[i + 1]) + BANK
		var c0 := Vector2i(floori((minf(a.x, b.x) - reach) / CELL), floori((minf(a.z, b.z) - reach) / CELL))
		var c1 := Vector2i(floori((maxf(a.x, b.x) + reach) / CELL), floori((maxf(a.z, b.z) + reach) / CELL))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
				arr.append(idx)
				_grid[key] = arr


## The lakes as a grid of water levels (-INF where there is none), cell meters each
func add_lakes(origin: Vector2, cell: float, w: int, h: int, levels: PackedFloat32Array, list: Array[Dictionary]) -> void:
	_lake_grids.append({"min": origin, "cell": cell, "w": w, "h": h, "levels": levels,
		"rect": Rect2(origin, Vector2(w, h) * cell)})
	lakes.append_array(list)
	_lake_count += list.size()


# (the lake's water level here or -INF, how much this is lake: 1 in the middle, 0 a cell away from
# it, blended smoothly between the lake grid's cell centers so the shore is never square)
func _lake_at(x: float, z: float) -> Vector2:
	for g: Dictionary in _lake_grids:
		if not (g["rect"] as Rect2).has_point(Vector2(x, z)):
			continue
		var cell: float = g["cell"]
		var lmin: Vector2 = g["min"]
		var w: int = g["w"]
		var h: int = g["h"]
		var levels: PackedFloat32Array = g["levels"]
		var fx := (x - lmin.x) / cell - 0.5
		var fz := (z - lmin.y) / cell - 0.5
		var i0 := floori(fx)
		var j0 := floori(fz)
		var tx := fx - float(i0)
		var tz := fz - float(j0)
		var level := -INF
		var m := 0.0
		for k in 4:
			var i := i0 + (k & 1)
			var j := j0 + (k >> 1)
			if i < 0 or j < 0 or i >= w or j >= h:
				continue
			var lv := levels[j * w + i]
			if lv > -INF:
				level = maxf(level, lv)
				m += (tx if k & 1 else 1.0 - tx) * (tz if k >> 1 else 1.0 - tz)
		return Vector2(level, m)
	return Vector2(-INF, 0.0)


## Height of the water surface here (river or lake), or -INF
func water_level(x: float, z: float) -> float:
	var level := _lake_at(x, z).x
	var list: PackedInt32Array = _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array())
	for i in list:
		var r := _nearest(i, x, z)
		if r.x < r.z + WATER_REACH:
			level = maxf(level, r.y)
	return level


## Meters from (x, z) to the edge of the nearest channel (negative inside it), or INF if none is
## within max_dist
func distance_to(x: float, z: float, max_dist: float) -> float:
	var best := INF
	var c0 := Vector2i(floori((x - max_dist) / CELL), floori((z - max_dist) / CELL))
	var c1 := Vector2i(floori((x + max_dist) / CELL), floori((z + max_dist) / CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for i in _grid.get(Vector2i(cx, cz), PackedInt32Array()):
				var r := _nearest(i, x, z)
				best = minf(best, r.x - r.z)
	return best if best <= max_dist else INF


## Is this inside a lake (by the coarse lake grid)?
func in_lake(x: float, z: float) -> bool:
	return _lake_at(x, z).y > 0.5


# (distance to segment i's middle line, water level there, half width there)
func _nearest(i: int, x: float, z: float) -> Vector3:
	var abx := _bx[i] - _ax[i]
	var abz := _bz[i] - _az[i]
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(((x - _ax[i]) * abx + (z - _az[i]) * abz) / len2, 0.0, 1.0)
	var px := _ax[i] + abx * t - x
	var pz := _az[i] + abz * t - z
	return Vector3(sqrt(px * px + pz * pz), lerpf(_al[i], _bl[i], t), lerpf(_ahw[i], _bhw[i], t))


## Carves the channels and hands back the water surface (WorldMap.sample calls this last)
func apply(x: float, z: float, out: WorldMap.Sample) -> void:
	var lake := _lake_at(x, z)
	if lake.x > -INF:
		# the shore rises to just above the water where the lake ends (no water past its edge)
		out.water = maxf(out.water, lake.x)
		var shore := lake.x + 0.45 - LAKE_SHELF * lake.y
		var gap := maxf(1.0 - absf(out.height - shore), 0.0)
		out.height = maxf(out.height, shore) + gap * gap * 0.25  # a soft maximum: no crease at the foot
	var list: PackedInt32Array = _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array())
	if list.is_empty():
		return
	var h := out.height
	var target := INF      # the lowest the channels and banks want the ground here
	var raise := -INF      # a low bank wanted where the land is under the water
	var raise_w := 0.0
	var level := -INF
	var wet := 0.0
	for i in list:
		var r := _nearest(i, x, z)
		var d := r.x
		var hw := r.z
		if d >= hw + BANK:
			continue
		var lv := r.y
		out.near_water = maxf(out.near_water, 1.0 - smoothstep(hw, hw + 22.0, d))
		var depth := 0.45 + hw * 0.16
		var want: float
		if d < hw:
			var f := d / hw
			want = lv - depth * (1.0 - f * f)
		else:
			want = lv + 0.25 + (d - hw) * BANK_SLOPE
			# toward the edge of its reach the bank gives way to the land, so a deep gorge never ends
			# in a step where the carving stops
			want = lerpf(want, maxf(want, h), smoothstep(hw + BANK * 0.55, hw + BANK, d))
		target = minf(target, want)
		if d < hw + WATER_REACH:
			level = maxf(level, lv)
			wet = maxf(wet, 1.0 - smoothstep(hw, hw + WATER_REACH, d))
		if d >= hw and h < lv + 0.3:
			var w := 1.0 - smoothstep(hw, hw + LEVEE, d)
			if w > raise_w:
				raise_w = w
				raise = lv + 0.3
	if raise_w > 0.0:
		h = lerpf(h, maxf(h, raise), raise_w)
	if target < h:
		# a soft minimum, so the bank's foot rounds into the land instead of making a crease
		var k := 1.2
		var gap := maxf(k - absf(h - target), 0.0) / k
		h = minf(h, target) - gap * gap * k * 0.25
	out.height = h
	if level > -INF:
		out.water = maxf(out.water, level)
		out.river = wet
