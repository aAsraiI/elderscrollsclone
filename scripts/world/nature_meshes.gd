class_name NatureMeshes
extends RefCounted
## The meshes and materials of the ground cover (grass, flowers, rocks, bushes) and the terrain
## material, all made in code and shared by every chunk. Seasons and weather change a few shader
## values here once, and every chunk follows: autumn browns the grass, winter covers flat ground
## in snow, rain makes everything shine.

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform vec3 season_tint = vec3(1.0);
uniform float snow = 0.0;
uniform float wind = 1.0;
varying float tip;
void vertex() {
	tip = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) * 0.6 + sin(TIME * 3.1 + wp.x * 1.3) * 0.25;
	VERTEX.x += sway * 0.08 * wind * UV.y * UV.y;
	VERTEX.z += sway * 0.05 * wind * UV.y * UV.y;
	VERTEX.y *= 1.0 - snow * 0.75;
}
void fragment() {
	vec3 c = COLOR.rgb * season_tint;
	c = mix(c, vec3(0.9, 0.92, 0.96), snow * 0.8);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25) * tip;
}
"""

static var _grass_mesh: ArrayMesh
static var _flower_mesh: ArrayMesh
static var _rock_meshes: Array[Mesh] = []
static var _bush_mesh: Mesh
static var _grass_mat: ShaderMaterial
static var _flower_mat: ShaderMaterial
static var _terrain_mat: ShaderMaterial
static var _rock_mat: StandardMaterial3D
static var _bush_mat: ShaderMaterial
static var _season := {"tint": Vector3.ONE, "snow": 0.0, "wet": 0.0, "wind": 1.0}


static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://shaders/terrain.gdshader") as Shader  # rock on slopes, earth, detail
		_push()
	return _terrain_mat


static func grass_material() -> ShaderMaterial:
	if _grass_mat == null:
		var sh := Shader.new()
		sh.code = GRASS_SHADER
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = sh
		_flower_mat = ShaderMaterial.new()
		_flower_mat.shader = sh
		_bush_mat = ShaderMaterial.new()
		_bush_mat.shader = sh
		_push()
	return _grass_mat


static func flower_material() -> ShaderMaterial:
	grass_material()
	return _flower_mat


static func bush_material() -> ShaderMaterial:
	grass_material()
	return _bush_mat


static func rock_material() -> StandardMaterial3D:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.vertex_color_use_as_albedo = true
		_rock_mat.roughness = 0.95
	return _rock_mat


## Season and weather: tint (multiplies green things), snow 0..1, wetness 0..1, wind 0..2
static func set_conditions(tint: Vector3, snow: float, wet: float, wind: float) -> void:
	_season = {"tint": tint, "snow": snow, "wet": wet, "wind": wind}
	_push()


static func _push() -> void:
	for m in [_grass_mat, _flower_mat, _bush_mat]:
		if m != null:
			m.set_shader_parameter("season_tint", _season["tint"])
			m.set_shader_parameter("snow", _season["snow"])
			m.set_shader_parameter("wind", _season["wind"])
	if _flower_mat != null:
		_flower_mat.set_shader_parameter("season_tint", Vector3.ONE.lerp(_season["tint"], 0.5))
	if _terrain_mat != null:
		_terrain_mat.set_shader_parameter("season_tint", _season["tint"])
		_terrain_mat.set_shader_parameter("snow", _season["snow"])
		_terrain_mat.set_shader_parameter("wetness", _season["wet"])
	if _rock_mat != null:
		_rock_mat.roughness = lerpf(0.95, 0.45, float(_season["wet"]))


# ---------------------------------------------------------------- meshes

## A clump of 7 bent blades. UV.y = 0 at the root, 1 at the tip (the shader sways the tips).
static func grass_mesh() -> ArrayMesh:
	if _grass_mesh != null:
		return _grass_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b in 7:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.18
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := rng.randf_range(0.32, 0.62)
		var w := rng.randf_range(0.035, 0.055)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face)) * w
		var lean := Vector3(-sin(face), 0.0, cos(face)) * rng.randf_range(0.05, 0.16)
		var pts: Array[Vector3] = []
		var segs := 3
		for i in segs + 1:
			var t := float(i) / float(segs)
			var center := base + Vector3(0.0, h * t, 0.0) + lean * t * t
			var width := 1.0 - t
			pts.append(center - side * width)
			pts.append(center + side * width)
		for i in segs:
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			var c0 := Color(0.55 + 0.45 * t0, 0.55 + 0.45 * t0, 0.55 + 0.45 * t0)
			var c1 := Color(0.55 + 0.45 * t1, 0.55 + 0.45 * t1, 0.55 + 0.45 * t1)
			var a0 := pts[i * 2]
			var b0 := pts[i * 2 + 1]
			var a1 := pts[i * 2 + 2]
			var b1 := pts[i * 2 + 3]
			_tri(st, a0, b0, a1, c0, c0, c1, t0, t0, t1)
			_tri(st, b0, b1, a1, c0, c1, c1, t0, t1, t1)
	st.generate_normals()
	_grass_mesh = st.commit()
	return _grass_mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, ua: float, ub: float, uc: float) -> void:
	st.set_color(ca)
	st.set_uv(Vector2(0.0, ua))
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_uv(Vector2(1.0, ub))
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_uv(Vector2(0.5, uc))
	st.set_normal(Vector3.UP)
	st.add_vertex(c)


## A stem with a little colored head (the head takes the instance color)
static func flower_mesh() -> ArrayMesh:
	if _flower_mesh != null:
		return _flower_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.25, 0.45, 0.18)
	var h := 0.42
	_tri(st, Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), Vector3(0, h, 0), stem, stem, stem, 0.0, 0.0, 1.0)
	_tri(st, Vector3(0, 0, -0.012), Vector3(0, 0, 0.012), Vector3(0, h, 0), stem, stem, stem, 0.0, 0.0, 1.0)
	var white := Color(1, 1, 1)
	for i in 5:
		var a := float(i) / 5.0 * TAU
		var a2 := a + TAU / 10.0
		var p0 := Vector3(0, h, 0)
		var p1 := Vector3(cos(a) * 0.07, h + 0.02, sin(a) * 0.07)
		var p2 := Vector3(cos(a2) * 0.07, h + 0.02, sin(a2) * 0.07)
		_tri(st, p0, p1, p2, white, white, white, 1.0, 1.0, 1.0)
	st.generate_normals()
	var m := st.commit()
	_flower_mesh = m
	return _flower_mesh


## Three lumpy rocks (low spheres pulled out of shape), colored per instance
static func rock_mesh(variant: int) -> Mesh:
	if _rock_meshes.is_empty():
		for v in 3:
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 0.7 + 0.15 * v
			sphere.radial_segments = 7 + v
			sphere.rings = 4
			var arrays := sphere.get_mesh_arrays()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + v
			var bumps := {}
			for i in verts.size():
				var key := Vector3i(roundi(verts[i].x * 100.0), roundi(verts[i].y * 100.0), roundi(verts[i].z * 100.0))
				if not bumps.has(key):
					bumps[key] = rng.randf_range(0.8, 1.2)
				verts[i] *= float(bumps[key])
				if verts[i].y < -0.1:
					verts[i].y = -0.1 - (verts[i].y + 0.1) * 0.3  # flat bottom, sits in the ground
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = null
			arrays[Mesh.ARRAY_TANGENT] = null
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			st.generate_normals()
			var colors := PackedColorArray()
			colors.resize(verts.size())
			colors.fill(Color.WHITE)
			var mesh := st.commit()
			_rock_meshes.append(mesh)
	return _rock_meshes[variant % _rock_meshes.size()]


static func bush_mesh() -> Mesh:
	if _bush_mesh != null:
		return _bush_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# A ball of crossed leafy cards: cheap, and it sways with the grass shader
	for i in 6:
		var a := float(i) / 6.0 * PI
		var d := Vector3(cos(a), 0.0, sin(a)) * 0.7
		var y0 := 0.0
		var y1 := rng.randf_range(0.9, 1.2)
		var c0 := Color(0.6, 0.6, 0.6)
		var c1 := Color(1, 1, 1)
		_tri(st, -d + Vector3(0, y0, 0), d + Vector3(0, y0, 0), -d + Vector3(0, y1, 0), c0, c0, c1, 0.2, 0.2, 1.0)
		_tri(st, d + Vector3(0, y0, 0), d + Vector3(0, y1, 0), -d + Vector3(0, y1, 0), c0, c1, c1, 0.2, 1.0, 1.0)
	st.generate_normals()
	_bush_mesh = st.commit()
	return _bush_mesh
