class_name BridgePOIData
extends POIData
## A bridge carrying a road over a river or a stream: stone with parapets and piers over a river,
## timber planks on posts with a rail over a stream. WorldPlan.bridges() makes one wherever a road
## crosses running water; its span, width and the water level are in the PlacedPOI's `extra`.
## Local space: the origin is the middle of the deck's top, the road runs along Z.

const MAT := "res://data/interiors/materials/"
## Rivers wider than this (m) get a stone bridge, narrower water a timber one
const STONE_FROM := 7.0


func _init() -> void:
	id = &"road_bridge"
	display_name = "Bridge"
	map_color = Color(0.75, 0.72, 0.65)
	footprint_radius = 6.0
	flatten_radius = 0.0
	discoverable = false
	random_rotation = false


func build(placed: PlacedPOI, _map: WorldMap) -> Node3D:
	var root := Node3D.new()
	var span := float(placed.extra.get("span", 12.0))
	var width := float(placed.extra.get("width", 5.0))
	var water := float(placed.extra.get("water", placed.position.y - 2.0)) - placed.position.y
	var stone := bool(placed.extra.get("stone", span >= STONE_FROM * 2.0))
	var bed := water - 2.5  # how deep the footings go (local)
	var body := StaticBody3D.new()
	body.name = "Bridge"
	root.add_child(body)
	if stone:
		var mat := _mat("stone")
		var dark := _mat("stone_dark")
		_box(body, Vector3(width, 0.7, span), Vector3(0, -0.35, 0), mat)
		for side in [-1.0, 1.0]:
			_box(body, Vector3(0.45, 0.85, span), Vector3(side * (width * 0.5 + 0.2), 0.42, 0), mat)
			_box(body, Vector3(0.6, 0.12, span), Vector3(side * (width * 0.5 + 0.2), 0.9, 0), dark)
		# the ends stand on the banks, piers in the water every 9 m or so
		for end in [-1.0, 1.0]:
			_box(body, Vector3(width + 1.3, -bed + 0.0, 2.6), Vector3(0, bed * 0.5 - 0.35, end * (span * 0.5 - 1.3)), dark)
		var piers := maxi(0, int(span / 9.0) - 1)
		for k in piers:
			var z := lerpf(-span * 0.5, span * 0.5, float(k + 1) / float(piers + 1))
			_box(body, Vector3(width * 0.9, -bed, 1.6), Vector3(0, bed * 0.5 - 0.35, z), dark)
			# a cutwater on the upstream face reads as a bridge, not a wall
			_box(body, Vector3(1.0, -bed - 0.6, 1.0), Vector3(0, (bed - 0.6) * 0.5 - 0.35, z), dark, PI * 0.25)
	else:
		var mat := _mat("wood")
		var dark := _mat("wood_dark")
		# planks across the stream (each its own slightly uneven board), on two beams
		var n := maxi(2, int(span / 0.5))
		for k in n:
			var z := lerpf(-span * 0.5 + 0.25, span * 0.5 - 0.25, float(k) / float(n - 1))
			_box(body, Vector3(width, 0.12, 0.46), Vector3(0, -0.06 + (0.02 if k % 3 == 0 else 0.0), z), mat if k % 2 == 0 else dark, 0.0, false)
		var deck := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 0.3, span)
		deck.shape = shape
		deck.position = Vector3(0, -0.15, 0)
		body.add_child(deck)
		for side in [-1.0, 1.0]:
			_box(body, Vector3(0.3, 0.35, span + 1.0), Vector3(side * (width * 0.5 - 0.4), -0.3, 0), dark)
			_box(body, Vector3(0.12, 0.12, span), Vector3(side * (width * 0.5 + 0.05), 1.0, 0), dark)
			var posts := maxi(2, int(span / 2.5) + 1)
			for k in posts:
				var z := lerpf(-span * 0.5, span * 0.5, float(k) / float(posts - 1))
				_box(body, Vector3(0.16, 1.1 - bed, 0.16), Vector3(side * (width * 0.5 + 0.05), (1.1 + bed) * 0.5, z), dark)
	return root


static func _mat(name: String) -> Material:
	var path := MAT + name + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as Material
	return POIBuilder.get_material(Color(0.5, 0.48, 0.44) if name.begins_with("stone") else Color(0.4, 0.3, 0.2))


static func _box(body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0, solid: bool = true) -> void:
	size = size.abs()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	body.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		cs.rotation.y = yaw
		body.add_child(cs)
