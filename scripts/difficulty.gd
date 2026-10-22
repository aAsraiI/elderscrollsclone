class_name Difficulty
extends RefCounted
## The Difficulty option (Settings > Gameplay). Scales the damage the player takes and deals.
## Adept is the normal game; Expert and Master make every enemy hit harder and every enemy tougher.

const NAMES: Array[String] = ["Novice", "Apprentice", "Adept", "Expert", "Master"]
## [damage the player takes, damage the player deals]
const SCALES := [[0.55, 1.4], [0.8, 1.15], [1.0, 1.0], [1.35, 0.85], [1.8, 0.7]]


static func level() -> int:
	return clampi(int(GameRules.get_rule("difficulty")), 0, 4)


## Multiplier for a hit from `attacker` on `victim`
static func damage_mult(attacker: Object, victim: Object) -> float:
	var s: Array = SCALES[level()]
	if victim != null and is_instance_valid(victim) and (victim as Node).is_in_group("player"):
		return s[0]
	if attacker != null and is_instance_valid(attacker) and ((attacker as Node).is_in_group("player") or (attacker as Node).has_meta("player_ally")):
		return s[1]
	return 1.0
