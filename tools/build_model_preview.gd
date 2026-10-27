extends SceneTree
## Lays every model in a folder out in a grid, each scaled to about 2 m with its name above it,
## and saves res://tools/model_preview.tscn for looking at in the editor.
##   godot --headless --path . -s res://tools/build_model_preview.gd -- res://assets/models/creatures [keys]
## With "keys" it lays out the ModelLibrary keys under that prefix instead (fitted as the game does).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if args.size() > 0 else "res://assets/models"
	var by_key := args.size() > 1 and args[1] == "keys"
	var root := Node3D.new()
	root.name = "ModelPreview"
	root.set_script(load("res://tools/preview_anim.gd"))
	if args.size() > 2:
		root.set("role", args[2])
	var items: Array = []
	if by_key:
		for k in ModelLibrary.keys():
			if String(k).begins_with(folder):
				items.append(k)
		items.sort()
	else:
		_collect(folder, items)
	var cols := ceili(sqrt(float(items.size())))
	for i in items.size():
		var spot := Node3D.new()
		spot.name = "Spot%d" % i
		spot.position = Vector3((i % cols) * 3.0, 0.0, (i / cols) * 3.0)
		root.add_child(spot)
		spot.owner = root
		var model: Node3D
		if by_key:
			model = ModelLibrary.fitted(items[i], AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2)))
		else:
			var ps := load(items[i]) as PackedScene
			model = ps.instantiate() as Node3D if ps != null else null
			if model != null:
				var box := ModelLibrary.bounds(model)
				var s := 2.0 / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.01))
				model.scale = Vector3.ONE * s
		if model != null:
			spot.add_child(model)
			_own(model, root)
		var label := Label3D.new()
		label.text = String(items[i]).get_file() if not by_key else String(items[i])
		label.position = Vector3(0, 2.4, 0)
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spot.add_child(label)
		label.owner = root
		# A 1 m marker pointing -Z (the game's forward)
		var arrow := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 1.0)
		arrow.mesh = bm
		arrow.position = Vector3(0, 0.02, -0.5)
		spot.add_child(arrow)
		arrow.owner = root
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	sun.owner = root
	var cam := Camera3D.new()
	cam.name = "Camera"
	var mid := Vector3(cols * 1.5, 0, (items.size() / cols) * 1.5)
	cam.position = mid + Vector3(0, cols * 1.1 + 2.0, cols * 1.5 + 3.0)
	cam.current = true
	root.add_child(cam)
	cam.owner = root
	cam.look_at_from_position(cam.position, mid, Vector3.UP)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, "res://tools/model_preview.tscn")
	print("saved %d models" % items.size())
	quit()


func _collect(dir_path: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir_path):
		_collect(dir_path.path_join(d), out)
	for f in DirAccess.get_files_at(dir_path):
		if f.get_extension().to_lower() in ["fbx", "glb", "gltf"]:
			out.append(dir_path.path_join(f))


func _own(n: Node, owner_node: Node) -> void:
	n.owner = owner_node
	for c in n.get_children():
		_own(c, owner_node)
