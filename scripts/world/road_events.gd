class_name RoadEvents
extends Node
## Alpha 1.26: things that happen on the road, staged a little ahead of you (RoadLife finds the spot).
##   highwaymen  three bandits across the road. Talk to the leader: "pay the toll" (gold for the
##               level) and they let you by; "refuse the toll" tries to face them down (Strength and
##               Speech, the chance shown); fail, or walk past without a word, and they draw steel
##   beset       a traveller fighting off wolves. Save them and they pay you what they can
##   ambush      at night: bandits crouched off the road. They rise when you come close
##   wreck       a broken cart and a carter who needs a hand: bring them two firewood
##               (or one and two plant fibre to bind it) and they pay, and tell you something worth knowing
## After a long fast-travel trip there is a chance you were waylaid on arrival (ambush_on_arrival).
## Created by WorldManager. At most one event at a time; it ends when you are far from it.

const EVERY := 45.0  # seconds between rolls
const CHANCE := 0.3
const AHEAD := [70.0, 120.0]
const GONE := 260.0
const KINDS := ["highwaymen", "beset", "ambush", "wreck"]

var world: WorldManager
var enabled := true
var current := {}  # {"kind", "at": Vector3, "members": Array, "state"}
var _t := 20.0
var _rng := RandomNumberGenerator.new()


static func of(tree: SceneTree) -> RoadEvents:
	return tree.get_first_node_in_group("road_events") as RoadEvents if tree != null else null


func _ready() -> void:
	add_to_group("road_events")
	world = get_parent() as WorldManager
	_rng.randomize()


func _process(delta: float) -> void:
	if not current.is_empty():
		_watch()
	_t -= delta
	if _t > 0.0 or not enabled or world == null or get_tree().paused:
		return
	_t = EVERY
	if not current.is_empty() or (world.dungeons != null and world.dungeons.is_inside()):
		return
	if _rng.randf() > CHANCE * float(GameRules.get_rule("encounter_rate")):
		return
	var kind: String = KINDS[_rng.randi() % KINDS.size()]
	if kind == "ambush" and world.clock != null and not world.clock.is_night():
		kind = "highwaymen"
	stage(kind)


## Puts an event on a road ahead of you. Returns its people ([] if no road is near)
func stage(kind: String, at: Vector3 = Vector3.INF) -> Array:
	var p := _player()
	if p == null:
		return []
	if not at.is_finite():
		if world.road_life == null:
			return []
		var was := [world.road_life.spawn_min, world.road_life.spawn_max]
		world.road_life.spawn_min = AHEAD[0]
		world.road_life.spawn_max = AHEAD[1]
		var spot := world.road_life._find_road_spot(p.global_position)
		world.road_life.spawn_min = was[0]
		world.road_life.spawn_max = was[1]
		if spot.is_empty():
			return []
		at = (spot["route"] as PackedVector3Array)[0]
	at.y = world.get_height_at(at.x, at.z)
	var level := _level()
	var members: Array = []
	match kind:
		"highwaymen":
			for i in 3:
				var b := _spawn("enemies", "cutthroat", level, at + Vector3(float(i - 1) * 1.6, 0.6, 0.0))
				if b == null:
					continue
				b.disposition = Enemy.Disposition.NEUTRAL
				b.display_name = "Highwayman"
				b.talk_name = "Highwayman"
				b.set_meta("road_toll", true)
				b.wander_radius = 0.0
				if i == 1:
					b.talk_lines = PackedStringArray(["This road's ours. Everyone pays. Even you."])
				members.append(b)
		"beset":
			var t := _spawn("npcs", "townsfolk", level, at + Vector3(0, 0.6, 0))
			if t != null:
				t.display_name = "Beset Traveller"
				t.talk_name = t.display_name
				t.disposition = Enemy.Disposition.FRIENDLY
				t.set_meta("beset", true)
				members.append(t)
				for i in 2 + _rng.randi() % 2:
					var w := _spawn("enemies", "wolf", maxi(level - 2, 1), at + Vector3(_rng.randf_range(-6, 6), 0.6, _rng.randf_range(-6, 6)))
					if w != null:
						w.set_meta("road_wolf", true)
						members.append(w)
						_after_ready(w, func() -> void: w.fight(t))
		"ambush":
			for i in 3:
				var off := Vector3(_rng.randf_range(8, 12) * (1 if i % 2 == 0 else -1), 0.6, _rng.randf_range(-6, 6))
				var b := _spawn("enemies", "cutthroat", level, at + off)
				if b == null:
					continue
				b.disposition = Enemy.Disposition.NEUTRAL
				b.display_name = "Bandit"
				b.wander_radius = 0.0
				b.set_meta("ambusher", true)
				members.append(b)
		"wreck":
			var c := _spawn("npcs", "townsfolk", level, at + Vector3(0, 0.6, 0))
			if c != null:
				c.display_name = "Stranded Carter"
				c.talk_name = c.display_name
				c.disposition = Enemy.Disposition.FRIENDLY
				c.wander_radius = 1.5
				c.set_meta("carter", true)
				c.talk_lines = PackedStringArray(["Axle's split clean through. If you've any firewood I could splint it, I'd pay you for it."])
				members.append(c)
				_cart(at + Vector3(2.0, 0, 0))
	if members.is_empty():
		return []
	current = {"kind": kind, "at": at, "members": members, "state": "waiting", "toll": 30 + level * 6}
	return members


# Watches the event: tolls, the ambush rising, the traveller saved, the end
func _watch() -> void:
	var p := _player()
	var at: Vector3 = current["at"]
	if p == null or Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() > GONE:
		_end()
		return
	var alive: Array = (current["members"] as Array).filter(func(e): return is_instance_valid(e) and not (e as Enemy).is_dead())
	var d := p.global_position.distance_to(at)
	match String(current["kind"]):
		"highwaymen":
			if current["state"] == "waiting" and d < 14.0:
				current["state"] = "warned"
				Locks.toast(get_tree(), "Highwayman: \"Stop there. %d gold to pass, or we take it off your body.\"" % int(current["toll"]), true)
			elif current["state"] == "warned" and d < 3.5:
				_draw_steel(alive, p)  # walked through them without paying
			elif current["state"] == "warned" and _hostile_now(alive):
				_draw_steel(alive, p)
		"ambush":
			if current["state"] == "waiting" and d < 16.0:
				current["state"] = "sprung"
				Locks.toast(get_tree(), "Bandits rise out of the dark!", true)
				_draw_steel(alive, p)
		"beset":
			var wolves := alive.filter(func(e): return (e as Enemy).has_meta("road_wolf"))
			var trav := alive.filter(func(e): return (e as Enemy).has_meta("beset"))
			if current["state"] == "waiting" and wolves.is_empty() and not trav.is_empty() and d < 20.0:
				current["state"] = "saved"
				var gold := 40 + _level() * 8
				Currency.add_gold(p.get_node("Inventory") as Inventory, gold)
				Locks.toast(get_tree(), "\"You came just in time. Here, %d gold. It's all I have, but it's yours.\"" % gold)
				var t := trav[0] as Enemy
				t.talk_lines = PackedStringArray(["I'd be wolf meat if not for you."])
				t.follow_route(PackedVector3Array([t.global_position + Vector3(40, 0, 40)]), false, 0.5)
			elif current["state"] == "waiting" and trav.is_empty():
				current["state"] = "lost"


func _hostile_now(alive: Array) -> bool:
	for e in alive:
		if (e as Enemy).disposition == Enemy.Disposition.HOSTILE or (e as Enemy).get_fight_target() != null:
			return true
	return false


func _draw_steel(alive: Array, p: Node3D) -> void:
	current["state"] = "fight"
	for e in alive:
		(e as Enemy).disposition = Enemy.Disposition.HOSTILE
		(e as Enemy).aggro(p)


func _end() -> void:
	for e in current.get("members", []):
		if is_instance_valid(e) and not (e as Enemy).is_dead() and (e as Enemy).get_fight_target() == null:
			(e as Enemy).queue_free()
	for c in get_tree().get_nodes_in_group("road_cart"):
		c.queue_free()
	current = {}


# ---------------------------------------------------------------- talking

func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	if s == null or s.enemy == null or not is_instance_valid(s.enemy) or current.is_empty():
		return PackedStringArray()
	if s.enemy.has_meta("road_toll") and current["state"] in ["waiting", "warned"]:
		return PackedStringArray(["pay the toll", "refuse the toll"])
	if s.enemy.has_meta("carter") and current["state"] == "waiting":
		return PackedStringArray(["the broken cart"])
	return PackedStringArray()


func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if s == null or s.enemy == null or current.is_empty():
		return {}
	var p := _player()
	var inv := p.get_node("Inventory") as Inventory
	match topic:
		"pay the toll":
			var toll := int(current["toll"])
			if not Currency.spend_gold(inv, toll):
				return _say("You don't have %d gold? Then we'll take what you do have." % toll, func() -> void: _draw_steel(current["members"], p))
			current["state"] = "paid"
			for e in current["members"]:
				if is_instance_valid(e):
					(e as Enemy).remove_meta("road_toll")
			return _say("Pleasure doing business. Road's clear. For you.")
		"refuse the toll":
			var c := refuse_chance(p)
			if _rng.randf() < c:
				current["state"] = "backed down"
				for e in current["members"]:
					if is_instance_valid(e):
						(e as Enemy).remove_meta("road_toll")
						(e as Enemy).follow_route(PackedVector3Array([(e as Enemy).global_position + Vector3(30, 0, -30)]), false, 0.7)
				return _say("[Intimidate %d%%: success] ...Not worth it. Let them through, lads." % int(c * 100.0))
			return _say("[Intimidate %d%%: failure] Wrong answer." % int(c * 100.0), func() -> void: _draw_steel(current["members"], p))
		"the broken cart":
			var fw := load("res://data/materials/firewood.tres") as ItemData
			var fibre := load("res://data/materials/plant_fibre.tres") as ItemData
			var paid := false
			if fw != null and inv.get_count(fw) >= 2:
				inv.remove_item(fw, 2)
				paid = true
			elif fw != null and fibre != null and inv.get_count(fw) >= 1 and inv.get_count(fibre) >= 2:
				inv.remove_item(fw, 1)
				inv.remove_item(fibre, 2)
				paid = true
			if not paid:
				return _say("Two lengths of firewood would splint it, or one and some fibre to bind it. Nothing? I'll wait. Not like the cart's going anywhere.")
			current["state"] = "mended"
			var gold := 25 + _level() * 5
			Currency.add_gold(inv, gold)
			var tip := _tip()
			return _say("That'll hold to the next town. Here's %d gold for your trouble. And a word: %s" % [gold, tip])
	return {}


## The chance to face the highwaymen down: Strength and Speech, and how much tougher you are
func refuse_chance(p: Node) -> float:
	var stats := p.get_node_or_null("Stats") as Stats
	var skills := p.get_node_or_null("Skills") as Skills
	var str_ := stats.get_stat("strength") if stats != null else 40.0
	var speech := float(skills.get_level(&"speech")) if skills != null else 15.0
	var gap := float((skills.get_player_level() if skills != null else 5) - _level())
	return clampf(0.15 + str_ / 200.0 + speech / 250.0 + gap * 0.03, 0.05, 0.9)


func _tip() -> String:
	var d := world.discovery if world != null else null
	if world != null:
		var best: PlacedPOI = null
		var bd := INF
		var p := _player()
		for poi in world.pois:
			if poi.poi is DungeonEntrancePOIData and not Discovery.is_found(poi.id):
				var dd := poi.position.distance_to(p.global_position)
				if dd < bd and dd < 1500.0:
					bd = dd
					best = poi
		if best != null:
			if d != null:
				d.mark_found(best)
			return "there's an old way down into the earth not far from here. I'll mark it for you."
	return "the inns between the towns keep a bed for anyone with ten gold."


# ---------------------------------------------------------------- after a long trip

## Waylaid on the road: a fight where you arrive (fast travel). The chance grows with the hours.
func ambush_on_arrival(hours: float) -> bool:
	if not enabled:
		return false
	var c := clampf(hours * 0.03, 0.0, 0.3) * float(GameRules.get_rule("encounter_rate"))
	if _rng.randf() >= c or not current.is_empty():
		return false
	var p := _player()
	var at := p.global_position + (-p.global_transform.basis.z).normalized() * 10.0
	var got := stage("ambush", at)
	if got.is_empty():
		return false
	Locks.toast(get_tree(), "You were waylaid on the road!", true)
	_draw_steel(got, p)
	return true


# ---------------------------------------------------------------- small helpers

func _spawn(sub: String, id: String, level: int, at: Vector3) -> Enemy:
	var path := "res://data/%s/%s.tres" % [sub, id]
	if not ResourceLoader.exists(path):
		return null
	at.y = world.get_height_at(at.x, at.z) + 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	return Population.spawn_enemy(load(path), level, world, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})


func _cart(at: Vector3) -> void:
	var cart := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.7, 2.8)
	cart.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.26, 0.16)
	cart.material_override = mat
	cart.add_to_group("road_cart")
	world.add_child(cart)
	cart.global_position = Vector3(at.x, world.get_height_at(at.x, at.z) + 0.45, at.z)
	cart.rotation = Vector3(0.0, _rng.randf() * TAU, 0.18)  # tipped on the broken wheel


static func _after_ready(e: Enemy, f: Callable) -> void:
	if e.is_inside_tree() and e.is_node_ready():
		f.call()
	else:
		e.ready.connect(f, CONNECT_ONE_SHOT)


func _level() -> int:
	var p := _player()
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	return skills.get_player_level() if skills != null else 5


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _say(text: String, after: Callable = Callable()) -> Dictionary:
	if after.is_valid():
		after.call_deferred()
	return {"text": text, "journal": false, "learn": PackedStringArray()}
