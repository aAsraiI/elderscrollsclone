@tool
class_name DungeonAssembler
extends RefCounted
## Stitches room modules (ModuleLibrary) into one interior, following a DungeonRecipe:
##   1. the entrance at the origin
##   2. rooms and corridors joined doorway to doorway, turned in 90 degree steps, until the
##      recipe's count is reached; the main path grows from the newest room, side branches split
##      off older ones (branching), and the kinds the recipe requires are put in first
##   3. stair rooms lift the dungeon a floor up or down (extra_floors)
##   4. the boss room on the open doorway farthest from the entrance
##   5. every doorway left open is closed with a wall (a cap)
## No two rooms share a grid cell (RoomModule.CELL x LEVEL); a room that doesn't fit is tried
## at the next doorway. The same seed always gives the same interior. Every room gets a stable id
## ("<dungeon id>/r<n>"), so its chests and enemies are saved by that id.

const MAX_TRIES := 60

## One room in the plan (before it is built)
class Placed:
	var entry
	var xform := Transform3D.IDENTITY
	var index := 0
	var depth := 0          # rooms from the entrance
	var used: Array[int] = []   # which of its doorways are joined
	var cells: Array[Vector3i] = []

var recipe: DungeonRecipe
var rng := RandomNumberGenerator.new()
var level := 1
var placed: Array[Placed] = []
var occupied := {}  # Vector3i -> room index
var counts := {}    # module path -> times used
var links: Array = []   # [room a, door a, room b, door b]
## The join to a hidden room (InteriorFeatures walls it off behind a loose stone), or []
var secret_link: Array = []
## The hand-made set-piece's room index, or -1
var set_piece := -1
var set_tried := false


## Plans an interior. Returns the plan (no nodes yet): call build() to make the scene.
static func plan(r: DungeonRecipe, seed_value: int, lvl: int) -> DungeonAssembler:
	var a: DungeonAssembler
	for attempt in 6:  # a plan that found no room for its boss is made again (same seeds every time)
		a = DungeonAssembler.new()
		a.recipe = r
		a.level = lvl
		a.rng.seed = seed_value + attempt * 104729
		a._run()
		if not r.boss or a.placed.any(func(p: Placed) -> bool: return p.entry.role == RoomModule.Role.BOSS):
			break
	return a


func _run() -> void:
	var theme := String(recipe.themes[0]) if not recipe.themes.is_empty() else "fort"
	var entrances := _pool(theme, RoomModule.Role.ENTRANCE)
	if entrances.is_empty():
		push_warning("DungeonAssembler: no entrance rooms for theme %s" % theme)
		return
	_add(_pick(entrances), Transform3D.IDENTITY, null)
	var target := recipe.rooms_for(level)
	var required := Array(recipe.required)
	var floors_left := recipe.extra_floors
	var tries := 0
	while _room_count() < target and tries < target * MAX_TRIES:
		tries += 1
		var open := _open_doors()
		if open.is_empty():
			break
		# the main path grows from the newest room; branches from any earlier one
		var spot: Array = open[-1] if rng.randf() > recipe.branching else open[rng.randi_range(0, open.size() - 1)]
		var from: Placed = placed[spot[0]]
		var role := _next_role(from, floors_left)
		if role == RoomModule.Role.DEAD_END and open.size() < 4:
			role = RoomModule.Role.ROOM  # never close the last ways on
		var pool := _pool(_theme_for(), role)
		if not required.is_empty() and role in [RoomModule.Role.ROOM, RoomModule.Role.HALL]:
			var want := pool.filter(func(e) -> bool: return required.has(e.kind))
			if not want.is_empty():
				pool = want
		if pool.is_empty():
			continue
		var pick = _pick(pool)
		if pick.doors.size() == 1 and open.size() < 4:
			continue  # a room with one way in would close the last ways on
		var p := _try_join(spot, pick)
		if p != null:
			required.erase(p.entry.kind)
			if p.entry.role == RoomModule.Role.STAIRS:
				floors_left -= 1
		if not set_tried and not recipe.set_pieces.is_empty() and _room_count() >= target / 2:
			set_tried = true
			_place_set_piece()
	if recipe.boss:
		_place_boss(theme)
	if rng.randf() < 0.6:
		_place_secret(theme)


func _room_count() -> int:
	return placed.filter(func(p: Placed) -> bool: return p.entry.role not in [RoomModule.Role.CORRIDOR, RoomModule.Role.JUNCTION]).size()


# A corridor between rooms now and then; stairs while floors are still wanted; else a room
func _next_role(from: Placed, floors_left: int) -> int:
	var r: int = from.entry.role
	if floors_left > 0 and rng.randf() < 0.25 and r != RoomModule.Role.STAIRS:
		return RoomModule.Role.STAIRS
	if r in [RoomModule.Role.ROOM, RoomModule.Role.HALL, RoomModule.Role.ENTRANCE, RoomModule.Role.STAIRS] and rng.randf() < recipe.corridors:
		return RoomModule.Role.JUNCTION if rng.randf() < 0.3 else RoomModule.Role.CORRIDOR
	if rng.randf() < 0.08:
		return RoomModule.Role.DEAD_END
	return RoomModule.Role.ROOM


# Mostly the main theme, sometimes a mixed-in one
func _theme_for() -> String:
	if recipe.themes.size() > 1 and rng.randf() < recipe.mix:
		return String(recipe.themes[rng.randi_range(1, recipe.themes.size() - 1)])
	return String(recipe.themes[0])


func _pool(theme: String, role: int) -> Array:
	var out: Array = []
	for e in ModuleLibrary.of(theme, role):
		if level < e.level_min or level > e.level_max:
			continue
		if e.max_per > 0 and int(counts.get(e.path, 0)) >= e.max_per:
			continue
		out.append(e)
	return out


func _pick(pool: Array):
	var total := 0.0
	for e in pool:
		total += e.weight
	var roll := rng.randf() * total
	for e in pool:
		roll -= e.weight
		if roll <= 0.0:
			return e
	return pool[-1]


## Open doorways of placed rooms: [[room index, door index]], oldest first
func _open_doors() -> Array:
	var out: Array = []
	for p in placed:
		for i in p.entry.doors.size():
			if not p.used.has(i):
				out.append([p.index, i])
	return out


func door_world(p: Placed, i: int) -> Dictionary:
	var d: Dictionary = p.entry.doors[i]
	return {"pos": p.xform * Vector3(d["pos"]), "out": (p.xform.basis * Vector3(d["out"])).normalized()}


# Tries every doorway of a module against an open doorway; places it where it fits
func _try_join(spot: Array, e) -> Placed:
	var from: Placed = placed[spot[0]]
	var a := door_world(from, spot[1])
	var fd: Dictionary = from.entry.doors[spot[1]]
	var order := range(e.doors.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for bi: int in order:
		var bd: Dictionary = e.doors[bi]
		if not _fits(fd, bd):
			continue
		var out_b: Vector3 = bd["out"]
		var want: Vector3 = -Vector3(a["out"])
		var yaw := snappedf(atan2(want.x, want.z) - atan2(out_b.x, out_b.z), PI * 0.5)
		var basis := Basis(Vector3.UP, yaw)
		var origin: Vector3 = Vector3(a["pos"]) - basis * Vector3(bd["pos"])
		var xf := Transform3D(basis, origin)
		var cells := _cells_of(e, xf)
		if cells.any(func(c: Vector3i) -> bool: return occupied.has(c)):
			continue
		var p := _add(e, xf, cells)
		p.depth = from.depth + 1
		p.used.append(bi)
		from.used.append(spot[1])
		links.append([from.index, spot[1], p.index, bi])
		return p
	return null


func _fits(a: Dictionary, b: Dictionary) -> bool:
	if absf(float(a["width"]) - float(b["width"])) > 1.0:
		return false
	var ta: PackedStringArray = a["tags"]
	var tb: PackedStringArray = b["tags"]
	if ta.is_empty() or tb.is_empty():
		return true
	for t in ta:
		if tb.has(t):
			return true
	return recipe.themes.size() > 1  # mixed recipes may join different themes


func _cells_of(e, xf: Transform3D) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in e.cells.x:
		for y in e.cells.y:
			for z in e.cells.z:
				var local := Vector3(-e.cells.x * RoomModule.CELL * 0.5 + RoomModule.CELL * 0.5 + x * RoomModule.CELL, y * RoomModule.LEVEL + 0.1,
					-e.cells.z * RoomModule.CELL * 0.5 + RoomModule.CELL * 0.5 + z * RoomModule.CELL)
				var w := xf * local
				out.append(Vector3i(floori(w.x / RoomModule.CELL), floori(w.y / RoomModule.LEVEL), floori(w.z / RoomModule.CELL)))
	return out


func _add(e, xf: Transform3D, cells: Variant) -> Placed:
	var p := Placed.new()
	p.entry = e
	p.xform = xf
	p.index = placed.size()
	p.cells = cells if cells != null else _cells_of(e, xf)
	for c in p.cells:
		occupied[c] = p.index
	placed.append(p)
	counts[e.path] = int(counts.get(e.path, 0)) + 1
	return p


# The boss room goes on the open doorway farthest from the entrance that it fits
func _place_boss(theme: String) -> void:
	var bosses := _pool(theme, RoomModule.Role.BOSS)
	if bosses.is_empty():
		return
	for attempt in 8:
		var open := _open_doors()
		open.sort_custom(func(x: Array, y: Array) -> bool: return placed[x[0]].depth > placed[y[0]].depth)
		for spot in open:
			for b in bosses:
				if _try_join(spot, b) != null:
					return
		# no room for it: lead a corridor out from a far doorway, and try again from its end
		var corridors := _pool(theme, RoomModule.Role.CORRIDOR)
		var grown := false
		for spot in open:
			if not corridors.is_empty() and _try_join(spot, _pick(corridors)) != null:
				grown = true
				break
		if not grown:
			return


# ---------------------------------------------------------------- making the scene

## Builds the planned interior under one Node3D: every room's scene in its place, caps on the
## doorways nobody joined. dungeon_id names the rooms ("<id>/r<n>", meta "room_id").
func build(dungeon_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Interior"
	# what a baked copy needs to be read back as a plan (from_scene): the joins and the hidden one
	root.set_meta("links", links.duplicate(true))
	root.set_meta("secret_link", secret_link.duplicate())
	for p in placed:
		var room := (load(p.entry.path) as PackedScene).instantiate() as RoomModule
		room.name = "R%d_%s" % [p.index, p.entry.path.get_file().get_basename()]
		room.transform = p.xform
		room.set_meta("room_id", "%s/r%d" % [dungeon_id, p.index])
		room.set_meta("depth", p.depth)
		root.add_child(room)
		var doors := room.doorways()
		for i in doors.size():
			if not p.used.has(i):
				InteriorKit.cap(doors[i], String(p.entry.themes[0]))
	return root


## The entrance room's "PlayerStart" (local to the interior), or the origin
func start_transform() -> Transform3D:
	return Transform3D.IDENTITY


## The plan in one line, for tests and the console: rooms, cells, links, floors
func summary() -> String:
	var floors := {}
	for c in occupied:
		floors[(c as Vector3i).y] = true
	return "%d rooms (%d counted), %d cells, %d links, floors %s" % [placed.size(), _room_count(), occupied.size(), links.size(), str(floors.keys())]


# One of the recipe's hand-made rooms, on the deepest open doorway it fits (no main-path dead end:
# a set-piece is somewhere you pass through or look into)
func _place_set_piece() -> void:
	var entries: Array = []
	for ps in recipe.set_pieces:
		if ps != null:
			var e := ModuleLibrary._read(ps.resource_path)
			if e != null:
				entries.append(e)
	if entries.is_empty():
		return
	var e = entries[rng.randi_range(0, entries.size() - 1)]
	var open := _open_doors()
	open.sort_custom(func(x: Array, y: Array) -> bool: return placed[x[0]].depth > placed[y[0]].depth)
	for spot in open:
		if placed[spot[0]].entry.role in [RoomModule.Role.BOSS, RoomModule.Role.DEAD_END]:
			continue
		var p := _try_join(spot, e)
		if p != null:
			set_piece = p.index
			return


## A plan read back from a built or baked interior (DungeonPreview's Bake, or a hand-made scene
## made of room modules): its rooms in child order, their places, and the joins it was built with
## (meta "links"; without them the rooms are taken as they are, and doors and levers are left out)
static func from_scene(root: Node3D) -> DungeonAssembler:
	var a := DungeonAssembler.new()
	a.recipe = DungeonRecipe.new()
	for c in root.get_children():
		var room := c as RoomModule
		if room == null or room.scene_file_path == "":
			continue
		var e := ModuleLibrary._read(room.scene_file_path)
		if e == null:
			continue
		var p := Placed.new()
		p.entry = e
		p.xform = room.transform
		p.index = a.placed.size()
		p.depth = int(room.get_meta("depth", p.index))
		p.cells = a._cells_of(e, p.xform)
		for cell in p.cells:
			a.occupied[cell] = p.index
		a.placed.append(p)
	a.links = root.get_meta("links", []).duplicate(true)
	a.secret_link = root.get_meta("secret_link", []).duplicate()
	for l: Array in a.links:
		if int(l[0]) < a.placed.size() and int(l[2]) < a.placed.size():
			a.placed[int(l[0])].used.append(int(l[1]))
			a.placed[int(l[2])].used.append(int(l[3]))
	return a


# A small room off a far doorway that will be hidden behind a loose stone
func _place_secret(theme: String) -> void:
	var small := _pool(theme, RoomModule.Role.ROOM).filter(func(e) -> bool: return e.cells.x * e.cells.z <= 4)
	small.append_array(_pool(theme, RoomModule.Role.DEAD_END))
	if small.is_empty():
		return
	var open := _open_doors()
	open.sort_custom(func(x: Array, y: Array) -> bool: return placed[x[0]].depth > placed[y[0]].depth)
	for spot in open.slice(0, 8):
		if placed[spot[0]].entry.role in [RoomModule.Role.BOSS, RoomModule.Role.ENTRANCE, RoomModule.Role.STAIRS]:
			continue
		var p := _try_join(spot, _pick(small))
		if p != null:
			secret_link = links[-1]
			return
