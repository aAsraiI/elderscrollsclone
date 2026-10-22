class_name DamageInfo
extends RefCounted
## Describes one hit. MeleeCombat builds it when you swing and hands it to the victim's
## MeleeCombat.take_damage(). The victim fills in the "result" fields so the attacker's side
## (hit markers, hitstop, health bars) knows what happened.

var amount: float = 0.0
## The attacker's body (Player or Enemy)
var source: Node = null
## "melee", "slam" or "bash"
var kind: StringName = &"melee"
var hit_position := Vector3.ZERO
## From the attacker toward the victim, world space, normalized
var direction := Vector3.ZERO
var weapon: ItemData = null
## Velocity pushed onto the victim (enemies use it, the player gets a small shove)
var knockback: float = 0.0
## true = block can't reduce this hit
var ignores_block := false
## How much this hit chips at the victim's poise. Poise at 0 = stagger.
var poise_damage: float = 0.0
## A charged heavy attack
var heavy := false
## Which swing of a combo this was (0 = the first one)
var combo_step := 0
## true = a well-timed block can parry it (slams and bashes can't be parried)
var parryable := true
## A sneak attack (the victim didn't know the attacker was there); amount is already multiplied
var sneak := false
## Magic: &"fire", &"frost", &"shock", &"poison" or &"magic" (resistances instead of armor). Empty = a weapon.
var element: StringName = &""
## One tick of damage over time (burning, poison): no stagger, no flinch
var dot := false

# ---- filled in by the victim's take_damage()

## &"hit", &"blocked" or &"parried"
var result: StringName = &"hit"
## Damage the victim's block took instead of their health
var absorbed := 0.0
## This hit broke the victim's poise
var staggered := false
## The victim was already staggered, so it took bonus damage
var punish := false
## This hit killed the victim
var killed := false


func _init(p_amount: float = 0.0, p_source: Node = null, p_kind: StringName = &"melee") -> void:
	amount = p_amount
	source = p_source
	kind = p_kind


## The attacker's MeleeCombat (or null). Used to stagger an attacker whose hit was parried.
func get_attacker_combat() -> Node:
	if source == null or not is_instance_valid(source) or not source.has_meta("damageable"):
		return null
	var d: Variant = source.get_meta("damageable")
	return d if is_instance_valid(d) else null
