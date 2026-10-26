extends SceneTree
## Makes the interior scenes of Alpha 1.13: the shared materials, the prop library
## (scenes/interiors/props/), the room modules of every theme (scenes/interiors/modules/<theme>/)
## and a template per role (scenes/interiors/modules/templates/). A scene that already exists is
## never overwritten (your hand edits are safe); pass --force to rebuild everything.
##   godot --headless --path . -s res://tools/build_interiors.gd [-- --force]

const MOD_DIR := "res://scenes/interiors/modules/"
const PROP_DIR := "res://scenes/interiors/props/"
const S := SpawnSocket.Kind

var force := false
var made := 0
var kept := 0


func _initialize() -> void:
	force = OS.get_cmdline_user_args().has("--force")
	InteriorKit.save_materials()
	_props()
	_modules()
	print("build_interiors: %d scenes made, %d kept as they were" % [made, kept])
	quit()


func _save(root: Node, path: String) -> void:
	if ResourceLoader.exists(path) and not force:
		kept += 1
		root.free()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("build_interiors: can't pack %s (%d)" % [path, err])
	ResourceSaver.save(ps, path)
	made += 1
	root.free()


# ---------------------------------------------------------------- props

# A prop: parts are [shape, size, position, material, yaw]; shape "box" or "cyl"
func _prop(file: String, tags: Array, kinds: Array, snap: int, parts: Array, opts: Dictionary = {}) -> void:
	var root := InteriorProp.new()
	root.name = file.to_pascal_case()
	root.tags = PackedStringArray(tags)
	root.socket_kinds = PackedStringArray(kinds)
	root.snap = snap as InteriorProp.Snap
	root.themes = PackedStringArray(opts.get("themes", []))
	root.wealth_min = int(opts.get("wealth_min", 0))
	root.wealth_max = int(opts.get("wealth_max", 2))
	root.weight = float(opts.get("weight", 1.0))
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var i := 0
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		mi.name = "Part%d" % i
		i += 1
		var size: Vector3 = p[1]
		if p[0] == "cyl":
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.z * 0.5
			cm.height = size.y
			cm.radial_segments = 10
			mi.mesh = cm
		else:
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
		mi.material_override = InteriorKit.material(String(p[3]))
		root.add_child(mi)
		mi.owner = root
		mi.position = p[2]
		if p.size() > 4:
			mi.rotation.y = float(p[4])
		var half := Vector3(maxf(size.x, size.z), size.y, maxf(size.x, size.z)) * 0.5
		lo = lo.min(Vector3(p[2]) - half)
		hi = hi.max(Vector3(p[2]) + half)
	root.radius = maxf(maxf(hi.x - lo.x, hi.z - lo.z) * 0.5, 0.2)
	if not bool(opts.get("ghost", false)):
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var bs := BoxShape3D.new()
		bs.size = (hi - lo).max(Vector3(0.1, 0.1, 0.1))
		shape.shape = bs
		root.add_child(shape)
		shape.owner = root
		shape.position = (hi + lo) * 0.5
	else:
		root.collision_layer = 0
	if opts.has("light"):
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = opts["light"]
		l.light_energy = float(opts.get("energy", 1.2))
		l.omni_range = float(opts.get("range", 6.0))
		l.shadow_enabled = false
		root.add_child(l)
		l.owner = root
		l.position = opts.get("light_at", Vector3(0, 1.0, 0))
	_save(root, PROP_DIR + file + ".tscn")


func _props() -> void:
	var F := InteriorProp.Snap.FLOOR
	var W := InteriorProp.Snap.WALL
	var C := InteriorProp.Snap.CEILING
	var warm := Color(1.0, 0.68, 0.38)
	var legs := func(w: float, d: float, h: float, mat: String) -> Array:
		var out: Array = []
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				out.append(["box", Vector3(0.08, h, 0.08), Vector3(sx * (w * 0.5 - 0.06), h * 0.5, sz * (d * 0.5 - 0.06)), mat])
		return out
	_prop("table", ["table"], ["FURNITURE"], F, [["box", Vector3(1.6, 0.08, 0.9), Vector3(0, 0.76, 0), "wood"]] + legs.call(1.6, 0.9, 0.72, "wood_dark"))
	_prop("table_meal", ["table", "meal"], ["FURNITURE"], F, [["box", Vector3(1.6, 0.08, 0.9), Vector3(0, 0.76, 0), "wood"], ["cyl", Vector3(0.25, 0.04, 0.25), Vector3(-0.4, 0.82, 0.1), "iron"],
		["cyl", Vector3(0.25, 0.04, 0.25), Vector3(0.4, 0.82, -0.1), "iron"], ["cyl", Vector3(0.1, 0.16, 0.1), Vector3(0.1, 0.88, 0.25), "wood_dark"], ["box", Vector3(0.3, 0.12, 0.2), Vector3(-0.1, 0.86, -0.2), "straw"]] + legs.call(1.6, 0.9, 0.72, "wood_dark"))
	_prop("map_table", ["table", "map"], ["FURNITURE"], F, [["box", Vector3(2.0, 0.1, 1.2), Vector3(0, 0.86, 0), "wood_dark"], ["box", Vector3(1.6, 0.01, 0.9), Vector3(0, 0.92, 0), "paper"],
		["box", Vector3(1.8, 0.8, 1.0), Vector3(0, 0.4, 0), "wood_dark"]], {"themes": ["fort", "house", "rich"]})
	_prop("chair", ["chair", "seat"], ["FURNITURE"], F, [["box", Vector3(0.45, 0.06, 0.45), Vector3(0, 0.45, 0), "wood"], ["box", Vector3(0.45, 0.5, 0.06), Vector3(0, 0.73, 0.2), "wood"]] + legs.call(0.45, 0.45, 0.42, "wood_dark"))
	_prop("bench", ["bench", "seat"], ["FURNITURE"], F, [["box", Vector3(1.5, 0.08, 0.35), Vector3(0, 0.42, 0), "wood"], ["box", Vector3(0.08, 0.4, 0.3), Vector3(-0.6, 0.2, 0), "wood_dark"], ["box", Vector3(0.08, 0.4, 0.3), Vector3(0.6, 0.2, 0), "wood_dark"]])
	_prop("stool", ["stool", "seat"], ["FURNITURE", "DECORATION"], F, [["cyl", Vector3(0.38, 0.05, 0.38), Vector3(0, 0.45, 0), "wood"], ["cyl", Vector3(0.08, 0.43, 0.08), Vector3(0, 0.21, 0), "wood_dark"]])
	_prop("bed", ["bed"], ["FURNITURE"], F, [["box", Vector3(1.0, 0.35, 2.0), Vector3(0, 0.18, 0), "wood_dark"], ["box", Vector3(0.92, 0.14, 1.92), Vector3(0, 0.42, 0), "cloth"], ["box", Vector3(0.6, 0.1, 0.35), Vector3(0, 0.53, 0.7), "paper"]])
	_prop("bed_rich", ["bed"], ["FURNITURE"], F, [["box", Vector3(1.6, 0.4, 2.2), Vector3(0, 0.2, 0), "wood_dark"], ["box", Vector3(1.5, 0.16, 2.1), Vector3(0, 0.48, 0), "cloth_red"], ["box", Vector3(1.6, 1.2, 0.1), Vector3(0, 0.6, 1.05), "wood_dark"]], {"wealth_min": 2, "themes": ["house", "rich", "fort"]})
	_prop("bunk", ["bed", "bunk"], ["FURNITURE"], F, [["box", Vector3(1.0, 0.12, 2.0), Vector3(0, 0.4, 0), "wood_dark"], ["box", Vector3(0.92, 0.1, 1.9), Vector3(0, 0.51, 0), "cloth"], ["box", Vector3(1.0, 0.12, 2.0), Vector3(0, 1.5, 0), "wood_dark"],
		["box", Vector3(0.92, 0.1, 1.9), Vector3(0, 1.61, 0), "cloth"]] + legs.call(1.0, 2.0, 1.9, "wood_dark"), {"themes": ["fort", "mine", "lair"]})
	_prop("bedroll", ["bed", "bedroll"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.8, 0.08, 1.9), Vector3(0, 0.04, 0), "cloth"], ["box", Vector3(0.5, 0.12, 0.3), Vector3(0, 0.1, 0.75), "cloth_red"]], {"themes": ["cave", "lair", "mine", "ruin"], "ghost": true})
	_prop("shelf", ["shelf", "storage"], ["FURNITURE", "WALL_DECORATION"], W, [["box", Vector3(1.4, 1.9, 0.05), Vector3(0, 0.95, 0.18), "wood_dark"], ["box", Vector3(1.4, 0.05, 0.4), Vector3(0, 0.6, 0), "wood"], ["box", Vector3(1.4, 0.05, 0.4), Vector3(0, 1.2, 0), "wood"],
		["box", Vector3(1.4, 0.05, 0.4), Vector3(0, 1.8, 0), "wood"], ["box", Vector3(0.3, 0.25, 0.25), Vector3(-0.4, 0.75, 0), "iron"], ["box", Vector3(0.4, 0.2, 0.3), Vector3(0.3, 1.33, 0), "cloth"]])
	_prop("bookshelf", ["shelf", "books"], ["FURNITURE", "WALL_DECORATION"], W, [["box", Vector3(1.4, 2.0, 0.4), Vector3(0, 1.0, 0), "wood_dark"], ["box", Vector3(1.2, 0.3, 0.3), Vector3(0, 0.5, -0.06), "cloth_red"], ["box", Vector3(1.2, 0.3, 0.3), Vector3(0, 1.05, -0.06), "cloth_blue"], ["box", Vector3(1.2, 0.3, 0.3), Vector3(0, 1.6, -0.06), "paper"]], {"themes": ["fort", "ruin", "house", "rich", "lair", "crypt"]})
	_prop("weapon_rack", ["rack", "weapons"], ["FURNITURE", "WALL_DECORATION"], W, [["box", Vector3(1.4, 0.1, 0.3), Vector3(0, 0.3, 0), "wood_dark"], ["box", Vector3(1.4, 0.1, 0.1), Vector3(0, 1.4, 0.1), "wood_dark"],
		["box", Vector3(0.06, 1.3, 0.06), Vector3(-0.4, 0.85, 0.05), "iron"], ["box", Vector3(0.06, 1.4, 0.06), Vector3(0, 0.9, 0.05), "iron"], ["box", Vector3(0.06, 1.2, 0.06), Vector3(0.4, 0.8, 0.05), "iron"]], {"themes": ["fort", "lair", "house"]})
	_prop("armor_stand", ["armor", "rack"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.5, 0.1, 0.5), Vector3(0, 0.05, 0), "wood_dark"], ["box", Vector3(0.08, 1.4, 0.08), Vector3(0, 0.75, 0), "wood"], ["box", Vector3(0.6, 0.7, 0.3), Vector3(0, 1.2, 0), "iron"]], {"themes": ["fort", "rich", "house"]})
	_prop("training_dummy", ["dummy", "training"], ["DECORATION"], F, [["box", Vector3(0.1, 1.6, 0.1), Vector3(0, 0.8, 0), "wood"], ["box", Vector3(0.6, 0.12, 0.12), Vector3(0, 1.3, 0), "wood"], ["box", Vector3(0.4, 0.6, 0.3), Vector3(0, 1.2, 0), "straw"]], {"themes": ["fort"]})
	_prop("barrel", ["barrel", "storage"], ["DECORATION", "FURNITURE"], F, [["cyl", Vector3(0.6, 0.9, 0.6), Vector3(0, 0.45, 0), "wood_dark"], ["cyl", Vector3(0.63, 0.06, 0.63), Vector3(0, 0.2, 0), "iron"], ["cyl", Vector3(0.63, 0.06, 0.63), Vector3(0, 0.7, 0), "iron"]], {"weight": 2.0})
	_prop("barrels", ["barrel", "storage"], ["DECORATION", "FURNITURE"], F, [["cyl", Vector3(0.6, 0.9, 0.6), Vector3(-0.35, 0.45, 0), "wood_dark"], ["cyl", Vector3(0.6, 0.9, 0.6), Vector3(0.35, 0.45, 0.1), "wood_dark"], ["cyl", Vector3(0.6, 0.9, 0.6), Vector3(0, 1.35, 0.05), "wood_dark"]])
	_prop("crate", ["crate", "storage"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), "wood"]], {"weight": 2.0})
	_prop("crates", ["crate", "storage"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(0.8, 0.8, 0.8), Vector3(-0.42, 0.4, 0), "wood"], ["box", Vector3(0.8, 0.8, 0.8), Vector3(0.42, 0.4, 0.05), "wood"], ["box", Vector3(0.7, 0.7, 0.7), Vector3(0, 1.15, 0), "wood", 0.3]])
	_prop("sacks", ["sack", "storage"], ["DECORATION"], F, [["box", Vector3(0.5, 0.6, 0.4), Vector3(-0.25, 0.3, 0), "cloth", 0.2], ["box", Vector3(0.5, 0.55, 0.4), Vector3(0.3, 0.28, 0.1), "cloth", -0.3]])
	_prop("keg_rack", ["barrel", "drink"], ["FURNITURE", "WALL_DECORATION"], W, [["box", Vector3(1.8, 1.2, 0.6), Vector3(0, 0.6, 0.05), "wood_dark"], ["cyl", Vector3(0.5, 0.7, 0.5), Vector3(-0.5, 0.95, -0.05), "wood"], ["cyl", Vector3(0.5, 0.7, 0.5), Vector3(0.5, 0.95, -0.05), "wood"]], {"themes": ["fort", "house", "lair"]})
	_prop("banner", ["banner"], ["WALL_DECORATION"], W, [["box", Vector3(1.1, 0.08, 0.08), Vector3(0, 3.0, 0.1), "wood_dark"], ["box", Vector3(1.0, 2.2, 0.04), Vector3(0, 1.85, 0.12), "cloth_red"]], {"themes": ["fort", "rich", "house"], "ghost": true})
	_prop("banner_blue", ["banner"], ["WALL_DECORATION"], W, [["box", Vector3(1.1, 0.08, 0.08), Vector3(0, 3.0, 0.1), "wood_dark"], ["box", Vector3(1.0, 2.2, 0.04), Vector3(0, 1.85, 0.12), "cloth_blue"]], {"themes": ["fort", "rich", "house"], "ghost": true})
	_prop("tapestry", ["tapestry", "banner"], ["WALL_DECORATION"], W, [["box", Vector3(2.0, 2.4, 0.04), Vector3(0, 2.0, 0.12), "cloth_blue"]], {"themes": ["rich", "fort", "house"], "wealth_min": 1, "ghost": true})
	_prop("shield_wall", ["shield"], ["WALL_DECORATION"], W, [["cyl", Vector3(0.7, 0.06, 0.7), Vector3(0, 2.2, 0.12), "iron"]], {"themes": ["fort", "house"], "ghost": true})
	_prop("candle_stand", ["candle", "light"], ["LIGHT", "DECORATION"], F, [["box", Vector3(0.3, 0.05, 0.3), Vector3(0, 0.03, 0), "iron"], ["box", Vector3(0.06, 1.3, 0.06), Vector3(0, 0.68, 0), "iron"], ["box", Vector3(0.08, 0.2, 0.08), Vector3(0, 1.43, 0), "paper"], ["box", Vector3(0.05, 0.08, 0.05), Vector3(0, 1.57, 0), "glow"]],
		{"light": warm, "range": 5.0, "energy": 0.9, "light_at": Vector3(0, 1.6, 0)})
	_prop("candles", ["candle", "light", "tabletop"], ["LIGHT", "DECORATION"], F, [["box", Vector3(0.07, 0.25, 0.07), Vector3(-0.1, 0.13, 0), "paper"], ["box", Vector3(0.07, 0.18, 0.07), Vector3(0.08, 0.09, 0.05), "paper"], ["box", Vector3(0.04, 0.06, 0.04), Vector3(-0.1, 0.29, 0), "glow"]],
		{"light": warm, "range": 4.0, "energy": 0.7, "light_at": Vector3(0, 0.4, 0), "ghost": true, "themes": ["crypt", "lair", "house", "rich", "ruin"]})
	_prop("sconce", ["torch", "light"], ["LIGHT", "WALL_DECORATION"], W, [["box", Vector3(0.12, 0.4, 0.15), Vector3(0, 2.1, 0.1), "iron"], ["box", Vector3(0.1, 0.18, 0.1), Vector3(0, 2.35, 0.0), "glow"]],
		{"light": warm, "range": 7.0, "energy": 1.3, "light_at": Vector3(0, 2.4, -0.3), "ghost": true})
	_prop("brazier", ["brazier", "light", "fire"], ["LIGHT", "DECORATION"], F, [["cyl", Vector3(0.8, 0.3, 0.5), Vector3(0, 0.85, 0), "iron"], ["box", Vector3(0.06, 0.75, 0.06), Vector3(-0.2, 0.38, 0), "iron"], ["box", Vector3(0.06, 0.75, 0.06), Vector3(0.2, 0.38, 0), "iron"], ["box", Vector3(0.5, 0.2, 0.5), Vector3(0, 1.05, 0), "glow"]],
		{"light": Color(1.0, 0.55, 0.25), "range": 9.0, "energy": 1.6, "light_at": Vector3(0, 1.4, 0)})
	_prop("fungus", ["fungus", "light"], ["LIGHT", "DECORATION"], F, [["cyl", Vector3(0.3, 0.3, 0.12), Vector3(0, 0.15, 0), "fungus_glow"], ["cyl", Vector3(0.22, 0.22, 0.1), Vector3(0.25, 0.11, 0.1), "fungus_glow"], ["cyl", Vector3(0.18, 0.18, 0.08), Vector3(-0.2, 0.09, 0.15), "fungus_glow"]],
		{"light": Color(0.4, 0.9, 0.7), "range": 5.0, "energy": 0.8, "light_at": Vector3(0, 0.6, 0), "ghost": true, "themes": ["cave", "mine", "lair", "sewer"]})
	_prop("crystal", ["crystal", "light"], ["LIGHT", "DECORATION"], F, [["box", Vector3(0.3, 1.2, 0.3), Vector3(0, 0.6, 0), "ice", 0.4], ["box", Vector3(0.25, 0.8, 0.25), Vector3(0.3, 0.4, 0.1), "ice", -0.3]],
		{"light": Color(0.6, 0.8, 1.0), "range": 6.0, "energy": 0.8, "light_at": Vector3(0, 1.0, 0), "themes": ["ice", "cave"]})
	_prop("cauldron", ["cauldron", "kitchen"], ["FURNITURE", "DECORATION"], F, [["cyl", Vector3(0.9, 0.6, 0.7), Vector3(0, 0.4, 0), "iron"], ["cyl", Vector3(0.75, 0.04, 0.75), Vector3(0, 0.71, 0), "water"]])
	_prop("hearth", ["hearth", "kitchen", "fire", "light"], ["FURNITURE", "LIGHT"], W, [["box", Vector3(1.8, 1.4, 0.8), Vector3(0, 0.7, 0.1), "stone"], ["box", Vector3(1.0, 0.6, 0.5), Vector3(0, 0.4, -0.1), "stone_dark"], ["box", Vector3(0.7, 0.3, 0.3), Vector3(0, 0.25, -0.2), "glow"]],
		{"light": Color(1.0, 0.5, 0.2), "range": 7.0, "energy": 1.4, "light_at": Vector3(0, 0.8, -0.8), "themes": ["fort", "house", "rich", "lair"]})
	_prop("anvil", ["anvil", "smith"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.4, 0.5, 0.4), Vector3(0, 0.25, 0), "wood_dark"], ["box", Vector3(0.8, 0.25, 0.35), Vector3(0, 0.63, 0), "iron"]], {"themes": ["fort", "house"]})
	_prop("altar", ["altar"], ["FURNITURE"], F, [["box", Vector3(1.8, 1.0, 0.9), Vector3(0, 0.5, 0), "stone"], ["box", Vector3(1.9, 0.05, 0.6), Vector3(0, 1.03, 0), "cloth_red"], ["box", Vector3(0.1, 0.3, 0.1), Vector3(-0.6, 1.2, 0), "paper"], ["box", Vector3(0.1, 0.3, 0.1), Vector3(0.6, 1.2, 0), "paper"]], {"themes": ["crypt", "lair", "ruin", "rich"]})
	_prop("sarcophagus", ["sarcophagus", "tomb"], ["FURNITURE"], F, [["box", Vector3(1.0, 0.8, 2.2), Vector3(0, 0.4, 0), "stone_dark"], ["box", Vector3(1.1, 0.15, 2.3), Vector3(0, 0.88, 0), "stone"]], {"themes": ["crypt", "ruin"], "weight": 2.0})
	_prop("bones", ["bones", "remains"], ["DECORATION"], F, [["box", Vector3(0.5, 0.06, 0.06), Vector3(0, 0.03, 0), "bone", 0.4], ["box", Vector3(0.4, 0.05, 0.05), Vector3(0.1, 0.03, 0.15), "bone", -0.8], ["box", Vector3(0.2, 0.18, 0.2), Vector3(-0.25, 0.09, -0.1), "bone"]], {"ghost": true, "themes": ["crypt", "cave", "lair", "ruin", "sewer"]})
	_prop("skull_pile", ["bones", "remains"], ["DECORATION"], F, [["box", Vector3(0.2, 0.18, 0.2), Vector3(0, 0.09, 0), "bone"], ["box", Vector3(0.2, 0.18, 0.2), Vector3(0.22, 0.09, 0.05), "bone"], ["box", Vector3(0.2, 0.18, 0.2), Vector3(0.1, 0.27, 0.02), "bone"]], {"themes": ["crypt", "lair"], "ghost": true})
	_prop("rubble", ["rubble"], ["DECORATION"], F, [["box", Vector3(0.7, 0.5, 0.6), Vector3(0, 0.25, 0), "stone", 0.5], ["box", Vector3(0.5, 0.35, 0.5), Vector3(0.5, 0.17, 0.2), "stone", 1.1], ["box", Vector3(0.4, 0.3, 0.4), Vector3(-0.45, 0.15, 0.3), "stone_dark", 0.2]], {"themes": ["ruin", "crypt", "mine", "cave", "fort"]})
	_prop("cobweb", ["cobweb"], ["CEILING", "DECORATION"], InteriorProp.Snap.CEILING, [["box", Vector3(1.4, 0.02, 1.4), Vector3(0, -0.05, 0), "paper", 0.7]], {"ghost": true, "themes": ["crypt", "cave", "ruin", "mine", "lair", "sewer"]})
	_prop("chain", ["chain"], ["CEILING", "DECORATION"], InteriorProp.Snap.CEILING, [["box", Vector3(0.05, 1.5, 0.05), Vector3(0, -0.75, 0), "iron"]], {"ghost": true, "themes": ["fort", "crypt", "lair", "sewer"]})
	_prop("cage", ["cage", "prison"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(1.2, 0.1, 1.2), Vector3(0, 0.05, 0), "iron"], ["box", Vector3(1.2, 0.1, 1.2), Vector3(0, 1.8, 0), "iron"],
		["box", Vector3(0.05, 1.7, 0.05), Vector3(-0.55, 0.9, -0.55), "iron"], ["box", Vector3(0.05, 1.7, 0.05), Vector3(0.55, 0.9, -0.55), "iron"], ["box", Vector3(0.05, 1.7, 0.05), Vector3(-0.55, 0.9, 0.55), "iron"], ["box", Vector3(0.05, 1.7, 0.05), Vector3(0.55, 0.9, 0.55), "iron"]], {"themes": ["fort", "lair", "sewer"]})
	_prop("mine_cart", ["cart", "mine"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.9, 0.6, 1.4), Vector3(0, 0.55, 0), "wood_dark"], ["cyl", Vector3(0.4, 0.1, 0.4), Vector3(-0.48, 0.2, 0.45), "iron"], ["cyl", Vector3(0.4, 0.1, 0.4), Vector3(0.48, 0.2, -0.45), "iron"], ["box", Vector3(0.7, 0.2, 1.2), Vector3(0, 0.9, 0), "rock_dark"]], {"themes": ["mine"]})
	_prop("rails", ["rails", "mine"], ["DECORATION"], F, [["box", Vector3(0.06, 0.05, 3.8), Vector3(-0.5, 0.03, 0), "iron"], ["box", Vector3(0.06, 0.05, 3.8), Vector3(0.5, 0.03, 0), "iron"], ["box", Vector3(1.3, 0.04, 0.2), Vector3(0, 0.02, -1.2), "wood_dark"], ["box", Vector3(1.3, 0.04, 0.2), Vector3(0, 0.02, 0), "wood_dark"], ["box", Vector3(1.3, 0.04, 0.2), Vector3(0, 0.02, 1.2), "wood_dark"]], {"themes": ["mine"], "ghost": true})
	_prop("support_beams", ["beams", "mine"], ["DECORATION"], F, [["box", Vector3(0.25, 4.6, 0.25), Vector3(-1.6, 2.3, 0), "wood"], ["box", Vector3(0.25, 4.6, 0.25), Vector3(1.6, 2.3, 0), "wood"], ["box", Vector3(3.6, 0.3, 0.3), Vector3(0, 4.55, 0), "wood"]], {"themes": ["mine"], "ghost": true})
	_prop("pickaxes", ["tools", "mine"], ["WALL_DECORATION", "DECORATION"], W, [["box", Vector3(0.05, 1.0, 0.05), Vector3(-0.2, 0.5, 0.1), "wood", 0.2], ["box", Vector3(0.4, 0.08, 0.06), Vector3(-0.15, 0.98, 0.1), "iron"], ["box", Vector3(0.05, 1.0, 0.05), Vector3(0.2, 0.5, 0.1), "wood", -0.2]], {"themes": ["mine"], "ghost": true})
	_prop("rope_coil", ["rope"], ["DECORATION"], F, [["cyl", Vector3(0.6, 0.2, 0.6), Vector3(0, 0.1, 0), "straw"]], {"themes": ["mine", "cave", "fort", "sewer"], "ghost": true})
	_prop("stalagmite", ["rock", "stalagmite"], ["DECORATION"], F, [["cyl", Vector3(0.05, 1.6, 0.7), Vector3(0, 0.8, 0), "rock"], ["cyl", Vector3(0.05, 0.9, 0.4), Vector3(0.4, 0.45, 0.2), "rock_dark"]], {"themes": ["cave", "ice", "mine"], "weight": 2.0})
	_prop("stalactite", ["rock"], ["CEILING", "DECORATION"], InteriorProp.Snap.CEILING, [["cyl", Vector3(0.6, 1.2, 0.05), Vector3(0, -0.6, 0), "rock_dark"]], {"themes": ["cave", "ice"], "ghost": true})
	_prop("boulder", ["rock", "rubble"], ["DECORATION"], F, [["box", Vector3(1.4, 1.0, 1.2), Vector3(0, 0.5, 0), "rock", 0.6], ["box", Vector3(0.8, 0.7, 0.9), Vector3(0.6, 0.35, 0.4), "rock_dark", 0.2]], {"themes": ["cave", "mine", "ruin", "ice"]})
	_prop("statue", ["statue"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(1.0, 0.6, 1.0), Vector3(0, 0.3, 0), "stone"], ["box", Vector3(0.5, 1.6, 0.4), Vector3(0, 1.4, 0), "stone"], ["box", Vector3(0.3, 0.35, 0.3), Vector3(0, 2.4, 0), "stone"]], {"themes": ["crypt", "ruin", "rich", "fort"]})
	_prop("pillar", ["pillar"], ["FURNITURE"], F, [["box", Vector3(0.9, 4.7, 0.9), Vector3(0, 2.35, 0), "stone"], ["box", Vector3(1.1, 0.3, 1.1), Vector3(0, 0.15, 0), "stone_dark"]], {"themes": ["fort", "crypt", "ruin", "rich", "sewer"]})
	_prop("broken_pillar", ["pillar", "rubble"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.9, 1.6, 0.9), Vector3(0, 0.8, 0), "moss_stone"], ["box", Vector3(0.9, 0.9, 1.8), Vector3(1.0, 0.45, 0.8), "moss_stone", 0.5]], {"themes": ["ruin", "crypt"]})
	_prop("throne", ["throne", "seat"], ["FURNITURE"], F, [["box", Vector3(1.2, 0.5, 1.0), Vector3(0, 0.25, 0), "stone"], ["box", Vector3(1.0, 0.1, 0.8), Vector3(0, 0.55, 0), "cloth_red"], ["box", Vector3(1.2, 2.2, 0.2), Vector3(0, 1.4, 0.45), "stone"]], {"themes": ["fort", "rich", "crypt", "lair"], "wealth_min": 1})
	_prop("hay_pile", ["hay"], ["DECORATION"], F, [["box", Vector3(1.4, 0.6, 1.2), Vector3(0, 0.3, 0), "straw", 0.2]], {"themes": ["fort", "lair", "house"]})
	_prop("bucket", ["bucket"], ["DECORATION"], F, [["cyl", Vector3(0.35, 0.4, 0.3), Vector3(0, 0.2, 0), "wood_dark"]], {"ghost": true})
	_prop("puddle", ["water"], ["DECORATION"], F, [["box", Vector3(1.6, 0.02, 1.2), Vector3(0, 0.01, 0), "water", 0.3]], {"ghost": true, "themes": ["sewer", "cave", "ruin", "crypt"]})
	_prop("ritual_circle", ["ritual"], ["DECORATION"], F, [["cyl", Vector3(2.6, 0.02, 2.6), Vector3(0, 0.01, 0), "cloth_red"], ["box", Vector3(0.1, 0.3, 0.1), Vector3(1.0, 0.15, 0), "paper"], ["box", Vector3(0.1, 0.3, 0.1), Vector3(-1.0, 0.15, 0), "paper"]], {"ghost": true, "themes": ["lair", "crypt", "ruin"]})


# ---------------------------------------------------------------- rooms

## What each kind of room holds: [rule, socket kind, tags, chance, count]
##   walls      along the walls, one per cell (not in front of doorways), facing in
##   wall_high  on the walls up high (banners, sconces)
##   center     in the middle (big rooms: one per 2x2 block)
##   cells      in the middle of every cell
##   corners    in the four corners
##   scatter    count spots spread around
##   ceiling    under the ceiling of every cell
const FURNISH := {
	"barracks": [["walls", S.FURNITURE, ["bunk", "bed"], 0.9, 1], ["center", S.FURNITURE, ["table"], 0.8, 1], ["wall_high", S.WALL_DECORATION, ["banner", "shield", "rack"], 0.5, 1], ["corners", S.CHEST, ["footlocker"], 0.4, 1], ["wall_high", S.LIGHT, ["torch"], 0.5, 1], ["scatter", S.ENEMY, ["sleeper"], 0.8, 2]],
	"war_room": [["center", S.FURNITURE, ["map"], 1.0, 1], ["walls", S.FURNITURE, ["shelf", "rack"], 0.6, 1], ["wall_high", S.WALL_DECORATION, ["banner", "tapestry"], 0.8, 1], ["corners", S.LIGHT, ["candle", "brazier"], 0.7, 1], ["scatter", S.ENEMY, [], 0.7, 2], ["corners", S.CHEST, [], 0.3, 1]],
	"kitchen": [["walls", S.FURNITURE, ["hearth", "shelf", "barrel"], 0.85, 1], ["center", S.FURNITURE, ["table", "meal"], 1.0, 1], ["scatter", S.DECORATION, ["barrel", "sack", "crate", "bucket"], 0.8, 3], ["corners", S.LIGHT, ["candle"], 0.5, 1], ["scatter", S.ENEMY, ["cook"], 0.5, 1]],
	"mess_hall": [["cells", S.FURNITURE, ["table", "meal"], 0.7, 1], ["walls", S.FURNITURE, ["bench", "barrel", "keg"], 0.6, 1], ["wall_high", S.LIGHT, ["torch"], 0.6, 1], ["scatter", S.ENEMY, ["eating"], 0.8, 3]],
	"armory": [["walls", S.FURNITURE, ["rack", "armor"], 0.95, 1], ["center", S.FURNITURE, ["anvil", "table"], 0.6, 1], ["corners", S.CHEST, ["weapons"], 0.5, 1], ["wall_high", S.LIGHT, ["torch"], 0.5, 1], ["scatter", S.ENEMY, ["guard"], 0.6, 1]],
	"storeroom": [["walls", S.FURNITURE, ["storage", "shelf"], 0.95, 1], ["scatter", S.DECORATION, ["crate", "barrel", "sack"], 0.9, 4], ["corners", S.CHEST, [], 0.6, 1], ["ceiling", S.CEILING, ["cobweb"], 0.4, 1]],
	"commander": [["walls", S.FURNITURE, ["bed", "bookshelf", "shelf"], 0.8, 1], ["center", S.FURNITURE, ["table"], 1.0, 1], ["wall_high", S.WALL_DECORATION, ["tapestry", "banner"], 0.8, 1], ["corners", S.CHEST, ["rich"], 0.9, 1], ["corners", S.LIGHT, ["candle"], 0.6, 1], ["center", S.ENEMY, ["officer"], 0.8, 1]],
	"cells": [["walls", S.FURNITURE, ["cage", "bedroll"], 0.8, 1], ["scatter", S.DECORATION, ["bones", "bucket", "hay"], 0.7, 3], ["ceiling", S.CEILING, ["chain"], 0.5, 1], ["wall_high", S.LIGHT, ["torch"], 0.4, 1], ["center", S.NPC, ["captive"], 0.3, 1], ["scatter", S.ENEMY, ["guard"], 0.6, 1]],
	"guard_post": [["center", S.FURNITURE, ["table", "stool"], 0.8, 1], ["wall_high", S.LIGHT, ["torch"], 0.8, 1], ["scatter", S.ENEMY, ["guard"], 0.9, 1]],
	"great_hall": [["cells", S.FURNITURE, ["pillar"], 0.35, 1], ["center", S.FURNITURE, ["throne", "table"], 1.0, 1], ["wall_high", S.WALL_DECORATION, ["banner", "tapestry"], 0.8, 1], ["corners", S.LIGHT, ["brazier"], 0.9, 1], ["center", S.BOSS, [], 1.0, 1], ["scatter", S.ENEMY, [], 0.8, 2], ["corners", S.CHEST, ["boss"], 1.0, 1]],
	"gallery": [["center", S.FURNITURE, ["table", "statue", "altar"], 0.8, 1], ["wall_high", S.WALL_DECORATION, ["banner", "tapestry"], 0.7, 1], ["corners", S.LIGHT, ["brazier", "candle"], 0.8, 1], ["scatter", S.ENEMY, [], 0.8, 3], ["scatter", S.DECORATION, ["rubble", "barrel", "bones"], 0.5, 2]],
	"corridor": [["wall_high", S.LIGHT, ["torch", "fungus"], 0.35, 1], ["scatter", S.DECORATION, ["rubble", "bones", "barrel", "crate", "rails", "puddle"], 0.4, 1], ["ceiling", S.CEILING, ["cobweb", "chain"], 0.2, 1], ["scatter", S.ENEMY, ["patrol"], 0.25, 1]],
	"entrance": [["wall_high", S.LIGHT, ["torch"], 0.8, 1], ["scatter", S.DECORATION, ["barrel", "crate", "rubble", "bones"], 0.6, 2]],
	"stairs": [["wall_high", S.LIGHT, ["torch"], 0.6, 1]],
	"burial_hall": [["walls", S.FURNITURE, ["sarcophagus"], 0.8, 1], ["scatter", S.DECORATION, ["bones", "candle", "rubble"], 0.8, 3], ["ceiling", S.CEILING, ["cobweb"], 0.5, 1], ["scatter", S.ENEMY, ["undead"], 0.8, 2], ["corners", S.LOOT, [], 0.4, 1]],
	"ossuary": [["walls", S.DECORATION, ["bones", "skull_pile"], 0.95, 1], ["center", S.FURNITURE, ["altar"], 0.5, 1], ["corners", S.LIGHT, ["candle"], 0.6, 1], ["scatter", S.ENEMY, ["undead"], 0.7, 2]],
	"sarcophagi": [["cells", S.FURNITURE, ["sarcophagus"], 0.6, 1], ["corners", S.LIGHT, ["candle", "brazier"], 0.5, 1], ["scatter", S.ENEMY, ["undead"], 0.7, 2], ["corners", S.CHEST, [], 0.35, 1]],
	"chapel": [["center", S.FURNITURE, ["altar"], 1.0, 1], ["walls", S.FURNITURE, ["bench", "statue"], 0.6, 1], ["corners", S.LIGHT, ["candle", "brazier"], 0.9, 1], ["scatter", S.ENEMY, ["priest"], 0.6, 1], ["scatter", S.DECORATION, ["ritual"], 0.4, 1]],
	"catacomb": [["walls", S.DECORATION, ["bones", "skull_pile"], 0.8, 1], ["cells", S.FURNITURE, ["pillar"], 0.25, 1], ["ceiling", S.CEILING, ["cobweb"], 0.5, 1], ["scatter", S.ENEMY, ["undead"], 0.8, 3]],
	"tomb": [["center", S.FURNITURE, ["sarcophagus"], 1.0, 1], ["walls", S.FURNITURE, ["statue", "pillar"], 0.6, 1], ["corners", S.LIGHT, ["brazier", "candle"], 1.0, 1], ["center", S.BOSS, [], 1.0, 1], ["corners", S.CHEST, ["boss"], 1.0, 1], ["scatter", S.ENEMY, ["undead"], 0.7, 2]],
	"cavern": [["scatter", S.DECORATION, ["stalagmite", "boulder", "rock"], 0.85, 4], ["ceiling", S.CEILING, ["rock"], 0.5, 1], ["scatter", S.LIGHT, ["fungus", "crystal"], 0.6, 2], ["scatter", S.ENEMY, ["beast"], 0.8, 2], ["scatter", S.LOOT, [], 0.3, 1]],
	"lake": [["walls", S.DECORATION, ["stalagmite", "boulder"], 0.6, 1], ["scatter", S.LIGHT, ["fungus"], 0.8, 2], ["scatter", S.ENEMY, ["beast"], 0.6, 2]],
	"chasm": [["walls", S.DECORATION, ["boulder", "rope"], 0.5, 1], ["scatter", S.LIGHT, ["fungus"], 0.6, 1], ["scatter", S.ENEMY, ["beast"], 0.5, 1]],
	"nest": [["scatter", S.DECORATION, ["bones", "remains", "boulder"], 0.95, 5], ["scatter", S.LIGHT, ["fungus"], 0.6, 2], ["center", S.BOSS, [], 1.0, 1], ["corners", S.CHEST, ["boss"], 1.0, 1], ["scatter", S.ENEMY, ["beast"], 0.7, 2]],
	"ore_chamber": [["walls", S.DECORATION, ["tools", "beams", "rope"], 0.6, 1], ["scatter", S.FURNITURE, ["cart"], 0.6, 1], ["scatter", S.DECORATION, ["boulder", "rubble"], 0.7, 3], ["wall_high", S.LIGHT, ["torch"], 0.6, 1], ["scatter", S.ENEMY, ["miner"], 0.7, 2]],
	"office": [["center", S.FURNITURE, ["table"], 1.0, 1], ["walls", S.FURNITURE, ["shelf", "bookshelf"], 0.7, 1], ["corners", S.CHEST, [], 0.7, 1], ["corners", S.LIGHT, ["candle"], 0.7, 1], ["center", S.ENEMY, ["officer"], 0.5, 1]],
	"cistern": [["cells", S.FURNITURE, ["pillar"], 0.4, 1], ["scatter", S.DECORATION, ["puddle", "bones", "crate"], 0.6, 3], ["wall_high", S.LIGHT, ["torch"], 0.4, 1], ["scatter", S.ENEMY, ["beast"], 0.7, 3]],
	"den": [["walls", S.FURNITURE, ["bedroll", "crate", "barrel"], 0.85, 1], ["center", S.FURNITURE, ["table"], 0.7, 1], ["scatter", S.LIGHT, ["brazier", "candle"], 0.7, 1], ["corners", S.CHEST, [], 0.8, 1], ["scatter", S.ENEMY, ["bandit"], 0.9, 3]],
	"library": [["walls", S.FURNITURE, ["bookshelf"], 0.95, 1], ["center", S.FURNITURE, ["table"], 0.8, 1], ["corners", S.LIGHT, ["candle"], 0.8, 1], ["corners", S.LOOT, ["book"], 0.6, 1], ["scatter", S.ENEMY, [], 0.5, 1]],
	"courtyard": [["cells", S.DECORATION, ["broken_pillar", "rubble", "statue"], 0.4, 1], ["scatter", S.ENEMY, [], 0.7, 2]],
	"fallen_hall": [["cells", S.FURNITURE, ["pillar", "broken_pillar"], 0.4, 1], ["scatter", S.DECORATION, ["rubble"], 0.9, 4], ["scatter", S.ENEMY, [], 0.7, 2]],
	"flooded": [["scatter", S.DECORATION, ["puddle", "rubble"], 0.9, 4], ["scatter", S.ENEMY, ["beast"], 0.6, 2]],
	"sanctum": [["center", S.FURNITURE, ["altar"], 1.0, 1], ["scatter", S.DECORATION, ["ritual", "candle", "skull_pile"], 0.9, 4], ["corners", S.LIGHT, ["brazier", "candle"], 0.9, 1], ["center", S.BOSS, [], 1.0, 1], ["corners", S.CHEST, ["boss"], 1.0, 1], ["scatter", S.ENEMY, ["cultist"], 0.9, 3]],
}


# side: 0 front (-Z), 1 left (-X), 2 back (+Z), 3 right (+X); door = [side, cell index, floor, kind, width]
func _room(theme: String, file: String, kind: String, role: RoomModule.Role, cells: Vector3i, doors: Array, opts: Dictionary = {}) -> void:
	var room := RoomModule.new()
	room.name = file.to_pascal_case()
	room.themes = PackedStringArray([theme] + Array(opts.get("also", [])))
	room.kind = kind
	room.role = role
	room.cells = cells
	room.weight = float(opts.get("weight", 1.0))
	room.max_per_dungeon = int(opts.get("max", 0))
	room.level_min = int(opts.get("level_min", 1))
	room.wealth = int(opts.get("wealth", 1))
	var b := room.bounds()
	var n := 0
	for d: Array in doors:
		var dm := DoorwayMarker.new()
		dm.name = "Doorway%d" % n
		n += 1
		var side := int(d[0])
		var i := int(d[1])
		var f := int(d[2]) if d.size() > 2 else 0
		dm.kind = DoorwayMarker.Kind.keys().find(String(d[3]).to_upper()) if d.size() > 3 else DoorwayMarker.Kind.ARCH
		dm.width = float(d[4]) if d.size() > 4 else (3.2 if role == RoomModule.Role.CORRIDOR else 2.4)
		dm.height = 3.2
		dm.tags = PackedStringArray(opts.get("door_tags", []))
		var along := -b.size.x * 0.5 + RoomModule.CELL * 0.5 + i * RoomModule.CELL if side % 2 == 0 else -b.size.z * 0.5 + RoomModule.CELL * 0.5 + i * RoomModule.CELL
		match side:
			0:
				dm.position = Vector3(along, f * RoomModule.LEVEL, -b.size.z * 0.5)
			1:
				dm.position = Vector3(-b.size.x * 0.5, f * RoomModule.LEVEL, along)
				dm.rotation.y = PI * 0.5
			2:
				dm.position = Vector3(along, f * RoomModule.LEVEL, b.size.z * 0.5)
				dm.rotation.y = PI
			3:
				dm.position = Vector3(b.size.x * 0.5, f * RoomModule.LEVEL, along)
				dm.rotation.y = -PI * 0.5
		room.add_child(dm)
		dm.owner = room
	InteriorKit.shell(room, theme, room, not bool(opts.get("open_sky", false)))
	if opts.has("extras"):
		(opts["extras"] as Callable).call(room, theme)
	_furnish(room, kind if FURNISH.has(kind) else ("corridor" if role in [RoomModule.Role.CORRIDOR, RoomModule.Role.JUNCTION, RoomModule.Role.DEAD_END] else "entrance"))
	if role == RoomModule.Role.BOSS and not FURNISH.get(kind, []).any(func(r: Array) -> bool: return int(r[1]) == S.BOSS):
		# every boss room has its boss and the boss chest (quests put their items in it)
		_socket(room, S.BOSS, [], Vector3(0, 0, room.bounds().size.z * 0.15), PI, 1.0, 1)
		_socket(room, S.CHEST, ["boss"], Vector3(room.bounds().size.x * 0.5 - 1.2, 0, room.bounds().size.z * 0.5 - 1.2), PI * 0.75, 1.0, 1)
	if role == RoomModule.Role.ENTRANCE:
		_marker(room, "PlayerStart", Vector3(0, 0.1, 0), PI)
		_marker(room, "Exit", Vector3(RoomModule.CELL * 0.5, 0.0, -room.bounds().size.z * 0.5 + 0.6), PI)  # the way out, on the front wall
	_save(room, String(opts.get("path", MOD_DIR + theme + "/" + file + ".tscn")))


func _marker(room: Node3D, name: String, at: Vector3, yaw: float) -> void:
	var m := Marker3D.new()
	m.name = name
	room.add_child(m)
	m.owner = room
	m.position = at
	m.rotation.y = yaw


func _socket(room: RoomModule, kind: int, tags: Array, at: Vector3, yaw: float, chance: float, count: int) -> void:
	var s := SpawnSocket.new()
	s.kind = kind as SpawnSocket.Kind
	s.tags = PackedStringArray(tags)
	s.chance = chance
	s.count = count
	s.name = "%s%d" % [String(SpawnSocket.Kind.keys()[kind]).to_pascal_case(), room.get_child_count()]
	room.add_child(s)
	s.owner = room
	s.position = at
	s.rotation.y = yaw


func _furnish(room: RoomModule, kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = String(room.name).hash()
	var b := room.bounds()
	var hx := b.size.x * 0.5
	var hz := b.size.z * 0.5
	var doors := room.doorways()
	var near_door := func(p: Vector3) -> bool:
		for d in doors:
			if Vector2(d.position.x - p.x, d.position.z - p.z).length() < 2.2 and absf(d.position.y - p.y) < 1.0:
				return true
		return false
	for rule: Array in FURNISH[kind]:
		var what := String(rule[0])
		var sk := int(rule[1])
		var tags: Array = rule[2]
		var chance := float(rule[3])
		var count := int(rule[4])
		match what:
			"walls", "wall_high":
				var y := 0.0 if what == "walls" else 0.0
				var inset := 0.8 if what == "walls" else 0.45
				for side in 4:
					var along_x := side % 2 == 0
					var cells := room.cells.x if along_x else room.cells.z
					for i in cells:
						var t := -(hx if along_x else hz) + RoomModule.CELL * 0.5 + i * RoomModule.CELL
						var p := Vector3(t, y, (-hz + inset) if side == 0 else (hz - inset)) if along_x else Vector3((-hx + inset) if side == 1 else (hx - inset), y, t)
						if near_door.call(p):
							continue
						# facing into the room: -Z of the socket points away from the wall
						var yaw: float = [PI, -PI * 0.5, 0.0, PI * 0.5][side]
						_socket(room, sk, tags, p, yaw, chance, count)
			"center":
				var blocks_x := maxi(room.cells.x / 2, 1)
				var blocks_z := maxi(room.cells.z / 2, 1)
				for bx in blocks_x:
					for bz in blocks_z:
						var p := Vector3(-hx + (bx + 0.5) * b.size.x / blocks_x, 0, -hz + (bz + 0.5) * b.size.z / blocks_z)
						_socket(room, sk, tags, p, rng.randf_range(-0.3, 0.3), chance, count)
			"cells":
				for c in room.local_cells():
					if c.y == 0:
						var p := room.cell_center(c)
						p.y = 0.0
						if not near_door.call(p):
							_socket(room, sk, tags, p, rng.randf() * TAU, chance, count)
			"corners":
				for sx in [-1, 1]:
					for sz in [-1, 1]:
						var p := Vector3(sx * (hx - 1.0), 0, sz * (hz - 1.0))
						if not near_door.call(p):
							_socket(room, sk, tags, p, atan2(sx, sz), chance, count)
			"scatter":
				for i in count:
					var p := Vector3(rng.randf_range(-hx + 1.2, hx - 1.2), 0, rng.randf_range(-hz + 1.2, hz - 1.2))
					if near_door.call(p):
						p = p * 0.5
					_socket(room, sk, tags, p, rng.randf() * TAU, chance, 1 if sk != S.ENEMY else 1)
			"ceiling":
				for c in room.local_cells():
					var p := room.cell_center(c)
					p.y = (c.y + 1) * RoomModule.LEVEL - 0.05
					_socket(room, sk, tags, p, rng.randf() * TAU, chance, count)


func _modules() -> void:
	var R := RoomModule.Role
	var themes_rooms := {
		"fort": ["barracks", "war_room", "kitchen", "mess_hall", "armory", "storeroom", "commander", "cells", "guard_post"],
		"crypt": ["burial_hall", "ossuary", "sarcophagi", "chapel", "catacomb"],
		"cave": ["cavern", "lake", "chasm"],
		"mine": ["ore_chamber", "office", "storeroom"],
		"sewer": ["cistern", "den", "storeroom"],
		"ruin": ["library", "fallen_hall", "flooded", "courtyard"],
		"lair": ["den", "cells", "storeroom"],
	}
	var boss := {"fort": "great_hall", "crypt": "tomb", "cave": "nest", "mine": "ore_chamber", "sewer": "cistern", "ruin": "fallen_hall", "lair": "sanctum"}
	var sizes := [Vector3i(2, 1, 2), Vector3i(3, 1, 2), Vector3i(2, 1, 3), Vector3i(3, 1, 3)]
	for theme in themes_rooms:
		var tags := [theme]
		# the way in: one doorway forward
		_room(theme, "entrance", "entrance", R.ENTRANCE, Vector3i(2, 1, 2), [[0, 0, 0, "door"], [2, 1]], {"door_tags": tags, "max": 1})
		_room(theme, "entrance_b", "entrance", R.ENTRANCE, Vector3i(2, 1, 2), [[2, 0], [3, 1]], {"door_tags": tags, "max": 1})
		# corridors and junctions
		_room(theme, "corridor_straight", "corridor", R.CORRIDOR, Vector3i(1, 1, 2), [[0, 0], [2, 0]], {"door_tags": tags, "weight": 2.0})
		_room(theme, "corridor_long", "corridor", R.CORRIDOR, Vector3i(1, 1, 3), [[0, 0], [2, 0]], {"door_tags": tags})
		_room(theme, "corridor_corner", "corridor", R.CORRIDOR, Vector3i(1, 1, 1), [[0, 0], [3, 0]], {"door_tags": tags, "weight": 1.5})
		_room(theme, "junction_t", "corridor", R.JUNCTION, Vector3i(1, 1, 1), [[0, 0], [1, 0], [3, 0]], {"door_tags": tags})
		_room(theme, "junction_cross", "corridor", R.JUNCTION, Vector3i(1, 1, 1), [[0, 0], [1, 0], [2, 0], [3, 0]], {"door_tags": tags, "weight": 0.7})
		_room(theme, "dead_end", "corridor", R.DEAD_END, Vector3i(1, 1, 1), [[0, 0]], {"door_tags": tags, "weight": 0.5})
		# rooms: each kind in two sizes, so rooms of a kind are similar but different
		var k := 0
		for kind: String in themes_rooms[theme]:
			for v in 2:
				var size: Vector3i = sizes[(k + v) % sizes.size()]
				var doors: Array = [[0, 0], [2, size.x - 1]]
				if v == 1:
					doors.append([3, size.z - 1])
				_room(theme, "%s_%s" % [kind, "a" if v == 0 else "b"], kind, R.ROOM if kind != "great_hall" else R.HALL, size, doors, {"door_tags": tags, "open_sky": kind == "courtyard"})
			k += 1
		# the boss room at the far end: one way in
		var bk: String = boss[theme]
		_room(theme, "boss_" + bk, bk, R.BOSS, Vector3i(4, 1, 4), [[0, 1, 0, "door", 3.2]], {"door_tags": tags, "max": 1, "level_min": 1})
		# stairs: up a floor, from the front at the bottom to the back at the top
		_room(theme, "stairs_straight", "stairs", R.STAIRS, Vector3i(1, 2, 4), [[0, 0, 0], [2, 0, 1]], {"door_tags": tags, "extras": _stairs_straight})
		_room(theme, "stairs_ladder", "stairs", R.STAIRS, Vector3i(1, 2, 2), [[0, 0, 0], [2, 0, 1]], {"door_tags": tags, "extras": _stairs_ladder, "weight": 0.6})
		if theme in ["cave", "mine", "lair"]:
			_room(theme, "stairs_ramp", "stairs", R.STAIRS, Vector3i(2, 2, 4), [[0, 0, 0], [2, 1, 1]], {"door_tags": tags, "extras": _stairs_ramp})
		if theme in ["fort", "crypt", "ruin"]:
			_room(theme, "gallery_hall", "gallery", R.HALL, Vector3i(3, 2, 3), [[0, 1, 0], [2, 1, 0], [1, 1, 1], [3, 1, 1]], {"door_tags": tags, "extras": _gallery, "max": 1})
	# the templates: one per role, to copy
	_room("fort", "template_room", "", R.ROOM, Vector3i(2, 1, 2), [[0, 0], [2, 1]], {"also": ["template"]})
	_save_template("template_room")
	_room("fort", "template_corridor", "corridor", R.CORRIDOR, Vector3i(1, 1, 2), [[0, 0], [2, 0]], {"also": ["template"]})
	_save_template("template_corridor")


# Templates are written into templates/ (the fort copy is removed again)
func _save_template(file: String) -> void:
	var src := MOD_DIR + "fort/" + file + ".tscn"
	var dst := MOD_DIR + "templates/" + file.trim_prefix("template_") + ".tscn"
	if ResourceLoader.exists(src):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MOD_DIR + "templates"))
		if not ResourceLoader.exists(dst) or force:
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(src))


# A slope you can walk (the player body can't climb tall step boxes): an invisible tilted box,
# from (z0, y0) to (z1, y1), as wide as w
func _ramp(holder: Node3D, room: RoomModule, w: float, z0: float, y0: float, z1: float, y1: float, mat: String, visible_slope: bool) -> void:
	var run := z1 - z0
	var rise := y1 - y0
	var length := sqrt(run * run + rise * rise)
	var body := StaticBody3D.new()
	body.name = "Ramp"
	holder.add_child(body)
	body.owner = room
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 0.2, length)
	shape.shape = bs
	body.add_child(shape)
	shape.owner = room
	if visible_slope:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var bm := BoxMesh.new()
		bm.size = bs.size
		mi.mesh = bm
		mi.material_override = InteriorKit.material(mat)
		body.add_child(mi)
		mi.owner = room
	body.position = Vector3(0, (y0 + y1) * 0.5 - 0.1, (z0 + z1) * 0.5)
	body.rotation.x = -atan2(rise, run)


# Steps up across the two middle cells to a landing over the back cell (32 degrees: walkable)
func _stairs_straight(room: RoomModule, theme: String) -> void:
	var b := room.bounds()
	var holder := Node3D.new()
	holder.name = "Stairs"
	room.add_child(holder)
	holder.owner = room
	var z0 := -b.size.z * 0.5 + RoomModule.CELL
	var z1 := b.size.z * 0.5 - RoomModule.CELL
	var steps := 16
	var w := b.size.x - InteriorKit.WALL * 2
	for i in steps:
		var h := RoomModule.LEVEL * (i + 1) / steps
		InteriorKit.box(holder, "Step%d" % i, Vector3(w, h, (z1 - z0) / steps), Vector3(0, h * 0.5, z0 + (z1 - z0) * (i + 0.5) / steps), InteriorKit.surface(theme, "floor"), room, false)
	_ramp(holder, room, w, z0, 0.0, z1, RoomModule.LEVEL, "", false)
	InteriorKit.box(holder, "Landing", Vector3(b.size.x, InteriorKit.SLAB, RoomModule.CELL), Vector3(0, RoomModule.LEVEL - InteriorKit.SLAB * 0.5, b.size.z * 0.5 - RoomModule.CELL * 0.5), InteriorKit.surface(theme, "floor"), room)


# A ladder up the middle wall to a landing over the back cell
func _stairs_ladder(room: RoomModule, theme: String) -> void:
	var b := room.bounds()
	var holder := Node3D.new()
	holder.name = "LadderUp"
	room.add_child(holder)
	holder.owner = room
	InteriorKit.box(holder, "Landing", Vector3(b.size.x, InteriorKit.SLAB, RoomModule.CELL), Vector3(0, RoomModule.LEVEL - InteriorKit.SLAB * 0.5, b.size.z * 0.5 - RoomModule.CELL * 0.5), InteriorKit.surface(theme, "floor"), room)
	InteriorKit.box(holder, "LandingFace", Vector3(b.size.x, RoomModule.LEVEL - 0.3, 0.3), Vector3(0, (RoomModule.LEVEL - 0.3) * 0.5, 0.15), InteriorKit.surface(theme, "wall"), room)
	for i in 10:
		InteriorKit.box(holder, "Rung%d" % i, Vector3(0.8, 0.06, 0.06), Vector3(0, 0.45 + i * 0.5, -0.12), "wood", room, false)
	InteriorKit.box(holder, "RailL", Vector3(0.08, RoomModule.LEVEL + 0.4, 0.08), Vector3(-0.42, (RoomModule.LEVEL + 0.4) * 0.5, -0.12), "wood", room, false)
	InteriorKit.box(holder, "RailR", Vector3(0.08, RoomModule.LEVEL + 0.4, 0.08), Vector3(0.42, (RoomModule.LEVEL + 0.4) * 0.5, -0.12), "wood", room, false)
	var ladder := Ladder.new()
	ladder.name = "Ladder"
	ladder.height = RoomModule.LEVEL
	holder.add_child(ladder)
	ladder.owner = room
	ladder.position = Vector3(0, 0, -0.5)
	ladder.rotation.y = PI  # its -Z faces the landing


# A wide rough slope of rock up to the next floor (caves and mines)
func _stairs_ramp(room: RoomModule, theme: String) -> void:
	var b := room.bounds()
	var holder := Node3D.new()
	holder.name = "Slope"
	room.add_child(holder)
	holder.owner = room
	var z0 := -b.size.z * 0.5 + RoomModule.CELL
	var z1 := b.size.z * 0.5 - RoomModule.CELL
	_ramp(holder, room, b.size.x - InteriorKit.WALL * 2, z0, 0.0, z1, RoomModule.LEVEL, InteriorKit.surface(theme, "floor"), true)
	InteriorKit.box(holder, "Landing", Vector3(b.size.x, InteriorKit.SLAB, RoomModule.CELL), Vector3(0, RoomModule.LEVEL - InteriorKit.SLAB * 0.5, b.size.z * 0.5 - RoomModule.CELL * 0.5), InteriorKit.surface(theme, "floor"), room)


# A two-storey hall with a gallery round the upper floor (doorways up there on the sides)
func _gallery(room: RoomModule, theme: String) -> void:
	var b := room.bounds()
	var holder := Node3D.new()
	holder.name = "Gallery"
	room.add_child(holder)
	holder.owner = room
	var w := 1.8
	var y := RoomModule.LEVEL - InteriorKit.SLAB * 0.5
	var trim := InteriorKit.surface(theme, "trim")
	var floor := InteriorKit.surface(theme, "floor")
	InteriorKit.box(holder, "WalkN", Vector3(b.size.x, InteriorKit.SLAB, w), Vector3(0, y, -b.size.z * 0.5 + w * 0.5), floor, room)
	InteriorKit.box(holder, "WalkS", Vector3(b.size.x, InteriorKit.SLAB, w), Vector3(0, y, b.size.z * 0.5 - w * 0.5), floor, room)
	InteriorKit.box(holder, "WalkW", Vector3(w, InteriorKit.SLAB, b.size.z - w * 2), Vector3(-b.size.x * 0.5 + w * 0.5, y, 0), floor, room)
	InteriorKit.box(holder, "WalkE", Vector3(w, InteriorKit.SLAB, b.size.z - w * 2), Vector3(b.size.x * 0.5 - w * 0.5, y, 0), floor, room)
	InteriorKit.box(holder, "RailN", Vector3(b.size.x - w * 2, 1.0, 0.15), Vector3(0, RoomModule.LEVEL + 0.5, -b.size.z * 0.5 + w), trim, room)
	InteriorKit.box(holder, "RailS", Vector3(b.size.x - w * 2, 1.0, 0.15), Vector3(0, RoomModule.LEVEL + 0.5, b.size.z * 0.5 - w), trim, room)
	InteriorKit.box(holder, "RailW", Vector3(0.15, 1.0, b.size.z - w * 2), Vector3(-b.size.x * 0.5 + w, RoomModule.LEVEL + 0.5, 0), trim, room)
	InteriorKit.box(holder, "RailE", Vector3(0.15, 1.0, b.size.z - w * 2), Vector3(b.size.x * 0.5 - w, RoomModule.LEVEL + 0.5, 0), trim, room)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			InteriorKit.box(holder, "Post%d%d" % [sx + 1, sz + 1], Vector3(0.6, RoomModule.LEVEL, 0.6), Vector3(sx * (b.size.x * 0.5 - w), RoomModule.LEVEL * 0.5, sz * (b.size.z * 0.5 - w)), trim, room)
	# up on the gallery: archers waiting to shoot down at whoever comes in (InteriorNav springs them)
	for side: float in [-1.0, 1.0]:
		_socket(room, S.ENEMY, ["ambush", "archer"], Vector3(side * (b.size.x * 0.5 - w * 0.5), RoomModule.LEVEL, 1.5), -side * PI * 0.5, 0.6, 1)
