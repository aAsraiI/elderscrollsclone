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
## Regions layouts (Alpha 1.21, WorldSettings.layout_style) work the same way, except step 2: every
## placement scatters a few seed points inside its box and each spot belongs to the nearest seed (a
## Voronoi map, after the warping), so the regions are rounded blobs that meet without gaps. Each
## region's "signed distance" is half the difference between its seed distance and the owner's,
## which blends exactly like the rectangles did. The layout is an island: past a warped coastline
## the land falls into the sea (no cliff ring). Rivers and lakes (RiverNetwork) are carved last.
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
	var edge := 0.0                 # 0 = inside the world, 1 = on the cliff plateau / the open sea
	## Height of the water surface here (sea, lake or river), or -INF where there is none. The
	## ground is under water where height < water.
	var water := -INF
	## 0..1: how much this is a river or stream bed / bank (1 = in the channel)
	var river := 0.0
	## 0..1: how close a river, stream or lake shore is (1 = at the water)
	var near_water := 0.0
	## The second strongest biome here (-1 = none) and how much the strongest one wins (0.5..1)
	var biome2 := -1
	var biome_w := 1.0
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
	# Alpha 1.21 layers, made only when the biome uses them
	var swirl_x: FastNoiseLite
	var swirl_z: FastNoiseLite
	var valley: FastNoiseLite
	var dune: FastNoiseLite
	var dune_mask: FastNoiseLite
	var pool: FastNoiseLite
	var crag: FastNoiseLite
	var crag_mask: FastNoiseLite
	var cone: FastNoiseLite
	var dune_cos := 1.0
	var dune_sin := 0.0


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
var _pad_core := PackedFloat64Array()  # the place itself (its footprint), without the wider bank round it
var _pad_h := PackedFloat64Array()
var _pad_sx := PackedFloat64Array()  # a town pad's gentle tilt (rise per meter along X and Z)
var _pad_sz := PackedFloat64Array()
## Steepest grade a town's ground keeps (Alpha 1.14: towns follow the slope they stand on)
const PAD_TILT_MAX := 0.06
## Widest extra bank (m) round a leveled place on steep land (Regions layouts)
const PAD_MAX_BANK := 120.0
var _pad_grid := {}  # Vector2i -> PackedInt32Array of pad indices
## Town centers (x, z): places are easier near towns and roads, harder deep in the wild
var _towns := PackedVector2Array()
## Roads and town streets (see set_roads). null = no roads.
var roads: RoadNetwork
## Rivers, streams and lakes (see set_rivers). null = none.
var rivers: RiverNetwork

# ---- Regions layouts
var _regions := false
var _site_x := PackedFloat64Array()
var _site_z := PackedFloat64Array()
var _site_region := PackedInt32Array()
var _reach := PackedFloat64Array()      # per region
# Which seeds can matter in each cell of a grid over the warped plane: index -> [sites, regions]
const LUT_CELL := 250.0
var _luts: Array = []  # per island: {"min", "w", "h", "cells": [[sites], [regions]]}
var _rwarp_x: FastNoiseLite
var _rwarp_z: FastNoiseLite
var _warp2_x: FastNoiseLite
var _warp2_z: FastNoiseLite
var _coast_x: FastNoiseLite
var _coast_z: FastNoiseLite
var _coast_fine: FastNoiseLite
var _coast_kind: FastNoiseLite
var _sea_floor: FastNoiseLite
var _land := Rect2()                    # all the islands' boxes together
var _place_island := PackedInt32Array()  # which island each placement is on (0 = the main one)
var _isl_rect: Array[Rect2] = []         # each island's boxes together
var _isl_round := PackedFloat64Array()  # corner rounding of each island (m)
var _isl_cwarp := PackedFloat64Array()  # how far its coast is bent (m)
var _isl_rwarp := PackedFloat64Array()  # its region warp, as a share of the world's
# Each region's rough extent and land area, from a coarse scan (see _scan_regions)
const SCAN_CELL := 80.0
var _scanned := false
var _scan_mutex := Mutex.new()
var _region_rects: Array[Rect2] = []
var _region_area := PackedFloat64Array()
var _region_center := PackedVector2Array()


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

	_regions = settings.is_regions() and _count > 0
	if _regions:
		_init_regions()
	else:
		_build_edge_grid()
	_min_half_blend = INF
	for hb in _half_blend:
		_min_half_blend = minf(_min_half_blend, hb)
	if _count == 0:
		_min_half_blend = 1.0

	# Two octaves: wiggly enough to look natural, gentle enough not to steepen the terrain at borders
	_warp_x = _make_noise("warp_x", settings.border_warp_scale, 2, FastNoiseLite.FRACTAL_FBM)
	_warp_z = _make_noise("warp_z", settings.border_warp_scale, 2, FastNoiseLite.FRACTAL_FBM)
	if _regions:
		_bounds = _land.grow(settings.sea_margin)
		_build_lut()
		return
	# Warping can move the world edge outward by this much, so the bounds grow with it
	_bounds = _bounds.grow(settings.border_warp_strength + 1.0)


# ---------------------------------------------------------------- public queries

## Rectangle (x, z in meters) that contains the whole world including the cliff ring
func get_bounds() -> Rect2:
	return _bounds


## Meters between this spot and the world edge, measured inward (negative = outside the world).
## The world edge is only where the combined layout ends, never a border between two biomes.
func get_inside_distance(x: float, z: float) -> float:
	if _regions:
		return -_coast_sdf(x, z)
	var w := _warped(x, z)
	return -_exterior_sdf(w.x, w.y)


## Levels the ground under POIs: flat at the POI's height inside flatten_radius, blending back to
## the natural terrain out to footprint_radius. Call once before any terrain is built.
func set_pads(list: Array[PlacedPOI]) -> void:
	_pad_x.clear()
	_pad_z.clear()
	_pad_flat.clear()
	_pad_out.clear()
	_pad_core.clear()
	_pad_h.clear()
	_pad_sx.clear()
	_pad_sz.clear()
	_pad_grid.clear()
	_towns.clear()
	for p in list:
		if p.town != null:
			_towns.append(Vector2(p.position.x, p.position.z))
		if p.poi.flatten_radius <= 0.0:
			continue
		var flat := minf(p.poi.flatten_radius, p.poi.footprint_radius)
		var outer := maxf(p.poi.footprint_radius, flat + 0.01)
		if _regions:
			# the steeper the land round it, the wider the bank down (or up) to the leveled ground, so
			# a town on a hillside sits on a terrace, not at the foot of a wall (at most ~1 in 2.5)
			var dev := 0.0
			for q in 10:
				var a := float(q) / 10.0 * TAU
				dev = maxf(dev, absf(get_height(p.position.x + cos(a) * outer, p.position.z + sin(a) * outer) - p.position.y))
			outer += clampf(dev * 2.5 - (outer - flat), 0.0, PAD_MAX_BANK)
		var idx := _pad_x.size()
		_pad_x.append(p.position.x)
		_pad_z.append(p.position.z)
		_pad_flat.append(flat)
		_pad_out.append(outer)
		_pad_core.append(maxf(p.poi.footprint_radius, flat + 0.01))
		_pad_h.append(p.position.y)
		var tilt := Vector2.ZERO
		if p.poi is TownData and TownLayout.compact:
			# worked out once, from the land before anything was built on it, and kept: the town's
			# streets and buildings are laid out on this same tilted ground
			if p.extra.has("tilt"):
				tilt = p.extra["tilt"]
			else:
				var r := flat * 0.8
				tilt = Vector2(get_height(p.position.x + r, p.position.z) - get_height(p.position.x - r, p.position.z), get_height(p.position.x, p.position.z + r) - get_height(p.position.x, p.position.z - r)) / (2.0 * r)
				tilt = tilt.limit_length(PAD_TILT_MAX)
				p.extra["tilt"] = tilt
		_pad_sx.append(tilt.x)
		_pad_sz.append(tilt.y)
		var c0 := Vector2i(floori((p.position.x - outer) / PAD_CELL), floori((p.position.z - outer) / PAD_CELL))
		var c1 := Vector2i(floori((p.position.x + outer) / PAD_CELL), floori((p.position.z + outer) / PAD_CELL))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _pad_grid.get(key, PackedInt32Array())
				arr.append(idx)
				_pad_grid[key] = arr


## Is the ground here under the water (when the world has water)? Only the sea: use is_wet()
## to count lakes and rivers too.
func is_under_water(height: float) -> bool:
	return settings.water_enabled and height < settings.sea_level


## Is this spot out past the coastline (Regions layouts; always false for the older worlds)?
func is_sea(x: float, z: float) -> bool:
	return _regions and _coast_sdf(x, z) > 0.0


## Is this spot under water: the sea, a lake or a river? height = the ground here (from sample()).
func is_wet(x: float, z: float, height: float, margin: float = 0.0) -> bool:
	if is_under_water(height - margin):
		return true
	return rivers != null and rivers.water_level(x, z) > height - margin


## Height of the water surface at a spot (sea, lake or river), or -INF where there is none
func get_water_level(x: float, z: float) -> float:
	var level := settings.sea_level if settings.water_enabled else -INF
	if rivers != null:
		level = maxf(level, rivers.water_level(x, z))
	return level


## Rivers, streams and lakes, carved into the ground from now on. Call once before any terrain
## is built (and before towns and roads, which keep out of the water).
func set_rivers(network: RiverNetwork) -> void:
	rivers = network


## Is this spot on the leveled ground of a town or a point of interest? Thread-safe.
func is_on_pad(x: float, z: float) -> bool:
	var pads: PackedInt32Array = _pad_grid.get(Vector2i(floori(x / PAD_CELL), floori(z / PAD_CELL)), PackedInt32Array())
	for pi in pads:
		var dx := x - _pad_x[pi]
		var dz := z - _pad_z[pi]
		if dx * dx + dz * dz < _pad_core[pi] * _pad_core[pi]:
			return true
	return false


## Meters round a building's footprint over which the ground blends back from its floor
const FOUNDATION_BLEND := 4.0
var _fd_x := PackedFloat64Array()
var _fd_z := PackedFloat64Array()
var _fd_hx := PackedFloat64Array()  # half size along the building's own x and z
var _fd_hz := PackedFloat64Array()
var _fd_c := PackedFloat64Array()   # cos and sin of its turn
var _fd_s := PackedFloat64Array()
var _fd_h := PackedFloat64Array()   # floor height
var _fd_grid := {}  # Vector2i -> PackedInt32Array


## The ground under every building is leveled to its floor and blends back round it, so nothing
## stands on stilts of air on a slope or sinks into a bank. Each: {"pos": Vector3 (floor middle),
## "half": Vector2 (half width, half depth), "yaw": float}. Call once, before roads and terrain.
func set_foundations(list: Array) -> void:
	_fd_x.clear()
	_fd_z.clear()
	_fd_hx.clear()
	_fd_hz.clear()
	_fd_c.clear()
	_fd_s.clear()
	_fd_h.clear()
	_fd_grid.clear()
	for f: Dictionary in list:
		var p: Vector3 = f["pos"]
		var half: Vector2 = f["half"]
		var yaw: float = f.get("yaw", 0.0)
		var idx := _fd_x.size()
		_fd_x.append(p.x)
		_fd_z.append(p.z)
		_fd_hx.append(half.x)
		_fd_hz.append(half.y)
		_fd_c.append(cos(yaw))
		_fd_s.append(sin(yaw))
		_fd_h.append(p.y)
		var reach := half.length() + FOUNDATION_BLEND
		for cz in range(floori((p.z - reach) / PAD_CELL), floori((p.z + reach) / PAD_CELL) + 1):
			for cx in range(floori((p.x - reach) / PAD_CELL), floori((p.x + reach) / PAD_CELL) + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _fd_grid.get(key, PackedInt32Array())
				arr.append(idx)
				_fd_grid[key] = arr


func _foundations(x: float, z: float, h: float) -> float:
	if _fd_grid.is_empty():
		return h
	var list: PackedInt32Array = _fd_grid.get(Vector2i(floori(x / PAD_CELL), floori(z / PAD_CELL)), PackedInt32Array())
	var best := 0.0
	var best_h := h
	for i in list:
		var dx := x - _fd_x[i]
		var dz := z - _fd_z[i]
		# into the building's own frame (Godot's yaw turns +Z toward +X)
		var lx := absf(dx * _fd_c[i] - dz * _fd_s[i]) - _fd_hx[i]
		var lz := absf(dx * _fd_s[i] + dz * _fd_c[i]) - _fd_hz[i]
		var d := Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()
		var w := 1.0 - smoothstep(0.3, FOUNDATION_BLEND, d)
		if w > best:
			best = w
			best_h = _fd_h[i]
	return lerpf(h, best_h, best) if best > 0.0 else h


## Levels and colors the ground under roads. Call once before any terrain is built.
func set_roads(network: RoadNetwork) -> void:
	roads = network


## The box a region fills: its placement's rectangle, or for a Regions layout the box round the
## land it really covers
func get_placement_rect(index: int) -> Rect2:
	if _regions:
		_scan_regions()
		return _region_rects[index]
	return placements[index].get_rect(settings.cell_size)


## Square meters of dry land in a region (a Regions layout's sea is not counted)
func get_region_area(index: int) -> float:
	if _regions:
		_scan_regions()
		return _region_area[index]
	return get_placement_rect(index).get_area()


## The middle of a region: the middle of its land for a Regions layout
func get_region_center(index: int) -> Vector2:
	if _regions:
		_scan_regions()
		return _region_center[index]
	return get_placement_rect(index).get_center()


## Where the player starts: the middle of the spawn placement, standing on the ground
func get_spawn_point() -> Vector3:
	if _count == 0:
		return Vector3.ZERO
	var i := clampi(settings.spawn_placement, 0, _count - 1)
	var c := get_region_center(i)
	return Vector3(c.x, get_height(c.x, c.y), c.y)


func get_height(x: float, z: float) -> float:
	var s := Sample.new()
	sample(x, z, s)
	return s.height


## Which placement owns this spot (index into `placements`), or -1 outside the world
func get_placement_index_at(x: float, z: float) -> int:
	if _count == 0:
		return -1
	if _regions:
		if _coast_sdf(x, z) > OPEN_SEA:
			return -1
		var rw := _region_warped(x, z)
		return _owner(rw)
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
	var wp := _region_warped(x, z) if _regions else Vector3.ZERO
	var wr := _warped(x, z) if not _regions else Vector2.ZERO
	var dist := _region_distances(wp) if _regions else PackedFloat64Array()
	var nearest := INF
	for d in dist:
		nearest = minf(nearest, d)
	var lo := 0.0
	var hi := 0.0
	var total := 0.0
	for i in _count:
		# levels blend over a much wider zone than the ground does, so they never jump at a border
		var sdf := (dist[i] - nearest) * 0.5 if _regions else _sdf(i, wr.x, wr.y)
		var lb := LEVEL_BLEND * (0.5 if _regions else 1.0)  # the island's regions are smaller
		var w := 1.0 - smoothstep(-lb, lb, sdf)
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
	out.river = 0.0
	out.near_water = 0.0
	out.biome2 = -1
	out.biome_w = 1.0
	out.water = settings.sea_level if settings.water_enabled else -INF
	if _regions:
		_sample_regions(x, z, out)
		return

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
				final_height = lerpf(final_height, _pad_h[pi] + _pad_sx[pi] * dx + _pad_sz[pi] * dz, pad_w)
	out.height = _foundations(x, z, final_height)
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
	# Swirl (domain warping): the big shapes are read from a pushed-about position, so hills
	# stretch into winding ridges and the valleys between them curve
	var sx := x
	var sz := z
	if bn.swirl_x != null:
		sx += bn.swirl_x.get_noise_2d(x, z) * b.swirl
		sz += bn.swirl_z.get_noise_2d(x, z) * b.swirl
	var h := b.base_height + bn.hills.get_noise_2d(sx, sz) * b.hills_amplitude
	# The big features only rise once you are a blend distance inside the biome, so a border is
	# always gentle ground that melts into the neighbor instead of a cliff
	var inland := smoothstep(0.0, maxf(b.blend_distance, 1.0), depth)
	if b.mountain_amplitude != 0.0:
		# Ridged noise: ridge lines come out near 1, valleys near 0
		var ridge := (bn.mountains.get_noise_2d(sx, sz) + 1.0) * 0.5
		var mask := 1.0
		if b.mountain_coverage < 1.0:
			var threshold := 1.0 - b.mountain_coverage
			mask = smoothstep(threshold - 0.12, threshold + 0.12, (bn.mountain_mask.get_noise_2d(x, z) + 1.0) * 0.5)
		h += pow(ridge, b.ridge_sharpness) * b.mountain_amplitude * mask * inland
	if bn.cone != null:
		# Cellular distance: 0 at a cone's middle. A cone with a crater bowl at the top.
		var r := clampf((bn.cone.get_noise_2d(x, z) + 1.0) / 0.85, 0.0, 1.0)
		var top := 1.0 - r
		var cone := top * top * (3.0 - 2.0 * top)
		cone -= b.crater_depth * smoothstep(0.72, 0.9, top) * 1.6
		h += maxf(cone, 0.0) * b.cone_amplitude * inland
	if bn.valley != null:
		# Valleys follow the noise's zero lines: |n| near 0 = the valley floor
		var v := absf(bn.valley.get_noise_2d(sx, sz))
		var carve := 1.0 - smoothstep(0.0, b.valley_width, v)
		h -= carve * carve * (3.0 - 2.0 * carve) * b.valley_depth * (0.35 + 0.65 * inland)
	if bn.dune != null:
		# Long crests across the wind, bent by the swirl, in fields with flat sand between
		var u := sx * bn.dune_cos + sz * bn.dune_sin
		var t := -sx * bn.dune_sin + sz * bn.dune_cos
		var crest := 1.0 - absf(bn.dune.get_noise_2d(u, t * 0.3))
		var field := smoothstep(0.35, 0.65, (bn.dune_mask.get_noise_2d(x, z) + 1.0) * 0.5)
		h += crest * crest * crest * b.dune_amplitude * field * inland
	if bn.crag != null:
		# Tors and spires: steep bumps round the cellular points, only where the mask allows
		var d := bn.crag.get_noise_2d(x, z) + 1.0
		var spike := 1.0 - smoothstep(0.0, b.crag_size, d)
		var crag_mask := smoothstep(0.45, 0.7, (bn.crag_mask.get_noise_2d(x, z) + 1.0) * 0.5)
		h += spike * spike * b.crag_amplitude * crag_mask * inland
	if b.terrace_height > 0.0:
		# Mesas and strata: flat treads with steep risers, kept soft near the border
		var steps := h / b.terrace_height
		var k := floorf(steps)
		var f := steps - k
		var stepped := (k + smoothstep(b.terrace_sharpness, 1.0, f)) * b.terrace_height
		h = lerpf(h, stepped, inland)
	if bn.pool != null:
		# Flat-bottomed hollows: where the land is low enough they hold water
		var p := (bn.pool.get_noise_2d(x, z) + 1.0) * 0.5
		var lo := 1.0 - b.pool_coverage
		h -= smoothstep(lo, lo + 0.07, p) * b.pool_depth
	h += bn.detail.get_noise_2d(x, z) * b.detail_amplitude

	var patch := (bn.patch.get_noise_2d(x, z) + 1.0) * 0.5
	var c := b.ground_color.lerp(b.ground_color_alt, patch)
	if b.high_full > 0.0:
		c = c.lerp(b.high_color, smoothstep(b.base_height + b.high_start, b.base_height + b.high_full, h + (patch - 0.5) * 6.0))
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
	if b.swirl > 0.0:
		bn.swirl_x = _make_noise(k + "/swirl_x", b.swirl_scale, 2, FastNoiseLite.FRACTAL_FBM)
		bn.swirl_z = _make_noise(k + "/swirl_z", b.swirl_scale, 2, FastNoiseLite.FRACTAL_FBM)
	if b.valley_depth > 0.0:
		bn.valley = _make_noise(k + "/valley", b.valley_scale, 3, FastNoiseLite.FRACTAL_FBM, 0.45)
	if b.dune_amplitude > 0.0:
		bn.dune = _make_noise(k + "/dune", b.dune_scale * 2.0, 1, FastNoiseLite.FRACTAL_NONE)
		bn.dune_mask = _make_noise(k + "/dune_mask", b.dune_scale * 12.0, 2, FastNoiseLite.FRACTAL_FBM)
		bn.dune_cos = cos(deg_to_rad(b.dune_angle))
		bn.dune_sin = sin(deg_to_rad(b.dune_angle))
	if b.pool_depth > 0.0:
		bn.pool = _make_noise(k + "/pool", b.pool_scale, 2, FastNoiseLite.FRACTAL_FBM)
	if b.crag_amplitude > 0.0:
		bn.crag = _make_cells(k + "/crag", b.crag_scale)
		bn.crag_mask = _make_noise(k + "/crag_mask", b.crag_scale * 6.0, 2, FastNoiseLite.FRACTAL_FBM)
	if b.cone_amplitude > 0.0:
		bn.cone = _make_cells(k + "/cone", b.cone_scale)
	return bn


# Cellular noise: the distance to the nearest of scattered points, minus 1 (in units of the spacing)
func _make_cells(key: String, scale_m: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.seed = _seed_for(key)
	n.frequency = 1.0 / maxf(scale_m, 0.01)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n.cellular_jitter = 0.85
	return n


# ---------------------------------------------------------------- Regions layouts (Alpha 1.21)

## Meters out to sea past the coastline where the world counts as "outside" (no biome, no cover)
const OPEN_SEA := 160.0
## The sea floor's colour, mixed into the ground under deep water
const SEA_FLOOR := Color(0.42, 0.4, 0.33)


# The islands (the main one, then WorldSettings.islands), the seed points of every region, and the
# noise that bends the borders and the coasts
func _init_regions() -> void:
	var cs := settings.cell_size
	_isl_rect.clear()
	_isl_round.clear()
	_isl_cwarp.clear()
	_isl_rwarp.clear()
	for i in _count:
		var p := placements[i]
		var isle := settings.island_of(p)
		_place_island.append(isle)
		var r := p.get_rect(cs)
		_land = r if i == 0 else _land.merge(r)
		while _isl_rect.size() <= isle:
			_isl_rect.append(Rect2())
		_isl_rect[isle] = r if not _isl_rect[isle].has_area() else _isl_rect[isle].merge(r)
		_reach.append(p.reach)
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed_for("sites|%s|%d,%d" % [p.biome.get_key(), p.cell.x, p.cell.y])
		var n := maxi(1, roundi(r.get_area() / 1.0e6 * settings.region_seeds_per_km2))
		# A jittered grid over the middle of the box: the seeds fill the box without bunching up
		var cols := maxi(1, roundi(sqrt(float(n) * r.size.x / maxf(r.size.y, 1.0))))
		var rows := ceili(float(n) / float(cols))
		var inner := r.grow_individual(-r.size.x * 0.16, -r.size.y * 0.16, -r.size.x * 0.16, -r.size.y * 0.16)
		var made := 0
		for row in rows:
			for col in cols:
				if made >= n:
					break
				var fx := (float(col) + 0.5 + rng.randf_range(-0.35, 0.35)) / float(cols)
				var fz := (float(row) + 0.5 + rng.randf_range(-0.35, 0.35)) / float(rows)
				if n == 1:
					fx = 0.5 + rng.randf_range(-0.1, 0.1)
					fz = 0.5 + rng.randf_range(-0.1, 0.1)
				_site_x.append(inner.position.x + inner.size.x * fx)
				_site_z.append(inner.position.y + inner.size.y * fz)
				_site_region.append(i)
				made += 1
	# Each island's shape: how round, and how far its coast and borders are bent (a small island
	# gets gentler noise, or it would be torn into pieces)
	for k in _isl_rect.size():
		var data: IslandData = settings.islands[k - 1] if k > 0 and k - 1 < settings.islands.size() else null
		var small := minf(_isl_rect[k].size.x, _isl_rect[k].size.y)
		var fit := clampf(small / 9000.0, 0.15, 1.0)
		_isl_round.append(small * (data.roundness if data != null else 0.4))
		_isl_cwarp.append(data.coast_warp if data != null and data.coast_warp >= 0.0 else settings.coast_warp * fit)
		_isl_rwarp.append((data.region_warp / maxf(settings.region_warp_strength, 1.0)) if data != null and data.region_warp >= 0.0 else fit)
	_rwarp_x = _make_noise("rwarp_x", settings.region_warp_scale, 3, FastNoiseLite.FRACTAL_FBM)
	_rwarp_z = _make_noise("rwarp_z", settings.region_warp_scale, 3, FastNoiseLite.FRACTAL_FBM)
	_warp2_x = _make_noise("rwarp2_x", settings.region_detail_scale, 2, FastNoiseLite.FRACTAL_FBM)
	_warp2_z = _make_noise("rwarp2_z", settings.region_detail_scale, 2, FastNoiseLite.FRACTAL_FBM)
	_coast_x = _make_noise("coast_x", settings.coast_warp_scale, 3, FastNoiseLite.FRACTAL_FBM)
	_coast_z = _make_noise("coast_z", settings.coast_warp_scale, 3, FastNoiseLite.FRACTAL_FBM)
	_coast_fine = _make_noise("coast_fine", 160.0, 3, FastNoiseLite.FRACTAL_FBM)
	_coast_kind = _make_noise("coast_kind", 1400.0, 2, FastNoiseLite.FRACTAL_FBM)
	_sea_floor = _make_noise("sea_floor", 420.0, 3, FastNoiseLite.FRACTAL_FBM)


# For every cell of a grid over the (warped) plane, the seeds that can matter there: a seed is
# left out when it is certainly more than a whole blend zone further than the nearest one. One grid
# per island, holding only that island's seeds (a spot belongs to the island whose coast it is in).
func _build_lut() -> void:
	var band := 0.0
	for hb in _half_blend:
		band = maxf(band, hb)
	band = band * 4.0 + 1.0  # (d_i - d_owner) / 2 must reach a whole half blend
	_luts.clear()
	for isle in _isl_rect.size():
		var b := _isl_rect[isle].grow(settings.sea_margin + (settings.region_warp_strength * _isl_rwarp[isle]) + settings.region_detail_warp + LUT_CELL)
		var lut := {"min": b.position, "w": ceili(b.size.x / LUT_CELL), "h": ceili(b.size.y / LUT_CELL), "cells": []}
		var w: int = lut["w"]
		var h: int = lut["h"]
		var cells: Array = lut["cells"]
		cells.resize(w * h)
		var sites := PackedInt32Array()
		for s in _site_x.size():
			if _place_island[_site_region[s]] == isle:
				sites.append(s)
		var near := PackedFloat64Array()
		near.resize(sites.size())
		for gz in h:
			for gx in w:
				var x0: float = b.position.x + gx * LUT_CELL
				var z0: float = b.position.y + gz * LUT_CELL
				var x1 := x0 + LUT_CELL
				var z1 := z0 + LUT_CELL
				var best_far := INF
				for q in sites.size():
					var s := sites[q]
					var sx := _site_x[s]
					var sz := _site_z[s]
					var dx := maxf(maxf(x0 - sx, sx - x1), 0.0)
					var dz := maxf(maxf(z0 - sz, sz - z1), 0.0)
					var fx := maxf(absf(sx - x0), absf(sx - x1))
					var fz := maxf(absf(sz - z0), absf(sz - z1))
					var reach := _reach[_site_region[s]]
					near[q] = sqrt(dx * dx + dz * dz) - reach
					best_far = minf(best_far, sqrt(fx * fx + fz * fz) - reach)
				var list := PackedInt32Array()
				var regs := PackedInt32Array()
				for q in sites.size():
					if near[q] <= best_far + band:
						list.append(sites[q])
						if not regs.has(_site_region[sites[q]]):
							regs.append(_site_region[sites[q]])
				cells[gz * w + gx] = [list, regs]
		_luts.append(lut)


# Where a spot is read from to decide its region (two layers of warping: broad bends, small
# wiggles), and which island it is on: (x, z, island)
func _region_warped(x: float, z: float) -> Vector3:
	var isle := int(_coast(x, z).y)
	var s := settings.region_warp_strength * _isl_rwarp[isle]
	var wx := x + _rwarp_x.get_noise_2d(x, z) * s
	var wz := z + _rwarp_z.get_noise_2d(x, z) * s
	var d := settings.region_detail_warp
	return Vector3(wx + _warp2_x.get_noise_2d(wx, wz) * d, wz + _warp2_z.get_noise_2d(wx, wz) * d, isle)


# Signed distance to the nearest coastline (negative on land, positive out at sea, meters roughly)
# and which island's coast that is: (distance, island)
func _coast(x: float, z: float) -> Vector2:
	var nx := _coast_x.get_noise_2d(x, z)
	var nz := _coast_z.get_noise_2d(x, z)
	var best := INF
	var isle := 0
	for k in _isl_rect.size():
		var r := _isl_rect[k]
		var rnd := minf(_isl_round[k], minf(r.size.x, r.size.y) * 0.5 - 1.0)
		var wx := x + nx * _isl_cwarp[k]
		var wz := z + nz * _isl_cwarp[k]
		var c := r.get_center()
		var qx := absf(wx - c.x) - (r.size.x * 0.5 - rnd)
		var qz := absf(wz - c.y) - (r.size.y * 0.5 - rnd)
		var d := sqrt(maxf(qx, 0.0) * maxf(qx, 0.0) + maxf(qz, 0.0) * maxf(qz, 0.0)) + minf(maxf(qx, qz), 0.0) - rnd
		if d < best:
			best = d
			isle = k
	var fine := clampf(minf(_isl_rect[isle].size.x, _isl_rect[isle].size.y) / 4000.0, 0.3, 1.0)
	return Vector2(best + _coast_fine.get_noise_2d(x, z) * 45.0 * fine, isle)


func _coast_sdf(x: float, z: float) -> float:
	return _coast(x, z).x


# Each region's distance score at a warped spot: the nearest of its seeds, less its reach (only the
# regions of the spot's own island; the others are INF)
func _region_distances(w: Vector3) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(_count)
	out.fill(INF)
	for s in _site_x.size():
		var r := _site_region[s]
		if _place_island[r] != int(w.z):
			continue
		var dx := w.x - _site_x[s]
		var dz := w.y - _site_z[s]
		out[r] = minf(out[r], sqrt(dx * dx + dz * dz) - _reach[r])
	return out


func _lut_cell(w: Vector3) -> Array:
	var lut: Dictionary = _luts[int(w.z)]
	var lmin: Vector2 = lut["min"]
	var gx := clampi(floori((w.x - lmin.x) / LUT_CELL), 0, int(lut["w"]) - 1)
	var gz := clampi(floori((w.y - lmin.y) / LUT_CELL), 0, int(lut["h"]) - 1)
	return lut["cells"][gz * int(lut["w"]) + gx]


# The region whose seed is nearest a warped spot
func _owner(w: Vector3) -> int:
	var cell: Array = _lut_cell(w)
	var best := INF
	var owner := -1
	for s: int in cell[0]:
		var dx := w.x - _site_x[s]
		var dz := w.y - _site_z[s]
		var d := sqrt(dx * dx + dz * dz) - _reach[_site_region[s]]
		if d < best:
			best = d
			owner = _site_region[s]
	return owner


func _sample_regions(x: float, z: float, out: Sample) -> void:
	var w := _region_warped(x, z)
	var cell: Array = _lut_cell(w)
	var regs: PackedInt32Array = cell[1]
	out.weights.fill(0.0)
	out.sdfs.fill(1.0e9)
	# Nearest seed of each region that can matter here
	for s: int in cell[0]:
		var dx := w.x - _site_x[s]
		var dz := w.y - _site_z[s]
		var r := _site_region[s]
		out.sdfs[r] = minf(out.sdfs[r], sqrt(dx * dx + dz * dz) - _reach[r])
	var owner := regs[0]
	var first := INF
	var second := INF
	for r in regs:
		var d: float = out.sdfs[r]
		if d < first:
			second = first
			first = d
			owner = r
		elif d < second:
			second = d
	if second == INF:
		second = first + 1.0e6
	# Signed distance to each region's border: half the gap to the owner's (the owner's own is
	# half the gap to the runner-up, negative)
	var blend := 0.0
	for r in regs:
		var sdf: float = (first - second) * 0.5 if r == owner else (out.sdfs[r] - first) * 0.5
		out.sdfs[r] = sdf
		if absf(sdf) < _half_blend[r]:
			blend = maxf(blend, _half_blend[r])
	if blend <= 0.0:
		blend = _min_half_blend
	var total := 0.0
	for r in regs:
		var weight := 1.0 - smoothstep(-blend, blend, out.sdfs[r])
		out.weights[r] = weight
		total += weight
	var inv := 1.0 / maxf(total, 0.0001)
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
	var hr := 0.0
	var hg := 0.0
	var hb := 0.0
	var s_start := 0.0
	var s_full := 0.0
	var best := owner
	var best_w := -1.0
	for r in regs:
		var weight: float = out.weights[r] * inv
		out.weights[r] = weight
		if weight <= 0.0:
			continue
		var bn := _noise[r]
		_eval_biome(bn, x, z, -out.sdfs[r], out)
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
		hr += weight * b.shore_color.r
		hg += weight * b.shore_color.g
		hb += weight * b.shore_color.b
		s_start += weight * b.steep_slope_start
		s_full += weight * b.steep_slope_full
		if weight > best_w:
			best_w = weight
			best = r
	var runner := -1
	var second_w := 0.0
	for r in regs:
		if r != best and out.weights[r] > second_w:
			second_w = out.weights[r]
			runner = r
	out.biome2 = runner
	out.biome_w = best_w / maxf(best_w + second_w, 0.0001)
	var col := Color(cr, cg, cb)
	var shore := Color(hr, hg, hb)
	# The coast: the land slopes down to a beach at the waterline (steeply where the coast is
	# narrow: sea cliffs), then the sea floor shelves away into deep water
	var e := _coast_sdf(x, z)
	var sea := settings.sea_level
	var width := lerpf(settings.coast_width_min, settings.coast_width_max, smoothstep(0.3, 0.7, (_coast_kind.get_noise_2d(x, z) + 1.0) * 0.5))
	if e > -width:
		if e >= 0.0:
			h = sea + 0.7 - settings.sea_depth * (1.0 - exp(-e / 380.0)) + _sea_floor.get_noise_2d(x, z) * 3.0 * smoothstep(0.0, 300.0, e)
		else:
			# a beach just above the water at the coastline, rising inland to meet the land
			var t := smoothstep(-width, 0.0, e)
			var beach := sea + 0.7 + (-e / width) * 2.5
			h = lerpf(h, minf(h, beach), t) if h > sea else lerpf(h, beach, t * 0.5)
		col = col.lerp(shore, smoothstep(-width * 0.25, 0.0, e) * 0.85)
		col = col.lerp(SEA_FLOOR, smoothstep(20.0, 200.0, e))
	if not _pad_grid.is_empty():
		var pads: PackedInt32Array = _pad_grid.get(Vector2i(floori(x / PAD_CELL), floori(z / PAD_CELL)), PackedInt32Array())
		for pi in pads:
			var dx := x - _pad_x[pi]
			var dz := z - _pad_z[pi]
			var dist2 := dx * dx + dz * dz
			var outer: float = _pad_out[pi]
			if dist2 < outer * outer:
				var pad_w := 1.0 - smoothstep(_pad_flat[pi], outer, sqrt(dist2))
				h = lerpf(h, _pad_h[pi] + _pad_sx[pi] * dx + _pad_sz[pi] * dz, pad_w)
	out.height = _foundations(x, z, h)
	out.color = col
	out.steep_color = Color(sr, sg, sb)
	out.map_color = Color(mr, mg, mb)
	out.steep_start = s_start
	out.steep_full = s_full
	out.biome_index = best
	out.edge = smoothstep(OPEN_SEA, OPEN_SEA * 2.0, e)
	if roads != null:
		roads.apply(x, z, out)
	if rivers != null:
		rivers.apply(x, z, out)
	# Wet ground along any water: sand, mud or shingle just above the waterline
	if out.water > -INF:
		var above := out.height - out.water
		if above < 1.6:
			out.color = out.color.lerp(shore, (1.0 - smoothstep(0.2, 1.6, above)) * 0.8)


# Each region's real box, land area and middle, from a coarse scan of the island (done once, the
# first time anything asks; the planners do)
func _scan_regions() -> void:
	if _scanned:
		return
	_scan_mutex.lock()
	if _scanned:
		_scan_mutex.unlock()
		return
	var cols := ceili(_bounds.size.x / SCAN_CELL)
	var rows := ceili(_bounds.size.y / SCAN_CELL)
	var lines: Array = []
	lines.resize(rows)
	var origin := _bounds.position
	var task := WorkerThreadPool.add_group_task(func(j: int) -> void:
		var line := PackedInt32Array()
		line.resize(cols)
		var z := origin.y + (float(j) + 0.5) * SCAN_CELL
		for i in cols:
			var x := origin.x + (float(i) + 0.5) * SCAN_CELL
			line[i] = -1 if _coast_sdf(x, z) > 0.0 else _owner_at(x, z)
		lines[j] = line, rows, -1, true, "region scan")
	WorkerThreadPool.wait_for_group_task_completion(task)
	_region_rects.clear()
	_region_area.resize(_count)
	_region_area.fill(0.0)
	var sum := PackedVector2Array()
	sum.resize(_count)
	var lo: Array[Vector2] = []
	var hi: Array[Vector2] = []
	for i in _count:
		lo.append(Vector2(INF, INF))
		hi.append(Vector2(-INF, -INF))
	var half := Vector2(SCAN_CELL, SCAN_CELL) * 0.5
	for j in rows:
		var line: PackedInt32Array = lines[j]
		for i in cols:
			var r := line[i]
			if r < 0:
				continue
			var p := origin + Vector2((float(i) + 0.5) * SCAN_CELL, (float(j) + 0.5) * SCAN_CELL)
			_region_area[r] += SCAN_CELL * SCAN_CELL
			sum[r] += p
			lo[r] = lo[r].min(p - half)
			hi[r] = hi[r].max(p + half)
	_region_center.resize(_count)
	for i in _count:
		if _region_area[i] <= 0.0:
			# a region the sea swallowed: a small box at its seed so nothing divides by zero
			var seed_at := Vector2(_site_x[_first_site(i)], _site_z[_first_site(i)])
			_region_rects.append(Rect2(seed_at, Vector2.ONE))
			_region_center[i] = seed_at
			continue
		_region_rects.append(Rect2(lo[i], hi[i] - lo[i]))
		var mid := sum[i] / (_region_area[i] / (SCAN_CELL * SCAN_CELL))
		# the middle of a crescent can lie outside it: then the region's seed nearest that middle
		if _owner_at(mid.x, mid.y) != i or _coast_sdf(mid.x, mid.y) > -200.0:
			var best := _first_site(i)
			for s in _site_x.size():
				if _site_region[s] == i and Vector2(_site_x[s], _site_z[s]).distance_to(mid) < Vector2(_site_x[best], _site_z[best]).distance_to(mid):
					best = s
			mid = Vector2(_site_x[best], _site_z[best])
		_region_center[i] = mid
	_scanned = true
	_scan_mutex.unlock()


func _owner_at(x: float, z: float) -> int:
	var w := _region_warped(x, z)
	return _owner(w)


func _first_site(region: int) -> int:
	for s in _site_x.size():
		if _site_region[s] == region:
			return s
	return 0
