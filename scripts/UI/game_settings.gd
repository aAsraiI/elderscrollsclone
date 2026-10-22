class_name GameSettings
extends RefCounted
## Player options (the Settings screen), kept in user://settings.cfg so they survive restarts
## and are shared by every save. Read anywhere with GameSettings.get_value("fov").
##
## Changing one: GameSettings.set_value("fov", 90.0) saves it and calls apply(), which pushes
## the window / audio options to the engine and calls apply_settings() on every node in group
## "settings_listener" (the player, the HUD bars, the weapon view, the save manager).

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Every option and its default. The Settings screen is built from OPTIONS below.
const DEFAULTS := {
	"mouse_sensitivity": 0.002,
	"invert_y": false,
	"fov": 75.0,
	"head_bob": true,
	"autosave_minutes": 5.0,
	"window_mode": 0,  # 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen
	"vsync": true,
	"max_fps": 0,
	"render_scale": 1.0,
	"ui_scale": 1.0,
	"show_fps": false,
	"master_volume": 0.8,
	"hud_values": true,
	"hud_always": false,
	"show_compass": true,
	"difficulty": 2,  # 0 Novice .. 4 Master
	"grass": 2,  # 0 off, 1 low, 2 medium, 3 high
	"weather_effects": true,
	"show_date": true,
	"music_volume": 0.5,
	"sfx_volume": 0.8,
	"tutorial": true,
	"controller_look": 3.0,
}

## How the Settings screen shows each option. kind: slider / check / choice.
## For sliders: min, max, step, and fmt (how the value is printed).
const OPTIONS := [
	{"tab": "Gameplay", "key": "mouse_sensitivity", "label": "Mouse sensitivity", "kind": "slider", "min": 0.0005, "max": 0.006, "step": 0.0001, "fmt": "x%.1f", "scale": 500.0},
	{"tab": "Gameplay", "key": "invert_y", "label": "Invert mouse Y", "kind": "check"},
	{"tab": "Gameplay", "key": "fov", "label": "Field of view", "kind": "slider", "min": 55.0, "max": 110.0, "step": 1.0, "fmt": "%d°"},
	{"tab": "Gameplay", "key": "head_bob", "label": "Weapon sway while walking", "kind": "check"},
	{"tab": "Gameplay", "key": "autosave_minutes", "label": "Autosave every", "kind": "slider", "min": 0.0, "max": 30.0, "step": 1.0, "fmt": "%d min", "zero": "Off"},
	{"tab": "Gameplay", "key": "difficulty", "label": "Difficulty", "kind": "choice", "choices": ["Novice", "Apprentice", "Adept", "Expert", "Master"]},
	{"tab": "Interface", "key": "ui_scale", "label": "Interface size", "kind": "slider", "min": 0.75, "max": 1.5, "step": 0.05, "fmt": "%d%%", "scale": 100.0},
	{"tab": "Interface", "key": "hud_values", "label": "Numbers on health / magicka / stamina", "kind": "check"},
	{"tab": "Interface", "key": "hud_always", "label": "Always show the bars (no fading)", "kind": "check"},
	{"tab": "Interface", "key": "show_compass", "label": "Compass", "kind": "check"},
	{"tab": "Interface", "key": "show_date", "label": "Date and weather in the corner", "kind": "check"},
	{"tab": "Interface", "key": "tutorial", "label": "Tutorial hints", "kind": "check"},
	{"tab": "Gameplay", "key": "controller_look", "label": "Controller look speed", "kind": "slider", "min": 1.0, "max": 6.0, "step": 0.25, "fmt": "%.2f"},
	{"tab": "Interface", "key": "show_fps", "label": "FPS counter", "kind": "check"},
	{"tab": "Video", "key": "window_mode", "label": "Window", "kind": "choice", "choices": ["Windowed", "Borderless fullscreen", "Fullscreen"]},
	{"tab": "Video", "key": "vsync", "label": "V-Sync", "kind": "check"},
	{"tab": "Video", "key": "max_fps", "label": "Frame limit", "kind": "choice", "choices": ["Unlimited", "30", "60", "120", "144"], "values": [0, 30, 60, 120, 144]},
	{"tab": "Video", "key": "render_scale", "label": "Render scale", "kind": "slider", "min": 0.5, "max": 1.0, "step": 0.05, "fmt": "%d%%", "scale": 100.0},
	{"tab": "Video", "key": "grass", "label": "Grass and flowers", "kind": "choice", "choices": ["Off", "Low", "Medium", "High"]},
	{"tab": "Video", "key": "weather_effects", "label": "Rain and snow", "kind": "check"},
	{"tab": "Audio", "key": "master_volume", "label": "Master volume", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "%d%%", "scale": 100.0},
	{"tab": "Audio", "key": "music_volume", "label": "Music", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "%d%%", "scale": 100.0},
	{"tab": "Audio", "key": "sfx_volume", "label": "Sound effects", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "%d%%", "scale": 100.0},
]

static var _values := {}
static var _loaded := false


static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant, tree: SceneTree = null) -> void:
	_ensure_loaded()
	if key == "difficulty":
		GameRules.set_rule("difficulty", int(value))  # the game being played changes with it
	_values[key] = value
	save()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree != null:
		apply(tree)


static func reset_to_defaults(tree: SceneTree = null) -> void:
	_values = DEFAULTS.duplicate()
	_loaded = true
	save()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree != null:
		apply(tree)


static func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)


## Pushes every option to the engine and to the listening nodes
static func apply(tree: SceneTree) -> void:
	_ensure_loaded()
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		var vol := float(get_value("master_volume"))
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.0001)))
		AudioServer.set_bus_mute(bus, vol <= 0.0)
	Engine.max_fps = int(get_value("max_fps"))
	if DisplayServer.get_name() != "headless":
		var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		var want: int = modes[clampi(int(get_value("window_mode")), 0, 2)]
		if int(DisplayServer.window_get_mode()) != want:
			DisplayServer.window_set_mode(want as DisplayServer.WindowMode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)
	var root := tree.root
	root.scaling_3d_scale = clampf(float(get_value("render_scale")), 0.25, 1.0)
	root.content_scale_factor = clampf(float(get_value("ui_scale")), 0.5, 2.0)
	FpsOverlay.set_shown(tree, bool(get_value("show_fps")))
	tree.call_group("settings_listener", "apply_settings")


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		if cfg.has_section_key(SECTION, key):
			var v: Variant = cfg.get_value(SECTION, key)
			# A hand-edited file with the wrong kind of value falls back to the default
			if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
				_values[key] = v
