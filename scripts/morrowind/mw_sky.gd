class_name MwSky
extends RefCounted
## Morrowind's skies: its cloud picture for each kind of weather and its night sky of stars and
## nebulae, converted from your copy by MwImport into the models folder ("textures/sky_*.res").
## WorldClock hands them to shaders/sky.gdshader when they are there; without them the sky's
## own drawn clouds and stars stay.

## Weather -> Morrowind's sky texture
const WEATHER := {
	Weather.Kind.CLEAR: "tx_sky_clear", Weather.Kind.CLOUDY: "tx_sky_cloudy", Weather.Kind.OVERCAST: "tx_sky_overcast",
	Weather.Kind.RAIN: "tx_sky_rainy", Weather.Kind.STORM: "tx_sky_thunder", Weather.Kind.SNOW: "tx_sky_overcast",
	Weather.Kind.BLIZZARD: "tx_sky_stormy", Weather.Kind.FOG: "tx_sky_foggy", Weather.Kind.SANDSTORM: "tx_sky_ashstorm",
}
const STARS := "tx_stars"
const NEBULA := "tx_stars_nebula"

static var _cache := {}


## Converts the sky textures (MwImport calls this); returns how many it made
static func convert(data: MwData, dir: String) -> int:
	var n := 0
	var names: Array = WEATHER.values().duplicate()
	names.append_array([STARS, NEBULA])
	for name in names:
		var tex := data.texture(String(name) + ".tga")
		if tex == null:
			continue
		var p := dir.path_join("sky_%s.res" % name)
		if ResourceSaver.save(tex, p, ResourceSaver.FLAG_COMPRESS) == OK:
			n += 1
	_cache.clear()
	return n


## A converted sky texture, or null
static func texture(name: String) -> Texture2D:
	if not _cache.has(name):
		var p := ProjectSettings.globalize_path("user://models/textures").path_join("sky_%s.res" % name)
		_cache[name] = ResourceLoader.load(p) as Texture2D if FileAccess.file_exists(p) else null
	return _cache[name]


static func forget() -> void:
	_cache.clear()
