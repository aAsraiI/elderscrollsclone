class_name AnimationHooks
extends Node
## The one place where gameplay asks for an animation. Safe with NO animations: nothing happens.
##
## Today: connect to the `triggered` signal, or turn on log_triggers to watch the calls.
## Later: put an AnimationPlayer anywhere under the Player / Enemy (it is found automatically,
## or assign it below) and name animations after the actions. For a weapon with
## animation_set = "sword" the lookup is "sword_attack" first, then plain "attack".
## Combo swings ask for a variant: the 2nd swing looks for "sword_attack_2" first, the 3rd
## for "sword_attack_3", then falls back to "sword_attack". Attack animations are sped up or
## slowed down to fit the swing's total time.
##
## Actions (the animation names to create):
##   idle  walk  run  alert
##   attack  attack_off  attack_heavy  slam  bash
##   block_start  block_end  block_hit  block_break  parry
##   hit_react  death

const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"
const ALERT := &"alert"
const ATTACK := &"attack"
const ATTACK_OFF := &"attack_off"
const ATTACK_HEAVY := &"attack_heavy"
const SLAM := &"slam"
const BASH := &"bash"
const BLOCK_START := &"block_start"
const BLOCK_END := &"block_end"
const BLOCK_HIT := &"block_hit"
const BLOCK_BREAK := &"block_break"
const PARRY := &"parry"
const HIT_REACT := &"hit_react"
const DEATH := &"death"

## duration > 0 means "this action should take about this many seconds" (the swing's total time)
signal triggered(action: StringName, set_name: StringName, duration: float)
## Same call, plus which swing of a combo it is (0 = first)
signal variant_triggered(action: StringName, set_name: StringName, duration: float, variant: int)

@export var animation_player: AnimationPlayer
## Where to look for an AnimationPlayer. Defaults to this node's parent.
@export var search_root: Node
@export var log_triggers := false


## Returns true if a real animation was started.
func trigger(action: StringName, anim_set: StringName = &"", duration: float = 0.0, variant: int = 0) -> bool:
	triggered.emit(action, anim_set, duration)
	variant_triggered.emit(action, anim_set, duration, variant)
	if log_triggers:
		print("[anim] %s  set='%s'  duration=%.2f  variant=%d" % [action, anim_set, duration, variant])
	if animation_player == null or not is_instance_valid(animation_player):
		animation_player = _find_player(search_root if search_root != null else get_parent())
	if animation_player == null:
		return false
	var anim := _resolve(action, anim_set, variant)
	if anim == &"":
		return false
	var speed := 1.0
	if duration > 0.0:
		var length := animation_player.get_animation(anim).length
		if length > 0.0:
			speed = clampf(length / duration, 0.25, 4.0)
	animation_player.play(anim, -1.0, speed)
	return true


func _resolve(action: StringName, anim_set: StringName, variant: int) -> StringName:
	var names: Array[String] = []
	if variant > 0:
		if anim_set != &"":
			names.append("%s_%s_%d" % [anim_set, action, variant + 1])
		names.append("%s_%d" % [action, variant + 1])
	if anim_set != &"":
		names.append("%s_%s" % [anim_set, action])
	names.append(String(action))
	for n in names:
		if animation_player.has_animation(n):
			return StringName(n)
	return &""


func _find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var deeper := _find_player(child)
		if deeper != null:
			return deeper
	return null
