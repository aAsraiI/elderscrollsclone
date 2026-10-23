class_name Weather
extends Node
## Rain, snow, storms, fog and sandstorms. Created by WorldManager (group "weather").
## The weather is rolled every few hours from the climate of the land you are in (BiomeData
## .get_climate) and the season (WorldClock), and blends smoothly into the next. WorldClock asks
## factors() each time it lights the sky, so clouds dim the sun, storms darken the day and fog
## closes in. Rain and snow are particles around the camera (not inside buildings or dungeons).
## Rain makes fire spells weaker and lightning stronger (WET_MULT); snow piles up on the ground.

enum Kind { CLEAR, CLOUDY, OVERCAST, RAIN, STORM, SNOW, BLIZZARD, FOG, SANDSTORM }

const NAMES: Array[String] = ["Clear", "Cloudy", "Overcast", "Rain", "Thunderstorm", "Snow", "Blizzard", "Fog", "Sandstorm"]
## Damage multipliers for magic that hits someone standing in the rain
const WET_MULT := {&"fire": 0.75, &"shock": 1.25}
## sun, sky, ambient, fog (density x), fog_tint, cloud (sky greyness), wind
const LOOK := {
	Kind.CLEAR: [1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.6],
	Kind.CLOUDY: [0.8, 0.85, 0.95, 1.2, 0.15, 0.35, 0.9],
	Kind.OVERCAST: [0.45, 0.6, 0.8, 1.8, 0.35, 0.75, 1.1],
	Kind.RAIN: [0.3, 0.45, 0.7, 2.6, 0.5, 0.85, 1.4],
	Kind.STORM: [0.15, 0.3, 0.55, 3.2, 0.6, 1.0, 2.0],
	Kind.SNOW: [0.45, 0.6, 0.85, 3.0, 0.55, 0.7, 0.9],
	Kind.BLIZZARD: [0.2, 0.4, 0.7, 7.0, 0.85, 0.95, 2.0],
	Kind.FOG: [0.55, 0.7, 0.85, 7.5, 0.8, 0.5, 0.3],
	Kind.SANDSTORM: [0.4, 0.55, 0.8, 8.0, 0.9, 0.6, 2.0],
}
const FOG_COLORS := {Kind.SANDSTORM: Color(0.75, 0.6, 0.4), Kind.FOG: Color(0.75, 0.78, 0.8), Kind.BLIZZARD: Color(0.85, 0.88, 0.92)}
## Chances per climate and season (winter turns rain into snow outside the desert)
const TABLE := {
	"temperate": {Kind.CLEAR: 34, Kind.CLOUDY: 24, Kind.OVERCAST: 12, Kind.RAIN: 15, Kind.STORM: 6, Kind.FOG: 9},
	"wet": {Kind.CLEAR: 18, Kind.CLOUDY: 20, Kind.OVERCAST: 16, Kind.RAIN: 26, Kind.STORM: 10, Kind.FOG: 10},
	"cold": {Kind.CLEAR: 26, Kind.CLOUDY: 20, Kind.OVERCAST: 14, Kind.SNOW: 30, Kind.BLIZZARD: 10},
	"arid": {Kind.CLEAR: 62, Kind.CLOUDY: 15, Kind.OVERCAST: 5, Kind.SANDSTORM: 14, Kind.RAIN: 4},
}

signal weather_changed(kind: int)

var enabled := true
var current: Kind = Kind.CLEAR
var previous: Kind = Kind.CLEAR
## 0..1 how far the change from previous to current has gone
var blend := 1.0
var hours_left := 4.0
## 0..1 snow lying on the ground (builds up in snow, melts otherwise)
var snow_cover := 0.0
var wetness := 0.0

var _climate := "temperate"
var _rig: Node3D
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _sand: GPUParticles3D
var _flash := 0.0
var _next_flash := 8.0
var _sky_base := {}
var _check := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()
	_build_particles()


## How the weather changes the light right now (WorldClock uses it)
static func factors(tree: SceneTree) -> Dictionary:
	if tree == null:
		return {}
	var w := tree.get_first_node_in_group("weather") as Weather
	if w == null or not w.enabled:
		return {}
	return w.get_factors()


## Is this body standing out in the rain?
static func is_wet_at(body: Node) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var w := body.get_tree().get_first_node_in_group("weather") as Weather
	if w == null or not w.enabled or not (w.current == Kind.RAIN or w.current == Kind.STORM) or w.blend < 0.5:
		return false
	var dm := body.get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	return dm == null or not dm.is_inside()


static func get_instance(tree: SceneTree) -> Weather:
	return tree.get_first_node_in_group("weather") as Weather if tree != null else null


func get_name_text() -> String:
	return NAMES[current]


func is_precipitating() -> bool:
	return current in [Kind.RAIN, Kind.STORM, Kind.SNOW, Kind.BLIZZARD]


func get_factors() -> Dictionary:
	var a: Array = LOOK[previous]
	var b: Array = LOOK[current]
	var t := blend
	var out := {
		"sun": lerpf(a[0], b[0], t), "sky": lerpf(a[1], b[1], t), "ambient": lerpf(a[2], b[2], t),
		"fog": lerpf(a[3], b[3], t), "fog_tint": lerpf(a[4], b[4], t), "flash": _flash,
		"fog_color": FOG_COLORS.get(current, Color(0.6, 0.63, 0.68)),
	}
	if _inside():
		return {"flash": 0.0}
	return out


## Sets the weather at once (debug, loading)
func set_weather(kind: Kind, hours: float = 4.0) -> void:
	previous = kind
	current = kind
	blend = 1.0
	hours_left = hours
	weather_changed.emit(current)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not enabled:
		_show_particles(false, false, false)
		return
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var game_hours := 0.0
	if clock != null and clock.day_length_minutes > 0.0:
		game_hours = delta * clock.time_scale * 24.0 / (clock.day_length_minutes * 60.0)
	hours_left -= game_hours
	blend = minf(blend + delta / 25.0, 1.0)  # about 25 seconds to change over
	_check -= delta
	if _check <= 0.0:
		_check = 2.0
		var c := _climate_here()
		var unfitting: bool = not TABLE[c].has(current) and not (current == Kind.SNOW and clock != null and clock.get_season() == 0)
		if c != _climate:
			_climate = c
			if unfitting:
				hours_left = 0.0  # walked into another land: its weather takes over
	if hours_left <= 0.0 and blend >= 1.0:
		_roll(clock)
	# Snow builds up, rain wets the ground
	var snowing := current == Kind.SNOW or current == Kind.BLIZZARD
	var raining := current == Kind.RAIN or current == Kind.STORM
	var season_snow := 0.0
	if clock != null and clock.get_season() == 0 and _climate != "arid":
		season_snow = 0.55
	snow_cover = move_toward(snow_cover, maxf(season_snow, 1.0 if snowing else 0.0), delta * (0.01 if snowing else 0.004))
	wetness = move_toward(wetness, 1.0 if raining else 0.0, delta * (0.03 if raining else 0.008))
	_update_lightning(delta)
	_follow_camera()
	var show := bool(GameSettings.get_value("weather_effects")) and not _inside() and blend > 0.3
	_show_particles(show and raining, show and snowing, show and current == Kind.SANDSTORM)
	if _rain != null:
		_rain.amount_ratio = 1.0 if current == Kind.STORM else 0.6
	if _snow != null:
		_snow.amount_ratio = 1.0 if current == Kind.BLIZZARD else 0.45
	_push_conditions(clock)
	_tint_sky()


func _roll(clock: WorldClock) -> void:
	var c := _climate_here()
	_climate = c
	var table: Dictionary = TABLE[c].duplicate()
	var season := clock.get_season() if clock != null else 1
	if season == 0 and c != "arid":
		table[Kind.SNOW] = int(table.get(Kind.RAIN, 0)) + int(table.get(Kind.SNOW, 0)) + 8
		table[Kind.BLIZZARD] = int(table.get(Kind.STORM, 0)) + int(table.get(Kind.BLIZZARD, 0))
		table.erase(Kind.RAIN)
		table.erase(Kind.STORM)
	elif season == 2 and c == "temperate":
		table[Kind.CLEAR] = int(table[Kind.CLEAR]) + 15
		table[Kind.STORM] = int(table[Kind.STORM]) + 3
	elif season == 3:
		table[Kind.FOG] = int(table.get(Kind.FOG, 0)) + 6
		table[Kind.RAIN] = int(table.get(Kind.RAIN, 0)) + 5
	var total := 0
	for k in table:
		total += int(table[k])
	var roll := _rng.randi_range(1, maxi(total, 1))
	var pick: Kind = Kind.CLEAR
	for k in table:
		roll -= int(table[k])
		if roll <= 0:
			pick = k
			break
	previous = current
	current = pick
	blend = 0.0 if previous != current else 1.0
	hours_left = _rng.randf_range(3.0, 9.0)
	if previous != current:
		weather_changed.emit(current)


func _climate_here() -> String:
	var world := get_parent() as WorldManager
	var cam := get_viewport().get_camera_3d()
	if world == null or cam == null or world.map == null:
		return "temperate"
	var biome := world.get_biome_at(cam.global_position.x, cam.global_position.z)
	return biome.get_climate() if biome != null else "temperate"


func _inside() -> bool:
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	return dm != null and dm.is_inside()


func _push_conditions(clock: WorldClock) -> void:
	var tint := Vector3.ONE
	if clock != null:
		var doy := clock.get_day_of_year()
		# autumn browns and golds, a pale winter, lush early summer
		var autumn := clampf(1.0 - absf(float(doy - 285)) / 45.0, 0.0, 1.0)
		var winter := clampf(1.0 - absf(float((doy + 15) % 360 - 15)) / 60.0, 0.0, 1.0)
		tint = Vector3.ONE.lerp(Vector3(1.35, 0.95, 0.45), autumn).lerp(Vector3(0.85, 0.85, 0.7), winter)
	var wind := lerpf(float(LOOK[previous][6]), float(LOOK[current][6]), blend)
	NatureMeshes.set_conditions(tint, snow_cover, wetness, wind)


# Grey clouds take over the sky in bad weather
func _tint_sky() -> void:
	var env := _find_env()
	if env == null or env.sky == null or not env.sky.sky_material is ProceduralSkyMaterial:
		return
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if _sky_base.is_empty():
		_sky_base = {"top": sky.sky_top_color, "horizon": sky.sky_horizon_color, "ground": sky.ground_horizon_color}
	var cloud := lerpf(float(LOOK[previous][5]), float(LOOK[current][5]), blend)
	if _inside():
		cloud = 0.0
	var grey := Color(0.42, 0.45, 0.5) if current != Kind.SANDSTORM else Color(0.7, 0.55, 0.38)
	sky.sky_top_color = (_sky_base["top"] as Color).lerp(grey * 0.8, cloud)
	sky.sky_horizon_color = (_sky_base["horizon"] as Color).lerp(grey, cloud)
	sky.ground_horizon_color = (_sky_base["ground"] as Color).lerp(grey, cloud * 0.7)


var _env_cache: Environment


func _find_env() -> Environment:
	if _env_cache == null:
		var envs := get_tree().root.find_children("*", "WorldEnvironment", true, false)
		if not envs.is_empty():
			_env_cache = (envs[0] as WorldEnvironment).environment
	return _env_cache


func _update_lightning(delta: float) -> void:
	_flash = maxf(_flash - delta * 6.0, 0.0)
	if current != Kind.STORM or blend < 0.6 or _inside():
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _rng.randf_range(6.0, 22.0)
		_flash = 1.6


# ---------------------------------------------------------------- particles

func _build_particles() -> void:
	_rig = Node3D.new()
	_rig.name = "WeatherRig"
	_rig.top_level = true
	add_child(_rig)
	_rain = _make(4000, 1.1, Vector3(0, -24, 0), Vector2(0.018, 0.7), Color(0.7, 0.75, 0.85, 0.45), true)
	_snow = _make(2500, 7.0, Vector3(0, -2.2, 0), Vector2(0.07, 0.07), Color(1, 1, 1, 0.9), false)
	_sand = _make(1800, 3.0, Vector3(9, -0.5, 3), Vector2(0.06, 0.06), Color(0.8, 0.65, 0.42, 0.55), false)
	(_sand.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(26, 8, 26)
	(_sand.process_material as ParticleProcessMaterial).spread = 25.0


func _make(amount: int, life: float, vel: Vector3, size: Vector2, color: Color, streak: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 1, 26)
	pm.direction = vel.normalized()
	pm.spread = 3.0 if streak else 15.0
	pm.initial_velocity_min = vel.length() * 0.9
	pm.initial_velocity_max = vel.length() * 1.1
	pm.gravity = Vector3.ZERO
	if not streak:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if streak else BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(p)
	p.position = Vector3(0, 16 if streak else 12, 0)
	return p


func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _rig != null:
		_rig.global_position = cam.global_position + (-cam.global_transform.basis.z * 6.0)


func _show_particles(rain: bool, snow: bool, sand: bool) -> void:
	if _rain != null and _rain.emitting != rain:
		_rain.emitting = rain
	if _snow != null and _snow.emitting != snow:
		_snow.emitting = snow
	if _sand != null and _sand.emitting != sand:
		_sand.emitting = sand


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {"kind": int(current), "left": hours_left, "snow": snow_cover, "wet": wetness}


func from_dict(d: Dictionary) -> void:
	set_weather(clampi(int(d.get("kind", 0)), 0, Kind.size() - 1) as Kind, float(d.get("left", 4.0)))
	snow_cover = float(d.get("snow", 0.0))
	wetness = float(d.get("wet", 0.0))
