class_name BossMechanics
extends Node
## Alpha 1.26: a dungeon's boss fights with a trick of its own (RoomFiller attaches it).
##   raiser    a necromancer, priest or wight lord raises the dead every so often; below a third of
##             its health its power fails and no more rise
##   regrows   a troll knits its wounds back together, unless fire has touched it in the last seconds
##   brood     a crawler queen or giant spider brings out its young
##   rage      anyone else, badly hurt, fights harder (once)
## Cheap: a look twice a second, only while it fights.

const RAISE_EVERY := 14.0
const RAISE_MAX := 4
const BROOD_EVERY := 15.0
const REGROW_PCT := 0.02  # of max health a second
const FIRE_STOPS := 6.0  # seconds a burn stops the regrowth

var boss: Enemy
var kind := "rage"
var _t := 0.0
var _clock := 0.0
var _next := 6.0
var _raised: Array = []
var _raged := false


static func attach(e: Enemy) -> BossMechanics:
	if e == null:
		return null
	var m := BossMechanics.new()
	m.name = "BossMechanics"
	m.boss = e
	m.kind = kind_for(e)
	e.add_child(m)
	return m


static func kind_for(e: Enemy) -> String:
	var id := String(e.enemy_id)
	if id in ["cave_troll", "forest_troll"]:
		return "regrows"
	if id in ["crawler_queen", "giant_spider"]:
		return "brood"
	if id in ["ashen_priest", "wight_lord", "barrow_wight", "crypt_warden", "vampire"] or e.style == Enemy.Style.MAGE:
		return "raiser"
	return "rage"


func _process(delta: float) -> void:
	_clock += delta
	_t -= delta
	if _t > 0.0 or boss == null or not is_instance_valid(boss) or boss.is_dead():
		return
	_t = 0.5
	if boss.get_fight_target() == null:
		return
	var hp := boss.stats.health / maxf(boss.stats.get_stat("max_health"), 1.0)
	match kind:
		"raiser":
			_raised = _raised.filter(func(x): return is_instance_valid(x) and not (x as Enemy).is_dead())
			if hp < 0.34:
				if not has_meta("failed"):
					set_meta("failed", true)
					boss._popup("Its power fails!", boss.global_position + Vector3.UP * 2.4, Color(0.7, 0.85, 1.0), 44)
				return
			if _clock >= _next and _raised.size() < RAISE_MAX:
				_next = _clock + RAISE_EVERY
				_raise("skeleton")
		"brood":
			if _clock >= _next and _raised.size() < RAISE_MAX:
				_next = _clock + BROOD_EVERY
				_raise("giant_rat" if not ResourceLoader.exists("res://data/enemies/deep_crawler.tres") else "deep_crawler", 0.55)
			_raised = _raised.filter(func(x): return is_instance_valid(x) and not (x as Enemy).is_dead())
		"regrows":
			var burned_at := float(boss.get_meta("burned_at", -999.0))
			if Time.get_ticks_msec() / 1000.0 - burned_at > FIRE_STOPS and hp < 1.0:
				boss.stats.modify_vital("health", boss.stats.get_stat("max_health") * REGROW_PCT * 0.5)
		"rage":
			if not _raged and hp < 0.3:
				_raged = true
				boss.stats.add_modifiers("boss_rage", {"damage_pct": 0.3, "move_speed_mult": 0.2})
				boss._popup("ENRAGED", boss.global_position + Vector3.UP * 2.4, Color(1.0, 0.3, 0.2), 48)


func _raise(kind_id: String, scale: float = 1.0) -> void:
	var data := load("res://data/enemies/%s.tres" % kind_id) as EnemyData
	if data == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var at := boss.global_position + Vector3(rng.randf_range(-3, 3), 0.3, rng.randf_range(-3, 3))
	var e := Population.spawn_enemy(data, maxi(boss.level - 4, 1) if "level" in boss else 5, boss.get_parent(), at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
	e.faction = CreatureFactions.of(boss)
	if scale != 1.0:
		e.body_scale *= scale
	var t := boss.get_fight_target()
	if t != null:
		if t is Enemy:
			e.fight(t)
		else:
			e.aggro(t)
	_raised.append(e)
	SpellFX.burst(boss, at, 1.2, Color(0.55, 0.85, 0.55))
