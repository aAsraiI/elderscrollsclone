extends SceneTree
## Saves a picture of chosen ModelLibrary keys side by side, seen from +Z (the front, for props
## that stand against a wall).  godot --path . -s res://tools/preview_keys.gd -- out.png key,key,...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var keys := args[1].split(",")
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	world.add_child(sun)
	var x := 0.0
	for k in keys:
		var m := ModelLibrary.instance(k)
		if m == null:
			print("no model for ", k)
			continue
		world.add_child(m)
		var b := ModelLibrary.bounds(m)
		m.position = Vector3(x - b.position.x, -b.position.y, -b.get_center().z)
		var label := Label3D.new()
		label.text = k.get_file()
		label.pixel_size = 0.004
		label.position = Vector3(x + b.size.x * 0.5, b.size.y + 0.2, 0)
		world.add_child(label)
		x += b.size.x + 0.4
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(x * 0.5, 1.3, maxf(3.0, x * 0.42)), Vector3(x * 0.5, 0.8, 0))
	cam.current = true
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	quit()
