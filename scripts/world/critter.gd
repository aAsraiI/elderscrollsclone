class_name Critter
extends StaticBody3D
## Alpha 1.24: small harmless life near you (AmbientLife): rabbits and squirrels that hop about and
## bolt when you come close, frogs, birds and bats circling overhead, crows picking at a body.
## Cheap: no AI, no stats, one model, a few lines of movement. A hit kills it (huntable): it drops
## a little meat or hide. They come and go out of your sight.

enum Move { HOP, FLY, PERCH }

const FLEE_RANGE := 6.0

var kind := "rabbit"
var move: Move = Move.HOP
var speed := 3.0
var drops: Array = []  # [item path, chance]
var home := Vector3.ZERO
var _goal := Vector3.ZERO
var _wait := 0.0
var _fleeing := 0.0
var _angle := 0.0
var _alt := 18.0
var _dead := false
var _player: Node3D
var _world: WorldManager


static func make(p_kind: String, at: Vector3, world: WorldManager) -> Critter:
	var c := Critter.new()
	c.kind = p_kind
	c._world = world
	c.home = at
	var look: Dictionary = AmbientLife.KINDS.get(p_kind, AmbientLife.KINDS["rabbit"])
	c.move = look.get("move", Move.HOP)
	c.speed = float(look.get("speed", 3.0))
	c.drops = look.get("drops", [])
	c.collision_layer = Enemy.ENEMY_LAYER  # swings and arrows can hit it
	c.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * float(look.get("size", 0.35)) * 1.4
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	c.add_child(shape)
	var model: Node3D = ModelLibrary.instance(String(look.get("model", ""))) if ModelLibrary.has(String(look.get("model", ""))) else null
	if model != null:
		var b := ModelLibrary.bounds(model)
		var s := float(look.get("size", 0.35)) / maxf(maxf(b.size.x, b.size.z), 0.001)
		model.scale = Vector3.ONE * s
		model.position.y = -b.position.y * s
		if look.has("tint"):
			ModelLibrary.tint(model, look["tint"])
		for gi in model.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(gi as GeometryInstance3D).visibility_range_end = 70.0
		c.add_child(model)
		var ap := model.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			var player := ap[0] as AnimationPlayer
			var want := "Flying" if c.move == Move.FLY else "Walk"
			for a in player.get_animation_list():
				if String(a).contains(want) or String(a).contains("Run") or String(a).contains("Jump"):
					player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
					player.play(a)
					break
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = float(look.get("size", 0.35)) * 0.5
		sm.height = sm.radius * 1.6
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.albedo_color = look.get("tint", Color(0.5, 0.4, 0.3))
		mi.material_override = mat
		mi.position.y = sm.radius
		c.add_child(mi)
	c.position = at
	c._angle = randf() * TAU
	c._alt = randf_range(14.0, 26.0)
	c._goal = at
	c.set_meta("damageable", c)
	return c


func _ready() -> void:
	add_to_group("critters")
	_player = get_tree().get_first_node_in_group("player") as Node3D


func is_alive() -> bool:
	return not _dead


## Any hit kills it, and it leaves what it had
func take_damage(_info: DamageInfo) -> float:
	if _dead:
		return 0.0
	_dead = true
	for d in drops:
		if randf() < float(d[1]):
			var item := load(String(d[0])) as ItemData
			if item != null and get_parent() != null:
				WorldItem.spawn(item, 1, get_parent(), global_position + Vector3.UP * 0.3)
	queue_free()
	return 1.0


func _physics_process(delta: float) -> void:
	if _dead:
		return
	match move:
		Move.FLY:
			_fly(delta)
		Move.PERCH:
			pass
		_:
			_hop(delta)


func _hop(delta: float) -> void:
	if _player != null and is_instance_valid(_player):
		var away := global_position - _player.global_position
		away.y = 0.0
		if away.length() < FLEE_RANGE:
			_fleeing = 2.5
			_goal = global_position + away.normalized() * 10.0
	_fleeing = maxf(_fleeing - delta, 0.0)
	var to := _goal - global_position
	to.y = 0.0
	if to.length() < 0.3:
		_wait -= delta
		if _wait <= 0.0:
			_wait = randf_range(1.0, 4.0)
			_goal = home + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
		return
	var step := to.normalized() * speed * (1.8 if _fleeing > 0.0 else 1.0) * delta
	var at := global_position + step
	if _world != null:
		at.y = _world.get_height_at(at.x, at.z)
	global_position = at
	rotation.y = atan2(step.x, step.z)


func _fly(delta: float) -> void:
	_angle += delta * speed / 12.0
	var at := home + Vector3(cos(_angle) * 12.0, _alt + sin(_angle * 2.3) * 2.0, sin(_angle) * 12.0)
	var step := at - global_position
	global_position = at
	if step.length() > 0.001:
		rotation.y = atan2(step.x, step.z)
