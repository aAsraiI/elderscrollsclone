class_name RoadNetwork
extends RefCounted
## Every road and town street, as straight pieces with a height at both ends. WorldMap asks it,
## for every spot of ground, whether a road is there: the ground under a road is leveled to the
## road's smooth height (blending back into the land beside it) and gets the road's color.
## Pure data, read-only once the world is planned, so worker threads may use it.

## Meters of grid used to find the pieces near a spot quickly
const CELL := 64.0
## Meters beside a road over which the ground blends back to the natural terrain
const SHOULDER := 6.0
## Meters over which the road color fades out at its edge
const EDGE_SOFT := 1.4

## Whole roads, for the map: {"points": PackedVector3Array, "half_width": float, "color": Color,
## "street": bool, "from": String, "to": String}
var polylines: Array[Dictionary] = []

var _ax := PackedFloat64Array()
var _az := PackedFloat64Array()
var _ah := PackedFloat64Array()
var _bx := PackedFloat64Array()
var _bz := PackedFloat64Array()
var _bh := PackedFloat64Array()
var _hw := PackedFloat64Array()
var _col := PackedColorArray()
var _grid := {}  # Vector2i -> PackedInt32Array of segment indices


func is_empty() -> bool:
	return _ax.is_empty()


func segment_count() -> int:
	return _ax.size()


func get_roads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in polylines:
		if not p["street"]:
			out.append(p)
	return out


## Adds a road along these points (x, height, z). half_width = half the road's width in meters.
## skip: optional, 1 per point; a piece between two skipped points is left out (another road
## already covers it), but the road is still listed whole in polylines.
func add_polyline(points: PackedVector3Array, half_width: float, color: Color, street: bool = false, from_id: String = "", to_id: String = "", skip: PackedByteArray = PackedByteArray()) -> void:
	if points.size() < 2:
		return
	polylines.append({"points": points, "half_width": half_width, "color": color, "street": street, "from": from_id, "to": to_id})
	for i in points.size() - 1:
		if skip.size() == points.size() and skip[i] == 1 and skip[i + 1] == 1:
			continue
		_add_segment(points[i], points[i + 1], half_width, color)


## Meters from (x, z) to the edge of the nearest road, or INF if none is within max_dist
func distance_to(x: float, z: float, max_dist: float) -> float:
	var best := INF
	var c0 := Vector2i(floori((x - max_dist) / CELL), floori((z - max_dist) / CELL))
	var c1 := Vector2i(floori((x + max_dist) / CELL), floori((z + max_dist) / CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var list: PackedInt32Array = _grid.get(Vector2i(cx, cz), PackedInt32Array())
			for i in list:
				var d := _segment_distance(i, x, z) - _hw[i]
				best = minf(best, d)
	return best if best <= max_dist else INF


## Height of the road surface at (x, z), or NAN when no road is there
func height_at(x: float, z: float) -> float:
	var list: PackedInt32Array = _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array())
	var best_d := INF
	var h := NAN
	for i in list:
		var d := _segment_distance(i, x, z)
		if d <= _hw[i] and d < best_d:
			best_d = d
			var abx := _bx[i] - _ax[i]
			var abz := _bz[i] - _az[i]
			var len2 := abx * abx + abz * abz
			var t := clampf(((x - _ax[i]) * abx + (z - _az[i]) * abz) / len2, 0.0, 1.0) if len2 > 0.0001 else 0.0
			h = lerpf(_ah[i], _bh[i], t)
	return h


## Changes a WorldMap sample where a road is: level ground and the road's color
func apply(x: float, z: float, out: WorldMap.Sample) -> void:
	var list: PackedInt32Array = _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array())
	if list.is_empty():
		return
	var best_w := 0.0
	var best_d := INF
	var best_h := 0.0
	var best_cw := 0.0
	var best_col := Color.WHITE
	for i in list:
		var abx := _bx[i] - _ax[i]
		var abz := _bz[i] - _az[i]
		var len2 := abx * abx + abz * abz
		var t := 0.0
		if len2 > 0.0001:
			t = clampf(((x - _ax[i]) * abx + (z - _az[i]) * abz) / len2, 0.0, 1.0)
		var px := _ax[i] + abx * t - x
		var pz := _az[i] + abz * t - z
		var d := sqrt(px * px + pz * pz)
		var hw: float = _hw[i]
		if d >= hw + SHOULDER:
			continue
		var w := 1.0 - smoothstep(hw, hw + SHOULDER, d)
		if w > best_w or (w == best_w and d < best_d):  # where roads meet, the nearest one decides
			best_w = w
			best_d = d
			best_h = lerpf(_ah[i], _bh[i], t)
		var cw := 1.0 - smoothstep(hw - EDGE_SOFT, hw + EDGE_SOFT, d)
		if cw > best_cw:
			best_cw = cw
			best_col = _col[i]
	if best_w > 0.0:
		out.height = lerpf(out.height, best_h, best_w)
	if best_cw > 0.0:
		out.color = out.color.lerp(best_col, best_cw)
		out.steep_color = out.steep_color.lerp(best_col, best_cw)
		out.map_color = out.map_color.lerp(best_col.darkened(0.2), best_cw)


# ---------------------------------------------------------------- internals

func _add_segment(a: Vector3, b: Vector3, half_width: float, color: Color) -> void:
	var idx := _ax.size()
	_ax.append(a.x)
	_az.append(a.z)
	_ah.append(a.y)
	_bx.append(b.x)
	_bz.append(b.z)
	_bh.append(b.y)
	_hw.append(half_width)
	_col.append(color)
	var reach := half_width + SHOULDER
	var c0 := Vector2i(floori((minf(a.x, b.x) - reach) / CELL), floori((minf(a.z, b.z) - reach) / CELL))
	var c1 := Vector2i(floori((maxf(a.x, b.x) + reach) / CELL), floori((maxf(a.z, b.z) + reach) / CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cz)
			var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
			arr.append(idx)
			_grid[key] = arr


func _segment_distance(i: int, x: float, z: float) -> float:
	var abx := _bx[i] - _ax[i]
	var abz := _bz[i] - _az[i]
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(((x - _ax[i]) * abx + (z - _az[i]) * abz) / len2, 0.0, 1.0)
	var px := _ax[i] + abx * t - x
	var pz := _az[i] + abz * t - z
	return sqrt(px * px + pz * pz)
