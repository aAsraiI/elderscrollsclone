extends SceneTree
## Lays out Castle Dawnhold, the one hand-built place in Caldreth, and saves it as
## res://scenes/world/castle_dawnhold.tscn. After that the scene is yours: open it in the editor and
## move, resize or add things by hand (every block is a named CSGBox3D with collision). Run this
## again only to start over from this layout.
##   godot --headless --path . -s res://tools/build_dawnhold.gd
##
## Local space like every interior: the floor's middle is the origin, the doors out are in the -Z
## wall, the player starts just inside facing +Z. Markers (Marker3D) tell the game where things go:
## Start, Exit, Throne (the King's place), Seat_* (council chairs), Bed_*, Chest_* (filled at runtime).

const OUT := "res://scenes/world/castle_dawnhold.tscn"
const HALL_H := 9.0
const ROOM_H := 5.0
const CRYPT_Y := -8.0
const CRYPT_H := 5.0
const T := 0.5  # wall thickness

var castle: Node3D
var mats := {}


func _initialize() -> void:
	castle = Node3D.new()
	castle.name = "CastleDawnhold"
	_materials()
	_great_hall()
	_east_wing()
	_west_wing()
	_north_rooms()
	_crypt()
	_lights()
	_markers()
	_own(castle)
	var scene := PackedScene.new()
	var err := scene.pack(castle)
	if err == OK:
		DirAccess.make_dir_recursive_absolute("res://scenes/world")
		err = ResourceSaver.save(scene, OUT)
	print("castle_dawnhold: %s" % ("saved " + OUT if err == OK else "error %d" % err))
	castle.free()
	quit(0 if err == OK else 1)


func _materials() -> void:
	for k in {"stone": Color(0.42, 0.4, 0.37), "dark_stone": Color(0.26, 0.25, 0.24), "floor": Color(0.33, 0.31, 0.29),
			"wood": Color(0.36, 0.24, 0.14), "dark_wood": Color(0.22, 0.14, 0.08), "carpet": Color(0.45, 0.08, 0.08),
			"gold": Color(0.78, 0.62, 0.25), "cloth": Color(0.55, 0.5, 0.42), "crypt": Color(0.3, 0.32, 0.34), "bone": Color(0.75, 0.72, 0.62)}:
		var c: Color = {"stone": Color(0.42, 0.4, 0.37), "dark_stone": Color(0.26, 0.25, 0.24), "floor": Color(0.33, 0.31, 0.29),
			"wood": Color(0.36, 0.24, 0.14), "dark_wood": Color(0.22, 0.14, 0.08), "carpet": Color(0.45, 0.08, 0.08),
			"gold": Color(0.78, 0.62, 0.25), "cloth": Color(0.55, 0.5, 0.42), "crypt": Color(0.3, 0.32, 0.34), "bone": Color(0.75, 0.72, 0.62)}[k]
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.35 if k == "gold" else 0.9
		m.metallic = 0.6 if k == "gold" else 0.0
		m.resource_name = k
		mats[k] = m
	for h in NamedSettlements.HOUSE_COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = NamedSettlements.HOUSE_COLORS[h]
		m.roughness = 0.95
		m.resource_name = "banner_" + h
		mats["banner_" + h] = m


# A named block. `at` is the block's middle; `size` its full size. Solid unless told otherwise.
func box(parent: Node3D, n: String, size: Vector3, at: Vector3, mat: String, solid: bool = true, rot := Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = n
	b.size = size
	b.position = at
	b.rotation = rot
	b.material = mats[mat]
	b.use_collision = solid
	parent.add_child(b)
	return b


func group(n: String, parent: Node3D = null) -> Node3D:
	var g := Node3D.new()
	g.name = n
	(parent if parent != null else castle).add_child(g)
	return g


func label(parent: Node3D, n: String, text: String, at: Vector3, yaw: float = 0.0, size: int = 48) -> void:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.position = at
	l.rotation.y = yaw
	l.font_size = size
	l.outline_size = 8
	l.modulate = Color(0.95, 0.85, 0.6)
	parent.add_child(l)


# A wall along X (dir "x") or Z (dir "z") from a to b at height range, with optional door gaps [center, width]
func wall(parent: Node3D, n: String, dir: String, fixed: float, from: float, to: float, y0: float, h: float, mat: String, gaps: Array = []) -> void:
	var cuts: Array = [[from, to]]
	for g in gaps:
		var lo: float = g[0] - g[1] * 0.5
		var hi: float = g[0] + g[1] * 0.5
		var next: Array = []
		for c in cuts:
			if hi <= c[0] or lo >= c[1]:
				next.append(c)
				continue
			if lo > c[0]:
				next.append([c[0], lo])
			if hi < c[1]:
				next.append([hi, c[1]])
		cuts = next
	var i := 0
	for c in cuts:
		var len: float = c[1] - c[0]
		var mid: float = (c[0] + c[1]) * 0.5
		var size := Vector3(len, h, T) if dir == "x" else Vector3(T, h, len)
		var at := Vector3(mid, y0 + h * 0.5, fixed) if dir == "x" else Vector3(fixed, y0 + h * 0.5, mid)
		box(parent, "%s_%d" % [n, i], size, at, mat)
		i += 1
	# lintels over door gaps
	for g in gaps:
		var lh := h - 3.0
		if lh > 0.1:
			var size := Vector3(g[1], lh, T) if dir == "x" else Vector3(T, lh, g[1])
			var at := Vector3(g[0], y0 + 3.0 + lh * 0.5, fixed) if dir == "x" else Vector3(fixed, y0 + 3.0 + lh * 0.5, g[0])
			box(parent, "%s_lintel_%d" % [n, i], size, at, mat)
			i += 1


func _great_hall() -> void:
	var g := group("GreatHall")
	# The floor has an opening on the west side where the stair goes down to the crypt
	box(g, "Floor_East", Vector3(10.5, T, 30), Vector3(1.75, -T * 0.5, 0), "floor")
	box(g, "Floor_West_South", Vector3(3.5, T, 13), Vector3(-5.25, -T * 0.5, -8.5), "floor")
	box(g, "Floor_West_North", Vector3(3.5, T, 3), Vector3(-5.25, -T * 0.5, 13.5), "floor")
	box(g, "Floor_West_Edge", Vector3(0.5, T, 14), Vector3(-6.75, -T * 0.5, 5), "floor")
	box(g, "Ceiling", Vector3(15, T, 31), Vector3(0, HALL_H + T * 0.5, 0), "dark_stone")
	wall(g, "Wall_South", "x", -15.25, -7.5, 7.5, 0.0, HALL_H, "stone", [[0.0, 3.0]])
	wall(g, "Wall_North", "x", 15.25, -7.5, 7.5, 0.0, HALL_H, "stone", [[-3.5, 2.4], [3.5, 2.4]])
	wall(g, "Wall_East", "z", 7.25, -15.0, 15.0, 0.0, HALL_H, "stone", [[-6.0, 2.4], [8.0, 2.4]])
	wall(g, "Wall_West", "z", -7.25, -15.0, 15.0, 0.0, HALL_H, "stone", [[-6.0, 2.4], [10.0, 2.4]])
	# The great door (decor), carpet, pillars, the dais and the throne
	box(g, "GreatDoor", Vector3(3.0, 3.6, 0.15), Vector3(0, 1.8, -15.4), "dark_wood", false)
	box(g, "Carpet", Vector3(2.6, 0.03, 24), Vector3(1.2, 0.015, -1.5), "carpet", false)
	for side in [-1, 1]:
		for i in 5:
			var x: float = 4.8 if side > 0 else -2.4
			box(g, "Pillar_%s_%d" % ["E" if side > 0 else "W", i], Vector3(1.0, HALL_H, 1.0), Vector3(x, HALL_H * 0.5, -11.0 + i * 5.0), "stone")
	box(g, "Dais", Vector3(9, 0.6, 4), Vector3(1.2, 0.3, 12.5), "stone")
	box(g, "Dais_Step", Vector3(5, 0.3, 1), Vector3(1.2, 0.15, 10.0), "stone")
	box(g, "Throne_Seat", Vector3(1.6, 0.6, 1.2), Vector3(1.2, 0.9, 13.2), "gold")
	box(g, "Throne_Back", Vector3(1.6, 2.6, 0.3), Vector3(1.2, 2.2, 13.9), "gold")
	box(g, "Throne_Cushion", Vector3(1.3, 0.12, 1.0), Vector3(1.2, 1.26, 13.15), "carpet", false)
	# The eight great houses' banners down the hall
	var houses := ["valcourt", "tidewell", "ashgrove", "morvaine", "brannoch", "sahrim", "kjellvar", "vyrel"]
	for i in houses.size():
		var east := i % 2 == 0
		var key: String = "banner_" + houses[i] if mats.has("banner_" + houses[i]) else "cloth"
		box(g, "Banner_" + houses[i], Vector3(0.05, 3.6, 1.6), Vector3(6.95 if east else -6.95, 5.2, -9.0 + float(i / 2) * 5.5), key, false)
	box(g, "Banner_Aurelane", Vector3(4.0, 5.0, 0.05), Vector3(1.2, 5.5, 14.95), "gold", false)
	# Railings around the stair opening
	box(g, "Rail_East", Vector3(0.2, 1.0, 14), Vector3(-3.4, 0.5, 5), "dark_stone")
	box(g, "Rail_North", Vector3(3.5, 1.0, 0.2), Vector3(-5.0, 0.5, 12.0), "dark_stone")
	label(g, "Sign_Crypt", "Crypt of Kings", Vector3(-5.0, 2.6, -2.2), 0.0, 40)


func _east_wing() -> void:
	var g := group("EastWing")
	# Royal Solar (south) and the Council Chamber (north)
	box(g, "Floor", Vector3(12.5, T, 30), Vector3(13.5, -T * 0.5, 0), "floor")
	box(g, "Ceiling", Vector3(12.5, T, 30), Vector3(13.5, ROOM_H + T * 0.5, 0), "dark_stone")
	wall(g, "Wall_East", "z", 19.75, -15.0, 15.0, 0.0, ROOM_H, "stone")
	wall(g, "Wall_South", "x", -15.25, 7.5, 20.0, 0.0, ROOM_H, "stone")
	wall(g, "Wall_North", "x", 15.25, 7.5, 20.0, 0.0, ROOM_H, "stone")
	wall(g, "Wall_Between", "x", 1.0, 7.5, 19.5, 0.0, ROOM_H, "stone", [[9.5, 2.0]])
	var solar := group("RoyalSolar", g)
	box(solar, "Bed", Vector3(2.2, 0.6, 3.0), Vector3(16.5, 0.3, -12.0), "carpet")
	box(solar, "Bed_Head", Vector3(2.4, 1.8, 0.2), Vector3(16.5, 0.9, -13.6), "dark_wood")
	box(solar, "Hearth", Vector3(2.6, 2.0, 0.8), Vector3(19.0, 1.0, -6.0), "dark_stone", true, Vector3(0, PI * 0.5, 0))
	box(solar, "Desk", Vector3(1.8, 0.8, 0.9), Vector3(10.5, 0.4, -12.5), "wood")
	label(solar, "Sign", "Royal Solar", Vector3(8.6, 3.2, -6.0), -PI * 0.5, 40)
	var council := group("CouncilChamber", g)
	box(council, "Table", Vector3(2.4, 0.9, 9.0), Vector3(13.5, 0.45, 8.0), "dark_wood")
	for i in 10:
		var east := i % 2 == 0
		box(council, "Chair_%d" % i, Vector3(0.7, 1.4, 0.7), Vector3(15.3 if east else 11.7, 0.7, 4.4 + float(i / 2) * 1.8), "wood")
	label(council, "Sign", "Council Chamber", Vector3(8.6, 3.2, 8.0), -PI * 0.5, 40)


func _west_wing() -> void:
	var g := group("WestWing")
	# The barracks (south) and the Chancellor's office (north)
	box(g, "Floor", Vector3(12.5, T, 30), Vector3(-13.5, -T * 0.5, 0), "floor")
	box(g, "Ceiling", Vector3(12.5, T, 30), Vector3(-13.5, ROOM_H + T * 0.5, 0), "dark_stone")
	wall(g, "Wall_West", "z", -19.75, -15.0, 15.0, 0.0, ROOM_H, "stone")
	wall(g, "Wall_South", "x", -15.25, -20.0, -7.5, 0.0, ROOM_H, "stone")
	wall(g, "Wall_North", "x", 15.25, -20.0, -7.5, 0.0, ROOM_H, "stone")
	wall(g, "Wall_Between", "x", 4.0, -19.5, -7.5, 0.0, ROOM_H, "stone", [[-10.0, 2.0]])
	var barracks := group("Barracks", g)
	for i in 4:
		box(barracks, "Bunk_%d" % i, Vector3(1.0, 0.5, 2.2), Vector3(-18.6, 0.25, -12.5 + i * 3.4), "cloth")
	box(barracks, "WeaponRack", Vector3(0.4, 2.0, 3.0), Vector3(-8.2, 1.0, -9.0), "dark_wood")
	label(barracks, "Sign", "Barracks", Vector3(-8.6, 3.2, -6.0), PI * 0.5, 40)
	var office := group("ChancellorsOffice", g)
	box(office, "Desk", Vector3(2.4, 0.85, 1.1), Vector3(-14.0, 0.42, 10.0), "dark_wood")
	box(office, "Shelves", Vector3(4.0, 3.0, 0.5), Vector3(-14.0, 1.5, 14.6), "wood")
	label(office, "Sign", "Chancellor's Office", Vector3(-8.6, 3.2, 10.0), PI * 0.5, 40)


func _north_rooms() -> void:
	var g := group("NorthRooms")
	box(g, "Floor", Vector3(15, T, 8.5), Vector3(0, -T * 0.5, 19.75), "floor")
	box(g, "Ceiling", Vector3(15, T, 8.5), Vector3(0, ROOM_H + T * 0.5, 19.75), "dark_stone")
	wall(g, "Wall_North", "x", 24.25, -7.5, 7.5, 0.0, ROOM_H, "stone")
	wall(g, "Wall_West", "z", -7.25, 15.5, 24.0, 0.0, ROOM_H, "stone")
	wall(g, "Wall_East", "z", 7.25, 15.5, 24.0, 0.0, ROOM_H, "stone")
	wall(g, "Wall_Between", "z", 0.0, 15.5, 24.0, 0.0, ROOM_H, "stone")
	var treasury := group("Treasury", g)
	for i in 3:
		box(treasury, "GoldPile_%d" % i, Vector3(1.2, 0.5, 1.0), Vector3(-5.5 + i * 1.8, 0.25, 22.8), "gold", false)
	label(treasury, "Sign", "Treasury", Vector3(-3.5, 3.2, 15.0), PI, 40)
	var tower := group("PrincessTower", g)
	box(tower, "Bed", Vector3(1.6, 0.5, 2.4), Vector3(5.6, 0.25, 21.8), "cloth")
	box(tower, "Window", Vector3(1.4, 1.6, 0.05), Vector3(3.5, 2.6, 24.0), "gold", false)
	label(tower, "Sign", "Princess's Tower", Vector3(3.5, 3.2, 15.0), PI, 40)


func _crypt() -> void:
	var g := group("CryptOfKings")
	# The stair down from the hall's west side, in its own shaft
	var ramp_len := sqrt(14.0 * 14.0 + 8.0 * 8.0)
	box(g, "Stair", Vector3(3.0, 0.4, ramp_len), Vector3(-5.0, -4.0 - 0.2, 5.0), "dark_stone", true, Vector3(atan2(8.0, 14.0), 0, 0))
	wall(g, "Shaft_West", "z", -6.75, -2.0, 4.0, CRYPT_Y, -CRYPT_Y, "dark_stone")
	wall(g, "Shaft_East", "z", -3.25, -2.0, 4.0, CRYPT_Y, -CRYPT_Y, "dark_stone")
	box(g, "Shaft_South", Vector3(3.5, -CRYPT_Y, T), Vector3(-5.0, CRYPT_Y * 0.5, -2.25), "dark_stone")
	# The crypt itself: a long vault north of the stair's foot
	box(g, "Floor", Vector3(18, T, 22), Vector3(-5.0, CRYPT_Y - T * 0.5, 15.0), "crypt")
	box(g, "Ceiling_East", Vector3(11, T, 22), Vector3(-0.5, CRYPT_Y + CRYPT_H + T * 0.5, 15.0), "crypt")
	box(g, "Ceiling_West", Vector3(4, T, 22), Vector3(-12.0, CRYPT_Y + CRYPT_H + T * 0.5, 15.0), "crypt")
	box(g, "Ceiling_Stair", Vector3(3.5, T, 15), Vector3(-5.0, CRYPT_Y + CRYPT_H + T * 0.5, 18.5), "crypt")
	wall(g, "Wall_West", "z", -14.25, 4.0, 26.0, CRYPT_Y, CRYPT_H, "crypt")
	wall(g, "Wall_East", "z", 4.25, 4.0, 26.0, CRYPT_Y, CRYPT_H, "crypt")
	wall(g, "Wall_South", "x", 3.75, -14.0, 4.0, CRYPT_Y, CRYPT_H, "crypt", [[-5.0, 3.5]])
	wall(g, "Wall_North", "x", 26.25, -14.0, 4.0, CRYPT_Y, CRYPT_H, "crypt", [[-5.0, 2.4]])
	# The kings of the Crowned Age in their tombs, and Prince Caedric
	var kings := ["Caedmon I", "Aldric I", "Caedmon II", "Rosamund", "Aldren III", "Prince Caedric"]
	for i in kings.size():
		var east := i % 2 == 0
		var x: float = 1.5 if east else -11.5
		var z := 9.0 + float(i / 2) * 5.0
		box(g, "Tomb_%d" % i, Vector3(1.6, 1.0, 2.8), Vector3(x, CRYPT_Y + 0.5, z), "crypt")
		box(g, "Effigy_%d" % i, Vector3(0.7, 0.3, 2.0), Vector3(x, CRYPT_Y + 1.15, z), "bone", false)
		label(g, "Name_%d" % i, kings[i], Vector3(x + (-1.0 if east else 1.0), CRYPT_Y + 1.6, z), -PI * 0.5 if east else PI * 0.5, 32)
	# The sealed door to the Old Keep, an imperial fortress buried under the castle
	box(g, "OldKeep_SealedDoor", Vector3(2.4, 3.0, 0.3), Vector3(-5.0, CRYPT_Y + 1.5, 26.1), "dark_stone")
	box(g, "OldKeep_Seal", Vector3(0.9, 0.9, 0.05), Vector3(-5.0, CRYPT_Y + 1.7, 25.92), "gold", false)
	label(g, "Sign_OldKeep", "The Old Keep  (sealed)", Vector3(-5.0, CRYPT_Y + 3.4, 25.8), PI, 36)


func _lights() -> void:
	var g := group("Lights")
	var spots := [[Vector3(1.2, 7.0, -10), 2.2, 16.0], [Vector3(1.2, 7.0, 0), 2.2, 16.0], [Vector3(1.2, 7.0, 10), 2.4, 16.0],
		[Vector3(13.5, 4.0, -7), 1.6, 11.0], [Vector3(13.5, 4.0, 8), 1.8, 11.0], [Vector3(-13.5, 4.0, -7), 1.4, 11.0],
		[Vector3(-13.5, 4.0, 10), 1.5, 9.0], [Vector3(-3.5, 4.0, 19.5), 1.2, 7.0], [Vector3(3.5, 4.0, 19.5), 1.3, 7.0]]
	for i in spots.size():
		var l := OmniLight3D.new()
		l.name = "Lamp_%d" % i
		l.position = spots[i][0]
		l.light_energy = spots[i][1]
		l.omni_range = spots[i][2]
		l.light_color = Color(1.0, 0.78, 0.5)
		g.add_child(l)
	for i in 3:
		var l := OmniLight3D.new()
		l.name = "CryptLamp_%d" % i
		l.position = Vector3(-5.0, CRYPT_Y + 3.8, 8.0 + i * 7.0)
		l.light_energy = 1.1
		l.omni_range = 9.0
		l.light_color = Color(0.55, 0.65, 0.9)
		g.add_child(l)


func _markers() -> void:
	var g := group("Markers")
	var put := func(n: String, at: Vector3) -> void:
		var m := Marker3D.new()
		m.name = n
		m.position = at
		g.add_child(m)
	put.call("Start", Vector3(1.2, 0.1, -12.6))
	put.call("Exit", Vector3(0.0, 1.3, -14.3))
	put.call("Throne", Vector3(1.2, 0.7, 11.5))
	for i in 10:
		put.call("Seat_%d" % i, Vector3(15.3 if i % 2 == 0 else 11.7, 0.1, 4.4 + float(i / 2) * 1.8))
	put.call("Bed_Solar", Vector3(16.5, 0.1, -10.0))
	put.call("Bed_Tower", Vector3(5.6, 0.1, 20.0))
	for i in 4:
		put.call("Bed_Barracks_%d" % i, Vector3(-17.4, 0.1, -12.5 + i * 3.4))
	put.call("Chest_Treasury", Vector3(-3.0, 0.0, 22.6))
	put.call("Chest_Solar", Vector3(18.6, 0.0, -13.6))


# A packed scene keeps only nodes owned by its castle
func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = castle
		_own(c)
