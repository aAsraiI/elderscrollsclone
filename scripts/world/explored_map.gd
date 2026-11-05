class_name ExploredMap
extends RefCounted
## Alpha 1.31.1: the map's fog. The world map is greyed over until you have been near a place (or
## bought a map of it). Kept per character in WorldState "explored" {"cells": [packed cell ints]};
## Tutorial marks the cells around the player every second. Settings > Interface > Map fog turns
## the layer off. The map draws it as one small texture, one pixel per cell.
## CARTOGRAPHERS: innkeepers sell a map of the land around them ("a map of these parts"): it clears
## the fog for MAP_RADIUS and puts the places in it on your map.

const CELL := 200.0
const SEE := 1  # cells on each side you clear as you go
const MAP_RADIUS := 1600.0
const MAP_PRICE := 150
const OFFSET := 32768

static var _cells := {}
static var image_dirty := true
static var _save_ver := -1


static func key(cx: int, cz: int) -> int:
	return (cx + OFFSET) * 65536 + (cz + OFFSET)


static func _load() -> void:
	var rec := WorldState.get_record("explored")
	if _save_ver == int(rec.get("v", 0)):
		return
	_cells = {}
	for k in rec.get("cells", []):
		_cells[int(k)] = true
	_save_ver = int(rec.get("v", 0))
	image_dirty = true


static func _store() -> void:
	_save_ver += 1
	WorldState.set_record("explored", {"cells": _cells.keys(), "v": _save_ver})
	image_dirty = true


static func is_explored(x: float, z: float) -> bool:
	_load()
	return _cells.has(key(floori(x / CELL), floori(z / CELL)))


## Clears the fog around a spot. Returns true if anything new was cleared.
static func reveal(x: float, z: float, cells: int = SEE) -> bool:
	_load()
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	var any := false
	for dx in range(-cells, cells + 1):
		for dz in range(-cells, cells + 1):
			var k := key(cx + dx, cz + dz)
			if not _cells.has(k):
				_cells[k] = true
				any = true
	if any:
		_store()
	return any


static func count() -> int:
	_load()
	return _cells.size()


## The fog as an image over these bounds: dark where unexplored, clear where explored
static func make_image(bounds: Rect2) -> Image:
	_load()
	var w := maxi(ceili(bounds.size.x / CELL), 1)
	var h := maxi(ceili(bounds.size.y / CELL), 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.11, 0.1, 0.72))
	var ox := floori(bounds.position.x / CELL)
	var oz := floori(bounds.position.y / CELL)
	for k: int in _cells:
		var cx := int(k / 65536) - OFFSET - ox
		var cz := int(k % 65536) - OFFSET - oz
		if cx >= 0 and cz >= 0 and cx < w and cz < h:
			img.set_pixel(cx, cz, Color(0, 0, 0, 0))
	image_dirty = false
	return img


# ---------------------------------------------------------------- the cartographer

static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s != null and not s.asleep and s.role == NpcData.Role.INNKEEPER:
		out.append("a map of these parts")
	return out


static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, world: WorldManager) -> Dictionary:
	if topic != "a map of these parts" or not topics_for(s).has(topic):
		return {}
	var inv := player.get_node("Inventory") as Inventory
	if Currency.get_gold(inv) < MAP_PRICE:
		return Roleplay._say("A traveller's map of these parts? %d gold. Come back with it." % MAP_PRICE)
	Currency.spend_gold(inv, MAP_PRICE)
	var at := s.position if s.position != Vector3.ZERO else (player as Node3D).global_position
	var n := buy_map(at, world, ceili(MAP_RADIUS / CELL))
	Achievements.note("map_bought")
	return Roleplay._say("%d gold. It's all there: the roads, the old places, %d of them new to you by the look of it." % [MAP_PRICE, n])


## Reveals around a spot and marks the places there as found. Returns how many new places.
static func buy_map(at: Vector3, world: WorldManager, cells: int) -> int:
	reveal(at.x, at.z, cells)
	var n := 0
	if world != null and world.discovery != null:
		for p in world.get_pois_near(at, MAP_RADIUS):
			if world.discovery.mark_found(p):
				n += 1
	return n
