extends SceneTree
## Alpha 1.20: furniture is part of each room's scene, never picked when the game runs. This turns every
## furniture spawn point (SpawnSocket FURNITURE, DECORATION, WALL_DECORATION, LIGHT, CEILING) in the room,
## house, hand-made and site scenes into the prop the game used to pick for it (the room's first layout),
## placed as a real node you can move, delete or swap in the editor, and removes the spawn point.
## Chest, loot, enemy, boss, captive, quest-item, trap and patrol spots stay.
##   godot --headless --path . -s res://tools/bake_room_props.gd
## Safe to run again: scenes without furniture spots are left as they are. Run it after the scene
## builders (build_interiors.gd, build_houses.gd, build_handmade.gd, build_sites.gd), which still write
## spawn points (and overwrite your hand edits: do not re-run those on scenes you have edited).

const DIRS := ["res://scenes/interiors/modules/", "res://scenes/interiors/houses/", "res://scenes/interiors/setpieces/",
	"res://scenes/interiors/handmade/", "res://scenes/sites/"]
const FURNITURE := [SpawnSocket.Kind.FURNITURE, SpawnSocket.Kind.DECORATION, SpawnSocket.Kind.WALL_DECORATION,
	SpawnSocket.Kind.LIGHT, SpawnSocket.Kind.CEILING]


func _initialize() -> void:
	var scenes := 0
	var props := 0
	var dropped := 0
	for dir: String in DIRS:
		for path in _scenes(dir):
			var got := _bake(path)
			if got[0] + got[1] > 0:
				scenes += 1
				props += got[0]
				dropped += got[1]
	print("baked %d scenes: %d props placed, %d empty spots removed" % [scenes, props, dropped])
	quit()


func _scenes(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scenes(dir + d + "/"))
	return out


# [props placed, spots that came up empty]
func _bake(path: String) -> Array:
	var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN)  # as the editor opens it: instances stay instances
	if not root is Node3D:
		root.free()
		return [0, 0]
	var rooms: Array = [root] if root is RoomModule else []
	rooms.append_array(root.find_children("*", "RoomModule", true, false))
	var placed := 0
	var empty := 0
	for room: RoomModule in rooms:
		var taken: Array = []  # [position, radius] of props already placed in this room
		var template := room.scene_file_path if room.scene_file_path != "" else String(room.name)
		var theme := String(room.themes[0]) if not room.themes.is_empty() else "fort"
		for s in room.sockets():
			if s.owner != root or not s.kind in FURNITURE or _room_of(s) != room:
				continue  # another room's, or one inside an instanced room (baked in that room's own file)
			var rng := RandomNumberGenerator.new()
			rng.seed = ("%s|%d|%s" % [template, 0, s.name]).hash()  # the first of the old layouts
			var prop: Node3D = null
			if rng.randf() <= clampf(s.chance, 0.0, 1.0):
				prop = _prop(s, theme, room.wealth, rng, taken, room)
			if prop != null:
				s.add_sibling(prop, true)
				prop.owner = root
				placed += 1
			else:
				empty += 1
			s.get_parent().remove_child(s)
			s.free()
	if placed + empty > 0:
		var ps := PackedScene.new()
		if ps.pack(root) != OK or ResourceSaver.save(ps, path) != OK:
			push_error("could not save " + path)
	root.free()
	return [placed, empty]


func _room_of(n: Node) -> RoomModule:
	var p := n.get_parent()
	while p != null and not p is RoomModule:
		p = p.get_parent()
	return p as RoomModule


# What the game picked for this spot (RoomFiller._place_prop before 1.20), as a node of its own
func _prop(s: SpawnSocket, theme: String, wealth: int, rng: RandomNumberGenerator, taken: Array, room: RoomModule) -> Node3D:
	var kind_name := String(SpawnSocket.Kind.keys()[s.kind])
	var e := PropLibrary.pick(kind_name, s.tags, theme, wealth, rng)
	if e == null and not s.tags.is_empty():
		e = PropLibrary.pick(kind_name, PackedStringArray(), theme, wealth, rng)
	if e == null:
		return null
	var at := _in_room(room, s).origin
	# a spot meant to be filled every time (chance 1: a bed by a bed marker) gives way only to a real overlap
	var near := 0.5 if s.chance >= 1.0 else 1.0
	if not s.tags.has("set") and taken.any(func(t: Array) -> bool: return Vector2(at.x - t[0].x, at.z - t[0].z).length() < (e.radius + float(t[1])) * near and absf(at.y - t[0].y) < 1.5):
		return null
	var prop := (load(e.path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D  # saved as a link to the prop scene
	prop.name = e.path.get_file().get_basename().to_pascal_case()
	prop.transform = s.transform
	if s.kind != SpawnSocket.Kind.WALL_DECORATION and e.snap == InteriorProp.Snap.FLOOR and not s.tags.has("tabletop"):
		prop.rotate_y(rng.randf_range(-0.15, 0.15))  # never quite straight
	taken.append([at, e.radius])
	return prop


func _in_room(room: Node3D, n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent() as Node3D
	while p != null and p != room:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf
