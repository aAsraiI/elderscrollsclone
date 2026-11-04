class_name BuildHooks
extends RefCounted
## The small pieces of game code that make the character build's stats do something (Alpha 1.22).
## Combat, movement, crafting, gathering and so on call these, so each rule lives in one place.
##
##   crit_chance / crit_mult       player hits (melee and arrows) can be critical
##   power_attack_pct              heavy attacks hit harder          (MeleeCombat._act_damage)
##   attack_cost_mult              stamina per swing                 (MeleeCombat)
##   block_cost_mult               stamina while blocking            (MeleeCombat.take_damage)
##   armor_pen                     part of the victim's armor ignored (MeleeCombat.take_damage)
##   damage_reduction              less damage from everything       (MeleeCombat.take_damage)
##   execute_bonus                 more damage to foes below 30% health
##   life_leech                    melee damage dealt heals you
##   poise_bonus                   your hits stagger sooner
##   bow_damage                    arrows hit harder                  (RangedCombat)
##   follower_damage / _health     followers and summons              (here, AllyBrain)
##   fall_resist                   less falling damage                (Player)
##   swim_speed_mult, breath_mult  (Swimming)    horse_speed_mult, horse_stamina_mult (Rider)
##   mounted_damage                (MeleeCombat._charge_mult)   sneak_speed_mult (Stealth)
##   magicka_cost_mult, cost_<school> (SpellCaster)   potion_mult (StatusEffects)
##   hunger_mult (Survival)   harvest/mining/gem/farming/crop (HarvestNode, Planter)
##   persuade_bonus (Persuasion)   blessing_mult (RestSpot prayer)

const EXECUTE_HEALTH := 0.3
const MAX_DAMAGE_REDUCTION := 0.75
const MAX_ARMOR_PEN := 0.9
const MAX_LEECH := 0.25
## Falls shorter than this (meters) never hurt; past it, FALL_DAMAGE per meter
const SAFE_FALL := 7.0
const FALL_DAMAGE := 9.0


static func stats_of(n: Node) -> Stats:
	if n == null or not is_instance_valid(n):
		return null
	if n is Enemy:
		return (n as Enemy).stats
	return n.get_node_or_null("Stats") as Stats


static func skills_of(n: Node) -> Skills:
	if n == null or not is_instance_valid(n):
		return null
	return n.get_node_or_null("Skills") as Skills


static func is_player(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player")


static func player_of(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group("player") if tree != null else null


## An ally of the player (a follower or a summon)
static func is_ally(n: Node) -> bool:
	return n != null and is_instance_valid(n) and not is_player(n) and (n.has_meta("player_ally") or n.has_meta("follower"))


# ---------------------------------------------------------------- dealing damage

## The attacker's outgoing multipliers for one hit on a victim. Sets info.crit (meta) when it crits.
## rng = null uses the global random numbers.
static func outgoing_mult(attacker: Node, victim: Node, info: DamageInfo, rng: RandomNumberGenerator = null) -> float:
	var m := 1.0
	if is_player(attacker):
		var st := stats_of(attacker)
		if st != null:
			var roll := rng.randf() if rng != null else randf()
			if roll < clampf(st.get_stat("crit_chance"), 0.0, 0.9):
				m *= maxf(st.get_stat("crit_mult"), 1.0)
				info.set_meta("crit", true)
			var exe := st.get_stat("execute_bonus")
			var vs := stats_of(victim)
			var vmax := _max_health_of(victim, vs)
			if exe > 0.0 and vmax > 0.0 and _health_of(victim, vs) / vmax < EXECUTE_HEALTH:
				m *= 1.0 + exe
			info.poise_damage *= 1.0 + maxf(st.get_stat("poise_bonus"), -0.9)
	elif is_ally(attacker):
		var ps := stats_of(player_of(attacker.get_tree()))
		if ps != null:
			m *= 1.0 + maxf(ps.get_stat("follower_damage"), -0.9)
	return m


static func _health_of(_n: Node, st: Stats) -> float:
	return st.health if st != null else 0.0


static func _max_health_of(_n: Node, st: Stats) -> float:
	return st.get_stat("max_health") if st != null else 0.0


## How much of the victim's armor the attacker ignores (0..MAX_ARMOR_PEN)
static func armor_pen(attacker: Node) -> float:
	if not is_player(attacker):
		return 0.0
	var st := stats_of(attacker)
	return clampf(st.get_stat("armor_pen"), 0.0, MAX_ARMOR_PEN) if st != null else 0.0


## Damage left after the victim's own damage reduction
static func reduce(stats: Stats, amount: float) -> float:
	if stats == null:
		return amount
	return amount * (1.0 - clampf(stats.get_stat("damage_reduction"), 0.0, MAX_DAMAGE_REDUCTION))


## After a hit landed: life leech, skill XP, kills
static func after_hit(attacker: Node, victim: Node, info: DamageInfo, final: float, weapon: ItemData) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if is_player(attacker):
		var st := stats_of(attacker)
		var sk := skills_of(attacker)
		if st != null and final > 0.0 and info.element == &"" and info.kind != &"arrow":
			var leech := clampf(st.get_stat("life_leech"), 0.0, MAX_LEECH)
			if leech > 0.0:
				st.modify_vital("health", final * leech)
		if sk != null and final > 0.0 and info.kind != &"arrow":
			if weapon == null:
				sk.add_xp(&"hand_to_hand", final * 0.08)
			elif sk.condition_met(SkillDatabase.get_skill(&"dual_wielding")):
				sk.add_xp(&"dual_wielding", final * 0.05)
		if info.killed and sk != null:
			on_kill(attacker, victim)
	elif is_ally(attacker) and final > 0.0:
		var p := player_of(attacker.get_tree())
		var sk := skills_of(p)
		if sk != null:
			sk.add_xp(&"leadership", final * 0.03 + (4.0 if info.killed else 0.0))


## The player killed something: Hunting for beasts, Devotion for the undead
static func on_kill(player: Node, victim: Node) -> void:
	var sk := skills_of(player)
	var e := victim as Enemy
	if sk == null or e == null:
		return
	var id := String(e.enemy_id)
	if e.body_kind == CreatureBody.Kind.BEAST or e.body_kind == CreatureBody.Kind.CRAWLER or id == "werewolf" or id.contains("wolf") or id.contains("bear"):
		sk.add_xp(&"hunting", 6.0 + float(e.level) * 0.3)
	if id.contains("skeleton") or id.contains("wight") or id.contains("draugr") or id.contains("ghost") or id == "vampire" or id.contains("lich") or id.contains("zombie"):
		sk.add_xp(&"devotion", 3.0 + float(e.level) * 0.1)


# ---------------------------------------------------------------- costs

## Stamina cost of a swing after attack_cost_mult (never below 20%)
static func attack_cost(stats: Stats, cost: float) -> float:
	if stats == null:
		return cost
	return cost * clampf(stats.get_stat("attack_cost_mult"), 0.2, 3.0)


static func block_cost(stats: Stats, cost: float) -> float:
	if stats == null:
		return cost
	return cost * clampf(stats.get_stat("block_cost_mult"), 0.2, 3.0)


## Spell cost multiplier for a school
static func spell_cost_mult(stats: Stats, school: StringName) -> float:
	if stats == null:
		return 1.0
	return clampf(stats.get_stat("magicka_cost_mult") + stats.get_stat("cost_" + String(school)), 0.25, 3.0)


# ---------------------------------------------------------------- allies

## A new follower or summon gets the player's follower_health
static func buff_ally(e: Enemy, leader: Node) -> void:
	var st := stats_of(leader)
	if e == null or st == null:
		return
	var bonus := st.get_stat("follower_health")
	if bonus <= 0.0 or e.has_meta("ally_buffed"):
		return
	e.set_meta("ally_buffed", true)
	e.max_health *= 1.0 + bonus
	if e.stats != null:
		e.stats.base_stats["max_health"] = float(e.stats.base_stats.get("max_health", e.max_health)) * (1.0 + bonus)
		e.stats.invalidate()
		e.stats.health = e.stats.get_stat("max_health")


# ---------------------------------------------------------------- gathering

## count, plus the extra a bonus gives: 0.35 = +0..1 (35% chance), 1.4 = +1..2
static func bonus_count(count: int, bonus: float) -> int:
	if bonus <= 0.0:
		return count
	var extra := float(count) * bonus
	var whole := floori(extra)
	return count + whole + (1 if randf() < extra - float(whole) else 0)


static func player_stat(tree: SceneTree, stat: String, fallback: float = 0.0) -> float:
	var st := stats_of(player_of(tree))
	return st.get_stat(stat) if st != null else fallback


static func train(tree: SceneTree, skill: StringName, amount: float) -> void:
	var sk := skills_of(player_of(tree))
	if sk != null:
		sk.add_xp(skill, amount)


# ---------------------------------------------------------------- falling

## Damage of a fall of this many meters with this resistance (0 = safe)
static func fall_damage(meters: float, resist: float) -> float:
	if meters <= SAFE_FALL:
		return 0.0
	return (meters - SAFE_FALL) * FALL_DAMAGE * (1.0 - clampf(resist, 0.0, 1.0))
