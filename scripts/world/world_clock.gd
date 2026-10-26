class_name WorldClock
extends Node
## The time of day. Created by WorldManager (group "world_clock"), nothing to add by hand.
## Everything that depends on the hour asks this node: NPC schedules, shop hours, door locks.
## It also moves the sun, and dims the sky and ambient light at night (not inside a dungeon,
## which has its own lighting). Time stands still while a menu pauses the game.
## Debug builds: F8 = +1 hour, Shift+F8 = +6 hours, Ctrl+F8 = +30 days (a month, to see the seasons).

signal hour_changed(hour: int)
signal day_changed(day: int)
signal night_started
signal day_started

## Real minutes for one full in-game day
@export var day_length_minutes := 24.0
@export_range(0.0, 24.0, 0.25) var start_hour := 8.0
## Everyone asleep and shops closed from night_start to night_end
@export_range(0.0, 24.0, 0.25) var night_start := 21.0
@export_range(0.0, 24.0, 0.25) var night_end := 6.0
@export var sunrise_hour := 6.0
@export var sunset_hour := 20.0
## Moves the sun and dims the sky. Turn off to keep your own lighting.
@export var control_environment := true
## Debug: 2.0 = time runs twice as fast
@export var time_scale := 1.0
@export var debug_keys := true

const ACTION := "debug_time"
const NIGHT_AMBIENT := 0.10
const NIGHT_SKY := 0.03
const DAY_FOG := Color(0.70, 0.78, 0.88)
const NIGHT_FOG := Color(0.02, 0.03, 0.06)

var hour := 8.0
var day := 1

## The calendar: 12 months of 30 days, a 7-day week. Day 1 of a new game is the 1st of Seedfall
## (early spring) in the year 412. Seasons change the length of the day, the weather and the land.
const MONTHS: Array[String] = ["Frostwane", "Thawmoon", "Seedfall", "Rainhand", "Bloomtide", "Midyear",
	"Sunheight", "Harvestmoon", "Hearthfire", "Leaffall", "Duskmoon", "Deepwinter"]
const WEEKDAYS: Array[String] = ["Moonsday", "Toilsday", "Wellsday", "Thornsday", "Fairday", "Starday", "Sunsday"]
const SEASONS: Array[String] = ["Winter", "Spring", "Summer", "Autumn"]
const DAYS_PER_MONTH := 30
const DAYS_PER_YEAR := 360
const START_MONTH := 2
const START_YEAR := 412
## Sunsday is a day of rest (most people don't work); Fairday is market day
const REST_DAY := 6
const MARKET_DAY := 4

var _was_night := false
var _last_hour_int := 8
var _sun: DirectionalLight3D
var _env: Environment
## The sky (shaders/sky.gdshader: stars, two moons, clouds), put in place of the scene's own
var _sky_mat: ShaderMaterial
var _apply_timer := 0.0
var _base_fog := -1.0


func _ready() -> void:
	add_to_group("world_clock")
	hour = start_hour
	_last_hour_int = int(hour)
	_was_night = is_night()
	if debug_keys and OS.is_debug_build() and not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F8
		InputMap.action_add_event(ACTION, ev)
	apply_now()


func _process(delta: float) -> void:
	if day_length_minutes > 0.0:
		advance_hours(delta * time_scale * 24.0 / (day_length_minutes * 60.0))
	_apply_timer -= delta
	if _apply_timer <= 0.0:
		_apply_timer = 0.05  # the sky does not need updating every frame
		apply_now()


func _unhandled_input(event: InputEvent) -> void:
	if debug_keys and OS.is_debug_build() and InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		advance_hours((6.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0) if not Input.is_key_pressed(KEY_CTRL) else 24.0 * 30.0)
		apply_now()


# ---------------------------------------------------------------- public API

## Moves time forward (waiting and sleeping will use this too)
func advance_hours(amount: float) -> void:
	hour += amount
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		day_changed.emit(day)
	_check_signals()


func set_time(new_hour: float, new_day: int = -1) -> void:
	hour = fposmod(new_hour, 24.0)
	if new_day > 0:
		day = new_day
	_last_hour_int = int(hour)
	_was_night = is_night()
	apply_now()


func get_hour() -> int:
	return int(hour)


func is_night() -> bool:
	return is_night_at(hour)


func is_night_at(h: float) -> bool:
	if night_start > night_end:
		return h >= night_start or h < night_end
	return h >= night_start and h < night_end


## Is `h` inside [from, to)? Works across midnight (22 -> 6).
static func hour_in_range(h: float, from: float, to: float) -> bool:
	if from <= to:
		return h >= from and h < to
	return h >= from or h < to


## "08:30"
func get_time_text() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]


## 0 = deep night, 1 = full daylight (smooth through dawn and dusk)
func get_daylight() -> float:
	return clampf(inverse_lerp(-4.0, 12.0, _sun_elevation_deg()), 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"hour": hour, "day": day}


func from_dict(data: Dictionary) -> void:
	hour = fposmod(float(data.get("hour", start_hour)), 24.0)
	day = maxi(int(data.get("day", 1)), 1)
	_last_hour_int = int(hour)
	_was_night = is_night()
	apply_now()


## Puts the sun, sky and ambient light where the current time says
## The fog thickness on a clear day (weather and night scale it from here); WorldManager sets it
## from the view distance
func set_base_fog(density: float) -> void:
	_base_fog = density
	apply_now()


func apply_now() -> void:
	if not control_environment or not is_inside_tree():
		return
	_find_nodes()
	var elevation := _sun_elevation_deg()
	var day_factor := get_daylight()
	# The weather dims the sun and the sky and thickens the fog (see Weather)
	var w := Weather.factors(get_tree())
	if _sun != null:
		# The sun travels east to west; below the horizon its light is switched off
		var el := deg_to_rad(clampf(elevation, -60.0, 70.0))
		var t := clampf(inverse_lerp(_sunrise(), _sunset(), hour), 0.0, 1.0)
		var az := lerpf(0.0, PI, t)
		var to_sun := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el) * 0.35).normalized()
		_sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), _sun.global_position)
		_sun.light_energy = day_factor * w.get("sun", 1.0)
		# Warm light when the sun is low
		_sun.light_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.97, 0.9), clampf(elevation / 35.0, 0.0, 1.0))
		_sun.shadow_enabled = day_factor * float(w.get("sun", 1.0)) > 0.08 and int(GameSettings.get_value("shadows")) > 0
	if _env != null and not _in_dungeon():
		_env.background_energy_multiplier = lerpf(NIGHT_SKY, 1.0, day_factor) * float(w.get("sky", 1.0))
		if _sky_mat != null:
			_env.background_energy_multiplier = lerpf(0.6, 1.0, day_factor) * float(w.get("sky", 1.0))  # the shader darkens the night itself
			_update_sky(elevation, day_factor, w)
		_env.ambient_light_energy = lerpf(NIGHT_AMBIENT, 1.0, day_factor) * float(w.get("ambient", 1.0)) + float(w.get("flash", 0.0))
		if _base_fog < 0.0:
			_base_fog = _env.fog_density
		if _env.fog_enabled:
			var fog: Color = NIGHT_FOG.lerp(DAY_FOG, day_factor)
			_env.fog_light_color = fog.lerp(Color(w.get("fog_color", fog)) * maxf(day_factor, 0.08), float(w.get("fog_tint", 0.0)))
			_env.fog_density = _base_fog * float(w.get("fog", 1.0))


# ---------------------------------------------------------------- the calendar

## 0..359
func get_day_of_year() -> int:
	return (day - 1 + START_MONTH * DAYS_PER_MONTH) % DAYS_PER_YEAR


## 0 = Frostwane .. 11 = Deepwinter
func get_month() -> int:
	return get_day_of_year() / DAYS_PER_MONTH


func get_day_of_month() -> int:
	return get_day_of_year() % DAYS_PER_MONTH + 1


func get_year() -> int:
	return START_YEAR + (day - 1 + START_MONTH * DAYS_PER_MONTH) / DAYS_PER_YEAR


## 0 = Moonsday .. 6 = Sunsday
func get_weekday() -> int:
	return (day - 1) % 7


func is_rest_day() -> bool:
	return get_weekday() == REST_DAY


## 0 winter, 1 spring, 2 summer, 3 autumn
func get_season() -> int:
	var m := get_month()
	if m == 11 or m <= 1:
		return 0
	return 1 + (m - 2) / 3


func get_season_name() -> String:
	return SEASONS[get_season()]


## 1 in midsummer, -1 in midwinter (smooth through the year)
func get_summerness() -> float:
	return cos(float(get_day_of_year() - 165) / float(DAYS_PER_YEAR) * TAU)


## "Starday, 14th of Seedfall, 412"
func get_date_text() -> String:
	return "%s, %s of %s, %d" % [WEEKDAYS[get_weekday()], ordinal(get_day_of_month()), MONTHS[get_month()], get_year()]


## "14 Seedfall"
func get_short_date() -> String:
	return "%d %s" % [get_day_of_month(), MONTHS[get_month()]]


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]


## The moon is full on the night of the 15th of every month (werewolves change, see Afflictions)
func get_moon_phase() -> float:
	return fposmod(float(_night_day_of_month() - 15) / float(DAYS_PER_MONTH) + 0.5, 1.0)


func is_full_moon_night() -> bool:
	return _night_day_of_month() == 15 and (hour >= 18.0 or hour < 6.0)


## "Full Moon", "Waxing Moon"...
func get_moon_name() -> String:
	var p := get_moon_phase()
	if absf(p - 0.5) < 0.04:
		return "Full Moon"
	if p < 0.04 or p > 0.96:
		return "New Moon"
	return "Waxing Moon" if p < 0.5 else "Waning Moon"


## Which day a night belongs to: the small hours count as the night before
func get_night_index() -> int:
	return day if hour >= 12.0 else day - 1


func _night_day_of_month() -> int:
	var d := get_night_index()
	return (d - 1 + START_MONTH * DAYS_PER_MONTH) % DAYS_PER_YEAR % DAYS_PER_MONTH + 1


# Long summer days, short winter ones
func _sunrise() -> float:
	return sunrise_hour - get_summerness() * 0.8


func _sunset() -> float:
	return sunset_hour + get_summerness() * 0.8


# ---------------------------------------------------------------- internals

# Degrees above the horizon (negative = night). Day arc between sunrise and sunset, a shallow
# dip below the horizon for the rest.
func _sun_elevation_deg() -> float:
	var rise := _sunrise()
	var sets := _sunset()
	var span := maxf(sets - rise, 1.0)
	if hour >= rise and hour <= sets:
		return sin((hour - rise) / span * PI) * (52.0 + 12.0 * get_summerness())
	var night_len := 24.0 - span
	var since := fposmod(hour - sets, 24.0)
	return -sin(clampf(since / night_len, 0.0, 1.0) * PI) * 30.0


func _check_signals() -> void:
	var h := int(hour)
	if h != _last_hour_int:
		_last_hour_int = h
		hour_changed.emit(h)
	var night := is_night()
	if night != _was_night:
		_was_night = night
		if night:
			night_started.emit()
		else:
			day_started.emit()


func _find_nodes() -> void:
	if _sun == null or not is_instance_valid(_sun):
		var lights := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		_sun = lights[0] as DirectionalLight3D if not lights.is_empty() else null
	if _env == null:
		var envs := get_tree().root.find_children("*", "WorldEnvironment", true, false)
		if not envs.is_empty():
			_env = (envs[0] as WorldEnvironment).environment
	if _env != null and _env.sky != null and _sky_mat == null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = load("res://shaders/sky.gdshader") as Shader
		_env.sky.sky_material = _sky_mat
		_env.fog_sky_affect = 0.15  # fog counts the sky as endlessly far: at 1.0 it hides it all


# The sky shader: how much day, dawn and dusk colour, clouds from the weather, where the moons are.
# Lune crosses the sky opposite the sun; the small red Ember runs a little ahead of it.
func _update_sky(elevation: float, day_factor: float, w: Dictionary) -> void:
	var hours := float(day) * 24.0 + hour
	_sky_mat.set_shader_parameter("day", day_factor)
	_sky_mat.set_shader_parameter("dusk", clampf(1.0 - absf(elevation - 3.0) / 14.0, 0.0, 1.0))
	var sky := float(w.get("sky", 1.0))
	_sky_mat.set_shader_parameter("cloud_cover", clampf(0.3 + (1.0 - sky) * 1.3, 0.0, 1.0))
	_sky_mat.set_shader_parameter("cloud_dark", clampf((1.0 - float(w.get("sun", 1.0))) * 1.2, 0.0, 1.0))
	_sky_mat.set_shader_parameter("time_of_world", hours)
	_sky_mat.set_shader_parameter("moon_phase", get_moon_phase())
	for m in [["moon_dir", 0.0, 0.7], ["moon2_dir", 2.2, 0.45]]:
		var a := (hour + 12.0 + float(m[1])) / 24.0 * TAU - PI * 0.5
		_sky_mat.set_shader_parameter(m[0], Vector3(cos(a), sin(a) * float(m[2]) + 0.15, -0.45).normalized())


func _in_dungeon() -> bool:
	var d := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	return d != null and d.is_inside()


## "14 Seedfall" for any day number of the game (the journal dates its entries with it)
static func short_date_of(game_day: int) -> String:
	var doy := (game_day - 1 + START_MONTH * DAYS_PER_MONTH) % DAYS_PER_YEAR
	return "%d %s" % [doy % DAYS_PER_MONTH + 1, MONTHS[doy / DAYS_PER_MONTH]]
