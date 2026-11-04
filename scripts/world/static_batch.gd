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
	var stone_hint := root.has_meta("stone_walls")  # a dungeon: what is not wood is stone (vertex alpha tells the shader)
	var found: Array = []  # [MeshInstance3D, Transform3D relative to root]
	_collect(root, Transform3D.IDENTITY, found)
	if found.size() < 2:
		return 0
	var mesh := _build_merged(found, stone_hint)  # 1.23: whole arrays at a time, no per-vertex script loops
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


## Alpha 1.13 interiors: merges the static drawing of each room module (its shell, inner walls,
## caps and props, all made by InteriorKit or prop scenes) into one mesh per room, so a room is
## one draw call and can be hidden as one (InteriorAtmosphere). Glowing, see-through and hidden
## parts stay, and so does anything in the group "interior_dynamic" (a secret wall that opens) or
## under a script of its own (doors, levers, chests, people). Collision is left as it is. A root
## with no room modules (a building interior) is merged as one room. Returns how many parts merged.
static func merge_interior(root: Node3D) -> int:
	var stone_hint := root.has_meta("stone_walls")
	var td := Time.get_ticks_usec()
	var dressed := 0
	for p in root.find_children("*", "StaticBody3D", true, false):
		if p is InteriorProp:
			(p as InteriorProp).dress()  # models in first: only props without one are merged as boxes
			dressed += 1
	if WorldManager.profile_hitches and Time.get_ticks_usec() - td > 10000:
		print("HITCH       props dressed: %d in %.1f ms" % [dressed, (Time.get_ticks_usec() - td) / 1000.0])
	var rooms: Array[Node3D] = []
	for c in root.get_children():
		if c is RoomModule:
			rooms.append(c)
	if rooms.is_empty():
		rooms.append(root)
	var total := 0
	for room in rooms:
		var found: Array = []
		_collect_interior(room, Transform3D.IDENTITY, found, room == root)
		if found.size() < 2:
			continue
		var tq := Time.get_ticks_usec()
		var mesh := _build_merged(found, stone_hint)  # 1.23: whole arrays at a time, no per-vertex script loops
		if WorldManager.profile_hitches and Time.get_ticks_usec() - tq > 10000:
			print("HITCH       merged %d pieces, %d vertices in %.1f ms" % [found.size(), mesh.surface_get_array_len(0), (Time.get_ticks_usec() - tq) / 1000.0])
		var merged := MeshInstance3D.new()
		merged.name = "MergedRoom"
		merged.mesh = mesh
		room.add_child(merged)
		# the big flat pieces (walls, floors, ceilings) hide what is behind them from the renderer
		var occ := 0
		for f in found:
			var mi := f[0] as MeshInstance3D
			var bm := mi.mesh as BoxMesh
			if bm != null:
				var s := bm.size
				var dims := [s.x, s.y, s.z]
				dims.sort()
				if dims[0] >= 0.25 and dims[1] >= 2.0:
					var oi := OccluderInstance3D.new()
					oi.name = "Occluder%d" % occ
					var bo := BoxOccluder3D.new()
					bo.size = s
					oi.occluder = bo
					room.add_child(oi)
					oi.transform = f[1]
					occ += 1
		for f in found:
			var mi := f[0] as MeshInstance3D
			mi.get_parent().remove_child(mi)
			mi.free()
		total += found.size()
	return total


static func _collect_interior(node: Node, xf: Transform3D, found: Array, flat: bool) -> void:
	for child in node.get_children():
		if not (child is Node3D) or child.is_in_group("interior_dynamic"):
			continue
		if child is RoomModule and not flat:
			continue  # another room: merged on its own
		if child.get_script() != null and not (child is RoomModule or child is InteriorProp or child is DoorwayMarker or child is SpawnSocket):
			continue
		var c := child as Node3D
		if not c.visible:
			continue
		var cxf := xf * c.transform
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var parent := mi.get_parent()
			var m := mi.material_override as StandardMaterial3D
			if mi.mesh is PrimitiveMesh and mi.get_child_count() == 0 and m != null and not m.emission_enabled \
					and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.albedo_color.a >= 1.0 \
					and (parent.is_in_group("interior_geometry") or parent is InteriorProp):
				found.append([mi, cxf])
		else:
			_collect_interior(c, cxf, found, flat)


## 1.23 performance: a primitive's geometry, worked out once per mesh (the same few boxes and
## cylinders are shared by thousands of props; get_mesh_arrays() rebuilt them every time)
static var _arrays := {}
static var _unit_box: BoxMesh


## [vertices, normals] of a primitive, one vertex per triangle corner (no index list), made once
static func _arrays_of(m: PrimitiveMesh) -> Array:
	var id := m.get_instance_id()
	if not _arrays.has(id):
		var src := m.get_mesh_arrays()
		var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		var idx = src[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			_arrays[id] = [v, n]
		else:
			var dv := PackedVector3Array()
			var dn := PackedVector3Array()
			dv.resize((idx as PackedInt32Array).size())
			dn.resize(dv.size())
			var k := 0
			for i in idx:
				dv[k] = v[i]
				dn[k] = n[i]
				k += 1
			_arrays[id] = [dv, dn]
	return _arrays[id]


## One mesh of every [MeshInstance3D, transform] in `found`, each piece coloured by its material
static func _build_merged(found: Array, stone_hint: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var piece := PackedColorArray()
	for f in found:
		var mi := f[0] as MeshInstance3D
		var xf: Transform3D = f[1]
		var src: Array
		var bm := mi.mesh as BoxMesh
		if bm != null and bm.subdivide_width == 0 and bm.subdivide_height == 0 and bm.subdivide_depth == 0:
			# every plain box is the unit box stretched: one set of arrays for all of them
			if _unit_box == null:
				_unit_box = BoxMesh.new()
				_unit_box.size = Vector3.ONE
			src = _arrays_of(_unit_box)
			xf = xf * Transform3D(Basis.from_scale(bm.size), Vector3.ZERO)
		else:
			src = _arrays_of(mi.mesh as PrimitiveMesh)
		var v: PackedVector3Array = src[0]
		var color := (mi.material_override as StandardMaterial3D).albedo_color
		if stone_hint:
			color.a = 0.5
		verts.append_array(xf * v)
		normals.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (src[1] as PackedVector3Array))
		piece.resize(v.size())
		piece.fill(color)
		colors.append_array(piece)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh
