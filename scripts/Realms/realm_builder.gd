class_name RealmBuilder
extends RefCounted
## Builds one realm (see RealmManager.REALMS) as a node tree for DungeonManager: a land of hills
## (or islands in a sea, or islands floating over nothing), lit by its own sun or none, with:
##   the hub     in the middle: a few huts, the people who live there, the way back out
##   the sites   on a ring around it: a ruin each, guarded by a named master and its followers,
##               with a chest of treasure
##   the heart   at the far edge: the realm's master and its guard (a "realm" quest step)
## The same realm is always the same land (the seed comes from the world seed and its id); the
## creatures remember their deaths through WorldState like any others.
##
## Local space: the hub is at the origin, ground height about 0.

const CELLS := 96

var id := ""
var data: Dictionary
var half := 600.0
var relief := 15.0
var islands := false
var floating := false
var _noise := FastNoiseLite.new()
var _mask := FastNoiseLite.new()
var _keys: Array[Vector2] = []     # hub, sites, heart (flattened, always land)


## {"root", "start", "start_yaw", "ambient", "sky", "fog"}
static func build(realm_id: String, realm_seed: int) -> Dictionary:
	var b := RealmBuilder.new()
	return b._build(realm_id, realm_seed)


func _build(realm_id: String, realm_seed: int) -> Dictionary:
	id = realm_id
	data = RealmManager.get_data(id)
	half = float(data.get("half", 600.0))
	relief = float(data.get("relief", 15.0))
	islands = bool(data.get("islands", false))
	floating = bool(data.get("floating", false))
	_noise.seed = realm_seed
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 4
	_mask.seed = realm_seed ^ 0x1515
	_mask.frequency = 0.004
	var rng := RandomNumberGenerator.new()
	rng.seed = realm_seed
	var root := Node3D.new()
	root.name = "Realm_" + id
	root.set_meta("realm_id", id)

	# where things go
	var sites: Array = data.get("sites", [])
	var turn := rng.randf() * TAU
	_keys.append(Vector2.ZERO)
	for k in sites.size():
		var a := turn + TAU * float(k) / float(sites.size() + 1)
		_keys.append(Vector2(cos(a), sin(a)) * half * rng.randf_range(0.42, 0.62))
	var ha := turn + TAU * float(sites.size()) / float(sites.size() + 1)
	_keys.append(Vector2(cos(ha), sin(ha)) * half * 0.8)

	_terrain(root)
	if islands and not floating:
		var sea := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(half * 2.4, half * 2.4)
		sea.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(data["fog"]).darkened(0.35)
		mat.albedo_color.a = 0.75
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sea.material_override = mat
		root.add_child(sea)
		sea.position = Vector3(0.0, -0.25, 0.0)
	var sun_color: Color = data.get("sun", Color.WHITE)
	if sun_color != Color.BLACK:
		var sun := DirectionalLight3D.new()
		sun.light_color = sun_color
		sun.light_energy = 0.9
		sun.set_meta("realm_light", true)
		sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
		root.add_child(sun)

	var levels: Array = data.get("levels", [20, 40])
	var lmin := int(levels[0])
	var lmax := int(levels[1])
	_hub(root, rng)
	for k in sites.size():
		var at := _keys[k + 1]
		var lvl := int(lerpf(float(lmin), float(lmax), clampf(at.length() / half, 0.0, 1.0)))
		_site(root, k, String(sites[k]), at, lvl, rng)
	_heart(root, _keys[_keys.size() - 1], lmax, rng)

	var start := Vector3(0.0, _height(Vector2(0.0, -6.0)) + 0.2, -6.0)
	root.set_meta("realm_start", start)
	return {"root": root, "start": start, "start_yaw": PI, "ambient": data.get("ambient", Color(0.4, 0.4, 0.45)),
		"sky": data.get("sky", Color.BLACK), "fog": data.get("fog", Color.GRAY)}


# ---------------------------------------------------------------- the land

# Ground height at a local point; NAN where there is nothing (between floating islands)
func _height(p: Vector2) -> float:
	var h := _noise.get_noise_2d(p.x, p.y) * relief
	var key_d := INF
	var key_h := 0.0
	for k in _keys:
		var d := p.distance_to(k)
		if d < key_d:
			key_d = d
			key_h = _noise.get_noise_2d(k.x, k.y) * relief * 0.3 + 1.0
	# flat ground at the hub, the sites and the heart
	var flat := 1.0 - smoothstep(30.0, 70.0, key_d)
	h = lerpf(h, key_h, flat)
	if not islands:
		return h
	var land := _mask.get_noise_2d(p.x, p.y) > 0.18 or key_d < 95.0 or _near_path(p) < 5.0
	if land:
		return maxf(h, 0.6) if key_d >= 95.0 else maxf(h, 1.0)
	return NAN if floating else -1.3  # shallows between the islands (wade across)


# Light-bridges and sandbars: from the hub out to every site and the heart
func _near_path(p: Vector2) -> float:
	var best := INF
	for i in range(1, _keys.size()):
		var a := Vector2.ZERO
		var b := _keys[i]
		var t := clampf(p.dot(b) / b.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a.lerp(b, t)))
	return best


func _terrain(root: Node3D) -> void:
	var step := half * 2.0 / float(CELLS)
	var hs := PackedFloat32Array()
	hs.resize((CELLS + 1) * (CELLS + 1))
	for j in CELLS + 1:
		for i in CELLS + 1:
			hs[j * (CELLS + 1) + i] = _height(Vector2(-half + i * step, -half + j * step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ground: Color = data.get("ground", Color(0.4, 0.4, 0.4))
	for j in CELLS:
		for i in CELLS:
			var h00 := hs[j * (CELLS + 1) + i]
			var h10 := hs[j * (CELLS + 1) + i + 1]
			var h01 := hs[(j + 1) * (CELLS + 1) + i]
			var h11 := hs[(j + 1) * (CELLS + 1) + i + 1]
			if is_nan(h00) or is_nan(h10) or is_nan(h01) or is_nan(h11):
				continue
			var x0 := -half + i * step
			var z0 := -half + j * step
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + step, h10, z0)
			var v01 := Vector3(x0, h01, z0 + step)
			var v11 := Vector3(x0 + step, h11, z0 + step)
			var low := minf(minf(h00, h10), minf(h01, h11)) < 0.0
			var c := ground.darkened(0.35) if low else ground.darkened(0.12 * (0.5 + 0.5 * _noise.get_noise_2d(x0 * 3.0, z0 * 3.0)))
			for v in [v00, v10, v11, v00, v11, v01]:
				st.set_color(c)
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)


# ---------------------------------------------------------------- places

func _ground(at: Vector2) -> Vector3:
	var h := _height(at)
	return Vector3(at.x, 0.0 if is_nan(h) else h, at.y)


func _hub(root: Node3D, rng: RandomNumberGenerator) -> void:
	var wall := Color(data["ground"]).darkened(0.4)
	for k in 4:
		var a := float(k) / 4.0 * TAU + 0.6
		var at := _ground(Vector2(cos(a), sin(a)) * 22.0)
		POIBuilder.add_box(root, Vector3(7.0, 4.0, 6.0), at + Vector3(0.0, 2.0, 0.0), wall, a)
	_label(root, String(data.get("hub", "")), _ground(Vector2.ZERO) + Vector3(0.0, 4.0, 4.0), 64)
	# the people who live here
	var npcs: Array = data.get("npcs", [])
	for k in npcs.size():
		var a := float(k) / maxf(npcs.size(), 1.0) * TAU + 1.2
		var e := Enemy.new()
		e.display_name = String(npcs[k])
		e.talk_name = String(npcs[k])
		e.talk_lines = PackedStringArray(["Few living souls find their way to %s." % data.get("hub", "this place")])
		e.disposition = Enemy.Disposition.NEUTRAL
		e.placeholder_color = Color(0.55, 0.50, 0.45)
		e.max_health = 400.0
		e.persist_mode = Enemy.PersistMode.NEVER
		e.set_meta("realm_npc", String(npcs[k]))
		e.set_meta("realm", id)
		e.position = _ground(Vector2(cos(a), sin(a)) * 9.0) + Vector3(0.0, 0.6, 0.0)
		root.add_child(e)
	# the way back
	var exit := DungeonDoor.new()
	exit.name = "Exit"
	exit.entrance_id = RealmManager.ENTRANCE_PREFIX + id
	exit.is_exit = true
	exit.label = "Leave %s" % data.get("name", "the realm")
	root.add_child(exit)
	var door_at := _ground(Vector2(0.0, -9.0))
	exit.position = door_at + Vector3(0.0, 1.3, 0.0)
	var glow := Color(0.55, 0.40, 0.95)
	for side in [-1.0, 1.0]:
		POIBuilder.add_box(root, Vector3(0.7, 4.0, 0.7), door_at + Vector3(side * 1.7, 2.0, 0.0), Color(0.35, 0.33, 0.38))
	POIBuilder.add_box(root, Vector3(2.6, 3.6, 0.08), door_at + Vector3(0.0, 1.8, 0.3), glow, 0.0, Vector3.ZERO, false, true)


func _site(root: Node3D, k: int, site_name: String, at2: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	var at := _ground(at2)
	_ruin(root, at, 9.0, rng)
	_label(root, site_name, at + Vector3(0.0, 5.0, 0.0), 56)
	var foes: Array = data.get("foes", ["skeleton"])
	for n in RealmManager.site_guards(id, k):
		var key := RealmManager.site_key(id, k, n)
		if WorldState.has_record("kill/" + key):
			continue
		var body := String(foes[(n + k) % foes.size()])
		var e := _spawn(root, body, level + (2 if n == 0 else 0), at + Vector3(rng.randf_range(-6.0, 6.0), 0.8, rng.randf_range(-6.0, 6.0)), key, rng)
		if e != null and n == 0:
			e.display_name = "Master of %s" % site_name
	var loot: Array[LootEntry] = []
	loot.append_array(ItemCatalog.treasure_loot(level, level + 4, 2.0))
	loot.append(ItemCatalog.gold_loot(level + 4, 1.0))
	var chest := POIBuilder.make_chest("%s Chest" % site_name, loot, "realm/%s/s%d/chest" % [id, k], (hash(id) + k * 977) | 1)
	root.add_child(chest)
	chest.position = at + Vector3(0.0, 0.35, 3.0)


func _heart(root: Node3D, at2: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	var at := _ground(at2)
	_ruin(root, at, 15.0, rng)
	_label(root, String(data.get("heart", "The Heart")), at + Vector3(0.0, 7.0, 0.0), 72)
	var boss: Array = data.get("boss", ["skeleton_knight", "The Master"])
	var foes: Array = data.get("foes", ["skeleton"])
	for n in 4:
		var key := "realm/%s/heart/%d" % [id, n]
		if WorldState.has_record("kill/" + key):
			continue
		var body := String(boss[0]) if n == 0 else String(foes[n % foes.size()])
		var e := _spawn(root, body, level + (5 if n == 0 else 2), at + Vector3(rng.randf_range(-7.0, 7.0), 0.8, rng.randf_range(-7.0, 7.0)), key, rng)
		if e != null and n == 0:
			e.display_name = String(boss[1])
	var loot: Array[LootEntry] = []
	loot.append_array(ItemCatalog.treasure_loot(level + 2, level + 8, 3.0))
	loot.append(ItemCatalog.gold_loot(level + 8, 1.0))
	var chest := POIBuilder.make_chest("Heart Chest", loot, "realm/%s/heart/chest" % id, hash(id + "heart") | 1)
	root.add_child(chest)
	chest.position = at + Vector3(0.0, 0.35, 5.0)


# Broken walls in a ring
func _ruin(root: Node3D, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var stone := Color(data["ground"]).darkened(0.5).lerp(Color(0.45, 0.44, 0.42), 0.5)
	for k in 8:
		if rng.randf() < 0.3:
			continue
		var a := float(k) / 8.0 * TAU
		var h := rng.randf_range(1.5, 4.5)
		POIBuilder.add_box(root, Vector3(r * 0.7, h, 0.8), at + Vector3(cos(a) * r, h * 0.5 - 0.3, sin(a) * r), stone, -a + PI * 0.5)


func _spawn(root: Node3D, body: String, level: int, pos: Vector3, key: String, rng: RandomNumberGenerator) -> Enemy:
	var path := QuestBook.ENEMY_DIR + body + ".tres"
	var d := load(path) as EnemyData if ResourceLoader.exists(path) else null
	if d == null:
		return null
	return Population.spawn_enemy(d, maxi(level, 1), root, pos, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})


func _label(root: Node3D, text: String, pos: Vector3, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.visibility_range_end = 120.0
	root.add_child(l)
	l.position = pos
