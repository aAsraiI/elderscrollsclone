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
	# Walls sunk a meter into the ground, so a slope never shows a gap underneath
	POIBuilder.add_box(holder, Vector3(s.x, s.y + 1.0, s.z), Vector3(0.0, (s.y - 1.0) * 0.5, 0.0), wall)
	if s.y > 5.0:  # a band between the floors
		POIBuilder.add_box(holder, Vector3(s.x + 0.15, 0.3, s.z + 0.15), Vector3(0.0, s.y * 0.5, 0.0), wall.darkened(0.3), 0.0, Vector3.ZERO, false)
	var roof_h := s.x * 0.42
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

	if b.kind == BuildingPlot.Kind.FARM:
		_field(holder, b, rng)

	# Name over the door
	if b.is_public():
		var board: Color = SIGN_COLORS.get(b.kind, GUILD_COLORS.get(b.guild, Color(0.5, 0.4, 0.3)))
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
