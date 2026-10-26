class_name ActorRegistry
extends RefCounted
## Every living creature and NPC in the scene (each Enemy adds itself), plus a coarse grid so
## "who is near this spot?" only looks at a few cells instead of every actor in the world.
## Use it instead of get_tree().get_nodes_in_group("enemies"), which walks the whole scene tree.
##   ActorRegistry.all()                    every living actor
##   ActorRegistry.near(pos, 30.0)          living actors within 30 m of pos
## (A static class rather than an autoload: headless test scripts compile the game's classes
## before autoloads exist.)

## Grid cell size in meters. Most questions ask about 12-40 m, so a query touches 4-9 cells.
const CELL := 32.0

static var _actors: Array[Enemy] = []
static var _grid := {}  # Vector2i cell -> Array[Enemy]
static var _grid_frame := -1


static func add(e: Enemy) -> void:
	if e != null and not _actors.has(e):
		_actors.append(e)
		_grid_frame = -1


static func remove(e: Enemy) -> void:
	var i := _actors.find(e)
	if i >= 0:
		_actors.remove_at(i)
		_grid_frame = -1


## Every living actor in the scene. Don't change the returned array.
static func all() -> Array[Enemy]:
	return _actors


static func count() -> int:
	return _actors.size()


## Living actors whose position is within `radius` meters of `pos`
static func near(pos: Vector3, radius: float) -> Array[Enemy]:
	_build_grid()
	var out: Array[Enemy] = []
	var r2 := radius * radius
	var lo := _cell_of(pos - Vector3(radius, 0.0, radius))
	var hi := _cell_of(pos + Vector3(radius, 0.0, radius))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			for e: Enemy in _grid.get(Vector2i(cx, cz), []):
				if is_instance_valid(e) and e.global_position.distance_squared_to(pos) <= r2:
					out.append(e)
	return out


## Forgets everyone (a new game is starting)
static func clear() -> void:
	_actors.clear()
	_grid.clear()
	_grid_frame = -1


# Actors move, so the grid is rebuilt at most once per physics frame, and only when someone asks
static func _build_grid() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _grid_frame:
		return
	_grid_frame = frame
	_grid.clear()
	for i in range(_actors.size() - 1, -1, -1):
		var e = _actors[i]  # untyped: a freed actor can't be read into an Enemy variable
		if not is_instance_valid(e) or not e.is_inside_tree():
			_actors.remove_at(i)
			continue
		var c := _cell_of(e.global_position)
		if not _grid.has(c):
			_grid[c] = [] as Array[Enemy]
		_grid[c].append(e)


static func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))
