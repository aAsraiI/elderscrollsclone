@tool
class_name SiteLink
extends Marker3D
## The way from an outdoor site down into its dungeon (Alpha 1.14): a door in a wall, a cave mouth,
## a hatch in a floor or a trapdoor at the top of a tower. Its -Z faces the way in. The site's
## SitePOIData names the dungeon (Dungeon, with a recipe or a hand-made scene); coming back up you
## arrive just in front of it (Return Offset, in its own space).

enum Kind { DOOR, CAVE, HATCH, TRAPDOOR }

@export var kind: Kind = Kind.DOOR:
	set(v):
		kind = v
		_redraw()
## What E says: "Enter <this>" ("the cellar", "the old crypt")
@export var label := "the depths"
@export var return_offset := Vector3(0, 0.2, 1.6)

var _gizmo: MeshInstance3D


func _ready() -> void:
	_redraw()


## Makes the door the player uses (DungeonDoor) for the place with this id
func make_door(entrance_id: String) -> DungeonDoor:
	var door := DungeonDoor.new()
	door.name = "LinkDoor"
	door.entrance_id = entrance_id
	door.label = "Enter %s" % label
	door.is_exit = false
	door.position = Vector3(0, 1.0 if kind in [Kind.DOOR, Kind.CAVE] else 0.4, 0)
	door.return_offset = return_offset - door.position
	add_child(door)
	return door


# The editor: a purple arrow pointing the way in, flat for a hatch or trapdoor
func _redraw() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _gizmo == null or not is_instance_valid(_gizmo):
		_gizmo = MeshInstance3D.new()
		_gizmo.name = "_LinkGizmo"
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var flat := kind in [Kind.HATCH, Kind.TRAPDOOR]
	var a := Vector3(0, 0.05, 0)
	var b := Vector3(0, -1.2, 0) if flat else Vector3(0, 0.05, -1.5)
	m.surface_add_vertex(a)
	m.surface_add_vertex(b)
	for side in [-1.0, 1.0]:
		m.surface_add_vertex(b)
		m.surface_add_vertex(b + (Vector3(side * 0.3, 0.4, 0) if flat else Vector3(side * 0.3, 0, 0.4)))
	m.surface_end()
	_gizmo.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.3, 1.0)
	_gizmo.material_override = mat
