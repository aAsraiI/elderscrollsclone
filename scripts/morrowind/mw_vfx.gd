class_name MwVfx
extends RefCounted
## Morrowind's spell and blood textures (1.18): the sparks, flares, glows and clouds its magic is drawn
## with, and its blood, converted from your own copy into your models folder (MwImport) and used by
## SpellFX and HitFX for their particles. Without them the particles are plain glowing squares.

## Each look (an element, or a school) -> [the glow at its heart, the sparks it throws, a cloud or flare]
const LOOKS := {
	&"fire": ["vfx_fireglow", "vfx_firealpha01", "vfx_firecloud"],
	&"frost": ["vfx_frostflare", "vfx_icestar", "vfx_frostblast"],
	&"shock": ["vfx_electricblue", "vfx_lightningspark", "vfx_electric"],
	&"poison": ["vfx_poisonglow", "vfx_poison", "vfx_poisoncloud01"],
	&"magic": ["vfx_myst_glow", "vfx_purplelite", "vfx_purplehaze"],
	&"destruction": ["vfx_redglow", "vfx_spark", "vfx_flare01"],
	&"restoration": ["vfx_restore_glow", "vfx_rest_glow", "vfx_restore_light"],
	&"alteration": ["vfx_alt_glow", "vfx_alt_star", "vfx_alt_envir"],
	&"conjuration": ["vfx_conj_flare", "vfx_summon_glow", "vfx_conjure"],
	&"illusion": ["vfx_ill_glow", "vfx_ill_flare01", "vfx_purplehaze"],
	&"mysticism": ["vfx_myst_glow", "vfx_mystflare", "vfx_myst_hotflare"],
}
const BLOOD := ["tx_blood", "tx_blood_white", "tx_blood_gold"]
const EXTRA := ["vfx_starglow", "vfx_flare02", "vfx_alpha_spark", "vfx_smokealpha00a"]

static var _cache := {}


static func convert(data: MwData, dir: String) -> int:
	var names := {}
	for look in LOOKS.values():
		for n in look:
			names[n] = true
	for n in BLOOD + EXTRA:
		names[n] = true
	var made := 0
	for name in names:
		var tex := data.texture(String(name) + ".dds")
		if tex == null:
			continue
		if String(name).begins_with("vfx_"):
			tex = _round(tex)
		if ResourceSaver.save(tex, dir.path_join("vfx_%s.res" % name), ResourceSaver.FLAG_COMPRESS) == OK:
			made += 1
	_cache.clear()
	return made


# Morrowind draws many of these across whole particle quads or tiles them over shells; as sprites they
# would show their square edges, so each fades out softly toward a round rim (and to black, for adding)
static func _round(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var r := Vector2((x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5).length() * 2.0
			var f := pow(clampf(1.0 - r, 0.0, 1.0), 1.4)
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f, c.a * f))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A converted texture by its Morrowind name ("vfx_fireglow"), or null
static func texture(name: String) -> Texture2D:
	if not _cache.has(name):
		var p := ProjectSettings.globalize_path("user://models/textures").path_join("vfx_%s.res" % name)
		_cache[name] = ResourceLoader.load(p) as Texture2D if FileAccess.file_exists(p) else null
	return _cache[name]


## [glow, sparks, cloud] for a look, each a texture or null
static func look(id: StringName) -> Array:
	var names: Array = LOOKS.get(id, LOOKS[&"destruction"])
	return [texture(names[0]), texture(names[1]), texture(names[2])]


static func forget() -> void:
	_cache.clear()
