class_name WorldClock
extends Node
## The time of day. Created by WorldManager (group "world_clock"), nothing to add by hand.
## Everything that depends on the hour asks this node: NPC schedules, shop hours, door locks.
## It also moves the sun, and dims the sky and ambient light at night (not inside a dungeon,
## which has its own lighting). Time stands still while a menu pauses the game.
## Debug builds: F8 = +1 hour, Shift+F8 = +6 hours.

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

var _was_night := false
var _last_hour_int := 8
var _sun: DirectionalLight3D
var _env: Environment
var _apply_timer := 0.0


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
		advance_hours(6.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
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
func apply_now() -> void:
	if not control_environment or not is_inside_tree():
		return
	_find_nodes()
	var elevation := _sun_elevation_deg()
	var day_factor := get_daylight()
	if _sun != null:
		# The sun travels east to west; below the horizon its light is switched off
		var el := deg_to_rad(clampf(elevation, -60.0, 70.0))
		var t := clampf(inverse_lerp(sunrise_hour, sunset_hour, hour), 0.0, 1.0)
		var az := lerpf(0.0, PI, t)
		var to_sun := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el) * 0.35).normalized()
		_sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), _sun.global_position)
		_sun.light_energy = day_factor
		# Warm light when the sun is low
		_sun.light_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.97, 0.9), clampf(elevation / 35.0, 0.0, 1.0))
		_sun.shadow_enabled = day_factor > 0.05
	if _env != null and not _in_dungeon():
		_env.background_energy_multiplier = lerpf(NIGHT_SKY, 1.0, day_factor)
		_env.ambient_light_energy = lerpf(NIGHT_AMBIENT, 1.0, day_factor)
		if _env.fog_enabled:
			_env.fog_light_color = NIGHT_FOG.lerp(DAY_FOG, day_factor)


# ---------------------------------------------------------------- internals

# Degrees above the horizon (negative = night). Day arc between sunrise and sunset, a shallow
# dip below the horizon for the rest.
func _sun_elevation_deg() -> float:
	var span := maxf(sunset_hour - sunrise_hour, 1.0)
	if hour >= sunrise_hour and hour <= sunset_hour:
		return sin((hour - sunrise_hour) / span * PI) * 62.0
	var night_len := 24.0 - span
	var since := fposmod(hour - sunset_hour, 24.0)
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


func _in_dungeon() -> bool:
	var d := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	return d != null and d.is_inside()
