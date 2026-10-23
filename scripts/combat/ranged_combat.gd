class_name RangedCombat
extends Node
## Bows, for the player and for enemy archers. Hold to draw, let go to shoot. The longer the draw
## (up to the bow's draw_time) the faster and harder the arrow flies. The player uses the best
## arrows in the bag (one is used up per shot; sometimes it can be picked up again where it hit);
## enemies never run out. Damage = (base damage + bow + arrow) x skill bonuses x draw.
## Hidden shots get the sneak attack bonus. Trains Archery.

signal shot(arrow: Arrow)

const MIN_DRAW := 0.25
const XP_PER_DAMAGE := 0.2

var host: Node3D
var stats: Stats
var skills: Skills
var equipment: Equipment
var inventory: Inventory
var aim_origin: Node3D
## Enemies: who to shoot at (null = straight ahead)
var aim_target: Node3D
## Enemies: the arrow they pretend to use
var npc_arrow: ItemData

var _drawing := false
var _draw := 0.0
var _cooldown := 0.0


func _ready() -> void:
	host = get_parent() as Node3D
	stats = host.get_node_or_null("Stats") as Stats
	skills = host.get_node_or_null("Skills") as Skills
	equipment = host.get_node_or_null("Equipment") as Equipment
	inventory = host.get_node_or_null("Inventory") as Inventory
	if aim_origin == null:
		aim_origin = host.get_node_or_null("Head/Camera3D") as Node3D
	if aim_origin == null:
		aim_origin = host.get_node_or_null("Head") as Node3D


func get_bow() -> ItemData:
	var w := equipment.get_main_hand() if equipment != null else null
	return w if w != null and w.is_bow else null


func has_bow() -> bool:
	return get_bow() != null


## The best arrows in the bag (null = none)
func best_arrow() -> ItemData:
	if npc_arrow != null:
		return npc_arrow
	var best: ItemData = null
	if inventory != null:
		for s in inventory.stacks:
			var it: ItemData = s.item
			if it.is_arrow and (best == null or it.arrow_damage > best.arrow_damage):
				best = it
	return best


func begin_draw() -> bool:
	if not has_bow() or _cooldown > 0.0 or _drawing:
		return false
	var combat := host.get_node_or_null("MeleeCombat") as MeleeCombat
	if combat != null and combat.is_stunned():
		return false
	if best_arrow() == null:
		if host.is_in_group("player"):
			Locks.toast(host.get_tree(), "You have no arrows", true)
		return false
	_drawing = true
	_draw = 0.0
	return true


func cancel() -> void:
	_drawing = false
	_draw = 0.0


func is_drawing() -> bool:
	return _drawing


## 0..1 how far the string is drawn
func get_draw_ratio() -> float:
	var bow := get_bow()
	if not _drawing or bow == null:
		return 0.0
	return clampf(_draw / maxf(bow.draw_time, 0.1), 0.0, 1.0)


func release() -> void:
	if not _drawing:
		return
	var ratio := get_draw_ratio()
	_drawing = false
	if ratio < MIN_DRAW:
		return  # let go too early: the arrow is not loosed
	_shoot(ratio)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _drawing:
		_draw += delta
		if not has_bow():
			cancel()
		elif stats != null and _draw > 0.3:
			stats.modify_vital("stamina", -2.0 * delta)  # holding a full draw tires the arms


func _shoot(ratio: float) -> void:
	var bow := get_bow()
	var arrow_item := best_arrow()
	if bow == null or arrow_item == null:
		return
	if npc_arrow == null and inventory != null:
		inventory.remove_item(arrow_item, 1)
	var origin := aim_origin.global_position
	var dir := -aim_origin.global_transform.basis.z
	if aim_target != null and is_instance_valid(aim_target):
		var at := aim_target.global_position + Vector3.UP * (1.2 if aim_target.is_in_group("player") else 0.9)
		var dist := origin.distance_to(at)
		var speed := bow.arrow_speed * (0.55 + 0.45 * ratio)
		var t := dist / speed
		var tv := (aim_target as CharacterBody3D).velocity if aim_target is CharacterBody3D else Vector3.ZERO
		at += tv * t * 0.6 + Vector3.UP * 0.5 * Arrow.GRAVITY * t * t  # lead the target and aim over the drop
		dir = (at - origin).normalized()
		dir = dir.rotated(Vector3.UP, randf_range(-0.03, 0.03))
	var dmg := stats.get_stat_plus("damage", bow.weapon_damage + arrow_item.arrow_damage) * (0.35 + 0.65 * ratio) if stats != null else 10.0
	var a := Arrow.launch(self, arrow_item, origin + dir * 0.6, dir * bow.arrow_speed * (0.55 + 0.45 * ratio), dmg, bow)
	_cooldown = 0.25
	var stealth: Variant = host.get_meta("stealth", null)
	if stealth != null and is_instance_valid(stealth):
		stealth.make_noise(0.5)
	var m := ActiveMagic.of(host)
	if m != null and m.has_effect(&"invisibility"):
		m.remove_effect(&"invisibility")
	shot.emit(a)


## An arrow landed on someone (Arrow calls this)
func on_arrow_hit(arrow: Arrow, target: Node, point: Vector3) -> void:
	var info := DamageInfo.new(arrow.damage, host if is_instance_valid(host) else null, &"arrow")
	info.hit_position = point
	info.direction = arrow.velocity.normalized()
	info.weapon = arrow.bow
	info.poise_damage = 12.0 + arrow.damage * 0.4
	info.knockback = 1.5
	info.parryable = false
	var victim := (target.get("body") as Node3D) if "body" in target else target as Node3D
	var e := victim as Enemy
	if host != null and is_instance_valid(host) and host.is_in_group("player") and e != null:
		var stealth: Variant = host.get_meta("stealth", null)
		if stealth != null and is_instance_valid(stealth):
			var mult: float = stealth.sneak_attack_mult(e, arrow.bow)
			if mult > 1.0:
				info.amount *= mult
				info.sneak = true
				stealth.sneak_attack.emit(e, mult)
	var final: float = target.take_damage(info)
	if host != null and is_instance_valid(host):
		MagicHit.after_hit(host, victim, info)
		WeaponMagic.on_hit(host, victim, arrow.bow, info)
		if skills != null and final > 0.0:
			skills.add_xp(&"archery", final * XP_PER_DAMAGE)
		var fb := host.get_node_or_null("MeleeCombat") as MeleeCombat
		if fb != null:
			fb.hit_dealt.emit(target, info, final)
