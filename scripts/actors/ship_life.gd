class_name ShipLife
extends RefCounted
## Alpha 1.31.3: a ship of your own. Innkeepers in port towns sell a Ship's Deed ("a ship of my
## own"). Use it at the water's edge and your ship is launched (a big Boat: Boat.is_ship); use it
## again and she comes to you. W/S, A/D and Sprint sail her as with a boat, but much faster.
## The open sea has its dangers while you are aboard, away from any shore:
##   storms        the sky turns and the sea tears at her: the hull wears and she runs slower
##   sea monsters  something rises beside the ship; it strikes you and the hull until you kill it
##                 (arrows and spells best). It leaves treasure from the deep.
## At 0 hull she goes down, and you swim for it; the deed launches another from any shore.
## A Repair Hammer aboard patches the hull. Saved in WorldState "boat" with her hull.

const PRICE := 8000
const DEED := "res://data/misc/ships_deed.tres"
const SPEED := 1.7
const EVENT_GAP := 60.0
const STORM_WEAR := 0.25  # hull a second, in a storm
const MONSTER_BITE := 6.0
const SEA_CLEAR := 180.0  # how far from land counts as open sea

static var _next_event := 60.0
static var _monster: Enemy
static var _bite_t := 0.0


static func speed_mult(b: Boat) -> float:
	var m := SPEED
	var w := Weather.get_instance(b.get_tree())
	if w != null and w.current == Weather.Kind.STORM:
		m *= 0.7
	return m * clampf(0.5 + b.hull / 200.0, 0.5, 1.0)


static func on_open_sea(b: Boat) -> bool:
	var w := b.get_tree().get_first_node_in_group("world_manager") as WorldManager
	if w == null or w.map == null:
		return false
	var p := b.global_position
	if not w.map.is_sea(p.x, p.z):
		return false
	for a in 8:
		var q := p + Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * SEA_CLEAR
		if w.get_height_at(q.x, q.z) > w.map.get_water_level(q.x, q.z):
			return false
	return true


static func tick(b: Boat, delta: float) -> void:
	var w := Weather.get_instance(b.get_tree())
	if w != null and w.current == Weather.Kind.STORM:
		wear(b, STORM_WEAR * delta)
	_tick_monster(b, delta)
	_next_event -= delta
	if _next_event > 0.0:
		return
	_next_event = EVENT_GAP
	if not on_open_sea(b):
		return
	var r := randf()
	if r < 0.2 and w != null:
		w.set_weather(Weather.Kind.STORM, 2.0)
		Locks.toast(b.get_tree(), "The sky darkens: a storm is coming down on you!", true)
	elif r < 0.35 and (_monster == null or not is_instance_valid(_monster)):
		rise(b)


static func wear(b: Boat, amount: float) -> void:
	var was := b.hull
	b.hull = maxf(b.hull - amount, 0.0)
	if was > 25.0 and b.hull <= 25.0:
		Locks.toast(b.get_tree(), "She is taking on water! (a Repair Hammer patches the hull)", true)
	if b.hull <= 0.0:
		sink(b)


static func sink(b: Boat) -> void:
	var tree := b.get_tree()
	if b.is_boarded():
		b.leave()
	WorldState.erase_record("boat")
	Locks.toast(tree, "Your ship breaks up and goes down! You swim for it.", true)
	DialogueState.system_entry("Knowledge", "My ship went down at sea. The yard will build another on the same deed.", "")
	b.queue_free()


## Something from the deep, beside the ship. Returns it.
static func rise(b: Boat) -> Enemy:
	var tree := b.get_tree()
	var w := tree.get_first_node_in_group("world_manager") as WorldManager
	var player := tree.get_first_node_in_group("player") as Node3D
	var sk := player.get_node_or_null("Skills") as Skills if player != null else null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var data := load("res://data/enemies/bog_lurker.tres") as EnemyData
	if data == null or w == null:
		return null
	var e := Population.spawn_enemy(data, maxi((sk.get_player_level() if sk != null else 5) + 3, 8), w, b.global_position + Vector3(5, 0, 0), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	if e == null:
		return null
	e.display_name = "Sea Serpent"
	e.disposition = Enemy.Disposition.HOSTILE
	e.scale = Vector3(1.8, 1.8, 1.8)
	e.set_meta("sea_monster", true)
	_monster = e
	_bite_t = 3.0
	e.aggro.call_deferred(player)
	Locks.toast(tree, "Something huge rises beside the ship!", true)
	return e


# The monster keeps pace with the ship, at the surface; it bites the hull now and then
static func _tick_monster(b: Boat, delta: float) -> void:
	if _monster == null:
		return
	if not is_instance_valid(_monster):
		_monster = null
		return
	if _monster.is_dead():
		var player := b.get_tree().get_first_node_in_group("player")
		if player != null:
			Currency.add_gold(player.get_node("Inventory") as Inventory, 200 + _monster.level * 15)
			Locks.toast(b.get_tree(), "The serpent sinks. Something glitters in its wake: you haul up a handful of old gold.")
		Achievements.note("sea_monster")
		_monster.queue_free()
		_monster = null
		return
	var a := Time.get_ticks_msec() * 0.0006
	_monster.global_position = b.global_position + Vector3(cos(a), 0, sin(a)) * 4.5 + Vector3(0, -0.2, 0)
	_monster.velocity = Vector3.ZERO
	_bite_t -= delta
	if _bite_t <= 0.0:
		_bite_t = 5.0
		wear(b, MONSTER_BITE)


## The deed, at the water's edge: launches her, or brings her to you
static func launch(player: Node3D, _deed: ItemData) -> String:
	var tree := player.get_tree()
	var w := tree.get_first_node_in_group("world_manager") as WorldManager
	var f := Fishing.of(player)
	if w == null or f == null or f.water_ahead() == "":
		return "Stand at the water's edge, facing it, to launch her."
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	var at := player.global_position + fwd.normalized() * 10.0
	if w.get_height_at(at.x, at.z) > w.map.get_water_level(at.x, at.z) - 1.0:
		return "The water is too shallow here for a ship."
	at.y = w.settings.sea_level
	var scene := tree.current_scene
	for n in scene.get_children():
		if n is Boat and (n as Boat).is_ship:
			if (n as Boat).is_boarded():
				return "You are aboard."
			n.global_position = at
			(n as Boat)._remember()
			return "Your ship comes round to you."
	var b := Boat.make(scene, at, player.rotation.y, "", false, true)
	b._remember()
	Achievements.note("ship")
	return "Your ship slides into the water. Press E on her to board."


static func patch(player: Node, hammer: ItemData) -> String:
	var b := player.get_meta("boat") as Boat
	var sk := player.get_node_or_null("Skills") as Skills
	b.hull = minf(b.hull + 25.0 + (float(sk.get_level(&"smithing")) * 0.25 if sk != null else 0.0), 100.0)
	(player.get_node("Inventory") as Inventory).remove_item(hammer, 1)
	return "You patch the hull (%d%%)." % roundi(b.hull)


# ---------------------------------------------------------------- buying her

static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s != null and not s.asleep and s.role == NpcData.Role.INNKEEPER and s.town != null and bool(s.town.extra.get("port", false)):
		out.append("a ship of my own")
	return out


static func respond(s: DialogueEngine.Speaker, topic: String, player: Node) -> Dictionary:
	if topic != "a ship of my own" or not topics_for(s).has(topic):
		return {}
	var inv := player.get_node("Inventory") as Inventory
	var deed := load(DEED) as ItemData
	if inv.has_item(deed):
		return Roleplay._say("You have your deed already. She's yours to launch from any shore.")
	if Currency.get_gold(inv) < PRICE:
		return Roleplay._say("A ship? The yard here will build you a good one: %d gold. Sail her between the islands yourself, if you dare." % PRICE)
	Currency.spend_gold(inv, PRICE)
	inv.add_item(deed, 1)
	return Roleplay._say("%d gold, and here's the deed. Launch her from any shore. Mind the deep water: there are storms out there, and worse." % PRICE)
