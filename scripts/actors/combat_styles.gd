class_name CombatStyles
extends RefCounted
## Alpha 1.27.5: some foes fight in a way that answers how you fight. When a hostile person comes
## into the world, about one in four takes up a style against your strongest kind of skill:
##   you shoot  (Archery)          Shieldbearer: a foe with a shield turns arrows that come from
##                                 the front (half damage); one without runs at you (Charger)
##   you cast   (the magic schools) Warded: 40% resistance to magic
##   you sneak  (Sneak, Security)   Tracker: notices you nearly twice as fast
##   you fight  (weapons, armour)   Duelist: sharper (blocks, parries and dodges more), sturdier guard
## The style shows by the name on the health bar ("Bandit (Warded)"), kept in Enemy meta
## "combat_style". Creatures, guards, townsfolk, bosses and named people keep to their ways.

const CHANCE := 0.25
const ARROW_GUARD := 0.5
const WARD := 0.4
const KEEN := 1.8

const NAMES := {"shieldbearer": "Shieldbearer", "charger": "Charger", "warded": "Warded", "tracker": "Tracker", "duelist": "Duelist"}


## Which kind of fighter the player is: "archer", "mage", "sneak" or "fighter"
static func player_kind(tree: SceneTree) -> String:
	var p := tree.get_first_node_in_group("player") if tree != null else null
	var sk := p.get_node_or_null("Skills") as Skills if p != null else null
	if sk == null:
		return "fighter"
	var best := {"archer": 0, "mage": 0, "sneak": 0, "fighter": 0}
	best["archer"] = sk.get_level(&"archery")
	for s in [&"destruction", &"restoration", &"alteration", &"conjuration", &"illusion", &"mysticism"]:
		best["mage"] = maxi(int(best["mage"]), sk.get_level(s))
	best["sneak"] = maxi(sk.get_level(&"sneak"), sk.get_level(&"security"))
	for s in [&"one_handed", &"two_handed", &"block", &"heavy_armor", &"hand_to_hand"]:
		best["fighter"] = maxi(int(best["fighter"]), sk.get_level(s))
	var kind := "fighter"
	for k in best:
		if int(best[k]) > int(best[kind]):
			kind = k
	return kind


## Called when a hostile person is ready (Enemy._ready)
static func maybe_take(e: Enemy) -> void:
	if e == null or e.disposition != Enemy.Disposition.HOSTILE or e.body_kind != CreatureBody.Kind.HUMANOID \
			or e.has_meta("npc_id") or e.has_meta("combat_style") or e.has_meta("player_ally"):
		return
	var h := absi(((e.spawn_key if e.spawn_key != "" else str(e.get_instance_id())) + "|style").hash())
	if float(h % 1000) / 1000.0 >= CHANCE:
		return
	var style := ""
	match player_kind(e.get_tree()):
		"archer":
			style = "shieldbearer" if e.starting_off_hand != null and e.starting_off_hand.secondary_action == ItemData.SecondaryAction.BLOCK else "charger"
		"mage":
			style = "warded"
		"sneak":
			style = "tracker"
		_:
			style = "duelist"
	take(e, style)


static func take(e: Enemy, style: String) -> void:
	e.set_meta("combat_style", style)
	match style:
		"shieldbearer":
			e.set_meta("arrow_guard", ARROW_GUARD)
		"charger":
			e.move_speed *= 1.25
		"warded":
			if e.stats != null:
				e.stats.add_modifiers("style", {"resist_magic": WARD})
		"tracker":
			e.set_meta("keen", KEEN)
		"duelist":
			if e.stats != null:
				e.stats.add_modifiers("style", {"block_strength": 0.15, "poise_bonus": 0.2})
			e.cunning = minf(e.cunning + 0.25, 1.0)  # blocks, parries and dodges more


## RangedCombat: an arrow from in front of a shieldbearer is turned aside, half of it
static func arrow_mult(victim: Node, arrow_dir: Vector3) -> float:
	var e := victim as Enemy
	if e == null or not e.has_meta("arrow_guard"):
		return 1.0
	var facing := -e.global_transform.basis.z
	if facing.dot(arrow_dir) < -0.3:
		return float(e.get_meta("arrow_guard"))
	return 1.0
