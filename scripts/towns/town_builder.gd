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
	_lit_windows(root)
	_dressing(root, layout, placed, map)
	if layout.wall_kind != "":
		_wall_ring(root, layout, placed, map)
	elif layout.wall_half > 0.0:
		_walls(root, layout, placed, map)
	_gate_signs(root, layout, placed, map)
	_pier(root, layout, placed, map)
	ModelLibrary.batch_dressed(root)  # the walls, towers and gates: one draw per model
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
	var front := -s.z * 0.5

	# a hand-made building (InteriorOverrides "exteriors") stands in for the generated one
	var ext := InteriorOverrides.exterior_scene(b)
	if ext != "":
		holder.add_child((load(ext) as PackedScene).instantiate())
		_door(holder, b, front, 0.0)
		return

	var style := BuildingStyle.for_biome(layout.biome_key)
	# the storeys match the inside it will have (manors and inns have an upper floor, Alpha 1.13)
	if map != null and b.kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.INN]:
		var irng := RandomNumberGenerator.new()
		irng.seed = ("%d|interior|%s" % [map.world_seed, b.id]).hash()
		var module := InteriorBuilder.pick_module(b, irng).get_file()
		if module.begins_with("manor") or module.begins_with("inn"):
			s.y = maxf(s.y, 6.4)
	var lift := 1.6 if style.base == "stilts" and b.kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM, BuildingPlot.Kind.SHOP, BuildingPlot.Kind.INN] else 0.0
	var wall: Color
	match style.walls:
		"stone":
			wall = data.stone_color.lightened(0.05)
		"adobe":
			wall = Color(0.72, 0.6, 0.43)
		"planks":
			wall = Color(0.43, 0.31, 0.2)
		_:
			wall = data.wall_color
	wall = (wall * style.wall_tint).darkened(rng.randf_range(0.0, 0.16))
	var roof := (data.roof_color * style.roof_tint).darkened(rng.randf_range(0.0, 0.2))
	if b.district == "slums":
		wall = wall.darkened(0.15)
		roof = roof.darkened(0.15)
	if b.kind == BuildingPlot.Kind.TEMPLE:
		wall = data.stone_color.lightened(0.15)
	elif b.kind == BuildingPlot.Kind.SEAT and b.seat_type != "reeve":
		wall = data.stone_color.darkened(rng.randf_range(0.0, 0.1))
	# what it stands on: posts and steps up (stilts), or a stone plinth
	if lift > 0.0:
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			POIBuilder.add_box(holder, Vector3(0.35, lift + 1.0, 0.35), Vector3(c.x * (s.x * 0.5 - 0.3), (lift - 1.0) * 0.5, c.y * (s.z * 0.5 - 0.3)), style.beam_color)
		for i in 4:
			POIBuilder.add_box(holder, Vector3(1.6, lift * (i + 1) / 4.0, 0.5), Vector3(0.0, lift * (i + 1) / 8.0, front - 0.6 - (3 - i) * 0.5), DOOR_COLOR)
	elif style.base == "stone" and b.kind != BuildingPlot.Kind.SEAT:
		POIBuilder.add_box(holder, Vector3(s.x + 0.35, 1.5, s.z + 0.35), Vector3(0.0, -0.35, 0.0), data.stone_color.darkened(0.2), 0.0, Vector3.ZERO, false)
	# the walls, sunk a meter into the ground (a slope never shows a gap); the floor bands and beams
	POIBuilder.add_box(holder, Vector3(s.x, s.y + 1.0, s.z), Vector3(0.0, lift + (s.y - 1.0) * 0.5, 0.0), wall)
	if s.y > 5.0:
		POIBuilder.add_box(holder, Vector3(s.x + 0.15, 0.3, s.z + 0.15), Vector3(0.0, lift + s.y * 0.5, 0.0), wall.darkened(0.3), 0.0, Vector3.ZERO, false)
	if style.walls == "timber" and b.kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM, BuildingPlot.Kind.SHOP, BuildingPlot.Kind.INN, BuildingPlot.Kind.SMITHY]:
		_timber(holder, s, lift, style.beam_color)
	var roof_h := s.x * (0.6 if style.roof == "steep" else 0.42)
	if not (b.kind == BuildingPlot.Kind.SEAT and (b.seat_type == "castle" or b.seat_type == "tower")):  # those have battlements
		if style.roof == "flat" and b.kind != BuildingPlot.Kind.TEMPLE:
			POIBuilder.add_box(holder, Vector3(s.x + 0.3, 0.35, s.z + 0.3), Vector3(0.0, lift + s.y + 0.17, 0.0), roof)
			_battlements(holder, Vector3(s.x, lift + s.y - 0.4, s.z), wall.darkened(0.08))
			roof_h = 0.6
		else:
			_roof(holder, Vector3(s.x + 0.8, roof_h, s.z + 0.8), Vector3(0.0, lift + s.y + roof_h * 0.5, 0.0), roof)

	# the door, the windows (they light up at night: the town's lit-window mesh), shutters, a porch
	# a door you can see from down the street; inns, shops, guilds and temples hang a lantern by it too
	DoorLook.dress(holder, Vector3(0.0, lift, front), PI, "door/building", b.kind in [BuildingPlot.Kind.INN, BuildingPlot.Kind.SHOP, BuildingPlot.Kind.GUILD_HALL, BuildingPlot.Kind.TEMPLE])
	var lit: Array = root.get_meta("lit_windows", [])
	var shutters := rng.randf() < style.shutters
	for side in [-1.0, 1.0]:
		lit.append([holder.transform * Transform3D(Basis(), Vector3(side * (s.x * 0.5 + 0.04), lift + 1.7, 0.0)), true])
		if s.x >= 7.0:
			lit.append([holder.transform * Transform3D(Basis(), Vector3(side * s.x * 0.3, lift + 1.7, front - 0.04)), false])
			if shutters:
				_part(holder, "shutters", Vector3(side * s.x * 0.3, lift + 1.7, front))
		if s.y > 5.0:
			lit.append([holder.transform * Transform3D(Basis(), Vector3(side * s.x * 0.3, lift + s.y * 0.75, front - 0.04)), false])
			if shutters:
				_part(holder, "shutters", Vector3(side * s.x * 0.3, lift + s.y * 0.75, front))
	root.set_meta("lit_windows", lit)
	if b.kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.SHOP, BuildingPlot.Kind.INN] and rng.randf() < style.porch:
		_part(holder, "porch", Vector3(0.0, lift, front))
	if s.y > 5.0 and b.kind in [BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.INN] and (rng.randf() < style.balcony or b.district == "noble"):
		_part(holder, "balcony", Vector3(0.0, lift + s.y * 0.5 + 0.2, front))

	match b.kind:
		BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM, BuildingPlot.Kind.INN:
			if style.chimneys and b.district != "slums":
				_part(holder, "chimney", Vector3(s.x * 0.25, lift + s.y + roof_h * 0.35, s.z * 0.2))
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
		# the farm's animals out in the field (Alpha 1.14)
		for i in rng.randi_range(1, 3):
			var kind := "sheep" if rng.randf() < 0.6 else "cow"
			SiteLife.animal(holder, kind, Vector3(rng.randf_range(-3.0, 3.0), lift, s.z * 0.5 + b.field_size.y * 0.5 + rng.randf_range(-2.0, 2.0)), "%s/animal%d" % [b.id, i])
	elif b.yard:
		_yard(holder, b, rng)
	if b.kind == BuildingPlot.Kind.HOUSE and b.trade != "":
		_trade_props(holder, b, rng)
	_sign(holder, b, front, lift)
	_door(holder, b, front, lift)


# The door you go in by
static func _door(holder: Node3D, b: BuildingPlot, front: float, lift: float) -> void:
	var door := BuildingDoor.new()
	door.name = "Door"
	door.building_id = b.id
	door.building_name = b.display_name
	door.lock_level = b.lock_level
	door.default_locked = b.starts_locked
	door.position = Vector3(0.0, lift + 1.3, front - 0.45)
	holder.add_child(door)


# A part from scenes/buildings/parts/ at a spot on the building
static func _part(holder: Node3D, name: String, at: Vector3) -> Node3D:
	var path := "res://scenes/buildings/parts/%s.tscn" % name
	if not ResourceLoader.exists(path):
		return null
	var p := (load(path) as PackedScene).instantiate() as Node3D
	p.name = "Part_" + name  # never "Door": the BuildingDoor has that name
	holder.add_child(p)
	p.position = at
	return p


# Timber framing: dark beams up the corners and across each wall at the floors and the top
static func _timber(holder: Node3D, s: Vector3, lift: float, color: Color) -> void:
	for side in 4:
		var along_x := side % 2 == 0
		var length := s.x if along_x else s.z
		var sign := -1.0 if side < 2 else 1.0
		var face := (s.z if along_x else s.x) * 0.5 + 0.04
		var n := maxi(int(length / 1.8), 2)
		for i in n + 1:
			var t := -length * 0.5 + length * i / n
			if side == 0 and absf(t) < 1.1:
				continue  # never up through the front door
			var at := Vector3(t, lift + s.y * 0.5, sign * face) if along_x else Vector3(sign * face, lift + s.y * 0.5, t)
			POIBuilder.add_box(holder, Vector3(0.18, s.y, 0.08) if along_x else Vector3(0.08, s.y, 0.18), at, color, 0.0, Vector3.ZERO, false)
		for y in [0.15, s.y * 0.5, s.y - 0.15]:
			var at := Vector3(0.0, lift + y, sign * face) if along_x else Vector3(sign * face, lift + y, 0.0)
			POIBuilder.add_box(holder, Vector3(length, 0.16, 0.08) if along_x else Vector3(0.08, 0.16, length), at, color, 0.0, Vector3.ZERO, false)


# Alpha 1.14 signs: homes have none; a shop, inn, smithy, temple or guild hall hangs a small board
# from a bracket beside the door with its trade's mark, and E on it reads the name
const TRADE_MARKS := {
	BuildingPlot.Kind.INN: ["tankard", Color(0.55, 0.32, 0.12)], BuildingPlot.Kind.SMITHY: ["anvil", Color(0.25, 0.25, 0.28)],
	BuildingPlot.Kind.TEMPLE: ["sun", Color(0.85, 0.7, 0.3)], BuildingPlot.Kind.SHOP: ["coin", Color(0.75, 0.6, 0.2)],
	BuildingPlot.Kind.GUILD_HALL: ["banner", Color(0.5, 0.2, 0.2)],
}

static func _sign(holder: Node3D, b: BuildingPlot, front: float, lift: float) -> void:
	if not b.is_public() or b.kind == BuildingPlot.Kind.SEAT:
		return  # homes have no sign; a lord's hall shows its banners
	var mark: Array = TRADE_MARKS.get(b.kind, ["coin", Color(0.5, 0.4, 0.3)])
	var board_color: Color = GUILD_COLORS.get(b.guild, mark[1]) if b.kind == BuildingPlot.Kind.GUILD_HALL else Color(0.42, 0.3, 0.18)
	var at := Vector3(1.5, lift + 3.0, front)
	_part(holder, "sign_bracket", at)
	var board := Readable.make(holder, at + Vector3(0, -0.55, -1.0), PI, b.display_name, "%s\n\n(%s)" % [b.display_name, BuildingPlot.kind_name(b.kind).to_lower()], "none")
	board.name = "Sign"
	POIBuilder.add_box(board, Vector3(0.75, 0.5, 0.05), Vector3(0, 0.25, 0), board_color, 0.0, Vector3.ZERO, false)
	# the trade's mark painted on it
	var ink: Color = mark[1].lightened(0.35)
	match String(mark[0]):
		"tankard":
			POIBuilder.add_box(board, Vector3(0.2, 0.26, 0.02), Vector3(-0.03, 0.25, -0.035), ink, 0.0, Vector3.ZERO, false)
			POIBuilder.add_box(board, Vector3(0.06, 0.14, 0.02), Vector3(0.11, 0.25, -0.035), ink, 0.0, Vector3.ZERO, false)
		"anvil":
			POIBuilder.add_box(board, Vector3(0.36, 0.08, 0.02), Vector3(0, 0.3, -0.035), ink, 0.0, Vector3.ZERO, false)
			POIBuilder.add_box(board, Vector3(0.12, 0.16, 0.02), Vector3(0, 0.18, -0.035), ink, 0.0, Vector3.ZERO, false)
		"sun":
			POIBuilder.add_box(board, Vector3(0.22, 0.22, 0.02), Vector3(0, 0.25, -0.035), ink, 0.785, Vector3.ZERO, false)
		"banner":
			POIBuilder.add_box(board, Vector3(0.16, 0.32, 0.02), Vector3(0, 0.25, -0.035), ink, 0.0, Vector3.ZERO, false)
		_:
			POIBuilder.add_box(board, Vector3(0.2, 0.2, 0.02), Vector3(0, 0.25, -0.035), ink, 0.0, Vector3.ZERO, false)


# Every lit window of the town as one mesh with one shared material that glows at night
# (window_material; WorldManager turns it up as the light goes)
static var _window_mat: StandardMaterial3D

static func window_material() -> StandardMaterial3D:
	if _window_mat == null:
		_window_mat = StandardMaterial3D.new()
		_window_mat.albedo_color = WINDOW_COLOR
		_window_mat.emission_enabled = true
		_window_mat.emission = Color(1.0, 0.72, 0.4)
		_window_mat.emission_energy_multiplier = 0.0
		var glass := MwSurfaces.texture("window")
		if glass != null:
			# Morrowind's leaded panes: dark by day, glowing between the lead at night
			_window_mat.albedo_texture = glass
			_window_mat.albedo_color = Color(0.75, 0.75, 0.8)
			_window_mat.emission_texture = glass
			_window_mat.uv1_triplanar = true
			_window_mat.uv1_world_triplanar = true
			_window_mat.uv1_scale = Vector3.ONE * 0.9
	return _window_mat


## How lit the windows are: 0 by day, up to full in the dark (daylight 1 = noon)
static func set_daylight(daylight: float) -> void:
	window_material().emission_energy_multiplier = clampf(1.0 - daylight * 1.6, 0.0, 1.0) * 1.8


static func _lit_windows(root: Node3D) -> void:
	var list: Array = root.get_meta("lit_windows", [])
	root.remove_meta("lit_windows")
	if list.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pane := BoxMesh.new()
	pane.size = Vector3(1.0, 1.0, 1.0)
	for w: Array in list:
		var xf: Transform3D = w[0]
		var thin := Vector3(0.08, 1.0, 1.0) if bool(w[1]) else Vector3(1.0, 1.0, 0.08)
		st.append_from(pane, 0, xf * Transform3D(Basis.from_scale(thin)))
	var mi := MeshInstance3D.new()
	mi.name = "LitWindows"
	mi.mesh = st.commit()
	mi.material_override = window_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


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
	mesh.material_override = roof_material(color)
	parent.add_child(mesh)
	mesh.position = pos


static var _roof_mats := {}


## A roof's look: its colour with Morrowind's shingles on it (the building shader's roof mode)
static func roof_material(color: Color) -> Material:
	var key := color.to_html(false)
	if not _roof_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = StaticBatch.material().shader
		m.set_shader_parameter("use_vertex_color", false)
		m.set_shader_parameter("base_color", color)
		m.set_shader_parameter("surface", 4)
		_roof_mats[key] = m
	return _roof_mats[key]


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


# The town's name carved on a stone beside the road at each gate (Alpha 1.14: no big boards); E on
# it reads the name
static func _gate_signs(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	var kind: String = ["village", "town", "city"][clampi(int(layout.data.kind), 0, 2)]
	for g in layout.gates:
		var out := signf(g.x)
		var at := Vector3(g.x + out * 5.0, 0.0, 6.5)
		at.y = POIBuilder.ground_y(placed, map, at.x, at.z)
		POIBuilder.add_box(root, Vector3(0.6, 1.5, 1.7), at + Vector3(0.0, 0.6, 0.0), layout.data.stone_color.darkened(0.12), 0.0, Vector3(0.0, 0.0, out * 0.06))
		var carved := _label(root, layout.display_name, at + Vector3(out * 0.31, 0.95, 0.0), out * PI * 0.5, 30)
		carved.visibility_range_end = 22.0
		carved.outline_size = 0
		carved.modulate = Color(0.25, 0.23, 0.2)
		Readable.make(root, at + Vector3(out * 0.5, 0.0, 0.0), out * PI * 0.5, "the stone", "%s\n\n(a %s)" % [layout.display_name, kind], "none")


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


# A house's yard (Alpha 1.14): a low fence round the space behind it, a vegetable bed or two, a
# woodpile or a washing line
static func _yard(holder: Node3D, b: BuildingPlot, rng: RandomNumberGenerator) -> void:
	var f := b.field_size
	var cz := b.size.z * 0.5 + f.y * 0.5 + 0.3
	var fence := Color(0.40, 0.30, 0.18)
	POIBuilder.add_box(holder, Vector3(f.x, 0.8, 0.1), Vector3(0.0, 0.4, cz + f.y * 0.5), fence)
	for side in [-1.0, 1.0]:
		POIBuilder.add_box(holder, Vector3(0.1, 0.8, f.y), Vector3(side * f.x * 0.5, 0.4, cz), fence)
	var soil := Color(0.34, 0.25, 0.16)
	for i in rng.randi_range(1, 2):
		var x := -f.x * 0.25 + i * f.x * 0.5
		POIBuilder.add_box(holder, Vector3(f.x * 0.35, 0.2, f.y * 0.55), Vector3(x, 0.1, cz + 0.4), soil, 0.0, Vector3.ZERO, false)
		POIBuilder.add_box(holder, Vector3(f.x * 0.3, 0.35, f.y * 0.4), Vector3(x, 0.3, cz + 0.4), Color(0.30, 0.48, 0.18).darkened(rng.randf() * 0.2), 0.0, Vector3.ZERO, false)
	if rng.randf() < 0.5:  # a woodpile against the fence
		POIBuilder.add_box(holder, Vector3(1.4, 0.9, 0.6), Vector3(f.x * 0.5 - 1.0, 0.45, cz + f.y * 0.5 - 0.5), Color(0.42, 0.30, 0.18))
	else:  # a washing line
		for side in [-1.0, 1.0]:
			POIBuilder.add_box(holder, Vector3(0.08, 1.8, 0.08), Vector3(side * f.x * 0.3, 0.9, cz - 0.6), fence, 0.0, Vector3.ZERO, false)
		POIBuilder.add_box(holder, Vector3(f.x * 0.6, 0.5, 0.03), Vector3(0, 1.45, cz - 0.6), Color(0.75, 0.72, 0.65), 0.0, Vector3.ZERO, false)


# ---------------------------------------------------------------- Alpha 1.14 walls

# The wall round the town along its outline (TownLayout.wall_poly): stone with a walkway on top and
# merlons on the outside, a city's thicker and higher with a ditch below, or a village's palisade of
# stakes. Each piece stands on the ground beneath it; towers at the bends and every so often,
# gatehouses at the gates with slopes up to the walkway beside them.
static func _wall_ring(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	var kind := layout.wall_kind
	var stone := layout.data.stone_color
	var wood := Color(0.40, 0.29, 0.17)
	var h: float = {"thick": 8.0, "stone": 6.0, "palisade": 3.4}[kind]
	var t: float = {"thick": 3.2, "stone": 2.6, "palisade": 0.6}[kind]
	var color := wood if kind == "palisade" else stone
	var since_tower := 0.0
	var prev_dir := Vector2.ZERO
	for piece: Array in layout.wall_pieces(6.0, 5.5 if kind == "palisade" else 6.5):
		var a: Vector2 = piece[0]
		var b: Vector2 = piece[1]
		var mid := (a + b) * 0.5
		var d := b - a
		var len := d.length()
		var yaw := -atan2(d.y, d.x)
		var gy := POIBuilder.ground_y(placed, map, mid.x, mid.y)
		# drawn a little longer than the piece, so the model's ends always meet the next one's
		var wall_box := POIBuilder.add_box(root, Vector3(len + (1.4 if ModelLibrary.has("wall/city") and kind != "palisade" else 0.3), h + 2.0, t), Vector3(mid.x, gy + h * 0.5 - 1.0, mid.y), color, yaw)
		var modelled := ModelLibrary.dress_box(wall_box, "wall/palisade" if kind == "palisade" else "wall/city")
		var outward := Vector2(mid).normalized()
		if modelled:
			pass  # the model has its own stakes or battlements
		elif kind == "palisade":  # the stake points along the top
			for k in int(len / 0.9):
				var p := a.lerp(b, (k + 0.5) / int(len / 0.9))
				POIBuilder.add_box(root, Vector3(0.35, 0.6, 0.35), Vector3(p.x, gy + h + 0.3, p.y), wood.darkened(0.1), yaw + 0.785, Vector3.ZERO, false)
		else:  # merlons on the outer edge of the walkway
			for k in int(len / 2.0):
				var p := a.lerp(b, (k + 0.5) / int(len / 2.0)) + outward * (t * 0.5 - 0.25)
				POIBuilder.add_box(root, Vector3(0.9, 0.9, 0.5), Vector3(p.x, gy + h + 0.45, p.y), stone.darkened(0.05), yaw, Vector3.ZERO, false)
		var bend := absf(prev_dir.angle_to(d)) if prev_dir != Vector2.ZERO else 0.0
		if modelled and kind != "palisade" and bend > 0.12:
			# a squared corner piece where the wall turns (never above the wall line), so no wedge shows
			var joint := POIBuilder.add_box(root, Vector3(t + 0.3, h + 2.0, t + 0.3), Vector3(a.x, gy + h * 0.5 - 1.0, a.y), color, yaw)
			ModelLibrary.dress_box(joint, "wall/corner")
		if kind == "thick" and not modelled:  # the ditch below a city's walls
			var dp := mid + outward * (t * 0.5 + 2.5)
			POIBuilder.add_box(root, Vector3(len + 0.3, 0.1, 3.5), Vector3(dp.x, POIBuilder.ground_y(placed, map, dp.x, dp.y) + 0.02, dp.y), Color(0.16, 0.18, 0.17), yaw, Vector3.ZERO, false)
		# towers where the wall turns and along long stretches
		since_tower += len
		var turn := absf(prev_dir.angle_to(d)) if prev_dir != Vector2.ZERO else 0.0
		prev_dir = d
		var near_gate := layout.gates.any(func(gt: Vector3) -> bool: return Vector2(gt.x, gt.z).distance_to(a) < 12.0)
		if kind != "palisade" and (since_tower > 34.0 or turn > 0.45) and not near_gate:  # never on top of a gatehouse tower
			since_tower = 0.0
			var tw := t + 2.2
			ModelLibrary.dress_box(POIBuilder.add_box(root, Vector3(tw, h + 5.0, tw), Vector3(a.x, gy + (h + 5.0) * 0.5 - 1.0, a.y), stone.darkened(0.12), yaw), "wall/tower")
	# gatehouses: a tower each side and the arch over the road, and a slope up to the walkway
	for g in layout.gates:
		var gp := Vector2(g.x, g.z)
		var along := Vector2(0, 1)  # the main street runs along X, so the wall runs along Z at a gate
		var gy := POIBuilder.ground_y(placed, map, gp.x, gp.y)
		if kind == "palisade":
			for side: float in [-1.0, 1.0]:
				var p := gp + along * side * 4.6
				POIBuilder.add_box(root, Vector3(0.7, h + 1.2, 0.7), Vector3(p.x, gy + (h + 1.2) * 0.5, p.y), wood.darkened(0.15))
			continue
		for side: float in [-1.0, 1.0]:
			var p := gp + along * side * 6.5
			ModelLibrary.dress_box(POIBuilder.add_box(root, Vector3(5.0, h + 6.0, 5.0), Vector3(p.x, gy + (h + 6.0) * 0.5 - 1.0, p.y), stone.darkened(0.15)), "wall/tower")
		var lintel := POIBuilder.add_box(root, Vector3(t + 1.0, 2.0, 8.2), Vector3(gp.x, gy + h + 0.0, gp.y), stone.darkened(0.08))
		if ModelLibrary.has("wall/arch"):
			# the arched gateway: drawn from the ground up over the road, solid only above it (the lintel)
			var arch := POIBuilder.add_box(root, Vector3(t + 1.0, h + 2.0, 8.2), Vector3(gp.x, gy + h * 0.5, gp.y), stone, 0.0, Vector3.ZERO, false)
			if ModelLibrary.dress_box(arch, "wall/arch"):
				ModelLibrary.add_trimesh(root, arch.get_node("Look"))  # its pillars and stone solid, the archway open
			for mi in lintel.find_children("*", "MeshInstance3D", false, false):
				lintel.remove_child(mi)
				mi.free()  # now, before the town is merged



# ---------------------------------------------------------------- Alpha 1.14 town dressing

## What each dressing spot gets (a prop scene in scenes/interiors/props/)
const DRESS_PROPS := {
	"lamp": "lamp_post", "stall": "market_stall", "fountain": "fountain", "well": "well", "bench": "stone_bench",
	"tree": "street_tree", "flowers": "flower_box", "barrel": "barrel", "crates": "crates", "cart": "cart",
	"hay": "hay_bale", "sacks": "sacks", "statue": "statue", "banner": "banner_pole", "broken_cart": "broken_cart",
}

# The town's things on their spots (TownLayout.dress); street lamps light up at night
static func _dressing(root: Node3D, layout: TownLayout, placed: PlacedPOI, map: WorldMap) -> void:
	var many := {}  # the repeated things, drawn as one MultiMesh each (Alpha 1.14.12)
	for d: Dictionary in layout.dress:
		var at: Vector3 = d["pos"]
		at.y = POIBuilder.ground_y(placed, map, at.x, at.z)
		var what := String(d["what"])
		if MULTI.has(what):
			if not many.has(what):
				many[what] = []
			many[what].append(Transform3D(Basis(Vector3.UP, float(d["yaw"])), at))
			continue
		match what:
			"notice":
				NoticeBoard.make(root, at, float(d["yaw"]), placed.id)
			"watchtower":
				_watchtower(root, at, layout.data.stone_color)
			_:
				var path := "res://scenes/interiors/props/%s.tscn" % DRESS_PROPS.get(what, what)
				if not ResourceLoader.exists(path):
					continue
				var p := (load(path) as PackedScene).instantiate() as Node3D
				p.name = "Dress_" + what
				root.add_child(p)
				p.position = at
				p.rotation.y = float(d["yaw"])
				for l in p.find_children("*", "OmniLight3D", true, false):
					var light := l as OmniLight3D
					light.add_to_group("town_lamps")
					light.distance_fade_enabled = true
					light.distance_fade_begin = 45.0
					light.distance_fade_length = 15.0
	_multi(root, many)
	DoorLook.batch(root)  # every door model in the town in one draw


# A village's wooden watchtower: four posts, a platform with a rail, a roof, a slope up
static func _watchtower(root: Node3D, at: Vector3, stone: Color) -> void:
	var wood := Color(0.38, 0.27, 0.16)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		POIBuilder.add_box(root, Vector3(0.3, 6.5, 0.3), at + Vector3(c.x * 1.4, 3.0, c.y * 1.4), wood)
	POIBuilder.add_box(root, Vector3(3.4, 0.25, 3.4), at + Vector3(0, 5.0, 0), wood.darkened(0.1))
	for side in 4:
		var along := side % 2 == 0
		var sg := -1.0 if side < 2 else 1.0
		POIBuilder.add_box(root, Vector3(3.4, 0.9, 0.12) if along else Vector3(0.12, 0.9, 3.4), at + (Vector3(0, 5.6, sg * 1.65) if along else Vector3(sg * 1.65, 5.6, 0)), wood, 0.0, Vector3.ZERO, false)
	_roof(root, Vector3(4.0, 1.4, 4.0), at + Vector3(0, 7.2, 0), Color(0.35, 0.24, 0.16))


## Street lamps on at night, off by day (WorldManager calls this as the light changes)
static func set_lamps(tree: SceneTree, night: bool) -> void:
	tree.call_group("town_lamps", "set_visible", night)


## Town things that come by the dozen: one MultiMesh (and one shared collision body) per kind,
## each seen out to its distance
const MULTI := {"flowers": 60.0, "tree": 180.0, "barrel": 90.0, "crates": 90.0, "sacks": 70.0, "hay": 90.0}

static var _prop_meshes := {}  # prop file -> [ArrayMesh, Array of [Shape3D, Transform3D]]


static func _multi(root: Node3D, many: Dictionary) -> void:
	for what: String in many:
		var file: String = DRESS_PROPS.get(what, what)
		var got := _prop_mesh(file)
		if got.is_empty():
			continue
		var list: Array = many[what]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = got[0]
		mm.instance_count = list.size()
		var body := StaticBody3D.new()
		body.name = "Many_%s_Collision" % what
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			for sh: Array in got[1]:
				var owner := body.create_shape_owner(body)
				body.shape_owner_add_shape(owner, sh[0])
				body.shape_owner_set_transform(owner, (list[i] as Transform3D) * (sh[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Many_" + what
		mmi.multimesh = mm
		mmi.visibility_range_end = float(MULTI[what])
		mmi.visibility_range_end_margin = 10.0
		root.add_child(mmi)
		if not got[1].is_empty():
			root.add_child(body)
		else:
			body.free()


# A prop scene as one mesh (its parts' colours kept, glowing parts left out) and its collision shapes
static func _prop_mesh(file: String) -> Array:
	if _prop_meshes.has(file):
		return _prop_meshes[file]
	var path := "res://scenes/interiors/props/%s.tscn" % file
	if not ResourceLoader.exists(path):
		return []
	var p := (load(path) as PackedScene).instantiate() as Node3D
	# its model when it has one (a Morrowind tree, barrel, crate...): baked as it is, materials and all
	if p is InteriorProp:
		(p as InteriorProp).dress()
	var modelled := p.find_children("*", "MeshInstance3D", true, false).any(func(n): return not ((n as MeshInstance3D).mesh is PrimitiveMesh))
	if modelled:
		var baked := ModelLibrary.bake(p)
		var hulls: Array = []
		for cs in p.find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).shape != null:
				hulls.append([(cs as CollisionShape3D).shape, _local_xf(p, cs as Node3D)])
		p.free()
		_prop_meshes[file] = [baked, hulls] if baked != null else []
		return _prop_meshes[file]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shapes: Array = []
	for n in p.find_children("*", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is PrimitiveMesh:
			var mi := n as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D
			if m != null and m.emission_enabled:
				continue
			var xf := p.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _local_xf(p, mi)
			var arrays := (mi.mesh as PrimitiveMesh).get_mesh_arrays()
			var colors := PackedColorArray()
			colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			colors.fill(m.albedo_color if m != null else Color.WHITE)
			arrays[Mesh.ARRAY_COLOR] = colors
			var part := ArrayMesh.new()
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			st.append_from(part, 0, xf)
		elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
			shapes.append([(n as CollisionShape3D).shape, _local_xf(p, n as Node3D)])
	var mesh := st.commit()
	mesh.surface_set_material(0, StaticBatch.material())
	p.free()
	_prop_meshes[file] = [mesh, shapes]
	return _prop_meshes[file]


static func _local_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
