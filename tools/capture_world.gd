extends SceneTree
## Screenshots of the open world from chosen spots (for checking the land, water and plants
## without playing). Each view: x,z,height above ground,yaw degrees,pitch degrees[,name].
## The player is moved there first so the terrain and plants load around it.
##   godot --path . -s res://tools/capture_world.gd -- out_dir "x,z,h,yaw,pitch[,name]" ["..."]
## A view of "town" or "start" is taken where the game starts.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0]
	var scene := load("res://scenes/game/game.tscn") as PackedScene
	var game := scene.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 30:
		await process_frame
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as Node3D
	if p.has_node("Stats"):
		(p.get_node("Stats") as Stats).invulnerable = true
	for enc in wm.find_children("*", "EncounterManager", true, false):
		(enc as EncounterManager).enabled = false
	if wm.clock != null:
		wm.clock.set("hour", 10.5)
	var cam := Camera3D.new()
	cam.far = 4000.0
	root.add_child(cam)
	for vi in range(1, args.size()):
		var v := args[vi].split(",")
		var x := float(v[0])
		var z := float(v[1])
		var name := v[5] if v.size() > 5 else "view%d" % vi
		var ground := wm.get_height_at(x, z)
		p.global_position = Vector3(x, ground + 1.5, z)
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO
		p.set_physics_process(false)
		wm.ensure_area_loaded(p.global_position, 2)
		for i in 240:
			await process_frame
		var h := float(v[2])
		var yaw := deg_to_rad(float(v[3]))
		var pitch := deg_to_rad(float(v[4]))
		cam.global_position = Vector3(x, maxf(ground, wm.map.get_water_level(x, z)) + h, z)
		cam.rotation = Vector3(pitch, yaw, 0.0)
		cam.current = true
		for i in 20:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out_dir.path_join(name + ".png")
		img.save_png(path)
		var b := wm.get_biome_at(x, z)
		print("saved %s (%s, ground %.1f)" % [path, b.display_name if b != null else "sea", ground])
	quit()
