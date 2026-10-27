@tool
class_name KitLootShelf
extends StaticBody3D
## The builder kit: a shelf, bookcase, table, counter or altar (its Morrowind model) that fills its own
## planks and top with loot when the game runs: things that fit, from the loot tags, at the player's
## level. The surfaces are read from the model itself, so it works for any piece and wherever it stands.

@export var furniture := "prop/shelf":
	set(v):
		furniture = v
		_build_model()
@export var loot_tags: PackedStringArray = ["library"]
## How many of its spots get something (0..1)
@export_range(0.0, 1.0) var fill := 0.6
## Who it belongs to ("" = free to take)
@export var owner_id := ""


func _ready() -> void:
	_build_model()
	if not Engine.is_editor_hint():
		_fill.call_deferred()


func _build_model() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("kit_built"):
			remove_child(c)
			c.free()
	var m := ModelLibrary.instance(furniture)
	if m == null:
		return
	m.set_meta("kit_built", true)
	add_child(m)
	var before := get_child_count()
	ModelLibrary.add_collision(self, m, furniture + "|kit")
	for i in range(before, get_child_count()):
		get_child(i).set_meta("kit_built", true)


func _fill() -> void:
	var p := get_tree().get_first_node_in_group("player")
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	var table := ItemCatalog.tag_loot(loot_tags, skills.get_player_level() if skills != null else 5, 1.0)
	if table.is_empty():
		return
	var prefix := "kit/%s/%s" % [owner.scene_file_path.get_file().get_basename() if owner != null else "world", name]
	var rng := RandomNumberGenerator.new()
	rng.seed = prefix.hash()
	var slots := ModelLibrary.surface_slots(self, self, furniture.get_file())  # a table only on its top, shelving on every plank
	for i in slots.size():
		var key := "%s/slot_%d" % [prefix, i]
		if rng.randf() > fill or not WorldState.get_record(WorldItem.taken_key(key)).is_empty():
			continue
		var item := RoomDecorator._pick(table, rng)
		if item == null:
			continue
		var w := WorldItem.place(item, 1, self, slots[i][0], key, owner_id)
		var room: Vector2 = slots[i][1]
		if maxf(w.size.x, w.size.z) > maxf(room.x, room.y) * 1.6 + 0.2:
			remove_child(w)
			w.free()  # too big for that spot
			continue
		w.rotation.y = rng.randf() * TAU
