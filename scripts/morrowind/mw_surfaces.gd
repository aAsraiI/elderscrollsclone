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
	"mw_rock": ["tx_rock_grey_01", "tx_rocky_mt", "tx_rock_brown_02"],
	# Built things: two of each, blended across a wall so no single texture repeats
	"mw_stone": ["tx_stoneshaft00", "tx_stonewall00", "tx_imp_wall_02"],
	"mw_stone2": ["tx_wg_cobblestones_01", "tx_stone_bluegrey", "tx_imp_wall_01"],
	"mw_wood": ["tx_wood_brown_posts_01", "tx_wood_brown_plank_01"],
	"mw_wood2": ["tx_wood_brown_posts_02", "tx_wood_blackwood"],
	"mw_plaster": ["tx_hlaalu_wall2_02", "tx_stone_adobe_01"],
	"mw_plaster2": ["tx_hlaalu_wall2_01", "tx_hlaalu_wall2_03"],
}
## Interior material (data/interiors/materials) -> Morrowind texture
const KIT := {
	"stone": ["tx_stoneshaft00", "tx_stonewall00"],
	"stone_dark": ["tx_stone_bluegrey", "tx_stone_darkgrey_01"],
	"brick": ["tx_wg_cobblestones_01", "tx_imp_block_01"],
	"plaster": ["tx_hlaalu_wall2_02", "tx_stone_adobe_01"],
	"wood": ["tx_wood_brown_posts_01", "tx_wood_brown_plank_01"],
	"wood_dark": ["tx_wood_blackwood", "tx_wood_brown_posts_02"],
	"wood_floor": ["tx_wood_brown_posts_02", "tx_wood_brown_plank_01"],
	"flagstone": ["tx_wg_cobblestones_01", "tx_imp_plaza_02"],
	"rock": ["tx_rock_cave_mu_01", "tx_rocky_mt", "tx_rock_cave_b_01"],
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
				if tex != null and table == KIT:
					tex = _soften(tex, 0.6)
				if tex != null:
					if ResourceSaver.save(tex, dir.path_join("surface_%s.res" % key), ResourceSaver.FLAG_COMPRESS) == OK:
						n += 1
					break
	forget()
	return n


# Morrowind's textures carry their own colour, and were made for its flat lighting: under ours their light
# and dark patches turn into camouflage. Made nearly grey (a little of their hue left) around 0.8, with
# the light and dark pulled part way in, so a material's own colour shows through with the grain on it.
static func _soften(tex: Texture2D, keep: float) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var sum := Color(0, 0, 0, 0)
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y)
	var mean := sum / float(img.get_width() * img.get_height())
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var d := Color(c.r / maxf(mean.r, 0.03), c.g / maxf(mean.g, 0.03), c.b / maxf(mean.b, 0.03))
			var l := (d.r + d.g + d.b) / 3.0
			var v := Color(l, l, l).lerp(d, 0.3)
			v = Color(1, 1, 1).lerp(v, keep) * 0.8
			img.set_pixel(x, y, Color(clampf(v.r, 0.0, 1.0), clampf(v.g, 0.0, 1.0), clampf(v.b, 0.0, 1.0), c.a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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
		if t == null and g.ends_with("2"):
			t = texture(g.trim_suffix("2"))  # an older import with no second texture: the first one twice
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
	m.albedo_color = m.albedo_color * 1.25  # the material keeps its own colour; the texture (grey, about 0.8) brings the grain
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Broad soft patches of light and dark over it, much larger than one tile, so the repeat never lines up
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_albedo = _patches()
	m.uv2_triplanar = true
	m.uv2_world_triplanar = true
	m.uv2_scale = Vector3.ONE * 0.07


static var _patch_tex: Texture2D


static func _patches() -> Texture2D:
	if _patch_tex == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 3
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 256
		t.height = 256
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.72, 0.7, 0.68))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = ramp
		_patch_tex = t
	return _patch_tex
