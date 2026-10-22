class_name DungeonManager
extends Node
## Takes the player into an instanced dungeon or building interior and back. Created by WorldManager.
##
## A dungeon is NOT part of the open world: when you enter, it is generated (from the world seed
## and the entrance's id, so it is always the same) far below the world, the player is moved in,
## the sun and sky are switched off for darkness, and leaving deletes it again and puts the player
## back in front of the entrance. Chests inside are saved through WorldState.
## Town buildings work the same way: their id (BuildingPlot.id) is the "entrance id", and the
## inside comes from InteriorBuilder instead of DungeonBuilder.

signal entered(entrance_id: String)
signal exited(entrance_id: String)

## Height the dungeon is built at, far below any terrain
const DUNGEON_Y := -5000.0

## Seconds of fade to black when going in or out (0 = instant)
@export var fade_time := 0.2

var current_entrance_id := ""
## Building interiors only: {"exit", "beds", "work", "seats"} positions inside the current interior
## (local to get_interior_root()), where the people living or working there go
var current_spots := {}

var _world: WorldManager
var _root: Node3D
var _return_position := Vector3.ZERO
var _return_yaw := 0.0
var _busy := false
var _saved_env := {}
var _hidden_lights: Array[Node] = []
var _saved_rescue := true
var _fade: ColorRect
## Dungeons: which floor you are on (0 = the top) and how many there are
var current_floor := 0
var floor_count := 1
var _next_floor := 0
var _arrive_down := false


func _ready() -> void:
	add_to_group("dungeon_manager")
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_inside() -> bool:
	return _root != null


func is_busy() -> bool:
	return _busy


## The node holding the current dungeon or interior (null when outside)
func get_interior_root() -> Node3D:
	return _root


## Inside a town building (not a dungeon)?
func is_in_building() -> bool:
	return _root != null and _root.has_meta("building_id")


## "Old Crypt", "Brenna's House" ... or "" when outside
func get_current_name() -> String:
	if _root == null:
		return ""
	var world := _get_world()
	if world == null:
		return ""
	var b := world.get_building(current_entrance_id)
	if b != null:
		return b.display_name
	var placed := world.get_poi(current_entrance_id)
	var entrance := placed.poi as DungeonEntrancePOIData if placed != null else null
	return entrance.dungeon.display_name if entrance != null and entrance.dungeon != null else "a dungeon"


## For the save file
func to_dict() -> Dictionary:
	if _root == null:
		return {"inside": false}
	return {
		"inside": true,
		"entrance": current_entrance_id,
		"return": SaveUtil.vec3_to_array(_return_position),
		"yaw": _return_yaw,
		"floor": current_floor,
	}


## Rebuilds the dungeon a save was made in (instantly, no fade). The caller then places the player.
func restore(d: Dictionary) -> bool:
	if not bool(d.get("inside", false)):
		return false
	_next_floor = int(d.get("floor", 0))
	_arrive_down = false
	return _open(String(d.get("entrance", "")), SaveUtil.array_to_vec3(d.get("return")), float(d.get("yaw", 0.0)), false)


## Takes the stairs: rebuilds the dungeon as floor n (0 = the top). Going up, you arrive by the
## stairs down of that floor; going down, by its stairs up.
func go_floor(n: int) -> void:
	if _busy or _root == null or n < 0:
		return
	_busy = true
	await _fade_to(1.0)
	var entrance := current_entrance_id
	_arrive_down = n < current_floor
	_next_floor = n
	_clear_entities_inside()
	remove_child(_root)
	_root.queue_free()  # not free(): the stairs that called us are inside it
	_root = null
	_set_dark(false)
	var world := _get_world()
	if world != null:
		world.rescue_fallen_player = _saved_rescue
	_open(entrance, _return_position, _return_yaw, true)
	_arrive_down = false
	await _fade_to(0.0)
	_busy = false


## Goes into the dungeon behind the entrance with this id. return_position / yaw = where to come back out.
func enter(entrance_id: String, return_position: Vector3, return_yaw: float) -> bool:
	if _busy or _root != null:
		return false
	_busy = true
	await _fade_to(1.0)
	_next_floor = 0
	_arrive_down = false
	var ok := _open(entrance_id, return_position, return_yaw, true)
	await _fade_to(0.0)
	_busy = false
	return ok


## Leaves the current dungeon
func exit() -> void:
	if _busy or _root == null:
		return
	_busy = true
	await _fade_to(1.0)
	var left := current_entrance_id
	var player := _get_player()
	var world := _get_world()
	_clear_entities_inside()
	_root.queue_free()
	_root = null
	current_entrance_id = ""
	current_spots = {}
	_set_dark(false)
	if world != null:
		world.rescue_fallen_player = _saved_rescue
		world.ensure_area_loaded(_return_position, 1)
	if player != null:
		player.global_position = _return_position
		player.rotation.y = _return_yaw
		var head := player.get_node_or_null("Head") as Node3D
		if head != null:
			head.rotation.x = 0.0
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
	exited.emit(left)
	await _fade_to(0.0)
	_busy = false


# ---------------------------------------------------------------- internals

func _open(entrance_id: String, return_position: Vector3, return_yaw: float, move_player: bool) -> bool:
	var world := _get_world()
	if world == null:
		push_error("DungeonManager: no WorldManager found.")
		return false
	var result := {}
	var ambient := Color(0.03, 0.03, 0.04)
	var building := world.get_building(entrance_id)
	if building != null:
		var lvl := LevelCurve.place_level(world.map, building.world_pos)
		result = InteriorBuilder.build(building, ("%d|interior|%s" % [world.world_seed, entrance_id]).hash(), lvl, world.clock.day if world.clock != null else 1)
		ambient = result["ambient"]
		current_spots = result["spots"]
		_root = result["root"]
		_root.position = Vector3(building.world_pos.x, DUNGEON_Y, building.world_pos.z)
	else:
		var placed := world.get_poi(entrance_id)
		var poi := placed.poi as DungeonEntrancePOIData if placed != null else null
		if poi == null or poi.dungeon == null:
			push_warning("DungeonManager: entrance '%s' has no dungeon." % entrance_id)
			return false
		var dungeon_seed := ("%d|dungeon|%s" % [world.world_seed, entrance_id]).hash()
		var zone := LevelCurve.zone_range(world.map, placed.position)  # a dungeon is as hard as the land around its door
		result = DungeonBuilder.build(poi.dungeon, dungeon_seed, entrance_id, zone.x, zone.y, _next_floor)
		current_floor = int(result.get("floor", 0))
		floor_count = int(result.get("floors", 1))
		if _arrive_down and result.get("down_spot") != null:
			result["start"] = result["down_spot"]  # came up the stairs: arrive by the stairs down
			result["start_yaw"] = float(result["start_yaw"]) + PI
		ambient = poi.dungeon.ambient_color
		current_spots = {}
		_root = result["root"]
		_root.position = Vector3(placed.position.x, DUNGEON_Y, placed.position.z)
	add_child(_root)

	current_entrance_id = entrance_id
	_return_position = return_position
	_return_yaw = return_yaw
	_saved_rescue = world.rescue_fallen_player
	world.rescue_fallen_player = false
	_set_dark(true, ambient)

	if move_player:
		var player := _get_player()
		if player != null:
			player.global_position = _root.to_global(result["start"])
			player.rotation.y = float(result.get("start_yaw", 0.0))
			var head := player.get_node_or_null("Head") as Node3D
			if head != null:
				head.rotation.x = 0.0
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity = Vector3.ZERO
	entered.emit(entrance_id)
	return true


# Things dropped inside the dungeon are lost when it is deleted (they would fall into the void)
func _clear_entities_inside() -> void:
	for n in get_tree().get_nodes_in_group("persistent"):
		if n is Node3D and (n as Node3D).global_position.y < DUNGEON_Y + 500.0:
			n.queue_free()


# Switches the sky and sun off so the dungeon is as dark as its lamps make it
func _set_dark(dark: bool, ambient: Color = Color(0.03, 0.03, 0.04)) -> void:
	var we := _find_first("WorldEnvironment") as WorldEnvironment
	if dark:
		if we != null and we.environment != null:
			var e := we.environment
			_saved_env = {
				"bg_mode": e.background_mode, "ambient_source": e.ambient_light_source,
				"ambient_color": e.ambient_light_color, "ambient_energy": e.ambient_light_energy,
				"fog": e.fog_enabled,
			}
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color.BLACK
			e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			e.ambient_light_color = ambient
			e.ambient_light_energy = 1.0
			e.fog_enabled = false
		_hidden_lights.clear()
		for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if n.visible:
				n.visible = false
				_hidden_lights.append(n)
	else:
		if we != null and we.environment != null and not _saved_env.is_empty():
			var e := we.environment
			e.background_mode = _saved_env["bg_mode"]
			e.ambient_light_source = _saved_env["ambient_source"]
			e.ambient_light_color = _saved_env["ambient_color"]
			e.ambient_light_energy = _saved_env["ambient_energy"]
			e.fog_enabled = _saved_env["fog"]
		_saved_env = {}
		for n in _hidden_lights:
			if is_instance_valid(n):
				n.visible = true
		_hidden_lights.clear()


func _find_first(type_name: String) -> Node:
	var list := get_tree().root.find_children("*", type_name, true, false)
	return list[0] if not list.is_empty() else null


func _fade_to(alpha: float) -> void:
	if fade_time <= 0.0:
		_fade.color.a = alpha
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, fade_time)
	await tween.finished


func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _get_world() -> WorldManager:
	if _world == null or not is_instance_valid(_world):
		_world = get_parent() as WorldManager
	return _world
