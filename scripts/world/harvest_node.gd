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


## Herbs added in Alpha 1.21: colour of the plain look, the models that show them (the first that
## exists; Morrowind's plants need Settings > Models > Import building pieces) and whether they
## grow at the water's edge
const HERB_INFO := {
	"heather": [Color(0.62, 0.38, 0.6), ["kit/plants/other/flora_heather_01"], false],
	"bog_bean": [Color(0.8, 0.75, 0.55), ["kit/plants/bitter_coast/flora_bc_podplant_01", "kit/plants/bitter_coast/flora_bc_podplant_02"], true],
	"shelf_fungus": [Color(0.72, 0.55, 0.32), ["kit/plants/mushrooms/flora_bc_mushroom_06", "kit/plants/mushrooms/flora_bc_mushroom_07"], false],  # (Morrowind's shelf fungus grows sideways off trunks)
	"spore_pod": [Color(0.55, 0.6, 0.3), ["kit/plants/other/flora_muckpod_01", "kit/plants/other/flora_t_podbud_01"], false],
	"cattail_root": [Color(0.42, 0.28, 0.16), [], true],
	"cloudberries": [Color(0.95, 0.62, 0.25), ["kit/plants/solstheim/flora_bm_shrub_02"], false],
	"wolfsbane": [Color(0.45, 0.35, 0.8), [], false],
	"belladonna": [Color(0.25, 0.12, 0.3), [], false],
	"aloe_leaf": [Color(0.45, 0.62, 0.42), [], false],
	"sagebrush": [Color(0.62, 0.66, 0.55), ["kit/plants/other/flora_roobrush_01"], false],
	"ash_root": [Color(0.5, 0.32, 0.25), ["kit/plants/other/flora_ash_grass_r_01"], false],
	"ember_fern": [Color(0.85, 0.35, 0.15), ["kit/plants/other/flora_trama_shrub_02", "kit/plants/other/flora_trama_shrub_05"], false],
	"thornroot": [Color(0.4, 0.3, 0.2), ["kit/plants/other/flora_rm_scathecraw_01", "kit/plants/other/flora_rm_scathecraw_02"], false],
	"sea_kelp": [Color(0.3, 0.4, 0.2), ["kit/plants/grass/flora_kelp_01", "kit/plants/grass/flora_kelp_02"], true],
	"saltgrass": [Color(0.7, 0.72, 0.5), ["kit/plants/bitter_coast/flora_bc_grass_01"], false],
	"red_poppy": [Color(0.9, 0.15, 0.12), [], false],
	"yarrow": [Color(0.95, 0.93, 0.85), [], false],
	"cornflower": [Color(0.3, 0.45, 0.95), [], false],
	"fly_agaric": [Color(0.85, 0.15, 0.1), ["kit/plants/mushrooms/flora_bc_mushroom_01", "kit/plants/mushrooms/flora_bc_mushroom_03"], false],
	"fiddlehead": [Color(0.4, 0.6, 0.25), ["kit/plants/bitter_coast/flora_bc_fern_01", "kit/plants/bitter_coast/flora_bc_fern_03"], false],
	"bramble_berries": [Color(0.3, 0.1, 0.3), ["kit/plants/other/flora_comberry_01"], false],
	"water_mint": [Color(0.5, 0.75, 0.55), [], true],
	"grave_moss": [Color(0.32, 0.36, 0.25), ["kit/plants/bitter_coast/flora_bc_moss_03", "kit/plants/bitter_coast/flora_bc_moss_07"], false],
	"ice_lichen": [Color(0.7, 0.85, 0.9), [], false],
	"strangleweed": [Color(0.35, 0.45, 0.2), ["kit/plants/other/flora_chokeweed_01"], false],
	"bulbroot": [Color(0.75, 0.6, 0.4), ["kit/plants/other/flora_corkbulb_01"], false],
	"mire_sponge": [Color(0.6, 0.5, 0.3), ["kit/plants/other/flora_muckspunge_01", "kit/plants/other/flora_muckspunge_03"], true],
	"sand_lily": [Color(0.98, 0.85, 0.75), [], false],
}
## Older herbs that grow by the water too
const WATER_HERBS := ["swamp_lily"]


## A herb for this spot of a biome: by the biome's Herbs list (weights after ':'), only water herbs
## at a wet spot and only dry-land herbs at a dry one; else one for the land's climate
static func pick_herb(biome: BiomeData, pick: int, wet: bool) -> String:
	var ids: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for entry in biome.herbs:
		var parts := entry.split(":")
		var id := parts[0].strip_edges()
		if id == "" or is_water_herb(id) != wet:
			continue
		var w := float(parts[1]) if parts.size() > 1 else 1.0
		ids.append(id)
		weights.append(w)
		total += w
	if ids.is_empty():
		if wet or not biome.herbs.is_empty():
			return ""  # no water herbs here (or the list has no dry-land ones)
		var list: Array = HERBS.get(biome.get_climate(), HERBS["temperate"])
		return list[pick % list.size()]
	var roll := float(pick % 10000) / 10000.0 * total
	for i in ids.size():
		roll -= weights[i]
		if roll <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


static func is_water_herb(id: String) -> bool:
	if HERB_INFO.has(id):
		return bool(HERB_INFO[id][2])
	return WATER_HERBS.has(id)


static func make_herb(chunk: Node3D, local: Vector3, world_pos: Vector3, climate: String, pick: int) -> HarvestNode:
	var list: Array = HERBS.get(climate, HERBS["temperate"])
	return make_herb_id(chunk, local, world_pos, list[pick % list.size()], pick)


static func make_herb_id(chunk: Node3D, local: Vector3, world_pos: Vector3, id: String, _pick: int) -> HarvestNode:
	var n := HarvestNode.new()
	n.kind = "herb"
	n.item_id = id
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


## How far away herbs and ore stop being drawn (they are small; past this they are a few pixels)
const DRAW_DISTANCE := 80.0

# Shared by every herb and ore node: one mesh per herb kind and one material per color
static var _herb_meshes := {}  # item_id -> ArrayMesh (surface 0 stems, surface 1 blooms)
static var _materials := {}    # "color|glow|metal" -> StandardMaterial3D


static func _material(color: Color, glow: bool = false, metal: bool = false) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [color.to_html(), glow, metal]
	if not _materials.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = glow
		m.emission = color * (0.5 if metal else 1.0)
		if metal:
			m.metallic = 0.7
			m.roughness = 0.3
		_materials[k] = m
	return _materials[k]


# Five stems with a bloom on each, as one mesh with two surfaces
static func _herb_mesh(id: String) -> ArrayMesh:
	if _herb_meshes.has(id):
		return _herb_meshes[id]
	var stem := BoxMesh.new()
	stem.size = Vector3(0.03, 0.35, 0.03)
	var bloom := SphereMesh.new()
	bloom.radius = 0.06
	bloom.height = 0.1
	bloom.radial_segments = 6
	bloom.rings = 3
	var stems := SurfaceTool.new()
	var blooms := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	blooms.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var a := float(i) / 5.0 * TAU
		stems.append_from(stem, 0, Transform3D(Basis.from_euler(Vector3(sin(a) * 0.3, 0, cos(a) * 0.3)), Vector3(cos(a) * 0.12, 0.17, sin(a) * 0.12)))
		blooms.append_from(bloom, 0, Transform3D(Basis.IDENTITY, Vector3(cos(a) * 0.16, 0.36, sin(a) * 0.16)))
	var mesh := stems.commit()
	blooms.commit(mesh)
	var col: Color = HERB_COLORS.get(id, HERB_INFO[id][0] if HERB_INFO.has(id) else Color(0.8, 0.8, 0.3))
	mesh.surface_set_material(0, _material(Color(0.25, 0.45, 0.18)))
	mesh.surface_set_material(1, _material(col, id == "glowcap"))
	_herb_meshes[id] = mesh
	return mesh


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	if kind == "herb":
		var model := ModelLibrary.first(HERB_INFO[item_id][1]) if HERB_INFO.has(item_id) else ""
		var mesh: Mesh = ModelLibrary.merged_mesh(model, 0.0, 0.03) if model != "" else null
		if mesh != null:
			_add_part(mesh, null, Transform3D(Basis(Vector3.UP, float(key.hash() % 628) / 100.0), Vector3.ZERO))
		else:
			_add_part(_herb_mesh(item_id), null, Transform3D.IDENTITY)
	else:
		# Child 0 is the rock, child 1 the ore veins (hidden while the node is mined out)
		_add_part(NatureMeshes.rock_mesh(1), _material(Color(0.35, 0.33, 0.32)),
			Transform3D(Basis.from_scale(Vector3(1.6, 1.1, 1.4)), Vector3(0.0, 0.3, 0.0)))
		var rng := RandomNumberGenerator.new()
		rng.seed = key.hash()
		var veins := SurfaceTool.new()
		veins.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 6:
			var nug := BoxMesh.new()
			nug.size = Vector3(0.18, 0.12, 0.18) * rng.randf_range(0.7, 1.4)
			var a := rng.randf() * TAU
			var at := Vector3(cos(a) * 0.6, rng.randf_range(0.3, 0.8), sin(a) * 0.55)
			veins.append_from(nug, 0, Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf())), at))
		var glow := item_id == "star_ore" or item_id == "dragonstone_ore"
		_add_part(veins.commit(), _material(ORE_COLORS.get(item_id, Color(0.7, 0.5, 0.4)), glow, true), Transform3D.IDENTITY)


func _add_part(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.visibility_range_end = DRAW_DISTANCE
	_visual.add_child(mi)


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
