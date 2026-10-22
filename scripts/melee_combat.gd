class_name MeleeCombat
extends Node
## Melee combat for the Player AND for enemies. It never reads input: PlayerCombat (mouse) or
## Enemy (AI) call light_attack(), heavy_attack(), secondary_press() and friends.
##
## Setup (Player): add a Node named MeleeCombat as a child of the Player (next to Stats /
## Equipment / Skills) and attach this script. It finds everything else on its own.
##
## ---------------------------------------------------------------- how a swing works
## Every attack goes through three phases, like the first-person melee games it is modeled on:
##   WINDUP    the weapon is being drawn back. Nothing can be hurt yet. Enemies can be told
##             about it (telegraph), and a hit on an enemy in this phase flinches it.
##   ACTIVE    the hit window. Rays sweep across the swing and every target is hit once.
##             ARC weapons sweep their whole arc during this time, so the swing visibly
##             "travels" and hits what is in front of it as it passes.
##   RECOVERY  the weapon returns. Blocking can cancel it; a click in the last moments of it
##             is remembered (input buffer) and fires the instant you are ready.
## A swing started within a moment of the last one CHAINS into a combo: it winds up a bit
## faster, alternates direction, and the last swing of the combo is a finisher.
##
## Light vs heavy: PlayerCombat calls begin_charge() on press and release_charge() on release.
## A tap = a light swing. Holding past the weapon's charge time = a heavy attack on release.
## Pressing right click while charging cancels the charge (feint).
##
## Stamina: a swing with too little stamina still happens, but it is slower and weaker
## ("winded"). Heavy attacks need the stamina or they become light swings.
##
## ---------------------------------------------------------------- stagger rules
## Hits chip at `poise`. At 0 the victim is STAGGERED: stun() cancels whatever it was doing,
## it cannot start or finish any attack, block or charge until the stun ends, and it takes
## bonus damage meanwhile. A stunned MeleeCombat never lands a hit. A parry (a block raised
## just before the hit lands) staggers the attacker outright.
##
## Physics layers: 1 = world (and the player), 5 (value 16) = enemies.

signal attack_started(hand: int, weapon: ItemData)
## The hit window closed without touching anything
signal attack_missed(hand: int, weapon: ItemData)
signal hit_dealt(target: Node, info: DamageInfo, final_amount: float)
signal slam_started(weapon: ItemData)
signal block_started(item: ItemData)
signal block_ended
signal blocked(info: DamageInfo, absorbed: float)
signal block_broken
## We parried a hit (info.source is now staggered)
signal parried(info: DamageInfo)
## We were hit. final_amount is what actually came off our health.
signal damaged(info: DamageInfo, final_amount: float)
## reason: &"cooldown", &"stamina" (also sent when a swing goes ahead "winded"), &"blocking", &"stunned"
signal attack_failed(reason: StringName)
## The swing moved to a new phase (see Phase). duration is how long that phase lasts.
signal phase_changed(phase: int, duration: float)
signal charge_started
## The held attack has been held long enough to become a heavy attack
signal charge_ready
signal charge_cancelled
## Our poise broke. info can be null (forced stagger).
signal staggered(info: DamageInfo)
## We can't act for this many seconds (stagger or flinch)
signal stunned(duration: float)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }
enum Kind { LIGHT, HEAVY, SLAM, BASH }

const LAYER_WORLD := 1
const LAYER_ENEMY := 16

const MAIN := ItemData.EquipSlot.MAIN_HAND
const OFF := ItemData.EquipSlot.OFF_HAND

# Fists
const UNARMED_REACH := 1.4
const UNARMED_DAMAGE := 0.0
const UNARMED_COOLDOWN := 0.55
const UNARMED_WINDUP := 0.05
const UNARMED_ACTIVE := 0.12
const UNARMED_POISE := 4.0
const UNARMED_CHARGE_TIME := 0.6
const UNARMED_HEAVY_COST := 8.0

# Damage balance
const ARMOR_REDUCTION_PER_POINT := 0.01  # 25 armor = 25% less damage
const MAX_ARMOR_REDUCTION := 0.8
const MAX_BLOCK_REDUCTION := 0.9
const BLOCK_STAMINA_PER_DAMAGE := 0.5  # stamina spent per point of damage absorbed
const BLOCK_MOVE_MULT := 0.6
const BLOCK_RAISE_COST := 3.0  # stamina to raise the guard (stops parry spam)
const BLOCK_RELAX_TIME := 0.2  # after lowering the guard you can't raise it for this long
const SLAM_MIN_FALLOFF := 0.5  # splash damage at the very edge of the radius
const SLAM_ACTIVE := 0.05
const SLAM_RECOVERY := 0.3
const SLAM_POISE_MULT := 1.8
const BASH_REACH := 1.8
const BASH_WINDUP := 0.12
const BASH_ACTIVE := 0.10
const BASH_RECOVERY := 0.35
const BASH_DAMAGE_MULT := 0.4
const BASH_KNOCKBACK := 5.0
const WEAPON_XP_PER_DAMAGE := 0.2
const BLOCK_XP_PER_DAMAGE := 0.3
const ARMOR_XP_PER_DAMAGE := 0.15
const PARRY_XP_MULT := 2.0
const PARRY_STUN := 1.1
const PARRY_STAMINA_REFUND := 10.0
const PUNISH_DAMAGE_MULT := 1.35  # hitting something that is staggered

# Feel
const MIN_RECOVERY := 0.08
const BUFFER_TIME := 0.5  # a click this long before you are ready is remembered
const COMBO_WINDOW := 0.55  # seconds after a swing's recovery in which the next swing chains
const COMBO_WINDUP_MULT := 0.85
const FINISHER_DAMAGE_MULT := 1.25
const FINISHER_POISE_MULT := 1.5
const FINISHER_KNOCKBACK_MULT := 1.5
const FINISHER_RECOVERY_MULT := 1.3
const DUAL_SWITCH_AT := 0.5  # the other hand may swing once this much of the recovery is over
const WINDED_WINDUP_MULT := 1.4
const WINDED_DAMAGE_MULT := 0.7
const WINDED_POISE_MULT := 0.5
const WINDED_RECOVERY_MULT := 1.3
const HEAVY_ACTIVE_MULT := 1.25
const HEAVY_RECOVERY_MULT := 1.4
const HEAVY_KNOCKBACK_MULT := 1.6
const CHARGE_MOVE_MULT := 0.7
const WINDUP_MOVE_MULT := 0.8
const RECOVERY_MOVE_MULT := 0.85

# Hit detection rays (degrees)
const SINGLE_YAWS: Array[float] = [0.0, -3.0, 3.0, -6.0, 6.0]
const SINGLE_PITCHES: Array[float] = [0.0, -6.0]
const ARC_PITCHES: Array[float] = [0.0, -10.0]

@export var stats: Stats
@export var equipment: Equipment
## Optional. Only the player has one: hits, blocks and wearing armor train skills.
@export var skills: Skills
## Where rays start and which way they point. Default: Head/Camera3D, else Head, else the body.
@export var aim_origin: Node3D
@export var animation: AnimationHooks
## What attack rays can hit. The player: world + enemies. Enemies set this to world only
## (the player lives on layer 1 with the world).
@export_flags_3d_physics var hit_mask: int = LAYER_WORLD | LAYER_ENEMY
## Degrees between the rays of an ARC attack (smaller = more rays, fewer gaps)
@export var ray_step_degrees := 8.0
## Draws every ray for a moment after each swing tick (yellow = missed, red = hit something)
@export var debug_draw := false

@export_group("Poise")
## Hits subtract their poise damage from this. At 0 the owner is staggered.
@export var max_poise := 40.0
## false = never staggered (the player: being locked out of control is not fun in first person)
@export var staggerable := true
## How long a stagger lasts (seconds)
@export var stagger_time := 0.8
## After a stagger ends, poise can't be chipped for this long (stops stun-locking)
@export var stagger_grace := 0.5
## Seconds without being hit before poise starts coming back
@export var poise_regen_delay := 2.0
@export var poise_regen_per_second := 15.0
## true = a hit during WINDUP flinches the owner and cancels the swing ("whoever hits first wins").
## Enemies turn this on; the player does not need it.
@export var interruptible_windup := false
@export var flinch_time := 0.35

@export_group("Feel")
## Seconds added to every windup. Enemies use this to telegraph their swings.
@export var windup_add := 0.0
## Forward step (m/s) when a swing becomes active, so attacks carry you into the target
@export var lunge_speed := 2.5
## How much of a hit's knockback shoves the PLAYER's body (enemies handle their own)
@export var shove_scale := 0.8

var body: Node3D
## Current poise (see max_poise)
var poise := 40.0

var _exclude: Array[RID] = []
var _phase := Phase.IDLE
var _phase_left := 0.0
var _phase_len := 0.0
var _act: Dictionary = {}
var _stun := 0.0
var _grace := 0.0
var _poise_wait := 0.0
var _secondary_cd := 0.0
var _buffer: Dictionary = {}
var _combo := 0
var _combo_timer := 0.0
var _charging := false
var _charge_time := 0.0
var _charge_ready_sent := false
var _blocking := false
var _block_item: ItemData
var _block_age := 0.0
var _block_relax := 0.0


func _ready() -> void:
	var parent := get_parent()
	body = parent as Node3D
	if body == null:
		push_error("MeleeCombat: must be a child of a Node3D body (Player or Enemy).")
		set_physics_process(false)
		return
	if stats == null:
		stats = parent.get_node_or_null("Stats") as Stats
	if equipment == null:
		equipment = parent.get_node_or_null("Equipment") as Equipment
	if skills == null:
		skills = parent.get_node_or_null("Skills") as Skills
	if stats == null:
		push_error("MeleeCombat: could not find a Stats node next to it.")
		set_physics_process(false)
		return

	if aim_origin == null:
		aim_origin = parent.get_node_or_null("Head/Camera3D") as Node3D
	if aim_origin == null:
		aim_origin = parent.get_node_or_null("Head") as Node3D
	if aim_origin == null:
		aim_origin = body

	if animation == null:
		animation = parent.get_node_or_null("AnimationHooks") as AnimationHooks
	if animation == null:
		animation = AnimationHooks.new()
		animation.name = "AnimationHooks"
		animation.search_root = body
		add_child(animation)

	var collider := body as CollisionObject3D
	if collider != null:
		_exclude.append(collider.get_rid())
	# Rays look for this on whatever they hit
	body.set_meta("damageable", self)

	poise = max_poise
	stats.died.connect(_on_died)
	if equipment != null:
		equipment.unequipped.connect(_on_unequipped)


func _physics_process(delta: float) -> void:
	_secondary_cd = maxf(_secondary_cd - delta, 0.0)
	_block_relax = maxf(_block_relax - delta, 0.0)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _blocking:
		_block_age += delta
	_tick_poise(delta)

	if _charging:
		_charge_time += delta
		if not _charge_ready_sent and _charge_time >= get_charge_threshold():
			_charge_ready_sent = true
			charge_ready.emit()

	if _stun > 0.0:
		_stun = maxf(_stun - delta, 0.0)
		return  # a staggered fighter does nothing at all
	_advance_phase(delta)
	_try_buffer(delta)


# ---------------------------------------------------------------- public API: attacking

## One light swing with the main hand (fists if empty). Chains into a combo when repeated.
## If a swing is still finishing, the click is remembered and fires as soon as you are ready.
## While blocking this is a shield bash instead.
func light_attack(quiet: bool = false) -> bool:
	if _blocking:
		return _bash()
	return _request(Kind.LIGHT, MAIN, null, 0.0, quiet)


## One heavy swing with the main hand. Players get here by holding left click.
func heavy_attack(quiet: bool = false) -> bool:
	if _blocking:
		return _bash()
	return _request(Kind.HEAVY, MAIN, null, 0.0, quiet)


## Old name for light_attack(). `repeat` = a held button trying again (fails quietly).
func primary_attack(repeat: bool = false) -> bool:
	return light_attack(repeat)


## Left click pressed. Starts winding up; release_charge() decides light or heavy.
## While blocking this bashes right away.
func begin_charge() -> bool:
	if not is_alive():
		return false
	if _stun > 0.0:
		return _fail(&"stunned", true)
	if _blocking:
		return _bash()
	if _charging:
		return true
	_charging = true
	_charge_time = 0.0
	_charge_ready_sent = false
	charge_started.emit()
	return true


## Left click released: a tap swings light, a long hold swings heavy.
func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	var held := _charge_time
	_charge_time = 0.0
	_charge_ready_sent = false
	if held >= get_charge_threshold():
		_request(Kind.HEAVY, MAIN, null, 0.0, true)
	else:
		# The weapon was already being drawn back while you held, so the windup is shorter
		_request(Kind.LIGHT, MAIN, null, held, true)


func cancel_charge() -> void:
	if not _charging:
		return
	_charging = false
	_charge_time = 0.0
	_charge_ready_sent = false
	charge_cancelled.emit()


## Right click, pressed. Checks the main hand, then the off hand, for a right-click action:
## SLAM (hammer) -> slam, BLOCK (shield) -> start blocking. Otherwise an off-hand weapon
## (second dagger) attacks with that hand.
func secondary_press(repeat: bool = false) -> bool:
	if not is_alive():
		return false
	if _stun > 0.0:
		return _fail(&"stunned", true)
	cancel_charge()
	for slot in [MAIN, OFF]:
		var item: ItemData = equipment.get_equipped(slot) if equipment != null else null
		if item == null:
			continue
		match item.secondary_action:
			ItemData.SecondaryAction.SLAM:
				if _secondary_cd > 0.0:
					return _fail(&"cooldown", repeat)
				return _request(Kind.SLAM, MAIN, item, 0.0, repeat)
			ItemData.SecondaryAction.BLOCK:
				return _start_block(item, repeat)
	var off := _weapon_in(OFF)
	if off != null:
		if _blocking:
			return _fail(&"blocking", repeat)
		return _request(Kind.LIGHT, OFF, null, 0.0, repeat)
	return false


## Right click, released
func secondary_release() -> void:
	stop_block()


func stop_block() -> void:
	if not _blocking:
		return
	_blocking = false
	_block_relax = BLOCK_RELAX_TIME
	var set_name := _block_item.animation_set if _block_item != null else &""
	_block_item = null
	animation.trigger(AnimationHooks.BLOCK_END, set_name)
	block_ended.emit()


# ---------------------------------------------------------------- public API: stagger

## The owner can't act for `duration` seconds: whatever it was doing is cancelled, and it can't
## swing, block or charge until the time is up. This is what makes a staggered enemy harmless.
func stun(duration: float) -> void:
	if duration <= 0.0 or not is_alive():
		return
	_stun = maxf(_stun, duration)
	_cancel_action()
	cancel_charge()
	stop_block()
	stunned.emit(duration)


## Staggers right now (poise back to full, with a short grace period afterwards).
## duration < 0 uses stagger_time. Parries use this on the attacker.
func force_stagger(duration: float = -1.0, info: DamageInfo = null) -> void:
	if not is_alive():
		return
	var d := stagger_time if duration < 0.0 else duration
	poise = max_poise
	_grace = d + stagger_grace
	stun(d)
	staggered.emit(info)


## Cancels swings that haven't landed yet (death). Cooldowns keep running.
func interrupt() -> void:
	_cancel_action()


func is_stunned() -> bool:
	return _stun > 0.0


# ---------------------------------------------------------------- public API: state

func is_blocking() -> bool:
	return _blocking


## Seconds since the guard was raised. Under the item's parry_window a hit is a parry.
func get_block_age() -> float:
	return _block_age if _blocking else 0.0


func get_block_item() -> ItemData:
	return _block_item


## A swing is in progress (windup, hit window or recovery)
func is_busy() -> bool:
	return _phase != Phase.IDLE


## The swing is committed: it is winding up or hurting things right now
func is_attacking() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.ACTIVE


func is_alive() -> bool:
	return stats != null and not stats.is_dead


func get_phase() -> int:
	return _phase


## 0..1 through the current phase
func get_phase_progress() -> float:
	if _phase == Phase.IDLE:
		return 0.0
	if _phase_len <= 0.0:
		return 1.0
	return clampf(1.0 - _phase_left / _phase_len, 0.0, 1.0)


## Kind of the swing in progress, or -1
func get_action_kind() -> int:
	return int(_act["kind"]) if not _act.is_empty() else -1


## MAIN or OFF hand of the swing in progress
func get_action_hand() -> int:
	return int(_act["hand"]) if not _act.is_empty() else MAIN


func get_action_weapon() -> ItemData:
	return _act["weapon"] if not _act.is_empty() else null


## +1 / -1: which way the swing travels (alternates down a combo)
func get_swing_dir() -> float:
	return float(_act["dir"]) if not _act.is_empty() else 1.0


func is_heavy_action() -> bool:
	return not _act.is_empty() and bool(_act["heavy"])


func get_combo_step() -> int:
	return int(_act["combo"]) if not _act.is_empty() else _combo


func is_charging() -> bool:
	return _charging


func get_charge_time() -> float:
	return _charge_time if _charging else 0.0


## 0..1, 1 = the next release is a heavy attack
func get_charge_ratio() -> float:
	if not _charging:
		return 0.0
	return clampf(_charge_time / maxf(get_charge_threshold(), 0.01), 0.0, 1.0)


func get_charge_threshold() -> float:
	var w := _weapon_in(MAIN)
	return w.heavy_charge_time if w != null else UNARMED_CHARGE_TIME


## Reach of the main-hand weapon (fists if empty), including the reach_bonus stat
func get_main_reach() -> float:
	return _reach_of(_weapon_in(MAIN))


## Seconds until the swing in progress is over (0 when idle). Kept for old callers.
func get_cooldown(_hand: int) -> float:
	return _phase_left if _phase != Phase.IDLE else 0.0


func get_slam_cooldown() -> float:
	return _secondary_cd


## Player movement multiplier: slower while blocking, charging, winding up or recovering
func get_move_speed_multiplier() -> float:
	var m := 1.0
	if _blocking:
		m = BLOCK_MOVE_MULT
	elif _charging:
		m = CHARGE_MOVE_MULT
	match _phase:
		Phase.WINDUP:
			m *= WINDUP_MOVE_MULT
		Phase.RECOVERY:
			m *= RECOVERY_MOVE_MULT
	return m


# ---------------------------------------------------------------- taking damage

## Everything that hurts us goes through here: parry, block, armor, health, then poise.
## Returns the damage that actually came off our health.
func take_damage(info: DamageInfo) -> float:
	if not is_alive():
		return 0.0
	var amount := info.amount

	# 1. Parry: the guard went up just before the hit. No damage, and the attacker pays for it.
	if _blocking and _block_item != null and info.parryable and not info.ignores_block \
			and _block_age <= _block_item.parry_window and _block_covers(info):
		_do_parry(info)
		return 0.0

	# 2. Hitting something that is staggered hurts more
	if _stun > 0.0:
		amount *= PUNISH_DAMAGE_MULT
		info.punish = true

	# 3. Block
	if _blocking and _block_item != null and not info.ignores_block and _block_covers(info):
		var reduction := clampf(_block_item.block_reduction + stats.get_stat("block_strength"), 0.0, MAX_BLOCK_REDUCTION)
		var absorbed := amount * reduction
		var cost := absorbed * BLOCK_STAMINA_PER_DAMAGE
		if stats.stamina >= cost:
			stats.modify_vital("stamina", -cost)
			amount -= absorbed
			info.result = &"blocked"
			info.absorbed = absorbed
			if skills != null:
				skills.add_xp(&"block", absorbed * BLOCK_XP_PER_DAMAGE)
			animation.trigger(AnimationHooks.BLOCK_HIT, _block_item.animation_set)
			blocked.emit(info, absorbed)
		else:
			# Out of stamina: the guard breaks and the hit lands in full
			stats.modify_vital("stamina", -stats.stamina)
			animation.trigger(AnimationHooks.BLOCK_BREAK, _block_item.animation_set)
			stop_block()
			block_broken.emit()

	# 4. Armor (weapons) or resistance (elements), then health
	if info.element != &"":
		var resist := stats.get_stat("resist_" + String(info.element))
		if info.element != &"magic":
			resist = resist if resist >= 1.0 else clampf(resist, -1.0, MagicEffects.MAX_RESIST)
		else:
			resist = clampf(resist, -1.0, MagicEffects.MAX_RESIST)
		amount *= 1.0 - minf(resist, 1.0)
		if Weather.is_wet_at(body):
			amount *= Weather.WET_MULT.get(info.element, 1.0)
	else:
		var armor := stats.get_stat("armor")
		if info.weapon != null:
			armor *= 1.0 - info.weapon.armor_pierce  # maces crush through part of it
		amount *= 1.0 - clampf(armor * ARMOR_REDUCTION_PER_POINT, 0.0, MAX_ARMOR_REDUCTION)
	amount *= Difficulty.damage_mult(info.source, body)
	var final := maxf(amount, 0.0)
	if final > 0.0:
		_train_armor(final)
	stats.modify_vital("health", -final)
	if stats.is_dead:
		info.killed = true
	else:
		_shove(info)
		if info.result != &"blocked" and not info.dot:
			_apply_poise(info)
	damaged.emit(info, final)
	return final


func _do_parry(info: DamageInfo) -> void:
	info.result = &"parried"
	info.absorbed = info.amount
	if skills != null:
		skills.add_xp(&"block", info.amount * BLOCK_XP_PER_DAMAGE * PARRY_XP_MULT)
	stats.modify_vital("stamina", PARRY_STAMINA_REFUND)
	animation.trigger(AnimationHooks.PARRY, _block_item.animation_set)
	var attacker := info.get_attacker_combat() as MeleeCombat
	if attacker != null and attacker != self and attacker.is_alive():
		attacker.force_stagger(PARRY_STUN, info)
	parried.emit(info)


func _apply_poise(info: DamageInfo) -> void:
	if not staggerable or max_poise <= 0.0 or info.poise_damage <= 0.0:
		return
	_poise_wait = poise_regen_delay
	if _grace > 0.0 or _stun > 0.0:
		return  # already reeling: can't be chipped further
	poise -= info.poise_damage
	if poise <= 0.0:
		info.staggered = true
		force_stagger(stagger_time * (1.25 if info.heavy else 1.0), info)
	elif interruptible_windup and _phase == Phase.WINDUP and info.source != null and is_instance_valid(info.source) and info.source.is_in_group("player"):
		stun(flinch_time)  # only the player's hits cancel a swing: creature fights would stall forever


func _tick_poise(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)
	if poise >= max_poise or _grace > 0.0:
		return
	_poise_wait -= delta
	if _poise_wait <= 0.0:
		poise = minf(poise + poise_regen_per_second * delta, max_poise)


# The player has no stagger, so a hit is felt as a small shove instead
func _shove(info: DamageInfo) -> void:
	if info.knockback <= 0.0 or shove_scale <= 0.0:
		return
	var cb := body as CharacterBody3D
	if cb == null or not cb.is_in_group("player"):
		return
	var push := Vector3(info.direction.x, 0.0, info.direction.z)
	if push.length() < 0.001:
		return
	var scale := shove_scale * (0.5 if info.result == &"blocked" else 1.0)
	cb.velocity += push.normalized() * info.knockback * scale


# Only hits from inside the item's block_angle cone in front of us are blocked
func _block_covers(info: DamageInfo) -> bool:
	var forward := -_aim_transform().basis.z
	forward.y = 0.0
	var to_attacker := -info.direction
	to_attacker.y = 0.0
	if forward.length() < 0.001 or to_attacker.length() < 0.001:
		return true
	return forward.normalized().angle_to(to_attacker.normalized()) <= deg_to_rad(_block_item.block_angle * 0.5)


# ---------------------------------------------------------------- swing state machine

func _request(kind: int, hand: int, item: ItemData, pre: float, quiet: bool) -> bool:
	if not is_alive():
		return false
	if _stun > 0.0:
		return _fail(&"stunned", quiet)
	if _blocking:
		return _fail(&"blocking", quiet)
	if _can_start(hand):
		return _start(kind, hand, item, pre)
	# Still busy: remember the click and fire it the moment we are ready
	_buffer = {"kind": kind, "hand": hand, "item": item, "pre": 0.0, "age": 0.0}
	return true


func _can_start(hand: int) -> bool:
	if _stun > 0.0 or not is_alive():
		return false
	if _phase == Phase.IDLE:
		return true
	# Dual wielding: the other hand can swing once the first is half way through its recovery
	return _phase == Phase.RECOVERY and not _act.is_empty() and hand != int(_act["hand"]) \
			and _phase_left <= _phase_len * (1.0 - DUAL_SWITCH_AT)


func _try_buffer(delta: float) -> void:
	if _buffer.is_empty():
		return
	_buffer["age"] = float(_buffer["age"]) + delta
	if float(_buffer["age"]) > BUFFER_TIME:
		_buffer = {}
		return
	if _blocking or not _can_start(int(_buffer["hand"])):
		return
	var b := _buffer
	_buffer = {}
	_start(int(b["kind"]), int(b["hand"]), b["item"], float(b["pre"]))


func _advance_phase(delta: float) -> void:
	var left := delta
	var guard := 0
	while _phase != Phase.IDLE and left > 0.0 and guard < 6:
		guard += 1
		var step := minf(left, _phase_left)
		_phase_left -= step
		left -= step
		if _phase == Phase.ACTIVE:
			_sweep()
			if _phase != Phase.ACTIVE:
				return  # we were staggered (or died) mid-swing
		if _phase_left <= 0.0001:
			_next_phase()
		else:
			break


func _next_phase() -> void:
	match _phase:
		Phase.WINDUP:
			_enter_phase(Phase.ACTIVE, float(_act["active"]))
		Phase.ACTIVE:
			_end_active()
			_enter_phase(Phase.RECOVERY, float(_act["recovery"]))
		Phase.RECOVERY:
			_enter_phase(Phase.IDLE, 0.0)


func _enter_phase(phase: int, length: float) -> void:
	_phase = phase as Phase
	_phase_len = length
	_phase_left = length
	if phase == Phase.IDLE:
		_act = {}
	elif phase == Phase.ACTIVE:
		_begin_active()
	phase_changed.emit(phase, length)


func _begin_active() -> void:
	_act["t"] = 0.0
	if int(_act["kind"]) == Kind.SLAM:
		_resolve_slam(_act)
	else:
		_lunge(bool(_act["heavy"]))


func _end_active() -> void:
	var kind := int(_act["kind"])
	if not bool(_act["dealt"]) and kind != Kind.SLAM:
		attack_missed.emit(int(_act["hand"]), _act["weapon"])
	if kind == Kind.LIGHT:
		_combo_timer = float(_act["recovery"]) + COMBO_WINDOW
	else:
		_combo = 0
		_combo_timer = 0.0


func _cancel_action(keep_combo: bool = false) -> void:
	_buffer = {}
	if not keep_combo:
		_combo_timer = 0.0
	if _phase != Phase.IDLE:
		_enter_phase(Phase.IDLE, 0.0)


func _make_act(kind: int, hand: int, weapon: ItemData, windup: float, active: float, recovery: float) -> Dictionary:
	return {
		"kind": kind, "hand": hand, "weapon": weapon,
		"windup": windup, "active": maxf(active, 0.03), "recovery": recovery,
		"heavy": false, "combo": 0, "finisher": false, "winded": false, "dir": 1.0,
		"dmg_mult": 1.0, "poise_mult": 1.0, "knock_mult": 1.0,
		"hit": {}, "dealt": false, "t": 0.0,
	}


# Pays the stamina, works out every number of the swing and starts the windup
func _start(kind: int, hand: int, item: ItemData, pre: float) -> bool:
	if _phase != Phase.IDLE:
		_cancel_action(true)  # the other hand cutting in on a recovery
	if kind == Kind.SLAM:
		return _start_slam(item)

	var weapon := _weapon_in(hand)
	var heavy := kind == Kind.HEAVY
	var base_cost := weapon.stamina_cost if weapon != null else 0.0
	var cost := base_cost
	if heavy:
		var heavy_cost := base_cost * weapon.heavy_stamina_mult if weapon != null else UNARMED_HEAVY_COST
		if stats.stamina >= heavy_cost:
			cost = heavy_cost
		else:
			heavy = false  # too tired for a heavy swing: it becomes a normal one
	var winded := false
	if cost > 0.0:
		if stats.stamina >= cost:
			stats.modify_vital("stamina", -cost)
		else:
			winded = true
			if stats.stamina > 0.0:
				stats.modify_vital("stamina", -stats.stamina)
			attack_failed.emit(&"stamina")

	var combo_len := weapon.combo_length if weapon != null else 2
	var combo := 0
	if not heavy and _combo_timer > 0.0:
		combo = (_combo + 1) % maxi(combo_len, 1)
	_combo = 0 if heavy else combo
	var finisher := not heavy and combo_len > 1 and combo == combo_len - 1

	var base_windup := weapon.attack_windup if weapon != null else UNARMED_WINDUP
	var active := weapon.attack_active if weapon != null else UNARMED_ACTIVE
	var cooldown := weapon.attack_cooldown if weapon != null else UNARMED_COOLDOWN
	var recovery := maxf(cooldown - base_windup - active, MIN_RECOVERY)
	var windup := base_windup
	var dmg_mult := 1.0
	var poise_mult := 1.0
	var knock_mult := 1.0
	if heavy:
		windup = weapon.heavy_windup if weapon != null else 0.2
		active *= HEAVY_ACTIVE_MULT
		recovery *= HEAVY_RECOVERY_MULT
		dmg_mult = weapon.heavy_damage_mult if weapon != null else 1.6
		poise_mult = weapon.heavy_poise_mult if weapon != null else 2.0
		knock_mult = HEAVY_KNOCKBACK_MULT
	elif combo > 0:
		windup *= COMBO_WINDUP_MULT
	if finisher:
		dmg_mult *= FINISHER_DAMAGE_MULT
		poise_mult *= FINISHER_POISE_MULT
		knock_mult *= FINISHER_KNOCKBACK_MULT
		recovery *= FINISHER_RECOVERY_MULT
	if winded:
		windup *= WINDED_WINDUP_MULT
		dmg_mult *= WINDED_DAMAGE_MULT
		poise_mult *= WINDED_POISE_MULT
		recovery *= WINDED_RECOVERY_MULT
	if not heavy and pre > 0.0:
		windup -= minf(pre, windup * 0.65)  # the weapon was already drawn back while you held the button
	windup += windup_add

	_act = _make_act(Kind.HEAVY if heavy else Kind.LIGHT, hand, weapon, windup, active, recovery)
	_act["heavy"] = heavy
	_act["combo"] = combo
	_act["finisher"] = finisher
	_act["winded"] = winded
	_act["dir"] = 1.0 if combo % 2 == 0 else -1.0
	_act["dmg_mult"] = dmg_mult
	_act["poise_mult"] = poise_mult
	_act["knock_mult"] = knock_mult

	attack_started.emit(hand, weapon)
	var action := AnimationHooks.ATTACK_HEAVY if heavy else (AnimationHooks.ATTACK if hand == MAIN else AnimationHooks.ATTACK_OFF)
	animation.trigger(action, weapon.animation_set if weapon != null else &"", windup + float(_act["active"]) + recovery, combo)
	_enter_phase(Phase.WINDUP, windup)
	return true


func _start_slam(item: ItemData) -> bool:
	if item == null:
		return false
	if _secondary_cd > 0.0:
		return _fail(&"cooldown", true)
	if stats.stamina < item.secondary_stamina_cost:
		return _fail(&"stamina", false)
	stats.modify_vital("stamina", -item.secondary_stamina_cost)
	var windup := item.secondary_windup + windup_add
	_secondary_cd = item.secondary_cooldown
	_combo = 0
	_combo_timer = 0.0
	_act = _make_act(Kind.SLAM, MAIN, item, windup, SLAM_ACTIVE, SLAM_RECOVERY)
	_act["heavy"] = true
	slam_started.emit(item)
	animation.trigger(AnimationHooks.SLAM, item.animation_set, windup + SLAM_ACTIVE + SLAM_RECOVERY)
	_enter_phase(Phase.WINDUP, windup)
	return true


# Left click while the guard is up
func _bash() -> bool:
	if not is_alive() or _block_item == null:
		return false
	if _stun > 0.0:
		return _fail(&"stunned", true)
	if _phase != Phase.IDLE:
		return false
	var item := _block_item
	if stats.stamina < item.bash_stamina_cost:
		return _fail(&"stamina", false)
	stats.modify_vital("stamina", -item.bash_stamina_cost)
	stop_block()
	_block_relax = 0.0
	_combo = 0
	_combo_timer = 0.0
	_act = _make_act(Kind.BASH, OFF, item, BASH_WINDUP + windup_add, BASH_ACTIVE, BASH_RECOVERY)
	attack_started.emit(OFF, item)
	animation.trigger(AnimationHooks.BASH, item.animation_set, BASH_WINDUP + BASH_ACTIVE + BASH_RECOVERY)
	_enter_phase(Phase.WINDUP, BASH_WINDUP + windup_add)
	return true


# ---------------------------------------------------------------- blocking

func _start_block(item: ItemData, repeat: bool) -> bool:
	if _blocking:
		return true
	if _block_relax > 0.0:
		return _fail(&"cooldown", true)
	if _phase == Phase.WINDUP or _phase == Phase.ACTIVE:
		return false  # committed to a swing
	if stats.stamina <= 0.0:
		return _fail(&"stamina", repeat)
	stats.modify_vital("stamina", -minf(BLOCK_RAISE_COST, stats.stamina))
	_cancel_action()  # raising the guard cancels a recovery
	_blocking = true
	_block_item = item
	_block_age = 0.0
	animation.trigger(AnimationHooks.BLOCK_START, item.animation_set)
	block_started.emit(item)
	return true


func _on_unequipped(_slot: int, item: ItemData) -> void:
	if _blocking and item == _block_item and not equipment.is_equipped(item):
		stop_block()


func _on_died() -> void:
	_cancel_action()
	cancel_charge()
	stop_block()


# ---------------------------------------------------------------- hitting things

# Called every physics tick of the ACTIVE phase
func _sweep() -> void:
	var act := _act
	var kind := int(act["kind"])
	if kind == Kind.SLAM:
		return
	var arc := _is_arc(act)
	if bool(act["dealt"]) and not arc:
		return  # a single-target swing is over after its first hit
	var weapon: ItemData = act["weapon"]
	var xf := _aim_transform()
	var reach := _act_reach(act)
	var t0 := float(act["t"])
	var t1 := 1.0 - _phase_left / maxf(_phase_len, 0.001)
	act["t"] = t1

	var lines: Array = []
	var hits: Array[Dictionary]
	if arc:
		var arc_deg := weapon.arc_degrees * (1.15 if bool(act["heavy"]) else 1.0)
		hits = _sweep_arc(act, xf, reach, arc_deg, t0, t1, lines)
	else:
		hits = _stab(act, xf, reach, lines)
	if debug_draw:
		_draw_debug(lines)
	if hits.is_empty():
		return
	act["dealt"] = true
	var dmg := _act_damage(act)
	var kind_name: StringName = &"bash" if kind == Kind.BASH else &"melee"
	for h in hits:
		if _phase != Phase.ACTIVE:
			break  # a parry staggered us part way through: no more hits
		_deal(act, h["target"], h["position"], xf.origin, dmg, kind_name)


# ARC: the fan of rays travels across the arc as the swing progresses; every target is hit once
func _sweep_arc(act: Dictionary, xf: Transform3D, reach: float, arc_deg: float, t0: float, t1: float, lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := float(act["dir"])
	var a0 := dir * lerpf(-arc_deg * 0.5, arc_deg * 0.5, t0)
	var a1 := dir * lerpf(-arc_deg * 0.5, arc_deg * 0.5, t1)
	var steps := maxi(ceili(absf(a1 - a0) / maxf(ray_step_degrees, 1.0)), 1)
	var seen: Dictionary = act["hit"]
	for i in steps + 1:
		var angle := lerpf(a0, a1, float(i) / float(steps))
		for pitch in ARC_PITCHES:
			var hit := _cast(xf, angle, pitch, reach, lines)
			var target := _damageable_of(hit.get("collider"))
			if target == null or seen.has(target.get_instance_id()):
				continue
			seen[target.get_instance_id()] = true
			out.append({"target": target, "position": hit["position"]})
	return out


# SINGLE: a small cluster of rays, centre first. The first damageable thing touched is the target.
func _stab(act: Dictionary, xf: Transform3D, reach: float, lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = act["hit"]
	for pitch in SINGLE_PITCHES:
		for yaw in SINGLE_YAWS:
			var hit := _cast(xf, yaw, pitch, reach, lines)
			var target := _damageable_of(hit.get("collider"))
			if target != null and not seen.has(target.get_instance_id()):
				seen[target.get_instance_id()] = true
				out.append({"target": target, "position": hit["position"]})
				return out
	return out


func _resolve_slam(act: Dictionary) -> void:
	var weapon: ItemData = act["weapon"]
	var xf := _aim_transform()
	var radius := weapon.secondary_radius
	var impact := _slam_center(xf, _reach_of(weapon))
	var point: Vector3 = impact["point"]
	var primary: Node = impact["primary"]
	var dmg := _act_damage(act)

	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = hit_mask
	query.exclude = _exclude
	var found := body.get_world_3d().direct_space_state.intersect_shape(query, 32)

	if debug_draw:
		var lines: Array = []
		for k in 24:
			var a0 := TAU * float(k) / 24.0
			var a1 := TAU * float(k + 1) / 24.0
			lines.append([point + Vector3(cos(a0), 0.05, sin(a0)) * radius, point + Vector3(cos(a1), 0.05, sin(a1)) * radius, true])
		_draw_debug(lines)

	var seen := {}
	for r in found:
		var collider: Object = r["collider"]
		var target := _damageable_of(collider)
		if target == null or seen.has(target.get_instance_id()):
			continue
		seen[target.get_instance_id()] = true
		var victim_pos := point
		if collider is Node3D:
			victim_pos = (collider as Node3D).global_position
		# The one you smashed takes full damage, bystanders less the further they are
		var falloff := 1.0
		if target != primary:
			falloff = lerpf(1.0, SLAM_MIN_FALLOFF, clampf(point.distance_to(victim_pos) / radius, 0.0, 1.0))
		act["dealt"] = true
		_deal(act, target, victim_pos + Vector3.UP, xf.origin, dmg * falloff, &"slam")
	if primary != null and not seen.has(primary.get_instance_id()):
		act["dealt"] = true
		_deal(act, primary, point, xf.origin, dmg, &"slam")


func _deal(act: Dictionary, target: Node, pos: Vector3, from: Vector3, dmg: float, kind_name: StringName) -> void:
	var target_body := victim_body_of(target)
	if target_body != null and target_body != body and (body.has_meta("player_ally") or target_body.has_meta("player_ally")) and MagicHit.friendly(body, target_body):
		return  # summons and their master never hurt each other
	var weapon: ItemData = act["weapon"]
	var kind := int(act["kind"])
	var info := DamageInfo.new(dmg, body, kind_name)
	info.hit_position = pos
	info.direction = (pos - from).normalized()
	info.weapon = weapon
	info.knockback = _act_knockback(act)
	info.poise_damage = _act_poise(act)
	info.heavy = bool(act["heavy"])
	info.combo_step = int(act["combo"])
	info.parryable = kind == Kind.LIGHT or kind == Kind.HEAVY
	# The player: sneak attacks, and crimes against people who weren't hostile (CrimeManager)
	var victim: Enemy = target.get("body") as Enemy if "body" in target else null
	var wronged := false
	if body != null and body.is_in_group("player") and victim != null:
		var stealth: Variant = body.get_meta("stealth", null)
		if stealth != null and is_instance_valid(stealth) and kind != Kind.SLAM:
			var mult: float = stealth.sneak_attack_mult(victim, weapon)
			if mult > 1.0:
				info.amount *= mult
				info.sneak = true
				stealth.sneak_attack.emit(victim, mult)
		wronged = (victim.disposition != Enemy.Disposition.HOSTILE or victim.get_meta("wronged_by_player", false)) and not victim.has_meta("player_ally")
		if wronged:
			victim.set_meta("wronged_by_player", true)
	info.amount *= _bane_mult(target, weapon)
	var final: float = target.take_damage(info)
	if final > 0.0 or info.result == &"blocked":
		WeaponMagic.on_hit(body, victim_body_of(target), weapon, info)
	if wronged:
		var crime := body.get_tree().get_first_node_in_group("crime")
		if crime != null:
			crime.on_player_hurt(victim, info.killed)
	hit_dealt.emit(target, info, final)
	if skills != null and weapon != null and weapon.governing_skill != "none" and final > 0.0:
		skills.add_xp(StringName(weapon.governing_skill), final * WEAPON_XP_PER_DAMAGE)


# Advantages against kinds of foes, and silver against werewolves
func _bane_mult(target: Node, weapon: ItemData) -> float:
	var v := victim_body_of(target)
	var m := 1.0
	var e := v as Enemy
	if e != null:
		var id := e.enemy_id
		if id.contains("skeleton") or id.contains("wight") or id.contains("warden") or id == "vampire":
			m += stats.get_stat("bane_undead")
		if e.body_kind == CreatureBody.Kind.BEAST or e.body_kind == CreatureBody.Kind.CRAWLER or id == "werewolf":
			m += stats.get_stat("bane_beast")
	var wolf := (e != null and e.enemy_id == "werewolf") or (v != null and v.has_meta("beast_form"))
	if wolf and weapon != null and weapon.tier == 3:
		m *= 1.4  # silver
	return maxf(m, 0.1)


## The body (Player or Enemy) behind a damageable (its MeleeCombat), or null
func victim_body_of(target: Node) -> Node3D:
	if target == null or not is_instance_valid(target):
		return null
	if "body" in target:
		return target.get("body") as Node3D
	return target as Node3D


# damage = (base damage stat + this weapon's damage) * (1 + skill bonuses) * the swing's multipliers
func _damage_for(flat: float, mult: float) -> float:
	return stats.get_stat_plus("damage", flat) * mult


func _act_damage(act: Dictionary) -> float:
	var w: ItemData = act["weapon"]
	var mult := float(act["dmg_mult"])
	match int(act["kind"]):
		Kind.BASH:
			return _damage_for(w.bash_damage if w != null else 0.0, BASH_DAMAGE_MULT * mult)
		Kind.SLAM:
			return _damage_for(w.weapon_damage, w.secondary_damage_mult * mult)
	return _damage_for(w.weapon_damage if w != null else UNARMED_DAMAGE + stats.get_stat("unarmed_damage"), mult)


func _act_poise(act: Dictionary) -> float:
	var w: ItemData = act["weapon"]
	var base := UNARMED_POISE
	match int(act["kind"]):
		Kind.BASH:
			base = w.bash_poise
		Kind.SLAM:
			base = w.poise_damage * SLAM_POISE_MULT
		_:
			base = w.poise_damage if w != null else UNARMED_POISE
	return base * float(act["poise_mult"])


func _act_knockback(act: Dictionary) -> float:
	var w: ItemData = act["weapon"]
	var base := 0.0
	match int(act["kind"]):
		Kind.BASH:
			base = BASH_KNOCKBACK
		Kind.SLAM:
			base = w.knockback * 1.2
		_:
			base = w.knockback if w != null else 0.0
	return base * float(act["knock_mult"])


func _act_reach(act: Dictionary) -> float:
	var w: ItemData = act["weapon"]
	if int(act["kind"]) == Kind.BASH:
		return BASH_REACH + stats.get_stat("reach_bonus")
	var r := _reach_of(w)
	if bool(act["heavy"]) and w != null:
		r += w.heavy_reach_bonus
	return r


func _is_arc(act: Dictionary) -> bool:
	var w: ItemData = act["weapon"]
	return int(act["kind"]) != Kind.BASH and w != null and w.attack_style == ItemData.AttackStyle.ARC


func _reach_of(weapon: ItemData) -> float:
	return (weapon.reach if weapon != null else UNARMED_REACH) + stats.get_stat("reach_bonus")


func _weapon_in(slot: int) -> ItemData:
	if equipment == null:
		return null
	var item := equipment.get_equipped(slot)
	if item != null and item.item_type == ItemData.ItemType.WEAPON:
		return item
	return null


# A small step forward when the swing becomes active, so attacks carry you into the target
func _lunge(heavy: bool) -> void:
	if lunge_speed <= 0.0:
		return
	var cb := body as CharacterBody3D
	if cb == null or not cb.is_on_floor():
		return
	var xf := _aim_transform()
	var forward := -xf.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	forward = forward.normalized()
	# Don't shove through something that is already in your face
	if not _ray(xf.origin, xf.origin + forward * 0.9).is_empty():
		return
	cb.velocity += forward * lunge_speed * (1.4 if heavy else 1.0)


# ---------------------------------------------------------------- rays

# One ray, turned `yaw_deg` to the left (+) / right (-) and `pitch_deg` up (+) / down (-)
func _cast(xf: Transform3D, yaw_deg: float, pitch_deg: float, reach: float, lines: Array) -> Dictionary:
	var basis := xf.basis
	var dir := (-basis.z).rotated(basis.x.normalized(), deg_to_rad(pitch_deg))
	dir = dir.rotated(basis.y.normalized(), deg_to_rad(yaw_deg)).normalized()
	var to := xf.origin + dir * reach
	var hit := _ray(xf.origin, to)
	if debug_draw:
		lines.append([xf.origin, hit["position"] if not hit.is_empty() else to, not hit.is_empty()])
	return hit


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, hit_mask, _exclude)
	return body.get_world_3d().direct_space_state.intersect_ray(query)


# Where a slam lands: what the center ray touches, else the ground at the end of the reach
func _slam_center(xf: Transform3D, reach: float) -> Dictionary:
	var forward := -xf.basis.z
	var hit := _ray(xf.origin, xf.origin + forward * reach)
	if not hit.is_empty():
		return {"point": hit["position"], "primary": _damageable_of(hit["collider"])}
	var tip := xf.origin + forward * reach
	var ground := _ray(tip, tip + Vector3.DOWN * 3.0)
	return {"point": ground["position"] if not ground.is_empty() else tip, "primary": null}


# The node to call take_damage() on: a MeleeCombat registered as meta "damageable" on the body,
# or the body itself if it has take_damage(). null = scenery.
func _damageable_of(collider: Object) -> Node:
	if collider == null:
		return null
	if collider.has_meta("damageable"):
		var d: Variant = collider.get_meta("damageable")
		if is_instance_valid(d) and d != self and d.has_method("take_damage"):
			return d
	elif collider.has_method("take_damage"):
		return collider as Node
	return null


func _aim_transform() -> Transform3D:
	return aim_origin.global_transform


# ---------------------------------------------------------------- helpers

func _fail(reason: StringName, quiet: bool) -> bool:
	if not quiet:
		attack_failed.emit(reason)
	return false


# Taking hits in armor trains that armor skill
func _train_armor(final: float) -> void:
	if skills == null or equipment == null:
		return
	var trained := {}
	for entry in equipment.slots.values():
		var item: ItemData = entry
		var skill := item.governing_skill
		if item.item_type != ItemData.ItemType.ARMOR or (skill != "heavy_armor" and skill != "light_armor") or trained.has(skill):
			continue
		trained[skill] = true
		skills.add_xp(StringName(skill), final * ARMOR_XP_PER_DAMAGE)


func _draw_debug(lines: Array) -> void:
	var host := get_tree().current_scene
	if host == null or lines.is_empty():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		var color := Color.RED if l[2] else Color.YELLOW
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(l[0])
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(l[1])
	mesh.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.mesh = mesh
	mi.material_override = mat
	host.add_child(mi)
	get_tree().create_timer(0.4).timeout.connect(mi.queue_free)
