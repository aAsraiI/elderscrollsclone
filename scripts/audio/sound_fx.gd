class_name SoundFX
extends Node
## Plays the game's sounds and music. Lives under the Player (player.gd adds it).
##   effects  swings, hits, blocks, getting hurt, spells, bows, footsteps, picking things up,
##            thunder and rain (made by Synth unless real files are in res://audio/)
##   music    a slow pad that follows the mood: day, town, night, dungeon, or combat when something is
##            hunting you; tracks are made in the background and cross-fade
## Volumes: Settings > Audio (Master, Music, Sound effects).

var _player: Node3D
var _music: Array[AudioStreamPlayer] = []
var _music_cur := 0
var _mood := ""
var _tracks := {}
var _task := -1
var _task_mood := ""
var _rain: AudioStreamPlayer
var _step_timer := 0.0
var _mood_timer := 0.0
var _last_flash := 0.0


func _ready() -> void:
	_player = get_parent() as Node3D
	add_to_group("settings_listener")
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_rain = AudioStreamPlayer.new()
	_rain.volume_db = -80.0
	add_child(_rain)
	_connect.call_deferred()


func _connect() -> void:
	var combat := _player.get_node_or_null("MeleeCombat") as MeleeCombat
	if combat != null:
		combat.attack_started.connect(func(_h: int, _w: ItemData) -> void: play("swing_heavy" if combat.is_heavy_action() else "swing", 0.15))
		combat.hit_dealt.connect(func(_t: Node, _i: DamageInfo, _f: float) -> void: play("hit"))
		combat.blocked.connect(func(_i: DamageInfo, _a: float) -> void: play("block"))
		combat.parried.connect(func(_i: DamageInfo) -> void: play("block", 0.0, 1.4))
		combat.damaged.connect(func(_i: DamageInfo, f: float) -> void:
			if f > 0.5:
				play("hurt"))
	var caster := _player.get_node_or_null("SpellCaster") as SpellCaster
	if caster != null:
		caster.spell_cast.connect(func(s: SpellData) -> void: play("boom" if s.get_area() > 0.0 else "cast", 0.1))
	var ranged := _player.get_node_or_null("RangedCombat") as RangedCombat
	if ranged != null:
		ranged.shot.connect(func(_a: Arrow) -> void: play("twang", 0.1))
	var inv := _player.get_node_or_null("Inventory") as Inventory
	if inv != null:
		var last := [inv.get_total_weight()]
		inv.changed.connect(func() -> void:
			if inv.get_total_weight() > float(last[0]) and not get_tree().paused:
				play("pickup", 0.0)
			last[0] = inv.get_total_weight())
	var skills := _player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.player_leveled_up.connect(func(_l: int) -> void: play("level_up"))


func _vol(key: String) -> float:
	return clampf(float(GameSettings.get_value(key)), 0.0001, 1.0)


## The voice a creature makes (by its EnemyData id), "" for none
static func voice_of(e: Enemy) -> String:
	match e.enemy_id:
		"dragon":
			return "roar"
		"wolf", "ash_hound", "frost_bear", "werewolf", "bog_lurker", "cave_troll", "forest_troll", "frost_giant", "dune_stalker":
			return "growl"
		"harpy", "giant_rat":
			return "screech"
		"giant_spider", "sand_scorpion", "deep_crawler", "crawler_queen":
			return "hiss"
		"skeleton", "skeleton_knight", "barrow_wight", "wight_lord", "crypt_warden", "grave_ghoul", "drowned_sailor", "vampire":
			return "groan"
		"fire_spirit", "ice_wraith", "vault_sentinel", "vault_guardian":
			return ""
	return "shout" if e.body_kind == CreatureBody.Kind.HUMANOID else "grunt"


## A creature's call where it stands (heard in 3D), pitched to its size
static func bark(e: Enemy) -> void:
	var voice := voice_of(e)
	if voice == "" or not e.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var s := Synth.get_sound(voice)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 6.0 * maxf(e.body_scale, 1.0)
	p.max_distance = 60.0
	p.volume_db = linear_to_db(clampf(float(GameSettings.get_value("sfx_volume")), 0.0001, 1.0))
	p.pitch_scale = clampf(1.15 / maxf(e.body_scale, 0.5), 0.5, 1.6) * randf_range(0.9, 1.1)
	e.add_child(p)
	p.position = Vector3.UP * 1.2 * e.body_scale
	p.play()
	p.finished.connect(p.queue_free)


func apply_settings() -> void:
	pass  # read every frame through _vol()


## Plays a sound effect. pitch_jitter: random pitch spread so repeats don't sound the same
func play(sound: String, pitch_jitter: float = 0.08, pitch: float = 1.0) -> void:
	var s := Synth.get_sound(sound)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = linear_to_db(_vol("sfx_volume"))
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _process(delta: float) -> void:
	_footsteps(delta)
	_weather_sounds()
	_mood_timer -= delta
	if _mood_timer <= 0.0:
		_mood_timer = 2.0
		_update_mood()
	_poll_task()
	# Cross-fade the music
	var target := linear_to_db(_vol("music_volume") * 0.6)
	for i in _music.size():
		var m := _music[i]
		var want := target if i == _music_cur and m.stream != null else -60.0
		m.volume_db = move_toward(m.volume_db, want, delta * 12.0)
		if m.volume_db <= -59.0 and m.playing and i != _music_cur:
			m.stop()


func _footsteps(delta: float) -> void:
	var cb := _player as CharacterBody3D
	if cb == null or not cb.is_on_floor() or get_tree().paused:
		return
	var speed := Vector2(cb.velocity.x, cb.velocity.z).length()
	if speed < 1.0:
		_step_timer = 0.1
		return
	_step_timer -= delta * speed / 2.2
	if _step_timer <= 0.0:
		_step_timer = 0.55
		var stealth := _player.get_node_or_null("Stealth") as Stealth
		if stealth != null and stealth.sneaking:
			return
		play("step_" + surface(), 0.2, 0.8 if _player.has_meta("riding") else 1.0)


## What the player is walking on: stone, wood, water, snow, sand or grass
func surface() -> String:
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		return "wood" if dm.is_in_building() else "stone"
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world == null:
		return "grass"
	var p := _player.global_position
	if world.settings.water_enabled and p.y < world.settings.sea_level + 0.25:
		return "water"
	if world.get_town_at(p, 0.0) != null:
		return "stone"
	var w := Weather.get_instance(get_tree())
	if w != null and w.snow_cover > 0.5:
		return "snow"
	var biome := world.map.get_biome_at(p.x, p.z)
	var id := String(biome.id) if biome != null else ""
	if id in ["snow_mountains", "tundra", "frozen_crown"]:
		return "snow"
	if id in ["desert", "coast"]:
		return "sand"
	return "grass"


func _weather_sounds() -> void:
	var w := Weather.get_instance(get_tree())
	var raining := w != null and w.enabled and (w.current == Weather.Kind.RAIN or w.current == Weather.Kind.STORM)
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		raining = false
	if raining and not _rain.playing:
		_rain.stream = Synth.get_sound("rain")
		_rain.play()
	_rain.volume_db = move_toward(_rain.volume_db, linear_to_db(_vol("sfx_volume") * 0.5) if raining else -60.0, 0.5)
	if not raining and _rain.volume_db <= -59.0 and _rain.playing:
		_rain.stop()
	if w != null and w.get_factors().get("flash", 0.0) > 1.0 and Time.get_ticks_msec() - _last_flash > 4000.0:
		_last_flash = Time.get_ticks_msec()
		get_tree().create_timer(randf_range(0.4, 2.0)).timeout.connect(func() -> void: play("thunder", 0.15))


func _update_mood() -> void:
	if DisplayServer.get_name() == "headless":
		return  # no one to hear it: don't spend threads making music
	var mood := "day"
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock != null and clock.is_night():
		mood = "night"
	else:
		var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
		if world != null and world.get_town_at(_player.global_position, 30.0) != null:
			mood = "town"
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside() and not dm.is_in_building():
		mood = "dungeon"
	for n in ActorRegistry.near(_player.global_position, 35.0):
		var e := n as Enemy
		if e != null and e.disposition == Enemy.Disposition.HOSTILE and e.is_alerted() and not e.is_dead() \
				and e.global_position.distance_to(_player.global_position) < 35.0:
			mood = "combat"
			break
	if mood == _mood:
		return
	_mood = mood
	if _tracks.has(mood):
		_switch_to(_tracks[mood])
	elif _task < 0:
		_task_mood = mood
		_task = WorkerThreadPool.add_task(func() -> void:
			var t := Synth.make_music(_task_mood)
			_tracks[_task_mood] = t, false, "music")


func _poll_task() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _tracks.has(_mood):
		_switch_to(_tracks[_mood])
	else:
		_mood = ""  # try again next time


func _switch_to(stream: AudioStream) -> void:
	_music_cur = 1 - _music_cur
	var m := _music[_music_cur]
	m.stream = stream
	m.volume_db = -60.0
	m.play()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
