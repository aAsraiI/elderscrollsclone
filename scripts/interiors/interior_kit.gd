@tool
class_name InteriorKit
extends RefCounted
## The shared building blocks of interiors: one material per surface (data/interiors/materials/,
## shared by every room so they batch), each theme's choice of materials, and the code that
## builds a room's shell (floor, ceiling, walls with openings at its doorways) and the caps that
## close doorways nobody joined. tools/build_interiors.gd uses it to make the room scenes; after
## that the scenes are yours to edit by hand.

const MAT_DIR := "res://data/interiors/materials/"
const WALL := 0.4
const SLAB := 0.3

## Surface colours (low fidelity, dark fantasy). Emissive ones glow.
const COLORS := {
	"stone": Color(0.42, 0.40, 0.37), "stone_dark": Color(0.28, 0.27, 0.26), "flagstone": Color(0.35, 0.33, 0.30),
	"wood": Color(0.40, 0.27, 0.16), "wood_dark": Color(0.26, 0.18, 0.11), "wood_floor": Color(0.45, 0.31, 0.19),
	"rock": Color(0.36, 0.32, 0.27), "rock_dark": Color(0.24, 0.21, 0.18), "brick": Color(0.45, 0.30, 0.24),
	"moss_stone": Color(0.33, 0.38, 0.29), "plaster": Color(0.72, 0.66, 0.55), "water": Color(0.10, 0.18, 0.20),
	"iron": Color(0.25, 0.25, 0.27), "cloth_red": Color(0.45, 0.12, 0.10), "cloth_blue": Color(0.14, 0.18, 0.40),
	"cloth": Color(0.55, 0.50, 0.40), "bone": Color(0.82, 0.78, 0.66), "straw": Color(0.70, 0.60, 0.30),
	"gold": Color(0.75, 0.6, 0.2), "paper": Color(0.86, 0.82, 0.70), "glow": Color(1.0, 0.75, 0.45), "fungus_glow": Color(0.4, 0.9, 0.7),
	"ice": Color(0.62, 0.74, 0.82), "ash": Color(0.22, 0.20, 0.20),
}
const GLOWING := ["glow", "fungus_glow"]

## Each theme's floor, walls, ceiling and trim
const THEMES := {
	"fort": {"floor": "flagstone", "wall": "stone", "ceiling": "stone_dark", "trim": "wood_dark"},
	"crypt": {"floor": "stone_dark", "wall": "stone_dark", "ceiling": "stone_dark", "trim": "bone"},
	"cave": {"floor": "rock", "wall": "rock", "ceiling": "rock_dark", "trim": "rock_dark"},
	"mine": {"floor": "rock", "wall": "rock", "ceiling": "rock_dark", "trim": "wood"},
	"sewer": {"floor": "brick", "wall": "brick", "ceiling": "stone_dark", "trim": "iron"},
	"ruin": {"floor": "moss_stone", "wall": "moss_stone", "ceiling": "stone_dark", "trim": "stone"},
	"lair": {"floor": "ash", "wall": "rock_dark", "ceiling": "rock_dark", "trim": "bone"},
	"ice": {"floor": "ice", "wall": "ice", "ceiling": "ice", "trim": "rock"},
	"house": {"floor": "wood_floor", "wall": "plaster", "ceiling": "wood_dark", "trim": "wood_dark"},
	"rich": {"floor": "flagstone", "wall": "plaster", "ceiling": "wood_dark", "trim": "gold"},
}

static var _mats := {}


## The shared material of a surface (made and saved the first time, if it isn't there yet)
static func material(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var path := MAT_DIR + name + ".tres"
	var m: StandardMaterial3D = load(path) as StandardMaterial3D if ResourceLoader.exists(path) else null
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = COLORS.get(name, Color(0.5, 0.5, 0.5))
		m.roughness = 0.9
		if GLOWING.has(name):
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 1.5
	_mats[name] = m
	return m


## Writes every surface material to data/interiors/materials/ (the build tool calls it)
static func save_materials() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	for name in COLORS:
		var m := material(name)
		if m.resource_path == "":
			ResourceSaver.save(m, MAT_DIR + name + ".tres")
			_mats.erase(name)
			_mats[name] = load(MAT_DIR + name + ".tres")


static func surface(theme: String, part: String) -> String:
	return String(THEMES.get(theme, THEMES["fort"]).get(part, "stone"))


## A solid box: a StaticBody3D with its mesh and collision (owner: the scene being saved, or null)
static func box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: String, owner: Node = null, solid: bool = true, yaw: float = 0.0) -> Node3D:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	holder.name = name
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material(mat)
	holder.add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		holder.add_child(shape)
	parent.add_child(holder)
	holder.position = pos
	holder.rotation.y = yaw
	holder.add_to_group("interior_geometry", true)
	if owner != null:
		holder.owner = owner
		mesh.owner = owner
		for c in holder.get_children():
			c.owner = owner
	return holder


## The room's shell: a floor and ceiling per storey and walls round the edges, with openings
## where its doorways are. Everything goes under a "Shell" node.
static func shell(room: RoomModule, theme: String, owner: Node = null, ceiling: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Shell"
	room.add_child(root)
	if owner != null:
		root.owner = owner
	var b := room.bounds()
	var floor_m := surface(theme, "floor")
	var wall_m := surface(theme, "wall")
	var ceil_m := surface(theme, "ceiling")
	box(root, "Floor", Vector3(b.size.x, SLAB, b.size.z), Vector3(0, -SLAB * 0.5, 0), floor_m, owner)
	if ceiling:
		box(root, "Ceiling", Vector3(b.size.x, SLAB, b.size.z), Vector3(0, b.size.y + SLAB * 0.5, 0), ceil_m, owner)
	var doors := room.doorways()
	# four walls, each split into one piece per cell and storey so doorways can open a gap
	for side in 4:
		var along_x := side % 2 == 0
		var length := b.size.x if along_x else b.size.z
		var n := room.cells.x if along_x else room.cells.z
		var sign := -1.0 if side < 2 else 1.0
		for f in room.cells.y:
			for i in n:
				var t := -length * 0.5 + RoomModule.CELL * 0.5 + i * RoomModule.CELL
				var mid := Vector3(t, f * RoomModule.LEVEL, sign * (b.size.z * 0.5 - WALL * 0.5)) if along_x else Vector3(sign * (b.size.x * 0.5 - WALL * 0.5), f * RoomModule.LEVEL, t)
				var gap: DoorwayMarker = null
				for d in doors:
					var dp := d.position
					if absf(dp.y - f * RoomModule.LEVEL) < 0.5 and (Vector2(dp.x, dp.z) - Vector2(mid.x, mid.z)).length() < RoomModule.CELL * 0.5:
						gap = d
				_wall_piece(root, mid, along_x, gap, wall_m, owner, "Wall_%d_%d_%d" % [side, f, i])
	return root


# One cell-wide piece of wall, LEVEL high; with a doorway, it keeps an opening of the doorway's size
static func _wall_piece(root: Node3D, mid: Vector3, along_x: bool, gap: DoorwayMarker, mat: String, owner: Node, name: String) -> void:
	var h := RoomModule.LEVEL
	var w := RoomModule.CELL
	var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var thick := Vector3(0, 0, WALL) if along_x else Vector3(WALL, 0, 0)
	if gap == null:
		box(root, name, axis * w + thick + Vector3(0, h, 0), mid + Vector3(0, h * 0.5, 0), mat, owner)
		return
	var gw := minf(gap.width, w - 0.2)
	var side := (w - gw) * 0.5
	var offset := ((gap.position - mid).dot(axis))
	offset = clampf(offset, -side, side)
	var left := side + offset
	var right := side - offset
	if left > 0.05:
		box(root, name + "_L", axis * left + thick + Vector3(0, h, 0), mid - axis * (w * 0.5 - left * 0.5) + Vector3(0, h * 0.5, 0), mat, owner)
	if right > 0.05:
		box(root, name + "_R", axis * right + thick + Vector3(0, h, 0), mid + axis * (w * 0.5 - right * 0.5) + Vector3(0, h * 0.5, 0), mat, owner)
	var top := h - gap.height
	if top > 0.05:
		box(root, name + "_Top", axis * gw + thick + Vector3(0, top, 0), mid + axis * offset + Vector3(0, gap.height + top * 0.5, 0), mat, owner)


## Closes a doorway nobody joined: a piece of wall filling its opening (in the doorway's parent)
static func cap(d: DoorwayMarker, theme: String) -> Node3D:
	var room := d.get_parent() as Node3D
	var size := Vector3(d.width + 0.1, d.height + 0.05, WALL + 0.05)
	var c := box(room, "Cap_" + d.name, size, d.position + Vector3(0, d.height * 0.5, 0) + d.basis.z * (WALL * 0.5), surface(theme, "wall"))
	c.basis = d.basis
	return c
