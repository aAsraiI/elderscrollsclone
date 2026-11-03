extends SceneTree
## Lists props and builder-kit pieces whose collision is much bigger than what you can see (or missing).
## Only solid collision counts (world layer 1); the use box of a bed or shrine is not a wall.
##   godot --headless --path . -s res://tools/audit_hitboxes.gd [-- builtin]

const DIRS := ["res://scenes/interiors/props/", "res://scenes/kit/containers/", "res://scenes/kit/surfaces/", "res://scenes/kit/stations/"]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # the tree is ready: pieces dress themselves (models, fitted collision) as in the game
	if "builtin" in OS.get_cmdline_user_args():
		ModelLibrary.only_builtin(true)
	var bad := 0
	var count := 0
	for dir: String in DIRS:
		for path in _scenes(dir):
			var p := (load(path) as PackedScene).instantiate() as Node3D
			root.add_child(p)
			var seen := ModelLibrary.bounds(p)
			var solid := AABB()
			var first := true
			for cs in p.find_children("*", "CollisionShape3D", true, false):
				var s := (cs as CollisionShape3D).shape
				var body := cs.get_parent() as CollisionObject3D
				if s == null or body == null or body.collision_layer & 1 == 0:
					continue
				var local := ModelLibrary.relative_transform(p, cs) * _extent(s)
				solid = local if first else solid.merge(local)
				first = false
			var note := ""
			if first:
				note = "no collision"
			else:
				var grow := Vector3(solid.size.x / maxf(seen.size.x, 0.01), solid.size.y / maxf(seen.size.y, 0.01), solid.size.z / maxf(seen.size.z, 0.01))
				if grow.x > 1.25 or grow.y > 1.25 or grow.z > 1.25:
					note = "collision %.2fx %.2fx %.2fx the model" % [grow.x, grow.y, grow.z]
			var name := path.trim_prefix("res://scenes/").get_basename()
			print("%-40s seen %s  solid %s  %s" % [name, seen.size.snappedf(0.01), solid.size.snappedf(0.01), note])
			count += 1
			if note != "":
				bad += 1
			p.free()
	print("%d of %d pieces with a problem" % [bad, count])
	quit()


# The space a shape fills, in its own coordinates
func _extent(s: Shape3D) -> AABB:
	var pts := PackedVector3Array()
	if s is BoxShape3D:
		return AABB(-(s as BoxShape3D).size * 0.5, (s as BoxShape3D).size)
	if s is ConvexPolygonShape3D:
		pts = (s as ConvexPolygonShape3D).points
	elif s is ConcavePolygonShape3D:
		pts = (s as ConcavePolygonShape3D).get_faces()
	else:
		return s.get_debug_mesh().get_aabb()
	var out := AABB(pts[0], Vector3.ZERO) if not pts.is_empty() else AABB()
	for q in pts:
		out = out.expand(q)
	return out


func _scenes(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scenes(dir + d + "/"))
	return out
