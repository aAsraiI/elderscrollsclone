class_name Bindings
extends RefCounted
## Keys you can change (Settings > Controls) and the game controller layout. Saved in
## user://settings.cfg under [bindings]. apply() runs when the player is made: it creates every
## action with your key (or the default) and adds the controller buttons, so the nodes that
## would register a default key find the action already there.
##
## Controller: left stick moves, right stick looks, A jump, X use, B sneak, Y menu (Tab),
## right trigger attack, left trigger block / cast / aim, left stick click sprint, D-pad down
## potion, D-pad up favorites, LB beast form, RB racial power, Start pause, Back wait.

const SECTION := "bindings"
## [action, label, default key]
const REBINDABLE := [
	["move_forward", "Move forward", KEY_W], ["move_back", "Move back", KEY_S],
	["move_left", "Move left", KEY_A], ["move_right", "Move right", KEY_D],
	["jump", "Jump", KEY_SPACE], ["sprint", "Sprint", KEY_SHIFT], ["sneak", "Sneak", KEY_CTRL],
	["interact", "Use / take / talk (hold: grab)", KEY_E], ["quick_heal", "Quick health potion", KEY_H],
	["favorites", "Favorites", KEY_Q], ["wait", "Wait", KEY_T], ["magic_menu", "Magic page", KEY_P],
	["racial_power", "Racial power", KEY_Z], ["beast_form", "Werewolf: change", KEY_B],
	["toggle_view", "First / third person", KEY_V], ["quicksave", "Quicksave", KEY_F5], ["quickload", "Quickload", KEY_F9],
]
const PAD := {
	"jump": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "sneak": JOY_BUTTON_B, "sprint": JOY_BUTTON_LEFT_STICK,
	"quick_heal": JOY_BUTTON_DPAD_DOWN, "favorites": JOY_BUTTON_DPAD_UP, "beast_form": JOY_BUTTON_LEFT_SHOULDER,
	"racial_power": JOY_BUTTON_RIGHT_SHOULDER, "wait": JOY_BUTTON_BACK,
}
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "secondary_attack": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

static var _keys := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(GameSettings.PATH) != OK or not cfg.has_section(SECTION):
		return
	for k in cfg.get_section_keys(SECTION):
		_keys[k] = int(cfg.get_value(SECTION, k))


static func get_key(action: String) -> int:
	_load()
	if _keys.has(action):
		return int(_keys[action])
	for r in REBINDABLE:
		if r[0] == action:
			return int(r[2])
	return 0


static func set_key(action: String, key: int) -> void:
	_load()
	_keys[action] = key
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.PATH)
	cfg.set_value(SECTION, action, key)
	cfg.save(GameSettings.PATH)
	_bind(action, key)


static func reset() -> void:
	_load()
	_keys.clear()
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.PATH)
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	cfg.save(GameSettings.PATH)
	apply()


## Creates every action with your keys plus the controller buttons and sticks
static func apply() -> void:
	_load()
	for r in REBINDABLE:
		_bind(r[0], get_key(r[0]))
	for action in PAD:
		_ensure(action)
		var has := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				has = true
		if not has:
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD[action]
			InputMap.action_add_event(action, jb)
	for action in PAD_AXES:
		_ensure(action)
		var has := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion:
				has = true
		if not has:
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
	_ensure("attack")
	_ensure("secondary_attack")
	if InputMap.action_get_events("attack").filter(func(e: InputEvent) -> bool: return e is InputEventMouseButton).is_empty():
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)
	if InputMap.action_get_events("secondary_attack").filter(func(e: InputEvent) -> bool: return e is InputEventMouseButton).is_empty():
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("secondary_attack", mb2)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)


static func _bind(action: String, key: int) -> void:
	_ensure(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	if key != 0:
		var k := InputEventKey.new()
		k.physical_keycode = key as Key
		InputMap.action_add_event(action, k)


static func key_name(action: String) -> String:
	var k := get_key(action)
	return OS.get_keycode_string(k) if k != 0 else "-"
