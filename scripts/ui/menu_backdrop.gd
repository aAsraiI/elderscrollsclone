class_name MenuBackdrop
extends Node3D
## The main menu's backdrop, built in code: a ruined keep on a crag above a misty valley at dusk,
## standing stones, a campfire, the game's sky (two moons rising), and a camera that circles
## slowly. The menu's buttons are drawn over it.

const ORBIT_SPEED := 0.03
const RADIUS := 42.0

var _cam: Camera3D
var _fire: OmniLight3D
var _angle := 0.6
var _t := 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader") as Shader
	sm.set_shader_parameter("day", 0.35)
	sm.set_shader_parameter("dusk", 0.9)
	sm.set_shader_parameter("cloud_cover", 0.45)
	sm.set_shader_parameter("time_of_world", 300.0)
	sm.set_shader_parameter("moon_dir", Vector3(-0.5, 0.25, -0.8))
	sm.set_shader_parameter("moon2_dir", Vector3(-0.2, 0.18, -0.95))
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.24, 0.24)
	env.fog_density = 0.0035
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.58, 0.35)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(-120.0), 0.0)
	add_child(sun)
	_ground()
	_keep()
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.current = true
	add_child(_cam)
	_place_camera()


func _process(delta: float) -> void:
	_t += delta
	_angle += delta * ORBIT_SPEED
	_place_camera()
	if _fire != null:
		_fire.light_energy = 1.6 + sin(_t * 11.0) * 0.25 + sin(_t * 23.0) * 0.15


func _place_camera() -> void:
	if _cam == null:
		return
	_cam.position = Vector3(cos(_angle) * RADIUS, 12.0 + sin(_t * 0.2) * 0.6, sin(_angle) * RADIUS)
	_cam.look_at(Vector3(0, 6.0, 0), Vector3.UP)


func _mat(c: Color) -> Material:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/built.gdshader") as Shader
	m.set_shader_parameter("use_vertex_color", false)
	m.set_shader_parameter("base_color", c)
	return m


func _box(size: Vector3, at: Vector3, c: Color, yaw: float = 0.0, tilt: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = at
	mi.rotation = Vector3(tilt.x, yaw, tilt.z)
	add_child(mi)


# A wide valley floor and the crag the keep stands on, from noise
func _ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.02
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 80
	var step := 4.0
	var h := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length()
		var crag := maxf(0.0, 1.0 - d / 22.0) * 7.0
		return noise.get_noise_2d(x, z) * 6.0 + crag - minf(d / 60.0, 1.0) * 3.0
	for i in n:
		for j in n:
			var x0 := (float(i) - n * 0.5) * step
			var z0 := (float(j) - n * 0.5) * step
			var quad := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for q in quad.size():
				quad[q].y = h.call(quad[q].x, quad[q].z)
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[idx]
				var grass := Color(0.27, 0.3, 0.17).lerp(Color(0.38, 0.33, 0.24), clampf(noise.get_noise_2d(v.x * 3.0, v.z * 3.0) + 0.3, 0.0, 1.0))
				st.set_color(grass)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader") as Shader
	mi.material_override = m
	add_child(mi)


# The ruined keep, its broken wall, standing stones and a campfire
func _keep() -> void:
	var stone := Color(0.42, 0.4, 0.37)
	var base := 7.0
	_box(Vector3(8, 12, 8), Vector3(0, base + 6.0, 0), stone)
	_box(Vector3(8.6, 0.6, 8.6), Vector3(0, base + 12.3, 0), stone.darkened(0.2))
	for i in 4:
		var a := float(i) * PI * 0.5
		_box(Vector3(1.4, 1.4, 1.4), Vector3(cos(a) * 3.6, base + 13.2, sin(a) * 3.6), stone.darkened(0.1))
	_box(Vector3(1.6, 3.0, 0.3), Vector3(0, base + 1.5, -4.05), Color(0.2, 0.13, 0.08))
	_box(Vector3(4, 16, 4), Vector3(6.0, base + 6.0, 4.0), stone.darkened(0.05))
	_box(Vector3(4.4, 3.0, 4.4), Vector3(6.0, base + 15.5, 4.0), Color(0.25, 0.14, 0.1), 0.0, Vector3(0.0, 0.0, 0.08))
	for k in 6:
		var a := -0.6 + float(k) * 0.42
		var hgt := 2.5 + absf(sin(float(k) * 2.3)) * 3.5
		_box(Vector3(3.6, hgt, 1.0), Vector3(cos(a) * 13.0, base - 1.0 + hgt * 0.5, sin(a) * 13.0), stone.darkened(0.15), -a + PI * 0.5)
	for k in 7:
		var a := float(k) / 7.0 * TAU
		_box(Vector3(1.0, 3.4, 0.7), Vector3(cos(a) * 7.0 - 26.0, 0.8, sin(a) * 7.0 + 18.0), Color(0.36, 0.36, 0.34), -a, Vector3(0.05, 0, -0.04))
	# The campfire
	var fire_at := Vector3(-6.0, base + 0.3, -9.0)
	_box(Vector3(1.4, 0.3, 1.4), fire_at, Color(0.15, 0.14, 0.13))
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.35
	fm.height = 0.9
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.55, 0.15)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.5, 0.15)
	fmat.emission_energy_multiplier = 3.0
	fm.material = fmat
	flame.mesh = fm
	flame.position = fire_at + Vector3(0, 0.5, 0)
	add_child(flame)
	_fire = OmniLight3D.new()
	_fire.light_color = Color(1.0, 0.55, 0.25)
	_fire.omni_range = 9.0
	_fire.position = fire_at + Vector3(0, 1.0, 0)
	add_child(_fire)
