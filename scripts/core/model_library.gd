class_name ModelLibrary
extends RefCounted
## Real models for things the game used to build from boxes. Every look has a key ("prop/barrel",
## "weapon/sword", "creature/wolf", "item/potion"...); data/models/models.json says which model file
## each key uses, how to turn and fit it, and (for bodies) which parts to hide and which bones hold weapons.
## When a key has no model the old box placeholder is used, so nothing ever goes missing.
##
## Your own models (your own conversions of models from a game you own, a Blender export, an asset
## pack) go in a "models" folder, which wins over the built-in ones:
##   <game folder>/models/     next to the .exe (exported game)
##   user://models/            %APPDATA%/Godot/app_userdata/ELDERSCROLLSCLONE/models
## Name a file after its key with "/" turned into "__" (prop__barrel.glb, creature__wolf.gltf), or
## list it in a models.json there (same format as data/models/models.json). glTF / glb load at
## runtime (FBX too); see MODELS.md for every key and how to convert other formats.
##
## Fitting: a model is scaled (evenly) to the size of the placeholder it replaces, so it stands in
## the same space, and gets collision built from its own shape (replace_meshes / add_collision).

const MANIFEST := "res://data/models/models.json"

static var _entries := {}            # key -> Dictionary
static var _loaded := false
static var _scenes := {}             # path -> PackedScene, or Node3D template for runtime glTF
static var _shapes := {}             # cache key -> Array of [ConvexPolygonShape3D]
static var _meshes := {}             # cache key -> ArrayMesh (merged, for MultiMesh use)
static var _user_dirs: PackedStringArray = []


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_read_manifest(MANIFEST, "res://assets/models")
	_user_dirs = []
	if not OS.has_feature("editor"):
		_user_dirs.append(OS.get_executable_path().get_base_dir().path_join("models"))
	_user_dirs.append(ProjectSettings.globalize_path("user://models"))
	for dir in _user_dirs:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		_read_manifest(dir.path_join("models.json"), dir)
		for f in DirAccess.get_files_at(dir):
			var ext := f.get_extension().to_lower()
			if ext in ["glb", "gltf", "fbx"]:
				var key := f.get_basename().replace("__", "/")
				var e: Dictionary = _entries.get(key, {}).duplicate()
				e["path"] = dir.path_join(f)
				e["user"] = true
				_entries[key] = e


static func _read_manifest(path: String, base: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_warning("ModelLibrary: %s is not a JSON object" % path)
		return
	for key in data:
		if String(key).begins_with("_"):
			continue
		var e = data[key]
		if e is String:
			e = {"path": e}
		if not (e is Dictionary) or not e.has("path"):
			continue
		e = (e as Dictionary).duplicate()
		var p := String(e["path"])
		if not p.begins_with("res://") and not p.is_absolute_path():
			p = base.path_join(p)
		e["path"] = p
		e["user"] = not base.begins_with("res://")
		_entries[key] = e


## Forget everything loaded (after dropping new files in the models folder)
static func reload() -> void:
	_loaded = false
	_entries.clear()
	_scenes.clear()
	_shapes.clear()
	_meshes.clear()


static func has(key: String) -> bool:
	_load()
	return _entries.has(key)


static func entry(key: String) -> Dictionary:
	_load()
	return _entries.get(key, {})


static func keys() -> Array:
	_load()
	return _entries.keys()


## The first of `keys` that has a model ("" if none)
static func first(candidates: Array) -> String:
	_load()
	for k in candidates:
		if _entries.has(String(k)):
			return String(k)
	return ""


## The model for `key`, turned the way its entry says (rot, in degrees), at its own size.
## null when there is no model or it fails to load.
static func instance(key: String) -> Node3D:
	var e := entry(key)
	if e.is_empty():
		return null
	var model := _instantiate(String(e["path"]))
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.set_meta("model_key", key)
	var rot: Array = e.get("rot", [0, 0, 0])
	model.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	holder.add_child(model)
	if e.has("texture"):
		_texture(holder, String(e["texture"]), String(e["path"]).get_base_dir())
	if e.has("tint"):
		var t: Array = e["tint"]
		tint(holder, Color(t[0], t[1], t[2]))
	return holder


static var _textured := {}  # texture path -> StandardMaterial3D


# Models whose texture did not come along with the file (older FBX): one textured material for all
static func _texture(holder: Node3D, tex: String, base: String) -> void:
	var path := tex if tex.begins_with("res://") or tex.is_absolute_path() else base.path_join(tex)
	if not _textured.has(path):
		var t: Texture2D = null
		if path.begins_with("res://"):
			t = load(path) as Texture2D
		else:
			var img := Image.load_from_file(path)
			t = ImageTexture.create_from_image(img) if img != null else null
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = t
		mat.roughness = 0.9
		_textured[path] = mat
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _textured[path]


static func _instantiate(path: String) -> Node3D:
	if _scenes.has(path):
		var cached = _scenes[path]
		if cached is PackedScene:
			return (cached as PackedScene).instantiate() as Node3D
		if cached is Node3D:
			return (cached as Node3D).duplicate() as Node3D
		return null
	var out: Node3D = null
	if path.begins_with("res://"):
		var ps := load(path) as PackedScene
		_scenes[path] = ps
		if ps != null:
			out = ps.instantiate() as Node3D
	else:
		# A user model: read the glTF (or FBX) at runtime
		var doc: GLTFDocument = FBXDocument.new() if path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
		var state: GLTFState = FBXState.new() if path.get_extension().to_lower() == "fbx" else GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			var scene := doc.generate_scene(state) as Node3D
			_scenes[path] = scene
			if scene != null:
				out = scene.duplicate() as Node3D
		else:
			push_warning("ModelLibrary: could not read %s" % path)
			_scenes[path] = null
	return out


## The model for `key`, scaled evenly and moved so it fills `target` (a box in the parent's space):
##   "contain"  as big as fits inside the box (default)
##   "height"   as tall as the box, centred on its floor
##   "long"     its longest side as long as the box's longest side
## The model's bottom sits on the box's bottom, centred across.
static func fitted(key: String, target: AABB, mode: String = "") -> Node3D:
	var holder := instance(key)
	if holder == null:
		return null
	var e := entry(key)
	if mode == "":
		mode = String(e.get("fit", "fill"))
	var box := bounds(holder)
	if box.size.length() < 0.0001:
		return holder
	# Lying the other way round from the space it fills: turn it a quarter (props, not held items)
	if mode != "long" and bool(e.get("align", true)):
		var t_ratio := target.size.x / maxf(target.size.z, 0.0001)
		var m_ratio := box.size.x / maxf(box.size.z, 0.0001)
		if (t_ratio > 1.3 and m_ratio < 0.77) or (t_ratio < 0.77 and m_ratio > 1.3):
			(holder.get_child(0) as Node3D).rotate_y(PI * 0.5)
			box = bounds(holder)
	var s := 1.0
	match mode:
		"height":
			s = target.size.y / maxf(box.size.y, 0.0001)
		"long":
			s = _longest(target.size) / maxf(_longest(box.size), 0.0001)
		"width":
			s = maxf(target.size.x, target.size.z) / maxf(maxf(box.size.x, box.size.z), 0.0001)
		"fill":
			# As tall as the old piece (so things set on top still sit on it), but not much wider
			s = minf(target.size.y / maxf(box.size.y, 0.0001), 1.2 * minf(target.size.x / maxf(box.size.x, 0.0001),
				target.size.z / maxf(box.size.z, 0.0001)))
		_:
			s = minf(minf(target.size.x / maxf(box.size.x, 0.0001), target.size.y / maxf(box.size.y, 0.0001)),
				target.size.z / maxf(box.size.z, 0.0001))
	s *= float(e.get("scale", 1.0))
	var child := holder.get_child(0) as Node3D
	child.scale *= s
	child.position *= s
	box = bounds(holder)
	var want_bottom := Vector3(target.get_center().x, target.position.y, target.get_center().z)
	var have_bottom := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	if String(e.get("anchor", "")) == "center":
		want_bottom.y = target.get_center().y
		have_bottom.y = box.get_center().y
	child.position += want_bottom - have_bottom
	return holder


static func _longest(v: Vector3) -> float:
	return maxf(v.x, maxf(v.y, v.z))


## The box around every mesh under `node`, in node's own space
static func bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "VisualInstance3D", true, false):
		var vi := mi as VisualInstance3D
		if vi is GPUParticles3D or vi is CPUParticles3D or vi is Label3D or _hidden(vi, node):
			continue
		var local: AABB
		var mesh_i := vi as MeshInstance3D
		var skel := _skeleton_of(mesh_i)
		if skel != null:
			# A skinned mesh is drawn where its skeleton puts it, not where its raw vertices sit
			var pts := skinned_points(mesh_i, skel, 2000)
			if pts.is_empty():
				continue
			var xf := relative_transform(node, skel)
			local = AABB(xf * pts[0], Vector3.ZERO)
			for p in pts:
				local = local.expand(xf * p)
		else:
			local = relative_transform(node, vi) * vi.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out if not first else AABB()


# Hidden itself or under something hidden (below `root`)
static func _hidden(n: Node, root: Node) -> bool:
	var cur := n
	while cur != null:
		if cur is Node3D and not (cur as Node3D).visible:
			return true
		if cur == root:
			return false
		cur = cur.get_parent()
	return false


static func _skeleton_of(mi: MeshInstance3D) -> Skeleton3D:
	if mi == null or mi.skin == null or mi.mesh == null:
		return null
	return mi.get_node_or_null(mi.skeleton) as Skeleton3D


## The vertices of a skinned mesh as its skeleton poses them (in the skeleton's space).
## Every `max_points`-th share is sampled, so big meshes stay quick.
static func skinned_points(mi: MeshInstance3D, skel: Skeleton3D, max_points: int = 2000) -> PackedVector3Array:
	var out := PackedVector3Array()
	var skin := mi.skin
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		mats.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(b) if bone >= 0 else Transform3D.IDENTITY)
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones == null or weights == null:
			continue
		var per := (bones as PackedInt32Array).size() / verts.size()
		var step := maxi(1, verts.size() / maxi(1, max_points))
		for i in range(0, verts.size(), step):
			var p := Vector3.ZERO
			var total := 0.0
			for k in per:
				var w: float = weights[i * per + k]
				var bi: int = bones[i * per + k]
				if w <= 0.0 or bi < 0 or bi >= mats.size():
					continue
				p += (mats[bi] * verts[i]) * w
				total += w
			out.append(p / total if total > 0.0 else verts[i])
	return out


static func relative_transform(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Collision that follows the model's own shape: one convex hull per mesh, added to `body`.
## The shapes are cached per key and size, so a hundred barrels share their hulls.
static func add_collision(body: CollisionObject3D, model: Node3D, cache_key: String = "") -> void:
	var rel := relative_transform(body, model)
	var shapes: Array = []
	var ck := cache_key + "|" + str(rel.basis.get_scale().snappedf(0.001)) if cache_key != "" else ""
	if ck != "" and _shapes.has(ck):
		shapes = _shapes[ck]
	else:
		# Points in the model's own space times the model's scale, so the shape can be reused anywhere
		var scale_only := Transform3D(Basis.from_scale(rel.basis.get_scale()), Vector3.ZERO)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var xf := scale_only * relative_transform(model, m)
			var pts := PackedVector3Array()
			var skel := _skeleton_of(m)
			if skel != null:
				xf = scale_only * relative_transform(model, skel)
				for p in skinned_points(m, skel, 400):
					pts.append(xf * p)
			else:
				for s in m.mesh.get_surface_count():
					var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
					var step := maxi(1, verts.size() / 400)
					for i in range(0, verts.size(), step):
						pts.append(xf * verts[i])
			if pts.size() < 4:
				continue
			var hull := ConvexPolygonShape3D.new()
			hull.points = _hull_points(pts)
			shapes.append(hull)
		if ck != "":
			_shapes[ck] = shapes
	for hull in shapes:
		var cs := CollisionShape3D.new()
		cs.name = "ModelShape"
		cs.shape = hull
		cs.transform = Transform3D(rel.basis.orthonormalized(), rel.origin)
		body.add_child(cs)


# Few points for a hull (physics engines want few): the furthest point in each of 98 directions
static func _hull_points(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() <= 64:
		return pts
	var out := PackedVector3Array()
	var seen := {}
	for x in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for y in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for z in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				if x == 0.0 and y == 0.0 and z == 0.0:
					continue
				var d := Vector3(x, y, z)
				var best := 0
				var best_dot := -INF
				for i in pts.size():
					var dot := pts[i].dot(d)
					if dot > best_dot:
						best_dot = dot
						best = i
				if not seen.has(best):
					seen[best] = true
					out.append(pts[best])
	return out


## Swaps the box meshes of `holder` for the model `key`: the model is fitted into the space the old
## meshes took up, the old meshes and box shapes are removed, and the nearest physics body gets
## collision from the model's shape. Returns the model, or null (and changes nothing) without one.
static func replace_meshes(holder: Node3D, key: String, mode: String = "", body: CollisionObject3D = null) -> Node3D:
	if not has(key):
		return null
	# The plain parts go; flames, glows and anything marked keep_mesh stay
	var plain: Array = []
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		if not _is_kept(mi) and not _glows(mi as MeshInstance3D) and (mi as MeshInstance3D).visible:
			plain.append(mi)
	if plain.is_empty():
		return null
	var old := AABB()
	for i in plain.size():
		var b := relative_transform(holder, plain[i]) * (plain[i] as MeshInstance3D).get_aabb()
		old = b if i == 0 else old.merge(b)
	if old.size.length() < 0.001:
		return null
	var model := fitted(key, old, mode)
	if model == null:
		return null
	if body == null and holder is CollisionObject3D:
		body = holder
	for mi in plain:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	# Box shapes inside the holder go (on the holder itself, or on little bodies that held one box)
	var had_shapes := false
	for cs in holder.find_children("*", "CollisionShape3D", true, false):
		had_shapes = true
		cs.get_parent().remove_child(cs)
		cs.queue_free()
	for sb in holder.find_children("*", "StaticBody3D", true, false):
		if sb != body and sb.get_child_count() == 0:
			sb.get_parent().remove_child(sb)
			sb.queue_free()
	holder.add_child(model)
	if had_shapes or body != null:
		if body == null:
			var sb := StaticBody3D.new()
			sb.name = "ModelBody"
			holder.add_child(sb)
			body = sb
		add_collision(body, model, key + "|" + str(old.size.snappedf(0.01)))
	return model


# A flame, ember or magic glow: kept when a prop's plain parts are swapped for a model
static func _glows(mi: MeshInstance3D) -> bool:
	var n := String(mi.name).to_lower()
	if n.contains("flame") or n.contains("fire") or n.contains("glow") or n.contains("ember"):
		return true
	var mat := mi.material_override as BaseMaterial3D
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.mesh.surface_get_material(0) as BaseMaterial3D
	return mat != null and mat.emission_enabled and mat.emission != Color.BLACK and mat.emission_energy_multiplier > 0.0


static func _is_kept(n: Node) -> bool:
	var cur := n
	while cur != null:
		if cur.has_meta("model_key") or cur.has_meta("keep_mesh"):
			return true
		cur = cur.get_parent()
	return false


## One mesh with every part of the model baked in, scaled to `height` metres tall (for MultiMesh
## scatter like trees and rocks). The bottom sits `sink` metres below y = 0 (into the ground).
static func merged_mesh(key: String, height: float = 0.0, sink: float = 0.0) -> ArrayMesh:
	var ck := "%s|%.3f|%.3f" % [key, height, sink]
	if _meshes.has(ck):
		return _meshes[ck]
	var holder := instance(key)
	if holder == null:
		return null
	var box := bounds(holder)
	var s := 1.0 if height <= 0.0 or box.size.y < 0.0001 else height / box.size.y
	var e := entry(key)
	s *= float(e.get("scale", 1.0)) if height <= 0.0 else 1.0
	var fix := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * s - Vector3(0.0, sink, 0.0))
	var out := ArrayMesh.new()
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := fix * relative_transform(holder, m)
		for si in m.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(m.mesh, si)
			var arrays := st.commit_to_arrays()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] = xf * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
			var normals = arrays[Mesh.ARRAY_NORMAL]
			if normals is PackedVector3Array:
				var nb := xf.basis.inverse().transposed()
				for i in normals.size():
					normals[i] = (nb * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := m.get_active_material(si)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	holder.free()
	_meshes[ck] = out
	return out


## Multiplies every material colour under `node` by `color` (materials are copied, not shared)
static func tint(node: Node, color: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si) as BaseMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as BaseMaterial3D
			mat.albedo_color = mat.albedo_color * color
			m.set_surface_override_material(si, mat)
