extends "res://tools/build_interiors.gd"
## The hand-made side of Alpha 1.13 (all yours to finish in the editor afterwards):
##   set-pieces      unique rooms pinned into random dungeons (scenes/interiors/setpieces/), added
##                   to their recipes' Set Pieces
##   the Codex vault the main quest's dungeon, baked from the crypt recipe
##                   (scenes/interiors/handmade/codex_vault.tscn)
##   lords' halls    a hall of its own for every named seat but Castle Dawnhold
##                   (scenes/interiors/handmade/seat_<town>.tscn), listed in InteriorOverrides
## Scenes that exist are kept (hand edits are safe); pass --force to make them again.
##   godot --headless --path . -s res://tools/build_handmade.gd [-- --force]

const SET_DIR := "res://scenes/interiors/setpieces/"
const HAND_DIR := "res://scenes/interiors/handmade/"
const CODEX_VAULT := HAND_DIR + "codex_vault.tscn"
const R := RoomModule.Role

## Which recipes get which set-pieces
const PINS := {
	"fort": ["war_council"], "bandit_hideout": ["war_council"], "fort_over_crypt": ["war_council", "kings_tomb"], "crypt": ["kings_tomb"],
	"cave": ["glow_grotto"], "ruin": ["fallen_library"], "mine": ["glow_grotto"],
}


func _initialize() -> void:
	force = OS.get_cmdline_user_args().has("--force")
	InteriorKit.save_materials()
	_set_pieces()
	ModuleLibrary.reload()
	_pin()
	if force or not ResourceLoader.exists(CODEX_VAULT):
		var err := DungeonPreview.bake_to(load("res://data/interiors/recipes/crypt.tres") as DungeonRecipe, 1337, 20, CODEX_VAULT)
		print("build_handmade: Codex vault baked (%d)" % err)
		made += 1
	_seats()
	print("build_handmade: %d scenes made, %d kept as they were" % [made, kept])
	quit()


# ---------------------------------------------------------------- set-pieces

func _set_pieces() -> void:
	# a fort's war council: the great map, the captain's high seat, banners and the war chest
	_room("fort", "war_council", "war_room", R.ROOM, Vector3i(3, 1, 3), [[0, 1], [2, 1], [1, 1]], {"path": SET_DIR + "war_council.tscn", "max": 1, "extras": _sp_war_council})
	# a crypt's royal tomb: a ring of sarcophagi round the old king's, an altar and his grave goods
	_room("crypt", "kings_tomb", "burial_hall", R.ROOM, Vector3i(3, 1, 3), [[0, 1], [1, 1], [3, 1]], {"path": SET_DIR + "kings_tomb.tscn", "max": 1, "extras": _sp_kings_tomb})
	# a glowing grotto: pools, crystals and fungus light, someone's lost pack
	_room("cave", "glow_grotto", "cavern", R.ROOM, Vector3i(3, 1, 3), [[0, 1], [2, 1], [3, 0]], {"path": SET_DIR + "glow_grotto.tscn", "max": 1, "extras": _sp_glow_grotto})
	# a ruin's fallen library: toppled shelves, rubble, a reading desk that still holds something
	_room("ruin", "fallen_library", "library", R.ROOM, Vector3i(3, 1, 3), [[0, 1], [1, 1], [2, 1]], {"path": SET_DIR + "fallen_library.tscn", "max": 1, "extras": _sp_fallen_library})


# Puts the set-pieces in their recipes (kept if a recipe already lists one)
func _pin() -> void:
	for f in DirAccess.get_files_at("res://data/interiors/recipes/"):
		var key := f.get_basename()
		if not PINS.has(key):
			continue
		var path := "res://data/interiors/recipes/" + f
		var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as DungeonRecipe
		if r == null or (not r.set_pieces.is_empty() and not force):
			continue
		var list: Array[PackedScene] = []
		for n: String in PINS[key]:
			list.append(load(SET_DIR + n + ".tscn") as PackedScene)
		r.set_pieces = list
		ResourceSaver.save(r, path)
		print("build_handmade: %s gets %s" % [key, ", ".join(PINS[key])])


# ---------------------------------------------------------------- lords' halls

# A hall of its own for every named keep and castle (not Dawnhold, which is hand-built already):
# the seat scene with the house's carpet down the middle, more statues and its own trophies
func _seats() -> void:
	var o := ResourceLoader.load(InteriorOverrides.PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as InteriorOverrides if ResourceLoader.exists(InteriorOverrides.PATH) else InteriorOverrides.new()
	var n := 0
	for biome: String in NamedSettlements.LIST:
		for s: Dictionary in NamedSettlements.LIST[biome]:
			if String(s["seat"]) == "reeve" or String(s["hall"]) == InteriorBuilder.DAWNHOLD:
				continue
			var file := "seat_" + String(s["name"]).to_snake_case().replace("'", "")
			var path := HAND_DIR + file + ".tscn"
			o.buildings["%s/%s" % [s["name"], s["hall"]]] = null
			if force or not ResourceLoader.exists(path):
				_seat_scene(path, s, n)
			o.buildings["%s/%s" % [s["name"], s["hall"]]] = load(path) as PackedScene
			n += 1
	ResourceSaver.save(o, InteriorOverrides.PATH)


func _seat_scene(path: String, s: Dictionary, n: int) -> void:
	var base := "res://scenes/interiors/houses/seat_b.tscn" if String(s["seat"]) == "castle" else "res://scenes/interiors/houses/seat_a.tscn"
	var room := (load(base) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED) as RoomModule
	room.name = String(s["hall"]).to_pascal_case().replace("'", "")
	var b := room.bounds()
	var hz := b.size.z * 0.5
	var ground := RoomModule.LEVEL
	var carpet: String = ["cloth_red", "cloth_blue", "cloth_red", "cloth_blue"][n % 4]
	InteriorKit.box(room, "Carpet", Vector3(1.6, 0.02, b.size.z - 4.0), Vector3(0, ground + 0.01, -1.0), carpet, room, false)
	var extras := Node3D.new()
	extras.name = "HallExtras"
	room.add_child(extras)
	extras.owner = room
	for side: float in [-1.0, 1.0]:
		_socket(room, S.FURNITURE, ["statue"], Vector3(side * 3.4, ground, hz - 4.2), 0.0, 1.0, 1)
		_socket(room, S.WALL_DECORATION, ["tapestry", "banner_blue", "banner"], Vector3(side * (b.size.x * 0.5 - 0.45), ground, 3.0), side * PI * 0.5, 1.0, 1)
		_socket(room, S.LIGHT, ["brazier"], Vector3(side * 2.2, ground, -3.0), 0.0, 1.0, 1)
	if String(s["seat"]) == "castle":
		_socket(room, S.FURNITURE, ["armor"], Vector3(-2.0, ground, hz - 0.8), 0.0, 1.0, 1)
		_socket(room, S.FURNITURE, ["armor"], Vector3(2.0, ground, hz - 0.8), 0.0, 1.0, 1)
	_save(room, path)


func _sp_war_council(room: RoomModule, _theme: String) -> void:
	_socket(room, S.FURNITURE, ["throne"], Vector3(0, 0, 4.6), 0.0, 1.0, 1)
	for side: float in [-1.0, 1.0]:
		_socket(room, S.FURNITURE, ["statue", "armor"], Vector3(side * 4.4, 0, 4.4), 0.0, 1.0, 1)
		_socket(room, S.WALL_DECORATION, ["banner"], Vector3(side * 2.4, 0, 5.55), 0.0, 1.0, 1)
		_socket(room, S.LIGHT, ["brazier"], Vector3(side * 3.0, 0, -3.0), 0.0, 1.0, 1)
	_socket(room, S.CHEST, ["war_chest"], Vector3(4.6, 0, 2.0), PI * 0.5, 1.0, 1)
	_socket(room, S.ENEMY, ["officer"], Vector3(0, 0, 3.2), PI, 1.0, 2)


func _sp_kings_tomb(room: RoomModule, _theme: String) -> void:
	_socket(room, S.FURNITURE, ["sarcophagus", "set"], Vector3(0, 0, 0.5), 0.0, 1.0, 1)
	for i in 6:
		var a := TAU * i / 6.0
		_socket(room, S.FURNITURE, ["sarcophagus", "set"], Vector3(cos(a) * 3.8, 0, 0.5 + sin(a) * 3.8), -a + PI * 0.5, 0.9, 1)
	_socket(room, S.FURNITURE, ["altar"], Vector3(0, 0, 5.0), 0.0, 1.0, 1)
	_socket(room, S.LOOT, ["grave_goods"], Vector3(0, 1.0, 5.0), 0.0, 1.0, 1)
	_socket(room, S.CHEST, ["tomb"], Vector3(-4.6, 0, 4.6), PI * 0.75, 1.0, 1)
	_socket(room, S.ENEMY, ["guardian"], Vector3(0, 0, 2.6), PI, 1.0, 2)


func _sp_glow_grotto(room: RoomModule, _theme: String) -> void:
	for i in 8:
		var a := TAU * i / 8.0
		_socket(room, S.LIGHT, ["crystal", "fungus", "set"], Vector3(cos(a) * 4.0, 0, sin(a) * 4.0), a, 1.0, 1)
	for p: Vector3 in [Vector3(-1.5, 0, 0.5), Vector3(1.4, 0, -0.8), Vector3(0.2, 0, 1.9)]:
		_socket(room, S.DECORATION, ["water", "set"], p, 0.4, 1.0, 1)
	_socket(room, S.LOOT, ["lost_pack"], Vector3(2.2, 0, 2.6), 0.0, 1.0, 1)
	_socket(room, S.DECORATION, ["bones", "set"], Vector3(2.6, 0, 2.2), 0.0, 1.0, 1)
	_socket(room, S.ENEMY, [], Vector3(-2.0, 0, -2.0), 0.0, 0.8, 2)


func _sp_fallen_library(room: RoomModule, _theme: String) -> void:
	for i in 4:
		_socket(room, S.FURNITURE, ["bookshelf", "set"], Vector3(-3.6 + i * 2.4, 0, 5.55), 0.0, 1.0, 1)
		_socket(room, S.DECORATION, ["rubble", "broken_pillar", "set"], Vector3(-3.6 + i * 2.4, 0, -2.0 + (i % 2) * 1.5), i * 0.7, 0.8, 1)
	_socket(room, S.FURNITURE, ["table", "set"], Vector3(0, 0, 2.0), 0.0, 1.0, 1)
	_socket(room, S.LOOT, ["book"], Vector3(0, 0.82, 2.0), 0.0, 1.0, 1)
	_socket(room, S.LIGHT, ["candle", "set"], Vector3(0.6, 0.82, 2.1), 0.0, 1.0, 1)
	_socket(room, S.ENEMY, [], Vector3(2.4, 0, 0.0), 0.0, 0.8, 2)
