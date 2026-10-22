class_name POIBuilder
extends RefCounted
## Placeholder structures made of boxes, so the world has something to look at before there are
## real models. Everything is built in code from the POI's seed, so a structure always looks the
## same. Replace any of it by giving the POI resource a Scene.
##
## Local space: the origin is the ground at the middle of the site, the front faces -Z.

static var _materials := {}


static func get_material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + ("g" if glow else "")
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	_materials[key] = m
	return m


## A box centered at `pos`. solid = it also blocks the player.
static func add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, yaw: float = 0.0, tilt: Vector3 = Vector3.ZERO, solid: bool = true, glow: bool = false) -> Node3D:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = get_material(color, glow)
	holder.add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		holder.add_child(shape)
	parent.add_child(holder)
	holder.position = pos
	holder.rotation = Vector3(tilt.x, yaw, tilt.z)
	return holder


## Height of the real ground (relative to the POI's middle) at a spot given in local coordinates
static func ground_y(placed: PlacedPOI, map: WorldMap, local_x: float, local_z: float) -> float:
	var w := placed.position + Basis(Vector3.UP, placed.yaw) * Vector3(local_x, 0.0, local_z)
	return map.get_height(w.x, w.z) - placed.position.y


static func _rng(placed: PlacedPOI, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = placed.seed_value + salt * 7919
	return r


# ---------------------------------------------------------------- simple shapes

static func build_shape(root: Node3D, shape: int, s: float, color: Color, placed: PlacedPOI, map: WorldMap) -> void:
	var rng := _rng(placed, 1)
	match shape:
		SimplePOIData.Shape.STANDING_STONES:
			_standing_stones(root, s, color, placed, map, rng)
		SimplePOIData.Shape.CAMP:
			_camp(root, s, color, rng)
		SimplePOIData.Shape.TOWER:
			_tower(root, s, color)
		SimplePOIData.Shape.RUINS:
			_ruins(root, s, color, rng)
		SimplePOIData.Shape.SHRINE:
			_shrine(root, s, color)


static func _standing_stones(root: Node3D, s: float, color: Color, placed: PlacedPOI, map: WorldMap, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(5, 8)
	var radius := 6.0 * s
	for i in n:
		var a := float(i) / float(n) * TAU + rng.randf_range(-0.15, 0.15)
		var lx := cos(a) * radius
		var lz := sin(a) * radius
		var h := rng.randf_range(2.8, 4.2) * s
		var gy := ground_y(placed, map, lx, lz)
		add_box(root, Vector3(1.1, h, 0.8) * Vector3(s, 1.0, s), Vector3(lx, gy + h * 0.5 - 0.4, lz), color.darkened(rng.randf_range(0.0, 0.25)), -a + PI * 0.5, Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06)))
	var cy := ground_y(placed, map, 0.0, 0.0)
	add_box(root, Vector3(2.6, 0.5, 1.5) * s, Vector3(0.0, cy + 0.15, 0.0), color.darkened(0.3))


static func _camp(root: Node3D, s: float, color: Color, rng: RandomNumberGenerator) -> void:
	var tents := rng.randi_range(2, 3)
	for i in tents:
		var a := float(i) / float(tents) * TAU + rng.randf_range(-0.3, 0.3) + 0.8
		var pos := Vector3(cos(a), 0.0, sin(a)) * 5.0 * s
		var holder := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(3.2, 2.2, 3.8) * s
		mesh.mesh = prism
		mesh.material_override = get_material(Color(0.55, 0.42, 0.28).darkened(rng.randf_range(0.0, 0.3)))
		holder.add_child(mesh)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.0, 2.0, 3.6) * s
		shape.shape = bs
		holder.add_child(shape)
		root.add_child(holder)
		holder.position = pos + Vector3(0.0, 1.1 * s, 0.0)
		holder.rotation.y = -a + PI * 0.5
	# fire ring and logs
	add_box(root, Vector3(1.4, 0.3, 1.4) * s, Vector3(0.0, 0.15, 0.0), Color(0.18, 0.17, 0.16), 0.0, Vector3.ZERO, false)
	add_box(root, Vector3(0.5, 0.5, 0.5) * s, Vector3(0.0, 0.45, 0.0), Color(1.0, 0.5, 0.15), 0.4, Vector3.ZERO, false, true)
	for i in 3:
		var a := float(i) * TAU / 3.0 + 0.5
		add_box(root, Vector3(1.6, 0.35, 0.35) * s, Vector3(cos(a), 0.2, sin(a)) * 2.0 * s, Color(0.35, 0.25, 0.15), a, Vector3.ZERO, false)


static func _tower(root: Node3D, s: float, color: Color) -> void:
	var radius := 3.2 * s
	var height := 12.0 * s
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.9
	cyl.bottom_radius = radius
	cyl.height = height
	mesh.mesh = cyl
	mesh.material_override = get_material(color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = height
	shape.shape = cs
	body.add_child(shape)
	root.add_child(body)
	body.position = Vector3(0.0, height * 0.5, 0.0)
	for i in 8:
		var a := float(i) * TAU / 8.0
		add_box(root, Vector3(1.0, 1.0, 1.0) * s, Vector3(cos(a), 0.0, sin(a)) * radius * 0.85 + Vector3(0.0, height + 0.4 * s, 0.0), color.darkened(0.1), a)
	add_box(root, Vector3(1.8, 2.6, 0.4) * s, Vector3(0.0, 1.3 * s, -radius * 0.95), Color(0.12, 0.08, 0.05), 0.0, Vector3.ZERO, false)


static func _ruins(root: Node3D, s: float, color: Color, rng: RandomNumberGenerator) -> void:
	var w := 14.0 * s
	var d := 10.0 * s
	var step := 2.4 * s
	var sides := [
		[Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(1.0, 0.0, 0.0), w, 0.0],
		[Vector3(-w * 0.5, 0.0, d * 0.5), Vector3(1.0, 0.0, 0.0), w, 0.0],
		[Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(0.0, 0.0, 1.0), d, PI * 0.5],
		[Vector3(w * 0.5, 0.0, -d * 0.5), Vector3(0.0, 0.0, 1.0), d, PI * 0.5],
	]
	for side in sides:
		var origin: Vector3 = side[0]
		var dir: Vector3 = side[1]
		var length: float = side[2]
		var t := step * 0.5
		while t < length:
			if rng.randf() < 0.72:
				var h := rng.randf_range(0.8, 3.6) * s
				add_box(root, Vector3(step * 0.95, h, 0.7 * s), origin + dir * t + Vector3(0.0, h * 0.5, 0.0), color.darkened(rng.randf_range(0.0, 0.3)), side[3])
			t += step
	for i in 3:
		var h := rng.randf_range(1.5, 4.5) * s
		add_box(root, Vector3(0.9, h, 0.9) * s, Vector3(rng.randf_range(-w * 0.3, w * 0.3), h * 0.5, rng.randf_range(-d * 0.3, d * 0.3)), color.darkened(0.15), rng.randf() * TAU)


static func _shrine(root: Node3D, s: float, color: Color) -> void:
	add_box(root, Vector3(7.0, 0.3, 7.0) * s, Vector3(0.0, 0.15, 0.0), color.darkened(0.2))
	add_box(root, Vector3(5.0, 0.3, 5.0) * s, Vector3(0.0, 0.45, 0.0), color)
	add_box(root, Vector3(0.9, 4.0, 0.9) * s, Vector3(0.0, 2.6 * s, 0.0), color.darkened(0.1))
	add_box(root, Vector3(0.5, 0.5, 0.5) * s, Vector3(0.0, 4.9 * s, 0.0), Color(0.5, 0.8, 1.0), 0.6, Vector3(0.4, 0.0, 0.4), false, true)


# ---------------------------------------------------------------- dungeon entrances

static func build_entrance_shape(root: Node3D, shape: int, s: float, color: Color, placed: PlacedPOI, _map: WorldMap) -> void:
	var rng := _rng(placed, 2)
	var dark := Color(0.02, 0.02, 0.025)
	match shape:
		DungeonEntrancePOIData.Shape.CAVE:
			# A heap of rocks with a dark opening on the -Z side
			add_box(root, Vector3(5.0, 4.6, 5.0) * s, Vector3(-4.0, 2.3, 0.0) * s, color, rng.randf_range(-0.2, 0.2), Vector3(0.0, 0.0, 0.05))
			add_box(root, Vector3(5.0, 4.0, 5.0) * s, Vector3(4.0, 2.0, 0.0) * s, color.darkened(0.1), rng.randf_range(-0.2, 0.2), Vector3(0.0, 0.0, -0.05))
			add_box(root, Vector3(8.5, 2.6, 5.0) * s, Vector3(0.0, 4.9, 0.0) * s, color.darkened(0.05), rng.randf_range(-0.1, 0.1))
			add_box(root, Vector3(11.0, 6.0, 4.0) * s, Vector3(0.0, 3.0, 4.2) * s, color.darkened(0.15))
			add_box(root, Vector3(3.0, 3.6, 0.3) * s, Vector3(0.0, 1.8, 1.8) * s, dark)
			add_box(root, Vector3(9.0, 3.0, 4.0) * s, Vector3(0.0, 1.5, 7.0) * s, color.darkened(0.2))
		DungeonEntrancePOIData.Shape.DOORWAY:
			# A stone doorway set into a low mound
			add_box(root, Vector3(1.3, 3.8, 1.3) * s, Vector3(-1.9, 1.9, -0.6) * s, color)
			add_box(root, Vector3(1.3, 3.8, 1.3) * s, Vector3(1.9, 1.9, -0.6) * s, color)
			add_box(root, Vector3(5.6, 1.1, 1.6) * s, Vector3(0.0, 4.3, -0.6) * s, color.darkened(0.1))
			add_box(root, Vector3(10.0, 3.2, 5.0) * s, Vector3(0.0, 1.6, 3.2) * s, color.darkened(0.15))
			add_box(root, Vector3(2.6, 3.4, 0.3) * s, Vector3(0.0, 1.7, 0.4) * s, dark)
			add_box(root, Vector3(4.4, 0.25, 2.0) * s, Vector3(0.0, 0.12, -2.0) * s, color.darkened(0.25), 0.0, Vector3.ZERO, false)


# ---------------------------------------------------------------- chests

static func add_containers(root: Node3D, list: Array[POIContainer], placed: PlacedPOI, map: WorldMap = null) -> void:
	for i in list.size():
		var c := list[i]
		if c == null:
			continue
		var rng := _rng(placed, 100 + i)
		if rng.randf() > c.chance:
			continue  # this structure doesn't have that chest (decided from the seed, so always the same)
		var gy := 0.0
		if map != null:
			gy = ground_y(placed, map, c.offset.x, c.offset.z)
		var loot: Array[LootEntry] = c.loot.duplicate()
		if c.curve_loot and map != null:
			var zone := LevelCurve.zone_range(map, placed.position)
			loot.append_array(ItemCatalog.curve_loot(zone.x, zone.y, 0.7))
			loot.append_array(ItemCatalog.treasure_loot(zone.x, zone.y, 0.8))
		var chest := make_chest(c.display_name, loot, "%s/c%d" % [placed.id, i], (placed.seed_value + i * 7919) | 1)
		root.add_child(chest)
		chest.position = Vector3(c.offset.x, gy + 0.35 + c.offset.y, c.offset.z)
		chest.rotation.y = rng.randf_range(-0.4, 0.4)


## A lootable chest. save_id makes it remember its contents; loot_seed makes the loot repeatable.
static func make_chest(chest_name: String, loot: Array[LootEntry], save_id: String, loot_seed: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Chest"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.7, 0.6)
	mesh.mesh = box
	mesh.material_override = get_material(Color(0.45, 0.30, 0.16))
	body.add_child(mesh)
	var lid := MeshInstance3D.new()
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(1.04, 0.14, 0.64)
	lid.mesh = lid_box
	lid.material_override = get_material(Color(0.33, 0.21, 0.11))
	lid.position = Vector3(0.0, 0.4, 0.0)
	body.add_child(lid)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.8, 0.6)
	shape.shape = bs
	body.add_child(shape)
	var cc := ContainerComponent.new()
	cc.name = "ContainerComponent"
	cc.display_name = chest_name
	cc.save_id = save_id
	cc.loot_seed = loot_seed
	for e in loot:
		cc.contents.append(e)
	body.add_child(cc)
	return body
