class_name Swimming
extends Node
## Lakes and the sea: deeper than your chest, you swim instead of walking on the bottom.
## player.gd asks is_swimming() and moves you with swim_move(): you float at the surface, swim
## where you look (look down and press forward to dive), Space rises. Under water your breath
## lasts BREATH seconds (forever with Water Breathing); after that you drown slowly.
## A blue tint shows when your head is under.

const BREATH := 25.0
const SWIM_SPEED := 3.0
const SPRINT_SWIM := 4.6

var breath := BREATH
var _swimming := false
var _under := false
var _hurt := 0.0
var _player: CharacterBody3D
var _tint: CanvasLayer
var _sea := 0.0
var _water := false


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null and world.settings != null:
		_water = world.settings.water_enabled
		_sea = world.settings.sea_level


func is_swimming() -> bool:
	return _swimming


func is_under() -> bool:
	return _under


func _physics_process(delta: float) -> void:
	if not _water:
		return
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	var inside := dm != null and dm.is_inside()
	var y := _player.global_position.y
	var was := _swimming
	_swimming = not inside and y < _sea - 1.1 and not _player.has_meta("riding") and not _player.has_meta("boat")
	if _swimming and not was:
		_player.velocity.y *= 0.2
	var head := (_player.get_node("Head") as Node3D).global_position.y
	_under = _swimming and head < _sea - 0.05
	var stats := _player.get_node_or_null("Stats") as Stats
	var water_breathing := stats != null and stats.get_stat("water_breathing") > 0.0
	if _under and not water_breathing:
		breath -= delta
		if breath <= 0.0:
			_hurt -= delta
			if _hurt <= 0.0:
				_hurt = 1.0
				stats.modify_vital("health", -6.0)
				Locks.toast(get_tree(), "You are drowning!", true)
	else:
		breath = minf(breath + delta * 6.0, BREATH)
	_show_tint(_under)


## Called by player.gd instead of walking while swimming
func swim_move(delta: float, input_dir: Vector2, sprint: bool) -> void:
	var cam := _player.get_node("Head") as Node3D
	var basis := cam.global_transform.basis
	var dir := (basis * Vector3(input_dir.x, 0.0, input_dir.y))
	if dir.length() > 0.01:
		dir = dir.normalized()
	var speed := SPRINT_SWIM if sprint else SWIM_SPEED
	var stats := _player.get_node_or_null("Stats") as Stats
	if sprint and stats != null:
		if stats.stamina <= 1.0:
			speed = SWIM_SPEED
		else:
			stats.modify_vital("stamina", -6.0 * delta)
	var want := dir * speed
	if Input.is_action_pressed("jump"):
		want.y += 2.5
	# Float up to the surface when not diving
	var surface := _sea - 1.25
	if input_dir == Vector2.ZERO or dir.y > -0.3:
		if _player.global_position.y < surface:
			want.y += clampf((surface - _player.global_position.y) * 2.0, 0.0, 2.0)
	if _player.global_position.y > surface and want.y > 0.0:
		want.y = 0.0
	_player.velocity = _player.velocity.lerp(want, clampf(4.0 * delta, 0.0, 1.0))
	_player.move_and_slide()


func _show_tint(on: bool) -> void:
	if on and _tint == null:
		_tint = CanvasLayer.new()
		_tint.layer = 1
		var r := ColorRect.new()
		r.color = Color(0.05, 0.2, 0.3, 0.45)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tint.add_child(r)
		add_child(_tint)
	elif not on and _tint != null:
		_tint.queue_free()
		_tint = null
