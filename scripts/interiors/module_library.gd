@tool
class_name ModuleLibrary
extends RefCounted
## Every room module (scenes/interiors/modules/<theme>/*.tscn), read once: its size, role, kind,
## weight and doorways, so the stitcher can try rooms without building them. Templates are left
## out. Rooms added to the folders are found automatically.

const DIR := "res://scenes/interiors/modules/"

## One room as the stitcher sees it
class Entry:
	var path := ""
	var themes: PackedStringArray = []
	var role: int = 0
	var kind := ""
	var cells := Vector3i.ONE
	var weight := 1.0
	var max_per := 0
	var level_min := 1
	var level_max := 100
	## [{"pos": Vector3, "out": Vector3 (outward), "width", "kind", "tags", "required"}]
	var doors: Array = []
	var aabb := AABB()

static var _all: Array[Entry] = []
static var _loaded := false


static func all() -> Array[Entry]:
	if _loaded:
		return _all
	_loaded = true
	for theme in DirAccess.get_directories_at(DIR):
		if theme == "templates":
			continue
		for f in DirAccess.get_files_at(DIR + theme):
			var file := f.trim_suffix(".remap")
			if not file.ends_with(".tscn"):
				continue
			var e := _read(DIR + theme + "/" + file)
			if e != null:
				_all.append(e)
	return _all


static func _read(path: String) -> Entry:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var room := ps.instantiate() as RoomModule
	if room == null:
		return null
	var e := Entry.new()
	e.path = path
	e.themes = room.themes
	e.role = room.role
	e.kind = room.kind
	e.cells = room.cells
	e.weight = room.weight
	e.max_per = room.max_per_dungeon
	e.level_min = room.level_min
	e.level_max = room.level_max
	e.aabb = room.bounds()
	for d in room.doorways():
		var t := d.transform
		var parent := d.get_parent() as Node3D
		while parent != null and parent != room:
			t = parent.transform * t
			parent = parent.get_parent() as Node3D
		e.doors.append({"pos": t.origin, "out": -t.basis.z.normalized(), "width": d.width, "kind": int(d.kind), "tags": d.tags, "required": d.required})
	room.free()
	return e


## The rooms of a theme (optionally only one role)
static func of(theme: String, role: int = -1) -> Array[Entry]:
	var out: Array[Entry] = []
	for e in all():
		if e.themes.has(theme) and (role < 0 or e.role == role):
			out.append(e)
	return out


## Forgets what was read (after adding rooms while the game runs)
static func reload() -> void:
	_all.clear()
	_loaded = false
