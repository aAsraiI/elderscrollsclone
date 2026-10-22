class_name Stats
extends Node
## Base stats + named modifier sources (equipment, skills, buffs, etc.)
##
## Modifier keys (used by add_modifiers):
##   "armor": 10         flat bonus
##   "damage_pct": 0.2   +20% on that stat (key = stat name + "_pct")
## Total = (base + flat + attribute effects) * (1 + sum of all pct bonuses)

signal stat_changed(stat: String)
signal vital_changed(vital: String, current: float, maximum: float)
## Fires once when health reaches 0. Stays dead until revive() is called.
signal died

const DEFAULT_BASE_STATS := {
	# Vitals and combat
	"max_health": 100.0,
	"max_magicka": 50.0,
	"max_stamina": 100.0,
	"carry_capacity": 200.0,
	"armor": 0.0,
	"damage": 5.0,
	## Health points per second restored passively. Food and potions add to it (see StatusEffects).
	"health_regen": 0.0,
	## Multiplier on stamina regen. Food adds to it (0.5 = +50%).
	"stamina_regen_mult": 1.0,
	## Meters added to every melee weapon's reach (gloves, buffs, ...)
	"reach_bonus": 0.0,
	# Attributes (raised by skill levels, see SkillDatabase)
	"strength": 10.0,
	"agility": 10.0,
	"endurance": 10.0,
	"wisdom": 10.0,
	"stealth": 10.0,
	"charisma": 10.0,
	# Passive stats granted by skill milestones. Systems read these when they exist:
	# movement (live now), blocking (live now), sneak attacks, vendors, locks/traps, crafting.
	"move_speed_mult": 1.0,
	"block_strength": 0.0,
	"sneak_attack_bonus": 0.0,
	"buy_price_mult": 1.0,
	"sell_price_mult": 1.0,
	"security_bonus": 0.0,
	"smithing_potency": 0.0,
	"alchemy_potency": 0.0,
	"enchanting_potency": 0.0,
	"tinkering_potency": 0.0,
}

## Every attribute point ABOVE its base value adds this much to another stat.
## Endurance, wisdom, stealth and charisma are stored but have no effects yet
## (stamina regen, magicka regen, detection and dialogue don't exist yet).
const ATTRIBUTE_EFFECTS := {
	"strength": {"carry_capacity": 3.0},
	"agility": {"move_speed_mult": 0.005},
}

@export var base_stats: Dictionary = DEFAULT_BASE_STATS.duplicate()
## Stamina points per second once you have stopped spending it for a moment
@export var stamina_regen := 10.0
@export var stamina_regen_delay := 1.5

var health: float
var magicka: float
var stamina: float
var is_dead := false

# source_id -> { stat_name: amount }
var _modifiers: Dictionary = {}
var _stamina_idle := 0.0


func _ready() -> void:
	# If the Inspector copy of base_stats is older than the script, fill in any new stats
	for key in DEFAULT_BASE_STATS:
		if not base_stats.has(key):
			base_stats[key] = DEFAULT_BASE_STATS[key]
	health = get_stat("max_health")
	magicka = get_stat("max_magicka")
	stamina = get_stat("max_stamina")


func _process(delta: float) -> void:
	if is_dead:
		return
	var heal := get_stat("health_regen")
	if heal > 0.0 and health < get_stat("max_health"):
		modify_vital("health", heal * delta)
	if stamina_regen <= 0.0:
		return
	_stamina_idle += delta
	if _stamina_idle >= stamina_regen_delay and stamina < get_stat("max_stamina"):
		modify_vital("stamina", stamina_regen * maxf(get_stat("stamina_regen_mult"), 0.0) * delta)


func get_stat(stat: String) -> float:
	return get_stat_plus(stat, 0.0)


## Same as get_stat, but with extra flat points added before the percentage bonuses.
## Combat uses it to add the swinging weapon's own damage: get_stat_plus("damage", weapon.weapon_damage)
func get_stat_plus(stat: String, extra_flat: float) -> float:
	var total := _flat_total(stat) + extra_flat
	# Attribute points above base feed other stats (strength -> carry capacity, ...)
	for attr in ATTRIBUTE_EFFECTS:
		var per_point: float = ATTRIBUTE_EFFECTS[attr].get(stat, 0.0)
		if per_point != 0.0:
			total += (_flat_total(attr) - float(base_stats.get(attr, 0.0))) * per_point
	var pct := 0.0
	var pct_key := stat + "_pct"
	for source in _modifiers:
		pct += float(_modifiers[source].get(pct_key, 0.0))
	return total * (1.0 + pct)


## Sum of the flat bonuses to `stat` from sources whose id starts with `prefix`,
## e.g. get_flat_from("equip_", "armor") = armor that comes from gear.
func get_flat_from(prefix: String, stat: String) -> float:
	var total := 0.0
	for source in _modifiers:
		if String(source).begins_with(prefix):
			total += float(_modifiers[source].get(stat, 0.0))
	return total


func add_modifiers(source: String, mods: Dictionary) -> void:
	_modifiers[source] = mods
	_emit_changed(mods)
	_clamp_vitals()


func remove_modifiers(source: String) -> void:
	if not _modifiers.has(source):
		return
	var mods: Dictionary = _modifiers[source]
	_modifiers.erase(source)
	_emit_changed(mods)
	_clamp_vitals()


## vital is "health", "magicka" or "stamina"; amount can be negative
func modify_vital(vital: String, amount: float) -> void:
	match vital:
		"health":
			if is_dead and amount > 0.0:
				return  # the dead stay dead until revive()
			health = clampf(health + amount, 0.0, get_stat("max_health"))
			vital_changed.emit(vital, health, get_stat("max_health"))
			if health <= 0.0 and not is_dead:
				is_dead = true
				died.emit()
		"magicka":
			magicka = clampf(magicka + amount, 0.0, get_stat("max_magicka"))
			vital_changed.emit(vital, magicka, get_stat("max_magicka"))
		"stamina":
			if amount < 0.0:
				_stamina_idle = 0.0
			stamina = clampf(stamina + amount, 0.0, get_stat("max_stamina"))
			vital_changed.emit(vital, stamina, get_stat("max_stamina"))


## Brings a dead character back with full vitals
func revive() -> void:
	is_dead = false
	health = get_stat("max_health")
	magicka = get_stat("max_magicka")
	stamina = get_stat("max_stamina")
	_clamp_vitals()


## Only the current vitals are saved. Maximums come from base stats, gear and skills, which are
## restored by their own systems; load those first so the maximums are right.
func to_dict() -> Dictionary:
	return {"health": health, "magicka": magicka, "stamina": stamina}


func from_dict(data: Dictionary) -> void:
	is_dead = false
	health = clampf(float(data.get("health", get_stat("max_health"))), 1.0, get_stat("max_health"))
	magicka = clampf(float(data.get("magicka", get_stat("max_magicka"))), 0.0, get_stat("max_magicka"))
	stamina = clampf(float(data.get("stamina", get_stat("max_stamina"))), 0.0, get_stat("max_stamina"))
	_stamina_idle = 0.0
	vital_changed.emit("health", health, get_stat("max_health"))
	vital_changed.emit("magicka", magicka, get_stat("max_magicka"))
	vital_changed.emit("stamina", stamina, get_stat("max_stamina"))


func _flat_total(stat: String) -> float:
	var total: float = base_stats.get(stat, 0.0)
	for source in _modifiers:
		total += float(_modifiers[source].get(stat, 0.0))
	return total


func _emit_changed(mods: Dictionary) -> void:
	for key in mods:
		var stat := String(key).trim_suffix("_pct")
		stat_changed.emit(stat)
		if ATTRIBUTE_EFFECTS.has(stat):
			for affected in ATTRIBUTE_EFFECTS[stat]:
				stat_changed.emit(affected)


func _clamp_vitals() -> void:
	modify_vital("health", 0.0)
	modify_vital("magicka", 0.0)
	modify_vital("stamina", 0.0)
