class_name TerrainChunk
extends StaticBody3D
## One square piece of terrain: a smooth mesh plus a matching collision shape.
## Made by WorldManager. build_data() does the heavy math and is safe on a worker thread;
## apply() creates the actual mesh and collider and must run on the main thread.
##
## Smoothness: heights are sampled one vertex beyond each edge, so normals at the border of two
## chunks are computed from the same numbers on both sides. No visible seams.

var coord := Vector2i.ZERO


## Heavy part. Returns {"coord", "arrays", "faces"}. Thread-safe.
## detail: ground cover amount (GameSettings "grass": 0 off .. 3 high)
static func build_data(map: WorldMap, chunk_coord: Vector2i, chunk_size: float, quads: int, detail: int = 2) -> Dictionary:
	var spacing := chunk_size / float(quads)
	var vps := quads + 1          # vertices per side
	var g := quads + 3            # sampled grid per side (one extra ring all around)
	var heights := PackedFloat32Array()
	heights.resize(g * g)
	var base_colors := PackedColorArray()
	base_colors.resize(vps * vps)
	var steep_colors := PackedColorArray()
	steep_colors.resize(vps * vps)
	var steep_start := PackedFloat32Array()
	steep_start.resize(vps * vps)
	var steep_full := PackedFloat32Array()
	steep_full.resize(vps * vps)
	var biomes := PackedInt32Array()
	biomes.resize(vps * vps)

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
				biomes[k] = s.biome_index if s.edge <= 0.05 else -1

	var verts := PackedVector3Array()
	verts.resize(vps * vps)
	var normals := PackedVector3Array()
	normals.resize(vps * vps)
	var colors := PackedColorArray()
	colors.resize(vps * vps)
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
	return {"coord": chunk_coord, "arrays": arrays, "faces": faces, "trees": _scatter_trees(map, chunk_coord, chunk_size),
		"details": GroundCover.scatter(map, chunk_coord, chunk_size, quads, verts, normals, colors, biomes, detail)}


## Where trees grow in this chunk: style -> {"pos": PackedVector3Array, "scale": PackedFloat32Array,
## "color": Color}. Never on roads, on leveled ground (towns, camps), in water or on steep slopes.
## Thread-safe; the same chunk always gets the same trees.
static func _scatter_trees(map: WorldMap, chunk_coord: Vector2i, chunk_size: float) -> Dictionary:
	var out := {}
	if map.placements.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|trees|%d,%d" % [map.world_seed, chunk_coord.x, chunk_coord.y]).hash()
	var s := WorldMap.Sample.new()
	var origin := Vector2(chunk_coord.x * chunk_size, chunk_coord.y * chunk_size)
	# Try a fixed grid of jittered spots; each biome's density decides how many grow
	var step := 5.0
	var cells := int(chunk_size / step)
	for j in cells:
		for i in cells:
			var x := origin.x + (float(i) + rng.randf()) * step
			var z := origin.y + (float(j) + rng.randf()) * step
			var roll := rng.randf()
			map.sample(x, z, s)
			if s.biome_index < 0 or s.edge > 0.05:
				continue
			var biome := map.placements[s.biome_index].biome
			var chance := biome.tree_density * step * step / 10000.0
			if roll >= chance:
				continue
			if map.is_under_water(s.height - 0.3) or map.is_on_pad(x, z):
				continue
			if map.roads != null and map.roads.distance_to(x, z, 4.0) < 4.0:
				continue
			var hx := map.get_height(x + 1.5, z)
			var hz := map.get_height(x, z + 1.5)
			if absf(hx - s.height) > 1.0 or absf(hz - s.height) > 1.0:
				continue  # too steep (over ~34 degrees)
			var key := int(biome.tree_style)
			if not out.has(key):
				out[key] = {"pos": PackedVector3Array(), "scale": PackedFloat32Array(), "color": biome.tree_color}
			out[key]["pos"].append(Vector3(x - origin.x, s.height, z - origin.y))
			out[key]["scale"].append(rng.randf_range(0.75, 1.35))
	return out


## Main-thread part: creates the mesh and the collision shape from build_data()'s result.
func apply(data: Dictionary, material: Material) -> void:
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
	_add_trees(data.get("trees", {}))
	GroundCover.apply(self, data.get("details", {}))


# ---------------------------------------------------------------- trees

static var _tree_meshes := {}  # style -> [trunk Mesh, crown Mesh, trunk height, trunk radius]
static var _trunk_shapes := {}  # style -> CylinderShape3D


static func _tree_parts(style: int) -> Array:
	if _tree_meshes.has(style):
		return _tree_meshes[style]
	var trunk := CylinderMesh.new()
	var crown: PrimitiveMesh
	var trunk_h := 2.2
	var radius := 0.22
	match style:
		BiomeData.TreeStyle.PINE:
			trunk_h = 2.0
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.8
			cone.height = 6.5
			crown = cone
		BiomeData.TreeStyle.DEAD:
			trunk_h = 4.5
			radius = 0.18
			var branches := BoxMesh.new()
			branches.size = Vector3(2.4, 0.18, 0.18)
			crown = branches
		BiomeData.TreeStyle.CACTUS:
			trunk_h = 2.6
			radius = 0.3
			var arms := BoxMesh.new()
			arms.size = Vector3(1.6, 0.35, 0.35)
			crown = arms
		_:
			var ball := SphereMesh.new()
			ball.radius = 2.2
			ball.height = 3.8
			crown = ball
	trunk.top_radius = radius * 0.8
	trunk.bottom_radius = radius
	trunk.height = trunk_h
	_tree_meshes[style] = [trunk, crown, trunk_h, radius]
	return _tree_meshes[style]


# Each kind of tree is drawn as two batches (trunks, crowns); trunks block you, crowns don't
func _add_trees(trees: Dictionary) -> void:
	for style: int in trees:
		var group: Dictionary = trees[style]
		var pos: PackedVector3Array = group["pos"]
		var scales: PackedFloat32Array = group["scale"]
		if pos.is_empty():
			continue
		var parts := _tree_parts(style)
		var trunk_h: float = parts[2]
		var crown_color: Color = group["color"]
		var trunk_color := Color(0.33, 0.24, 0.15) if style != BiomeData.TreeStyle.CACTUS else crown_color
		var crown_y := trunk_h + (2.6 if style == BiomeData.TreeStyle.PINE else (1.6 if style == BiomeData.TreeStyle.BROADLEAF else 0.0))
		if style == BiomeData.TreeStyle.DEAD:
			crown_y = trunk_h * 0.75
		elif style == BiomeData.TreeStyle.CACTUS:
			crown_y = trunk_h * 0.55
		for part in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = parts[part]
			mm.instance_count = pos.size()
			for k in pos.size():
				var sc := scales[k]
				var rot := Basis(Vector3.UP, float(k) * 2.39996) * sc
				var y := pos[k].y + (trunk_h * 0.5 if part == 0 else crown_y) * sc
				mm.set_instance_transform(k, Transform3D(rot, Vector3(pos[k].x, y, pos[k].z)))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees%d_%d" % [style, part]
			mmi.multimesh = mm
			mmi.material_override = POIBuilder.get_material(trunk_color if part == 0 else crown_color)
			mmi.visibility_range_end = 900.0
			add_child(mmi)
		# Trunks are solid: shapes added straight to this chunk's own body (no extra nodes)
		if not _trunk_shapes.has(style):
			var cyl := CylinderShape3D.new()
			cyl.radius = float(parts[3]) * 1.2
			cyl.height = trunk_h
			_trunk_shapes[style] = cyl
		var shape: Shape3D = _trunk_shapes[style]
		for k in pos.size():
			var owner_id := create_shape_owner(self)  # one owner per trunk: each has its own place
			shape_owner_add_shape(owner_id, shape)
			shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, Vector3(pos[k].x, pos[k].y + trunk_h * 0.5 * scales[k], pos[k].z)))
