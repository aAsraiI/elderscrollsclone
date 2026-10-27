class_name HitFX
extends RefCounted
## Marks a hit leaves in the world (MeleeCombat calls these for everyone, player and enemies):
##   blood   droplets streaking from where a blade or claw lands, a fine mist, and a dark stain on the
##           ground beneath (Morrowind's blood texture when imported)
##           (the stain a Decal that fades after a minute; skeletons, spirits and constructs don't bleed)
##   sparks  a burst of hot sparks where a blow is blocked or parried
## At most MAX_STAINS stains exist at once; the oldest goes first.

const MAX_STAINS := 24
const STAIN_LIFE := 60.0
## Creatures without blood (by EnemyData id)
const BLOODLESS := ["skeleton", "skeleton_knight", "barrow_wight", "wight_lord", "crypt_warden", "fire_spirit", "ice_wraith",
	"vault_sentinel", "vault_guardian"]

static var _stains: Array[Decal] = []
static var _stain_tex: Texture2D
static var _blood_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D


static func bleeds(target: Node) -> bool:
	return not (target is Enemy and BLOODLESS.has((target as Enemy).enemy_id))


## A spray of blood at `at` going along `dir`, and a stain on the floor below. `amount` 0..1+.
static func blood(tree: SceneTree, at: Vector3, dir: Vector3, amount: float) -> void:
	if tree == null or tree.current_scene == null or DisplayServer.get_name() == "headless":
		return
	var scene := tree.current_scene
	var along := (dir if dir.length() > 0.01 else Vector3.UP).normalized()
	# droplets that streak along their flight, thrown with the blow and falling
	var drops := _burst(maxi(int(14.0 + amount * 30.0), 8), 0.8, _blood_streak(), Vector3(0.025, 0.09, 1.0), true)
	var pm := drops.process_material as ParticleProcessMaterial
	pm.direction = along + Vector3(0, 0.35, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 3.2 + amount * 2.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	scene.add_child(drops)
	drops.global_position = at
	drops.emitting = true
	# a fine red mist where it landed
	var mist := _burst(maxi(int(4.0 + amount * 6.0), 3), 0.45, _blood_mist(), Vector3(0.22, 0.22, 1.0))
	var mm := mist.process_material as ParticleProcessMaterial
	mm.direction = along
	mm.spread = 50.0
	mm.initial_velocity_min = 0.3
	mm.initial_velocity_max = 0.9
	mm.gravity = Vector3(0, -0.6, 0)
	mm.scale_min = 0.7
	mm.scale_max = 1.6 + amount
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	mm.color_ramp = ft
	scene.add_child(mist)
	mist.global_position = at
	mist.emitting = true
	tree.create_timer(1.4, false).timeout.connect(func() -> void:
		drops.queue_free()
		mist.queue_free())
	_stain(tree, at, amount)


## Hot sparks where steel meets steel
static func sparks(tree: SceneTree, at: Vector3) -> void:
	if tree == null or tree.current_scene == null or DisplayServer.get_name() == "headless":
		return
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.albedo_color = Color(1.0, 0.75, 0.3)
		_spark_mat.emission_enabled = true
		_spark_mat.emission = Color(1.0, 0.6, 0.2)
		_spark_mat.emission_energy_multiplier = 4.0
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mw := MwVfx.texture("vfx_alpha_spark")
		_spark_mat.albedo_texture = mw if mw != null else SpellFX.soft_texture()
	var p := _burst(22, 0.35, _spark_mat, Vector3(0.03, 0.16, 1.0), true)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -12.0, 0)
	tree.current_scene.add_child(p)
	p.global_position = at
	p.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.65, 0.3)
	flash.light_energy = 2.0
	flash.omni_range = 3.0
	tree.current_scene.add_child(flash)
	flash.global_position = at
	flash.create_tween().tween_property(flash, "light_energy", 0.0, 0.15)
	tree.create_timer(0.8, false).timeout.connect(func() -> void:
		p.queue_free()
		flash.queue_free())


# size.z == 1: a flat sprite (size.x by size.y) that faces you; `streak`: stretched along its flight
static func _burst(amount: int, life: float, mat: Material, size: Vector3, streak: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	var mesh: PrimitiveMesh
	if size.z == 1.0:
		var q := QuadMesh.new()
		q.size = Vector2(size.x, size.y)
		mesh = q
	else:
		var b := BoxMesh.new()
		b.size = size
		mesh = b
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if streak:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	return p


# Morrowind's blood (tx_blood) when imported, else a soft dark red
static func _blood_streak() -> StandardMaterial3D:
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.albedo_color = Color(0.45, 0.03, 0.03)
		_blood_mat.roughness = 0.25
		_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blood_mat.albedo_texture = SpellFX.soft_texture()
		_blood_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mw := MwVfx.texture("tx_blood")
		if mw != null:
			_blood_mat.detail_enabled = true
			_blood_mat.detail_albedo = mw
			_blood_mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	return _blood_mat


static var _mist_mat: StandardMaterial3D


static func _blood_mist() -> StandardMaterial3D:
	if _mist_mat == null:
		_mist_mat = StandardMaterial3D.new()
		_mist_mat.albedo_color = Color(0.35, 0.02, 0.02, 0.55)
		_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mist_mat.albedo_texture = SpellFX.soft_texture()
		_mist_mat.vertex_color_use_as_albedo = true
		_mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mist_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _mist_mat


# A dark stain on whatever is below the hit
static func _stain(tree: SceneTree, at: Vector3, amount: float) -> void:
	var space := (tree.current_scene as Node3D).get_world_3d().direct_space_state if tree.current_scene is Node3D else null
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var d := Decal.new()
	d.texture_albedo = _stain_texture()
	d.modulate = Color(0.3, 0.02, 0.02, 0.85)
	var s := 0.5 + amount * 0.6 + randf() * 0.3
	d.size = Vector3(s, 0.6, s)
	d.cull_mask = 1
	tree.current_scene.add_child(d)
	d.global_position = hit["position"]
	d.rotation.y = randf() * TAU
	# Stains from an earlier game are already gone (loading or quitting to the menu frees the scene),
	# and reading a freed one into a typed variable is an error, so drop those first
	for i in range(_stains.size() - 1, -1, -1):
		if not is_instance_valid(_stains[i]):
			_stains.remove_at(i)
	_stains.append(d)
	while _stains.size() > MAX_STAINS:
		_stains.pop_front().queue_free()
	var t := d.create_tween()
	t.tween_interval(STAIN_LIFE)
	t.tween_property(d, "modulate:a", 0.0, 4.0)
	t.tween_callback(func() -> void:
		_stains.erase(d)
		d.queue_free())


# A splash: a soft blob with a ragged edge, made once
static func _stain_texture() -> Texture2D:
	if _stain_tex != null:
		return _stain_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	for y in size:
		for x in size:
			var v := Vector2(x - size * 0.5, y - size * 0.5) / (size * 0.5)
			var r := v.length() + noise.get_noise_2d(x, y) * 0.45
			var a := clampf((0.85 - r) * 4.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_stain_tex = ImageTexture.create_from_image(img)
	return _stain_tex
