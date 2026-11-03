class_name TerrainChunk
extends StaticBody3D
## One square piece of terrain: a smooth mesh plus a matching collision shape, its plants (Flora),
## its grass, rocks and herbs (GroundCover), and the surface of any river, stream or lake on it.
## Made by WorldManager. build_data() does the heavy math and is safe on a worker thread;
## apply() creates the actual mesh and collider and must run on the main thread.
##
## Smoothness: heights are sampled one vertex beyond each edge, so normals at the border of two
## chunks are computed from the same numbers on both sides. No visible seams.

var coord := Vector2i.ZERO
var _details := {}  # ground cover data, kept so the cover can be rebuilt when the player comes back
var _flora: Array = []
var _map: WorldMap
var _cover_on := false
## Shape owners added with the cover (logs and rocks you bump into), removed with it
var cover_owners := PackedInt32Array()

static var _water_mat: ShaderMaterial


## Heavy part. Returns {"coord", "arrays", "faces", "water", "flora", "details"}. Thread-safe.
## detail: ground cover amount (GameSettings "grass": 0 off .. 3 high)
static func build_data(map: WorldMap, chunk_coord: Vector2i, chunk_size: float, quads: int, detail: int = 2) -> Dictionary:
	var spacing := chunk_size / float(quads)
	var vps := quads + 1          # vertices per side
	var g := quads + 3            # sampled grid per side (one extra ring all around)
	var count := vps * vps
	var heights := PackedFloat32Array()
	heights.resize(g * g)
	var base_colors := PackedColorArray()
	base_colors.resize(count)
	var steep_colors := PackedColorArray()
	steep_colors.resize(count)
	var steep_start := PackedFloat32Array()
	steep_start.resize(count)
	var steep_full := PackedFloat32Array()
	steep_full.resize(count)
	var biomes := PackedInt32Array()
	biomes.resize(count)
	var biomes2 := PackedInt32Array()
	biomes2.resize(count)
	var bweight := PackedFloat32Array()
	bweight.resize(count)
	var water := PackedFloat32Array()
	water.resize(count)
	var near := PackedFloat32Array()
	near.resize(count)
	var free := PackedByteArray()
	free.resize(count)
	var roadd := PackedFloat32Array()
	roadd.resize(count)

	var origin_x := chunk_coord.x * chunk_size
	var origin_z := chunk_coord.y * chunk_size
	var s := WorldMap.Sample.new()
	for gj in g:
		var z := origin_z + float(gj - 1) * spacing
		for gi in g:
			var x := origin_x + float(gi - 1) * spacing
			map.sample(x, z, s)
			heights[gj * g + gi] = s.height
			if gi >= 1 and gi <= quads + 1 and gj >= 1 and gj <= quads + 1:
				var k := (gj - 1) * vps + (gi - 1)
				base_colors[k] = s.color
				steep_colors[k] = s.steep_color
				steep_start[k] = s.steep_start
				steep_full[k] = s.steep_full
				var inside := s.edge <= 0.05
				biomes[k] = s.biome_index if inside else -1
				biomes2[k] = s.biome2 if inside else -1
				bweight[k] = s.biome_w
				water[k] = s.water
				near[k] = maxf(s.near_water, 1.0 - smoothstep(0.3, 3.5, s.height - s.water)) if s.water > -INF else s.near_water
				free[k] = 0 if map.is_on_pad(x, z) else 1
				roadd[k] = map.roads.distance_to(x, z, 12.0) if map.roads != null else INF

	var verts := PackedVector3Array()
	verts.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	var colors := PackedColorArray()
	colors.resize(count)
	for j in vps:
		for i in vps:
			var gi := i + 1
			var gj := j + 1
			var k := j * vps + i
			var h := heights[gj * g + gi]
			var dhdx := (heights[gj * g + gi + 1] - heights[gj * g + gi - 1]) / (2.0 * spacing)
			var dhdz := (heights[(gj + 1) * g + gi] - heights[(gj - 1) * g + gi]) / (2.0 * spacing)
			var normal := Vector3(-dhdx, 1.0, -dhdz).normalized()
			verts[k] = Vector3(float(i) * spacing, h, float(j) * spacing)
			normals[k] = normal
			var slope := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
			var a := steep_start[k]
			var t := smoothstep(a, maxf(steep_full[k], a + 0.01), slope)
			colors[k] = base_colors[k].lerp(steep_colors[k], t)

	# Two triangles per square, clockwise seen from above (Godot's front face)
	var indices := PackedInt32Array()
	indices.resize(quads * quads * 6)
	var faces := PackedVector3Array()
	faces.resize(quads * quads * 6)
	var n := 0
	for j in quads:
		for i in quads:
			var a0 := j * vps + i
			var b0 := a0 + 1
			var c0 := a0 + vps
			var d0 := c0 + 1
			indices[n] = a0
			indices[n + 1] = b0
			indices[n + 2] = c0
			indices[n + 3] = b0
			indices[n + 4] = d0
			indices[n + 5] = c0
			faces[n] = verts[a0]
			faces[n + 1] = verts[b0]
			faces[n + 2] = verts[c0]
			faces[n + 3] = verts[b0]
			faces[n + 4] = verts[d0]
			faces[n + 5] = verts[c0]
			n += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var grid := {"verts": verts, "normals": normals, "colors": colors, "biomes": biomes, "biomes2": biomes2, "bweight": bweight,
		"water": water, "near": near, "free": free, "roadd": roadd}
	return {"coord": chunk_coord, "arrays": arrays, "faces": faces, "water": _water_arrays(map, verts, water, quads, spacing),
		"flora": Flora.scatter(map, chunk_coord, chunk_size, quads, grid),
		"details": GroundCover.scatter(map, chunk_coord, chunk_size, quads, grid, detail)}


# The surface of rivers, streams and lakes on this chunk (the sea is one big sheet of its own): a
# square of water wherever the water stands above the ground at any of its corners, at the water's
# own height at each corner, so a river's surface follows it downhill
static func _water_arrays(map: WorldMap, verts: PackedVector3Array, water: PackedFloat32Array, quads: int, spacing: float) -> Array:
	var vps := quads + 1
	var sea := map.settings.sea_level if map.settings.water_enabled else -INF
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in quads:
		for i in quads:
			var ks := [j * vps + i, j * vps + i + 1, (j + 1) * vps + i, (j + 1) * vps + i + 1]
			var any := false
			var top := -INF
			for k: int in ks:
				top = maxf(top, water[k])
				if water[k] > verts[k].y + 0.02 and water[k] > sea + 0.05:
					any = true
			if not any:
				continue
			var corner: Array[Vector3] = []
			for k: int in ks:
				var w := water[k] if water[k] > -INF else top
				corner.append(Vector3(verts[k].x, w, verts[k].z))
			for idx in [0, 1, 2, 1, 3, 2]:
				pts.append(corner[idx])
				uvs.append(Vector2(corner[idx].x, corner[idx].z))
	if pts.is_empty():
		return []
	var normals := PackedVector3Array()
	normals.resize(pts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


## The water of rivers and lakes (and the sea): see shaders/water.gdshader
static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://shaders/water.gdshader") as Shader
	return _water_mat


## Main-thread part: creates the mesh and the collision shape from build_data()'s result.
func apply(data: Dictionary, material: Material, map: WorldMap = null) -> void:
	_map = map
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	add_child(instance)

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(data["faces"])
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	add_child(collider)
	var water: Array = data.get("water", [])
	if not water.is_empty():
		var wm := ArrayMesh.new()
		wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water)
		var wmi := MeshInstance3D.new()
		wmi.name = "Water"
		wmi.mesh = wm
		wmi.material_override = water_material()
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wmi)
	_flora = data.get("flora", [])
	if map != null:
		Flora.apply(self, map, _flora)
	_details = data.get("details", {})
	GroundCover.apply(self, _details)


## Builds or frees this chunk's grass, flowers, rocks, shrubs and plants. WorldManager turns it on
## only for chunks near the player (GroundCover.COVER_REACH), so far chunks carry no cover nodes.
func set_cover(on: bool) -> void:
	if on == _cover_on:
		return
	_cover_on = on
	if on:
		GroundCover.apply_cover(self, _details)
		if _map != null:
			Flora.apply_cover(self, _map, _flora)
		return
	for c in get_children():
		if c.has_meta("cover"):
			remove_child(c)
			c.queue_free()
	for owner_id in cover_owners:
		remove_shape_owner(owner_id)
	cover_owners.clear()
