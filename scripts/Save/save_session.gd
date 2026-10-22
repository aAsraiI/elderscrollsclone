class_name SaveSession
extends RefCounted
## What has to survive the scene reload that loading a game (or starting a new one) performs.
## Static variables live as long as the program runs, unlike nodes.
##
## Loading works in two steps: SaveManager calls begin_load(), which parks the save here and
## reloads the scene. The fresh scene builds the world from the seed stored here, and the new
## SaveManager then applies the rest (player, inventory, entities...) from `pending`.

## The loaded save waiting to be applied. Empty = nothing to apply.
static var pending: Dictionary = {}
static var current_slot := ""
## Seconds played in this game
static var playtime := 0.0

static var _has_seed := false
static var _seed := 0
static var _has_start := false
static var _start := Vector3.ZERO


static func has_pending() -> bool:
	return not pending.is_empty()


static func take_pending() -> Dictionary:
	var data := pending
	pending = {}
	return data


## The seed to build the world with: the chosen/loaded one, else the settings' default
static func get_seed(default_seed: int) -> int:
	return _seed if _has_seed else default_seed


static func has_start_position() -> bool:
	return _has_start


static func get_start_position() -> Vector3:
	return _start


static func begin_load(data: Dictionary, slot: String) -> void:
	pending = data
	current_slot = slot
	playtime = float(data.get("playtime", 0.0))
	var world: Dictionary = data.get("world", {})
	_has_seed = world.has("seed")
	_seed = int(world.get("seed", 0))
	var player: Dictionary = data.get("player", {})
	_has_start = player.has("pos")
	_start = SaveUtil.array_to_vec3(player.get("pos"))
	WorldState.from_dict(data.get("world_state", {}))


## use_default = true plays the default world from WorldSettings
static func begin_new_game(seed_value: int, use_default: bool) -> void:
	pending = {}
	current_slot = ""
	playtime = 0.0
	_has_seed = not use_default
	_seed = seed_value
	_has_start = false
	WorldState.clear()


## "12345" becomes 12345, any other text is turned into a number the same way every time
static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_int():
		return int(t)
	return t.hash()
