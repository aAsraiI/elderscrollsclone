class_name HarvestNode
extends StaticBody3D
## Something out in the wild you can gather: a herb (press E to pick it) or an ore vein (needs a
## pickaxe in your bag). Made by GroundCover on terrain chunks. What it gives depends on the land
## (the climate for herbs, the area's level for ore). Picked ones grow back after a few days
## (WorldState "harvest/<x>_<z>" remembers the day).

const INTERACTABLE_LAYER := 4
const HERB_REGROW_DAYS := 3
const ORE_REGROW_DAYS := 7
const ING := "res://data/ingredients/"
const MAT := "res://data/materials/"
const HERBS := {
	"temperate": ["lavender", "thistle", "blue_mountain_flower", "red_mountain_flower", "nightshade", "glowcap", "wild_garlic", "mandrake_root"],
	"wet": ["swamp_lily", "bloodmoss", "glowcap", "nightshade", "red_mountain_flower", "mandrake_root"],
	"cold": ["snowberries", "frost_mirriam", "juniper_berries", "blue_mountain_flower"],
	"arid": ["sandroot", "cactus_flower", "thistle"],
}
const HERB_COLORS := {
	"lavender": Color(0.6, 0.45, 0.9), "thistle": Color(0.75, 0.35, 0.75), "blue_mountain_flower": Color(0.35, 0.5, 1.0),
	"red_mountain_flower": Color(0.95, 0.2, 0.2), "nightshade": Color(0.35, 0.15, 0.45), "glowcap": Color(0.4, 0.9, 1.0),
	"swamp_lily": Color(0.95, 0.95, 0.85), "bloodmoss": Color(0.6, 0.1, 0.1), "snowberries": Color(0.95, 0.95, 1.0),
	"frost_mirriam": Color(0.6, 0.85, 0.75), "juniper_berries": Color(0.2, 0.3, 0.6), "sandroot": Color(0.8, 0.6, 0.3),
	"cactus_flower": Color(1.0, 0.45, 0.6), "wild_garlic": Color(0.92, 0.92, 0.82), "mandrake_root": Color(0.6, 0.45, 0.3),
}
## Ore by the area's level: [min level, ore id, weight]
const ORES := [[1, "iron_ore", 10.0], [6, "corundum_ore", 5.0], [12, "silver_ore", 4.0], [18, "gold_ore", 2.0],
	[26, "obsidian_ore", 3.0], [38, "ebony_ore", 2.5], [55, "dragonstone_ore", 1.5], [70, "star_ore", 1.0]]

var kind := "herb"
var item_id := ""
var key := ""
var _visual: Node3D


static func make_herb(chunk: Node3D, local: Vector3, world_pos: Vector3, climate: String, pick: int) -> HarvestNode:
	var list: Array = HERBS.get(climate, HERBS["temperate"])
	var n := HarvestNode.new()
	n.kind = "herb"
	n.item_id = list[pick % list.size()]
	n.key = "harvest/%d_%d" % [roundi(world_pos.x), roundi(world_pos.z)]
	n.position = local
	chunk.add_child(n)
	return n


static func make_ore(chunk: Node3D, local: Vector3, world_pos: Vector3, pick: int) -> HarvestNode:
	var n := HarvestNode.new()
	n.kind = "ore"
	n.key = "harvest/%d_%d" % [roundi(world_pos.x), roundi(world_pos.z)]
	n.position = local
	n.set_meta("pick", pick)
	chunk.add_child(n)
	return n


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.45 if kind == "herb" else 0.9
	shape.shape = s
	shape.position = Vector3(0, s.radius * 0.8, 0)
	add_child(shape)
	if kind == "ore":
		item_id = _pick_ore()
	_build_visual()
	_refresh()


func _pick_ore() -> String:
	var level := 5
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null and world.map != null:
		level = LevelCurve.place_level(world.map, global_position)
	var total := 0.0
	var options: Array = []
	for o in ORES:
		if level >= int(o[0]):
			options.append(o)
			total += float(o[2])
	var roll := float(int(get_meta("pick", 0)) % 10000) / 10000.0 * total
	for o in options:
		roll -= float(o[2])
		if roll <= 0.0:
			return String(o[1])
	return "iron_ore"


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	if kind == "herb":
		var col: Color = HERB_COLORS.get(item_id, Color(0.8, 0.8, 0.3))
		var leaf := StandardMaterial3D.new()
		leaf.albedo_color = Color(0.25, 0.45, 0.18)
		var bloom := StandardMaterial3D.new()
		bloom.albedo_color = col
		bloom.emission_enabled = item_id == "glowcap"
		bloom.emission = col
		for i in 5:
			var a := float(i) / 5.0 * TAU
			var stem := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.03, 0.35, 0.03)
			stem.mesh = bm
			stem.material_override = leaf
			stem.position = Vector3(cos(a) * 0.12, 0.17, sin(a) * 0.12)
			stem.rotation = Vector3(sin(a) * 0.3, 0, cos(a) * 0.3)
			_visual.add_child(stem)
			var head := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.06
			hm.height = 0.1
			hm.radial_segments = 6
			hm.rings = 3
			head.mesh = hm
			head.material_override = bloom
			head.position = Vector3(cos(a) * 0.16, 0.36, sin(a) * 0.16)
			_visual.add_child(head)
	else:
		var rock := MeshInstance3D.new()
		rock.mesh = NatureMeshes.rock_mesh(1)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.35, 0.33, 0.32)
		rock.material_override = rm
		rock.scale = Vector3(1.6, 1.1, 1.4)
		rock.position.y = 0.3
		_visual.add_child(rock)
		var vein := StandardMaterial3D.new()
		vein.albedo_color = ORE_COLORS.get(item_id, Color(0.7, 0.5, 0.4))
		vein.metallic = 0.7
		vein.roughness = 0.3
		vein.emission_enabled = item_id == "star_ore" or item_id == "dragonstone_ore"
		vein.emission = vein.albedo_color * 0.5
		var rng := RandomNumberGenerator.new()
		rng.seed = key.hash()
		for i in 6:
			var nug := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.18, 0.12, 0.18) * rng.randf_range(0.7, 1.4)
			nug.mesh = bm
			nug.material_override = vein
			var a := rng.randf() * TAU
			nug.position = Vector3(cos(a) * 0.6, rng.randf_range(0.3, 0.8), sin(a) * 0.55)
			nug.rotation = Vector3(rng.randf(), rng.randf(), rng.randf())
			_visual.add_child(nug)


const ORE_COLORS := {"iron_ore": Color(0.55, 0.35, 0.28), "corundum_ore": Color(0.75, 0.5, 0.3), "silver_ore": Color(0.85, 0.87, 0.9),
	"gold_ore": Color(1.0, 0.8, 0.3), "obsidian_ore": Color(0.12, 0.08, 0.15), "ebony_ore": Color(0.08, 0.08, 0.1),
	"dragonstone_ore": Color(0.7, 0.2, 0.15), "star_ore": Color(0.55, 0.65, 1.0)}


func _today() -> int:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	return clock.day if clock != null else 1


func is_ready() -> bool:
	var rec := WorldState.get_record(key)
	if rec.is_empty():
		return true
	var wait := HERB_REGROW_DAYS if kind == "herb" else ORE_REGROW_DAYS
	return _today() - int(rec.get("day", -999)) >= wait


func _refresh() -> void:
	var is_grown := is_ready()
	if _visual != null:
		_visual.visible = is_grown or kind == "ore"
		if kind == "ore":
			for c in _visual.get_children().slice(1):
				(c as Node3D).visible = is_grown
	collision_layer = INTERACTABLE_LAYER if is_grown else 0


func _item() -> ItemData:
	var path := (ING if kind == "herb" else MAT) + item_id + ".tres"
	return load(path) as ItemData if ResourceLoader.exists(path) else null


func get_prompt() -> String:
	var item := _item()
	if item == null:
		return ""
	if kind == "herb":
		return "Pick %s" % item.display_name
	return "Mine %s" % item.display_name.trim_suffix(" Ore") + " Vein" + ("" if _has_pickaxe() else "  (needs a pickaxe)")


func _has_pickaxe() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	var inv := player.get_node_or_null("Inventory") as Inventory if player != null else null
	var pick := load(MAT + "pickaxe.tres") as ItemData if ResourceLoader.exists(MAT + "pickaxe.tres") else null
	return inv != null and pick != null and inv.has_item(pick)


func interact(actor: Inventory) -> void:
	if actor == null or not is_ready():
		return
	var item := _item()
	if item == null:
		return
	var count := 1
	if kind == "ore":
		if not _has_pickaxe():
			Locks.toast(get_tree(), "You need a pickaxe to mine this", true)
			return
		count = 2 + int(get_meta("pick", 0)) % 2
		var skills := actor.get_parent().get_node_or_null("Skills") as Skills
		if skills != null:
			skills.add_xp(&"smithing", 4.0)
	else:
		count = 1 + (1 if randf() < 0.3 else 0)
	actor.add_item(item, count)
	WorldState.set_record(key, {"day": _today()})
	Locks.toast(get_tree(), "%s x%d" % [item.display_name, count])
	_refresh()
