class_name StaticBatch
extends RefCounted
## Merges the plain boxes of a built place (a town, camp, interior or dungeon floor) into one mesh,
## so the GPU draws the whole place in one call instead of one call per box.
##
## Only boxes made by POIBuilder.add_box that nothing will touch again are merged: an unnamed
## (automatically named) box with no script anywhere above it, a non-glowing POIBuilder material,
## and nothing hidden. Their collision stays as it is; only the drawing moves into the merged mesh.
## Named boxes ("Gate", "SecretWall"...) are left alone because code finds and moves them by name.

static var _material: ShaderMaterial


## Shared material: the boxes' colours travel as vertex colours, and shaders/built.gdshader turns
## them into stone blocks, wood grain or worn plaster (see that file)
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/built.gdshader") as Shader
	return _material


## Merges what it can under `root` (in or out of the scene tree). Returns how many boxes it merged.
static func merge(root: Node3D) -> int:
	var found: Array = []  # [MeshInstance3D, Transform3D relative to root]
	_collect(root, Transform3D.IDENTITY, found)
	if found.size() < 2:
		return 0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for f in found:
		var mi := f[0] as MeshInstance3D
		var xf: Transform3D = f[1]
		var src := (mi.mesh as BoxMesh).get_mesh_arrays()
		var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
		var color := (mi.material_override as StandardMaterial3D).albedo_color
		var normal_basis := xf.basis.inverse().transposed()
		var base := verts.size()
		for i in v.size():
			verts.append(xf * v[i])
			normals.append((normal_basis * n[i]).normalized())
			colors.append(color)
		for i in idx:
			indices.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	var merged := MeshInstance3D.new()
	merged.name = "MergedBoxes"
	merged.mesh = mesh
	root.add_child(merged)
	# The originals go. A holder left with nothing in it goes too, and a plain solid holder hands
	# its collision shapes to one shared body (shapes without nodes, like a terrain chunk's).
	var body := StaticBody3D.new()
	body.name = "MergedCollision"
	for f in found:
		var mi := f[0] as MeshInstance3D
		var holder := mi.get_parent()
		var holder_xf: Transform3D = f[1] * mi.transform.affine_inverse()
		holder.remove_child(mi)
		mi.free()
		if holder == root or not String(holder.name).begins_with("@"):
			continue
		if holder.get_child_count() == 0 and holder.get_class() == "Node3D":
			holder.get_parent().remove_child(holder)
			holder.free()
		elif _plain_body(holder):
			for cs: CollisionShape3D in holder.get_children():
				var owner_id := body.create_shape_owner(body)
				body.shape_owner_add_shape(owner_id, cs.shape)
				body.shape_owner_set_transform(owner_id, holder_xf * cs.transform)
			holder.get_parent().remove_child(holder)
			holder.free()
	if body.get_shape_owners().is_empty():
		body.free()
	else:
		root.add_child(body)
	return found.size()


# A StaticBody3D add_box made: default layers, nothing left in it but its collision shapes
static func _plain_body(n: Node) -> bool:
	if n.get_class() != "StaticBody3D" or n.get_child_count() == 0:
		return false
	var b := n as StaticBody3D
	if b.collision_layer != 1 or b.collision_mask != 1:
		return false
	for c in b.get_children():
		if not (c is CollisionShape3D) or (c as CollisionShape3D).disabled:
			return false
	return true


static func _collect(node: Node, xf: Transform3D, found: Array) -> void:
	for child in node.get_children():
		if child.get_script() != null or not (child is Node3D):
			continue  # a scripted node may move or hide its parts: leave its whole subtree alone
		var c := child as Node3D
		if not c.visible:
			continue
		var cxf := xf * c.transform
		if c is MeshInstance3D:
			if _mergeable(c as MeshInstance3D):
				found.append([c, cxf])
		else:
			_collect(c, cxf, found)


static func _mergeable(mi: MeshInstance3D) -> bool:
	# Automatic names start with "@": code that looks a box up again gives it a real name
	if not (mi.mesh is BoxMesh) or mi.get_child_count() > 0 or not String(mi.name).begins_with("@"):
		return false
	var m := mi.material_override as StandardMaterial3D
	if m == null or m.emission_enabled or m.albedo_color.a < 1.0 or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	return String(mi.get_parent().name).begins_with("@")
