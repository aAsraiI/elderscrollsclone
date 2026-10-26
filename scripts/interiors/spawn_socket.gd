@tool
class_name SpawnSocket
extends Marker3D
## A spot in a room (or outdoor site) where something may appear: a piece of furniture, a
## decoration, a chest, an enemy, a light... RoomFiller picks what goes here from the prop and
## spawn libraries by Kind, Tags, the room's theme and wealth, and the level. Drawn in the editor
## as a small coloured box (its colour is its kind); its -Z is the way the thing faces.

enum Kind { FURNITURE, DECORATION, WALL_DECORATION, CHEST, LOOT, ENEMY, BOSS, LIGHT, TRAP, NPC, QUEST_ITEM, PATROL, CEILING }

const COLORS := [Color(0.7, 0.45, 0.2), Color(0.6, 0.8, 0.3), Color(0.3, 0.7, 0.6), Color(1.0, 0.85, 0.2), Color(1.0, 1.0, 0.5),
	Color(0.9, 0.2, 0.2), Color(0.6, 0.0, 0.0), Color(1.0, 0.7, 0.4), Color(0.9, 0.3, 0.9), Color(0.3, 0.5, 1.0),
	Color(1.0, 0.5, 0.0), Color(0.6, 0.6, 0.6), Color(0.5, 0.5, 0.8)]

@export var kind: Kind = Kind.DECORATION:
	set(v):
		kind = v
		_redraw()
## What fits here: "table", "bed", "rack", "bones", "banner"... (empty = anything of its kind)
@export var tags: PackedStringArray = []
## The chance something appears here at all (0..1)
@export_range(0.0, 1.0) var chance := 0.75
## These exact scenes or enemy files instead of the library's choice (one is picked)
@export var pool: PackedStringArray = []
## For ENEMY: how many (a group); for LOOT: how many rolls
@export var count := 1

var _gizmo: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()


func _redraw() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _gizmo == null or not is_instance_valid(_gizmo):
		_gizmo = MeshInstance3D.new()
		_gizmo.name = "_SocketGizmo"
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 0.35)
	_gizmo.mesh = box
	_gizmo.position = Vector3(0, 0.18, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLORS[int(kind)]
	_gizmo.material_override = mat
