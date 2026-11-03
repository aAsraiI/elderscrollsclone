@tool
class_name KitLootShelf
extends StaticBody3D
## The builder kit: furniture that holds loot (scenes/kit/surfaces/): a shelf, bookcase, table, counter,
## altar, rack, lectern... drawn as its model, with things set on its planks and top when the game runs.
## The furniture always stands where you put it; only what is on it changes (rolled per place and save).
##   Where things go is read from the model itself: every plank of shelving, only the top of a table.
##   What goes there: its own Loot Tags, else what the place holds that suits this kind of surface
##   (KitPlace.tags: books on a bookcase in a library, food on a tavern table), at the place's level.
##   Shelving gets exact collision (ModelLibrary.OPEN), so you can put things back on its planks.
## In town buildings taken things come back after a few days; in dungeons and outdoors they never do.

@export var furniture := "prop/shelf":
	set(v):
		furniture = v
		_build_model()
## Used when Furniture has no model (a Morrowind key before the import)
@export var fallback := "":
	set(v):
		fallback = v
		_build_model()
## What kind of surface it is for loot ("shelf", "bookcase", "table", "rack", "altar"...); empty = read from
## the furniture's name
@export var surface := ""
## What can be found on it (ItemCatalog tags); empty = what the place holds
@export var loot_tags: PackedStringArray = []
## How many of its spots get something (0..1)
@export_range(0.0, 1.0) var fill := 0.6
## Levels above (or below) the place's
@export var level_bonus := 0
## Who it belongs to ("" = whoever owns the building it stands in)
@export var owner_id := ""
## Never anyone's, even inside a building
@export var free_to_take := false


func _ready() -> void:
	_build_model()
	if not Engine.is_editor_hint():
		_fill.call_deferred()


func key() -> String:
	return ModelLibrary.first([furniture, fallback])


## The kind of surface, for loot and for where things go (every plank, or only the top)
func label() -> String:
	if surface != "":
		return surface
	var n := key().get_file()
	for w in ["bookcase", "bookshelf", "shelf", "rack", "niche", "lecturn", "counter", "bar", "altar", "plinth", "sarcophagus", "display", "cart"]:
		if n.contains(w):
			return {"bookshelf": "bookcase", "lecturn": "bookcase", "bar": "table", "counter": "table"}.get(w, w)
	return "table"


func _build_model() -> void:
	if not is_inside_tree():
		return
	for c in get_children(true):
		if c.has_meta("kit_built"):
			remove_child(c)
			c.free()
	var k := key()
	var m := ModelLibrary.instance(k) if k != "" else null
	if m == null:
		return
	m.set_meta("kit_built", true)
	add_child(m, false, Node.INTERNAL_MODE_BACK)
	if Engine.is_editor_hint():
		return
	var before := get_child_count(true)
	ModelLibrary.add_collision(self, m, k + "|kit")
	for i in range(before, get_child_count(true)):
		get_child(i, true).set_meta("kit_built", true)


func _fill() -> void:
	var lbl := label()
	var table := ItemCatalog.tag_loot(KitPlace.tags(self, loot_tags, lbl), KitPlace.level(self) + level_bonus, 1.0)
	if table.is_empty():
		return
	var prefix := KitPlace.save_prefix(self)
	var who := "" if free_to_take else KitPlace.owner_of(self, owner_id)
	var restock := KitPlace.restock_days(self)
	var today := Rumors._day()
	var slots := ModelLibrary.surface_slots(self, self, lbl)
	for i in slots.size():
		var slot_key := "%s/slot_%d" % [prefix, i]
		var rng := RandomNumberGenerator.new()
		rng.seed = slot_key.hash()  # its own: taking one thing never changes what the other spots hold
		var taken := WorldState.get_record(WorldItem.taken_key(slot_key))
		if not taken.is_empty():
			if restock <= 0 or today - int(taken.get("day", today)) < restock:
				continue
			WorldState.erase_record(WorldItem.taken_key(slot_key))  # restocked
		if rng.randf() > fill:
			continue
		var item := RoomDecorator._pick(table, rng)
		if item == null:
			continue
		var w := WorldItem.place(item, 1, self, slots[i][0], slot_key, who)
		if not RoomDecorator.set_on(w, slots[i], slots, rng):  # lying along the plank, never inside the furniture
			remove_child(w)
			w.free()

