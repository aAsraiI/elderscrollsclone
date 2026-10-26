extends "res://tools/build_interiors.gd"
## Makes the town building interiors of Alpha 1.13 (scenes/interiors/houses/): cottages, houses
## with a bedroom, farmhouses, two-storey manors, shops with a counter and a back room, smithies
## and inns with rooms upstairs. Each is a RoomModule scene (kind = house, farm, manor, shop,
## smithy, inn) with spawn points for its furniture and markers that tell InteriorBuilder where
## the working things go:
##   Door, ExitSpot, Start        the way out, where people leave from, where you arrive
##   Bed<n>, Seat<n>, Work        where the people who live here sleep, sit and work
##   Chest<n>                     the owner's chests (Chest0 is "building/<id>/chest_0")
##   Station_<kind>               a crafting station (Station_trade: the shop's trade decides)
##   Spare<n>                     room for what you add to a home you own (stations, planters)
##   Notice                       the inn's notice board
##   Via_<spot>_<n>               the way to a spot behind a wall or upstairs, in order
## A scene that exists is never overwritten (hand edits are safe); pass --force to rebuild.
##   godot --headless --path . -s res://tools/build_houses.gd [-- --force]

const HOUSE_DIR := "res://scenes/interiors/houses/"

## [file, kind, cells, theme, wealth, layout, side]
const HOUSES := [
	["cottage_a", "house", Vector3i(2, 1, 2), "house", 0, "one", 1],
	["cottage_b", "house", Vector3i(2, 1, 2), "house", 0, "one", -1],
	["house_a", "house", Vector3i(3, 1, 2), "house", 1, "side", 1],
	["house_b", "house", Vector3i(3, 1, 2), "house", 1, "side", -1],
	["house_c", "house", Vector3i(2, 1, 3), "house", 1, "back", 1],
	["farmhouse_a", "farm", Vector3i(3, 1, 2), "house", 0, "side", 1],
	["farmhouse_b", "farm", Vector3i(3, 1, 3), "house", 0, "back", 1],
	["manor_a", "manor", Vector3i(3, 2, 3), "rich", 2, "manor", 1],
	["manor_b", "manor", Vector3i(4, 2, 3), "rich", 2, "manor", 1],
	["shop_a", "shop", Vector3i(3, 1, 2), "house", 1, "shop", 1],
	["shop_b", "shop", Vector3i(3, 1, 2), "house", 1, "shop", -1],
	["smithy_a", "smithy", Vector3i(3, 1, 2), "fort", 1, "smithy", 1],
	["smithy_b", "smithy", Vector3i(3, 1, 2), "fort", 1, "smithy", -1],
	["inn_a", "inn", Vector3i(3, 2, 3), "house", 1, "inn", 1],
	["inn_b", "inn", Vector3i(4, 2, 3), "house", 1, "inn", 1],
	# with a cellar: the house sits a storey up, a trapdoor and ladder go down to the stores
	["house_d", "house", Vector3i(3, 2, 2), "house", 1, "side", 1, "store"],
	["farmhouse_c", "farm", Vector3i(3, 2, 3), "house", 0, "back", 1, "store"],
	["temple_a", "temple", Vector3i(4, 1, 4), "rich", 1, "temple", 1],
	["temple_b", "temple", Vector3i(4, 1, 4), "rich", 1, "temple", -1],
	["guild_a", "guild", Vector3i(3, 1, 3), "house", 1, "guild", 1],
	["guild_b", "guild", Vector3i(4, 1, 3), "house", 1, "guild", -1],
	# a lord's hall over the cells, stairs down from the hall
	["seat_a", "seat", Vector3i(4, 2, 5), "fort", 2, "seat", 1, "cells"],
	["seat_b", "seat", Vector3i(5, 2, 5), "fort", 2, "seat", 1, "cells"],
]

var _theme := "house"
var _beds := 0
var _seats := 0
var _spares := 0
var _upper := false  # a storey above the ground floor (manors, inns)


func _initialize() -> void:
	force = OS.get_cmdline_user_args().has("--force")
	InteriorKit.save_materials()
	for h: Array in HOUSES:
		_house(h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7] if h.size() > 7 else "")
	print("build_houses: %d scenes made, %d kept as they were" % [made, kept])
	quit()


func _house(file: String, kind: String, cells: Vector3i, theme: String, wealth: int, layout: String, s: int, cellar: String) -> void:
	var room := RoomModule.new()
	room.name = file.to_pascal_case()
	room.themes = PackedStringArray([theme, "house"])
	room.kind = kind
	room.cells = cells
	room.wealth = wealth
	_theme = theme
	_beds = 0
	_seats = 0
	_spares = 0
	_upper = layout in ["manor", "inn"]
	InteriorKit.shell(room, theme, room)
	var first := room.get_child_count()
	var b := room.bounds()
	var hx := b.size.x * 0.5
	var hz := b.size.z * 0.5
	# the front door in the middle of the -Z wall
	InteriorKit.box(room, "FrontDoor", Vector3(1.6, 2.4, 0.12), Vector3(0, 1.2, -hz + InteriorKit.WALL + 0.06), "wood_dark", room, false)
	_marker(room, "Door", Vector3(0, 0, -hz + 0.7), PI)
	_marker(room, "ExitSpot", Vector3(0, 0, -hz + 1.8), PI)
	_marker(room, "Start", Vector3(0, 0, -hz + 2.6), PI)
	match layout:
		"one":
			_one(room, hx, hz, s)
		"side":
			_side(room, hx, hz, s, kind == "farm")
		"back":
			_back(room, hx, hz, kind == "farm")
		"manor":
			_manor(room, hx, hz)
		"shop":
			_shop(room, hx, hz, s)
		"smithy":
			_smithy(room, hx, hz, s)
		"inn":
			_inn(room, hx, hz)
		"temple":
			_temple(room, hx, hz, s)
		"guild":
			_guild(room, hx, hz, s)
		"seat":
			_seat(room, hx, hz)
	# the small things: a light by the door, a bucket or sack, cobwebs in the poor ones
	_socket(room, S.LIGHT, ["candle"], Vector3(hx - 1.0, 0, -hz + 1.0), 0.0, 0.8, 1)
	_socket(room, S.DECORATION, ["bucket", "sack", "barrel"], Vector3(-hx + 0.9, 0, -hz + 0.9), 0.0, 0.7, 1)
	if wealth == 0:
		_socket(room, S.CEILING, ["cobweb"], Vector3(-hx + 1.0, RoomModule.LEVEL - 0.05, hz - 1.0), 0.0, 0.5, 1)
	# a cellar: everything so far moves up a storey and the cellar goes under it
	var ground := 0.0
	if cellar != "":
		ground = RoomModule.LEVEL
		for i in range(first, room.get_child_count()):
			(room.get_child(i) as Node3D).position.y += ground
		if cellar == "cells":
			_cells(room, hx, hz)
		else:
			_store(room, hx, hz, s, layout)
	var trim := InteriorKit.surface(theme, "trim")
	for f in cells.y:
		for i in cells.z * 2:
			InteriorKit.box(room, "Beam%d_%d" % [f, i], Vector3(b.size.x - 0.8, 0.22, 0.25), Vector3(0, (f + 1) * RoomModule.LEVEL - 0.15 - (InteriorKit.SLAB if f + 1 < cells.y else 0.0), -hz + (i + 0.5) * b.size.z / (cells.z * 2)), trim, room, false)
	_windows(room, hx, hz, ground)
	if _upper:
		_windows(room, hx, hz, RoomModule.LEVEL)
	_save(room, HOUSE_DIR + file + ".tscn")


# ---------------------------------------------------------------- the pieces

# A bed (its spawn point and the marker people sleep at); via = the way there, in order
func _bed(room: RoomModule, at: Vector3, yaw: float, via: Array = []) -> void:
	var n := "Bed%d" % _beds
	_beds += 1
	_marker(room, n, at, yaw)
	_socket(room, S.FURNITURE, ["bed"], at, yaw, 1.0, 1)
	_via(room, n, via)


func _via(room: RoomModule, spot: String, via: Array) -> void:
	for i in via.size():
		_marker(room, "Via_%s_%d" % [spot, i], via[i], 0.0)


# A table with stools round it; the seats are where people stand or sit by it
func _table(room: RoomModule, at: Vector3, around: int, tags: Array = ["table"]) -> void:
	_socket(room, S.FURNITURE, tags, at, 0.0, 1.0, 1)
	var offs := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	for i in around:
		var o: Vector3 = offs[i]
		_socket(room, S.FURNITURE, ["stool", "chair", "bench", "set"], at + o * Vector3(0.95, 0, 0.75), atan2(-o.x, -o.z), 0.85, 1)
		_marker(room, "Seat%d" % _seats, at + o * Vector3(1.45, 0, 1.2), 0.0)
		_seats += 1


func _spare(room: RoomModule, at: Vector3, yaw: float) -> void:
	_marker(room, "Spare%d" % _spares, at, yaw)
	_spares += 1


# An inner wall from a to b (x, z), one storey high at height y, with 1.4 m doorways at the gaps
func _partition(room: RoomModule, name: String, a: Vector2, b: Vector2, gaps: Array, y: float = 0.0) -> void:
	var mat := InteriorKit.surface(_theme, "wall")
	var along_x := absf(a.y - b.y) < 0.01
	var lo := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var fixed := a.y if along_x else a.x
	var h := RoomModule.LEVEL - (InteriorKit.SLAB if y == 0.0 and _upper else 0.0)
	var cuts := [lo]
	gaps.sort()
	for g: float in gaps:
		cuts.append(g - 0.7)
		cuts.append(g + 0.7)
	cuts.append(hi)
	for i in range(0, cuts.size(), 2):
		var s0: float = cuts[i]
		var s1: float = cuts[i + 1]
		if s1 - s0 < 0.05:
			continue
		var mid := (s0 + s1) * 0.5
		InteriorKit.box(room, "%s_%d" % [name, i / 2], Vector3(s1 - s0, h, 0.25) if along_x else Vector3(0.25, h, s1 - s0),
			Vector3(mid, y + h * 0.5, fixed) if along_x else Vector3(fixed, y + h * 0.5, mid), mat, room)
	for g: float in gaps:  # the lintel over each doorway
		InteriorKit.box(room, "%s_Lintel%d" % [name, gaps.find(g)], Vector3(1.4, h - 2.4, 0.25) if along_x else Vector3(0.25, h - 2.4, 1.4),
			Vector3(g, y + 2.4 + (h - 2.4) * 0.5, fixed) if along_x else Vector3(fixed, y + 2.4 + (h - 2.4) * 0.5, g), mat, room)


# A flight of stairs along Z at x, from z0 on the floor to z1 a storey up (a walkable slope under
# the steps), with a landing and the upper floor beside it
func _flight(room: RoomModule, x: float, z0: float, z1: float) -> void:
	var holder := Node3D.new()
	holder.name = "Stairs"
	room.add_child(holder)
	holder.owner = room
	holder.position.x = x
	var steps := 14
	var dz := (z1 - z0) / steps
	for i in steps:
		var sh := RoomModule.LEVEL * (i + 1) / float(steps)
		InteriorKit.box(holder, "Step%d" % i, Vector3(2.4, sh, dz), Vector3(0, sh * 0.5, z0 + dz * (i + 0.5)), "wood", room, false)
	_ramp(holder, room, 2.4, z0, 0.0, z1, RoomModule.LEVEL, "", false)


# ---------------------------------------------------------------- layouts

# One room: the bed in a back corner, the hearth and pot on one side, the table in the middle
func _one(room: RoomModule, hx: float, hz: float, s: int) -> void:
	_bed(room, Vector3(-s * (hx - 1.0), 0, hz - 1.4), 0.0)
	_socket(room, S.DECORATION, ["crate", "barrel"], Vector3(-s * (hx - 2.2), 0, hz - 0.6), 0.0, 1.0, 1)  # by the bed
	_socket(room, S.FURNITURE, ["hearth"], Vector3(s * (hx - 0.45), 0, 0.5), s * PI * 0.5, 1.0, 1)
	_marker(room, "Station_cooking_pot", Vector3(s * (hx - 1.4), 0, 2.4), s * PI * 0.5)
	_marker(room, "Work", Vector3(s * (hx - 2.2), 0, 2.4), 0.0)
	_table(room, Vector3(-s * 0.8, 0, -0.2), 2)
	_marker(room, "Chest0", Vector3(-s * (hx - 0.6), 0, 0.6), -s * PI * 0.5)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(s * 1.0, 0, hz - 0.45), 0.0, 0.9, 1)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(-s * (hx - 0.45), 0, -1.4), -s * PI * 0.5, 1.0, 1)
	_socket(room, S.DECORATION, ["crate", "barrel"], Vector3(s * (hx - 0.6), 0, -1.2), 0.0, 0.9, 1)
	_socket(room, S.DECORATION, ["barrel", "crate", "sack"], Vector3(-s * 1.2, 0, hz - 0.7), 0.0, 0.8, 1)
	_spare(room, Vector3(-s * (hx - 0.5), 0, -hz + 2.0), -s * PI * 0.5)
	_spare(room, Vector3(s * 2.2, 0, -hz + 0.5), PI)
	_spare(room, Vector3(-s * 2.2, 0, -hz + 0.5), PI)
	_spare(room, Vector3(s * (hx - 0.5), 0, -hz + 2.0), s * PI * 0.5)


# A main room and a bedroom down one side, through a doorway near the front
func _side(room: RoomModule, hx: float, hz: float, s: int, farm: bool) -> void:
	var px := s * (hx - RoomModule.CELL)
	var gz := -hz + 2.0
	_partition(room, "InnerWall", Vector2(px, -hz), Vector2(px, hz), [gz])
	var via := [Vector3(px - s * 1.0, 0, gz), Vector3(px + s * 1.0, 0, gz)]
	_bed(room, Vector3(s * (hx - 1.0), 0, hz - 1.4), 0.0, via)
	_bed(room, Vector3(s * (hx - 2.7), 0, hz - 1.4), 0.0, via)
	_marker(room, "Chest0", Vector3(s * (hx - 0.7), 0, -hz + 1.2), s * PI * 0.5)
	_socket(room, S.DECORATION, ["crate", "barrel"], Vector3(s * (hx - 0.6), 0, -hz + 2.6), 0.0, 1.0, 1)
	_socket(room, S.DECORATION, ["crate", "barrel", "sack"], Vector3(-s * (hx - 0.6), 0, hz - 0.8), 0.0, 0.9, 1)
	_socket(room, S.FURNITURE, ["shelf", "bookshelf", "storage"], Vector3(s * (hx - 0.45), 0, 0.3), s * PI * 0.5, 0.8, 1)
	var c := (-s * hx + px) * 0.5
	_socket(room, S.FURNITURE, ["hearth"], Vector3(-s * (hx - 0.45), 0, 0.5), -s * PI * 0.5, 1.0, 1)
	_marker(room, "Station_cooking_pot", Vector3(-s * (hx - 1.4), 0, 2.2), -s * PI * 0.5)
	_marker(room, "Work", Vector3(-s * (hx - 2.3), 0, 2.2), 0.0)
	_table(room, Vector3(c, 0, 0.4), 2)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(c, 0, hz - 0.45), 0.0, 0.9, 1)
	_socket(room, S.WALL_DECORATION, ["shield", "tapestry", "banner"], Vector3(c - s * 1.5, 0, -hz + 0.45), PI, 0.5, 1)
	if farm:
		for z in [0.2, 1.4]:
			_socket(room, S.DECORATION, ["sack", "barrel", "crate", "hay"], Vector3(px - s * 0.6, 0, z), 0.0, 0.9, 1)
	_spare(room, Vector3(-s * (hx - 0.5), 0, -hz + 1.8), -s * PI * 0.5)
	_spare(room, Vector3(c - s * 1.5, 0, -hz + 1.2), PI)
	_spare(room, Vector3(px - s * 0.5, 0, hz - 1.0), s * PI * 0.5)
	_spare(room, Vector3(c, 0, -hz + 2.6), 0.0)


# A main room in front and the bedroom across the back
func _back(room: RoomModule, hx: float, hz: float, farm: bool) -> void:
	var pz := hz - RoomModule.CELL
	var gx := hx - 2.0
	_partition(room, "InnerWall", Vector2(-hx, pz), Vector2(hx, pz), [gx])
	var via := [Vector3(gx, 0, pz - 1.0), Vector3(gx, 0, pz + 1.0)]
	for i in (3 if farm and hx >= 6.0 else 2):
		_bed(room, Vector3(-hx + 1.0 + i * 1.7, 0, hz - 1.4), 0.0, via)
	_marker(room, "Chest0", Vector3(hx - 0.7, 0, hz - 1.0), PI * 0.5)
	_socket(room, S.DECORATION, ["crate", "barrel"], Vector3(hx - 0.6, 0, pz - 0.7), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(0.6, 0, hz - 0.45), 0.0, 0.9, 1)
	_socket(room, S.FURNITURE, ["hearth"], Vector3(hx - 0.45, 0, pz - 2.6), PI * 0.5, 1.0, 1)
	_marker(room, "Station_cooking_pot", Vector3(hx - 1.4, 0, pz - 4.4), PI * 0.5)
	_marker(room, "Work", Vector3(hx - 2.2, 0, pz - 4.4), 0.0)
	_table(room, Vector3(-hx + 2.6, 0, pz - 2.4), 2)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(-hx + 0.45, 0, pz - 0.9), -PI * 0.5, 0.9, 1)
	if farm:
		for z in [pz + 1.0, pz + 2.4]:
			_socket(room, S.DECORATION, ["sack", "barrel", "crate", "hay"], Vector3(hx - 0.6, 0, z), 0.0, 0.9, 1)
	_spare(room, Vector3(-hx + 0.5, 0, -hz + 1.8), -PI * 0.5)
	_spare(room, Vector3(hx - 0.5, 0, -hz + 1.8), PI * 0.5)
	_spare(room, Vector3(-hx + 1.8, 0, -hz + 0.5), PI)
	_spare(room, Vector3(hx - 1.8, 0, -hz + 0.5), PI)


# Two storeys: a hall with the long table and the hearth, the bedroom behind it, stairs up the west
# wall to a study and a guest bed
func _manor(room: RoomModule, hx: float, hz: float) -> void:
	var sx := -hx + 1.6
	var z0 := -hz + 1.0
	var z1 := hz - 2.0
	var top := RoomModule.LEVEL
	var floor_m := InteriorKit.surface(_theme, "floor")
	_flight(room, sx, z0, z1)
	InteriorKit.box(room, "Landing", Vector3(2.8, InteriorKit.SLAB, 2.0), Vector3(-hx + 1.4, top - InteriorKit.SLAB * 0.5, hz - 1.0), floor_m, room)
	InteriorKit.box(room, "UpperFloor", Vector3(hx * 2.0 - 2.8, InteriorKit.SLAB, hz * 2.0), Vector3(1.4, top - InteriorKit.SLAB * 0.5, 0), floor_m, room)
	InteriorKit.box(room, "Rail", Vector3(0.15, 1.0, hz * 2.0 - 2.0), Vector3(-hx + 2.8, top + 0.5, -1.0), InteriorKit.surface(_theme, "trim"), room)
	var pz := hz - RoomModule.CELL
	_partition(room, "InnerWall", Vector2(-hx + 2.8, pz), Vector2(hx, pz), [hx - 2.5])
	var via := [Vector3(hx - 2.5, 0, pz - 1.0), Vector3(hx - 2.5, 0, pz + 1.0)]
	_bed(room, Vector3(hx - 1.0, 0, hz - 1.4), 0.0, via)
	_bed(room, Vector3(hx - 2.9, 0, hz - 1.4), 0.0, via)
	_marker(room, "Chest0", Vector3(-hx + 3.6, 0, hz - 0.8), 0.0)
	_socket(room, S.FURNITURE, ["hearth"], Vector3(hx - 0.45, 0, -1.5), PI * 0.5, 1.0, 1)
	_marker(room, "Station_cooking_pot", Vector3(hx - 1.4, 0, 0.6), PI * 0.5)
	_marker(room, "Work", Vector3(hx - 2.3, 0, 0.6), 0.0)
	_table(room, Vector3(0.5, 0, -1.5), 4, ["table"])
	_socket(room, S.FURNITURE, ["armor", "statue"], Vector3(hx - 0.9, 0, -hz + 1.4), PI * 0.5, 0.8, 1)
	_socket(room, S.WALL_DECORATION, ["tapestry", "banner"], Vector3(hx - 2.6, 0, -hz + 0.45), PI, 1.0, 1)
	_socket(room, S.WALL_DECORATION, ["tapestry", "banner"], Vector3(0.5, 0, pz - 0.15), 0.0, 0.8, 1)
	# upstairs: a guest bed, the strongbox, books and a writing table
	_bed(room, Vector3(hx - 1.0, top, hz - 1.4), 0.0, [Vector3(sx, 0, z0 - 0.4), Vector3(sx, top, hz - 1.0), Vector3(-hx + 3.6, top, hz - 1.0)])
	_marker(room, "Chest1", Vector3(hx - 0.8, top, -hz + 1.0), PI * 0.5)
	_socket(room, S.FURNITURE, ["bookshelf"], Vector3(0.0, top, hz - 0.45), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["bookshelf", "shelf"], Vector3(-1.6, top, -hz + 0.45), PI, 0.8, 1)
	_socket(room, S.FURNITURE, ["table"], Vector3(1.5, top, -1.0), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["chair", "stool"], Vector3(1.5, top, -0.2), PI, 0.9, 1)
	_socket(room, S.LIGHT, ["candle"], Vector3(hx - 2.2, top, hz - 0.8), 0.0, 0.9, 1)
	_socket(room, S.WALL_DECORATION, ["tapestry", "banner"], Vector3(hx - 0.45, top, 0.0), PI * 0.5, 0.8, 1)
	_spare(room, Vector3(hx - 0.5, 0, -hz + 2.8), PI * 0.5)
	_spare(room, Vector3(2.5, 0, -hz + 0.5), PI)
	_spare(room, Vector3(-1.8, 0, -hz + 0.5), PI)
	_spare(room, Vector3(-1.0, 0, pz - 0.5), 0.0)


# A shop: the counter with the keeper behind it, shelves on the back wall, goods on display in
# front, the keeper's bed and stores in a back room through a doorway at the back
func _shop(room: RoomModule, hx: float, hz: float, s: int) -> void:
	var px := s * (hx - RoomModule.CELL)
	var gz := hz - 1.6
	_partition(room, "InnerWall", Vector2(px, -hz), Vector2(px, hz), [gz])
	var c := (-s * hx + px) * 0.5
	InteriorKit.box(room, "Counter", Vector3(3.5, 1.0, 0.7), Vector3(c - s * 0.75, 0.5, 1.0), "wood", room)
	InteriorKit.box(room, "CounterTop", Vector3(3.6, 0.06, 0.8), Vector3(c - s * 0.75, 1.03, 1.0), "wood_dark", room, false)
	_marker(room, "Work", Vector3(c, 0, 2.0), 0.0)
	_via(room, "Work", [Vector3(c + s * 1.8, 0, 1.0)])
	_marker(room, "Chest0", Vector3(c - s * 2.6, 0, hz - 0.8), 0.0)
	_marker(room, "Station_trade", Vector3(-s * (hx - 0.5), 0, -0.8), -s * PI * 0.5)
	for x in [c - 1.5, c + 1.5]:
		_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(x, 0, hz - 0.45), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["table", "crate", "barrel"], Vector3(c, 0, -1.6), 0.0, 0.9, 1)
	_socket(room, S.DECORATION, ["crate", "barrel", "sack"], Vector3(c - s * 2.6, 0, -2.4), 0.0, 0.8, 1)
	_marker(room, "Seat0", Vector3(c - s * 1.0, 0, -0.2), 0.0)  # customers wait at the counter
	_marker(room, "Seat1", Vector3(c + s * 0.4, 0, -0.4), 0.0)
	# the back room
	_bed(room, Vector3(s * (hx - 1.0), 0, -hz + 1.4), PI, [Vector3(px - s * 1.0, 0, gz), Vector3(px + s * 1.0, 0, gz)])
	_socket(room, S.DECORATION, ["crate", "barrel", "sack"], Vector3(s * (hx - 0.7), 0, hz - 0.8), 0.0, 0.9, 1)
	_socket(room, S.DECORATION, ["crate", "barrel", "sack"], Vector3(s * (hx - 0.7), 0, 1.0), 0.0, 0.8, 1)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(px + s * 0.45, 0, -1.4), -s * PI * 0.5, 0.8, 1)


# A smithy: the forge and smelter at the back, the anvil in the middle, the bench and wheel by
# the door, racks of work on the walls
func _smithy(room: RoomModule, hx: float, hz: float, s: int) -> void:
	_marker(room, "Station_forge", Vector3(s * (hx - 1.2), 0, hz - 1.2), 0.0)
	_marker(room, "Station_smelter", Vector3(s * (hx - 0.8), 0, hz - 3.0), 0.0)
	_marker(room, "Station_tanning_rack", Vector3(-s * (hx - 0.3), 0, -hz + 2.0), s * PI * 0.5)
	_marker(room, "Station_grindstone", Vector3(-s * hx * 0.5, 0, -hz + 0.8), 0.0)
	_marker(room, "Station_workbench", Vector3(s * hx * 0.4, 0, -hz + 0.6), 0.0)
	_socket(room, S.FURNITURE, ["anvil"], Vector3(0, 0, 0.6), 0.0, 1.0, 1)
	_marker(room, "Work", Vector3(0, 0, 1.5), 0.0)
	_socket(room, S.FURNITURE, ["rack", "weapons"], Vector3(-s * (hx - 1.5), 0, hz - 0.45), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["armor", "rack"], Vector3(-s * (hx - 3.4), 0, hz - 0.6), 0.0, 0.8, 1)
	_socket(room, S.DECORATION, ["barrel", "crate"], Vector3(s * (hx - 2.6), 0, hz - 0.7), 0.0, 0.8, 1)
	_bed(room, Vector3(s * (hx - 0.8), 0, -hz + 1.6), PI)
	_marker(room, "Chest0", Vector3(-s * (hx - 0.8), 0, 0.0), -s * PI * 0.5)


# An inn: the bar down the west wall, tables before the hearth, stairs up the east wall to three
# rooms for guests
func _inn(room: RoomModule, hx: float, hz: float) -> void:
	var sx := hx - 1.6
	var z0 := -hz + 1.0
	var z1 := hz - 2.0
	var top := RoomModule.LEVEL
	var floor_m := InteriorKit.surface(_theme, "floor")
	_flight(room, sx, z0, z1)
	InteriorKit.box(room, "Landing", Vector3(2.8, InteriorKit.SLAB, 2.0), Vector3(hx - 1.4, top - InteriorKit.SLAB * 0.5, hz - 1.0), floor_m, room)
	InteriorKit.box(room, "UpperFloor", Vector3(hx * 2.0 - 2.8, InteriorKit.SLAB, hz * 2.0), Vector3(-1.4, top - InteriorKit.SLAB * 0.5, 0), floor_m, room)
	InteriorKit.box(room, "Rail", Vector3(0.15, 1.0, hz * 2.0 - 2.0), Vector3(hx - 2.8, top + 0.5, -1.0), InteriorKit.surface(_theme, "trim"), room)
	# the bar
	InteriorKit.box(room, "Bar", Vector3(0.7, 1.1, 4.8), Vector3(-hx + 2.4, 0.55, 0.0), "wood", room)
	InteriorKit.box(room, "BarTop", Vector3(0.8, 0.06, 4.9), Vector3(-hx + 2.4, 1.13, 0.0), "wood_dark", room, false)
	_marker(room, "Work", Vector3(-hx + 1.3, 0, -0.6), 0.0)
	_via(room, "Work", [Vector3(-hx + 1.3, 0, -3.4)])
	_socket(room, S.FURNITURE, ["barrel", "drink"], Vector3(-hx + 0.45, 0, 1.0), -PI * 0.5, 1.0, 1)
	_marker(room, "Chest0", Vector3(-hx + 0.9, 0, 3.2), -PI * 0.5)
	_marker(room, "Notice", Vector3(-2.6, 0, -hz + 0.15), 0.0)
	_socket(room, S.FURNITURE, ["hearth"], Vector3(0.5, 0, hz - 0.45), 0.0, 1.0, 1)
	_marker(room, "Station_cooking_pot", Vector3(-1.6, 0, hz - 1.3), 0.0)
	var xs := [-0.4] + ([2.4] if hx >= 8.0 else [])
	for x: float in xs:
		for z: float in [-2.8, 0.6]:
			_table(room, Vector3(x, 0, z), 4, ["table"])
	_socket(room, S.DECORATION, ["barrel", "crate"], Vector3(hx - 3.4, 0, hz - 0.7), 0.0, 0.8, 1)
	# upstairs: three rooms on the west side, a sitting place on the landing side
	var wx := -hx + RoomModule.CELL
	_partition(room, "RoomWall", Vector2(wx, -hz), Vector2(wx, hz), [-hz + 2.0, 0.0, hz - 2.0], top)
	_partition(room, "RoomSplitA", Vector2(-hx, -hz / 3.0), Vector2(wx, -hz / 3.0), [], top)
	_partition(room, "RoomSplitB", Vector2(-hx, hz / 3.0), Vector2(wx, hz / 3.0), [], top)
	for zc: float in [-hz + 2.0, 0.0, hz - 2.0]:
		_bed(room, Vector3(-hx + 1.4, top, zc), -PI * 0.5, [Vector3(sx, 0, z0 - 0.4), Vector3(sx, top, hz - 1.0), Vector3(hx - 3.6, top, hz - 1.0), Vector3(wx + 1.0, top, zc), Vector3(wx - 1.0, top, zc)])
		_socket(room, S.LIGHT, ["candle"], Vector3(-hx + 0.7, top, zc + 1.3), 0.0, 0.8, 1)
	_table(room, Vector3(0.6, top, -1.5), 2, ["table"])
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(0.0, top, -hz + 0.45), PI, 0.8, 1)


# A temple: pews down the nave, the altar and shrine at the far end, the priest's vestry by the door
func _temple(room: RoomModule, hx: float, hz: float, s: int) -> void:
	var vx := s * (hx - RoomModule.CELL)
	_partition(room, "VestryWall", Vector2(vx, -hz), Vector2(vx, -hz + 5.0), [-hz + 3.5])
	_partition(room, "VestryBack", Vector2(vx, -hz + 5.0), Vector2(s * hx, -hz + 5.0), [])
	_bed(room, Vector3(s * (hx - 1.0), 0, -hz + 1.4), PI, [Vector3(vx - s * 1.0, 0, -hz + 3.5), Vector3(vx + s * 1.0, 0, -hz + 3.5)])
	_marker(room, "Station_alchemy_lab", Vector3(s * (hx - 0.5), 0, -hz + 3.8), s * PI * 0.5)
	for z: float in [-2.0, -0.4, 1.2, 2.8]:
		for side: float in [-1.0, 1.0]:
			for x: float in [1.6, 3.2]:
				_socket(room, S.FURNITURE, ["bench", "set"], Vector3(side * x, 0, z), 0.0, 1.0, 1)
			_marker(room, "Seat%d" % _seats, Vector3(side * 2.4, 0, z - 0.6), 0.0)
			_seats += 1
	_socket(room, S.FURNITURE, ["altar"], Vector3(0, 0, hz - 1.6), 0.0, 1.0, 1)
	_marker(room, "Shrine", Vector3(0, 0, hz - 1.3), 0.0)
	_marker(room, "Work", Vector3(0, 0, hz - 2.8), 0.0)
	_marker(room, "Chest0", Vector3(s * (hx - 0.8), 0, hz - 1.0), 0.0)
	for side: float in [-1.0, 1.0]:
		_socket(room, S.FURNITURE, ["statue"], Vector3(side * (hx - 1.4), 0, hz - 3.0), 0.0, 0.9, 1)
		_socket(room, S.LIGHT, ["candle"], Vector3(side * 3.0, 0, hz - 0.8), 0.0, 1.0, 1)
		_socket(room, S.WALL_DECORATION, ["banner", "tapestry"], Vector3(side * (hx - 0.45), 0, 0.5), side * PI * 0.5, 0.9, 1)


# A guild hall: the long table, the guild's stations along one wall, its banners, the master's
# room at the back
func _guild(room: RoomModule, hx: float, hz: float, s: int) -> void:
	var bx := -s * (hx - RoomModule.CELL)
	_partition(room, "BackRoom", Vector2(-s * hx, hz - RoomModule.CELL), Vector2(bx, hz - RoomModule.CELL), [])
	_partition(room, "BackRoomSide", Vector2(bx, hz - RoomModule.CELL), Vector2(bx, hz), [hz - 2.0])
	_bed(room, Vector3(-s * (hx - 1.0), 0, hz - 1.4), 0.0, [Vector3(bx + s * 1.0, 0, hz - 2.0), Vector3(bx - s * 1.0, 0, hz - 2.0)])
	_marker(room, "Chest0", Vector3(-s * (hx - 2.6), 0, hz - 0.8), 0.0)
	for z: float in [-1.4, 0.2]:
		_socket(room, S.FURNITURE, ["table"], Vector3(0, 0, z), PI * 0.5, 1.0, 1)
		for side: float in [-1.0, 1.0]:
			_socket(room, S.FURNITURE, ["bench", "set"], Vector3(side * 1.0, 0, z), PI * 0.5, 1.0, 1)
			_marker(room, "Seat%d" % _seats, Vector3(side * 1.6, 0, z), 0.0)
			_seats += 1
	_marker(room, "Station_guild0", Vector3(s * (hx - 0.6), 0, -1.0), s * PI * 0.5)
	_marker(room, "Station_guild1", Vector3(s * (hx - 0.6), 0, 1.6), s * PI * 0.5)
	_marker(room, "Station_guild2", Vector3(s * 1.0, 0, hz - 0.8), 0.0)
	_marker(room, "Work", Vector3(s * 1.0, 0, hz - 2.0), 0.0)
	_marker(room, "Banner0", Vector3(s * (hx - 1.5), 0, hz - 0.05), 0.0)
	_marker(room, "Banner1", Vector3(-s * 0.8, 0, hz - 0.05), 0.0)
	_marker(room, "Case", Vector3(-s * (hx - 1.0), 0, -1.0), -s * PI * 0.5)
	_socket(room, S.FURNITURE, ["rack", "bookshelf", "shelf"], Vector3(-s * (hx - 0.45), 0, -3.0), -s * PI * 0.5, 0.9, 1)
	_socket(room, S.FURNITURE, ["shelf", "rack", "storage"], Vector3(s * 2.5, 0, -hz + 0.45), PI, 0.9, 1)


# A lord's hall: the high seat on a dais under the house banners, long tables down the middle, a
# chamber each side of the door, the bounty board, the treasury and the lore shelf; stairs go down
# from the hall to the cells (_cells)
func _seat(room: RoomModule, hx: float, hz: float) -> void:
	InteriorKit.box(room, "Dais", Vector3(7.0, 0.4, 2.6), Vector3(0, 0.2, hz - 1.3), "stone", room)
	_socket(room, S.FURNITURE, ["throne"], Vector3(0, 0.4, hz - 1.0), 0.0, 1.0, 1)
	_marker(room, "Work", Vector3(0, 0, hz - 3.0), 0.0)
	_marker(room, "Banner0", Vector3(-2.5, 0, hz - 0.05), 0.0)
	_marker(room, "Banner1", Vector3(2.5, 0, hz - 0.05), 0.0)
	for z: float in [-3.2, -1.6, 0.0, 1.6]:
		_socket(room, S.FURNITURE, ["table"], Vector3(0, 0, z), PI * 0.5, 1.0, 1)
		for side: float in [-1.0, 1.0]:
			_socket(room, S.FURNITURE, ["bench", "set"], Vector3(side * 1.0, 0, z), PI * 0.5, 1.0, 1)
	for z: float in [-1.6, 1.6]:
		for side: float in [-1.0, 1.0]:
			_marker(room, "Seat%d" % _seats, Vector3(side * 1.6, 0, z), 0.0)
			_seats += 1
	_marker(room, "Bounty", Vector3(hx - 0.15, 0, 0.0), -PI * 0.5)
	_marker(room, "Lore", Vector3(-hx + 0.8, 0, hz - 1.0), 0.0)
	_marker(room, "Chest0", Vector3(hx - 0.8, 0, hz - 1.0), 0.0)
	# the chambers either side of the great door, two beds in the west one
	for side: float in [-1.0, 1.0]:
		var cx := side * (hx - RoomModule.CELL)
		_partition(room, "Chamber%d" % int(side + 1), Vector2(cx, -hz), Vector2(cx, -hz + 6.0), [-hz + 4.5])
		_partition(room, "ChamberBack%d" % int(side + 1), Vector2(cx, -hz + 6.0), Vector2(side * hx, -hz + 6.0), [])
		var via := [Vector3(cx - side * 1.0, 0, -hz + 4.5), Vector3(cx + side * 1.0, 0, -hz + 4.5)]
		_bed(room, Vector3(side * (hx - 1.0), 0, -hz + 1.4), PI, via)
		if side < 0.0:
			_bed(room, Vector3(side * (hx - 2.6), 0, -hz + 1.4), PI, via)
		_socket(room, S.FURNITURE, ["shelf", "bookshelf", "storage"], Vector3(side * (hx - 0.45), 0, -hz + 4.4), side * PI * 0.5, 0.9, 1)
		_socket(room, S.FURNITURE, ["armor", "statue"], Vector3(side * 3.0, 0, -hz + 6.8), 0.0, 0.8, 1)
		_socket(room, S.LIGHT, ["candle", "brazier"], Vector3(side * 4.2, 0, hz - 1.4), 0.0, 1.0, 1)


# ---------------------------------------------------------------- cellars

# The floor of the raised storey, with a hole (x, z, width, depth) for the way down
func _slab(room: RoomModule, y: float, hx: float, hz: float, hole: Rect2) -> void:
	var m := InteriorKit.surface(_theme, "floor")
	var t := y - InteriorKit.SLAB * 0.5
	var parts := [
		[Vector2(-hx, -hz), Vector2(hx, hole.position.y)],
		[Vector2(-hx, hole.end.y), Vector2(hx, hz)],
		[Vector2(-hx, hole.position.y), Vector2(hole.position.x, hole.end.y)],
		[Vector2(hole.end.x, hole.position.y), Vector2(hx, hole.end.y)],
	]
	for i in parts.size():
		var a: Vector2 = parts[i][0]
		var b: Vector2 = parts[i][1]
		if b.x - a.x > 0.05 and b.y - a.y > 0.05:
			InteriorKit.box(room, "GroundFloor%d" % i, Vector3(b.x - a.x, InteriorKit.SLAB, b.y - a.y), Vector3((a.x + b.x) * 0.5, t, (a.y + b.y) * 0.5), m, room)


# A store cellar under a house: a trapdoor and a ladder down to barrels, sacks and shelves
func _store(room: RoomModule, hx: float, hz: float, s: int, layout: String) -> void:
	var c := (-s * hx + s * (hx - RoomModule.CELL)) * 0.5
	var at := Vector2(c + s * 1.4, 2.3) if layout == "side" else Vector2(1.0, 0.4)
	_slab(room, RoomModule.LEVEL, hx, hz, Rect2(at.x - 0.6, at.y - 0.7, 1.2, 1.4))
	var holder := Node3D.new()
	holder.name = "CellarLadder"
	room.add_child(holder)
	holder.owner = room
	holder.position = Vector3(at.x, 0, at.y + 0.45)
	for i in 10:
		InteriorKit.box(holder, "Rung%d" % i, Vector3(0.8, 0.06, 0.06), Vector3(0, 0.45 + i * 0.5, 0.12), "wood", room, false)
	for x: float in [-0.42, 0.42]:
		InteriorKit.box(holder, "Rail%d" % int(x > 0), Vector3(0.08, RoomModule.LEVEL + 0.4, 0.08), Vector3(x, (RoomModule.LEVEL + 0.4) * 0.5, 0.12), "wood", room, false)
	var ladder := Ladder.new()
	ladder.name = "Ladder"
	ladder.height = RoomModule.LEVEL
	holder.add_child(ladder)
	ladder.owner = room
	ladder.position = Vector3(0, 0, -0.2)  # its -Z faces the floor you step onto at the top
	_marker(room, "Cellar", Vector3(at.x, 0, at.y - 1.6), 0.0)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_socket(room, S.DECORATION, ["barrel", "sack", "crate"], Vector3(side * (hx - 0.9), 0, -hz + 1.2 + (i / 2) * 2.4), 0.0, 0.9, 1)
	_socket(room, S.FURNITURE, ["shelf", "storage", "keg_rack"], Vector3(0, 0, hz - 0.45), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["shelf", "storage"], Vector3(-hx + 0.45, 0, 1.6), -PI * 0.5, 0.8, 1)
	_socket(room, S.CEILING, ["cobweb"], Vector3(hx - 1.0, RoomModule.LEVEL - 0.35, hz - 1.0), 0.0, 0.8, 1)
	_socket(room, S.LIGHT, ["candle"], Vector3(at.x + 1.2, 0, at.y - 1.0), 0.0, 1.0, 1)


# The cells under a lord's hall: stairs down from the hall, three barred cells down one side,
# the jailer's table, stores
func _cells(room: RoomModule, hx: float, hz: float) -> void:
	var top := RoomModule.LEVEL
	var z0 := -1.0
	var z1 := hz - 2.5
	_slab(room, top, hx, hz, Rect2(-hx, -1.5, 2.8, z1 + 1.5))
	_flight(room, -hx + 1.6, z0, z1)
	var trim := InteriorKit.surface(_theme, "trim")
	var wall := InteriorKit.surface(_theme, "wall")
	InteriorKit.box(room, "StairRail", Vector3(0.15, 1.0, z1 + 1.5), Vector3(-hx + 2.8, top + 0.5, (z1 - 1.5) * 0.5), trim, room)
	InteriorKit.box(room, "StairRailFront", Vector3(2.8, 1.0, 0.15), Vector3(-hx + 1.4, top + 0.5, -1.5), trim, room)
	var cx := hx - RoomModule.CELL
	for i in 3:
		var za := -hz + i * 5.0
		var mid := za + 2.5
		InteriorKit.box(room, "CellWall%d" % i, Vector3(RoomModule.CELL, top, 0.3), Vector3(hx - RoomModule.CELL * 0.5, top * 0.5, za + 5.0), wall, room)
		var n := 0
		var z := za + 0.25
		while z < za + 5.0:
			if absf(z - mid) > 0.75:
				InteriorKit.box(room, "Bar%d_%d" % [i, n], Vector3(0.07, 2.6, 0.07), Vector3(cx, 1.3, z), "iron", room)
				n += 1
			z += 0.4
		InteriorKit.box(room, "BarTop%d" % i, Vector3(0.1, 0.1, 5.0), Vector3(cx, 2.6, mid), "iron", room, false)
		_marker(room, "Cell%d" % i, Vector3(hx - 1.6, 0, mid), -PI * 0.5)
		_socket(room, S.NPC, ["captive"], Vector3(hx - 1.6, 0, mid), -PI * 0.5, 1.0, 1)
		_socket(room, S.DECORATION, ["bones", "bucket", "hay"], Vector3(hx - 0.8, 0, mid + 1.4), 0.0, 0.7, 1)
		_socket(room, S.CEILING, ["chain"], Vector3(hx - 2.0, top - 0.35, mid - 1.0), 0.0, 0.6, 1)
	_socket(room, S.FURNITURE, ["table"], Vector3(0.5, 0, -2.0), 0.0, 1.0, 1)
	_socket(room, S.FURNITURE, ["stool", "chair", "set"], Vector3(0.5, 0, -1.2), PI, 0.9, 1)
	_marker(room, "Jailer", Vector3(0.5, 0, -0.6), 0.0)
	_socket(room, S.FURNITURE, ["weapon_rack", "rack"], Vector3(-1.0, 0, -hz + 0.45), PI, 0.9, 1)
	for i in 3:
		_socket(room, S.DECORATION, ["barrel", "crate", "sack"], Vector3(-hx + 0.9, 0, -hz + 1.2 + i * 1.6), 0.0, 0.9, 1)
	_socket(room, S.LIGHT, ["brazier", "candle"], Vector3(1.5, 0, 2.0), 0.0, 1.0, 1)


# Windows (a frame and an oiled-paper pane) on the side walls and the front of the storey at y
func _windows(room: RoomModule, hx: float, hz: float, y: float) -> void:
	var inset := InteriorKit.WALL + 0.04
	var spots := [[Vector3(-hx + inset, 0, -hz + 2.0), true], [Vector3(hx - inset, 0, -hz + 2.0), true],
		[Vector3(-hx + inset, 0, hz - 2.0), true], [Vector3(hx - inset, 0, hz - 2.0), true]]
	if hx >= 6.0:
		spots.append([Vector3(-hx + 2.0, 0, -hz + inset), false])
		spots.append([Vector3(hx - 2.0, 0, -hz + inset), false])
	var n := 0
	for sp: Array in spots:
		var at: Vector3 = sp[0] + Vector3(0, y + 2.0, 0)
		var on_side: bool = sp[1]
		InteriorKit.box(room, "WindowFrame%d_%d" % [int(y), n], Vector3(0.06, 1.3, 1.1) if on_side else Vector3(1.1, 1.3, 0.06), at, "wood_dark", room, false)
		InteriorKit.box(room, "WindowPane%d_%d" % [int(y), n], Vector3(0.08, 1.05, 0.85) if on_side else Vector3(0.85, 1.05, 0.08), at, "paper", room, false)
		n += 1
