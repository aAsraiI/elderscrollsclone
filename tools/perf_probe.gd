extends SceneTree
## Performance probe (Alpha 1.23). Runs the real game WITH rendering, then for each place
## (where you start, the middle of a city, inside a dungeon) prints:
##   frame time (avg / worst), script process + physics time, draw calls, objects, nodes, lights
##   and which scripts cost the most: each script's _process/_physics_process is switched off
##   for a moment and the drop in script time is its cost.
##   godot --path . -s res://tools/perf_probe.gd            (a window opens for ~1-2 minutes)
##   godot --path . -s res://tools/perf_probe.gd -- quick   (no per-script costs)

var quick := false
var wm: WorldManager
var p: Node3D


func _initialize() -> void:
	quick = OS.get_cmdline_user_args().has("quick")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # true frame times, not the screen's 60 Hz
	Engine.max_fps = 0
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("set:"):
			var kv := a.trim_prefix("set:").split("=")
			GameSettings._ensure_loaded()
			GameSettings._values[kv[0]] = str_to_var(kv[1])  # this run only: never saved to your settings
			print("PERF setting ", kv[0], " = ", kv[1])
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(120)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as Node3D
	if wm == null or p == null:
		print("PERF no game")
		quit(1)
		return
	(p.get_node("Stats") as Stats).add_modifiers("perf_tough", {"max_health": 1000000.0})
	wm.clock.set_time(12.0)
	await frames(240)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("trees="):
			var reach := float(a.trim_prefix("trees="))
			var n := 0
			for mmi in root.find_children("Flora_*", "MultiMeshInstance3D", true, false):
				if (mmi as GeometryInstance3D).visibility_range_end > reach:
					(mmi as GeometryInstance3D).visibility_range_end = reach
					n += 1
			print("PERF trees capped at %.0f m: %d multimeshes" % [reach, n])
		if a == "noterrain":
			for c in root.find_children("Chunk_*", "", true, false):
				var m := c.get_node_or_null("Mesh") as Node3D
				if m != null and Vector2(c.global_position.x - p.global_position.x, c.global_position.z - p.global_position.z).length() > 300.0:
					m.visible = false
			print("PERF far terrain hidden")
	if OS.get_cmdline_user_args().has("ride"):
		WorldManager.profile_hitches = true
		Enemy.profile_spawns = OS.get_cmdline_user_args().has("spawns")
		await _ride()
		quit(0)
		return
	var only_dungeon := OS.get_cmdline_user_args().has("dungeon")
	if not only_dungeon:
		await _place("start")
	# the middle of the biggest city
	var city: PlacedPOI = null
	for t in wm.towns:
		if (t.poi as TownData).kind == TownData.Kind.CITY:
			city = t
			break
	if OS.get_cmdline_user_args().has("startonly"):
		quit(0)
		return
	if city != null and not only_dungeon:
		p.global_position = Vector3(city.position.x, wm.get_height_at(city.position.x, city.position.z) + 1.5, city.position.z)
		await frames(400)
		await _place("city " + city.id)
	# a dungeon
	for poi in wm.pois:
		if poi.poi is DungeonEntrancePOIData:
			var ok: bool = await wm.dungeons.enter(poi.id, poi.position, 0.0)
			if ok:
				await frames(200)
				await _place("dungeon " + poi.id)
				await wm.dungeons.exit()
			break
	quit(0)


func _sample(n: int) -> Dictionary:
	var ft := PackedFloat32Array()
	var proc := 0.0
	var phys := 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		ft.append((now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var sum := 0.0
	var worst := 0.0
	for f in ft:
		sum += f
		worst = maxf(worst, f)
	var sorted := ft.duplicate()
	sorted.sort()
	return {"avg": sum / n, "worst": worst, "p95": sorted[int(n * 0.95)], "proc": proc / n, "phys": phys / n}


func _place(label: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a == "turn":
			p.rotation.y += PI
			p.global_position.y += 12.0  # up a little, to see over the land
		if a.begins_with("shot="):
			await frames(20)
			var img := root.get_viewport().get_texture().get_image()
			var out := a.trim_prefix("shot=") + "_" + label.get_slice(" ", 0) + ".png"
			img.save_png(out)
			print("PERF shot ", out)
	var s := await _sample(180)
	var lights := 0
	var shadowed := 0
	for l in root.find_children("*", "Light3D", true, false):
		if (l as Light3D).is_visible_in_tree():
			lights += 1
			if (l as Light3D).shadow_enabled:
				shadowed += 1
				print("PERF shadowed light %s %s range %s" % [l.get_path(), l.get_class(), l.get("omni_range")])
	print("PERF == %s" % label)
	print("PERF settings view %s shadows %s grass %s far %s scale %s" % [GameSettings.get_value("view_distance"), GameSettings.get_value("shadows"), GameSettings.get_value("grass"), GameSettings.get_value("far_land"), GameSettings.get_value("render_scale")])
	for dl in root.find_children("*", "DirectionalLight3D", true, false):
		var d := dl as DirectionalLight3D
		if d.visible:
			print("PERF sun %s shadow %s  mode %d  max distance %.0f  splits %.2f/%.2f/%.2f" % [d.get_path(), d.shadow_enabled, d.directional_shadow_mode, d.directional_shadow_max_distance, d.directional_shadow_split_1, d.directional_shadow_split_2, d.directional_shadow_split_3])
	print("PERF frame avg %.2f ms  p95 %.2f  worst %.2f  | process %.2f ms  physics %.2f ms" % [s["avg"], s["p95"], s["worst"], s["proc"], s["phys"]])
	print("PERF draw calls %d  objects %d  primitives %dk  nodes %d  lights %d (shadowed %d)  actors %d  vram %d MB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		lights, shadowed, ActorRegistry.all().size(), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576)])
	# what is drawn: visible geometry grouped by the node under World (or the scene root) it belongs to
	var census := {}
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var cam := root.get_viewport().get_camera_3d()
		if cam != null and gi.visibility_range_end > 0.0 and gi.global_position.distance_to(cam.global_position) > gi.visibility_range_end + 50.0:
			continue  # past its draw distance
		var top: Node = gi
		var path := PackedStringArray()
		var n: Node = gi
		while n != null and n != root:
			path.insert(0, String(n.name).rstrip("0123456789_-"))
			n = n.get_parent()
		var key := "/".join(path.slice(0, mini(5 if path.size() > 3 and path[2] == "Chunk" else 4, path.size())))
		var c: Array = census.get(key, [0, 0, 0])
		c[0] += 1
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			c[2] += 1
		if gi is MultiMeshInstance3D:
			c[1] += (gi as MultiMeshInstance3D).multimesh.visible_instance_count if (gi as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (gi as MultiMeshInstance3D).multimesh.instance_count
		census[key] = c
	var keys := census.keys()
	keys.sort_custom(func(a, b) -> bool: return census[a][0] > census[b][0])
	for k in keys.slice(0, 14):
		print("PERF   draw %-56s %5d in range  %5d shadow  %d mm" % [k, census[k][0], census[k][2], census[k][1]])
	if quick:
		return
	# per-script cost: group processing nodes by script, switch each group off, see what drops
	var groups := {}
	for n in root.find_children("*", "", true, false):
		var sc := n.get_script() as Script
		if sc == null or not (n.is_processing() or n.is_physics_processing()):
			continue
		var key := sc.resource_path.get_file()
		if not groups.has(key):
			groups[key] = []
		groups[key].append(n)
	var costs := []
	for key in groups:
		var nodes: Array = groups[key]
		var was := []
		for n in nodes:
			was.append([n.is_processing(), n.is_physics_processing()])
			n.set_process(false)
			n.set_physics_process(false)
		var off := await _sample(40)
		for i in nodes.size():
			if is_instance_valid(nodes[i]):
				nodes[i].set_process(was[i][0])
				nodes[i].set_physics_process(was[i][1])
		await frames(5)
		var on := await _sample(40)
		costs.append([key, nodes.size(), float(on["avg"]) - float(off["avg"])])
	costs.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	for c in costs.slice(0, 18):
		print("PERF   %-32s x%-4d %.3f ms" % [c[0], c[1], c[2]])


# Moves the player at horse speed (15 m/s) in a straight line for 30 s; prints frame-time spikes
func _ride() -> void:
	var dir := Vector3(1, 0, 0.3).normalized()
	var spikes := 0
	var worst := 0.0
	var sum := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	var t := 0.0
	while t < 30.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var dt := minf(ms / 1000.0, 0.1)
		t += dt
		var at := p.global_position + dir * 15.0 * dt
		at.y = wm.get_height_at(at.x, at.z) + 1.2
		p.global_position = at
		sum += ms
		n += 1
		worst = maxf(worst, ms)
		if ms > 40.0:
			spikes += 1
			print("SPIKE %.0f ms at %.1f s" % [ms, t])
	for part in Enemy.spawn_costs:
		var c: Array = Enemy.spawn_costs[part]
		print("PERF spawn %-16s avg %.2f ms over %d" % [part, c[0] / 1000.0 / maxi(c[1], 1), c[1]])
	print("PERF ride: avg %.2f ms, worst %.0f ms, %d spikes over 40 ms in %d frames" % [sum / n, worst, spikes, n])
