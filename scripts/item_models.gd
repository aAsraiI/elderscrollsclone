class_name ItemModels
extends RefCounted
## The 3D look of an item, in one place for the three places that show it:
##   view    in your hands in first person (ViewModel)       uses ItemData.view_scene
##   world   lying on the ground (WorldItem)                 uses ItemData.world_scene
##   preview the turning model in the inventory              world_scene, else view_scene
## An item without a model gets a placeholder built from boxes, shaped by its type
## (blade, hammer, shield, chestplate, potion, food, coins, gem, ring, bundle).
##
## Giving an item your own model: make a scene (a .glb / .gltf dropped into the project works too),
## then on the item's .tres set "View Scene" (held in first person) and/or "World Scene"
## (on the ground). Use the Models group on the item to move / turn / scale it into the hand.

const METAL := Color(0.72, 0.74, 0.80)
const DARK := Color(0.30, 0.30, 0.34)
const WOOD := Color(0.38, 0.26, 0.15)
const SKIN := Color(0.80, 0.62, 0.50)
const GOLD := Color(0.95, 0.75, 0.25)
const CLOTH := Color(0.45, 0.32, 0.22)

static var _materials := {}


## In first person. Grip at the origin, blade along +Y. null item = a bare fist.
static func build_view(item: ItemData) -> Node3D:
	var root := Node3D.new()
	if item == null:
		_box(root, Vector3(0.10, 0.10, 0.14), Vector3.ZERO, SKIN)
		return root
	if item.view_scene != null:
		var model := item.view_scene.instantiate() as Node3D
		if model != null:
			model.position = item.view_offset
			model.rotation_degrees = item.view_rotation
			model.scale = Vector3.ONE * item.view_scale
			root.add_child(model)
			return root
	_placeholder(root, item)
	return root


## On the ground. Centered on its own middle, so a collision box can be fitted around it.
static func build_world(item: ItemData) -> Node3D:
	var root := Node3D.new()
	if item == null:
		_box(root, Vector3(0.3, 0.3, 0.3), Vector3.ZERO, DARK)
		return root
	var scene := item.world_scene if item.world_scene != null else item.view_scene
	if scene != null:
		var model := scene.instantiate() as Node3D
		if model != null:
			model.scale = Vector3.ONE * item.world_scale
			root.add_child(model)
			return root
	_placeholder(root, item)
	return root


## The box around every mesh under `node`, in node's own space
static func get_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "VisualInstance3D", true, false):
		var vi := mi as VisualInstance3D
		var local := _relative_transform(node, vi) * vi.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out if not first else AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))


static func _relative_transform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# ---------------------------------------------------------------- placeholders

static func _placeholder(root: Node3D, item: ItemData) -> void:
	var anim := String(item.animation_set)
	if item.item_type == ItemData.ItemType.WEAPON or item.equip_slot == ItemData.EquipSlot.OFF_HAND:
		match anim:
			"dagger":
				_blade(root, 0.30, 0.04, 0.10, 0.12)
			"greatsword":
				_blade(root, 1.05, 0.10, 0.26, 0.34)
			"hammer":
				_box(root, Vector3(0.045, 0.95, 0.045), Vector3(0.0, 0.30, 0.0), WOOD)
				_box(root, Vector3(0.30, 0.20, 0.22), Vector3(0.0, 0.82, 0.0), DARK)
				_box(root, Vector3(0.05, 0.05, 0.05), Vector3(0.0, -0.20, 0.0), DARK)
			"shield":
				_shield(root)
			_:
				if item.secondary_action == ItemData.SecondaryAction.BLOCK:
					_shield(root)
				elif item.two_handed:
					_blade(root, 0.95, 0.09, 0.24, 0.30)
				else:
					_blade(root, 0.72, 0.06, 0.20, 0.16)
		return
	match item.item_type:
		ItemData.ItemType.ARMOR:
			match item.equip_slot:
				ItemData.EquipSlot.RING:
					_ring(root)
				ItemData.EquipSlot.AMULET:
					_ring(root)
					_gem(root, Vector3(0.0, -0.06, 0.0), Color(0.6, 0.2, 0.8))
				ItemData.EquipSlot.HEAD:
					_box(root, Vector3(0.26, 0.22, 0.28), Vector3.ZERO, METAL)
				_:
					_box(root, Vector3(0.46, 0.52, 0.22), Vector3.ZERO, METAL)  # chest
					_box(root, Vector3(0.16, 0.14, 0.20), Vector3(-0.30, 0.18, 0.0), DARK)  # shoulders
					_box(root, Vector3(0.16, 0.14, 0.20), Vector3(0.30, 0.18, 0.0), DARK)
		ItemData.ItemType.CONSUMABLE:
			if item.id == &"gold" or item.display_name.to_lower().begins_with("gold"):
				for i in 3:
					_cylinder(root, 0.06, 0.012, Vector3(0.02 * i, 0.014 * i, -0.01 * i), GOLD)
			elif item.effect_group == "potion":
				_cylinder(root, 0.055, 0.14, Vector3.ZERO, Color(0.75, 0.15, 0.2, 0.85))
				_cylinder(root, 0.02, 0.06, Vector3(0.0, 0.10, 0.0), Color(0.8, 0.85, 0.9, 0.7))
				_cylinder(root, 0.024, 0.02, Vector3(0.0, 0.14, 0.0), WOOD)
			else:
				_sphere(root, 0.09, Vector3.ZERO, Color(0.70, 0.45, 0.20))
		ItemData.ItemType.KEY:
			_box(root, Vector3(0.12, 0.02, 0.02), Vector3.ZERO, GOLD)
			_box(root, Vector3(0.05, 0.05, 0.02), Vector3(-0.07, 0.0, 0.0), GOLD)
		_:
			if item.treasure:
				var lower := item.display_name.to_lower()
				if lower.contains("ring"):
					_ring(root)
				elif lower.contains("necklace") or lower.contains("circlet") or lower.contains("crown"):
					_ring(root, 0.10)
				elif lower.contains("chalice") or lower.contains("reliquary") or lower.contains("idol"):
					_cylinder(root, 0.06, 0.16, Vector3.ZERO, Color(0.8, 0.8, 0.85) if lower.contains("silver") else GOLD)
				elif lower.contains("coin"):
					_cylinder(root, 0.05, 0.01, Vector3.ZERO, GOLD)
				else:
					_gem(root, Vector3.ZERO, _gem_color(lower))
			else:
				_box(root, Vector3(0.22, 0.14, 0.16), Vector3.ZERO, CLOTH)  # a bundle


static func _gem_color(item_name: String) -> Color:
	for pair in [["ruby", Color(0.85, 0.1, 0.15)], ["sapphire", Color(0.15, 0.3, 0.9)], ["emerald", Color(0.1, 0.75, 0.3)], ["amethyst", Color(0.6, 0.25, 0.85)], ["garnet", Color(0.6, 0.1, 0.2)], ["diamond", Color(0.9, 0.95, 1.0)]]:
		if item_name.contains(pair[0]):
			return pair[1]
	return Color(0.8, 0.8, 0.9)


static func _blade(root: Node3D, blade_len: float, blade_w: float, guard_w: float, handle_len: float) -> void:
	_box(root, Vector3(0.035, handle_len, 0.035), Vector3.ZERO, WOOD)
	_box(root, Vector3(0.05, 0.03, 0.05), Vector3(0.0, -handle_len * 0.5 - 0.015, 0.0), DARK)
	_box(root, Vector3(guard_w, 0.025, 0.04), Vector3(0.0, handle_len * 0.5 + 0.0125, 0.0), DARK)
	_box(root, Vector3(blade_w, blade_len, 0.014), Vector3(0.0, handle_len * 0.5 + 0.025 + blade_len * 0.5, 0.0), METAL)


static func _shield(root: Node3D) -> void:
	_box(root, Vector3(0.58, 0.70, 0.03), Vector3(0.0, 0.0, 0.025), DARK)
	_box(root, Vector3(0.52, 0.64, 0.05), Vector3.ZERO, Color(0.55, 0.57, 0.62))
	_box(root, Vector3(0.15, 0.15, 0.08), Vector3(0.0, 0.0, -0.05), METAL)


static func _ring(root: Node3D, radius: float = 0.035) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.75
	mesh.outer_radius = radius
	_add(root, mesh, Vector3.ZERO, GOLD)


static func _gem(root: Node3D, pos: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 2
	_add(root, mesh, pos, color)


static func _cylinder(root: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	_add(root, mesh, pos, color)


static func _sphere(root: Node3D, radius: float, pos: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_add(root, mesh, pos, color)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_add(parent, box, pos, color)


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = pos
	parent.add_child(mi)


static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	m.metallic = 0.6 if color == METAL or color == GOLD else 0.0
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = m
	return m
