class_name EncounterManager
extends Node
## Random events around the player, based on the biome they are standing in. Created by the
## WorldManager (turn it off there with "Encounters Enabled"), nothing to add by hand.
##
## Every so often (a random time between Min Interval and Max Interval) it rolls a chance. If it
## succeeds it looks up the biome under the player, picks one of that biome's Encounters (weighted,
## respecting level limits and cooldowns), finds a spot around the player (outside their view,
## inside the same biome, on loaded ground that is not too steep, away from points of interest) and
## spawns the encounter's creatures there. Their level is the player's level held inside the
## biome's level range, so a beginner meets weak things even in a hard biome's edge, and a strong
## player is not bored in an easy one.
##
## It never starts anything while the player is in a dungeon, dead, or already in a fight, and it
## caps how many of its creatures are alive. It cleans up after itself: creatures that are far away
## or have been around too long without a fight are removed, and so are old corpses.
## Debug builds: press F7 to force an encounter right now.

signal encounter_started(data: EncounterData, spawned: Array)

@export var enabled := true
## Seconds before the first roll after the world starts
@export var first_delay := 15.0
@export var min_interval := 30.0
@export var max_interval := 75.0
## Chance that a roll becomes an encounter
@export_range(0.0, 1.0, 0.05) var chance := 0.75
## Most creatures from encounters alive at once
@export var max_alive := 10
## Creatures this far from the player (m) are removed
@export var despawn_distance := 150.0
## Seconds a calm creature may stay around before being removed (when not near the player)
@export var lifetime := 360.0
## Seconds a corpse stays (it is never saved, so loot it before it goes)
@export var corpse_seconds := 150.0
## No new encounter while something is hunting the player within this distance (m)
@export var quiet_radius := 45.0
@export var show_messages := true
## F7 forces an encounter, in debug builds only
@export var debug_key := true
@export var debug_log := false

const ACTION := "debug_encounter"
const MAX_SLOPE_DEG := 28.0
## Meters around a town's edge where nothing random starts
const TOWN_MARGIN := 60.0

var world: WorldManager
var player: Node3D

var _clock := 0.0
var _timer := 0.0
var _cleanup_timer := 0.0
var _cooldowns := {}  # encounter key -> clock time it is available again
var _live: Array[Dictionary] = []  # {"node", "born", "dead_at"}
var _rng := RandomNumberGenerator.new()
var _root: Node3D


func _ready() -> void:
	world = get_parent() as WorldManager
	_rng.randomize()
	_timer = first_delay
	if debug_key and OS.is_debug_build() and not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F7
		InputMap.action_add_event(ACTION, ev)


func _process(delta: float) -> void:
	_clock += delta
	_cleanup_timer -= delta
	if _cleanup_timer <= 0.0:
		_cleanup_timer = 1.0
		_cleanup()
	if not enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(min_interval, max_interval)
		try_encounter()


func _unhandled_input(event: InputEvent) -> void:
	if debug_key and OS.is_debug_build() and InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		try_encounter(true)


# ---------------------------------------------------------------- public API

## Starts an encounter around the player. `force` skips the chance, the cap, the quiet rule and cooldowns.
## `only` forces one specific encounter instead of picking from the biome. Returns what spawned.
func try_encounter(force: bool = false, only: EncounterData = null) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not _can_run():
		return out
	var pos := player.global_position
	var biome := world.get_biome_at(pos.x, pos.z)
	if biome == null:
		return out
	if not force:
		if _rng.randf() > chance * float(GameRules.get_rule("encounter_rate")) or get_alive_count() >= max_alive:
			return out
		if world.get_town_at(pos, TOWN_MARGIN) != null:
			return out  # towns are safe
		if _fight_nearby(pos):
			_timer = 10.0
			return out
	var player_level := _player_level()
	var zone_level := LevelCurve.scale_level(player_level, biome.level_min, biome.level_max)
	var data := only if only != null else _pick(biome, player_level, zone_level, force)
	if data == null or data.table == null:
		return out
	var spot := _find_spot(data, biome, pos)
	if spot == Vector3.INF:
		if debug_log:
			print("EncounterManager: no room for '%s'" % data.get_key())
		return out
	var members := data.table.roll(_rng, zone_level)
	if members.is_empty():
		return out

	var host := _spawn_root()
	for m in members:
		var angle := _rng.randf() * TAU
		var off := Vector3(cos(angle), 0.0, sin(angle)) * data.group_spread * sqrt(_rng.randf())
		var x := spot.x + off.x
		var z := spot.z + off.z
		var y := world.get_height_at(x, z)
		var level := clampi(zone_level + _rng.randi_range(-1, 1), 1, 99)
		var e := Population.spawn_enemy(m, level, host, Vector3(x, y + 0.6, z), _rng, {"persist_mode": Enemy.PersistMode.NEVER})
		if data.aggro:
			e.aggro(player)
		_live.append({"node": e, "born": _clock, "dead_at": -1.0})
		out.append(e)
	_cooldowns[data.get_key()] = _clock + data.cooldown
	if show_messages and data.message != "":
		_toast(data.message)
	if debug_log:
		print("EncounterManager: '%s' in %s: %d creatures at level ~%d" % [data.get_key(), biome.display_name, out.size(), zone_level])
	encounter_started.emit(data, out)
	return out


func get_alive_count() -> int:
	var n := 0
	for r in _live:
		if not is_instance_valid(r["node"]):
			continue  # freed (cleaned up, or its chunk went away)
		var e := r["node"] as Enemy
		if e != null and not e.is_dead():
			n += 1
	return n


func get_spawned() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in _live:
		if is_instance_valid(r["node"]):
			out.append(r["node"])
	return out


## Removes creatures that are far away, were around too long, or are old corpses
func cleanup_now() -> void:
	_cleanup()


# ---------------------------------------------------------------- internals

func _can_run() -> bool:
	if world == null or world.map == null:
		return false
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return false
	if world.dungeons != null and (world.dungeons.is_inside() or world.dungeons.is_busy()):
		return false
	var d: Variant = player.get_meta("damageable", null)
	if d != null and not d.is_alive():
		return false
	return true


func _player_level() -> int:
	var skills := player.get_node_or_null("Skills") as Skills
	return skills.get_player_level() if skills != null else 1


func _fight_nearby(pos: Vector3) -> bool:
	for n in ActorRegistry.all():
		var e := n as Enemy
		if e == null or e.is_dead():
			continue
		if e.state != Enemy.State.CHASE and e.state != Enemy.State.ATTACK:
			continue
		var d := Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length()
		if d < quiet_radius:
			return true
	return false


func _pick(biome: BiomeData, player_level: int, zone_level: int, ignore_cooldown: bool = false) -> EncounterData:
	var total := 0.0
	var options: Array[EncounterData] = []
	for enc in biome.encounters:
		if enc == null or enc.table == null or enc.weight <= 0.0:
			continue
		if enc.night_only:
			var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
			if clock == null or not clock.is_night():
				continue
		if enc.min_player_level > 0 and player_level < enc.min_player_level:
			continue
		if enc.max_player_level > 0 and player_level > enc.max_player_level:
			continue
		if not ignore_cooldown and _clock < float(_cooldowns.get(enc.get_key(), 0.0)):
			continue
		if not enc.table.has_entries_for(zone_level):
			continue
		options.append(enc)
		total += enc.weight
	if options.is_empty():
		return null
	var pick := _rng.randf() * total
	for enc in options:
		pick -= enc.weight
		if pick <= 0.0:
			return enc
	return options[options.size() - 1]


# A spot around the player: not in view, same biome, on loaded and gentle ground, not at a POI
func _find_spot(data: EncounterData, biome: BiomeData, pos: Vector3) -> Vector3:
	var forward := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		forward = -cam.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var cs := world.settings.chunk_size
	for attempt in 16:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(data.distance_min, maxf(data.distance_max, data.distance_min))
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		if data.avoid_view and dist < 120.0 and forward.angle_to(dir) < deg_to_rad(55.0):
			continue
		var x := pos.x + dir.x * dist
		var z := pos.z + dir.z * dist
		if world.get_biome_at(x, z) != biome:
			continue
		if not world.is_chunk_loaded(Vector2i(floori(x / cs), floori(z / cs))):
			continue
		if world.map.get_inside_distance(x, z) < world.settings.edge_width + 40.0:
			continue
		if not _gentle(x, z) or world.map.is_under_water(world.get_height_at(x, z) - 0.3):
			continue
		if not world.get_pois_near(Vector3(x, 0.0, z), 30.0).is_empty():
			continue
		if world.get_town_at(Vector3(x, 0.0, z), TOWN_MARGIN) != null:
			continue
		return Vector3(x, world.get_height_at(x, z), z)
	return Vector3.INF


func _gentle(x: float, z: float) -> bool:
	var h0 := world.get_height_at(x, z)
	for off in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		var h := world.get_height_at(x + off.x, z + off.y)
		if rad_to_deg(atan2(absf(h - h0), 3.0)) > MAX_SLOPE_DEG:
			return false
	return true


func _spawn_root() -> Node3D:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "EncounterSpawns"
		world.add_child(_root)
	return _root


func _cleanup() -> void:
	if player == null or not is_instance_valid(player):
		return
	var pos := player.global_position
	for i in range(_live.size() - 1, -1, -1):
		var r := _live[i]
		var n: Node3D = r["node"] if is_instance_valid(r["node"]) else null
		if n == null:
			_live.remove_at(i)
			continue
		var dist := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
		var e := n as Enemy
		var remove := false
		if e != null and e.is_dead():
			if float(r["dead_at"]) < 0.0:
				r["dead_at"] = _clock
			remove = dist > despawn_distance or (_clock - float(r["dead_at"]) > corpse_seconds and dist > 15.0)
		else:
			var engaged := e != null and (e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK or e.state == Enemy.State.STAGGER or e.state == Enemy.State.FLEE)
			remove = dist > despawn_distance or (_clock - float(r["born"]) > lifetime and not engaged and dist > 50.0)
		if remove:
			n.queue_free()
			_live.remove_at(i)


func _toast(text: String) -> void:
	var sm := get_tree().get_first_node_in_group("save_manager") as SaveManager
	if sm != null and sm.menu != null:
		sm.menu.show_toast(text)
