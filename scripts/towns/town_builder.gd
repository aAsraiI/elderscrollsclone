class_name TownBuilder
extends RefCounted
## Builds a town out of placeholder boxes from its TownLayout: every building (walls, roof, door,
## windows, a name sign), farm fields, the well or statue on the plaza, city walls with gates, and
## a sign with the town's name at every gate. Streets are not meshes: the ground itself is leveled
## and colored under them (RoadNetwork).
##
## To use real models later: swap the body of _building() for a scene picked by BuildingPlot.kind,
## and keep the BuildingDoor where the door is.

const DOOR_COLOR := Color(0.24, 0.15, 0.08)
const WINDOW_COLOR := Color(0.12, 0.14, 0.18)
const GUILD_COLORS := {
	"fighters": Color(0.65, 0.12, 0.10),
	"mages": Color(0.18, 0.25, 0.70),
	"knights": Color(0.80, 0.78, 0.70),
	"thieves": Color(0.15, 0.15, 0.15),
	"antiquarians": Color(0.75, 0.60, 0.25),
	"hunters": Color(0.25, 0.42, 0.20),
	"merchants": Color(0.55, 0.18, 0.45),
}
const SIGN_COLORS := {
	BuildingPlot.Kind.SHOP: Color(0.70, 0.55, 0.20),
	BuildingPlot.Kind.INN: Color(0.55, 0.30, 0.12),
	BuildingPlot.Kind.SMITHY: Color(0.30, 0.30, 0.32),
	BuildingPlot.Kind.TEMPLE: Color(0.85, 0.80, 0.55),
}


static func build(data: TownData, placed: PlacedPOI, map: WorldMap) -> Node3D:
	var layout := placed.town
	if layout == null:
		layout = TownLayout.generate(data, placed, data.display_name, map)
		placed.town = layout
	var root := Node3D.new()
	_plaza(root, layout, placed, map)
	for b in layout.buildings:
		_building(root, b, layout, placed, map)
	if layout.wall_half > 0.0:
		_walls(root, layout, placed, map)
	_gate_signs(root, layout, placed, map)
	_pier(root, layout, placed, map)
	if data.kind == TownData.Kind.CITY and not layout.gates.is_empty():
		# The carriage to the other cities, just outside the first gate (see Carriage)
		var gate := layout.gates[0]
		var out := gate.normalized()
		var at := gate + out * 10.0 + Vector3(-out.z, 0.0, out.x) * 4.0
		var cart := Carriage.new()
		cart.name = "Carriage"
		cart.town_id = placed.id
		root.add_child(cart)
		cart.position = Vector3(at.x, POIBuilder.ground_y(placed, map, at.x, at.z), at.z)
		cart.rotation.y = atan2(out.x, out.z)
	return root


# ---------------------------------------------------------------- buildings

static func _building(root: Node3D, b: BuildingPlot, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	var data := layout.data
	var rng := RandomNumberGenerator.new()
	rng.seed = placed.seed_value + b.index * 7919
	var holder := Node3D.new()
	holder.name = "B%d_%s" % [b.index, BuildingPlot.kind_name(b.kind).replace(" ", "")]
	holder.set_meta("building_id", b.id)
	root.add_child(holder)
	var gy := POIBuilder.ground_y(placed, map, b.local_pos.x, b.local_pos.z)
	holder.position = Vector3(b.local_pos.x, gy, b.local_pos.z)
	holder.rotation.y = b.local_yaw

	var s := b.size
	var wall := data.wall_color.darkened(rng.randf_range(0.0, 0.18))
	var roof := data.roof_color.darkened(rng.randf_range(0.0, 0.2))
	if b.kind == BuildingPlot.Kind.TEMPLE:
		wall = data.stone_color.lightened(0.15)
	elif b.kind == BuildingPlot.Kind.SEAT and b.seat_type != "reeve":
		wall = data.stone_color.darkened(rng.randf_range(0.0, 0.1))
	# Walls sunk a meter into the ground, so a slope never shows a gap underneath
	POIBuilder.add_box(holder, Vector3(s.x, s.y + 1.0, s.z), Vector3(0.0, (s.y - 1.0) * 0.5, 0.0), wall)
	if s.y > 5.0:  # a band between the floors
		POIBuilder.add_box(holder, Vector3(s.x + 0.15, 0.3, s.z + 0.15), Vector3(0.0, s.y * 0.5, 0.0), wall.darkened(0.3), 0.0, Vector3.ZERO, false)
	var roof_h := s.x * 0.42
	if not (b.kind == BuildingPlot.Kind.SEAT and (b.seat_type == "castle" or b.seat_type == "tower")):  # those have battlements
		_roof(holder, Vector3(s.x + 0.8, roof_h, s.z + 0.8), Vector3(0.0, s.y + roof_h * 0.5, 0.0), roof)

	# Door and windows
	var front := -s.z * 0.5
	POIBuilder.add_box(holder, Vector3(1.4, 2.3, 0.12), Vector3(0.0, 1.15, front - 0.06), DOOR_COLOR, 0.0, Vector3.ZERO, false)
	for side in [-1.0, 1.0]:
		POIBuilder.add_box(holder, Vector3(0.08, 1.0, 1.0), Vector3(side * (s.x * 0.5 + 0.04), 1.7, 0.0), WINDOW_COLOR, 0.0, Vector3.ZERO, false)
		if s.x >= 7.0:
			POIBuilder.add_box(holder, Vector3(1.0, 1.0, 0.08), Vector3(side * s.x * 0.3, 1.7, front - 0.04), WINDOW_COLOR, 0.0, Vector3.ZERO, false)
		if s.y > 5.0:
			POIBuilder.add_box(holder, Vector3(1.0, 1.0, 0.08), Vector3(side * s.x * 0.3, s.y * 0.75, front - 0.04), WINDOW_COLOR, 0.0, Vector3.ZERO, false)

	match b.kind:
		BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM, BuildingPlot.Kind.INN:
			var ch := roof_h + 1.4
			POIBuilder.add_box(holder, Vector3(0.8, ch, 0.8), Vector3(s.x * 0.25, s.y + ch * 0.5, s.z * 0.2), data.stone_color.darkened(0.2))
		BuildingPlot.Kind.SMITHY:
			# An open forge beside the house
			var fx := s.x * 0.5 + 2.0
			POIBuilder.add_box(holder, Vector3(2.4, 1.0, 2.4), Vector3(fx, 0.5, 0.0), data.stone_color.darkened(0.3))
			POIBuilder.add_box(holder, Vector3(1.2, 0.3, 1.2), Vector3(fx, 1.1, 0.0), Color(1.0, 0.45, 0.1), 0.0, Vector3.ZERO, false, true)
			POIBuilder.add_box(holder, Vector3(0.8, 0.6, 0.4), Vector3(fx, 0.3, -2.0), Color(0.22, 0.22, 0.24))
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				POIBuilder.add_box(holder, Vector3(0.25, 3.0, 0.25), Vector3(fx + corner.x * 1.6, 1.5, corner.y * 1.6), DOOR_COLOR)
			_roof(holder, Vector3(4.0, 0.8, 4.0), Vector3(fx, 3.4, 0.0), roof)
		BuildingPlot.Kind.TEMPLE:
			POIBuilder.add_box(holder, Vector3(3.2, 5.0, 3.2), Vector3(0.0, s.y + 2.5, s.z * 0.3), wall)
			_roof(holder, Vector3(3.8, 2.2, 3.8), Vector3(0.0, s.y + 6.1, s.z * 0.3), roof)
		BuildingPlot.Kind.GUILD_HALL:
			var banner: Color = GUILD_COLORS.get(b.guild, Color.DIM_GRAY)
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(1.0, 2.6, 0.06), Vector3(side * 2.3, 3.4, front - 0.08), banner, 0.0, Vector3.ZERO, false)
		BuildingPlot.Kind.SEAT:
			_seat(holder, b, data, wall, roof)

	if b.kind == BuildingPlot.Kind.FARM:
		_field(holder, b, rng)
	if b.kind == BuildingPlot.Kind.HOUSE and b.trade != "":
		_trade_props(holder, b, rng)

	# Name over the door
	if b.is_public():
		var board: Color = SIGN_COLORS.get(b.kind, GUILD_COLORS.get(b.guild, Color(0.5, 0.4, 0.3)))
		if b.kind == BuildingPlot.Kind.SEAT:
			board = NamedSettlements.house_color(b.house).darkened(0.25)
		POIBuilder.add_box(holder, Vector3(2.4, 0.6, 0.1), Vector3(0.0, 2.85, front - 0.15), board, 0.0, Vector3.ZERO, false)
		_label(holder, b.display_name, Vector3(0.0, 2.85, front - 0.22), PI, 40)
	else:
		_label(holder, b.display_name, Vector3(0.0, 2.55, front - 0.1), PI, 28)

	var door := BuildingDoor.new()
	door.name = "Door"
	door.building_id = b.id
	door.building_name = b.display_name
	door.lock_level = b.lock_level
	door.default_locked = b.starts_locked
	door.position = Vector3(0.0, 1.3, front - 0.45)
	holder.add_child(door)


# A lord's seat: a castle gets four corner towers, battlements and a gatehouse; a keep one great
# tower; a knight's tower house battlements; a reeve's house a chimney and a banner pole. All hang
# the banners of the house that holds the land.
static func _seat(holder: Node3D, b: BuildingPlot, data: TownData, wall: Color, roof: Color) -> void:
	var s := b.size
	var front := -s.z * 0.5
	var banner := NamedSettlements.house_color(b.house)
	var dark := wall.darkened(0.15)
	match b.seat_type:
		"castle":
			var th := s.y + 5.0
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var at := Vector3(c.x * s.x * 0.5, 0.0, c.y * s.z * 0.5)
				POIBuilder.add_box(holder, Vector3(4.0, th + 1.0, 4.0), at + Vector3(0.0, th * 0.5 - 0.5, 0.0), dark)
				_roof(holder, Vector3(4.6, 3.0, 4.6), at + Vector3(0.0, th + 1.5, 0.0), roof)
			_battlements(holder, s, dark)
			# the gatehouse around the door: two pillars and an arch, open in the middle
			var gh := s.y + 2.0
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(1.6, gh, 2.0), Vector3(side * 2.2, gh * 0.5, front - 1.0), dark)
			POIBuilder.add_box(holder, Vector3(6.0, gh - 3.4, 2.0), Vector3(0.0, 3.4 + (gh - 3.4) * 0.5, front - 1.0), dark)
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(1.6, 4.0, 0.08), Vector3(side * 5.5, s.y * 0.6, front - 0.1), banner, 0.0, Vector3.ZERO, false)
		"keep":
			var th := s.y + 6.0
			var at := Vector3(s.x * 0.5 - 2.5, 0.0, s.z * 0.5 - 2.5)
			POIBuilder.add_box(holder, Vector3(5.0, th + 1.0, 5.0), at + Vector3(0.0, th * 0.5 - 0.5, 0.0), dark)
			_battlements(holder, Vector3(5.0, th, 5.0), dark, at)
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(1.2, 3.0, 0.08), Vector3(side * 3.6, s.y * 0.6, front - 0.1), banner, 0.0, Vector3.ZERO, false)
		"tower":
			_battlements(holder, s, dark)
			POIBuilder.add_box(holder, Vector3(1.2, 3.0, 0.08), Vector3(0.0, s.y * 0.65, front - 0.1), banner, 0.0, Vector3.ZERO, false)
		_:
			var ch := s.x * 0.42 + 1.4
			POIBuilder.add_box(holder, Vector3(0.8, ch, 0.8), Vector3(s.x * 0.25, s.y + ch * 0.5, s.z * 0.2), data.stone_color.darkened(0.2))
			var pole := Vector3(s.x * 0.5 + 1.0, 0.0, front - 0.5)
			POIBuilder.add_box(holder, Vector3(0.15, 5.0, 0.15), pole + Vector3(0.0, 2.5, 0.0), DOOR_COLOR, 0.0, Vector3.ZERO, false)
			POIBuilder.add_box(holder, Vector3(0.06, 1.2, 0.9), pole + Vector3(0.0, 4.2, 0.5), banner, 0.0, Vector3.ZERO, false)


# Merlons along the top edge of a block of size `s` standing at `at`
static func _battlements(holder: Node3D, s: Vector3, color: Color, at: Vector3 = Vector3.ZERO) -> void:
	var y := s.y + 0.6
	var n_x := maxi(int(s.x / 2.0), 2)
	var n_z := maxi(int(s.z / 2.0), 2)
	for i in n_x:
		var x := -s.x * 0.5 + (float(i) + 0.5) * s.x / float(n_x)
		for z in [-s.z * 0.5, s.z * 0.5]:
			POIBuilder.add_box(holder, Vector3(0.9, 1.2, 0.5), at + Vector3(x, y, z), color, 0.0, Vector3.ZERO, false)
	for i in n_z:
		var z := -s.z * 0.5 + (float(i) + 0.5) * s.z / float(n_z)
		for x in [-s.x * 0.5, s.x * 0.5]:
			POIBuilder.add_box(holder, Vector3(0.5, 1.2, 0.9), at + Vector3(x, y, z), color, 0.0, Vector3.ZERO, false)


static func _roof(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = size
	mesh.mesh = prism
	mesh.material_override = POIBuilder.get_material(color)
	parent.add_child(mesh)
	mesh.position = pos


# A field behind the farmhouse: soil, crop rows and a fence
static func _field(holder: Node3D, b: BuildingPlot, rng: RandomNumberGenerator) -> void:
	var f := b.field_size
	var cz := b.size.z * 0.5 + f.y * 0.5 + 0.5
	POIBuilder.add_box(holder, Vector3(f.x, 0.3, f.y), Vector3(0.0, 0.0, cz), Color(0.36, 0.26, 0.16), 0.0, Vector3.ZERO, false)
	var crop := Color(0.35, 0.55, 0.18) if rng.randf() < 0.6 else Color(0.78, 0.68, 0.30)
	var rows := int(f.x / 1.6)
	for i in rows:
		var x := -f.x * 0.5 + 0.8 + float(i) * 1.6
		POIBuilder.add_box(holder, Vector3(0.6, 0.55, f.y - 1.6), Vector3(x, 0.4, cz), crop.darkened(rng.randf_range(0.0, 0.15)), 0.0, Vector3.ZERO, false)
	var fence := Color(0.40, 0.30, 0.18)
	POIBuilder.add_box(holder, Vector3(f.x + 0.4, 1.0, 0.15), Vector3(0.0, 0.5, cz + f.y * 0.5 + 0.2), fence)
	for side in [-1.0, 1.0]:
		POIBuilder.add_box(holder, Vector3(0.15, 1.0, f.y + 0.4), Vector3(side * (f.x * 0.5 + 0.2), 0.5, cz), fence)


static func _label(parent: Node3D, text: String, pos: Vector3, yaw: float, font_size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.006
	l.outline_size = 8
	l.modulate = Color(1.0, 0.95, 0.85)
	l.visibility_range_end = 45.0
	parent.add_child(l)
	l.position = pos
	l.rotation.y = yaw
	return l


# ---------------------------------------------------------------- the rest of the town

static func _plaza(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	var gy := POIBuilder.ground_y(placed, map, 0.0, 0.0)
	var stone := layout.data.stone_color
	if layout.data.kind == TownData.Kind.CITY:
		POIBuilder.add_box(root, Vector3(3.0, 1.6, 3.0), Vector3(0.0, gy + 0.8, 0.0), stone)
		POIBuilder.add_box(root, Vector3(1.0, 3.0, 1.0), Vector3(0.0, gy + 3.1, 0.0), stone.lightened(0.2))
		return
	# A well with a little roof
	for i in 4:
		var a := float(i) * PI * 0.5
		POIBuilder.add_box(root, Vector3(2.2, 0.9, 0.3), Vector3(cos(a), 0.0, sin(a)) * 0.95 + Vector3(0.0, gy + 0.45, 0.0), stone, a + PI * 0.5)
	for side in [-1.0, 1.0]:
		POIBuilder.add_box(root, Vector3(0.2, 2.4, 0.2), Vector3(side * 0.95, gy + 1.2, 0.0), DOOR_COLOR, 0.0, Vector3.ZERO, false)
	_roof(root, Vector3(2.6, 0.9, 2.6), Vector3(0.0, gy + 2.8, 0.0), layout.data.roof_color)


static func _walls(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	var w := layout.wall_half
	var t := 1.6
	var h := 7.0
	var gate := 12.0
	var stone := layout.data.stone_color
	var gy := POIBuilder.ground_y(placed, map, 0.0, 0.0)
	# North and south: whole
	for z in [-w, w]:
		POIBuilder.add_box(root, Vector3(w * 2.0 + t, h + 2.0, t), Vector3(0.0, gy + h * 0.5 - 1.0, z), stone)
	# East and west: a gate in the middle, where the main street goes through
	var piece := w - gate * 0.5
	for x in [-w, w]:
		for side in [-1.0, 1.0]:
			POIBuilder.add_box(root, Vector3(t, h + 2.0, piece), Vector3(x, gy + h * 0.5 - 1.0, side * (gate * 0.5 + piece * 0.5)), stone)
			POIBuilder.add_box(root, Vector3(3.2, h + 4.0, 3.2), Vector3(x, gy + h * 0.5, side * (gate * 0.5 + 1.6)), stone.darkened(0.1))
	for c in [Vector2(-w, -w), Vector2(w, -w), Vector2(-w, w), Vector2(w, w)]:
		POIBuilder.add_box(root, Vector3(4.0, h + 5.0, 4.0), Vector3(c.x, gy + (h + 5.0) * 0.5 - 1.0, c.y), stone.darkened(0.15))


static func _gate_signs(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	for g in layout.gates:
		var out := signf(g.x)
		var at := Vector3(g.x + out * 4.0, 0.0, 6.0)  # just outside the town, beside the road
		at.y = POIBuilder.ground_y(placed, map, at.x, at.z)
		POIBuilder.add_box(root, Vector3(0.2, 2.4, 0.2), at + Vector3(0.0, 1.2, 0.0), DOOR_COLOR)
		POIBuilder.add_box(root, Vector3(0.1, 0.7, 2.4), at + Vector3(0.0, 2.2, 0.0), Color(0.5, 0.38, 0.22), 0.0, Vector3.ZERO, false)
		_label(root, layout.display_name, at + Vector3(out * 0.07, 2.2, 0.0), out * PI * 0.5, 56).visibility_range_end = 80.0


# ---------------------------------------------------------------- tradesmen

# What a tradesman keeps beside their house (on the side where they work)
static func _trade_props(holder: Node3D, b: BuildingPlot, rng: RandomNumberGenerator) -> void:
	var x := b.size.x * 0.5 + 1.1
	var wood := Color(0.42, 0.30, 0.18)
	match b.trade:
		"woodcutter":
			for i in 3:
				for j in 3 - i:
					POIBuilder.add_box(holder, Vector3(0.35, 0.35, 1.8), Vector3(x + 0.38 * float(j) + 0.19 * float(i), 0.18 + 0.33 * float(i), -1.2), wood.darkened(rng.randf_range(0.0, 0.2)), 0.0, Vector3.ZERO, false)
			POIBuilder.add_box(holder, Vector3(0.6, 0.5, 0.6), Vector3(x + 0.4, 0.25, 1.0), wood.darkened(0.25))
		"fisherman":
			for z in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(0.12, 1.8, 0.12), Vector3(x + 0.4, 0.9, z), DOOR_COLOR, 0.0, Vector3.ZERO, false)
			POIBuilder.add_box(holder, Vector3(0.08, 0.08, 2.2), Vector3(x + 0.4, 1.75, 0.0), DOOR_COLOR, 0.0, Vector3.ZERO, false)
			for k in 4:
				POIBuilder.add_box(holder, Vector3(0.06, 0.45, 0.16), Vector3(x + 0.4, 1.45, -0.75 + 0.5 * float(k)), Color(0.6, 0.62, 0.6), 0.0, Vector3.ZERO, false)
		"hunter":
			POIBuilder.add_box(holder, Vector3(0.1, 1.9, 2.2), Vector3(x + 0.4, 0.95, 0.0), DOOR_COLOR, 0.0, Vector3.ZERO, false)
			for k in 2:
				POIBuilder.add_box(holder, Vector3(0.05, 1.1, 0.9), Vector3(x + 0.48, 1.15, -0.5 + float(k)), Color(0.5, 0.36, 0.22).darkened(0.1 * k), 0.0, Vector3.ZERO, false)
		"miner":
			POIBuilder.add_box(holder, Vector3(0.9, 0.6, 1.4), Vector3(x + 0.3, 0.55, -0.6), Color(0.3, 0.28, 0.27))
			for k in 4:
				POIBuilder.add_box(holder, Vector3(0.4, 0.35, 0.4), Vector3(x + 0.3 + rng.randf_range(-0.3, 0.3), 0.18, 1.0 + rng.randf_range(-0.3, 0.3)), Color(0.45, 0.42, 0.4).darkened(rng.randf_range(0.0, 0.3)), rng.randf() * TAU, Vector3.ZERO, false)
		"herbalist":
			POIBuilder.add_box(holder, Vector3(1.1, 0.25, 2.4), Vector3(x + 0.4, 0.12, 0.0), Color(0.33, 0.24, 0.15), 0.0, Vector3.ZERO, false)
			for k in 6:
				POIBuilder.add_box(holder, Vector3(0.25, 0.35, 0.25), Vector3(x + 0.15 + 0.5 * float(k % 2), 0.4, -0.9 + 0.36 * float(k)), Color(0.3, 0.55, 0.25).lightened(rng.randf_range(0.0, 0.3)), 0.0, Vector3.ZERO, false)


# A wooden pier on the shore, when the town has fishermen
static func _pier(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	if layout.shore == Vector3.INF:
		return
	var fishers := false
	for b in layout.buildings:
		fishers = fishers or b.trade == "fisherman"
	if not fishers:
		return
	var out := Vector3(layout.shore.x, 0.0, layout.shore.z).normalized()
	var yaw := atan2(out.x, out.z)
	var sea := map.settings.sea_level - placed.position.y
	for k in 4:
		var at := layout.shore + out * (1.5 + 2.2 * float(k))
		POIBuilder.add_box(root, Vector3(2.2, 0.2, 2.2), Vector3(at.x, sea + 0.5, at.z), Color(0.45, 0.33, 0.2), yaw)
		POIBuilder.add_box(root, Vector3(0.2, 3.0, 0.2), Vector3(at.x, sea - 1.0, at.z) + Basis(Vector3.UP, yaw) * Vector3(1.0, 0, 0), DOOR_COLOR, 0.0, Vector3.ZERO, false)
	# The town's rowboat, tied alongside the end of the pier (unless you sailed off in it)
	if not Boat.taken_from(placed.id):
		var tie := layout.shore + out * (1.5 + 2.2 * 3.0) + Basis(Vector3.UP, yaw) * Vector3(2.3, 0, 0)
		Boat.make(root, Vector3(tie.x, sea - 0.05, tie.z), yaw + PI, placed.id)
