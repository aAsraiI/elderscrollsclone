@tool
class_name RoomModule
extends Node3D
## One room of an interior, as a scene you can open and edit (scenes/interiors/modules/<theme>/).
## The stitcher (DungeonAssembler) joins rooms doorway to doorway into a dungeon, a fort or a
## house; the room then fills itself from its spawn points (RoomFiller).
##
## Build a room: copy a template from scenes/interiors/modules/templates/, keep the walls, floor
## and ceiling inside the box drawn in the editor (Cells x 4 m wide, Floors x 5 m high), put
## DoorwayMarker nodes on its edges where other rooms may join, and SpawnSocket nodes where
## things may appear. The origin is the middle of the floor; -Z is the room's "front".
##
## Grid: rooms are measured in cells of CELL meters, and floors of LEVEL meters, so any two
## rooms line up when their doorways meet.

const CELL := 4.0
const LEVEL := 5.0

enum Role { ROOM, HALL, CORRIDOR, JUNCTION, ENTRANCE, STAIRS, BOSS, DEAD_END, SECRET }

## What this room fits: fort, crypt, cave, mine, sewer, ruin, lair, house, inn, shop...
@export var themes: PackedStringArray = []
@export var role: Role = Role.ROOM
## What kind of room it is, for recipes that need one (barracks, war_room, kitchen, armory...)
@export var kind := ""
## Size in cells: x (width), y (floors), z (depth)
@export var cells := Vector3i(2, 1, 2):
	set(v):
		cells = Vector3i(maxi(v.x, 1), maxi(v.y, 1), maxi(v.z, 1))
		_redraw()
@export var level_min := 1
@export var level_max := 100
## How often the stitcher picks it, against other rooms of the same role
@export var weight := 1.0
## Most of this room in one dungeon (0 = no limit)
@export var max_per_dungeon := 0
## Wealth of what fills it: 0 poor, 1 common, 2 rich
@export_range(0, 2) var wealth := 1

var _gizmo: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()


## The room's box in its own space
func bounds() -> AABB:
	return AABB(Vector3(-cells.x * CELL * 0.5, 0.0, -cells.z * CELL * 0.5), Vector3(cells.x * CELL, cells.y * LEVEL, cells.z * CELL))


func doorways() -> Array[DoorwayMarker]:
	var out: Array[DoorwayMarker] = []
	for c in find_children("*", "DoorwayMarker", true, false):
		out.append(c as DoorwayMarker)
	return out


func sockets() -> Array[SpawnSocket]:
	var out: Array[SpawnSocket] = []
	for c in find_children("*", "SpawnSocket", true, false):
		out.append(c as SpawnSocket)
	return out


## The grid cells (x, floor, z) this room covers, in its own space
func local_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in cells.x:
		for y in cells.y:
			for z in cells.z:
				out.append(Vector3i(x, y, z))
	return out


## The middle of one of its cells, in its own space
func cell_center(c: Vector3i) -> Vector3:
	return Vector3(-cells.x * CELL * 0.5 + CELL * 0.5 + c.x * CELL, c.y * LEVEL + LEVEL * 0.5, -cells.z * CELL * 0.5 + CELL * 0.5 + c.z * CELL)


## Problems with this room (the module checker): doorways off the edges, sockets in the air
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var b := bounds()
	if themes.is_empty():
		out.append("%s: no themes" % name)
	for d in doorways():
		var p := d.position
		var on_x := absf(absf(p.x) - b.size.x * 0.5) < 0.3
		var on_z := absf(absf(p.z) - b.size.z * 0.5) < 0.3
		if not (on_x or on_z):
			out.append("%s: doorway %s is not on an edge (%s)" % [name, d.name, p])
		if absf(fposmod(p.y, LEVEL)) > 0.3 and absf(fposmod(p.y, LEVEL) - LEVEL) > 0.3:
			out.append("%s: doorway %s is not at a floor's height" % [name, d.name])
		var out_dir := -d.global_basis.z if d.is_inside_tree() else -d.basis.z
		var outward := Vector3(signf(p.x) if on_x else 0.0, 0.0, signf(p.z) if on_z else 0.0)
		if out_dir.dot(outward) < 0.7:
			out.append("%s: doorway %s does not face out of the room" % [name, d.name])
	for s in sockets():
		if not b.grow(0.5).has_point(s.position):
			out.append("%s: socket %s is outside the room" % [name, s.name])
	return out


# The editor: the room's box as a wireframe
func _redraw() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _gizmo == null or not is_instance_valid(_gizmo):
		_gizmo = MeshInstance3D.new()
		_gizmo.name = "_BoundsGizmo"
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)
	var m := ImmediateMesh.new()
	var b := bounds()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := [b.position, b.position + Vector3(b.size.x, 0, 0), b.position + Vector3(b.size.x, 0, b.size.z), b.position + Vector3(0, 0, b.size.z)]
	for i in 4:
		var a: Vector3 = c[i]
		var n: Vector3 = c[(i + 1) % 4]
		for h in [0.0, b.size.y]:
			m.surface_add_vertex(a + Vector3(0, h, 0))
			m.surface_add_vertex(n + Vector3(0, h, 0))
		m.surface_add_vertex(a)
		m.surface_add_vertex(a + Vector3(0, b.size.y, 0))
	m.surface_end()
	_gizmo.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.9, 1.0)
	_gizmo.material_override = mat
