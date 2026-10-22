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
static func build_data(map: WorldMap, coord: Vector2i, chunk_size: float, quads: int) -> Dictionary:
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

	var origin_x := coord.x * chunk_size
	var origin_z := coord.y * chunk_size
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
	return {"coord": coord, "arrays": arrays, "faces": faces}


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
