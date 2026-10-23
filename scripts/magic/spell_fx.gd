class_name SpellFX
extends RefCounted
## The looks of magic, all built from simple shapes and particles: glowing orbs, bursts, beams,
## sprays. Nothing here changes the game, it only shows what happened.

static var _mats := {}


## A glowing unshaded material in this color (shared per color)
static func glow_material(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## A sphere of light that swells and fades (explosions, casting on yourself, summons)
static func burst(anchor: Node, at: Vector3, radius: float, color: Color) -> void:
	if anchor == null or not anchor.is_inside_tree():
		return
	var host: Node = anchor.get_tree().current_scene
	if host == null:
		return
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	ball.mesh = mesh
	var mat := glow_material(color, 0.45).duplicate() as StandardMaterial3D
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * maxf(radius, 0.4) * 0.2
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = maxf(radius, 1.0) * 2.5
	ball.add_child(light)
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * maxf(radius, 0.4), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.chain().tween_callback(ball.queue_free)


## A thin bright line from a to b that fades (beam spells)
static func beam(anchor: Node, a: Vector3, b: Vector3, color: Color) -> void:
	if anchor == null or not anchor.is_inside_tree() or a.distance_to(b) < 0.05:
		return
	var host: Node = anchor.get_tree().current_scene
	var line := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var length := a.distance_to(b)
	mesh.top_radius = 0.05
	mesh.bottom_radius = 0.05
	mesh.height = length
	mesh.radial_segments = 6
	mesh.rings = 1
	line.mesh = mesh
	var mat := glow_material(color, 0.9).duplicate() as StandardMaterial3D
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(line)
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI * 0.5)
	line.global_transform = Transform3D(basis, mid)
	var tw := line.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(line.queue_free)
	burst(anchor, b, 0.6, color)


## A cone of glowing particles (spray spells), pointing along -Z of its parent. Set emitting.
static func make_spray(color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 0.45
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 14.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color = color
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := glow_material(color, 0.75).duplicate() as StandardMaterial3D
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-4, -4, -9), Vector3(8, 8, 10))
	return p


## A small glowing orb with a light (projectiles, a charged hand)
static func orb(color: Color, radius: float = 0.15, light_range: float = 4.0) -> Node3D:
	var root := Node3D.new()
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	ball.mesh = mesh
	ball.material_override = glow_material(color)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = light_range
	root.add_child(light)
	return root
