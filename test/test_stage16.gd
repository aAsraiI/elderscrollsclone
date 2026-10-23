extends SceneTree
## Headless tests for stage 16, art, sound and polish: the shaders are in place (built world,
## terrain, sky), the sky follows the clock, the menu's 3D backdrop builds, footsteps know the
## ground, creatures have voices, the town has its own music, and hits leave blood or sparks.
## (Headless has no GPU, so these check the wiring; how it looks is checked in the editor.)
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage16.gd

var passes := 0
var fails := 0


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await frames(2)
	t_shaders()
	t_sound()
	await t_menu()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_shaders() -> void:
	print("-- the look")
	for s in ["sky", "built", "terrain"]:
		var sh := load("res://shaders/%s.gdshader" % s) as Shader
		check("the %s shader loads" % s, sh != null and sh.code.length() > 200)
	check("built things use the stone / wood / plaster shader", StaticBatch.material().shader != null and StaticBatch.material().shader.resource_path.ends_with("built.gdshader"))
	check("the ground uses the terrain shader", NatureMeshes.terrain_material().shader.resource_path.ends_with("terrain.gdshader"))
	var sky := (load("res://shaders/sky.gdshader") as Shader).code
	check("the sky has stars, moons and clouds", sky.contains("star") and sky.contains("moon2_dir") and sky.contains("cloud_cover"))


func t_sound() -> void:
	print("-- sound")
	var ok := 0
	for s in ["step_grass", "step_stone", "step_wood", "step_water", "step_snow", "step_sand", "growl", "roar", "screech", "hiss", "grunt", "groan", "shout"]:
		var w := Synth.get_sound(s) as AudioStreamWAV
		ok += 1 if w != null and w.data.size() > 200 else 0
	check("footsteps for six surfaces and seven creature voices", ok == 13, str(ok))
	check("each surface sounds different", (Synth.get_sound("step_grass") as AudioStreamWAV).data != (Synth.get_sound("step_stone") as AudioStreamWAV).data)
	var town := Synth.make_music("town")
	check("the town has its own music", town != null and town.data.size() > 1000 and town.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	check("and it differs from the day's", town.data != Synth.make_music("day").data)


func t_menu() -> void:
	print("-- the main menu")
	var b := MenuBackdrop.new()
	root.add_child(b)
	await frames(3)
	check("the 3D backdrop builds", b.get_child_count() > 20, str(b.get_child_count()))
	check("with a camera", b._cam != null and b._cam.current)
	var pos := b._cam.position
	await secs(0.5)
	check("that circles", b._cam.position != pos)
	b.queue_free()
	await frames(2)


func t_in_game() -> void:
	print("-- in the game")
	WorldState.clear()
	SaveSession.begin_new_game(0, true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	var clock := wm.clock
	clock.apply_now()
	check("the world's sky is the new one", clock._sky_mat != null and clock._env.sky.sky_material == clock._sky_mat)
	check("fog doesn't hide the sky", clock._env.fog_sky_affect < 0.5)
	clock.set_time(13.0, clock.day)
	clock.apply_now()
	var noon := float(clock._sky_mat.get_shader_parameter("day"))
	clock.set_time(1.0, clock.day + 1)
	clock.apply_now()
	var night := float(clock._sky_mat.get_shader_parameter("day"))
	check("the sky follows the day", noon > 0.8 and night < 0.2, "%f / %f" % [noon, night])
	check("and the moon's phase", absf(float(clock._sky_mat.get_shader_parameter("moon_phase")) - clock.get_moon_phase()) < 0.001)
	clock.set_time(19.0, clock.day)
	clock.apply_now()
	check("dusk colours the sky", float(clock._sky_mat.get_shader_parameter("dusk")) > 0.0)
	# Footsteps
	var sfx := player.get_node("SoundFX") as SoundFX
	player.get_node("DebugConsole").run("tp kingsreach")
	await secs(1.5)
	check("town streets ring like stone", sfx.surface() == "stone", sfx.surface())
	player.global_position += Vector3(600, 0, 0)
	player.global_position.y = wm.map.get_height(player.global_position.x, player.global_position.z) + 1.0
	await frames(2)
	check("out in the land the ground fits the biome", sfx.surface() in ["grass", "sand", "snow", "water"], sfx.surface())
	# Voices
	var rng := RandomNumberGenerator.new()
	var wolf := Population.spawn_enemy(load("res://data/enemies/wolf.tres"), 3, wm, player.global_position + Vector3(0, 1, 15), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	var skel := Population.spawn_enemy(load("res://data/enemies/skeleton.tres"), 3, wm, player.global_position + Vector3(3, 1, 15), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	var bandit := Population.spawn_enemy(load("res://data/enemies/bandit.tres"), 3, wm, player.global_position + Vector3(-3, 1, 15), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	await frames(2)
	check("wolves growl, the dead groan, bandits shout", SoundFX.voice_of(wolf) == "growl" and SoundFX.voice_of(skel) == "groan" and SoundFX.voice_of(bandit) == "shout")
	# Blood (in headless nothing is drawn, so this checks who bleeds)
	check("the living bleed, skeletons don't", HitFX.bleeds(wolf) and not HitFX.bleeds(skel))
	var hp := (wolf.get_node("Stats") as Stats).health
	var d := DamageInfo.new()
	d.amount = 5.0
	wolf.combat.take_damage(d)
	check("hits still land as before", (wolf.get_node("Stats") as Stats).health < hp)
	for e in [wolf, skel, bandit]:
		e.queue_free()
