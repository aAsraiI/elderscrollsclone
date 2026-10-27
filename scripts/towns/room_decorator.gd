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
	for p in root.find_children("*", "StaticBody3D", true, false):
		if p is InteriorProp:
			(p as InteriorProp).dress()  # props in the room scene get their models before their tops are measured
	var t: Dictionary = THEMES.get(theme, THEMES["home"])
	# Two seeds: the room's own picks the loot; the layout (furniture, clutter) comes from the theme, the
	# room's size and one of LAYOUTS variants, so rooms of a kind look alike wherever they are
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed
	var layout := RandomNumberGenerator.new()
	layout.seed = ("%s|%d|%d|%d" % [theme, roundi(room.size.x * 2.0), roundi(room.size.y * 2.0), absi(room_seed) % LAYOUTS]).hash()
	var grid := Occupancy.new(room)
	grid.mark_existing(root)
	for d in doors:
		grid.mark_walkway(d, room.get_center())
	var slots: Array = []  # [local position of the surface top, max size]
	slots.append_array(_existing_surfaces(root, room))
	var pieces := 0
	# wall pieces: a few tries per wall meter
	var wall: Array = t["wall"]
	if not DUNGEON_THEMES.has(theme) and not wall.has("shelf"):
		wall = wall + ["shelf"]  # every room people live in has somewhere to put things
	var perimeter := (room.size.x + room.size.y) * 2.0
	var want := int(perimeter / 2.0)
	for i in want * 3:
		if pieces >= want or wall.is_empty():
			break
		var kind: String = wall[layout.randi() % wall.size()]
		if _try_wall_piece(root, grid, room, kind, layout, slots, height):
			pieces += 1
	# middle pieces
	for kind: String in t["middle"]:
		for attempt in 12:
			var at := Vector2(layout.randf_range(room.position.x + 1.6, room.end.x - 1.6), layout.randf_range(room.position.y + 1.6, room.end.y - 1.6))
			if _middle_piece(root, grid, kind, at, layout.randf() * TAU if kind == "campfire" else (0.0 if layout.randf() < 0.5 else PI * 0.5), slots):
				pieces += 1
				break
	# containers
	var containers := 0
	for c: Array in t["containers"]:
		for attempt in 10:
			var at := Vector2(layout.randf_range(room.position.x + 0.6, room.end.x - 0.6), layout.randf_range(room.position.y + 0.6, room.end.y - 0.6))
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
	# things that belong in the room: plates and cups on tables, books and bottles on shelves, candles,
	# bones in crypts... the same in every room of this kind (they are part of the layout, not loot)
	var clutter := _place_clutter(root, theme, slots, layout, save_prefix, owner, restock_days, today)
	# loot on every surface, from that surface's own table at the room's level
	var tags := PackedStringArray(t["tags"])
	var tables := {}
	var table_for := func(kind: String) -> Array[LootEntry]:
		if not tables.has(kind):
			tables[kind] = ItemCatalog.tag_loot(surface_tags(kind, tags), level, 1.0)
		return tables[kind]
	var table := ItemCatalog.tag_loot(tags, level, 1.0)
	var fill: float = t["fill"]
	fill = maxf(fill, minf(0.85, 3.5 / maxf(slots.size(), 1.0)))  # a small room still has a few things about
	var items := 0
	var place := func(i: int) -> bool:
		var slot: Array = slots[i]
		var key := "%s/slot_%d" % [save_prefix, i]
		var taken := WorldState.get_record(WorldItem.taken_key(key))
		if not taken.is_empty():
			if restock_days <= 0 or today - int(taken.get("day", today)) < restock_days:
				return false
			WorldState.erase_record(WorldItem.taken_key(key))  # restocked
		var own: Array[LootEntry] = table_for.call(String(slot[2]) if slot.size() > 2 else "")
		var item := _pick(own if not own.is_empty() else table, rng)
		if item == null:
			return false
		var at: Vector3 = slot[0]
		var w := WorldItem.place(item, 1, root, at, key, owner)
		var room_for: Vector2 = slot[1]
		if maxf(w.size.x, w.size.z) > maxf(room_for.x, room_for.y) * 1.6 + 0.2:
			root.remove_child(w)
			w.free()  # a greatsword does not fit on a shelf
			return false
		w.rotation.y = rng.randf() * TAU
		return true
	var skipped: Array[int] = []
	for i in slots.size():
		if rng.randf() > fill or table.is_empty():
			if not table.is_empty():
				skipped.append(i)
			continue
		if place.call(i):
			items += 1
	# a room that ended up nearly bare gets a few things after all, where there is room for them
	for i in skipped:
		if items >= 3:
			break
		if place.call(i):
			items += 1
	return {"pieces": pieces, "slots": slots.size(), "items": items, "containers": containers, "clutter": clutter}


## Variants of each kind of room (layouts repeat across rooms of the same kind and size)
const LAYOUTS := 3
const DUNGEON_THEMES := ["cave", "camp", "crypt", "barrow", "mine", "fort", "ruin", "vault", "ice", "ashen", "sewer"]

## Which loot suits a kind of surface (crossed with the room's own tags; the room's tags alone when
## nothing matches): books on bookcases, weapons on racks, food on tables, treasure on altars
const SURFACE_TAGS := {
	"shelf": ["kitchen", "alchemist", "alchemy", "tools", "clothes", "home", "library", "mine", "camp", "tavern"],
	"bookcase": ["library", "mage", "temple"],
	"table": ["kitchen", "tavern", "home", "alchemy", "alchemist", "camp", "rich_home"],
	"rack": ["weapon", "weapons", "armor", "smithy", "hunter"],
	"display": ["jewelry", "jeweler", "shop", "rich_home", "vault"],
	"plinth": ["jewelry", "jeweler", "vault", "ruin", "temple", "crypt"],
	"altar": ["temple", "vault", "jewelry", "ruin", "ashen"],
	"niche": ["crypt", "barrow", "ruin", "jewelry"],
	"sarcophagus": ["crypt", "barrow", "jewelry", "vault"],
	"bench": ["smithy", "alchemist", "alchemy", "tools"],
	"barrel": ["kitchen", "tavern", "camp", "mine", "tools"],
	"crate": ["tools", "mine", "camp", "kitchen", "smithy", "shop"],
	"cart": ["mine", "tools", "camp"],
}

## Clutter by room theme (ModelLibrary "clutter/<name>" keys; missing ones are skipped)
const CLUTTER := {
	"home": ["plate", "bowl", "cup", "candle", "basket", "pitcher", "spoon", "cloth"],
	"rich_home": ["plate_metal", "goblet", "candle", "book", "bottle_2", "pitcher", "cloth"],
	"farm": ["bowl", "basket", "cup", "bread", "candle"],
	"tavern": ["tankard", "plate", "bottle", "bottle_3", "cup", "candle", "pitcher", "bread"],
	"shop": ["basket", "bottle", "cloth", "candle", "book_2"],
	"smithy": ["hammer", "tankard", "candle", "cloth"],
	"temple": ["candle", "book", "book_open", "scroll", "goblet", "urn"],
	"alchemist": ["flask", "beaker", "bottle", "bottle_2", "bowl_redware", "book", "candle"],
	"library": ["book", "book_2", "book_3", "book_open", "scroll", "inkwell", "quill", "candle", "paper"],
	"guild": ["tankard", "candle", "book", "plate"],
	"camp": ["cup", "bowl", "bone", "bottle", "candle"],
	"cave": ["bone", "skull", "bowl"],
	"crypt": ["skull", "bone", "candle", "urn"],
	"barrow": ["skull", "bone", "urn"],
	"mine": ["cup", "bottle", "candle", "hammer"],
	"fort": ["tankard", "plate", "candle", "book_2"],
	"ruin": ["skull", "urn", "bone"],
	"vault": ["goblet", "urn", "book_3"],
	"sewer": ["bottle", "bone", "cup"],
}


## The loot tags for a kind of surface in a room with these tags
static func surface_tags(kind: String, room_tags: PackedStringArray) -> PackedStringArray:
	var suits: Array = SURFACE_TAGS.get(kind, [])
	var out := PackedStringArray()
	for tag in room_tags:
		if suits.has(tag):
			out.append(tag)
	return out if not out.is_empty() else room_tags


# Clutter on the surfaces: about half of them get one or two small things, picked by the layout seed
# The clutter you can pick up: what each kind of clutter is as an item. The rest (baskets, cloth,
# spoons) stays a fixed part of the room.
const CLUTTER_ITEMS := {
	"plate": "res://data/clutter/plate.tres", "plate_metal": "res://data/clutter/plate.tres",
	"bowl": "res://data/clutter/bowl.tres", "bowl_redware": "res://data/clutter/bowl.tres",
	"cup": "res://data/clutter/cup.tres", "tankard": "res://data/clutter/tankard.tres",
	"pitcher": "res://data/clutter/tankard.tres", "goblet": "res://data/clutter/silver_goblet.tres",
	"candle": "res://data/clutter/candlestick.tres",
	"book": "res://data/clutter/old_book.tres", "book_2": "res://data/clutter/old_book.tres",
	"book_3": "res://data/clutter/ledger.tres", "book_open": "res://data/clutter/torn_journal.tres",
	"scroll": "res://data/clutter/blank_scroll.tres", "paper": "res://data/clutter/blank_scroll.tres",
	"inkwell": "res://data/clutter/inkwell.tres", "quill": "res://data/clutter/quill.tres",
	"skull": "res://data/clutter/skull.tres", "bone": "res://data/clutter/old_bone.tres",
	"urn": "res://data/clutter/burial_urn.tres", "hammer": "res://data/clutter/smith_hammer.tres",
	"bottle": "res://data/misc/empty_bottle.tres", "bottle_2": "res://data/misc/empty_bottle.tres",
	"bottle_3": "res://data/misc/empty_bottle.tres", "flask": "res://data/misc/empty_bottle.tres",
	"beaker": "res://data/misc/empty_bottle.tres", "bread": "res://data/consumables/bread.tres",
}


static func _place_clutter(root: Node3D, theme: String, slots: Array, layout: RandomNumberGenerator, save_prefix: String = "", owner: String = "", restock_days: int = 0, today: int = 1) -> int:
	var kinds: Array = CLUTTER.get(theme, CLUTTER.get(theme.get_slice("_", 0), CLUTTER["home"]))
	var have: Array = kinds.filter(func(k): return ModelLibrary.has("clutter/" + String(k)) or CLUTTER_ITEMS.has(k))
	if have.is_empty():
		return 0
	var n := 0
	for si in slots.size():
		var slot: Array = slots[si]
		if layout.randf() > 0.55:
			continue
		var room_for: Vector2 = slot[1]
		for j in (1 if layout.randf() < 0.6 else 2):
			var kind := String(have[layout.randi() % have.size()])
			# off to one side of the surface, leaving the middle for loot
			var reach := minf(room_for.x, room_for.y) * 0.32
			var a := layout.randf() * TAU
			var off := Vector3(cos(a), 0.0, sin(a)) * reach * layout.randf_range(0.6, 1.0)
			var at := (slot[0] as Vector3) + off
			var yaw := layout.randf() * TAU
			var item_path: String = CLUTTER_ITEMS.get(kind, "")
			if item_path != "" and save_prefix != "" and ResourceLoader.exists(item_path):
				# a real item, owned like the room's loot: once taken it stays gone until the room restocks
				var key := "%s/clutter_%d_%d" % [save_prefix, si, j]
				var taken := WorldState.get_record(WorldItem.taken_key(key))
				if not taken.is_empty():
					if restock_days <= 0 or today - int(taken.get("day", today)) < restock_days:
						continue
					WorldState.erase_record(WorldItem.taken_key(key))
				var w := WorldItem.place(load(item_path) as ItemData, 1, root, at, key, owner)
				w.rotation.y = yaw
				n += 1
				continue
			if not ModelLibrary.has("clutter/" + kind):
				continue
			var m := ModelLibrary.fitted("clutter/" + kind, AABB(Vector3(-0.1, 0.0, -0.1), Vector3(0.2, 0.25, 0.2)))
			if m == null:
				continue
			m.name = "Clutter"
			for light in m.find_children("*", "Light3D", true, false):
				light.queue_free()  # the flame still glows; a room of candles does not need a light each
			m.position = at
			m.rotation.y = yaw
			root.add_child(m)
			n += 1
	return n


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
		var decor := c is Node3D and String(c.name).begins_with("Decor_")  # furniture an interior builder put in
		if not (c is StaticBody3D or decor) or c is MuseumCase or c.name == "Chest" or not room.has_point(Vector2((c as Node3D).position.x, (c as Node3D).position.z)):
			continue
		var b := (c as Node3D).transform * ModelLibrary.bounds(c as Node3D)  # in the room's space, turned as it stands
		var top := b.end.y
		if (c is InteriorProp and (c as InteriorProp).tags.has("shelf")) or (decor and (String(c.name).contains("shelf") or String(c.name).contains("bookcase"))):
			# a shelf prop (1.13 rooms): one thing on each plank, just in front of its back board
			var fwd := (c as Node3D).basis * Vector3(0, 0, -0.05)
			for f: float in [0.33, 0.63]:  # its planks, wherever its model puts them
				out.append([Vector3(b.get_center().x, b.position.y + b.size.y * f, b.get_center().z) + fwd, Vector2(0.5, 0.3), "shelf"])
			continue
		if top < 0.6 or top > 1.5 or b.size.x * b.size.z < 0.25 or b.size.x > room.size.x * 0.9 or b.size.z > room.size.y * 0.9:
			continue
		out.append([Vector3(b.get_center().x, top, b.get_center().z), Vector2(b.size.x, b.size.z), "table"])
		if b.size.x * b.size.z > 1.0:  # a long counter holds two things
			var off := Vector3(b.size.x * 0.25, 0.0, 0.0) if b.size.x > b.size.z else Vector3(0.0, 0.0, b.size.z * 0.25)
			out.append([Vector3(b.get_center().x, top, b.get_center().z) + off, Vector2(b.size.x, b.size.z) * 0.5, "table"])
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
	# A real model for this piece (ModelLibrary "prop/<kind>") replaces its boxes; its surfaces move to
	# the model's own heights (a shelf's planks, a table top) in proportion
	var old_top := ModelLibrary.bounds(holder).end.y
	var heights := 1.0
	if ModelLibrary.replace_meshes(holder, "prop/" + kind) != null and old_top > 0.05:
		heights = ModelLibrary.bounds(holder).end.y / old_top
	for top: Array in tops:
		var p: Vector3 = top[0]
		p.y *= heights
		slots.append([at + p.rotated(Vector3.UP, yaw), top[1], kind])


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
			if not (c is Node3D) or c is Light3D or c is WorldItem or c is Marker3D or c is SpawnSocket:
				continue
			var cp := (c as Node3D).position
			if not rect.has_point(Vector2(cp.x, cp.z)):
				continue  # outside this room (walls stand just outside it)
			var b := ModelLibrary.bounds(c as Node3D)
			b.position += (c as Node3D).position
			if b.end.y <= 0.05 or b.position.y > 2.0:
				continue  # floor, ceiling, beams
			if b.size.x >= rect.size.x * 0.95 or b.size.z >= rect.size.y * 0.95:
				continue  # a wall
			mark(Vector2(b.get_center().x, b.get_center().z), Vector2(b.size.x, b.size.z), 0.25)
