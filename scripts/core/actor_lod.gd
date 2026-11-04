class_name ActorLOD
extends Node
## Alpha 1.23 performance: actors (townsfolk, guards, creatures) far from you, or on the other side
## of a dungeon door, stop costing anything. Created by WorldManager.
##
##   near     closer than WAKE m and in the same place as you (both outside, or both inside):
##            everything runs as before
##   frozen   further than SLEEP m, or outside while you are inside (or the other way round):
##            hidden, no _process / _physics_process / animation anywhere in the actor, until
##            you come back in range. What they were doing carries on from where it stopped.
## Never frozen: your followers and allies, a fight that is on (chasing or attacking you within
## FIGHT_RANGE), and anything with the meta "lod_keep".
## A few actors are looked at per frame (BATCH), so the cost stays flat however many there are.

const WAKE := 135.0
const SLEEP := 150.0  # = CreatureBody.DRAW_DISTANCE: past this their bodies were not drawn anyway
const FIGHT_RANGE := 220.0
## Inside a dungeon or building walls hide everything far sooner
const WAKE_INSIDE := 45.0
const SLEEP_INSIDE := 55.0
const BATCH := 24
## People and creatures further than this cast no shadow (their many body parts were drawn again
## for every shadow cascade)
const SHADOW_RANGE := 35.0
const META := "lod_frozen"

var _cursor := 0
var _player: Node3D
var _was_inside := false


func _ready() -> void:
	add_to_group("actor_lod")


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var actors := ActorRegistry.all()
	var n := actors.size()
	if n == 0:
		return
	var inside := _player.global_position.y < DungeonManager.DUNGEON_Y + 500.0
	var count := BATCH
	if inside != _was_inside:
		_was_inside = inside
		count = n  # through a door: everyone is sorted out at once
	var ppos := _player.global_position
	for i in mini(count, n):
		_cursor = (_cursor + 1) % n
		var e: Enemy = actors[_cursor]
		if e == null or not is_instance_valid(e) or not e.is_inside_tree():
			continue
		var frozen := e.has_meta(META)
		var want := _should_freeze(e, ppos, inside, frozen)
		if want and not frozen:
			freeze(e)
		elif not want and frozen:
			thaw(e)
		if not want:
			_shadow_tier(e, e.global_position.distance_squared_to(ppos) < SHADOW_RANGE * SHADOW_RANGE)


func _should_freeze(e: Enemy, ppos: Vector3, inside: bool, frozen: bool) -> bool:
	if e.has_meta("player_ally") or e.has_meta("lod_keep"):
		return false
	var e_inside := e.global_position.y < DungeonManager.DUNGEON_Y + 500.0
	if e_inside != inside:
		return true
	var d2 := e.global_position.distance_squared_to(ppos)
	if (e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK) and d2 < FIGHT_RANGE * FIGHT_RANGE:
		return false
	var edge := (WAKE_INSIDE if frozen else SLEEP_INSIDE) if inside else (WAKE if frozen else SLEEP)  # a little give, so nobody flickers at the edge
	return d2 > edge * edge


## Everything in the actor that runs every frame stops, and it is hidden
static func freeze(e: Enemy) -> void:
	var stopped: Array = []
	_collect(e, stopped)
	for entry in stopped:
		var n: Node = entry[0]
		if n is AnimationMixer:
			(n as AnimationMixer).active = false
		else:
			n.set_process(false)
			n.set_physics_process(false)
	e.set_meta(META, stopped)
	e.visible = false


static func thaw(e: Enemy) -> void:
	var stopped: Array = e.get_meta(META, [])
	e.remove_meta(META)
	for entry in stopped:
		var n: Node = entry[0]
		if not is_instance_valid(n):
			continue
		if n is AnimationMixer:
			(n as AnimationMixer).active = bool(entry[1])
		else:
			n.set_process(bool(entry[1]))
			n.set_physics_process(bool(entry[2]))
	e.visible = true
	if e is CharacterBody3D:
		(e as CharacterBody3D).velocity = Vector3.ZERO


static func is_frozen(e: Node) -> bool:
	return e != null and e.has_meta(META)


static func _collect(n: Node, out: Array) -> void:
	if n is AnimationMixer:
		if (n as AnimationMixer).active:
			out.append([n, true, false])
	elif n.is_processing() or n.is_physics_processing():
		out.append([n, n.is_processing(), n.is_physics_processing()])
	for c in n.get_children():
		_collect(c, out)


static func _shadow_tier(e: Enemy, on: bool) -> void:
	if bool(e.get_meta("lod_shadow", true)) == on:
		return
	e.set_meta("lod_shadow", on)
	var parts: Array = e.get_meta("lod_parts", [])
	if parts.is_empty():
		for g in e.find_children("*", "GeometryInstance3D", true, false):
			if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				parts.append(g)
		e.set_meta("lod_parts", parts)
	for g in parts:
		if is_instance_valid(g):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
