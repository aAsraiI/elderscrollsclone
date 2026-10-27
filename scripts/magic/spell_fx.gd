class_name SpellFX
extends RefCounted
## The looks of magic: glowing orbs, bursts, beams, sprays and the glow of a hand holding a spell; drawn
## with Morrowind's own spell textures when imported (MwVfx: its sparks, flares and clouds for each element
## and school), else with simple shapes. Nothing here changes the game, it only shows what happened.

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
	sparkle(host, at, radius, color)


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
	quad.size = Vector2(0.3, 0.3)
	quad.material = sprite_material(MwVfx.look(look_of_color(color))[1], color)
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
	var tex: Texture2D = MwVfx.look(look_of_color(color))[0]
	if tex != null:
		# Morrowind's glow around the ball
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * radius * 5.0
		q.material = sprite_material(tex, color, false)
		halo.mesh = q
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(halo)
	return root


## Which look (element or school, MwVfx.LOOKS) a spell colour belongs to
static func look_of_color(color: Color) -> StringName:
	var best := &"destruction"
	var near := 99.0
	for table: Dictionary in [MagicEffects.ELEMENT_COLORS, MagicEffects.SCHOOL_COLORS]:
		for k in table:
			var c: Color = table[k]
			var d := Vector3(c.r - color.r, c.g - color.g, c.b - color.b).length()
			if d < near:
				near = d
				best = k
	return best


## A soft round dot (used where there is no Morrowind texture)
static func soft_texture() -> Texture2D:
	if not _mats.has("soft"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_mats["soft"] = t
	return _mats["soft"]


## A glowing, additive sprite in this colour (particles, or a single quad that faces you)
static func sprite_material(tex: Texture2D, color: Color, particles: bool = true) -> StandardMaterial3D:
	if tex == null:
		tex = soft_texture()
	var key := "spr|%d|%s|%s" % [tex.get_rid().get_id(), color.to_html(), particles]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_texture = tex
	m.albedo_color = color.lightened(0.15)
	m.vertex_color_use_as_albedo = particles
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if particles else BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## Sparks thrown out from a spell's hit, and a puff of its cloud (Morrowind's for its look)
static func sparkle(host: Node, at: Vector3, radius: float, color: Color) -> void:
	if host == null or DisplayServer.get_name() == "headless":
		return
	var look := MwVfx.look(look_of_color(color))
	var r := maxf(radius, 0.6)
	for part in [[look[1], 36, 0.12, 2.5 * r, 0.7], [look[2], 8, 0.6 * r, 0.6, 0.9]]:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 0.9
		p.amount = int(part[1])
		p.lifetime = float(part[4])
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.2 * r
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = float(part[3]) * 0.4
		pm.initial_velocity_max = float(part[3])
		pm.damping_min = 2.0
		pm.damping_max = 4.0
		pm.gravity = Vector3(0, -1.5, 0)
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		var ft := GradientTexture1D.new()
		ft.gradient = fade
		pm.color_ramp = ft
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(part[2])
		q.material = sprite_material(part[0], color)
		p.draw_pass_1 = q
		host.add_child(p)
		p.global_position = at
		p.emitting = true
		p.finished.connect(p.queue_free)


## The glow of a hand holding a spell: Morrowind's glow in the palm, motes drifting up from it, and a
## little light. set_hand_glow() swells it as the spell charges.
static func hand_glow(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "HandGlow"
	var look := MwVfx.look(look_of_color(color))
	var core := MeshInstance3D.new()
	core.name = "Core"
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	q.material = sprite_material(look[0], color, false)
	core.mesh = q
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = 28
	p.lifetime = 0.7
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, 0.25, 0)
	pm.angle_max = 360.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var mq := QuadMesh.new()
	mq.size = Vector2(0.035, 0.035)
	mq.material = sprite_material(look[1], color)
	p.draw_pass_1 = mq
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.omni_range = 1.6
	light.light_energy = 0.5
	root.add_child(light)
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = 1
	return root


## charge 0..1 while charging; channel while a spray or beam runs
static func set_hand_glow(glow: Node3D, charge: float, channel: bool, time: float, _delta: float) -> void:
	var power := maxf(charge, 1.0 if channel else 0.0)
	var core := glow.get_node_or_null("Core") as Node3D
	if core != null:
		core.scale = Vector3.ONE * (0.7 + power * 1.1 + sin(time * 7.0) * 0.08)
	var p := glow.get_node_or_null("Motes") as GPUParticles3D
	if p != null:
		p.amount_ratio = 0.35 + power * 0.65
	var light := glow.get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.light_energy = 0.4 + power * 1.4 + sin(time * 11.0) * 0.05
