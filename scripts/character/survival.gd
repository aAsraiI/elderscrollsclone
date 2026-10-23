class_name Survival
extends Node
## Survival mode (World Creation option): hunger, fatigue and cold. Off = this node does nothing.
## Lives under the Player (player.gd adds it).
##
##   hunger   rises 4 an hour; eating lowers it (bigger meals more). Hungry and starving weaken you;
##            at 100 you slowly lose health. Vampires don't hunger for food (they need blood).
##   fatigue  rises 3 an hour awake; sleeping in a bed (T near a bed, or E on it) clears it.
##            Tired and exhausted cut your magicka and stamina.
##   cold     drifts toward how cold it is where you stand: the season, the land's climate, night,
##            rain and snow, minus your clothes and armor. Indoors you warm up. Freezing hurts.
## Each need has 4 stages; the HUD shows the bad ones. Sleeping in a bed also gives Well Rested
## (+10% skill XP for 8 hours) whether or not survival is on.

const HUNGER_PER_HOUR := 4.0
const FATIGUE_PER_HOUR := 3.0
const COLD_RATE := 12.0  # points an hour toward the target
const STAGE_NAMES := {
	"hunger": ["", "Peckish", "Hungry", "Starving"],
	"fatigue": ["", "Tired", "Weary", "Exhausted"],
	"cold": ["", "Chilly", "Cold", "Freezing"],
}
const PENALTIES := {
	"hunger": [{}, {}, {"stamina_regen_mult": -0.2, "max_stamina": -10.0}, {"stamina_regen_mult": -0.4, "max_stamina": -25.0, "damage_pct": -0.15}],
	"fatigue": [{}, {"magicka_regen_pct": -0.2}, {"magicka_regen_pct": -0.4, "max_magicka": -15.0}, {"magicka_regen_pct": -0.6, "max_magicka": -30.0, "max_stamina": -20.0}],
	"cold": [{}, {"move_speed_mult": -0.03}, {"move_speed_mult": -0.08, "stamina_regen_mult": -0.25}, {"move_speed_mult": -0.15, "stamina_regen_mult": -0.5, "damage_pct": -0.1}],
}

var hunger := 10.0
var fatigue := 10.0
var cold := 0.0
var _last_hours := -1.0
var _stages := {"hunger": 0, "fatigue": 0, "cold": 0}
var _hurt_timer := 0.0
var _stats: Stats


func _ready() -> void:
	_stats = get_parent().get_node_or_null("Stats") as Stats


func enabled() -> bool:
	return GameRules.survival()


func _process(delta: float) -> void:
	if not enabled() or _stats == null or _stats.is_dead:
		return
	var aff := get_parent().get_node_or_null("Afflictions") as Afflictions
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock == null:
		return
	var t := float(clock.day) * 24.0 + clock.hour
	if _last_hours < 0.0:
		_last_hours = t
	var hours := clampf(t - _last_hours, 0.0, 48.0)
	_last_hours = t
	if hours > 0.0:
		if aff == null or not aff.vampire:
			hunger = minf(hunger + HUNGER_PER_HOUR * hours, 100.0)
		fatigue = minf(fatigue + FATIGUE_PER_HOUR * hours, 100.0)
		var target := cold_target()
		cold = move_toward(cold, target, COLD_RATE * hours * (2.0 if target < cold else 1.0))
	_update_stages()
	_hurt_timer -= delta
	if _hurt_timer <= 0.0:
		_hurt_timer = 5.0
		if hunger >= 100.0:
			_stats.modify_vital("health", -2.0)
		if cold >= 90.0:
			_stats.modify_vital("health", -3.0)


## How cold it is here, 0..100 (where your cold drifts to)
func cold_target() -> float:
	var player := get_parent() as Node3D
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_in_building():
		return 0.0
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var climate := "temperate"
	if world != null and world.map != null and not (dm != null and dm.is_inside()):
		var b := world.get_biome_at(player.global_position.x, player.global_position.z)
		if b != null:
			climate = b.get_climate()
	var c: float = {"cold": 55.0, "temperate": 15.0, "wet": 20.0, "arid": 0.0}.get(climate, 15.0)
	if clock != null:
		c += [35.0, 10.0, -10.0, 10.0][clock.get_season()] * (0.3 if climate == "arid" else 1.0)
		if clock.is_night():
			c += 18.0 if climate != "arid" else 25.0
	var w := Weather.get_instance(get_tree())
	if w != null and w.enabled and not (dm != null and dm.is_inside()):
		match w.current:
			Weather.Kind.RAIN, Weather.Kind.STORM:
				c += 12.0
			Weather.Kind.SNOW:
				c += 15.0
			Weather.Kind.BLIZZARD:
				c += 35.0
	if dm != null and dm.is_inside():
		c = minf(c, 30.0)  # caves and crypts are cool but out of the wind
	# Clothes and armor keep you warm; so does resistance to frost
	var eq := get_parent().get_node_or_null("Equipment") as Equipment
	if eq != null:
		for slot in eq.slots:
			var it: ItemData = eq.slots[slot]
			if it != null and it.item_type == ItemData.ItemType.ARMOR:
				c -= 6.0
	c *= 1.0 - clampf(_stats.get_stat("resist_frost"), 0.0, 1.0)
	return clampf(c, 0.0, 100.0)


func _stage(v: float) -> int:
	return 0 if v < 25.0 else (1 if v < 50.0 else (2 if v < 75.0 else 3))


func _update_stages() -> void:
	var values := {"hunger": hunger, "fatigue": fatigue, "cold": cold}
	for k in values:
		var s := _stage(values[k])
		if s != _stages[k]:
			if s > _stages[k] and s >= 2:
				Locks.toast(get_tree(), "You are %s" % String(STAGE_NAMES[k][s]).to_lower(), true)
			_stages[k] = s
			var mods: Dictionary = PENALTIES[k][s]
			if mods.is_empty():
				_stats.remove_modifiers("need_" + k)
			else:
				_stats.add_modifiers("need_" + k, mods)


## Called when you eat or drink something
func on_eat(item: ItemData) -> void:
	if not enabled() or item == null:
		return
	var food := 6.0 + float(item.value) * 1.2 + item.heal_amount * 0.2
	if not item.magic_effects.is_empty() and item.effect_group == "food":
		food += 15.0
	if item.effect_group == "potion" and item.magic_effects.is_empty():
		food = 2.0
	hunger = maxf(hunger - minf(food, 60.0), 0.0)
	if item.id == &"ale" or item.id == &"wine" or item.id == &"spiced_wine":
		cold = maxf(cold - 10.0, 0.0)
	_update_stages()


## Sleeping in a bed for this many hours
func on_sleep(hours: float) -> void:
	fatigue = maxf(fatigue - hours * 14.0, 0.0)
	cold = maxf(cold - hours * 10.0, 0.0)
	_last_hours = -1.0
	_update_stages()


## Lines for the HUD (only the needs that matter)
func status_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if not enabled():
		return out
	for k in ["hunger", "fatigue", "cold"]:
		var s: int = _stages[k]
		if s >= 1:
			out.append("%s%s" % ["✖ " if s >= 2 else "", STAGE_NAMES[k][s]])
	return out


func to_dict() -> Dictionary:
	return {"hunger": hunger, "fatigue": fatigue, "cold": cold}


func from_dict(d: Dictionary) -> void:
	hunger = float(d.get("hunger", 10.0))
	fatigue = float(d.get("fatigue", 10.0))
	cold = float(d.get("cold", 0.0))
	_last_hours = -1.0
	for k in _stages:
		_stages[k] = -1
	_update_stages()
