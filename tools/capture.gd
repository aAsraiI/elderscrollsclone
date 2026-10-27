extends SceneTree
## Opens a scene in a window, waits, saves a screenshot and quits (for checking looks without
## the editor). Optional camera: a position to look from and a point to look at.
##   godot --path . -s res://tools/capture.gd -- res://scene.tscn out.png [frames] [x,y,z] [tx,ty,tz]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := load(args[0]) as PackedScene
	var out := args[1]
	var frames := int(args[2]) if args.size() > 2 else 120
	var node := scene.instantiate()
	root.add_child(node)
	current_scene = node
	_godmode.call_deferred()  # nothing kills the player while the shot is set up
	if args.size() > 4:
		var cam := Camera3D.new()
		root.add_child(cam)
		var p := args[3].split_floats(",")
		var t := args[4].split_floats(",")
		cam.look_at_from_position(Vector3(p[0], p[1], p[2]), Vector3(t[0], t[1], t[2]))
		cam.current = true
	for i in frames:
		await process_frame
	if args.size() > 3 and args[3].begins_with("near:"):
		# Look at the n-th nearest node of a group from the current camera: near:enemies:0
		var parts := args[3].split(":")
		var from := root.get_viewport().get_camera_3d().global_position
		var list := get_nodes_in_group(parts[1]).filter(func(n): return n is Node3D)
		list.sort_custom(func(a, b): return a.global_position.distance_to(from) < b.global_position.distance_to(from))
		var pick: Node3D = list[mini(int(parts[2]) if parts.size() > 2 else 0, list.size() - 1)]
		var cam := Camera3D.new()
		root.add_child(cam)
		var fwd := -pick.global_transform.basis.z
		var dist := float(parts[3]) if parts.size() > 3 else 3.5
		cam.look_at_from_position(pick.global_position + fwd * dist + Vector3.UP * 1.6, pick.global_position + Vector3.UP * 0.9)
		cam.current = true
		print("looking at ", pick.name, " ", pick.get("display_name"))
		for i in 30:
			await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()


func _godmode() -> void:
	for i in 10:
		await process_frame
		var p := get_first_node_in_group("player")
		if p != null and p.has_node("Stats"):
			(p.get_node("Stats") as Stats).invulnerable = true
			return
