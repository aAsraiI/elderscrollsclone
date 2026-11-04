class_name WorldMarks
extends Node
## Alpha 1.24: the world shows where things happened, and you can hear what goes on in it.
##   footprints   you leave prints in snow, sand and swamp mud; they fade in a minute or two
##   blood        a body leaves a dark stain under it that fades over a day
##   breath       your breath fogs in the cold, quicker when you are out of breath
##   sounds       a fight you can't see (steel on steel), someone screaming as they run, wolves
##                howling at dusk (TownSociety sounds the horn when a town is attacked)
## One multimesh for every print, a handful of stains, one particle puff: costs next to nothing.
## Created by WorldManager.

const PRINT_STEP := 0.85
const PRINTS := 90
const PRINT_LIFE := 100.0
const STAIN_HOURS := 24.0
const MAX_STAINS := 24
const COLD_LANDS := ["tundra", "snow_mountains", "frozen_crown"]

var world: WorldManager
var _player: Node3D
var _prints: MultiMeshInstance3D
var _print_i := 0
var _print_born := PackedFloat32Array()
var _last_print := Vector3.INF
var _left := false
var _stains: Array = []  # [MeshInstance3D, game hour made]
var _breath: GPUParticles3D
var _breath_t := 0.0
var _sound_t := 0.0
var _clock := 0.0
var _howled := {}  # group -> day
var _fade_t := 0.0


func _ready() -> void:
	add_to_group("world_marks")
	world = get_parent() as WorldManager
	_print_born.resize(PRINTS)
	_print_born.fill(-1000.0)


func _process(delta: float) -> void:
	_clock += delta
	if world == null or get_tree().paused:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var inside := world.dungeons != null and world.dungeons.is_inside()
	if not inside:
		_footprints()
	_breathe(delta, inside)
	_fade_t -= delta
	if _fade_t <= 0.0:
		_fade_t = 1.0
		_fade_prints()
		_blood()
		_blood_trails()
	_sound_t -= delta
	if _sound_t <= 0.0:
		_sound_t = 1.5
		_sounds(inside)


# ---------------------------------------------------------------- footprints

func _footprints() -> void:
	var p := _player.global_position
	if _last_print.is_finite() and Vector2(p.x - _last_print.x, p.z - _last_print.z).length() < PRINT_STEP:
		return
	var moved := _last_print.is_finite()
	var from := _last_print
	_last_print = p
	if not moved or not (_player is CharacterBody3D) or not (_player as CharacterBody3D).is_on_floor():
		return
	if not _soft_ground(p):
		return
	if _prints == null:
		_prints = _make_prints()
		world.add_child(_prints)
	var dir := Vector3(p.x - from.x, 0.0, p.z - from.z).normalized()
	var side := dir.cross(Vector3.UP) * (0.13 if _left else -0.13)
	_left = not _left
	var at := Vector3(p.x, world.get_height_at(p.x, p.z) + 0.03, p.z) + side
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
	_prints.multimesh.set_instance_transform(_print_i, Transform3D(basis, at))
	_prints.multimesh.set_instance_color(_print_i, Color(0, 0, 0, 0.55))
	_print_born[_print_i] = _clock
	_print_i = (_print_i + 1) % PRINTS


func _soft_ground(p: Vector3) -> bool:
	var sfx := get_tree().get_first_node_in_group("sound_fx")
	var s := String(sfx.call("surface")) if sfx != null and sfx.has_method("surface") else "grass"
	if s == "snow" or s == "sand":
		return true
	var b := world.get_biome_at(p.x, p.z)
	return b != null and String(b.id) == "swamp"


func _make_prints() -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.3)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.25, 0.22, 0.2)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = PRINTS
	for i in PRINTS:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -10000, 0)))
		mm.set_instance_color(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Footprints"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-100000, -1000, -100000), Vector3(200000, 2000, 200000))
	return mmi


func _fade_prints() -> void:
	if _prints == null:
		return
	for i in PRINTS:
		var age := _clock - _print_born[i]
		if age < 0.0 or age > PRINT_LIFE + 2.0:
			continue
		_prints.multimesh.set_instance_color(i, Color(0, 0, 0, clampf(0.55 * (1.0 - age / PRINT_LIFE), 0.0, 0.55)))


# ---------------------------------------------------------------- blood

func _hours() -> float:
	return float(world.clock.day) * 24.0 + world.clock.hour if world.clock != null else _clock / 60.0


func _blood() -> void:
	var now := _hours()
	for n in get_tree().get_nodes_in_group("persistent"):
		var e := n as Enemy
		if e == null or not e.is_dead() or e.has_meta("stained") or not e.is_inside_tree():
			continue
		if e.global_position.distance_to(_player.global_position) > 60.0 or e.body_kind == CreatureBody.Kind.SPIRIT:
			continue
		e.set_meta("stained", true)
		var mi := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = randf_range(0.45, 0.8) * maxf(e.body_scale, 0.6)
		disc.bottom_radius = disc.top_radius
		disc.height = 0.01
		disc.radial_segments = 12
		mi.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.02, 0.02, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.3
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		var at := e.global_position
		mi.global_position = Vector3(at.x, (world.get_height_at(at.x, at.z) if not (world.dungeons != null and world.dungeons.is_inside()) else at.y) + 0.02, at.z)
		_stains.append([mi, now])
	# stains fade over a day; the oldest go when there are too many
	var keep: Array = []
	for s in _stains:
		var mi := s[0] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var age := now - float(s[1])
		if age > STAIN_HOURS:
			mi.queue_free()
			continue
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - age / STAIN_HOURS)
		keep.append(s)
	while keep.size() > MAX_STAINS:
		(keep.pop_front()[0] as MeshInstance3D).queue_free()
	_stains = keep


# ---------------------------------------------------------------- breath

func _breathe(delta: float, inside: bool) -> void:
	_breath_t -= delta
	if _breath_t > 0.0:
		return
	var stats := _player.get_node_or_null("Stats") as Stats
	var winded := stats != null and stats.stamina < stats.get_stat("max_stamina") * 0.25
	_breath_t = 1.1 if winded else 2.8
	if inside or not _cold():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _breath == null:
		_breath = _make_breath()
		cam.add_child(_breath)
	_breath.restart()


func _cold() -> bool:
	var p := _player.global_position
	var b := world.get_biome_at(p.x, p.z)
	if b != null and COLD_LANDS.has(String(b.id)):
		return true
	var winter := world.clock != null and world.clock.get_season() == 0
	var night := world.clock != null and world.clock.is_night()
	return (winter and night) or p.y > 160.0


func _make_breath() -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.name = "Breath"
	g.one_shot = true
	g.amount = 10
	g.lifetime = 1.4
	g.explosiveness = 0.7
	g.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.2, -1)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.08, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.22))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	g.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	g.draw_pass_1 = quad
	g.position = Vector3(0, -0.12, -0.35)
	return g


# ---------------------------------------------------------------- sounds you can read

func _sounds(inside: bool) -> void:
	var p := _player.global_position
	# a fight out of sight: steel on steel
	var clashes := 0
	for e in ActorRegistry.near(p, 90.0):
		if e.is_dead() or e.state != Enemy.State.ATTACK or clashes >= 2:
			continue
		var t := e.get_fight_target()
		if t == null or t.is_in_group("player") or e.global_position.distance_to(p) < 20.0:
			continue
		if e.combat != null and e.combat.get_phase() == MeleeCombat.Phase.ACTIVE:
			SoundFX.at(get_tree(), e.global_position + Vector3.UP, "clang", 90.0, randf_range(0.9, 1.1))
			clashes += 1
	# someone screaming as they run
	for e in ActorRegistry.near(p, 70.0):
		if e.is_dead() or e.state != Enemy.State.FLEE or not e.has_meta("npc_id"):
			if is_instance_valid(e) and e.state != Enemy.State.FLEE and e.has_meta("screamed"):
				e.remove_meta("screamed")
			continue
		if not e.has_meta("screamed"):
			e.set_meta("screamed", true)
			SoundFX.at(get_tree(), e.global_position + Vector3.UP * 1.5, "scream", 80.0, randf_range(0.85, 1.2))
	# wolves at dusk
	if inside or world.clock == null:
		return
	var h := world.clock.hour
	if not ((h >= 18.5 and h < 21.0) or (h >= 4.0 and h < 5.5)):
		return
	var wl := get_tree().get_first_node_in_group("wild_life") as WildLife
	if wl == null:
		return
	for g in wl.groups:
		if not (String(g["kind"]) in ["wolf", "ash_hound"]):
			continue
		var lead: Enemy = g["leader"]
		if lead == null or not is_instance_valid(lead) or lead.is_dead():
			continue
		var key := lead.get_instance_id()
		if int(_howled.get(key, -1)) == world.clock.day:
			continue
		_howled[key] = world.clock.day
		SoundFX.at(get_tree(), lead.global_position + Vector3.UP, "howl", 260.0, randf_range(0.9, 1.1))
		return


# ---------------------------------------------------------------- blood trails (1.24.10)

const DROPS := 60
var _drops: MultiMeshInstance3D
var _drop_i := 0
var _drop_born := PackedFloat32Array()
var _drop_last := {}  # animal id -> where it last bled


## A wounded animal running away leaves drops of blood to follow
func _blood_trails() -> void:
	if world.dungeons != null and world.dungeons.is_inside():
		return
	for e in ActorRegistry.near(_player.global_position, 90.0):
		if not e.has_meta("wild") or e.is_dead() or e.state != Enemy.State.FLEE:
			continue
		if e.stats.health > e.stats.get_stat("max_health") * 0.85:
			continue
		var id := e.get_instance_id()
		var last: Vector3 = _drop_last.get(id, Vector3.INF)
		if last.is_finite() and last.distance_to(e.global_position) < 1.5:
			continue
		_drop_last[id] = e.global_position
		_drop(e.global_position)
	if _drops != null:
		for i in DROPS:
			var age := _clock - _drop_born[i]
			if age >= 0.0 and age < 182.0:
				_drops.multimesh.set_instance_color(i, Color(0.35, 0.02, 0.02, clampf(0.9 * (1.0 - age / 180.0), 0.0, 0.9)))


func _drop(at: Vector3) -> void:
	if _drops == null:
		_drop_born.resize(DROPS)
		_drop_born.fill(-1000.0)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.16, 0.16)
		quad.orientation = PlaneMesh.FACE_Y
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = DROPS
		for i in DROPS:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -10000, 0)))
			mm.set_instance_color(i, Color(0, 0, 0, 0))
		_drops = MultiMeshInstance3D.new()
		_drops.name = "BloodTrail"
		_drops.multimesh = mm
		_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drops.custom_aabb = AABB(Vector3(-100000, -1000, -100000), Vector3(200000, 2000, 200000))
		world.add_child(_drops)
	var g := Vector3(at.x + randf_range(-0.2, 0.2), world.get_height_at(at.x, at.z) + 0.03, at.z + randf_range(-0.2, 0.2))
	_drops.multimesh.set_instance_transform(_drop_i, Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.6, 1.3)), g))
	_drops.multimesh.set_instance_color(_drop_i, Color(0.35, 0.02, 0.02, 0.9))
	_drop_born[_drop_i] = _clock
	_drop_i = (_drop_i + 1) % DROPS
