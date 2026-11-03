class_name Flora
extends RefCounted
## Scatters each biome's flora layers (FloraLayer) on a terrain chunk: trees, shrubs, plants,
## logs, rocks. scatter() runs on the chunk's worker thread and reads only the chunk's own vertex
## grid (height, slope, biome, water), so it is cheap and the same chunk always grows the same
## plants. apply() / apply_cover() turn the result into MultiMeshes on the main thread: trees on
## every chunk, the smaller things only on chunks near the player (like the grass).
##
## Near a border both lands' plants grow, each where its own land is the stronger at that spot
## (with a random dither), so forests thin out into meadow instead of stopping at a line.

const STRIDE := 12  # floats per transform

static var _defaults := {}  # biome -> Array[FloraLayer] made from Tree Style / Tree Density
static var _defaults_mutex := Mutex.new()
static var _shape_meshes := {}  # "shape|color" -> ArrayMesh


## The layers a biome grows: its Flora list, or one tree layer from the older Tree settings
static func layers_of(b: BiomeData) -> Array[FloraLayer]:
	if not b.flora.is_empty():
		return b.flora
	_defaults_mutex.lock()
	if not _defaults.has(b):
		var list: Array[FloraLayer] = []
		if b.tree_density > 0.0:
			var style := String(BiomeData.TreeStyle.keys()[b.tree_style]).to_lower()
			var shape: int = {BiomeData.TreeStyle.PINE: FloraLayer.Shape.PINE, BiomeData.TreeStyle.DEAD: FloraLayer.Shape.DEAD,
				BiomeData.TreeStyle.CACTUS: FloraLayer.Shape.CACTUS}.get(b.tree_style, FloraLayer.Shape.BROADLEAF)
			var height: float = {BiomeData.TreeStyle.PINE: 7.8, BiomeData.TreeStyle.DEAD: 4.6, BiomeData.TreeStyle.CACTUS: 2.8}.get(b.tree_style, 5.8)
			list.append(FloraLayer.make("trees", shape, FloraLayer.Size.TREE, b.tree_density, ["tree/" + style],
				{"color": b.tree_color, "height": height, "real_size": false, "scale_min": 0.75, "scale_max": 1.35, "clumping": 0.0,
				"max_slope": 34.0, "water": -1.0, "trunk_radius": 0.26}))
		_defaults[b] = list
	var out: Array[FloraLayer] = _defaults[b]
	_defaults_mutex.unlock()
	return out


## Thread-safe. `g` holds the chunk's vertex grid: verts (chunk-local), normals, biomes, biomes2,
## bweight (how much biomes wins over biomes2), water (water level or -INF), near (0..1 how close the
## water is), free (1 = nothing built here: no road, town or camp).
static func scatter(map: WorldMap, coord: Vector2i, chunk_size: float, quads: int, g: Dictionary) -> Array:
	var out: Array = []
	if map.placements.is_empty():
		return out
	var verts: PackedVector3Array = g["verts"]
	var normals: PackedVector3Array = g["normals"]
	var biomes: PackedInt32Array = g["biomes"]
	var biomes2: PackedInt32Array = g["biomes2"]
	var bweight: PackedFloat32Array = g["bweight"]
	var water: PackedFloat32Array = g["water"]
	var near: PackedFloat32Array = g["near"]
	var free: PackedByteArray = g["free"]
	var roadd: PackedFloat32Array = g["roadd"]
	var vps := quads + 1
	var spacing := chunk_size / float(quads)
	var ox := coord.x * chunk_size
	var oz := coord.y * chunk_size
	var area_ha := chunk_size * chunk_size / 10000.0
	var sea := map.settings.sea_level
	# every biome on this chunk
	var present := {}
	for k in biomes.size():
		if biomes[k] >= 0:
			present[biomes[k]] = true
		if biomes2[k] >= 0:
			present[biomes2[k]] = true
	for bi: int in present:
		var biome := map.placements[bi].biome
		var layers := layers_of(biome)
		for li in layers.size():
			var layer := layers[li]
			if layer == null or layer.density <= 0.0:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = ("%d|flora|%s|%d|%d,%d" % [map.world_seed, biome.get_key(), li, coord.x, coord.y]).hash()
			var clump: FastNoiseLite = null
			if layer.clumping > 0.0 and layer.clump_scale > 0.0:
				clump = FastNoiseLite.new()
				clump.seed = ("%d|clump|%s|%d" % [map.world_seed, biome.get_key(), li]).hash()
				clump.frequency = 1.0 / layer.clump_scale
				clump.fractal_octaves = 2
			var expect := layer.density * area_ha
			var tries := int(expect) + (1 if rng.randf() < expect - floorf(expect) else 0)
			var xf := PackedFloat32Array()
			var picks := PackedInt32Array()
			var scales := PackedFloat32Array()
			var n := 0
			var min_ny := cos(deg_to_rad(layer.max_slope))
			var max_ny := cos(deg_to_rad(layer.min_slope)) + 0.0001
			var tree := layer.size == FloraLayer.Size.TREE
			for t in tries:
				var lx := rng.randf() * chunk_size
				var lz := rng.randf() * chunk_size
				var roll := rng.randf()
				var pick := rng.randi()
				var k := _nearest(lx, lz, spacing, vps)
				# which land this spot belongs to (dithered near a border)
				var own := biomes[k] if roll < bweight[k] or biomes2[k] < 0 else biomes2[k]
				if own != bi:
					continue
				if clump != null:
					var c := (clump.get_noise_2d(ox + lx, oz + lz) + 1.0) * 0.5
					if rng.randf() > lerpf(1.0, smoothstep(0.42, 0.62, c), layer.clumping):
						continue
				var nrm := normals[k]
				if nrm.y < min_ny or nrm.y > max_ny:
					continue
				var y := _height(verts, lx, lz, spacing, vps)
				var wl := water[k]
				var wet := wl > y + 0.05
				if layer.in_water:
					if not wet or wl - y > 1.4:
						continue
				elif layer.water_ok:
					if wet and wl - y > 0.8:
						continue
				elif wet or (wl > -INF and y < wl + 0.15):
					continue
				if y - sea < layer.min_height or y - sea > layer.max_height:
					continue
				if layer.water != 0.0:
					var nw := near[k]
					if layer.water > 0.0 and rng.randf() > nw * layer.water + (1.0 - layer.water):
						continue
					if layer.water > 0.0 and nw < 0.05:
						continue
					if layer.water < 0.0 and rng.randf() < nw * -layer.water:
						continue
				if free[k] == 0 or roadd[k] < (3.5 if tree else 1.6):
					continue
				var sc := rng.randf_range(layer.scale_min, layer.scale_max)
				var yaw := rng.randf() * TAU
				var basis := Basis(Vector3.UP, yaw)
				if layer.follow_ground and nrm.y < 0.999:
					var axis := Vector3.UP.cross(nrm).normalized()
					basis = Basis(axis, acos(clampf(nrm.y, -1.0, 1.0))) * basis
				if layer.lean > 0.0:
					var la := rng.randf() * TAU
					basis = Basis(Vector3(cos(la), 0.0, sin(la)), deg_to_rad(rng.randf_range(0.0, layer.lean))) * basis
				basis = basis.scaled(Vector3.ONE * sc)
				var pos := Vector3(lx, wl + 0.02 if layer.floats and wet else y - layer.sink * sc, lz)
				xf.resize((n + 1) * STRIDE)
				_write(xf, n, basis, pos)
				picks.append(pick)
				scales.append(sc)
				n += 1
			if n > 0:
				out.append({"biome": bi, "layer": li, "xf": xf, "pick": picks, "scale": scales, "n": n})
	return out


## Main thread: the trees (seen from far, solid trunks)
static func apply(chunk: TerrainChunk, map: WorldMap, groups: Array) -> void:
	for gr: Dictionary in groups:
		var layer := _layer(map, gr)
		if layer != null and layer.size == FloraLayer.Size.TREE:
			_build(chunk, layer, gr, false)


## Main thread: shrubs, plants, logs and rocks (only near the player; tagged "cover")
static func apply_cover(chunk: TerrainChunk, map: WorldMap, groups: Array) -> void:
	for gr: Dictionary in groups:
		var layer := _layer(map, gr)
		if layer != null and layer.size != FloraLayer.Size.TREE:
			_build(chunk, layer, gr, true)


static func _layer(map: WorldMap, gr: Dictionary) -> FloraLayer:
	var bi: int = gr["biome"]
	if bi < 0 or bi >= map.placements.size():
		return null
	var layers := layers_of(map.placements[bi].biome)
	var li: int = gr["layer"]
	return layers[li] if li < layers.size() else null


static func _build(chunk: TerrainChunk, layer: FloraLayer, gr: Dictionary, cover: bool) -> void:
	var xf: PackedFloat32Array = gr["xf"]
	var picks: PackedInt32Array = gr["pick"]
	var scales: PackedFloat32Array = gr["scale"]
	var n: int = gr["n"]
	var models := layer.usable_models()
	var meshes: Array[Mesh] = []
	if models.is_empty():
		meshes.append(shape_mesh(layer))
	else:
		for key in models:
			var m := planted_mesh(key, 0.0 if layer.real_size else layer.height)
			meshes.append(m if m != null else shape_mesh(layer))
	var count := meshes.size()
	for mi in count:
		var buf := PackedFloat32Array()
		var c := 0
		for k in n:
			if picks[k] % count != mi:
				continue
			buf.resize((c + 1) * STRIDE)
			for q in STRIDE:
				buf[c * STRIDE + q] = xf[k * STRIDE + q]
			c += 1
		if c == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[mi]
		mm.instance_count = c
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flora_%s_%d" % [layer.name if layer.name != "" else "layer", mi]
		mmi.multimesh = mm
		var reach := layer.get_draw_distance()
		mmi.visibility_range_end = reach
		mmi.visibility_range_end_margin = reach * 0.12
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if layer.size == FloraLayer.Size.PLANT:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cover:
			mmi.set_meta("cover", true)
		chunk.add_child(mmi)
		if layer.solid:
			_collide(chunk, layer, meshes[mi], buf, c, cover)


# Trees: a trunk you bump into. Logs and rocks: a box round the model.
static func _collide(chunk: TerrainChunk, layer: FloraLayer, mesh: Mesh, buf: PackedFloat32Array, count: int, cover: bool) -> void:
	if layer.size == FloraLayer.Size.PLANT:
		return
	var aabb := mesh.get_aabb()
	for k in count:
		var at := k * STRIDE
		var basis := Basis(Vector3(buf[at], buf[at + 4], buf[at + 8]), Vector3(buf[at + 1], buf[at + 5], buf[at + 9]), Vector3(buf[at + 2], buf[at + 6], buf[at + 10]))
		var pos := Vector3(buf[at + 3], buf[at + 7], buf[at + 11])
		var sc := basis.get_scale().x
		var shape: Shape3D
		var t: Transform3D
		if layer.size == FloraLayer.Size.TREE:
			var cyl := CylinderShape3D.new()
			cyl.radius = layer.trunk_radius * sc
			cyl.height = minf(aabb.size.y * sc, 5.0)
			shape = cyl
			t = Transform3D(Basis.IDENTITY, pos + Vector3.UP * cyl.height * 0.5)
		else:
			if aabb.size.y * sc < 0.5 and maxf(aabb.size.x, aabb.size.z) * sc < 1.0:
				continue  # too small to stop anyone
			var box := BoxShape3D.new()
			box.size = aabb.size * sc * 0.85
			shape = box
			t = Transform3D(basis.orthonormalized(), pos + basis * aabb.get_center())
		var owner_id := chunk.create_shape_owner(chunk)
		chunk.shape_owner_add_shape(owner_id, shape)
		chunk.shape_owner_set_transform(owner_id, t)
		if cover:
			chunk.cover_owners.append(owner_id)


static var _planted := {}  # "key|height" -> ArrayMesh


## A model as one mesh standing on its own roots: its foot (the middle of its lowest part) at the
## origin. ModelLibrary centres a model on its box, which for a tree that grows out at an angle (a
## cliffside tree, a leaning trunk) puts its roots off to one side, hanging in the air on a slope.
static func planted_mesh(key: String, height: float) -> ArrayMesh:
	var ck := "%s|%.2f" % [key, height]
	if _planted.has(ck):
		return _planted[ck]
	var src := ModelLibrary.merged_mesh(key, height, 0.0)
	if src == null:
		return null
	var foot := foot_of(src)
	var out := src
	if Vector2(foot.x, foot.z).length() > 0.05:
		out = ArrayMesh.new()
		for si in src.get_surface_count():
			var arrays := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] -= Vector3(foot.x, 0.0, foot.z)
			arrays[Mesh.ARRAY_VERTEX] = verts
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(si, src.surface_get_material(si))
	_planted[ck] = out
	return out


## Where a mesh meets the ground: the middle of its vertices in the lowest few percent of its height
static func foot_of(mesh: Mesh) -> Vector3:
	var aabb := mesh.get_aabb()
	var cut := aabb.position.y + maxf(aabb.size.y * 0.04, 0.05)
	var sum := Vector3.ZERO
	var n := 0
	for si in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y <= cut:
				sum += v
				n += 1
	return sum / float(n) if n > 0 else aabb.get_center()


## The plain look of a layer with no model: a tree, shrub, plant or rock made of simple shapes,
## one unit tall, scaled to the layer's height
static func shape_mesh(layer: FloraLayer) -> ArrayMesh:
	var key := "%d|%s|%.2f" % [layer.shape, layer.color.to_html(), layer.height]
	if _shape_meshes.has(key):
		return _shape_meshes[key]
	var h := layer.height
	var col := layer.color
	var bark := Color(0.33, 0.25, 0.17)
	var parts: Array = []  # [PrimitiveMesh, Transform3D, Color]
	match layer.shape:
		FloraLayer.Shape.PINE:
			parts.append([_cyl(0.18, 0.12, h * 0.35), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.175, 0)), bark])
			for i in 3:
				var cone := _cyl(h * (0.24 - i * 0.06), 0.0, h * 0.42)
				parts.append([cone, Transform3D(Basis.IDENTITY, Vector3(0, h * (0.42 + i * 0.18), 0)), col.darkened(0.05 * i)])
		FloraLayer.Shape.BIRCH:
			parts.append([_cyl(0.13, 0.09, h * 0.7), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.35, 0)), Color(0.85, 0.84, 0.78)])
			parts.append([_ball(h * 0.22, h * 0.45), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.72, 0)), col])
		FloraLayer.Shape.PALM:
			parts.append([_cyl(0.16, 0.11, h * 0.85), Transform3D(Basis(Vector3.FORWARD, 0.12), Vector3(0.05 * h, h * 0.42, 0)), bark.lightened(0.15)])
			for i in 6:
				var a := float(i) / 6.0 * TAU
				var leaf := BoxMesh.new()
				leaf.size = Vector3(h * 0.38, 0.04, 0.35)
				parts.append([leaf, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, -0.35), Vector3(cos(a) * h * 0.16 + 0.1 * h, h * 0.84, -sin(a) * h * 0.16)), col])
		FloraLayer.Shape.DEAD:
			parts.append([_cyl(0.17, 0.08, h), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), bark.darkened(0.2)])
			for i in 4:
				var a := float(i) * 1.7
				var br := _cyl(0.06, 0.02, h * 0.35)
				parts.append([br, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.9), Vector3(cos(a) * h * 0.1, h * (0.55 + i * 0.1), sin(a) * h * 0.1)), bark.darkened(0.2)])
		FloraLayer.Shape.CACTUS:
			parts.append([_cyl(0.22, 0.2, h), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), col])
			parts.append([_cyl(0.13, 0.12, h * 0.35), Transform3D(Basis.IDENTITY, Vector3(0.38, h * 0.55, 0)), col])
			parts.append([_cyl(0.12, 0.12, h * 0.3), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.2, h * 0.38, 0)), col])
		FloraLayer.Shape.BUSH:
			parts.append([_ball(h * 0.6, h), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), Vector3(0, h * 0.4, 0)), col])
			parts.append([_ball(h * 0.4, h * 0.7), Transform3D(Basis.IDENTITY, Vector3(h * 0.35, h * 0.3, h * 0.2)), col.darkened(0.1)])
		FloraLayer.Shape.FERN:
			for i in 7:
				var a := float(i) / 7.0 * TAU
				var frond := BoxMesh.new()
				frond.size = Vector3(0.18, 0.02, h * 0.9)
				parts.append([frond, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.55), Vector3(sin(a) * h * 0.3, h * 0.3, cos(a) * h * 0.3)), col])
		FloraLayer.Shape.REEDS:
			for i in 9:
				var a := float(i) * 2.4
				var r := 0.08 + float(i % 3) * 0.07
				parts.append([_cyl(0.02, 0.012, h * (0.7 + float(i % 4) * 0.1)), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.08), Vector3(cos(a) * r, h * 0.4, sin(a) * r)), col])
			parts.append([_cyl(0.04, 0.04, h * 0.14), Transform3D(Basis.IDENTITY, Vector3(0.05, h * 0.82, 0)), Color(0.35, 0.22, 0.12)])
		FloraLayer.Shape.MUSHROOM:
			parts.append([_cyl(0.06, 0.05, h * 0.6), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.3, 0)), Color(0.85, 0.8, 0.7)])
			parts.append([_ball(h * 0.32, h * 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.62, 0)), col])
		FloraLayer.Shape.LOG:
			parts.append([_cyl(0.28, 0.25, h), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.24, 0)), bark])
		FloraLayer.Shape.STUMP:
			parts.append([_cyl(0.38, 0.3, h), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), bark])
		FloraLayer.Shape.ROCK:
			var rock := NatureMeshes.rock_mesh(0)
			var out_rock := ArrayMesh.new()
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(rock, 0, Transform3D(Basis.from_scale(Vector3.ONE * h), Vector3.ZERO))
			st.commit(out_rock)
			out_rock.surface_set_material(0, POIBuilder.get_material(col))
			_shape_meshes[key] = out_rock
			return out_rock
		FloraLayer.Shape.FLOWERS:
			for i in 6:
				var a := float(i) * 2.1
				parts.append([_cyl(0.012, 0.01, h * 0.8), Transform3D(Basis.IDENTITY, Vector3(cos(a) * 0.12, h * 0.4, sin(a) * 0.12)), Color(0.25, 0.42, 0.18)])
				parts.append([_ball(0.05, 0.07), Transform3D(Basis.IDENTITY, Vector3(cos(a) * 0.12, h * 0.82, sin(a) * 0.12)), col])
		_:
			parts.append([_cyl(0.22, 0.16, h * 0.4), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.2, 0)), bark])
			parts.append([_ball(h * 0.36, h * 0.62), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.62, 0)), col])
	# one surface per colour
	var by_color := {}
	for p: Array in parts:
		var c: Color = p[2]
		var hk := c.to_html()
		if not by_color.has(hk):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_color[hk] = [st, c]
		(by_color[hk][0] as SurfaceTool).append_from(p[0], 0, p[1])
	var mesh := ArrayMesh.new()
	for hk: String in by_color:
		var st: SurfaceTool = by_color[hk][0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, POIBuilder.get_material(by_color[hk][1]))
	_shape_meshes[key] = mesh
	return mesh


static func _cyl(bottom: float, top: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = 7
	c.rings = 1
	return c


static func _ball(radius: float, height: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height
	s.radial_segments = 8
	s.rings = 5
	return s


static func _nearest(lx: float, lz: float, spacing: float, vps: int) -> int:
	var i := clampi(roundi(lx / spacing), 0, vps - 1)
	var j := clampi(roundi(lz / spacing), 0, vps - 1)
	return j * vps + i


static func _height(verts: PackedVector3Array, lx: float, lz: float, spacing: float, vps: int) -> float:
	return GroundCover._height(verts, lx, lz, spacing, vps)


static func _write(buf: PackedFloat32Array, n: int, b: Basis, o: Vector3) -> void:
	var at := n * STRIDE
	buf[at] = b.x.x
	buf[at + 1] = b.y.x
	buf[at + 2] = b.z.x
	buf[at + 3] = o.x
	buf[at + 4] = b.x.y
	buf[at + 5] = b.y.y
	buf[at + 6] = b.z.y
	buf[at + 7] = o.y
	buf[at + 8] = b.x.z
	buf[at + 9] = b.y.z
	buf[at + 10] = b.z.z
	buf[at + 11] = o.z
