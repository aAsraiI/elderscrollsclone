class_name MwSurfaces
extends RefCounted
## Morrowind's surfaces from your copy: grass, earth and rock for the land (shaders/terrain.gdshader),
## stone, wood and plaster for everything built (shaders/built.gdshader), both through the project's
## shader globals, and the textured walls, floors and cave rock of interiors (InteriorKit materials).
## MwImport converts them into the models folder; apply() switches them on when the game starts.

## Shader global -> Morrowind texture (tried in order)
const GLOBALS := {
	"mw_grass": ["tx_ai_grass_01", "tx_gl_grass_01", "tx_grass_01"],
	"mw_earth": ["tx_ai_dirt_01", "tx_gl_dirt_01", "tx_ac_dirt_01"],
	"mw_rock": ["tx_rocky_mt", "tx_rock_brown_02", "tx_rock_grey_01"],
	"mw_stone": ["tx_imp_wall_01", "tx_stonewall00", "tx_stone_plain_01"],
	"mw_wood": ["tx_wood_brown_plank_01", "tx_wood"],
	"mw_plaster": ["tx_stone_adobe_01", "tx_imp_plain_01"],
}
## Interior material (data/interiors/materials) -> Morrowind texture
const KIT := {
	"stone": ["tx_imp_wall_01", "tx_stonewall00"],
	"stone_dark": ["tx_stone_darkgrey_01", "tx_stone_bluegrey"],
	"brick": ["tx_imp_block_01", "tx_imp_block_02"],
	"plaster": ["tx_stone_adobe_01", "tx_imp_plain_01"],
	"wood": ["tx_wood_brown_plank_01", "tx_wood"],
	"wood_dark": ["tx_wood_blackwood", "tx_wood_brown_block"],
	"wood_floor": ["tx_wood_brown_plank_01", "tx_imp_floor_01"],
	"flagstone": ["tx_imp_plaza_02", "tx_imp_floor_01", "tx_cobblestone_01"],
	"rock": ["tx_rock_cave_b_01", "tx_rock_cave_l_01"],
	"rock_dark": ["tx_rock_cave_mu_01", "tx_rock_cave_mo_01"],
	"moss_stone": ["tx_bc_moss_01", "tx_bc_moss"],
	"ash": ["tx_ac_dirt_01"],
}

static var _cache := {}
static var _applied := false


static func _dir() -> String:
	return ProjectSettings.globalize_path("user://models/textures")


## Converts the surfaces (MwImport calls this); returns how many it made
static func convert(data: MwData, dir: String) -> int:
	var n := 0
	for table: Dictionary in [GLOBALS, KIT]:
		for key in table:
			for name in table[key]:
				var tex := data.texture(String(name) + ".tga")
				if tex != null:
					if ResourceSaver.save(tex, dir.path_join("surface_%s.res" % key), ResourceSaver.FLAG_COMPRESS) == OK:
						n += 1
					break
	forget()
	return n


static func texture(key: String) -> Texture2D:
	if not _cache.has(key):
		var p := _dir().path_join("surface_%s.res" % key)
		_cache[key] = ResourceLoader.load(p) as Texture2D if FileAccess.file_exists(p) else null
	return _cache[key]


static func forget() -> void:
	_cache.clear()
	_applied = false


## Turns Morrowind's surfaces on (or off when they are not imported). Called when a world starts.
static func apply() -> void:
	if _applied:
		return
	_applied = true
	var on := texture("mw_grass") != null and texture("mw_stone") != null
	RenderingServer.global_shader_parameter_set("mw_surfaces", on)
	for g in GLOBALS:
		var t := texture(g)
		if t != null:
			RenderingServer.global_shader_parameter_set(g, t)
	# The interior materials every room shares: changed where they are loaded (never saved), so walls,
	# floors and cave rock in every interior scene take Morrowind's look
	for name in KIT:
		var path := "res://data/interiors/materials/%s.tres" % name
		if ResourceLoader.exists(path):
			dress_material(name, load(path) as StandardMaterial3D)


## The Morrowind look for an interior material: its texture projected from the three axes, so the
## boxes need no UVs. Leaves the material alone when there is none.
static func dress_material(name: String, m: StandardMaterial3D) -> void:
	var t := texture(name) if KIT.has(name) else null
	if t == null or m == null:
		return
	m.albedo_texture = t
	m.albedo_color = m.albedo_color.lerp(Color(1, 1, 1), 0.7) * 1.15
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
