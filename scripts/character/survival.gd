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
	"heat": ["", "Warm", "Hot", "Heatstroke"],  # 1.25
	"wet": ["", "Damp", "Wet", "Soaked"],  # 1.25
	"thirst": ["", "Dry", "Thirsty", "Parched"],  # 1.30
}
const PENALTIES := {
	"hunger": [{}, {}, {"stamina_regen_mult": -0.2, "max_stamina": -10.0}, {"stamina_regen_mult": -0.4, "max_stamina": -25.0, "damage_pct": -0.15}],
	"fatigue": [{}, {"magicka_regen_pct": -0.2}, {"magicka_regen_pct": -0.4, "max_magicka": -15.0, "skill_xp_pct": -0.15}, {"magicka_regen_pct": -0.6, "max_magicka": -30.0, "max_stamina": -20.0, "skill_xp_pct": -0.35}],  # 1.25: the exhausted learn slowly
	"cold": [{}, {"move_speed_mult": -0.03}, {"move_speed_mult": -0.08, "stamina_regen_mult": -0.25}, {"move_speed_mult": -0.15, "stamina_regen_mult": -0.5, "damage_pct": -0.1}],
	"heat": [{}, {}, {"stamina_regen_mult": -0.25, "max_stamina": -10.0}, {"stamina_regen_mult": -0.5, "max_stamina": -25.0, "move_speed_mult": -0.08}],
	"wet": [{}, {}, {"stamina_regen_mult": -0.1}, {"stamina_regen_mult": -0.2, "move_speed_mult": -0.04}],
	"thirst": [{}, {}, {"stamina_regen_mult": -0.25, "magicka_regen_pct": -0.15}, {"stamina_regen_mult": -0.5, "magicka_regen_pct": -0.3, "max_stamina": -20.0}],  # 1.30
}

var hunger := 10.0
var fatigue := 10.0
var cold := 0.0
var _last_hours := -1.0
var heat := 0.0  # 1.25
var wet := 0.0  # 1.25
var thirst := 10.0  # 1.30: rises 5 an hour (faster in the heat); water lowers it
const THIRST_PER_HOUR := 5.0
var _stages := {"hunger": 0, "fatigue": 0, "cold": 0, "heat": 0, "wet": 0, "thirst": 0}
var _hurt_timer := 0.0
var _stats: Stats


func _ready() -> void:
	_stats = get_parent().get_node_or_null("Stats") as Stats


func enabled() -> bool:
	return GameRules.survival()


func _process(delta: float) -> void:
	_tick_meals(delta)  # 1.25: meals wear off (survival mode or not)
	_tick_wounds(delta)  # 1.30
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
			hunger = minf(hunger + HUNGER_PER_HOUR * hours * _need_mult(), 100.0)
		fatigue = minf(fatigue + FATIGUE_PER_HOUR * hours * _need_mult(), 100.0)
		if aff == null or not aff.vampire:
			thirst = minf(thirst + THIRST_PER_HOUR * hours * _need_mult() * (1.0 + heat / 100.0), 100.0)
		var target := cold_target()
		cold = move_toward(cold, target, COLD_RATE * hours * (2.0 if target < cold else 1.0))
		var ht := heat_target()
		heat = move_toward(heat, ht, COLD_RATE * hours * (2.0 if ht < heat else 1.0))
		wet = move_toward(wet, wet_target(), (60.0 if near_fire() else 25.0) * hours)
	_update_stages()
	_hurt_timer -= delta
	if _hurt_timer <= 0.0:
		_hurt_timer = 5.0
		if hunger >= 100.0:
			_stats.modify_vital("health", -2.0)
		if cold >= 90.0:
			_stats.modify_vital("health", -3.0)
		if heat >= 90.0:
			_stats.modify_vital("health", -2.0)  # heatstroke
		var sky := Weather.get_instance(get_tree())
		if sky != null and sky.enabled and sky.current == Weather.Kind.ASHSTORM and not sky._inside():
			_stats.modify_vital("health", -1.0)  # 1.31: ash in the lungs
			thirst = minf(thirst + 1.0, 100.0)
		if thirst >= 100.0:
			_stats.modify_vital("health", -2.0)  # 1.30: parched


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
			if it != null:
				c -= warmth(it)  # 1.25: furs keep you far warmer than linen
	c += wet * 0.3  # wet clothes chill
	if near_fire():
		c -= 45.0
	c *= 1.0 - clampf(_stats.get_stat("resist_frost"), 0.0, 1.0)
	return clampf(c, 0.0, 100.0)


func _stage(v: float) -> int:
	return 0 if v < 25.0 else (1 if v < 50.0 else (2 if v < 75.0 else 3))


func _update_stages() -> void:
	var values := {"hunger": hunger, "fatigue": fatigue, "cold": cold, "heat": heat, "wet": wet, "thirst": thirst}
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
	eat_meal(item)  # 1.25
	if not enabled() or item == null:
		return
	var food := 6.0 + float(item.value) * 1.2 + item.heal_amount * 0.2
	if not item.magic_effects.is_empty() and item.effect_group == "food":
		food += 15.0
	if item.effect_group == "potion" and item.magic_effects.is_empty():
		food = 2.0
	hunger = maxf(hunger - minf(food, 60.0), 0.0)
	if item.use_verb == "Drink" or item.effect_group == "potion":
		thirst = maxf(thirst - 25.0, 0.0)  # 1.30: drinks quench thirst
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
	for k in ["hunger", "thirst", "fatigue", "cold", "heat", "wet"]:
		var s: int = _stages[k]
		if s >= 1:
			out.append("%s%s" % ["✖ " if s >= 2 else "", STAGE_NAMES[k][s]])
	if is_bleeding():
		out.append("✖ Bleeding (%d)" % wounds.size())  # 1.30
	return out


func to_dict() -> Dictionary:
	return {"hunger": hunger, "fatigue": fatigue, "cold": cold, "heat": heat, "wet": wet, "thirst": thirst, "meals": meals}


func from_dict(d: Dictionary) -> void:
	hunger = float(d.get("hunger", 10.0))
	fatigue = float(d.get("fatigue", 10.0))
	cold = float(d.get("cold", 0.0))
	heat = float(d.get("heat", 0.0))
	wet = float(d.get("wet", 0.0))
	thirst = float(d.get("thirst", 10.0))
	meals = d.get("meals", [])
	_apply_meals()
	_last_hours = -1.0
	for k in _stages:
		_stages[k] = -1
	_update_stages()


# Survival skill and perks slow hunger and tiredness (never below a fifth)
func _need_mult() -> float:
	return clampf(_stats.get_stat("hunger_mult"), 0.2, 2.0) if _stats != null else 1.0


# ---------------------------------------------------------------- 1.25: heat, wet, fire, warmth

const WARM_WORDS := ["fur", "pelt", "wool", "bear", "hide", "fleece", "winter", "frost"]
const COOL_WORDS := ["linen", "silk", "robe", "desert", "sun"]


## How warm a piece of clothing or armour keeps you (cold points it takes off)
static func warmth(it: ItemData) -> float:
	if it == null or it.item_type != ItemData.ItemType.ARMOR:
		return 0.0
	var name := (String(it.id) + " " + it.display_name).to_lower()
	for w in WARM_WORDS:
		if name.contains(w):
			return 13.0
	for w in COOL_WORDS:
		if name.contains(w):
			return 2.0
	return 8.0 if it.governing_skill == "heavy_armor" else 5.0


## How hot it is here, 0..100: deserts and summer days, worse in heavy armour, cooled by water
func heat_target() -> float:
	var player := get_parent() as Node3D
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		return 0.0
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var climate := "temperate"
	if world != null and world.map != null:
		var b := world.get_biome_at(player.global_position.x, player.global_position.z)
		if b != null:
			climate = b.get_climate()
	if clock == null or clock.is_night():
		return 0.0
	var h: float = {"arid": 55.0, "temperate": 5.0, "wet": 15.0, "cold": 0.0}.get(climate, 5.0)
	h += [-20.0, 0.0, 20.0, 0.0][clock.get_season()]
	var midday := 1.0 - absf(clock.hour - 13.0) / 7.0
	h *= clampf(midday, 0.0, 1.0)
	var eq := get_parent().get_node_or_null("Equipment") as Equipment
	if eq != null and h > 0.0:
		for slot in eq.slots:
			var it: ItemData = eq.slots[slot]
			if it != null and it.item_type == ItemData.ItemType.ARMOR:
				h += 6.0 if it.governing_skill == "heavy_armor" else 2.0
				var name := (String(it.id) + " " + it.display_name).to_lower()
				for w in WARM_WORDS:
					if name.contains(w):
						h += 5.0
	h -= wet * 0.3  # wet clothes cool you
	h *= 1.0 - clampf(_stats.get_stat("resist_fire"), 0.0, 1.0)
	return clampf(h, 0.0, 100.0)


## How wet you are getting: soaked swimming, wet in the rain, drying otherwise
func wet_target() -> float:
	var player := get_parent()
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	var sw := player.get_node_or_null("Swimming")
	if sw != null and bool(sw.get("_swimming")):
		wet = 100.0
		return 100.0
	if dm != null and dm.is_inside():
		return 0.0
	var w := Weather.get_instance(get_tree())
	if w != null and w.enabled and w.current in [Weather.Kind.RAIN, Weather.Kind.STORM]:
		return 80.0 if w.current == Weather.Kind.RAIN else 100.0
	return 0.0


## A fire, hearth or forge within a few steps (Group "heat_sources")
func near_fire() -> bool:
	var player := get_parent() as Node3D
	for n in get_tree().get_nodes_in_group("heat_sources"):
		if n is Node3D and (n as Node3D).global_position.distance_to(player.global_position) < 5.0:
			return true
	return false


# ---------------------------------------------------------------- 1.25: meals as buffs (Valheim)

const MAX_MEALS := 3
var meals: Array = []  # {"id", "name", "until" (game hours), "health", "stamina"}
var _meal_t := 0.0


## Eating a meal gives a buff to health and stamina for a while (bigger and longer for better food,
## better cooks and cooked dishes); three at once at most, the oldest goes first. Works with or
## without survival mode.
func eat_meal(item: ItemData) -> void:
	if item == null or item.effect_group == "potion" or item.item_type != ItemData.ItemType.CONSUMABLE:
		return
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var now := float(clock.day) * 24.0 + clock.hour if clock != null else 0.0
	var cook := 1.0 + clampf(_stats.get_stat("cooking_potency") / 100.0, 0.0, 1.5)
	var cooked := not item.magic_effects.is_empty() or item.heal_amount > 0.0
	var size := (4.0 + float(item.value) * 0.6) * cook * (1.4 if cooked else 1.0)
	var hours := clampf((1.0 + float(item.value) / 12.0) * cook * (1.3 if cooked else 1.0), 1.0, 8.0)
	for m in meals.duplicate():
		if String(m["id"]) == String(item.id):
			meals.erase(m)  # the same dish again: just refreshed
	while meals.size() >= MAX_MEALS:
		meals.pop_front()
	meals.append({"id": String(item.id), "name": item.display_name, "until": now + hours, "health": roundf(size), "stamina": roundf(size * 0.8)})
	_apply_meals()


func _apply_meals() -> void:
	if _stats == null:
		return
	for i in MAX_MEALS:
		_stats.remove_modifiers("meal_%d" % i)
	for i in meals.size():
		var m: Dictionary = meals[i]
		_stats.add_modifiers("meal_%d" % i, {"max_health": float(m["health"]), "max_stamina": float(m["stamina"])})


func _tick_meals(delta: float) -> void:
	_meal_t -= delta
	if _meal_t > 0.0 or meals.is_empty():
		return
	_meal_t = 2.0
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock == null:
		return
	var now := float(clock.day) * 24.0 + clock.hour
	var before := meals.size()
	meals = meals.filter(func(m): return float(m["until"]) > now)
	if meals.size() != before:
		_apply_meals()


## The meals working now, for the status page: ["Venison Stew: +18 health, +14 stamina (3 h)"]
func meal_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var now := float(clock.day) * 24.0 + clock.hour if clock != null else 0.0
	for m in meals:
		out.append("%s: +%d health, +%d stamina (%d h)" % [m["name"], int(m["health"]), int(m["stamina"]), maxi(ceili(float(m["until"]) - now), 1)])
	return out


# ---------------------------------------------------------------- 1.25: comfort

## How comfortable a bed is (0-4): a house or inn, a fire close by, furnishings around it
func comfort(at: Vector3) -> int:
	var c := 0
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_in_building():
		c += 1
	for n in get_tree().get_nodes_in_group("heat_sources"):
		if n is Node3D and (n as Node3D).global_position.distance_to(at) < 7.0:
			c += 1
			break
	var things := 0
	for n in get_tree().get_nodes_in_group("interior_props"):
		if n is Node3D and (n as Node3D).global_position.distance_to(at) < 5.0:
			things += 1
	c += mini(things / 3, 2)
	return clampi(c, 0, 4)


## Minutes of Well Rested a sleep gives in this much comfort
static func rest_minutes(comfort_level: int) -> float:
	return 240.0 + 120.0 * float(comfort_level)


## 1.30: a long drink of water (a waterskin, or straight from a river)
func drink_water(amount: float = 60.0) -> void:
	thirst = maxf(thirst - amount, 0.0)
	_update_stages()


# ---------------------------------------------------------------- 1.30: bleeding

## A heavy blow (or one that takes a sixth of your health) opens a wound in Survival mode: you
## bleed BLEED_PER_SEC for BLEED_SECONDS, up to three wounds at once, until a Bandage closes them.
const BLEED_PER_SEC := 0.8
const BLEED_SECONDS := 25.0
const BLEED_MAX := 3
var wounds: Array = []  # seconds left on each open wound


func maybe_bleed(info: DamageInfo, taken: float) -> void:
	if not enabled() or _stats == null or taken <= 0.0 or info.kind == &"magic":
		return
	if not (info.heavy or taken >= _stats.get_stat("max_health") / 6.0):
		return
	if wounds.size() >= BLEED_MAX:
		wounds[0] = BLEED_SECONDS
		return
	wounds.append(BLEED_SECONDS)
	Locks.toast(get_tree(), "You are bleeding! (a Bandage stops it)", true)


func is_bleeding() -> bool:
	return not wounds.is_empty()


func _tick_wounds(delta: float) -> void:
	if wounds.is_empty() or _stats == null or _stats.is_dead:
		return
	_stats.modify_vital("health", -BLEED_PER_SEC * wounds.size() * delta)
	for i in range(wounds.size() - 1, -1, -1):
		wounds[i] = float(wounds[i]) - delta
		if float(wounds[i]) <= 0.0:
			wounds.remove_at(i)


## A Bandage: closes every wound and heals a little (more with Medicine). Trains Medicine.
func bandage(item: ItemData) -> String:
	var sk := get_parent().get_node_or_null("Skills") as Skills
	var med := float(sk.get_level(&"medicine")) if sk != null else 15.0
	var was := wounds.size()
	wounds.clear()
	_stats.modify_vital("health", 8.0 + med * 0.5)
	(get_parent().get_node("Inventory") as Inventory).remove_item(item, 1)
	if sk != null:
		sk.add_xp(&"medicine", 4.0 + was * 2.0)
	Achievements.note("bandage")
	return "You bind your wounds." if was > 0 else "You bandage yourself up."
