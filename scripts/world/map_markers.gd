class_name MapMarkers
extends RefCounted
## Markers you put on the map yourself (right click on the M map), with a name you type.
## They show on the map and on the compass, and are saved with the game (WorldState).

const RECORD := "map_markers"
const MAX := 50


## [{"pos": Vector2 (world x, z), "name": String}], oldest first
static func all() -> Array:
	var out: Array = []
	for m in WorldState.get_record(RECORD).get("list", []):
		out.append({"pos": Vector2(float(m[0]), float(m[1])), "name": String(m[2])})
	return out


## Adds a marker and returns its index (the oldest goes when there are MAX already)
static func add(pos: Vector2, marker_name: String) -> int:
	var list: Array = (WorldState.get_record(RECORD).get("list", []) as Array).duplicate(true)
	if list.size() >= MAX:
		list.remove_at(0)
	list.append([pos.x, pos.y, marker_name])
	WorldState.set_record(RECORD, {"list": list})
	return list.size() - 1


static func rename(index: int, marker_name: String) -> void:
	var list: Array = (WorldState.get_record(RECORD).get("list", []) as Array).duplicate(true)
	if index >= 0 and index < list.size() and marker_name.strip_edges() != "":
		list[index][2] = marker_name.strip_edges()
		WorldState.set_record(RECORD, {"list": list})


static func remove(index: int) -> void:
	var list: Array = (WorldState.get_record(RECORD).get("list", []) as Array).duplicate(true)
	if index >= 0 and index < list.size():
		list.remove_at(index)
		WorldState.set_record(RECORD, {"list": list})
