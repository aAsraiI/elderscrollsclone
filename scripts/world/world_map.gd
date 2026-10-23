class_name WorldMap
extends RefCounted
## The shape of the world as pure math: give it a position, get back height, color and biome.
## No nodes, no randomness beyond the seed, so the same seed always gives the same world and
## it is safe to call from worker threads (chunks are built that way).
##
## How it works:
##  1. The position is nudged by smooth noise ("domain warping"). This is what makes the straight
##     rectangles of the layout turn into natural, uneven biome borders.
##  2. Every biome rectangle gets a weight from how far inside it the nudged position is. Near a
##     border two biomes both have weight, so height and color blend smoothly.
##  3. Height = the weight-blended height of each biome, using the REAL position (so the terrain
##     itself is never distorted), plus a cliff ring where the world ends.
##
## Coordinates: x = east, z = south (+Z). Height is y.

## Reusable result object. Make one per thread and pass it to sample() again and again.
class Sample:
	var height := 0.0
	var color := Color.WHITE        # ground color before the cliff color is mixed in
	var steep_color := Color.GRAY
	var steep_start := 28.0         # degrees
	var steep_full := 50.0
	var map_color := Color.WHITE    # for the debug map
	var biome_index := -1           # strongest biome here (index into WorldMap.placements)
	var edge := 0.0                 # 0 = inside the world, 1 = on the cliff plateau
	var weights := PackedFloat32Array()
	var sdfs := PackedFloat32Array()
	var _th := 0.0
	var _tc := Color.WHITE


class BiomeNoise:
	var biome: BiomeData
	var hills: FastNoiseLite
	var mountains: FastNoiseLite
	var mountain_mask: FastNoiseLite
	var detail: FastNoiseLite
	var patch: FastNoiseLite


## Meters. How gradually the nearest biome takes over outside the world edge
const OUTSIDE_SOFTNESS := 120.0

var settings: WorldSettings
var world_seed: int
## The valid placements, in the order used by every index this class hands out
var placements: Array[BiomePlacement] = []

var _count := 0
var _cx := PackedFloat64Array()
var _cz := PackedFloat64Array()
var _hx := PackedFloat64Array()
var _hz := PackedFloat64Array()
var _half_blend := PackedFloat64Array()
var _min_half_blend := 1.0
var _noise: Array[BiomeNoise] = []
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite
var _bounds := Rect2()
# Which layout cells are inside the world. The world edge is measured against the cells that are
# NOT part of any biome, never against the border between two biomes.
var _grid_min := Vector2i.ZERO
var _grid_w := 0
var _grid_h := 0
var _occ := PackedByteArray()          # 1 = covered by a biome
var _near_empty := {}                  # cell index -> PackedFloat64Array of x0,z0,x1,z1 of empty cells nearby
var _edge_reach := 1                   # cells: how far the cliff ring reaches inward
# Leveled ground under POIs (see set_pads)
const PAD_CELL := 128.0
## Meters over which level ranges blend across a biome border (half on each side)
const LEVEL_BLEND := 900.0
var _pad_x := PackedFloat64Array()
var _pad_z := PackedFloat64Array()
var _pad_flat := PackedFloat64Array()
var _pad_out := PackedFloat64Array()
var _pad_h := PackedFloat64Array()
var _pad_grid := {}  # Vector2i -> PackedInt32Array of pad indices
## Town centers (x, z): places are easier near towns and roads, harder deep in the wild
var _towns := PackedVector2Array()
## Roads and town streets (see set_roads). null = no roads.
var roads: RoadNetwork


func _init(p_settings: WorldSettings, p_seed: int) -> void:
	settings = p_settings
	world_seed = p_seed
	placements = settings.get_valid_placements()
	_count = placements.size()

	var shared := {}  # biome -> BiomeNoise, so repeated biomes share one set of noise
	var bounds_set := false
	for p in placements:
		var r := p.get_rect(settings.cell_size)
		var c := r.get_center()
		_cx.append(c.x)
		_cz.append(c.y)
		_hx.append(r.size.x * 0.5)
		_hz.append(r.size.y * 0.5)
		_half_blend.append(maxf(p.biome.blend_distance, 1.0) * 0.5)
		_bounds = r if not bounds_set else _bounds.merge(r)
		bounds_set = true
		if not shared.has(p.biome):
			shared[p.biome] = _make_biome_noise(p.biome)
		_noise.append(shared[p.biome])

	_build_edge_grid()
	_min_half_blend = INF
	for hb in _half_blend:
		_min_half_blend = minf(_min_half_blend, hb)
	if _count == 0:
		_min_half_blend = 1.0

	# Two octaves: wiggly enough to look natural, gentle enough not to steepen the terrain at borders
	_warp_x = _make_noise("warp_x", settings.border_warp_scale, 2, FastNoiseLite.FRACTAL_FBM)
	_warp_z = _make_noise("warp_z", settings.border_warp_scale, 2, FastNoiseLite.FRACTAL_FBM)
	# Warping can move the world edge outward by this much, so the bounds grow with it
	_bounds = _bounds.grow(settings.border_warp_strength + 1.0)


# ---------------------------------------------------------------- public queries

## Rectangle (x, z in meters) that contains the whole world including the cliff ring
func get_bounds() -> Rect2:
	return _bounds


## Meters between this spot and the world edge, measured inward (negative = outside the world).
## The world edge is only where the combined layout ends, never a border between two biomes.
func get_inside_distance(x: float, z: float) -> float:
	var w := _warped(x, z)
	return -_exterior_sdf(w.x, w.y)


## Levels the ground under POIs: flat at the POI's height inside flatten_radius, blending back to
## the natural terrain out to footprint_radius. Call once before any terrain is built.
func set_pads(list: Array[PlacedPOI]) -> void:
	_pad_x.clear()
	_pad_z.clear()
	_pad_flat.clear()
	_pad_out.clear()
	_pad_h.clear()
	_pad_grid.clear()
	_towns.clear()
	for p in list:
		if p.town != null:
			_towns.append(Vector2(p.position.x, p.position.z))
		if p.poi.flatten_radius <= 0.0:
			continue
		var flat := minf(p.poi.flatten_radius, p.poi.footprint_radius)
		var outer := maxf(p.poi.footprint_radius, flat + 0.01)
		var idx := _pad_x.size()
		_pad_x.append(p.position.x)
		_pad_z.append(p.position.z)
		_pad_flat.append(flat)
		_pad_out.append(outer)
		_pad_h.append(p.position.y)
		var c0 := Vector2i(floori((p.position.x - outer) / PAD_CELL), floori((p.position.z - outer) / PAD_CELL))
		var c1 := Vector2i(floori((p.position.x + outer) / PAD_CELL), floori((p.position.z + outer) / PAD_CELL))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _pad_grid.get(key, PackedInt32Array())
				arr.append(idx)
				_pad_grid[key] = arr


## Is the ground here under the water (when the world has water)?
func is_under_water(height: float) -> bool:
	return settings.water_enabled and height < settings.sea_level


## Is this spot on the leveled ground of a town or a point of interest? Thread-safe.
func is_on_pad(x: float, z: float) -> bool:
	var pads: PackedInt32Array = _pad_grid.get(Vector2i(floori(x / PAD_CELL), floori(z / PAD_CELL)), PackedInt32Array())
	for pi in pads:
		var dx := x - _pad_x[pi]
		var dz := z - _pad_z[pi]
		if dx * dx + dz * dz < _pad_out[pi] * _pad_out[pi]:
			return true
	return false


## Levels and colors the ground under roads. Call once before any terrain is built.
func set_roads(network: RoadNetwork) -> void:
	roads = network


func get_placement_rect(index: int) -> Rect2:
	return placements[index].get_rect(settings.cell_size)


## Where the player starts: the middle of the spawn placement, standing on the ground
func get_spawn_point() -> Vector3:
	if _count == 0:
		return Vector3.ZERO
	var i := clampi(settings.spawn_placement, 0, _count - 1)
	var c := get_placement_rect(i).get_center()
	return Vector3(c.x, get_height(c.x, c.y), c.y)


func get_height(x: float, z: float) -> float:
	var s := Sample.new()
	sample(x, z, s)
	return s.height


## Which placement owns this spot (index into `placements`), or -1 outside the world
func get_placement_index_at(x: float, z: float) -> int:
	if _count == 0:
		return -1
	var w := _warped(x, z)
	var best := -1
	var best_w := -1.0
	var union_sdf := INF
	for i in _count:
		var sdf := _sdf(i, w.x, w.y)
		union_sdf = minf(union_sdf, sdf)
		var weight := 1.0 - smoothstep(-_half_blend[i], _half_blend[i], sdf)
		if weight > best_w:
			best_w = weight
			best = i
	return best if union_sdf <= 0.0 else -1


## The level range of the land here: each nearby biome rectangle's range (BiomePlacement can
## override the biome's), blended across borders the same way the ground color blends.
## Returns Vector2(min, max) as floats; LevelCurve.zone_range() rounds it and narrows it by how
## far the spot is from a town.
func get_level_band(x: float, z: float) -> Vector2:
	if _count == 0:
		return Vector2(1, 10)
	var wp := _warped(x, z)
	var lo := 0.0
	var hi := 0.0
	var total := 0.0
	for i in _count:
		# levels blend over a much wider zone than the ground does, so they never jump at a border
		var w := 1.0 - smoothstep(-LEVEL_BLEND, LEVEL_BLEND, _sdf(i, wp.x, wp.y))
		if w <= 0.0:
			continue
		var r := placements[i].get_level_range()
		lo += w * r.x
		hi += w * r.y
		total += w
	if total <= 0.0:
		return Vector2(1, 10)
	return Vector2(lo / total, hi / total)


## Meters to the nearest town center (INF if the world has no towns)
func get_town_distance(x: float, z: float) -> float:
	var best := INF
	for t in _towns:
		best = minf(best, t.distance_to(Vector2(x, z)))
	return best


func get_biome_at(x: float, z: float) -> BiomeData:
	var i := get_placement_index_at(x, z)
	return placements[i].biome if i >= 0 else null


## Fills `out` with everything about the ground at (x, z). Thread-safe if each thread owns its `out`.
func sample(x: float, z: float, out: Sample) -> void:
	var n := _count
	if n == 0:
		out.height = 0.0
		out.color = Color(0.4, 0.4, 0.4)
		out.steep_color = out.color
		out.map_color = out.color
		out.biome_index = -1
		out.edge = 0.0
		return
	if out.weights.size() != n:
		out.weights.resize(n)
		out.sdfs.resize(n)

	var w := _warped(x, z)
	var union_sdf := INF
	var blend := 0.0
	for i in n:
		var sdf := _sdf(i, w.x, w.y)
		out.sdfs[i] = sdf
		union_sdf = minf(union_sdf, sdf)
		# Where a border is inside the blend zone of two biomes, the wider blend wins, so a
		# soft mountain biome stays soft even next to a biome with a small blend distance
		if absf(sdf) < _half_blend[i]:
			blend = maxf(blend, _half_blend[i])
	if blend <= 0.0:
		blend = _min_half_blend
	var total := 0.0
	for i in n:
		var weight := 1.0 - smoothstep(-blend, blend, out.sdfs[i])
		out.weights[i] = weight
		total += weight

	if total < 1.0:
		# Outside the blend zones (the cliff plateau) the weights fade to nothing. Hand the missing
		# share to the closest biomes, smoothly (softmax over distance), so there is never a jump.
		var soft := 0.0
		for i in n:
			soft += exp(-(out.sdfs[i] - union_sdf) / OUTSIDE_SOFTNESS)
		var missing := 1.0 - total
		for i in n:
			out.weights[i] += missing * exp(-(out.sdfs[i] - union_sdf) / OUTSIDE_SOFTNESS) / soft
		total = 1.0

	var inv := 1.0 / total
	var h := 0.0
	var cr := 0.0
	var cg := 0.0
	var cb := 0.0
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var mr := 0.0
	var mg := 0.0
	var mb := 0.0
	var s_start := 0.0
	var s_full := 0.0
	var best := 0
	var best_w := -1.0
	for i in n:
		var weight: float = out.weights[i] * inv
		if weight <= 0.0:
			continue
		var bn := _noise[i]
		_eval_biome(bn, x, z, -out.sdfs[i], out)
		h += weight * out._th
		cr += weight * out._tc.r
		cg += weight * out._tc.g
		cb += weight * out._tc.b
		var b := bn.biome
		sr += weight * b.steep_color.r
		sg += weight * b.steep_color.g
		sb += weight * b.steep_color.b
		mr += weight * b.map_color.r
		mg += weight * b.map_color.g
		mb += weight * b.map_color.b
		s_start += weight * b.steep_slope_start
		s_full += weight * b.steep_slope_full
		if weight > best_w:
			best_w = weight
			best = i

	var edge := smoothstep(-settings.edge_width, 0.0, _exterior_sdf(w.x, w.y))
	var final_height := h + edge * settings.edge_height
	if not _pad_grid.is_empty():
		var pads: PackedInt32Array = _pad_grid.get(Vector2i(floori(x / PAD_CELL), floori(z / PAD_CELL)), PackedInt32Array())
		for pi in pads:
			var dx := x - _pad_x[pi]
			var dz := z - _pad_z[pi]
			var dist2 := dx * dx + dz * dz
			var outer: float = _pad_out[pi]
			if dist2 < outer * outer:
				var pad_w := 1.0 - smoothstep(_pad_flat[pi], outer, sqrt(dist2))
				final_height = lerpf(final_height, _pad_h[pi], pad_w)
	out.height = final_height
	out.color = Color(cr, cg, cb)
	out.steep_color = Color(sr, sg, sb)
	out.map_color = Color(mr, mg, mb)
	out.steep_start = s_start
	out.steep_full = s_full
	out.biome_index = best
	out.edge = edge
	if roads != null:
		roads.apply(x, z, out)


# ---------------------------------------------------------------- the world edge

# Marks which cells of the layout are covered by a biome and, for the cells close enough to the
# outside to matter, remembers the empty cells around them.
func _build_edge_grid() -> void:
	_occ.clear()
	_near_empty.clear()
	if _count == 0:
		_grid_w = 0
		_grid_h = 0
		return
	var cs := settings.cell_size
	_edge_reach = maxi(ceili(settings.edge_width / cs) + 1, 1)
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for p in placements:
		lo = Vector2i(mini(lo.x, p.cell.x), mini(lo.y, p.cell.y))
		hi = Vector2i(maxi(hi.x, p.cell.x + p.size_cells.x), maxi(hi.y, p.cell.y + p.size_cells.y))
	var pad := _edge_reach + 1
	_grid_min = lo - Vector2i(pad, pad)
	_grid_w = hi.x - lo.x + pad * 2
	_grid_h = hi.y - lo.y + pad * 2
	_occ.resize(_grid_w * _grid_h)
	for p in placements:
		for cz in range(p.cell.y, p.cell.y + p.size_cells.y):
			for cx in range(p.cell.x, p.cell.x + p.size_cells.x):
				_occ[(cz - _grid_min.y) * _grid_w + (cx - _grid_min.x)] = 1
	# For each covered cell within reach of an empty one, list those empty cells' rectangles
	for gz in _grid_h:
		for gx in _grid_w:
			if _occ[gz * _grid_w + gx] == 0:
				continue
			var rects := PackedFloat64Array()
			for dz in range(-_edge_reach, _edge_reach + 1):
				for dx in range(-_edge_reach, _edge_reach + 1):
					var nx := gx + dx
					var nz := gz + dz
					var empty := nx < 0 or nz < 0 or nx >= _grid_w or nz >= _grid_h or _occ[nz * _grid_w + nx] == 0
					if empty:
						rects.append(float(nx + _grid_min.x) * cs)
						rects.append(float(nz + _grid_min.y) * cs)
						rects.append(float(nx + _grid_min.x + 1) * cs)
						rects.append(float(nz + _grid_min.y + 1) * cs)
			if not rects.is_empty():
				_near_empty[gz * _grid_w + gx] = rects


# Signed distance to the outside of the world at a (warped) position: negative inside, positive
# outside. Inside it is only measured when the outside is within the cliff ring's reach, otherwise
# it returns a value large enough to mean "nowhere near the edge".
func _exterior_sdf(wx: float, wz: float) -> float:
	var cs := settings.cell_size
	var gx := floori(wx / cs) - _grid_min.x
	var gz := floori(wz / cs) - _grid_min.y
	if gx < 0 or gz < 0 or gx >= _grid_w or gz >= _grid_h:
		return 1.0
	var idx := gz * _grid_w + gx
	if _occ[idx] == 0:
		return 1.0
	if not _near_empty.has(idx):
		return -(settings.edge_width + cs)
	var rects: PackedFloat64Array = _near_empty[idx]
	var best := INF
	for i in range(0, rects.size(), 4):
		var dx := maxf(maxf(rects[i] - wx, wx - rects[i + 2]), 0.0)
		var dz := maxf(maxf(rects[i + 1] - wz, wz - rects[i + 3]), 0.0)
		best = minf(best, dx * dx + dz * dz)
	return -sqrt(best)


# ---------------------------------------------------------------- internals

# Position after domain warping (only used to decide WHICH biome we are in)
func _warped(x: float, z: float) -> Vector2:
	var s := settings.border_warp_strength
	return Vector2(x + _warp_x.get_noise_2d(x, z) * s, z + _warp_z.get_noise_2d(x, z) * s)


# Signed distance to biome rectangle i: negative inside, positive outside, 0 on the edge
func _sdf(i: int, wx: float, wz: float) -> float:
	var qx := absf(wx - _cx[i]) - _hx[i]
	var qz := absf(wz - _cz[i]) - _hz[i]
	var ox := maxf(qx, 0.0)
	var oz := maxf(qz, 0.0)
	return sqrt(ox * ox + oz * oz) + minf(maxf(qx, qz), 0.0)


# One biome's own height and ground color at a spot (results go into out._th / out._tc).
# depth = how far inside this biome's rectangle the spot is (meters, negative outside).
func _eval_biome(bn: BiomeNoise, x: float, z: float, depth: float, out: Sample) -> void:
	var b := bn.biome
	var h := b.base_height + bn.hills.get_noise_2d(x, z) * b.hills_amplitude
	if b.mountain_amplitude != 0.0:
		# Ridged noise: ridge lines come out near 1, valleys near 0
		var ridge := (bn.mountains.get_noise_2d(x, z) + 1.0) * 0.5
		var mask := 1.0
		if b.mountain_coverage < 1.0:
			var threshold := 1.0 - b.mountain_coverage
			mask = smoothstep(threshold - 0.12, threshold + 0.12, (bn.mountain_mask.get_noise_2d(x, z) + 1.0) * 0.5)
		# Mountains only rise once you are a blend distance inside the biome, so a border is
		# always gentle ground that melts into the neighbor instead of a cliff
		var inland := smoothstep(0.0, maxf(b.blend_distance, 1.0), depth)
		h += ridge * ridge * b.mountain_amplitude * mask * inland
	h += bn.detail.get_noise_2d(x, z) * b.detail_amplitude

	var patch := (bn.patch.get_noise_2d(x, z) + 1.0) * 0.5
	var c := b.ground_color.lerp(b.ground_color_alt, patch)
	if b.peak_height < 50000.0:
		c = c.lerp(b.peak_color, smoothstep(b.peak_height, b.peak_height + b.peak_blend, h))
	out._th = h
	out._tc = c


func _seed_for(key: String) -> int:
	return ("%d|%s" % [world_seed, key]).hash()


func _make_noise(key: String, scale_m: float, octaves: int, fractal: int, gain: float = 0.5) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = _seed_for(key)
	n.frequency = 1.0 / maxf(scale_m, 0.01)
	n.fractal_type = fractal as FastNoiseLite.FractalType
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = 2.0
	return n


func _make_biome_noise(b: BiomeData) -> BiomeNoise:
	var k := b.get_key()
	var bn := BiomeNoise.new()
	bn.biome = b
	bn.hills = _make_noise(k + "/hills", b.hills_scale, b.hills_octaves, FastNoiseLite.FRACTAL_FBM)
	bn.mountains = _make_noise(k + "/mountains", b.mountain_scale, 3, FastNoiseLite.FRACTAL_RIDGED, 0.4)
	bn.mountain_mask = _make_noise(k + "/mask", b.mountain_scale * 2.5, 2, FastNoiseLite.FRACTAL_FBM)
	bn.detail = _make_noise(k + "/detail", b.detail_scale, 2, FastNoiseLite.FRACTAL_FBM)
	bn.patch = _make_noise(k + "/patch", b.patch_scale, 2, FastNoiseLite.FRACTAL_FBM)
	return bn
