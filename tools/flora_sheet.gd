extends SceneTree
## Contact sheets of plant and rock models standing on flat ground, for choosing which to use.
## Each model stands on its foot (Flora.planted_mesh: the middle of its lowest part) beside a
## 1.8 m person (the white post), labelled with its name and height. A model whose trunk leans (its
## top well off to one side of its foot) is marked in red: it was made to grow out of a slope or a
## cliff and will not stand right on flat ground. One whose foot is far from its middle (a lopsided
## crown) is yellow: fine, it is planted by its foot. Prints the same as a table.
##   godot --path . -s res://tools/flora_sheet.gd -- out_dir prefix [per_sheet]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0]
	var prefix := args[1] if args.size() > 1 else "kit/plants/"
	var per := int(args[2]) if args.size() > 2 else 8
	var keys: Array = []
	for k in ModelLibrary.keys():
		if String(k).begins_with(prefix):
			keys.append(k)
	keys.sort()
	var sheet := 0
	var i := 0
	while i < keys.size():
		var batch := keys.slice(i, i + per)
		await _sheet(batch, out_dir.path_join("%s_%02d.png" % [prefix.trim_suffix("/").get_file(), sheet]))
		i += per
		sheet += 1
	quit()


## How a model stands: [height, lean degrees, foot offset as a share of its half width, flagged]
static func stance(mesh: Mesh) -> Array:
	var aabb := mesh.get_aabb()
	var foot := Flora.foot_of(mesh)
	var top_cut := aabb.position.y + aabb.size.y * 0.7
	var sum := Vector3.ZERO
	var n := 0
	for si in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			if v.y >= top_cut:
				sum += v
				n += 1
	var top := sum / float(maxi(n, 1))
	var rise := maxf(top.y - foot.y, 0.01)
	var lean := rad_to_deg(atan2(Vector2(top.x - foot.x, top.z - foot.z).length(), rise))
	var half := maxf(maxf(aabb.size.x, aabb.size.z) * 0.5, 0.01)
	var off := Vector2(foot.x - aabb.get_center().x, foot.z - aabb.get_center().z).length() / half
	return [aabb.size.y, lean, off, lean > 18.0]


func _sheet(keys: Array, path: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var x := 0.0
	var tallest := 2.0
	for k: String in keys:
		var mesh := Flora.planted_mesh(k, 0.0)
		if mesh == null:
			continue
		var st := stance(mesh)
		var aabb := mesh.get_aabb()
		var w := maxf(aabb.size.x, aabb.size.z)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		world.add_child(mi)
		mi.position = Vector3(x + w * 0.5 - aabb.get_center().x, 0, 0)
		var person := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 1.8, 0.3)
		person.mesh = box
		person.position = Vector3(x + w * 0.5 + w * 0.5 + 0.6, 0.9, 1.0)
		world.add_child(person)
		var label := Label3D.new()
		label.text = "%s\n%.1f m%s" % [k.get_file(), st[0], "\nLEANS %.0f°" % st[1] if st[1] > 18.0 else ("\nFOOT OFF-CENTRE" if st[2] > 0.45 else "")]
		label.modulate = Color(1, 0.3, 0.25) if st[3] else (Color(1, 0.85, 0.4) if st[2] > 0.45 else Color.WHITE)
		label.outline_size = 10
		label.font_size = 26
		label.fixed_size = true
		label.pixel_size = 0.0015
		label.no_depth_test = true
		label.position = Vector3(x + w * 0.5, -1.0, 0.0)
		world.add_child(label)
		print("%s\theight %.1f\twidth %.1f\tlean %.0f\tfoot off %.2f%s" % [k, st[0], w, st[1], st[2], "\tCHECK" if st[3] else ""])
		x += w + 2.0
		tallest = maxf(tallest, aabb.size.y)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(x + 40.0, 60.0)
	ground.mesh = plane
	ground.position = Vector3(x * 0.5, 0, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.4, 0.28)
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(x / 1.7, tallest + 6.0)
	cam.look_at_from_position(Vector3(x * 0.5, tallest * 0.5 + 6.0, 200.0), Vector3(x * 0.5, tallest * 0.35 - 1.0, 0))
	cam.current = true
	for i in 12:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	world.queue_free()
	await process_frame
