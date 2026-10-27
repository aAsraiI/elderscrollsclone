class_name DoorLook
extends RefCounted
## Makes a way in or out easy to spot from across a street or a dark room: the door itself (a model
## when ModelLibrary has one, "door/building", "door/dungeon"; else planks and iron bands), a lighter
## frame round it, and a lit lantern beside it. Used for town doors and dungeon exits.

const FRAME_COLOR := Color(0.58, 0.42, 0.26)  # light wood (reads as wood in the built shader)
const WOOD := Color(0.36, 0.24, 0.13)
const IRON := Color(0.2, 0.2, 0.22)


## `floor_at` is the bottom middle of the doorway on the wall's face, `yaw` turns the door to face the side
## you approach from (+Z of the door faces there). Everything stands just out from the wall (never in it,
## where the two would flicker through each other).
static func dress(parent: Node3D, floor_at: Vector3, yaw: float, key: String, lamp: bool = true, frame: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DoorLook"
	root.add_to_group("door_looks")
	root.position = floor_at
	root.rotation.y = yaw
	parent.add_child(root)
	var door := ModelLibrary.fitted(key, AABB(Vector3(-0.75, 0.0, -0.1), Vector3(1.5, 2.4, 0.2)), "height") if ModelLibrary.has(key) else null
	if door != null:
		door.name = "Door"
		door.set_meta("model_key", key)
		root.add_child(door)
		var b := door.transform * ModelLibrary.bounds(door)
		if b.size.x > 1.5:
			door.scale *= 1.5 / b.size.x  # no wider than its frame
			b = door.transform * ModelLibrary.bounds(door)
		door.position += Vector3(-b.get_center().x, -b.position.y, 0.03 - b.position.z)  # its back just off the wall
	else:
		POIBuilder.add_box(root, Vector3(1.4, 2.3, 0.1), Vector3(0.0, 1.15, 0.08), WOOD, 0.0, Vector3.ZERO, false)
		for y in [0.55, 1.75]:
			POIBuilder.add_box(root, Vector3(1.3, 0.08, 0.06), Vector3(0.0, y, 0.15), IRON, 0.0, Vector3.ZERO, false)
		POIBuilder.add_box(root, Vector3(0.08, 0.08, 0.12), Vector3(0.5, 1.15, 0.17), Color(0.75, 0.62, 0.3), 0.0, Vector3.ZERO, false)
	# A lighter frame, so the doorway stands out from the wall around it (not in a rock mouth)
	for x in ([-0.82, 0.82] if frame else []):
		POIBuilder.add_box(root, Vector3(0.18, 2.6, 0.24), Vector3(x, 1.3, 0.13), FRAME_COLOR, 0.0, Vector3.ZERO, false)
	if frame:
		POIBuilder.add_box(root, Vector3(1.82, 0.2, 0.26), Vector3(0.0, 2.65, 0.14), FRAME_COLOR, 0.0, Vector3.ZERO, false)
	if lamp:
		_lamp(root, Vector3(1.15, 2.05, 0.3))
	return root


# A lantern on the wall beside the door: warm light and a small flame, lit day and night
static func _lamp(root: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "DoorLamp"
	holder.position = at
	root.add_child(holder)
	var model := ModelLibrary.fitted("prop/sconce", AABB(Vector3(-0.15, -0.3, -0.15), Vector3(0.3, 0.45, 0.3)), "height") if ModelLibrary.has("prop/sconce") else null
	if model != null:
		for l in model.find_children("*", "Light3D", true, false):
			l.queue_free()  # this one has its own light below
		holder.add_child(model)
	else:
		POIBuilder.add_box(holder, Vector3(0.18, 0.26, 0.18), Vector3.ZERO, IRON, 0.0, Vector3.ZERO, false)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.2)
	flame.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.65, 0.3)
	fm.albedo_texture = MwCharacter._flame_texture()
	flame.material_override = fm
	flame.position = Vector3(0.0, 0.05, 0.0)
	holder.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.position = Vector3(0.0, 0.0, 0.25)
	holder.add_child(light)


## A town's doors drawn as one: every door model under `root` becomes an instance of one MultiMesh
## (the model baked to a single mesh, its parts' materials kept). The doors you open are separate nodes
## (BuildingDoor), so nothing else changes.
static func batch(root: Node3D) -> void:
	var doors := root.find_children("Door", "Node3D", true, false).filter(func(n): return n.get_parent() != null and String(n.get_parent().name).begins_with("DoorLook") and n.has_meta("model_key"))
	var by_key := {}
	for d: Node3D in doors:
		var key := String(d.get_meta("model_key"))
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(d)
	for key: String in by_key:
		var list: Array = by_key[key]
		if list.size() < 2:
			continue
		var mesh := ModelLibrary.bake(list[0])
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, _relative(list[i], root))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Many_doors"
		mmi.multimesh = mm
		mmi.visibility_range_end = 150.0
		mmi.visibility_range_end_margin = 10.0
		root.add_child(mmi)
		for d: Node3D in list:
			d.get_parent().remove_child(d)
			d.free()


static func _relative(n: Node3D, to: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != to:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
