class_name Planter
extends StaticBody3D
## A planter box in your home. E with nothing growing: plant a vegetable or herb from your bag
## (potato, carrot, cabbage, leek, wild garlic, lavender, mountain flowers...). It grows for
## GROW_DAYS days (not in winter) and gives back HARVEST of it. Remembered in WorldState.

const GROW_DAYS := 3
const HARVEST := 4
const PLANTS := [
	"res://scripts/Resources/Materials/potato.tres", "res://scripts/Resources/Materials/carrot.tres",
	"res://scripts/Resources/Materials/cabbage.tres", "res://scripts/Resources/Materials/leek.tres",
	"res://scripts/Resources/Ingredients/wild_garlic.tres", "res://scripts/Resources/Ingredients/lavender.tres",
	"res://scripts/Resources/Ingredients/blue_mountain_flower.tres", "res://scripts/Resources/Ingredients/red_mountain_flower.tres",
	"res://scripts/Resources/Ingredients/thistle.tres", "res://scripts/Resources/Ingredients/nightshade.tres",
	"res://scripts/Resources/Ingredients/mandrake_root.tres", "res://scripts/Resources/Ingredients/juniper_berries.tres",
]

var key := ""
var _sprout: MeshInstance3D


static func place(root: Node3D, at: Vector3, p_key: String) -> Planter:
	var p := Planter.new()
	p.key = p_key
	root.add_child(p)
	p.position = at
	return p


func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.5, 0.6)
	shape.shape = box
	shape.position.y = 0.25
	add_child(shape)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.15)
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.22, 0.15, 0.1)
	_mesh(Vector3(1.4, 0.45, 0.6), Vector3(0, 0.225, 0), wood)
	_mesh(Vector3(1.3, 0.05, 0.5), Vector3(0, 0.46, 0), soil)
	_sprout = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.3, 0.35)
	_sprout.mesh = bm
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.3, 0.55, 0.2)
	_sprout.material_override = leaf
	add_child(_sprout)
	_refresh()


func _mesh(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = m
	add_child(mi)


func _clock() -> WorldClock:
	return get_tree().get_first_node_in_group("world_clock") as WorldClock


func _growth() -> float:
	var rec := WorldState.get_record(key)
	if rec.is_empty():
		return -1.0
	var c := _clock()
	if c == null:
		return 0.0
	var days := float(c.day - int(rec.get("day", c.day)))
	if c.get_season() == 0:
		days = minf(days, float(rec.get("grown", 0.0)))  # nothing grows in winter
	return clampf(days / float(GROW_DAYS), 0.0, 1.0)


func _refresh() -> void:
	var g := _growth()
	_sprout.visible = g >= 0.0
	_sprout.scale = Vector3(1.0, maxf(g, 0.1), 1.0)
	_sprout.position = Vector3(0, 0.48 + 0.15 * maxf(g, 0.1), 0)


func get_prompt() -> String:
	var rec := WorldState.get_record(key)
	if rec.is_empty():
		return "Plant something"
	var item := load(String(rec["crop"])) as ItemData
	var g := _growth()
	if g >= 1.0:
		return "Harvest %s" % item.display_name
	return "%s growing (%d%%)%s" % [item.display_name, roundi(g * 100.0), "  (winter: not growing)" if _clock() != null and _clock().get_season() == 0 else ""]


func interact(actor: Inventory) -> void:
	var rec := WorldState.get_record(key)
	if rec.is_empty():
		for path in PLANTS:
			var it := load(path) as ItemData if ResourceLoader.exists(path) else null
			if it != null and actor.has_item(it):
				actor.remove_item(it, 1)
				WorldState.set_record(key, {"crop": path, "day": _clock().day if _clock() != null else 1})
				Locks.toast(get_tree(), "You plant %s" % it.display_name)
				_refresh()
				return
		Locks.toast(get_tree(), "You have nothing to plant (vegetables or herbs)", true)
		return
	if _growth() >= 1.0:
		var item := load(String(rec["crop"])) as ItemData
		actor.add_item(item, HARVEST)
		WorldState.erase_record(key)
		Locks.toast(get_tree(), "You harvest %s x%d" % [item.display_name, HARVEST])
		_refresh()
