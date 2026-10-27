class_name CraftingStation
extends StaticBody3D
## A workstation: forge, smelter, tanning rack, workbench, grindstone, cooking pot, alchemy lab,
## arcane enchanter or altar of spellmaking. Press E to use it (opens the CraftingUI).
## Placed by InteriorBuilder in smithies, inns, homes, temples, alchemists and guild halls.
## It is built from models (LOOKS: a table, forge, oven or altar with its tools and apparatus set on it,
## fixed in place, not things you can take), or from boxes when those models are missing.

const INTERACTABLE_LAYER := 4
const WORLD_LAYER := 1

@export_enum("forge", "smelter", "tanning_rack", "workbench", "grindstone", "cooking_pot", "alchemy_lab", "enchanter", "spell_altar")
var kind: String = "forge"


static func place(parent: Node3D, p_kind: String, at: Vector3, yaw: float = 0.0) -> CraftingStation:
	var s := CraftingStation.new()
	s.kind = p_kind
	s.name = "Station_" + p_kind
	parent.add_child(s)
	s.position = at
	s.rotation.y = yaw
	return s


func _ready() -> void:
	collision_layer = WORLD_LAYER | INTERACTABLE_LAYER
	collision_mask = 0
	var size := _size()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(shape)
	_build_model()


func get_prompt() -> String:
	return "Use %s" % Recipes.STATIONS.get(kind, kind)


func interact(_actor: Inventory) -> void:
	var ui := get_tree().get_first_node_in_group("crafting_ui") as CraftingUI
	if ui != null:
		ui.open_station(kind)


func _size() -> Vector3:
	match kind:
		"forge":
			return Vector3(1.4, 1.1, 1.2)
		"smelter":
			return Vector3(1.2, 1.6, 1.2)
		"tanning_rack":
			return Vector3(1.6, 1.8, 0.4)
		"grindstone":
			return Vector3(0.9, 1.0, 0.6)
		"cooking_pot":
			return Vector3(0.9, 0.9, 0.9)
		"spell_altar":
			return Vector3(1.2, 1.1, 0.8)
	return Vector3(1.6, 0.95, 0.8)


func _box(size: Vector3, at: Vector3, color: Color, glow: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.5
	mi.material_override = m
	add_child(mi)


func _light(at: Vector3, color: Color, energy: float = 1.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 3.5
	l.position = at
	add_child(l)


func _build_model() -> void:
	if _build_from_models():
		return
	var wood := Color(0.4, 0.27, 0.15)
	var dark := Color(0.25, 0.17, 0.1)
	var stone := Color(0.38, 0.37, 0.36)
	var metal := Color(0.3, 0.3, 0.33)
	match kind:
		"forge":
			_box(Vector3(1.4, 0.9, 1.2), Vector3(0, 0.45, 0), stone)
			_box(Vector3(0.9, 0.12, 0.7), Vector3(0, 0.96, 0), Color(1.0, 0.4, 0.1), true)
			_box(Vector3(0.3, 1.4, 0.3), Vector3(0, 1.6, 0.35), stone.darkened(0.2))
			_light(Vector3(0, 1.3, 0), Color(1.0, 0.5, 0.2), 1.4)
		"smelter":
			_box(Vector3(1.2, 1.2, 1.2), Vector3(0, 0.6, 0), stone.darkened(0.1))
			_box(Vector3(0.5, 0.35, 0.1), Vector3(0, 0.45, -0.6), Color(1.0, 0.55, 0.15), true)
			_box(Vector3(0.6, 0.5, 0.6), Vector3(0, 1.45, 0), stone.darkened(0.25))
			_light(Vector3(0, 0.5, -0.9), Color(1.0, 0.5, 0.2), 1.0)
		"tanning_rack":
			for x in [-0.75, 0.75]:
				_box(Vector3(0.1, 1.8, 0.1), Vector3(x, 0.9, 0), wood)
			_box(Vector3(1.6, 0.08, 0.08), Vector3(0, 1.75, 0), wood)
			_box(Vector3(1.2, 1.1, 0.04), Vector3(0, 1.1, 0), Color(0.6, 0.45, 0.3))
		"grindstone":
			_box(Vector3(0.7, 0.5, 0.5), Vector3(0, 0.25, 0), wood)
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.38
			cyl.height = 0.12
			wheel.mesh = cyl
			wheel.rotation = Vector3(0, 0, PI * 0.5)
			wheel.position = Vector3(0, 0.7, 0)
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.55, 0.53, 0.5)
			wheel.material_override = wm
			add_child(wheel)
		"cooking_pot":
			_box(Vector3(0.8, 0.15, 0.8), Vector3(0, 0.08, 0), stone)
			_box(Vector3(0.5, 0.12, 0.5), Vector3(0, 0.2, 0), Color(1.0, 0.45, 0.1), true)
			_box(Vector3(0.55, 0.4, 0.55), Vector3(0, 0.55, 0), metal)
			_box(Vector3(0.05, 0.9, 0.05), Vector3(-0.35, 0.45, 0), dark)
			_box(Vector3(0.05, 0.9, 0.05), Vector3(0.35, 0.45, 0), dark)
			_light(Vector3(0, 0.4, 0), Color(1.0, 0.55, 0.25), 0.8)
		"alchemy_lab":
			_box(Vector3(1.6, 0.08, 0.8), Vector3(0, 0.9, 0), wood)
			_box(Vector3(1.4, 0.86, 0.6), Vector3(0, 0.43, 0), dark)
			var colors := [Color(0.3, 0.9, 0.4), Color(0.9, 0.3, 0.3), Color(0.4, 0.5, 1.0), Color(0.9, 0.8, 0.3)]
			for i in 4:
				_box(Vector3(0.1, 0.22, 0.1), Vector3(-0.55 + i * 0.3, 1.05, 0.1), colors[i], true)
			_box(Vector3(0.3, 0.2, 0.3), Vector3(0.5, 1.04, -0.15), Color(0.5, 0.45, 0.4))
		"enchanter":
			_box(Vector3(1.6, 0.9, 0.8), Vector3(0, 0.45, 0), Color(0.22, 0.2, 0.28))
			_box(Vector3(0.6, 0.04, 0.45), Vector3(0, 0.92, 0), Color(0.85, 0.8, 0.65))
			_box(Vector3(0.18, 0.18, 0.18), Vector3(0.55, 1.1, 0.0), Color(0.6, 0.4, 1.0), true)
			_light(Vector3(0.55, 1.3, 0), Color(0.6, 0.4, 1.0), 0.9)
		"spell_altar":
			_box(Vector3(1.2, 1.0, 0.8), Vector3(0, 0.5, 0), Color(0.75, 0.72, 0.68))
			_box(Vector3(0.9, 0.05, 0.5), Vector3(0, 1.03, 0), Color(0.4, 0.6, 1.0), true)
			_light(Vector3(0, 1.4, 0), Color(0.5, 0.7, 1.0), 1.1)
		_:
			_box(Vector3(1.6, 0.08, 0.8), Vector3(0, 0.9, 0), wood)
			_box(Vector3(1.5, 0.86, 0.7), Vector3(0, 0.43, 0), dark)
			_box(Vector3(0.3, 0.1, 0.2), Vector3(-0.4, 0.99, 0), metal)
			_box(Vector3(0.1, 0.25, 0.1), Vector3(0.5, 1.05, 0), metal)


## Each station as models: [key, where (x, z; y = 0 on the floor, "top" on the first piece's top), the
## space it takes, fit mode]. The first piece is the base; without its model the station stays boxes.
const LOOKS := {
	"alchemy_lab": [["prop/table", "floor", Vector3(0, 0, 0), Vector3(1.6, 0.9, 0.8), "fill"],
		["station/alembic", "top", Vector3(-0.55, 0, 0.05), Vector3(0.3, 0.32, 0.3), "contain"],
		["station/retort", "top", Vector3(-0.15, 0, -0.1), Vector3(0.28, 0.3, 0.28), "contain"],
		["station/calcinator", "top", Vector3(0.25, 0, 0.05), Vector3(0.26, 0.28, 0.3), "contain"],
		["station/mortar", "top", Vector3(0.6, 0, -0.15), Vector3(0.14, 0.15, 0.14), "contain"],
		["clutter/bottle", "top", Vector3(0.62, 0, 0.18), Vector3(0.09, 0.24, 0.09), "contain"],
		["clutter/flask", "top", Vector3(0.05, 0, 0.22), Vector3(0.09, 0.18, 0.09), "contain"]],
	"enchanter": [["prop/table", "floor", Vector3(0, 0, 0), Vector3(1.6, 0.9, 0.8), "fill"],
		["station/soulgem", "top", Vector3(0.45, 0, 0.0), Vector3(0.14, 0.14, 0.14), "contain"],
		["station/soulgem", "top", Vector3(0.62, 0, 0.12), Vector3(0.1, 0.1, 0.1), "contain"],
		["clutter/book_open", "top", Vector3(-0.1, 0, 0.0), Vector3(0.4, 0.08, 0.3), "contain"],
		["clutter/candle", "top", Vector3(-0.6, 0, -0.15), Vector3(0.1, 0.25, 0.1), "contain"],
		["clutter/quill", "top", Vector3(0.15, 0, 0.18), Vector3(0.2, 0.05, 0.2), "contain"]],
	"workbench": [["prop/table", "floor", Vector3(0, 0, 0), Vector3(1.6, 0.9, 0.8), "fill"],
		["item/hammer", "top", Vector3(-0.45, 0, 0.0), Vector3(0.4, 0.08, 0.4), "contain"],
		["item/tongs", "top", Vector3(0.0, 0, 0.12), Vector3(0.45, 0.06, 0.45), "contain"],
		["prop/rope_coil", "top", Vector3(0.5, 0, -0.1), Vector3(0.35, 0.12, 0.35), "contain"],
		["clutter/candle", "top", Vector3(0.65, 0, 0.2), Vector3(0.1, 0.22, 0.1), "contain"]],
	"grindstone": [["prop/table", "floor", Vector3(0, 0, 0), Vector3(0.9, 0.75, 0.6), "fill"],
		["item/ingot", "top", Vector3(-0.2, 0, 0.0), Vector3(0.3, 0.08, 0.2), "contain"],
		["item/hammer", "top", Vector3(0.2, 0, 0.05), Vector3(0.35, 0.08, 0.35), "contain"]],
	"forge": [["station/forge", "floor", Vector3(0, 0, 0), Vector3(1.4, 1.1, 1.2), "contain"],
		["station/bellows", "floor", Vector3(0.85, 0, 0.2), Vector3(0.5, 0.5, 0.8), "contain"]],
	"smelter": [["station/oven", "floor", Vector3(0, 0, 0), Vector3(1.2, 1.6, 1.2), "contain"],
		["station/coal", "floor", Vector3(0.75, 0, 0.3), Vector3(0.6, 0.35, 0.6), "contain"]],
	"tanning_rack": [["station/hide_rack", "floor", Vector3(0, 0, 0), Vector3(1.6, 1.8, 0.4), "contain"]],
	"cooking_pot": [["prop/campfire", "floor", Vector3(0, 0, 0), Vector3(0.9, 0.3, 0.9), "contain"],
		["prop/cauldron", "floor", Vector3(0, 0.12, 0), Vector3(0.6, 0.55, 0.6), "contain"]],
	"spell_altar": [["prop/altar", "floor", Vector3(0, 0, 0), Vector3(1.2, 1.0, 0.8), "fill"],
		["clutter/book_open", "top", Vector3(0.0, 0, 0.0), Vector3(0.4, 0.08, 0.3), "contain"],
		["clutter/candle", "top", Vector3(-0.42, 0, 0.0), Vector3(0.1, 0.25, 0.1), "contain"],
		["clutter/candle", "top", Vector3(0.42, 0, 0.0), Vector3(0.1, 0.25, 0.1), "contain"]],
}
## Their glow (the forge's fire, the enchanter's gem...): kept whatever they are made of
const GLOWS := {"forge": [Vector3(0, 1.3, 0), Color(1.0, 0.5, 0.2), 1.4], "smelter": [Vector3(0, 0.5, -0.9), Color(1.0, 0.5, 0.2), 1.0],
	"cooking_pot": [Vector3(0, 0.4, 0), Color(1.0, 0.55, 0.25), 0.8], "enchanter": [Vector3(0.55, 1.3, 0), Color(0.6, 0.4, 1.0), 0.9],
	"spell_altar": [Vector3(0, 1.4, 0), Color(0.5, 0.7, 1.0), 1.1]}


func _build_from_models() -> bool:
	var look: Array = LOOKS.get(kind, [])
	if look.is_empty() or not ModelLibrary.has(String(look[0][0])):
		return false
	var top := 0.0
	for i in look.size():
		var part: Array = look[i]
		var key := String(part[0])
		if not ModelLibrary.has(key):
			continue
		var at: Vector3 = part[2]
		var size: Vector3 = part[3]
		var base_y := top if part[1] == "top" else at.y
		var m := ModelLibrary.fitted(key, AABB(Vector3(at.x - size.x * 0.5, base_y, at.z - size.z * 0.5), size), String(part[4]))
		if m == null:
			continue
		for l in m.find_children("*", "Light3D", true, false):
			l.queue_free()  # one light for the station (GLOWS), not one per candle
		m.name = "Look_" + key.get_file()
		add_child(m)
		if i == 0:
			top = ModelLibrary.bounds(self).end.y
	if GLOWS.has(kind):
		var g: Array = GLOWS[kind]
		_light(g[0], g[1], g[2])
	return true
