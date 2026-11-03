class_name RoomDecorator
extends RefCounted
## Puts loose loot on the surfaces of a room's own furniture. Used for every building interior (and the
## old generated dungeons). It never adds furniture (Alpha 1.20): a room's furniture is its scene's, placed
## by hand, so a room looks the same every time; only the things set on it change.
##
##   1. Every surface of the furniture already in the room is a loot slot: table tops, each shelf plank,
##      counter, altar and cupboard tops (read from the models themselves).
##   2. A slot gets one item (or none) from the theme's loot tags crossed with what suits that surface
##      (SURFACE_TAGS), at the room's level (ItemCatalog.tag_loot); some slots get a small thing you can
##      pick up (a plate, a candlestick, a book: CLUTTER).
##   3. Items are placed frozen (WorldItem.place), owned by `owner` (empty = free to take), and
##      remembered by slot id: once taken, a slot stays empty (shops and homes refill after
##      `restock_days`, dungeons never).
## Builder-kit loot furniture (KitLootShelf) fills itself and is left alone here.

## theme -> {"tags": [loot tags], "fill": chance a slot holds something}
const THEMES := {
	"home": {"tags": ["home", "kitchen", "clothes"], "fill": 0.5},
	"rich_home": {"tags": ["rich_home", "kitchen", "library", "jewelry"], "fill": 0.55},
	"farm": {"tags": ["home", "kitchen"], "fill": 0.45},
	"tavern": {"tags": ["tavern", "kitchen"], "fill": 0.55},
	"shop": {"tags": ["shop", "tools", "kitchen", "clothes"], "fill": 0.6},
	"smithy": {"tags": ["smithy", "weapon", "armor", "tools"], "fill": 0.55},
	"temple": {"tags": ["temple", "library"], "fill": 0.5},
	"alchemist": {"tags": ["alchemist"], "fill": 0.6},
	"library": {"tags": ["library"], "fill": 0.6},
	"guild_fighters": {"tags": ["weapon", "armor", "tavern"], "fill": 0.45},
	"guild_mages": {"tags": ["library", "alchemist"], "fill": 0.6},
	"guild_thieves": {"tags": ["shop", "jewelry", "tavern"], "fill": 0.5},
	"guild_hunters": {"tags": ["hunter", "camp"], "fill": 0.5},
	"guild_antiquarians": {"tags": ["library", "ruin"], "fill": 0.45},
	"guild_merchants": {"tags": ["shop", "jeweler"], "fill": 0.5},
	"guild": {"tags": ["weapon", "library", "tavern"], "fill": 0.45},
	# dungeons
	"cave": {"tags": ["camp", "cave"], "fill": 0.55},
	"camp": {"tags": ["camp", "weapon", "tavern"], "fill": 0.65},
	"crypt": {"tags": ["crypt"], "fill": 0.60},
	"barrow": {"tags": ["barrow", "crypt"], "fill": 0.60},
	"mine": {"tags": ["mine", "tools"], "fill": 0.65},
	"fort": {"tags": ["weapon", "armor", "camp", "tavern"], "fill": 0.65},
	"ruin": {"tags": ["ruin", "crypt"], "fill": 0.55},
	"vault": {"tags": ["vault", "ruin", "jeweler"], "fill": 0.65},
	"ice": {"tags": ["ice", "crypt"], "fill": 0.55},
	"ashen": {"tags": ["ashen", "ashlands", "vault"], "fill": 0.60},
	"sewer": {"tags": ["camp", "shop", "kitchen"], "fill": 0.55},
}



## Sets loot on the furniture in `root` (local space). room = floor rectangle (x, z). `doors` and `height`
## are no longer used (kept so old callers still work). fill_scale below 1 thins it out (dungeon rooms),
## and then a bare room stays bare. Returns {"pieces": 0, "slots": n, "items": n,
## "containers": 0, "clutter": n}.
static func decorate(root: Node3D, room: Rect2, theme: String, level: int, room_seed: int, owner: String, save_prefix: String,
		_doors: Array[Vector3] = [], restock_days: int = 0, today: int = 1, _height: float = 3.0, fill_scale: float = 1.0) -> Dictionary:
	for p in root.find_children("*", "StaticBody3D", true, false):
		if p is InteriorProp:
			(p as InteriorProp).dress()  # props in the room scene get their models before their tops are measured
	var t: Dictionary = THEMES.get(theme, THEMES["home"])
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed
	var slots := _existing_surfaces(root, room)
	# small things that belong in the room and can be picked up: plates and cups on tables, books on shelves
	var clutter := _place_clutter(root, theme, slots, rng, save_prefix, owner, restock_days, today)
	# loot on every surface, from that surface's own table at the room's level
	var tags := PackedStringArray(t["tags"])
	var tables := {}
	var table_for := func(kind: String) -> Array[LootEntry]:
		if not tables.has(kind):
			tables[kind] = ItemCatalog.tag_loot(surface_tags(kind, tags), level, 1.0)
		return tables[kind]
	var table := ItemCatalog.tag_loot(tags, level, 1.0)
	var fill: float = t["fill"] * fill_scale
	if fill_scale >= 1.0:
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
		var w := WorldItem.place(item, 1, root, slot[0], key, owner)
		if not set_on(w, slot, slots, rng):
			root.remove_child(w)
			w.free()  # a greatsword does not fit on a shelf
			return false
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
		if items >= 3 or fill_scale < 1.0:
			break
		if place.call(i):
			items += 1
	return {"pieces": 0, "slots": slots.size(), "items": items, "containers": 0, "clutter": clutter}


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

## Small things you can pick up, by room theme (CLUTTER_ITEMS; kinds without an item are skipped)
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


## What each kind of clutter is as an item (baskets, cloth and spoons are not things: place them by hand,
## as kit models clutter/basket...)
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


# Clutter on the surfaces: about half of them get one or two small things, rolled like the loot
static func _place_clutter(root: Node3D, theme: String, slots: Array, rng: RandomNumberGenerator, save_prefix: String = "", owner: String = "", restock_days: int = 0, today: int = 1) -> int:
	var kinds: Array = CLUTTER.get(theme, CLUTTER.get(theme.get_slice("_", 0), CLUTTER["home"]))
	var have: Array = kinds.filter(func(k): return ResourceLoader.exists(String(CLUTTER_ITEMS.get(k, ""))))
	if have.is_empty() or save_prefix == "":
		return 0
	var n := 0
	for si in slots.size():
		var slot: Array = slots[si]
		if rng.randf() > 0.55:
			continue
		var room_for: Vector2 = slot[1]
		for j in (1 if rng.randf() < 0.6 else 2):
			var kind := String(have[rng.randi() % have.size()])
			# off to one side of the surface, leaving the middle for loot
			var reach := minf(room_for.x, room_for.y) * 0.32
			var a := rng.randf() * TAU
			var off := Vector3(cos(a), 0.0, sin(a)) * reach * rng.randf_range(0.6, 1.0)
			var at := (slot[0] as Vector3) + off
			var yaw := rng.randf() * TAU
			# owned like the room's loot: once taken it stays gone until the room restocks
			var key := "%s/clutter_%d_%d" % [save_prefix, si, j]
			var taken := WorldState.get_record(WorldItem.taken_key(key))
			if not taken.is_empty():
				if restock_days <= 0 or today - int(taken.get("day", today)) < restock_days:
					continue
				WorldState.erase_record(WorldItem.taken_key(key))
			var w := WorldItem.place(load(String(CLUTTER_ITEMS[kind])) as ItemData, 1, root, at, key, owner)
			w.rotation.y = yaw
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
		if not (c is StaticBody3D or decor) or c is MuseumCase or c is KitLootShelf or c is CraftingStation or c.name == "Chest" or not room.has_point(Vector2((c as Node3D).position.x, (c as Node3D).position.z)):
			continue
		var b := (c as Node3D).transform * ModelLibrary.bounds(c as Node3D)  # in the room's space, turned as it stands
		var top := b.end.y
		if b.size.x > room.size.x * 0.9 or b.size.z > room.size.y * 0.9:
			continue  # a wall or a floor, not furniture
		var shelf := (c is InteriorProp and (c as InteriorProp).tags.has("shelf")) or (decor and (String(c.name).contains("shelf") or String(c.name).contains("bookcase")))
		var holds := shelf
		for word in ["table", "counter", "altar", "desk", "plinth", "display", "sarcophagus", "cupboard", "bar"]:
			if String(c.name).to_lower().contains(word) or (c is InteriorProp and (c as InteriorProp).tags.has(word)):
				holds = true
		if holds:
			# its own planks and tops, read from what you see (a model's shelves are wherever it puts them)
			var on_it := ModelLibrary.surface_slots(c as Node3D, root, "shelf" if shelf else "table")
			if not on_it.is_empty():
				out.append_array(on_it)
				continue
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




## Turns `w` (just placed on `slot`, one of `slots`: [position, room, label]) to sit on it; false when it
## does not fit: too long for the spot, too deep for the plank or too tall for the gap under the plank
## above. Such a thing would stand inside the furniture and be pushed out of it (through the wall behind)
## the moment it is touched. On shelving things lie along the plank; elsewhere any way round.
static func set_on(w: WorldItem, slot: Array, slots: Array, rng: RandomNumberGenerator) -> bool:
	var at: Vector3 = slot[0]
	var room: Vector2 = slot[1]
	var long := maxf(w.size.x, w.size.z)
	var length := maxf(room.x, room.y)
	if long > length * 1.6 + 0.2:
		return false
	var shelving := slot.size() > 2 and String(slot[2]) in ["shelf", "bookcase", "rack", "niche", "cupboard", "wardrobe", "display"]
	if not shelving:
		w.rotation.y = rng.randf() * TAU
		return true
	var depth := minf(room.x, room.y) / 0.8  # surface_slots gives 80% of the plank's depth
	if minf(w.size.x, w.size.z) > depth * 0.95 or long > length * 1.15 + 0.05:
		return false
	var above := INF
	for s: Array in slots:
		var p: Vector3 = s[0]
		if p.y > at.y + 0.1 and Vector2(p.x - at.x, p.z - at.z).length() < 0.6:
			above = minf(above, p.y)  # the next plank up, on this same piece
	if w.size.y > above - at.y - 0.06:
		return false
	var along_x := room.x >= room.y
	var item_x := w.size.x >= w.size.z
	w.rotation.y = (0.0 if along_x == item_x else PI * 0.5) + rng.randf_range(-0.12, 0.12)
	return true
