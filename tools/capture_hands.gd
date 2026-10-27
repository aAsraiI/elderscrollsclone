extends SceneTree
## Close-ups of people holding a weapon (and a shield), one per look, for checking grips.
##   godot --path . -s res://tools/capture_hands.gd -- out.png <weapon .tres> <keys,comma,separated> [builtin] [role]
## "builtin" ignores your own models folder. role: idle (default), block, attack...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var weapon := load(args[1]) as ItemData
	var keys := args[2].split(",")
	ModelLibrary.only_builtin(args.size() > 3 and args[3] == "builtin")
	print("knight: ", ModelLibrary.entry("people/knight").get("path"))
	var role := args[4] if args.size() > 4 else "idle"
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	world.add_child(floor_body)
	var shield := load("res://data/weapons/iron_shield.tres") as ItemData
	var people: Array[Enemy] = []
	for i in keys.size():
		var e := Enemy.create()
		e.set_meta("model_key", keys[i])
		e.disposition = Enemy.Disposition.NEUTRAL
		e.starting_weapon = weapon
		e.starting_off_hand = shield if not weapon.two_handed and not weapon.is_bow else null
		e.position = Vector3(i * 1.6, 0.05, 0)
		world.add_child(e)
		e.rotation.y = deg_to_rad(-70)  # right side toward the camera
		people.append(e)
	for i in 30:
		await physics_frame
	for e in people:
		if e.body != null and e.body.model_body != null:
			var mb := e.body.model_body
			mb.set_process(false)
			mb._play(role)
			e.set_physics_process(false)
	for i in 40:
		await process_frame
	for e in people:
		if e.body != null and e.body.grip != null:
			var fwd := -e.global_basis.z
			var right := e.global_basis.x
			var g := e.body.grip.global_basis
			var held := e.body.grip.get_child(0) as Node3D if e.body.grip.get_child_count() > 0 else null
			var blade := (-g.z).normalized()
			print("%s: blade fwd %.2f right %.2f up %.2f | grip children %d" % [e.get_meta("model_key"), blade.dot(fwd), blade.dot(right), blade.y, e.body.grip.get_child_count()])
			var theirs := e.body.model_body.model.find_child("1H_Sword", true, false) as Node3D if e.body.model_body != null else null
			if theirs != null:
				var tb := theirs.global_basis.y.normalized()
				print("   their sword fwd %.2f right %.2f up %.2f   anim %s" % [tb.dot(fwd), tb.dot(right), tb.y, e.body.model_body.player.current_animation])
			if held != null:
				var wb := ModelLibrary.bounds(held)
				print("   weapon box in grip space ", wb)
	var cam := Camera3D.new()
	world.add_child(cam)
	var mid := Vector3((keys.size() - 1) * 0.8, 1.1, 0)
	cam.look_at_from_position(mid + Vector3(0.0, 0.25, 1.4 + keys.size() * 0.75), mid)
	if keys.size() == 1 and people[0].body != null and people[0].body.grip != null:
		# One person: right up to the hand
		var hand := people[0].body.grip.global_position
		var from_dir := Vector3(0.15, 0.2, 0.9) if args.size() <= 5 else Vector3(args[5].split_floats(",")[0], args[5].split_floats(",")[1], args[5].split_floats(",")[2])
		cam.look_at_from_position(hand + from_dir, hand)
		cam.fov = 40.0
	cam.current = true
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
