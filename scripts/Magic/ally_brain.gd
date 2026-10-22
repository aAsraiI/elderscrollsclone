class_name AllyBrain
extends Node
## Makes an Enemy body fight FOR someone (summons, reanimated corpses): it follows its leader and
## attacks the nearest hostile creature, or whatever is fighting its leader. Added by SpellCaster.

const THINK := 0.3
const FOLLOW_DIST := 4.0
const SEARCH_RADIUS := 22.0
const TELEPORT_DIST := 45.0

var leader: Node3D
var _body: Enemy
var _timer := 0.0


static func attach(e: Enemy, p_leader: Node3D) -> AllyBrain:
	var b := AllyBrain.new()
	b.name = "AllyBrain"
	b.leader = p_leader
	e.add_child(b)
	return b


func _ready() -> void:
	_body = get_parent() as Enemy
	_body.set_meta("player_ally", true)
	_body.flee_time = 0.0
	_body.combat.hit_mask = MagicHit.LAYER_WORLD | MagicHit.LAYER_ENEMY


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = THINK
	if _body == null or _body.is_dead() or leader == null or not is_instance_valid(leader):
		return
	var foe := _pick_foe()
	if foe != null:
		if _body.get_fight_target() != foe:
			_body.fight(foe)
		return
	if _body.state == Enemy.State.CHASE or _body.state == Enemy.State.ATTACK:
		_body.stop_fighting()
	if _body.has_meta("wait_here"):
		return  # told to wait: stays put (but still fights what comes near)
	var d := _body.global_position.distance_to(leader.global_position)
	if d > TELEPORT_DIST:
		var back := -leader.global_transform.basis.z
		_body.global_position = leader.global_position - back.normalized() * 2.0 + Vector3.UP * 0.5
		_body.velocity = Vector3.ZERO
	elif d > FOLLOW_DIST:
		var to := leader.global_position
		if not _body.is_on_route() or _body.route.is_empty() or _body.route[_body.route.size() - 1].distance_to(to) > 2.0:
			_body.follow_route(PackedVector3Array([to]), false, 1.0 if d > 10.0 else 0.6)
	elif _body.is_on_route():
		_body.stop_route()


func _pick_foe() -> Enemy:
	var current := _body.get_fight_target() as Enemy
	if current != null and is_instance_valid(current) and not current.is_dead() \
			and current.global_position.distance_to(leader.global_position) < SEARCH_RADIUS * 1.5:
		return current
	var best: Enemy = null
	var best_d := SEARCH_RADIUS
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == _body or e.is_dead() or e.has_meta("player_ally"):
			continue
		# Hostile creatures, and anyone the player is already fighting
		if e.disposition != Enemy.Disposition.HOSTILE and not e.get_meta("wronged_by_player", false):
			continue
		var d := e.global_position.distance_to(leader.global_position)
		if d < best_d and (e.is_alerted() or d < 10.0):
			best_d = d
			best = e
	return best
