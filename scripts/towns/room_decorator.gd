class_name RoomDecorator
extends RefCounted
## Furnishes a room and puts loose loot on its surfaces. Used for every building interior and
## every dungeon room. Built from a seed, so a room is the same every visit.
##
##   1. What is already in the room (walls, a bed, a counter) is measured, so nothing is placed
##      inside it, and a walkway from every door is kept clear.
##   2. Wall pieces go along the walls (shelves, cupboards, barrels, crates, racks...), then a few
##      middle pieces (tables, sarcophagi, workbenches) where there is room.
##   3. Every surface is a loot slot: table tops, each shelf plank, crate and barrel tops, and the
##      tops of furniture that was already there. A slot gets one item (or none) from the theme's
##      loot tags at the room's level (ItemCatalog.tag_loot).
##   4. Items are placed frozen (WorldItem.place), owned by `owner` (empty = free to take), and
##      remembered by slot id: once taken, a slot stays empty (shops and homes refill after
##      `restock_days`, dungeons never).
##
## Themes are the THEMES table below: which pieces, how many, which loot tags.

## theme -> {"wall": [pieces], "middle": [pieces], "tags": [loot tags], "fill": chance a slot holds something,
##           "containers": [[name, loot tags]] one container per entry}
const THEMES := {
	"home": {"wall": ["shelf", "cupboard", "barrel", "crate"], "middle": ["table"], "tags": ["home", "kitchen", "clothes"], "fill": 0.5,
		"containers": [["Cupboard", ["home", "kitchen", "clothes"]]]},
	"rich_home": {"wall": ["shelf", "bookcase", "cupboard", "wardrobe"], "middle": ["table"], "tags": ["rich_home", "kitchen", "library", "jewelry"], "fill": 0.55,
		"containers": [["Wardrobe", ["rich_home", "clothes", "jewelry"]]]},
	"farm": {"wall": ["barrel", "crate", "sack", "shelf"], "middle": ["table"], "tags": ["home", "kitchen"], "fill": 0.45, "containers": [["Sack", ["kitchen"]]]},
	"tavern": {"wall": ["barrel", "shelf", "barrel", "crate"], "middle": ["table", "table"], "tags": ["tavern", "kitchen"], "fill": 0.55, "containers": []},
	"shop": {"wall": ["shelf", "shelf", "crate", "barrel"], "middle": ["display"], "tags": ["shop", "tools", "kitchen", "clothes"], "fill": 0.6, "containers": []},
	"smithy": {"wall": ["rack", "shelf", "crate", "barrel"], "middle": ["bench"], "tags": ["smithy", "weapon", "armor", "tools"], "fill": 0.55, "containers": [["Crate", ["smithy"]]]},
	"temple": {"wall": ["shelf", "bookcase"], "middle": [], "tags": ["temple", "library"], "fill": 0.5, "containers": []},
	"alchemist": {"wall": ["shelf", "shelf", "bookcase", "barrel"], "middle": ["bench"], "tags": ["alchemist"], "fill": 0.6, "containers": []},
	"library": {"wall": ["bookcase", "bookcase", "shelf"], "middle": ["table"], "tags": ["library"], "fill": 0.6, "containers": []},
	"guild_fighters": {"wall": ["rack", "rack", "shelf", "barrel"], "middle": ["table"], "tags": ["weapon", "armor", "tavern"], "fill": 0.45, "containers": []},
	"guild_mages": {"wall": ["bookcase", "bookcase", "shelf"], "middle": ["table"], "tags": ["library", "alchemist"], "fill": 0.6, "containers": []},
	"guild_thieves": {"wall": ["crate", "barrel", "shelf"], "middle": ["table"], "tags": ["shop", "jewelry", "tavern"], "fill": 0.5, "containers": []},
	"guild_hunters": {"wall": ["rack", "shelf", "barrel"], "middle": ["table"], "tags": ["hunter", "camp"], "fill": 0.5, "containers": []},
	"guild_antiquarians": {"wall": ["bookcase", "plinth", "plinth", "shelf"], "middle": ["display"], "tags": ["library", "ruin"], "fill": 0.45, "containers": []},
	"guild_merchants": {"wall": ["shelf", "crate", "crate", "barrel"], "middle": ["table"], "tags": ["shop", "jeweler"], "fill": 0.5, "containers": []},
	"guild": {"wall": ["rack", "shelf", "bookcase"], "middle": ["table"], "tags": ["weapon", "library", "tavern"], "fill": 0.45, "containers": []},
	# dungeons
	"cave": {"wall": ["crate", "sack", "barrel"], "middle": ["campfire"], "tags": ["camp", "cave"], "fill": 0.35, "containers": [["Sack", ["camp", "cave"]]]},
	"camp": {"wall": ["crate", "barrel", "rack", "sack"], "middle": ["table", "campfire"], "tags": ["camp", "weapon", "tavern"], "fill": 0.45, "containers": [["Crate", ["camp", "weapon"]]]},
	"crypt": {"wall": ["niche", "urn", "niche"], "middle": ["sarcophagus"], "tags": ["crypt"], "fill": 0.4, "containers": [["Burial Urn", ["crypt"]]]},
	"barrow": {"wall": ["niche", "urn", "niche", "rack"], "middle": ["sarcophagus"], "tags": ["barrow", "crypt"], "fill": 0.4, "containers": [["Burial Urn", ["barrow"]]]},
	"mine": {"wall": ["crate", "barrel", "rack", "sack"], "middle": ["cart"], "tags": ["mine", "tools"], "fill": 0.45, "containers": [["Ore Crate", ["mine"]]]},
	"fort": {"wall": ["rack", "crate", "barrel", "shelf"], "middle": ["table"], "tags": ["weapon", "armor", "camp", "tavern"], "fill": 0.45, "containers": [["Footlocker", ["camp", "weapon"]]]},
	"ruin": {"wall": ["plinth", "rubble", "plinth"], "middle": ["altar"], "tags": ["ruin", "crypt"], "fill": 0.35, "containers": []},
	"vault": {"wall": ["plinth", "plinth", "shelf"], "middle": ["altar"], "tags": ["vault", "ruin", "jeweler"], "fill": 0.45, "containers": [["Vault Coffer", ["vault"]]]},
	"ice": {"wall": ["rubble", "niche", "crate"], "middle": ["altar"], "tags": ["ice", "crypt"], "fill": 0.35, "containers": []},
	"ashen": {"wall": ["plinth", "urn", "rubble"], "middle": ["altar"], "tags": ["ashen", "ashlands", "vault"], "fill": 0.4, "containers": []},
	"sewer": {"wall": ["crate", "barrel", "sack"], "middle": [], "tags": ["camp", "shop", "kitchen"], "fill": 0.35, "containers": [["Smuggler's Crate", ["shop", "jewelry"]]]},
}

const WOOD := Color(0.45, 0.31, 0.18)
const DARK_WOOD := Color(0.30, 0.20, 0.12)
const STONE := Color(0.50, 0.49, 0.46)
const METAL := Color(0.45, 0.46, 0.50)
const CELL := 0.5  # meters per occupancy cell
const WALK := 1.1  # half-width of the walkway kept clear from each door


## Furnishes `root` (local space). room = floor rectangle (x, z). doors = local floor points of
## the doors / openings. Returns {"pieces": n, "slots": n, "items": n, "containers": n}.
static func decorate(root: Node3D, room: Rect2, theme: String, level: int, room_seed: int, owner: String, save_prefix: String,
		doors: Array[Vector3] = [], restock_days: int = 0, today: int = 1, height: float = 3.0) -> Dictionary:
	var t: Dictionary = THEMES.get(theme, THEMES["home"])
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed
	var grid := Occupancy.new(room)
	grid.mark_existing(root)
	for d in doors:
		grid.mark_walkway(d, room.get_center())
	var slots: Array = []  # [local position of the surface top, max size]
	slots.append_array(_existing_surfaces(root, room))
	var pieces := 0
	# wall pieces: a few tries per wall meter
	var wall: Array = t["wall"]
	var perimeter := (room.size.x + room.size.y) * 2.0
	var want := int(perimeter / 2.6)
	for i in want * 3:
		if pieces >= want or wall.is_empty():
			break
		var kind: String = wall[rng.randi() % wall.size()]
		if _try_wall_piece(root, grid, room, kind, rng, slots, height):
			pieces += 1
	# middle pieces
	for kind: String in t["middle"]:
		for attempt in 12:
			var at := Vector2(rng.randf_range(room.position.x + 1.6, room.end.x - 1.6), rng.randf_range(room.position.y + 1.6, room.end.y - 1.6))
			if _middle_piece(root, grid, kind, at, rng.randf() * TAU if kind == "campfire" else (0.0 if rng.randf() < 0.5 else PI * 0.5), slots):
				pieces += 1
				break
	# containers
	var containers := 0
	for c: Array in t["containers"]:
		for attempt in 10:
			var at := Vector2(rng.randf_range(room.position.x + 0.6, room.end.x - 0.6), rng.randf_range(room.position.y + 0.6, room.end.y - 0.6))
			var size := Vector2(0.9, 0.7)
			if not grid.is_free(at, size, 0.1):
				continue
			grid.mark(at, size)
			var loot := ItemCatalog.tag_loot(PackedStringArray(c[1]), level, 1.5)
			loot.append(ItemCatalog.gold_loot(level, 0.5))
			var chest := POIBuilder.make_chest(c[0], loot, "%s/box_%d" % [save_prefix, containers], (room_seed + 811 * (containers + 1)) | 1)
			if owner != "":
				(chest.get_node("ContainerComponent") as ContainerComponent).owner_id = owner
			root.add_child(chest)
			chest.position = Vector3(at.x, 0.35, at.y)
			containers += 1
			break
	# loot on every surface
	var tags := PackedStringArray(t["tags"])
	var table := ItemCatalog.tag_loot(tags, level, 1.0)
	var fill: float = t["fill"]
	var items := 0
	for i in slots.size():
		var slot: Array = slots[i]
		var key := "%s/slot_%d" % [save_prefix, i]
		if rng.randf() > fill or table.is_empty():
			continue
		var taken := WorldState.get_record(WorldItem.taken_key(key))
		if not taken.is_empty():
			if restock_days <= 0 or today - int(taken.get("day", today)) < restock_days:
				continue
			WorldState.erase_record(WorldItem.taken_key(key))  # restocked
		var item := _pick(table, rng)
		if item == null:
			continue
		var at: Vector3 = slot[0]
		var w := WorldItem.place(item, 1, root, at, key, owner)
		var room_for: Vector2 = slot[1]
		if maxf(w.size.x, w.size.z) > maxf(room_for.x, room_for.y) * 1.6 + 0.2:
			root.remove_child(w)
			w.free()  # a greatsword does not fit on a shelf
			continue
		w.rotation.y = rng.randf() * TAU
		items += 1
	return {"pieces": pieces, "slots": slots.size(), "items": items, "containers": containers}


# One item from the list, by its chance (the chances act as weights here)
static func _pick(table: Array[LootEntry], rng: RandomNumberGenerator) -> ItemData:
	var total := 0.0
	for e in table:
		total += e.chance
	var r := rng.randf() * total
	for e in table:
		r -= e.chance
		if r <= 0.0:
			return e.item
	return table.back().item


# Tops of furniture that was already in the room (tables, counters, altars) become slots too
static func _existing_surfaces(root: Node3D, room: Rect2) -> Array:
	var out: Array = []
	for c in root.get_children():
		if not c is StaticBody3D or c is MuseumCase or c.name == "Chest" or not room.has_point(Vector2((c as Node3D).position.x, (c as Node3D).position.z)):
			continue
		var b := ItemModels.get_bounds(c as Node3D)
		b.position += (c as Node3D).position
		var top := b.end.y
		if top < 0.6 or top > 1.3 or b.size.x * b.size.z < 0.25 or b.size.x > room.size.x * 0.9 or b.size.z > room.size.y * 0.9:
			continue
		out.append([Vector3(b.get_center().x, top, b.get_center().z), Vector2(b.size.x, b.size.z)])
		if b.size.x * b.size.z > 1.0:  # a long counter holds two things
			var off := Vector3(b.size.x * 0.25, 0.0, 0.0) if b.size.x > b.size.z else Vector3(0.0, 0.0, b.size.z * 0.25)
			out.append([Vector3(b.get_center().x, top, b.get_center().z) + off, Vector2(b.size.x, b.size.z) * 0.5])
	return out


# A piece against a random wall, facing into the room
static func _try_wall_piece(root: Node3D, grid: Occupancy, room: Rect2, kind: String, rng: RandomNumberGenerator, slots: Array, height: float) -> bool:
	var size := _piece_size(kind)
	var side := rng.randi() % 4
	var at := Vector2.ZERO
	var yaw := 0.0
	var foot := size  # x along the wall, y depth
	match side:
		0:  # north wall (-z), faces +z
			at = Vector2(rng.randf_range(room.position.x + size.x * 0.5, room.end.x - size.x * 0.5), room.position.y + size.y * 0.5 + 0.02)
			yaw = 0.0
		1:  # south wall (+z), faces -z
			at = Vector2(rng.randf_range(room.position.x + size.x * 0.5, room.end.x - size.x * 0.5), room.end.y - size.y * 0.5 - 0.02)
			yaw = PI
		2:  # west wall (-x), faces +x
			at = Vector2(room.position.x + size.y * 0.5 + 0.02, rng.randf_range(room.position.y + size.x * 0.5, room.end.y - size.x * 0.5))
			yaw = -PI * 0.5
			foot = Vector2(size.y, size.x)
		_:  # east wall
			at = Vector2(room.end.x - size.y * 0.5 - 0.02, rng.randf_range(room.position.y + size.x * 0.5, room.end.y - size.x * 0.5))
			yaw = PI * 0.5
			foot = Vector2(size.y, size.x)
	if not grid.is_free(at, foot, 0.05):
		return false
	grid.mark(at, foot)
	_build_piece(root, kind, Vector3(at.x, 0.0, at.y), yaw, slots, height)
	return true


static func _middle_piece(root: Node3D, grid: Occupancy, kind: String, at: Vector2, yaw: float, slots: Array) -> bool:
	var size := _piece_size(kind)
	var foot := size if absf(sin(yaw)) < 0.5 else Vector2(size.y, size.x)
	if not grid.is_free(at, foot, 0.7):
		return false
	grid.mark(at, foot)
	_build_piece(root, kind, Vector3(at.x, 0.0, at.y), yaw, slots, 3.0)
	return true


## Footprint (width along the wall, depth) of each piece
static func _piece_size(kind: String) -> Vector2:
	match kind:
		"shelf", "bookcase": return Vector2(1.4, 0.45)
		"cupboard", "wardrobe": return Vector2(1.1, 0.6)
		"rack": return Vector2(1.6, 0.4)
		"barrel": return Vector2(0.7, 0.7)
		"crate": return Vector2(0.8, 0.8)
		"sack": return Vector2(0.6, 0.6)
		"urn": return Vector2(0.6, 0.6)
		"niche": return Vector2(1.6, 0.5)
		"plinth": return Vector2(0.7, 0.7)
		"rubble": return Vector2(1.2, 0.9)
		"table": return Vector2(1.6, 1.0)
		"display": return Vector2(1.8, 0.8)
		"bench": return Vector2(1.8, 0.8)
		"sarcophagus": return Vector2(2.3, 1.1)
		"altar": return Vector2(1.6, 1.0)
		"campfire": return Vector2(1.2, 1.2)
		"cart": return Vector2(1.6, 1.0)
	return Vector2(1.0, 1.0)


# Builds a piece at `at` (floor point, local), turned by yaw, and adds its surfaces to `slots`
static func _build_piece(root: Node3D, kind: String, at: Vector3, yaw: float, slots: Array, _height: float) -> void:
	var holder := Node3D.new()
	holder.name = "Decor_" + kind
	holder.position = at
	holder.rotation.y = yaw
	root.add_child(holder, true)  # readable names: Decor_shelf, Decor_shelf2, ...
	var s := _piece_size(kind)
	var tops: Array = []  # [local position, size] in the holder's space
	match kind:
		"shelf", "bookcase":
			var col := DARK_WOOD if kind == "bookcase" else WOOD
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(0.06, 1.9, s.y), Vector3(side * (s.x * 0.5 - 0.03), 0.95, 0.0), col)
			POIBuilder.add_box(holder, Vector3(s.x, 1.9, 0.04), Vector3(0.0, 0.95, -s.y * 0.5 + 0.02), col.darkened(0.2), 0.0, Vector3.ZERO, false)
			for y in [0.05, 0.62, 1.2, 1.78]:
				POIBuilder.add_box(holder, Vector3(s.x - 0.1, 0.04, s.y - 0.04), Vector3(0.0, y, 0.0), col)
				if y < 1.7:
					for x in [-s.x * 0.25, s.x * 0.25]:
						tops.append([Vector3(x, y + 0.02, 0.02), Vector2(s.x * 0.45, s.y)])
			if kind == "bookcase":  # rows of books
				for y in [0.62, 1.2]:
					POIBuilder.add_box(holder, Vector3(s.x * 0.4, 0.26, 0.24), Vector3(-s.x * 0.22, y + 0.15, -0.05), Color(0.45, 0.18, 0.15), 0.0, Vector3.ZERO, false)
		"cupboard", "wardrobe":
			POIBuilder.add_box(holder, Vector3(s.x, 1.2 if kind == "cupboard" else 2.0, s.y), Vector3(0.0, 0.6 if kind == "cupboard" else 1.0, 0.0), DARK_WOOD)
			if kind == "cupboard":
				tops.append([Vector3(0.0, 1.2, 0.0), s])
		"rack":
			POIBuilder.add_box(holder, Vector3(s.x, 0.08, 0.3), Vector3(0.0, 1.0, 0.0), DARK_WOOD)
			POIBuilder.add_box(holder, Vector3(s.x, 0.08, 0.3), Vector3(0.0, 0.5, 0.0), DARK_WOOD)
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(holder, Vector3(0.08, 1.2, 0.3), Vector3(side * s.x * 0.48, 0.6, 0.0), DARK_WOOD)
			tops.append([Vector3(-s.x * 0.22, 1.04, 0.0), Vector2(s.x * 0.45, 0.3)])
			tops.append([Vector3(s.x * 0.22, 1.04, 0.0), Vector2(s.x * 0.45, 0.3)])
		"barrel":
			_cyl(holder, 0.32, 0.9, Vector3(0.0, 0.45, 0.0), WOOD)
			tops.append([Vector3(0.0, 0.9, 0.0), Vector2(0.5, 0.5)])
		"crate":
			POIBuilder.add_box(holder, Vector3(0.75, 0.7, 0.75), Vector3(0.0, 0.35, 0.0), WOOD.lightened(0.1))
			tops.append([Vector3(0.0, 0.7, 0.0), Vector2(0.6, 0.6)])
		"sack":
			POIBuilder.add_box(holder, Vector3(0.5, 0.55, 0.45), Vector3(0.0, 0.28, 0.0), Color(0.65, 0.58, 0.42))
		"urn":
			_cyl(holder, 0.24, 0.7, Vector3(0.0, 0.35, 0.0), Color(0.5, 0.38, 0.28))
		"niche":
			POIBuilder.add_box(holder, Vector3(s.x, 0.12, s.y), Vector3(0.0, 0.9, 0.0), STONE)
			POIBuilder.add_box(holder, Vector3(s.x, 0.9, 0.2), Vector3(0.0, 0.45, -s.y * 0.4), STONE.darkened(0.2))
			tops.append([Vector3(-0.4, 0.96, 0.05), Vector2(0.7, 0.4)])
			tops.append([Vector3(0.4, 0.96, 0.05), Vector2(0.7, 0.4)])
		"plinth":
			POIBuilder.add_box(holder, Vector3(0.55, 1.0, 0.55), Vector3(0.0, 0.5, 0.0), STONE.lightened(0.15))
			tops.append([Vector3(0.0, 1.0, 0.0), Vector2(0.45, 0.45)])
		"rubble":
			POIBuilder.add_box(holder, Vector3(1.0, 0.4, 0.7), Vector3(0.0, 0.2, 0.0), STONE.darkened(0.15), 0.4)
			POIBuilder.add_box(holder, Vector3(0.5, 0.3, 0.4), Vector3(0.2, 0.5, 0.0), STONE, 0.9)
		"table":
			POIBuilder.add_box(holder, Vector3(s.x, 0.08, s.y), Vector3(0.0, 0.78, 0.0), WOOD)
			POIBuilder.add_box(holder, Vector3(s.x * 0.7, 0.74, s.y * 0.5), Vector3(0.0, 0.37, 0.0), DARK_WOOD)
			for x in [-s.x * 0.3, 0.0, s.x * 0.3]:
				tops.append([Vector3(x, 0.82, 0.0), Vector2(s.x * 0.3, s.y)])
		"display", "bench":
			POIBuilder.add_box(holder, Vector3(s.x, 0.9, s.y), Vector3(0.0, 0.45, 0.0), DARK_WOOD if kind == "display" else WOOD.darkened(0.2))
			for x in [-s.x * 0.3, 0.0, s.x * 0.3]:
				tops.append([Vector3(x, 0.9, 0.0), Vector2(s.x * 0.3, s.y)])
		"sarcophagus":
			POIBuilder.add_box(holder, Vector3(s.x, 0.8, s.y), Vector3(0.0, 0.4, 0.0), STONE)
			POIBuilder.add_box(holder, Vector3(s.x + 0.1, 0.12, s.y + 0.1), Vector3(0.0, 0.86, 0.0), STONE.lightened(0.1))
			tops.append([Vector3(-0.5, 0.92, 0.0), Vector2(0.6, 0.6)])
			tops.append([Vector3(0.5, 0.92, 0.0), Vector2(0.6, 0.6)])
		"altar":
			POIBuilder.add_box(holder, Vector3(s.x, 1.0, s.y), Vector3(0.0, 0.5, 0.0), STONE.lightened(0.2))
			tops.append([Vector3(0.0, 1.0, 0.0), Vector2(0.8, 0.6)])
			var glow := OmniLight3D.new()
			glow.light_color = Color(0.7, 0.8, 1.0)
			glow.light_energy = 0.6
			glow.omni_range = 4.0
			glow.position = Vector3(0.0, 1.6, 0.0)
			holder.add_child(glow)
		"campfire":
			for i in 6:
				var a := float(i) / 6.0 * TAU
				POIBuilder.add_box(holder, Vector3(0.25, 0.18, 0.25), Vector3(cos(a) * 0.45, 0.09, sin(a) * 0.45), STONE)
			POIBuilder.add_box(holder, Vector3(0.4, 0.2, 0.4), Vector3(0.0, 0.1, 0.0), Color(1.0, 0.5, 0.15), 0.0, Vector3.ZERO, false, true)
			var fire := OmniLight3D.new()
			fire.light_color = Color(1.0, 0.55, 0.25)
			fire.light_energy = 1.4
			fire.omni_range = 6.0
			fire.position = Vector3(0.0, 0.6, 0.0)
			holder.add_child(fire)
		"cart":
			POIBuilder.add_box(holder, Vector3(s.x, 0.6, s.y * 0.8), Vector3(0.0, 0.6, 0.0), DARK_WOOD)
			for x in [-0.55, 0.55]:
				_cyl(holder, 0.3, 0.1, Vector3(x, 0.3, s.y * 0.42), DARK_WOOD, true)
				_cyl(holder, 0.3, 0.1, Vector3(x, 0.3, -s.y * 0.42), DARK_WOOD, true)
			tops.append([Vector3(0.0, 0.9, 0.0), Vector2(1.0, 0.6)])
	for top: Array in tops:
		var p: Vector3 = top[0]
		slots.append([at + p.rotated(Vector3.UP, yaw), top[1]])


static func _cyl(parent: Node3D, radius: float, h: float, pos: Vector3, color: Color, sideways: bool = false) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	if sideways:
		body.rotation.x = PI * 0.5
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = h
	cyl.radial_segments = 12
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = h
	shape.shape = cs
	body.add_child(shape)
	parent.add_child(body)


## Which half-meter cells of the floor are taken
class Occupancy:
	var rect: Rect2
	var w: int
	var h: int
	var cells := PackedByteArray()

	func _init(r: Rect2) -> void:
		rect = r
		w = maxi(int(ceil(r.size.x / CELL)), 1)
		h = maxi(int(ceil(r.size.y / CELL)), 1)
		cells.resize(w * h)

	func _cell_range(at: Vector2, size: Vector2, pad: float) -> Rect2i:
		var x0 := floori((at.x - size.x * 0.5 - pad - rect.position.x) / CELL)
		var z0 := floori((at.y - size.y * 0.5 - pad - rect.position.y) / CELL)
		var x1 := floori((at.x + size.x * 0.5 + pad - rect.position.x - 0.001) / CELL)
		var z1 := floori((at.y + size.y * 0.5 + pad - rect.position.y - 0.001) / CELL)
		return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)

	func is_free(at: Vector2, size: Vector2, pad: float) -> bool:
		var r := _cell_range(at, size, pad)
		for z in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x < 0 or z < 0 or x >= w or z >= h:
					continue  # beyond the walls: the margin may reach there, the piece itself never does
				if cells[z * w + x] != 0:
					return false
		return true

	func mark(at: Vector2, size: Vector2, pad: float = 0.0) -> void:
		var r := _cell_range(at, size, pad)
		for z in range(maxi(r.position.y, 0), mini(r.end.y, h)):
			for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
				cells[z * w + x] = 1

	## A straight walkway from a door to the room's middle
	func mark_walkway(door: Vector3, center: Vector2) -> void:
		var a := Vector2(door.x, door.z)
		var steps := int(a.distance_to(center) / (CELL * 0.5)) + 1
		for i in steps + 1:
			mark(a.lerp(center, float(i) / steps), Vector2(WALK * 2.0, WALK * 2.0))

	## Everything already standing in the room (furniture, not walls, floor or ceiling)
	func mark_existing(root: Node3D) -> void:
		for c in root.get_children():
			if not (c is Node3D) or c is Light3D or c is WorldItem:
				continue
			var cp := (c as Node3D).position
			if not rect.has_point(Vector2(cp.x, cp.z)):
				continue  # outside this room (walls stand just outside it)
			var b := ItemModels.get_bounds(c as Node3D)
			b.position += (c as Node3D).position
			if b.end.y <= 0.05 or b.position.y > 2.0:
				continue  # floor, ceiling, beams
			if b.size.x >= rect.size.x * 0.95 or b.size.z >= rect.size.y * 0.95:
				continue  # a wall
			mark(Vector2(b.get_center().x, b.get_center().z), Vector2(b.size.x, b.size.z), 0.25)
