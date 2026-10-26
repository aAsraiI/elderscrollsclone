@tool
class_name DoorwayMarker
extends Marker3D
## Where another room may join this one (see RoomModule). Put it on the room's edge, on the floor,
## facing OUT of the room (its -Z, the blue arrow drawn in the editor). Two rooms join when two
## doorways meet face to face. A doorway nobody joins is closed with a wall (a cap).

enum Kind { DOOR, ARCH, CORRIDOR, STAIRS, LADDER, SECRET }

@export var kind: Kind = Kind.ARCH:
	set(v):
		kind = v
		_redraw()
@export var width := 2.4
@export var height := 3.0
## Only joins doorways that share one of these tags ("" = any). Keeps sewers out of forts.
@export var tags: PackedStringArray = []
## Must be joined (an entrance or a stair) rather than capped
@export var required := false

var _gizmo: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()


## Can these two doorways join?
func fits(other: DoorwayMarker) -> bool:
	if absf(width - other.width) > 0.6 or (kind == Kind.SECRET) != (other.kind == Kind.SECRET):
		return false
	if tags.is_empty() or other.tags.is_empty():
		return true
	for t in tags:
		if other.tags.has(t):
			return true
	return false


func _redraw() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _gizmo == null or not is_instance_valid(_gizmo):
		_gizmo = MeshInstance3D.new()
		_gizmo.name = "_DoorGizmo"
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var w := width * 0.5
	# the opening, and an arrow pointing out of the room
	for e in [[Vector3(-w, 0, 0), Vector3(-w, height, 0)], [Vector3(w, 0, 0), Vector3(w, height, 0)], [Vector3(-w, height, 0), Vector3(w, height, 0)],
			[Vector3(0, 0.1, 0), Vector3(0, 0.1, -1.5)], [Vector3(0, 0.1, -1.5), Vector3(-0.4, 0.1, -1.0)], [Vector3(0, 0.1, -1.5), Vector3(0.4, 0.1, -1.0)]]:
		m.surface_add_vertex(e[0])
		m.surface_add_vertex(e[1])
	m.surface_end()
	_gizmo.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = [Color(1, 0.8, 0.2), Color(0.3, 0.6, 1), Color(0.3, 1, 0.4), Color(1, 0.4, 1), Color(1, 0.6, 0.3), Color(0.8, 0.2, 0.2)][int(kind)]
	_gizmo.material_override = mat
