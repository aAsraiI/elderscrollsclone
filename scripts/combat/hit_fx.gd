class_name HitFX
extends RefCounted
## Marks a hit leaves in the world (MeleeCombat calls these for everyone, player and enemies):
##   blood   a short spray where a blade or claw lands, and a dark stain on the ground beneath
##           (a Decal that fades after a minute; skeletons, spirits and constructs don't bleed)
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
	var p := _burst(maxi(int(10.0 + amount * 18.0), 6), 0.5, _blood_material(), Vector3(0.035, 0.035, 0.035))
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = (dir if dir.length() > 0.01 else Vector3.UP).normalized() + Vector3(0, 0.4, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 2.5 + amount * 1.5
	pm.gravity = Vector3(0, -9.8, 0)
	scene.add_child(p)
	p.global_position = at
	p.emitting = true
	tree.create_timer(1.2, false).timeout.connect(p.queue_free)
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
	var p := _burst(18, 0.35, _spark_mat, Vector3(0.025, 0.025, 0.12))
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


static func _burst(amount: int, life: float, mat: Material, size: Vector3) -> GPUParticles3D:
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
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p


static func _blood_material() -> StandardMaterial3D:
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.albedo_color = Color(0.32, 0.02, 0.02)
		_blood_mat.roughness = 0.3
	return _blood_mat


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
	_stains.append(d)
	while _stains.size() > MAX_STAINS:
		var old: Decal = _stains.pop_front()
		if is_instance_valid(old):
			old.queue_free()
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
