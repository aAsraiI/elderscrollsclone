class_name MuseumCase
extends StaticBody3D
## The Antiquarian Society's display case, in every Antiquarian Museum. Donate the artifacts you
## carry: each one is shown in the case for good (in every museum), the Society pays its full
## value, and it counts as a deed (player XP). Every artifact in the collection also gives you
## +2 maximum health, for good ("museum" in Stats). Donations are kept in WorldState.

const INTERACTABLE_LAYER := 4
const PREFIX := "museum/"
const HEALTH_PER_ARTIFACT := 2.0


## Ids of every artifact donated so far
static func donated() -> PackedStringArray:
	var out := PackedStringArray()
	for item in ItemCatalog.all_items():
		if item.artifact and WorldState.has_record(PREFIX + String(item.id)):
			out.append(String(item.id))
	return out


## The collection's bonus on the player (call after loading, and after each donation)
static func apply_bonus(player: Node) -> void:
	var stats := player.get_node_or_null("Stats") as Stats if player != null else null
	if stats == null:
		return
	stats.remove_modifiers("museum")
	var n := donated().size()
	if n > 0:
		stats.add_modifiers("museum", {"max_health": HEALTH_PER_ARTIFACT * n})


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER | 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.5, 0.0)
	add_child(shape)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	base.mesh = bm
	base.position = shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.22, 0.14)
	base.material_override = mat
	add_child(base)
	_show_collection()


# Small models of the donated artifacts along the top of the case
func _show_collection() -> void:
	for c in get_children():
		if c.name.begins_with("Shown"):
			c.queue_free()
	var ids := donated()
	for i in ids.size():
		var item: ItemData = null
		for it in ItemCatalog.all_items():
			if String(it.id) == ids[i]:
				item = it
		if item == null:
			continue
		var m := ItemModels.build_world(item)
		var fit := Node3D.new()
		fit.name = "Shown%d" % i
		fit.add_child(m)
		var b := ItemModels.get_bounds(fit)
		var s := 0.25 / maxf(b.size[b.get_longest_axis_index()], 0.01)
		fit.scale = Vector3.ONE * s
		m.position -= b.get_center()
		fit.position = Vector3(-1.1 + float(i % 8) * 0.31, 1.15, -0.2 + float(i / 8) * 0.25)
		add_child(fit)


func get_prompt() -> String:
	var p := get_tree().get_first_node_in_group("player")
	var n := _carried(p.get_node("Inventory") as Inventory).size() if p != null else 0
	if n == 0:
		return "Museum collection (%d of %d)" % [donated().size(), _total()]
	return "Donate %d artifact%s" % [n, "s" if n > 1 else ""]


func interact(actor: Inventory) -> void:
	if actor == null:
		return
	var p := get_tree().get_first_node_in_group("player")
	var gold := donate(actor, p)
	if gold > 0:
		var hud := p.get_node_or_null("CompassHUD") as CompassHUD
		if hud != null:
			hud.show_banner("Added to the collection", "The Society pays %d gold" % gold)
		_show_collection()


## Donates every artifact in the inventory that the museum does not have yet. Returns the gold paid.
static func donate(inv: Inventory, player: Node) -> int:
	var gold := 0
	for item in _carried(inv):
		inv.remove_item(item, 1)
		WorldState.set_record(PREFIX + String(item.id), {"donated": true})
		gold += item.value
		var skills := player.get_node_or_null("Skills") as Skills if player != null else null
		if skills != null:
			skills.add_deed_xp(SkillDatabase.deed_xp(item.min_level, 1.0))
	if gold > 0:
		Currency.add_gold(inv, gold)
		apply_bonus(player)
	return gold


static func _carried(inv: Inventory) -> Array[ItemData]:
	var out: Array[ItemData] = []
	if inv == null:
		return out
	for st in inv.stacks:
		var it: ItemData = st.item
		if it.artifact and not WorldState.has_record(PREFIX + String(it.id)) and not out.has(it):
			out.append(it)
	return out


static func _total() -> int:
	return ItemCatalog.all_items().filter(func(i: ItemData) -> bool: return i.artifact).size()
