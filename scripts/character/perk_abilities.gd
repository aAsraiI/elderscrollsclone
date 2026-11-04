class_name PerkAbilities
extends Node
## Alpha 1.27.3: perks that give a move of your own, on G (Shift+G picks the next one you own).
##   Shield Charge     (Guardian)  a rush forward: everyone in the way is struck and knocked off balance
##   Whirlwind Sprint  (Wanderer)  a burst of speed straight ahead, faster than any horse
##   Shadow Step       (Shadow)    step behind the foe you look at (12 m) and fade from sight for 3 s
## Each has a cooldown; the chosen one is saved in WorldState "ability". Lives under the Player.

const ACTION := "perk_ability"
## id -> [name, perk, cooldown s, stamina, what it does]
const LIST := {
	"shield_charge": ["Shield Charge", "g_shield_charge", 18.0, 35.0, "Rush 7 m forward; everyone in the way is struck and staggered."],
	"whirlwind": ["Whirlwind Sprint", "wa_whirlwind_sprint", 14.0, 30.0, "A burst of speed: 12 m straight ahead in a blink."],
	"shadow_step": ["Shadow Step", "sh_shadow_step", 25.0, 25.0, "Step behind the foe you look at (12 m) and fade from sight for 3 s."],
}
const ORDER := ["shield_charge", "whirlwind", "shadow_step"]

var _player: CharacterBody3D
var _ready_at := {}  # id -> msec


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_G
		InputMap.action_add_event(ACTION, ev)


static func owned(player: Node) -> Array:
	var sk := player.get_node_or_null("Skills") as Skills if player != null else null
	var out := []
	if sk == null or sk.build == null:
		return out
	for id in ORDER:
		if sk.build.rank_of(LIST[id][1]) > 0:
			out.append(id)
	return out


func current() -> String:
	var have := owned(_player)
	if have.is_empty():
		return ""
	var pick := String(WorldState.get_record("ability").get("id", ""))
	return pick if have.has(pick) else String(have[0])


func cooldown_left(id: String) -> float:
	return maxf(float(_ready_at.get(id, 0)) - Time.get_ticks_msec(), 0.0) / 1000.0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION) or event.is_echo() or get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and (event as InputEventKey).shift_pressed:
		cycle()
	else:
		use()


## Shift+G: the next ability you own
func cycle() -> String:
	var have := owned(_player)
	if have.is_empty():
		Locks.toast(get_tree(), "No perk gives you a move yet (Character > Perks).", true)
		return ""
	var next: String = have[(have.find(current()) + 1) % have.size()]
	WorldState.set_record("ability", {"id": next})
	Locks.toast(get_tree(), "G: %s" % LIST[next][0])
	return next


## G: the chosen ability. Returns "" when it worked, or why not.
func use() -> String:
	var id := current()
	var why := ""
	if id == "":
		why = "No perk gives you a move yet (Character > Perks)."
	elif cooldown_left(id) > 0.0:
		why = "%s is ready in %d s." % [LIST[id][0], ceili(cooldown_left(id))]
	var stats := _player.get_node_or_null("Stats") as Stats
	if why == "" and stats != null and stats.stamina < float(LIST[id][3]):
		why = "Too tired for %s." % LIST[id][0]
	if why == "":
		match id:
			"shield_charge":
				why = _charge()
			"whirlwind":
				why = _whirlwind()
			"shadow_step":
				why = _shadow_step()
	if why != "":
		Locks.toast(get_tree(), why, true)
		return why
	if stats != null:
		stats.modify_vital("stamina", -float(LIST[id][3]))
	_ready_at[id] = Time.get_ticks_msec() + int(float(LIST[id][2]) * 1000.0)
	Achievements.note("ability")
	return ""


func _forward() -> Vector3:
	var f := -_player.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


# The player moves at this velocity for a moment (player.gd reads the "dash" meta)
func _dash(dist: float, seconds: float) -> void:
	_player.set_meta("dash", {"vel": _forward() * (dist / seconds), "until": Time.get_ticks_msec() + int(seconds * 1000.0)})


func _charge() -> String:
	_dash(7.0, 0.4)
	var start := _player.global_position
	var fwd := _forward()
	var sk := _player.get_node_or_null("Skills") as Skills
	var dmg := 12.0 + (float(sk.get_level(&"block")) * 0.4 if sk != null else 0.0)
	for n in ActorRegistry.near(start, 9.0):
		var e := n as Enemy
		if e == null or e.state == Enemy.State.DEAD or e.has_meta("player_ally"):
			continue
		var rel := e.global_position - start
		var along := rel.dot(fwd)
		if along < -0.5 or along > 8.0 or (rel - fwd * along).length() > 1.8:
			continue
		var info := DamageInfo.new(dmg, _player, &"melee")
		info.direction = fwd
		info.knockback = 6.0
		info.poise_damage = 120.0
		info.parryable = false
		info.ignores_block = true
		var mc := e.get_node_or_null("MeleeCombat") as MeleeCombat
		if mc != null:
			mc.take_damage(info)
			mc.stun(1.2)
		if e.disposition != Enemy.Disposition.HOSTILE:
			e.aggro(_player)
	return ""


func _whirlwind() -> String:
	_dash(12.0, 0.3)
	return ""


func _shadow_step() -> String:
	var cam := _player.get_node_or_null("Head/Camera3D") as Node3D
	var from := cam.global_position if cam != null else _player.global_position + Vector3.UP * 1.6
	var look := -(cam.global_transform.basis.z if cam != null else _player.global_transform.basis.z)
	var best: Enemy = null
	var best_dot := 0.94
	for n in ActorRegistry.near(_player.global_position, 12.0):
		var e := n as Enemy
		if e == null or e.state == Enemy.State.DEAD or e.has_meta("player_ally"):
			continue
		var to := (e.global_position + Vector3.UP - from)
		var d := to.normalized().dot(look)
		if d > best_dot:
			best_dot = d
			best = e
	if best == null:
		return "Look at someone within 12 m."
	var behind := best.global_position + best.global_transform.basis.z * 1.2
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(behind + Vector3.UP * 2.0, behind + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		behind.y = (hit["position"] as Vector3).y + 0.1
	_player.global_position = behind
	_player.look_at(Vector3(best.global_position.x, _player.global_position.y, best.global_position.z), Vector3.UP)
	_player.velocity = Vector3.ZERO
	var m := ActiveMagic.of(_player)
	if m != null:
		m.apply_one({"id": "invisibility", "mag": 1.0, "dur": 3.0}, _player, "Shadow Step", "power")
	return ""
