class_name FarLand
extends Node3D
## Level of detail for the land past the view distance: one coarse terrain mesh REACH meters
## around the player (a vertex every STEP meters, coloured by biome, water blue), sunk SINK meters
## so the detailed chunks always sit on top of it, and a block outline of every town out there
## (its buildings as plain boxes) until the real town loads in. Rebuilt on a worker thread when the
## player has moved REBUILD_AFTER meters. WorldManager makes it in the real game (follow_video_settings).

const REACH := 3200.0
const STEP := 50.0
const SINK := 3.0
const REBUILD_AFTER := 500.0
const WATER := Color(0.16, 0.3, 0.42)

var world: WorldManager
var _mesh: MeshInstance3D
var _center := Vector3.INF
var _task := -1
var _result := {}
var _mutex := Mutex.new()
var _towns := {}  # town id -> MeshInstance3D (the outline)
var _timer := 0.0


func _ready() -> void:
	world = get_parent() as WorldManager
	_mesh = MeshInstance3D.new()
	_mesh.name = "FarTerrain"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	_mesh.material_override = mat
	add_child(_mesh)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if world == null or world.map == null or world.player == null or not is_instance_valid(world.player):
		return
	var dm := world.dungeons
	visible = dm == null or not dm.is_inside()
	var p := world.player.global_position
	# A finished build: show it
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_mutex.lock()
		var arrays: Array = _result.get("arrays", [])
		_result = {}
		_mutex.unlock()
		if not arrays.is_empty():
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_mesh.mesh = m
	if _task < 0 and (not _center.is_finite() or Vector2(p.x - _center.x, p.z - _center.z).length() > REBUILD_AFTER):
		_center = Vector3(snappedf(p.x, STEP), 0.0, snappedf(p.z, STEP))
		var c := _center
		var map := world.map
		var sea := world.settings.sea_level
		_task = WorkerThreadPool.add_task(func() -> void: _build(map, c, sea), false, "far land")
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_update_towns(p)


# Worker thread: the coarse grid around c
func _build(map: WorldMap, c: Vector3, sea: float) -> void:
	var n := int(REACH * 2.0 / STEP) + 1
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	colors.resize(n * n)
	normals.resize(n * n)
	var x0 := c.x - REACH
	var z0 := c.z - REACH
	for iz in n:
		for ix in n:
			var x := x0 + ix * STEP
			var z := z0 + iz * STEP
			var h := map.get_height(x, z)
			var i := iz * n + ix
			verts[i] = Vector3(x, maxf(h, sea - 0.5) - SINK, z)
			var b := map.get_biome_at(x, z)
			colors[i] = WATER if h < sea else (b.ground_color if b != null else Color(0.35, 0.45, 0.25))
	# normals from the neighbours, for a little shading on hills
	for iz in n:
		for ix in n:
			var l := verts[iz * n + maxi(ix - 1, 0)]
			var r := verts[iz * n + mini(ix + 1, n - 1)]
			var d := verts[maxi(iz - 1, 0) * n + ix]
			var u := verts[mini(iz + 1, n - 1) * n + ix]
			normals[iz * n + ix] = (u - d).cross(r - l).normalized()
	var idx := PackedInt32Array()
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	_mutex.lock()
	_result = {"arrays": arrays}
	_mutex.unlock()


# Towns out past the loaded land get their outline; a town whose real buildings are there hides it
func _update_towns(p: Vector3) -> void:
	for t in world.towns:
		if t.town == null:
			continue
		var d := Vector2(t.position.x - p.x, t.position.z - p.z).length()
		var want := d < REACH and world.get_poi_node(t.id) == null
		if want and not _towns.has(t.id):
			_towns[t.id] = _outline(t)
		if _towns.has(t.id):
			(_towns[t.id] as Node3D).visible = want


# A town's buildings as plain boxes on the ground, one mesh, sunk like the far land
func _outline(t: PlacedPOI) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	for b in t.town.buildings:
		var h := b.size.y * 1.6  # a roof's worth taller
		box.size = Vector3(b.size.x, h, b.size.z)
		var ground := world.map.get_height(b.world_pos.x, b.world_pos.z) - SINK
		st.append_from(box, 0, Transform3D(Basis(Vector3.UP, b.world_yaw), Vector3(b.world_pos.x, ground + h * 0.5, b.world_pos.z)))
	var mi := MeshInstance3D.new()
	mi.name = "FarTown_" + t.id
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.44, 0.4)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	return mi
