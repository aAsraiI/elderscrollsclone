extends "res://tools/build_interiors.gd"
## The building kit of Alpha 1.14 (yours to edit afterwards):
##   styles   data/buildings/styles/<name>.tres (BuildingStyle): how each land builds
##   parts    scenes/buildings/parts/<part>.tscn: chimney, porch, balcony, shutters, door, sign
##            bracket; each with its origin where TownBuilder puts it (see the notes below)
## Files that exist are kept; pass --force to make them again.
##   godot --headless --path . -s res://tools/build_buildings.gd [-- --force]

const PART_DIR := "res://scenes/buildings/parts/"


func _initialize() -> void:
	force = OS.get_cmdline_user_args().has("--force")
	InteriorKit.save_materials()
	_styles()
	_parts()
	print("build_buildings: %d made, %d kept as they were" % [made, kept])
	quit()


func _styles() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BuildingStyle.DIR))
	# name: [walls, wall tint, base, roof, roof tint, chimneys, porch, balcony, shutters]
	var list := {
		"timber": ["timber", Color.WHITE, "stone", "gable", Color.WHITE, true, 0.3, 0.3, 0.5],
		"northern": ["planks", Color(0.95, 0.9, 0.85), "stone", "steep", Color(0.85, 0.85, 0.9), true, 0.2, 0.15, 0.7],
		"highland": ["stone", Color.WHITE, "stone", "gable", Color(0.8, 0.8, 0.85), true, 0.2, 0.2, 0.4],
		"desert": ["adobe", Color.WHITE, "none", "flat", Color.WHITE, false, 0.4, 0.2, 0.2],
		"swamp": ["planks", Color(0.85, 0.9, 0.8), "stilts", "steep", Color(0.75, 0.8, 0.7), false, 0.5, 0.0, 0.3],
		"coastal": ["plaster", Color(1.1, 1.1, 1.1), "stone", "gable", Color(0.85, 0.9, 1.0), true, 0.3, 0.35, 0.8],
	}
	for name: String in list:
		var path := BuildingStyle.DIR + name + ".tres"
		if ResourceLoader.exists(path) and not force:
			kept += 1
			continue
		var v: Array = list[name]
		var s := BuildingStyle.new()
		s.walls = v[0]
		s.wall_tint = v[1]
		s.base = v[2]
		s.roof = v[3]
		s.roof_tint = v[4]
		s.chimneys = v[5]
		s.porch = v[6]
		s.balcony = v[7]
		s.shutters = v[8]
		ResourceSaver.save(s, path)
		made += 1


# Each part: a root Node3D named for it, its boxes made by InteriorKit (so the town merges them)
func _part(file: String, boxes: Array) -> void:
	var root := Node3D.new()
	root.name = file.to_pascal_case()
	for i in boxes.size():
		var b: Array = boxes[i]
		InteriorKit.box(root, "Box%d" % i, b[0], b[1], b[2], root, bool(b[3]) if b.size() > 3 else false)
	_save(root, PART_DIR + file + ".tscn")


func _parts() -> void:
	# a chimney: origin at the foot of it, on the roof's base line
	_part("chimney", [[Vector3(0.8, 3.4, 0.8), Vector3(0, 1.7, 0), "stone_dark"], [Vector3(1.0, 0.2, 1.0), Vector3(0, 3.45, 0), "stone"]])
	# a porch over the door: origin at the foot of the wall under the door, roof out toward -Z
	_part("porch", [[Vector3(2.6, 0.12, 1.6), Vector3(0, 2.75, -0.8), "wood_dark"], [Vector3(0.14, 2.7, 0.14), Vector3(-1.2, 1.35, -1.5), "wood"],
		[Vector3(0.14, 2.7, 0.14), Vector3(1.2, 1.35, -1.5), "wood"], [Vector3(2.6, 0.12, 1.6), Vector3(0, 0.06, -0.8), "wood_floor", true]])
	# a balcony: origin on the wall at the upper floor's level, standing out toward -Z
	_part("balcony", [[Vector3(2.4, 0.15, 1.1), Vector3(0, 0, -0.55), "wood_dark"], [Vector3(2.4, 0.9, 0.08), Vector3(0, 0.5, -1.05), "wood"],
		[Vector3(0.08, 0.9, 1.1), Vector3(-1.16, 0.5, -0.55), "wood"], [Vector3(0.08, 0.9, 1.1), Vector3(1.16, 0.5, -0.55), "wood"],
		[Vector3(0.12, 0.12, 1.0), Vector3(-1.0, -0.4, -0.5), "wood_dark"], [Vector3(0.12, 0.12, 1.0), Vector3(1.0, -0.4, -0.5), "wood_dark"]])
	# shutters: origin at the middle of a 1 m window on the wall, one each side
	_part("shutters", [[Vector3(0.5, 1.05, 0.06), Vector3(-0.78, 0, -0.04), "wood"], [Vector3(0.5, 1.05, 0.06), Vector3(0.78, 0, -0.04), "wood"]])
	# a door: origin at the foot of the doorway on the wall
	_part("door", [[Vector3(1.4, 2.3, 0.1), Vector3(0, 1.15, -0.06), "wood_dark"], [Vector3(1.6, 0.18, 0.16), Vector3(0, 2.38, -0.08), "wood"],
		[Vector3(1.2, 0.08, 0.12), Vector3(0, 0.6, -0.12), "iron"], [Vector3(1.2, 0.08, 0.12), Vector3(0, 1.7, -0.12), "iron"]])
	# a sign bracket: origin on the wall, the arm out toward -Z, the board hangs from its end
	_part("sign_bracket", [[Vector3(0.08, 0.08, 1.1), Vector3(0, 0, -0.55), "iron"], [Vector3(0.06, 0.4, 0.06), Vector3(0, -0.2, -0.05), "iron"]])
