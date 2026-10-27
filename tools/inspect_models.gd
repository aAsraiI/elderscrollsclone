extends SceneTree
## Prints every model under res://assets/models: its size, skeleton bones and animations.
##   godot --headless --path . -s res://tools/inspect_models.gd [-- folder]

func _init() -> void:
	var root := "res://assets/models"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		root = args[0]
	_walk(root)
	quit()


func _walk(dir_path: String) -> void:
	for d in DirAccess.get_directories_at(dir_path):
		_walk(dir_path.path_join(d))
	for f in DirAccess.get_files_at(dir_path):
		var ext := f.get_extension().to_lower()
		if ext in ["fbx", "glb", "gltf"]:
			_inspect(dir_path.path_join(f))


func _inspect(path: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("%s\tFAILED" % path)
		return
	var n := ps.instantiate() as Node3D
	var box := ModelLibrary.bounds(n)
	var line := "%s\tsize=(%.2f, %.2f, %.2f)\tmin=(%.2f, %.2f, %.2f)" % [path, box.size.x, box.size.y, box.size.z, box.position.x, box.position.y, box.position.z]
	var tris := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m != null:
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	line += "\ttris=%d" % tris
	var mesh_names: PackedStringArray = []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mesh_names.append("%s%s" % [mi.name, "(skinned)" if (mi as MeshInstance3D).skin != null else ""])
	if mesh_names.size() > 1:
		line += "\n    meshes: " + ", ".join(mesh_names)
	for sk in n.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		var names: PackedStringArray = []
		for i in s.get_bone_count():
			names.append("%s<%s" % [s.get_bone_name(i), s.get_bone_name(s.get_bone_parent(i)) if s.get_bone_parent(i) >= 0 else "-"])
		line += "\n    bones: " + ", ".join(names)
	# Which way the head points from the middle (the game's forward is -Z)
	for sk in n.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		for i in s.get_bone_count():
			if s.get_bone_name(i).to_lower() == "head":
				var hp := ModelLibrary.relative_transform(n, s) * s.get_bone_global_pose(i).origin
				var d := hp - box.get_center()
				line += "\n    head at (%.2f, %.2f, %.2f) from centre" % [d.x, d.y, d.z]
				break
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		line += "\n    anims: " + ", ".join((ap as AnimationPlayer).get_animation_list())
	print(line)
	n.free()
