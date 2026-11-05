class_name WorldSites
extends Node
## Alpha 1.31.2: places laid over the world from its seed, without touching the towns, roads and
## dungeons (so old saves keep their world). Under WorldManager. Built when you come near:
##   landmark    a giant statue, a fallen tower, a half-sunk temple, the skeleton of a titan: big
##               enough to see from far off, each with something left at its foot
##   underwater  drowned ruins and sea caves on the sea floor. Swim (Air Bladders, Water Breathing)
##   puzzle      an old place shut with a puzzle (PuzzleSite): levers, turning pillars, mirrors
##   ruined city on the far islands: clear the dead out and settle it again (RuinedCity)
## Found ones go on your map and in the journal. Saved in WorldState "site/<id>" {"found"}.

const SPACING := 700.0
const COUNTS := {"landmark": 14, "underwater": 8, "puzzle": 9, "city": 3}
const LOAD := {"landmark": 1300.0, "underwater": 160.0, "puzzle": 180.0, "city": 320.0}
const FOUND_RANGE := {"landmark": 60.0, "underwater": 25.0, "puzzle": 25.0, "city": 60.0}
const LANDMARKS := ["statue", "fallen_tower", "sunken_temple", "titan"]
const LANDMARK_NAMES := {"statue": "The Giant Statue", "fallen_tower": "The Fallen Tower", "sunken_temple": "The Sunken Temple", "titan": "The Titan's Bones"}
const STONE := Color(0.42, 0.41, 0.38)
const BONE := Color(0.72, 0.68, 0.58)

var world: WorldManager
var sites: Array = []  # {"id", "kind", "form", "name", "pos": Vector3, "yaw"}
var _nodes := {}
var _t := 0.0
var _planned := false


func _ready() -> void:
	add_to_group("world_sites")
	world = get_parent() as WorldManager


static func of(tree: SceneTree) -> WorldSites:
	return tree.get_first_node_in_group("world_sites") as WorldSites


# ---------------------------------------------------------------- planning

## Works out every site from the world's seed. Always the same for the same world.
func plan() -> void:
	_planned = true
	sites = []
	if world == null or world.map == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.world_seed) ^ 0x51735
	var b := world.map.get_bounds()
	var taken: Array[Vector2] = []
	for kind in ["city", "landmark", "puzzle", "underwater"]:
		var want: int = COUNTS[kind]
		var got := 0
		var tries := 0
		while got < want and tries < 500:
			tries += 1
			var x := rng.randf_range(b.position.x, b.end.x)
			var z := rng.randf_range(b.position.y, b.end.y)
			if not _fits(kind, x, z, taken):
				continue
			taken.append(Vector2(x, z))
			var form := ""
			var site_name := ""
			match kind:
				"landmark":
					form = LANDMARKS[got % LANDMARKS.size()]
					site_name = LANDMARK_NAMES[form]
				"underwater":
					form = "ruin" if got % 2 == 0 else "cave"
					site_name = "A Drowned Ruin" if form == "ruin" else "A Sea Cave"
				"puzzle":
					form = PuzzleSite.FORMS[got % PuzzleSite.FORMS.size()]
					site_name = PuzzleSite.NAMES[form]
				"city":
					form = "city"
					site_name = RuinedCity.NAMES[got % RuinedCity.NAMES.size()]
			sites.append({"id": "%s_%d" % [kind, got], "kind": kind, "form": form, "name": site_name,
				"pos": Vector3(x, world.get_height_at(x, z), z), "yaw": rng.randf() * TAU})
			got += 1


func _fits(kind: String, x: float, z: float, taken: Array[Vector2]) -> bool:
	for t in taken:
		if t.distance_to(Vector2(x, z)) < SPACING:
			return false
	var h := world.get_height_at(x, z)
	var water := world.map.get_water_level(x, z)
	if kind == "underwater":
		return world.map.is_sea(x, z) and h < water - 5.0 and h > water - 40.0
	if h < water + 1.5:
		return false
	var band := world.map.get_level_band(x, z)
	if kind == "city" and band.x < 100.0:
		return false
	var at := Vector3(x, h, z)
	var t := world.get_nearest_town(at)
	if t != null and t.position.distance_to(at) < t.poi.footprint_radius + (160.0 if kind == "city" else 90.0):
		return false
	return world.get_pois_near(at, 90.0).is_empty()


# ---------------------------------------------------------------- near and far

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or get_tree().paused:
		return
	_t = 2.0
	if not _planned:
		plan()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or (world.dungeons != null and world.dungeons.is_inside()):
		return
	for s: Dictionary in sites:
		var d: float = (s["pos"] as Vector3).distance_to(player.global_position)
		var reach: float = LOAD[s["kind"]]
		var id: String = s["id"]
		if d < reach and not _nodes.has(id):
			_nodes[id] = build(s)
		elif d > reach + 120.0 and _nodes.has(id):
			if is_instance_valid(_nodes[id]):
				_nodes[id].queue_free()
			_nodes.erase(id)
		if d < float(FOUND_RANGE[s["kind"]]) and not is_found(id):
			mark_found(s)


static func is_found(id: String) -> bool:
	return WorldState.has_record("site/" + id)


func mark_found(s: Dictionary) -> void:
	WorldState.set_record("site/" + String(s["id"]), {"found": true})
	var p: Vector3 = s["pos"]
	MapMarkers.add(Vector2(p.x, p.z), String(s["name"]))
	Locks.toast(get_tree(), "You have found %s." % s["name"])
	DialogueState.system_entry("Place", "I found %s." % s["name"], "")
	Achievements.note("site_" + String(s["kind"]))


func build(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Site_" + String(s["id"])
	add_child(root)
	root.global_position = s["pos"]
	root.rotation.y = float(s["yaw"])
	match String(s["kind"]):
		"landmark":
			_landmark(root, String(s["form"]))
			_treasure(root, s, Vector3(6.0, 0.4, 3.0))
		"underwater":
			_underwater(root, String(s["form"]))
			_treasure(root, s, Vector3(0.0, 0.5, 0.0))
		"puzzle":
			PuzzleSite.make(root, s)
		"city":
			RuinedCity.make(root, s, world)
	return root


func _treasure(root: Node3D, s: Dictionary, at: Vector3) -> void:
	var level := LevelCurve.place_level(world.map, s["pos"])
	var chest := POIBuilder.make_chest("Old Chest", ItemCatalog.enemy_loot(level, 1.5), "site/%s/chest" % s["id"], absi(String(s["id"]).hash()))
	root.add_child(chest)
	chest.position = at


# ---------------------------------------------------------------- what they look like

func _landmark(root: Node3D, form: String) -> void:
	var box := POIBuilder.add_box
	match form:
		"statue":
			box.call(root, Vector3(8, 3, 8), Vector3(0, 1.5, 0), STONE.darkened(0.2))
			box.call(root, Vector3(4, 12, 3), Vector3(0, 9, 0), STONE)  # the robe
			box.call(root, Vector3(6, 5, 3), Vector3(0, 17.5, 0), STONE)  # the chest
			box.call(root, Vector3(2.4, 2.8, 2.4), Vector3(0, 21.5, 0), STONE.lightened(0.05))  # the head
			box.call(root, Vector3(1.4, 8, 1.4), Vector3(4, 17, 2), STONE, 0.0, Vector3(-0.5, 0, 0))  # an arm held out
			box.call(root, Vector3(1.4, 8, 1.4), Vector3(-3.8, 12, 0), STONE)
		"fallen_tower":
			for i in 5:
				box.call(root, Vector3(7, 7, 7), Vector3(0, 3.0 + 0.4 * i, -2.0 - i * 7.5), STONE, 0.0, Vector3(0.0, 0.0, 0.04 * i))
			box.call(root, Vector3(9, 8, 9), Vector3(0, 4, 3), STONE.darkened(0.1))
			box.call(root, Vector3(7, 10, 7), Vector3(0, 12, 3), STONE)
		"sunken_temple":
			box.call(root, Vector3(26, 2, 18), Vector3(0, -0.2, 0), STONE.darkened(0.15), 0.0, Vector3(0.05, 0, 0.03))
			for x in [-10.0, -5.0, 0.0, 5.0, 10.0]:
				for z in [-7.0, 7.0]:
					var tall := 9.0 - absf(x) * 0.25
					box.call(root, Vector3(1.6, tall, 1.6), Vector3(x, tall * 0.5, z), STONE.lightened(0.05), 0.0, Vector3(0.03, 0, 0.04))
			box.call(root, Vector3(24, 1.4, 16), Vector3(0, 9.2, 0), STONE, 0.0, Vector3(0.09, 0, -0.05))
		"titan":
			for i in 11:  # the ribs, arching out of the ground
				var z := -18.0 + i * 3.6
				for side in [-1.0, 1.0]:
					box.call(root, Vector3(0.9, 9.0, 0.9), Vector3(side * 4.0, 4.0, z), BONE, 0.0, Vector3(0.0, 0.0, -side * 0.35))
			box.call(root, Vector3(1.6, 1.6, 40.0), Vector3(0, 0.8, 0), BONE)  # the spine
			box.call(root, Vector3(7, 5, 9), Vector3(0, 2.5, 25), BONE)  # the skull
			box.call(root, Vector3(2, 2, 2), Vector3(-2, 3.2, 29.5), Color(0.08, 0.07, 0.06))
			box.call(root, Vector3(2, 2, 2), Vector3(2, 3.2, 29.5), Color(0.08, 0.07, 0.06))


func _underwater(root: Node3D, form: String) -> void:
	var box := POIBuilder.add_box
	var weed := Color(0.25, 0.32, 0.26)
	if form == "ruin":
		box.call(root, Vector3(14, 0.8, 14), Vector3(0, 0.1, 0), weed)
		for c in [Vector3(-6, 0, -6), Vector3(6, 0, -6), Vector3(-6, 0, 6), Vector3(6, 0, 6)]:
			box.call(root, Vector3(1.2, 5.0, 1.2), c + Vector3(0, 2.5, 0), weed.lightened(0.1), 0.0, Vector3(0.04, 0, 0.05))
		box.call(root, Vector3(14, 3.0, 0.8), Vector3(0, 1.5, -7), weed.lightened(0.05))
	else:
		# a cave: a hollow of rock on the sea floor, open on one side
		var rock := Color(0.2, 0.21, 0.22)
		box.call(root, Vector3(12, 1, 12), Vector3(0, 6, 0), rock)
		box.call(root, Vector3(1, 6, 12), Vector3(-6, 3, 0), rock)
		box.call(root, Vector3(1, 6, 12), Vector3(6, 3, 0), rock)
		box.call(root, Vector3(12, 6, 1), Vector3(0, 3, -6), rock)
