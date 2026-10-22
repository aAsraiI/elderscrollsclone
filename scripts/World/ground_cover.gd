class_name GroundCover
extends RefCounted
## Grass, flowers, rocks, boulders and bushes on a terrain chunk, plus the herbs you can pick and
## the ore veins you can mine. scatter() runs on the chunk's worker thread (pure math, same result
## for the same chunk every time); apply() turns it into a few MultiMeshes on the main thread.
##
## Grass is cut into 4 blocks per chunk that fade out past GRASS_RANGE, so only the grass around
## you is drawn. Nothing grows on roads, town squares, under water or on cliffs. How much grows
## comes from each biome (BiomeData.get_grass_density / get_rock_density) and the Grass setting.

const GRASS_RANGE := 55.0
const FLOWER_RANGE := 40.0
const BUSH_RANGE := 160.0
const ROCK_RANGE := 260.0
## Grass clumps per 32 x 32 m block at full density, for the Grass setting (off, low, medium, high)
const GRASS_PER_BLOCK: Array[int] = [0, 260, 620, 1150]
const FLOWER_COLORS := {
	"temperate": [Color(1.0, 0.85, 0.2), Color(0.95, 0.95, 0.95), Color(0.65, 0.4, 0.9), Color(0.9, 0.25, 0.25), Color(0.4, 0.55, 1.0)],
	"wet": [Color(0.95, 0.95, 0.95), Color(0.9, 0.6, 0.8), Color(1.0, 0.9, 0.3)],
	"cold": [Color(0.6, 0.75, 1.0), Color(0.95, 0.95, 1.0)],
	"arid": [Color(1.0, 0.5, 0.2)],
}
const STRIDE := 16  # floats per MultiMesh instance: 12 transform + 4 color


## Thread-safe. verts are chunk-local, colors / biomes per vertex.
static func scatter(map: WorldMap, coord: Vector2i, chunk_size: float, quads: int, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray, biomes: PackedInt32Array, detail: int) -> Dictionary:
	var out := {}
	if map.placements.is_empty():
		return out
	var vps := quads + 1
	var spacing := chunk_size / float(quads)
	var ox := coord.x * chunk_size
	var oz := coord.y * chunk_size
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|cover|%d,%d" % [map.world_seed, coord.x, coord.y]).hash()

	# Where things may grow: per vertex 0 = nothing, 1 = flat ground, 2 = rocky slope
	var ok := PackedByteArray()
	ok.resize(vps * vps)
	var steep_count := 0
	for k in vps * vps:
		var p := verts[k]
		var wx := ox + p.x
		var wz := oz + p.z
		if biomes[k] < 0 or map.is_under_water(p.y - 0.15) or map.is_on_pad(wx, wz):
			continue
		if map.roads != null and map.roads.distance_to(wx, wz, 3.0) < 1.2:
			continue
		if normals[k].y < 0.8:
			ok[k] = 2
			steep_count += 1
		else:
			ok[k] = 1

	var climates := {}
	var biome_list := {}
	for k in vps * vps:
		var bi := biomes[k]
		if bi >= 0 and not biome_list.has(bi):
			biome_list[bi] = map.placements[bi].biome

	# ---- grass (and flowers among it), in 4 blocks
	var half := chunk_size * 0.5
	var per_block := GRASS_PER_BLOCK[clampi(detail, 0, 3)]
	var grass_blocks: Array = []
	var flowers := PackedFloat32Array()
	var flower_n := 0
	for by in 2:
		for bx in 2:
			var buf := PackedFloat32Array()
			buf.resize(per_block * STRIDE)
			var cx := (float(bx) + 0.5) * half
			var cz := (float(by) + 0.5) * half
			var n := 0
			for i in per_block:
				var lx := (float(bx) + rng.randf()) * half
				var lz := (float(by) + rng.randf()) * half
				var k := _nearest(lx, lz, spacing, vps)
				if ok[k] != 1:
					continue
				var biome: BiomeData = biome_list.get(biomes[k])
				if biome == null or rng.randf() > biome.get_grass_density():
					continue
				var y := _height(verts, lx, lz, spacing, vps)
				var c := colors[k].lightened(0.08).lerp(Color(0.55, 0.7, 0.3), 0.15)
				c = c * rng.randf_range(0.85, 1.15)
				c.a = 1.0
				var sc := rng.randf_range(0.75, 1.3)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.35), sc))
				_write(buf, n, basis, Vector3(lx - cx, y - 0.02, lz - cz), c)
				n += 1
				# A flower here and there
				var clim := _climate(climates, biome)
				if rng.randf() < 0.035 and FLOWER_COLORS.has(clim):
					var pal: Array = FLOWER_COLORS[clim]
					if flowers.size() < (flower_n + 1) * STRIDE:
						flowers.resize((flower_n + 16) * STRIDE)
					var fb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3))
					_write(flowers, flower_n, fb, Vector3(lx + 0.25, y - 0.02, lz - 0.2), pal[rng.randi() % pal.size()])
					flower_n += 1
			buf.resize(n * STRIDE)
			grass_blocks.append({"buf": buf, "n": n, "center": Vector3((float(bx) + 0.5) * half, 0.0, (float(by) + 0.5) * half)})
	flowers.resize(flower_n * STRIDE)
	out["grass"] = grass_blocks
	out["flowers"] = {"buf": flowers, "n": flower_n}

	# ---- rocks, boulders and bushes
	var rock_bufs: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var rock_n: Array[int] = [0, 0, 0]
	var boulders: Array = []
	var bush_buf := PackedFloat32Array()
	var bush_n := 0
	var tries := 14 + steep_count / 12
	for i in tries:
		var lx := rng.randf() * chunk_size
		var lz := rng.randf() * chunk_size
		var k := _nearest(lx, lz, spacing, vps)
		if ok[k] == 0:
			continue
		var biome: BiomeData = biome_list.get(biomes[k])
		if biome == null:
			continue
		var dens := biome.get_rock_density() * (2.5 if ok[k] == 2 else 1.0)
		if rng.randf() > dens * 0.35:
			continue
		var y := _height(verts, lx, lz, spacing, vps)
		var big := rng.randf() < 0.1
		var sc := rng.randf_range(1.4, 3.2) if big else rng.randf_range(0.25, 0.9)
		var v := rng.randi() % 3
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		basis = basis.scaled(Vector3(sc * rng.randf_range(0.8, 1.3), sc * rng.randf_range(0.6, 1.0), sc * rng.randf_range(0.8, 1.3)))
		var base_c := colors[k].lerp(Color(0.45, 0.43, 0.4), 0.65) * rng.randf_range(0.8, 1.1)
		base_c.a = 1.0
		var buf: PackedFloat32Array = rock_bufs[v]
		buf.resize((rock_n[v] + 1) * STRIDE)
		_write(buf, rock_n[v], basis, Vector3(lx, y - sc * 0.15, lz), base_c)
		rock_bufs[v] = buf
		rock_n[v] += 1
		if big:
			boulders.append(Vector4(lx, y + sc * 0.15, lz, sc * 0.42))
	var bush_tries := 10
	for i in bush_tries:
		var lx := rng.randf() * chunk_size
		var lz := rng.randf() * chunk_size
		var k := _nearest(lx, lz, spacing, vps)
		if ok[k] != 1:
			continue
		var biome: BiomeData = biome_list.get(biomes[k])
		if biome == null or rng.randf() > biome.get_grass_density() * 0.45:
			continue
		var y := _height(verts, lx, lz, spacing, vps)
		var sc := rng.randf_range(0.7, 1.5)
		var c := colors[k].darkened(0.25).lerp(Color(0.2, 0.35, 0.12), 0.4) * rng.randf_range(0.85, 1.15)
		if _climate(climates, biome) == "arid":
			c = Color(0.5, 0.42, 0.25)
		c.a = 1.0
		bush_buf.resize((bush_n + 1) * STRIDE)
		_write(bush_buf, bush_n, Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * 0.8, sc)), Vector3(lx, y - 0.1, lz), c)
		bush_n += 1
	out["rocks"] = {"bufs": rock_bufs, "n": rock_n}
	out["boulders"] = boulders
	out["bushes"] = {"buf": bush_buf, "n": bush_n}

	# ---- things to gather: herbs on flat ground, ore on rocky slopes
	var herbs: Array = []
	var herb_tries := 3
	for i in herb_tries:
		var lx := rng.randf() * chunk_size
		var lz := rng.randf() * chunk_size
		var k := _nearest(lx, lz, spacing, vps)
		if ok[k] != 1 or rng.randf() > 0.45:
			continue
		var biome: BiomeData = biome_list.get(biomes[k])
		if biome == null:
			continue
		herbs.append({"pos": Vector3(lx, _height(verts, lx, lz, spacing, vps), lz), "climate": _climate(climates, biome), "pick": rng.randi()})
	out["herbs"] = herbs
	var ores: Array = []
	if steep_count > 6 and rng.randf() < 0.4:
		for i in 12:
			var lx := rng.randf() * chunk_size
			var lz := rng.randf() * chunk_size
			var k := _nearest(lx, lz, spacing, vps)
			if ok[k] == 2:
				ores.append({"pos": Vector3(lx, _height(verts, lx, lz, spacing, vps), lz), "pick": rng.randi()})
				break
	out["ores"] = ores
	return out


static func _climate(cache: Dictionary, biome: BiomeData) -> String:
	var key := biome.get_instance_id()
	if not cache.has(key):
		cache[key] = biome.get_climate()
	return cache[key]


static func _nearest(lx: float, lz: float, spacing: float, vps: int) -> int:
	var i := clampi(roundi(lx / spacing), 0, vps - 1)
	var j := clampi(roundi(lz / spacing), 0, vps - 1)
	return j * vps + i


# Bilinear height between the four vertices around (lx, lz)
static func _height(verts: PackedVector3Array, lx: float, lz: float, spacing: float, vps: int) -> float:
	var fx := clampf(lx / spacing, 0.0, float(vps - 1) - 0.001)
	var fz := clampf(lz / spacing, 0.0, float(vps - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var h00 := verts[j * vps + i].y
	var h10 := verts[j * vps + i + 1].y
	var h01 := verts[(j + 1) * vps + i].y
	var h11 := verts[(j + 1) * vps + i + 1].y
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


static func _write(buf: PackedFloat32Array, n: int, b: Basis, o: Vector3, c: Color) -> void:
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
	buf[at + 12] = c.r
	buf[at + 13] = c.g
	buf[at + 14] = c.b
	buf[at + 15] = c.a


# ---------------------------------------------------------------- main thread

static func apply(chunk: TerrainChunk, d: Dictionary) -> void:
	if d.is_empty():
		return
	for block in d.get("grass", []):
		if int(block["n"]) > 0:
			var g := _mmi(chunk, "Grass", NatureMeshes.grass_mesh(), NatureMeshes.grass_material(), block["buf"], block["n"], GRASS_RANGE, false)
			g.position = block["center"]
	var fl: Dictionary = d.get("flowers", {})
	if int(fl.get("n", 0)) > 0:
		_mmi(chunk, "Flowers", NatureMeshes.flower_mesh(), NatureMeshes.flower_material(), fl["buf"], fl["n"], FLOWER_RANGE, false)
	var rocks: Dictionary = d.get("rocks", {})
	if not rocks.is_empty():
		for v in 3:
			if int(rocks["n"][v]) > 0:
				_mmi(chunk, "Rocks%d" % v, NatureMeshes.rock_mesh(v), NatureMeshes.rock_material(), rocks["bufs"][v], rocks["n"][v], ROCK_RANGE, true)
	var bushes: Dictionary = d.get("bushes", {})
	if int(bushes.get("n", 0)) > 0:
		_mmi(chunk, "Bushes", NatureMeshes.bush_mesh(), NatureMeshes.bush_material(), bushes["buf"], bushes["n"], BUSH_RANGE, false)
	# Boulders are solid (shapes straight on the chunk's own body, like tree trunks)
	for bl in d.get("boulders", []):
		var b4: Vector4 = bl
		var sphere := SphereShape3D.new()
		sphere.radius = b4.w
		var owner_id := chunk.create_shape_owner(chunk)
		chunk.shape_owner_add_shape(owner_id, sphere)
		chunk.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, Vector3(b4.x, b4.y, b4.z)))
	var origin := chunk.position
	for h in d.get("herbs", []):
		HarvestNode.make_herb(chunk, h["pos"], origin + h["pos"], String(h["climate"]), int(h["pick"]))
	for o in d.get("ores", []):
		HarvestNode.make_ore(chunk, o["pos"], origin + o["pos"], int(o["pick"]))


static func _mmi(chunk: Node3D, n: String, mesh: Mesh, mat: Material, buf: PackedFloat32Array, count: int, range_end: float, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = range_end * 0.15
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	chunk.add_child(mmi)
	return mmi
