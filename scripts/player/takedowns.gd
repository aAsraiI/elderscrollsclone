class_name Takedowns
extends RefCounted
## Alpha 1.24 (immersive sim): putting people down without killing them.
##   chokehold  sneaking up behind someone who hasn't noticed you, E knocks them out
##   cudgel     a sneak attack with a cudgel knocks out instead of hurting
## The knocked out lie where they fell for a couple of minutes (nothing wakes them early), then get up
## and remember: they are alert and go looking for you. Your kills and knock-outs are counted
## (WorldState "tally"): the town and Chaos (1.24.9) read them.

const REACH := 1.7
const BEHIND := 0.35  # how far round their back you must be (dot of their facing and the way to you)
const OUT_MIN := 90.0
const OUT_MAX := 150.0
const TALLY := "tally"


## Who you could knock out right now (null = no one)
static func candidate(player: Node3D) -> Enemy:
	if player == null or not player.has_meta("stealth"):
		return null
	var st: Variant = player.get_meta("stealth")
	if not is_instance_valid(st) or not bool(st.get("sneaking")):
		return null
	var best: Enemy = null
	var best_d := REACH
	for e in ActorRegistry.near(player.global_position, REACH + 0.5):
		if e.is_dead() or e.body_kind != CreatureBody.Kind.HUMANOID or is_out(e) or e.is_alerted() or e.has_meta("player_ally"):
			continue
		if e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK or e.state == Enemy.State.FLEE:
			continue
		var to_me := player.global_position - e.global_position
		to_me.y = 0.0
		var d := to_me.length()
		if d > best_d:
			continue
		var facing := -e.global_transform.basis.z
		facing.y = 0.0
		if facing.normalized().dot(to_me.normalized()) > -BEHIND and not e.asleep:
			continue  # you must be behind them (a sleeper can be taken from anywhere)
		best_d = d
		best = e
	return best


## Knocks someone out (a chokehold or a cudgel)
static func knock_out(e: Enemy, by_player: bool = true) -> void:
	if e == null or e.is_dead() or is_out(e):
		return
	e.stop_fighting()
	e.sleep()
	e.set_meta("knocked_out_until", e._clock + randf_range(OUT_MIN, OUT_MAX))
	e.set_meta("knocked_out", true)
	if by_player:
		count("knockouts")
		var crime := e.get_tree().get_first_node_in_group("crime") as CrimeManager
		if crime != null and e.disposition != Enemy.Disposition.HOSTILE:
			crime.on_player_hurt(e, false)  # knocking out a townsperson is still assault, if seen


static func is_out(e: Node) -> bool:
	return e != null and e.has_meta("knocked_out")


## Enemy calls this each think: up again when the time is up, alert and looking for you
static func tick(e: Enemy) -> bool:
	if not is_out(e):
		return false
	if e._clock < float(e.get_meta("knocked_out_until", 0.0)):
		return true
	e.remove_meta("knocked_out")
	e.remove_meta("knocked_out_until")
	e.wake()
	e._alerted = true
	if e.disposition == Enemy.Disposition.HOSTILE:
		var p := e.get_tree().get_first_node_in_group("player") as Node3D
		if p != null:
			e.follow_route(PackedVector3Array([e.global_position + (p.global_position - e.global_position).normalized() * 6.0]), false, 0.6)
	return false


static func count(what: String) -> void:
	var t := WorldState.get_record(TALLY).duplicate()
	t[what] = int(t.get(what, 0)) + 1
	WorldState.set_record(TALLY, t)


static func tally(what: String) -> int:
	return int(WorldState.get_record(TALLY).get(what, 0))
