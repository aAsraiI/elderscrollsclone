class_name TownLife
extends Node
## The people of every town and their day. Created by WorldManager, nothing to add by hand.
##
## Everyone's day comes from their NpcData and the WorldClock:
##   work hours  shopkeepers, smiths, priests, guild members and the innkeeper are inside their
##               building (it is unlocked); farmers are out in their field; the rest are on the square
##   evening     free time: on the square, by their front door, or over at the inn
##   night       they walk home, go in and lock the door, and sleep (you find them in bed)
##   guards      walk their rounds day and night, with a lantern after dark
##
## Bodies only exist where you can see them: outside in towns whose buildings are loaded, and
## inside the one building you are in. Everyone else is just data that keeps time, so a town you
## walk into at midnight is asleep behind locked doors. Nobody alive is saved: where people are
## follows from the clock. What IS saved (WorldState): who is dead ("kill/npc/..."), the last
## activity applied to each person ("npcact/...") and the door locks.
##
## Locks follow the owners: a home is locked while its owner sleeps; a shop is open during work
## hours and locked otherwise; a plain house is back to its usual state when the owner is up. A
## lock you picked stays open until the owner's day next moves on.

## Seconds between updates
const TICK := 0.5
## Jumps of the clock bigger than this (hours: skipping time, loading) are not walked: everyone
## is simply put where they should be
const JUMP_HOURS := 0.5
## Walking speed as a part of the body's run speed
const WALK := 0.45

class Resident:
	var data: NpcData
	var town: PlacedPOI
	var activity := -1
	## The building they are in ("" = outside)
	var inside := ""
	## Where they are headed or staying: {"inside": id} / {"outside": local pos} / {"field": pick} / {"patrol": true}
	var goal := {}
	## Their body while it exists (outside in a loaded town, or inside the interior you are in)
	var node: Enemy
	var node_inside := false
	var walking := false
	var dead := false
	## Which stretch of free time it is (see _leisure_slot): a new one sends them somewhere else
	var slot := -1

var world: WorldManager
var clock: WorldClock
var residents: Array[Resident] = []

var _by_town := {}   # town id -> Array of Resident
var _by_id := {}     # npc id -> Resident
var _loaded := {}    # town id -> true while its buildings exist
var _root: Node3D
var _timer := 0.0
var _last_hour := -1.0
var _beds_used := 0


func _ready() -> void:
	add_to_group("town_life")
	world = get_parent() as WorldManager
	clock = world.clock if world != null else null
	_root = Node3D.new()
	_root.name = "Townsfolk"
	add_child(_root)
	if world == null:
		return
	world.poi_spawned.connect(_on_poi_spawned)
	world.poi_removed.connect(_on_poi_removed)
	world.world_rebuilt.connect(rebuild)
	if world.dungeons != null:
		world.dungeons.entered.connect(_on_entered)
		world.dungeons.exited.connect(_on_exited)
	rebuild()


# ---------------------------------------------------------------- public API

func get_resident(npc_id: String) -> Resident:
	return _by_id.get(npc_id)


func get_town_residents(town_id: String) -> Array:
	return _by_town.get(town_id, [])


## The resident whose home is this building (null for none)
func get_owner_of(building_id: String) -> Resident:
	return _by_id.get("npc/" + building_id)


## Makes everyone again (new world seed)
func rebuild() -> void:
	for r in residents:
		_free_body(r)
	residents.clear()
	_by_town.clear()
	_by_id.clear()
	_loaded.clear()
	for t in world.towns:
		var list: Array = []
		for n in Residents.generate(t, world.map):
			var r := Resident.new()
			r.data = n
			r.town = t
			r.dead = WorldState.has_record("kill/" + n.id)
			residents.append(r)
			list.append(r)
			_by_id[n.id] = r
		_by_town[t.id] = list
	_last_hour = _start_hour()
	for r in residents:
		_settle(r, _last_hour)
	for t in world.towns:
		if world.get_poi_node(t.id) != null:
			_on_town_loaded(t)


## Puts everyone where the clock says, right now (after skipping time)
func resettle() -> void:
	var h := _hour()
	_last_hour = h
	for r in residents:
		_free_body(r)
		_settle(r, h)
	for id in _loaded.keys():
		for r: Resident in _by_town.get(id, []):
			_show_outside(r)
	_populate_interior()


# ---------------------------------------------------------------- the clock

func _process(delta: float) -> void:
	if world == null or clock == null or _save_loading():
		return
	_timer += delta
	if _timer < TICK:
		return
	_timer = 0.0
	var h := _hour()
	if fposmod(h - _last_hour, 24.0) > JUMP_HOURS:
		resettle()
		return
	_last_hour = h
	var night := clock.is_night()
	for r in residents:
		if r.dead:
			continue
		var act := _activity(r, h)
		var slot := _leisure_slot(r, h) if act == NpcData.Activity.LEISURE else -1
		if act != r.activity or slot != r.slot:
			r.slot = slot
			_change(r, act)
		else:
			_keep_going(r)
		if r.data.role == NpcData.Role.GUARD and _alive(r.node):
			var lantern := r.node.get_node_or_null("Lantern") as Light3D
			if lantern != null:
				lantern.visible = night


func _hour() -> float:
	return clock.hour if clock != null else 12.0


# A load in progress: the save's time, not the clock's (it is set a moment later)
func _start_hour() -> float:
	if SaveSession.has_pending():
		var c: Dictionary = SaveSession.pending.get("clock", {})
		if c.has("hour"):
			return fposmod(float(c["hour"]), 24.0)
	return _hour()


func _save_loading() -> bool:
	var sm := get_tree().get_first_node_in_group("save_manager") as SaveManager
	return sm != null and sm.is_loading()


# ---------------------------------------------------------------- where people should be

func _settle(r: Resident, hour: float) -> void:
	if r.dead:
		return
	var act := _activity(r, hour)
	r.slot = _leisure_slot(r, hour) if act == NpcData.Activity.LEISURE else -1
	_set_activity(r, act)
	r.goal = _goal_for(r, r.activity)
	r.inside = String(r.goal.get("inside", ""))
	r.walking = false


func _set_activity(r: Resident, act: int) -> void:
	var key := "npcact/" + r.data.id
	var before := r.activity
	if before < 0:
		before = int(WorldState.get_record(key).get("a", -1))
	r.activity = act
	if before == act:
		return
	WorldState.set_record(key, {"a": act})
	# Whenever the owner's day moves on (off to work, home for the night, waking up) they see to
	# their door, so a lock you picked only stays open until then
	var home := world.get_building(r.data.home_id)
	if home != null:
		Locks.set_locked(home.id, _wants_locked(home, act))


func _wants_locked(home: BuildingPlot, act: int) -> bool:
	if act == NpcData.Activity.SLEEP:
		return true
	if home.is_public():
		return act != NpcData.Activity.WORK
	return home.starts_locked


func _goal_for(r: Resident, act: int) -> Dictionary:
	var d := r.data
	var layout := r.town.town
	var pick := ("%s|%d" % [d.id, clock.day if clock != null else 1]).hash() & 0x7FFFFFFF
	match act:
		NpcData.Activity.PATROL:
			if d.post >= 0 and d.post < layout.gates.size():
				# a gate post: just inside the gate, beside the road
				var gate := layout.gates[d.post]
				var inward := -gate.normalized()
				var side := Vector3(-inward.z, 0.0, inward.x) * (4.0 if d.post == 0 else -4.0)
				return {"outside": gate + inward * 6.0 + side}
			return {"patrol": true}
		NpcData.Activity.SLEEP:
			return {"inside": d.home_id}
		NpcData.Activity.WORK:
			if d.work_id != "":
				return {"inside": d.work_id}
			if d.role == NpcData.Role.FARMER:
				return {"field": pick}
			if NpcData.is_tradesman(d.role):
				var home := world.get_building(d.home_id)
				if home != null:
					return {"outside": layout.get_trade_spot(home)}  # the woodpile, the drying rack, the shore
			return {"outside": layout.get_plaza_spot(pick)}
	return _leisure_goal(r, layout)


## Free time changes every hour and a half or so (each person on their own clock). Who goes where
## depends on the hour, the weather (rain sends people indoors), the day (Sunsday is a day of rest
## and temple, Fairday is market day) and their personality.
func _leisure_slot(r: Resident, hour: float) -> int:
	var offset := float(r.data.id.hash() & 0xFF) / 255.0 * 1.5
	return int(floor((hour + offset) / 1.5))


func _leisure_goal(r: Resident, layout: TownLayout) -> Dictionary:
	var d := r.data
	var day := clock.day if clock != null else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|%d|%d" % [d.id, day, r.slot]).hash()
	var h := _hour()
	var raining := false
	var weather := Weather.get_instance(get_tree())
	if weather != null and weather.enabled:
		raining = weather.is_precipitating()
	var rest_day := clock != null and clock.get_weekday() == WorldClock.REST_DAY
	var market := clock != null and clock.get_weekday() == WorldClock.MARKET_DAY
	var evening := h >= 18.0 or h < 4.0
	var inn := ""
	var temple := ""
	var shops: Array[String] = []
	for b in layout.buildings:
		match b.kind:
			BuildingPlot.Kind.INN:
				inn = b.id
			BuildingPlot.Kind.TEMPLE:
				temple = b.id
			BuildingPlot.Kind.SHOP, BuildingPlot.Kind.SMITHY:
				if b.id != d.home_id:
					shops.append(b.id)
	# Weights for each kind of outing
	var w := {
		"plaza": 3.0 + (3.0 if market else 0.0), "chat": 3.0, "stroll": 2.5, "doorstep": 1.5,
		"inn": (3.5 if evening else 0.8), "temple": (4.0 if rest_day and h < 13.0 else 0.6), "errand": (2.0 if h >= 8.0 and h < 17.0 else 0.0),
		"home": 1.0,
	}
	# the town's own things (Alpha 1.14): a bench to sit on, the well or fountain, the market stalls
	var benches := layout.dress.filter(func(x: Dictionary) -> bool: return x["what"] == "bench")
	var wells := layout.dress.filter(func(x: Dictionary) -> bool: return x["what"] in ["well", "fountain"])
	var stalls := layout.dress.filter(func(x: Dictionary) -> bool: return x["what"] == "stall")
	w["bench"] = 2.0 if not benches.is_empty() else 0.0
	w["water"] = (1.6 if h < 11.0 else 0.5) if not wells.is_empty() else 0.0
	w["stall"] = (2.5 if h >= 8.0 and h < 17.0 else 0.0) if not stalls.is_empty() else 0.0
	if d.personality == NpcData.Personality.PIOUS:
		w["temple"] *= 3.0
	elif d.personality == NpcData.Personality.CHEERFUL or d.personality == NpcData.Personality.FRIENDLY:
		w["chat"] *= 1.6
		w["inn"] *= 1.4
	elif d.personality == NpcData.Personality.GRUMPY:
		w["chat"] *= 0.4
		w["home"] *= 2.5
	elif d.personality == NpcData.Personality.NERVOUS:
		w["home"] *= 2.0
		w["stroll"] *= 0.5
	if raining:
		for k in ["plaza", "chat", "stroll", "doorstep", "bench", "water", "stall"]:
			w[k] *= 0.15
		w["inn"] *= 2.0
		w["home"] *= 3.0
	if inn == "" or inn == d.home_id:
		w["inn"] = 0.0
	if temple == "":
		w["temple"] = 0.0
	if shops.is_empty():
		w["errand"] = 0.0
	var total := 0.0
	for k in w:
		total += float(w[k])
	var roll := rng.randf() * total
	var choice := "plaza"
	for k in w:
		roll -= float(w[k])
		if roll <= 0.0:
			choice = k
			break
	var home := world.get_building(d.home_id)
	match choice:
		"inn":
			return {"inside": inn, "pose": &"drink" if rng.randf() < 0.5 else &"sit"}
		"temple":
			return {"inside": temple, "pose": &"pray"}
		"errand":
			return {"inside": shops[rng.randi() % shops.size()], "pose": &""}
		"home":
			if home != null:
				return {"inside": home.id, "pose": &"sit"}
		"doorstep":
			if home != null:
				var door := home.get_door_local()
				return {"outside": door + (door - home.local_pos).normalized() * 1.5, "pose": &"sweep" if rng.randf() < 0.4 else &""}
		"bench":
			var bd: Dictionary = benches[rng.randi() % benches.size()]
			return {"outside": Vector3(bd["pos"]) + Basis(Vector3.UP, float(bd["yaw"])) * Vector3(0, 0, -0.55), "pose": &"sit"}
		"water":
			var wd: Dictionary = wells[rng.randi() % wells.size()]
			var wp: Vector3 = wd["pos"]
			var to_mid := -Vector3(wp.x, 0, wp.z).normalized() if Vector3(wp.x, 0, wp.z).length() > 0.5 else Vector3(0, 0, -1)
			return {"outside": wp + to_mid * 2.4 + Vector3(rng.randf_range(-0.8, 0.8), 0, 0), "pose": &"work"}
		"stall":
			var sd: Dictionary = stalls[rng.randi() % stalls.size()]
			var sp: Vector3 = sd["pos"]
			return {"outside": sp - Vector3(sp.x, 0, sp.z).normalized() * 1.8, "pose": &"talk"}
		"chat":
			# A few gathering spots on the square: whoever picks the same one ends up talking
			var spot := layout.get_plaza_spot(((day * 7 + r.slot) * 13 + rng.randi_range(0, 3) * 211) & 0x7FFFFFFF)
			var jitter := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
			return {"outside": spot + jitter, "pose": &"talk"}
		"stroll":
			if not layout.streets.is_empty():
				var s := layout.streets[rng.randi() % layout.streets.size()]
				var p := s.a.lerp(s.b, rng.randf_range(0.15, 0.85))
				var side := (s.b - s.a).normalized().cross(Vector3.UP) * s.half_width * 0.8 * (1.0 if rng.randf() < 0.5 else -1.0)
				return {"outside": p + side, "pose": &""}
	return {"outside": layout.get_plaza_spot(rng.randi() & 0xFFFF), "pose": &"talk" if rng.randf() < 0.4 else &""}


## What someone does now, with days of rest: on Sunsday farmers, smiths and tradesmen stay off work
func _activity(r: Resident, hour: float) -> int:
	var act := r.data.activity_at(hour)
	if act == NpcData.Activity.WORK and clock != null and clock.get_weekday() == WorldClock.REST_DAY:
		var role := r.data.role
		if role == NpcData.Role.FARMER or role == NpcData.Role.SMITH or NpcData.is_tradesman(role):
			return NpcData.Activity.LEISURE
	return act


# ---------------------------------------------------------------- changes during the day

func _change(r: Resident, act: int) -> void:
	_set_activity(r, act)
	var goal := _goal_for(r, act)
	r.goal = goal
	if not _loaded.has(r.town.id):
		r.inside = String(goal.get("inside", ""))  # nobody is watching: just be there
		return
	if r.inside != "":
		var from := world.get_building(r.inside)
		if String(goal.get("inside", "")) == r.inside:
			_populate_interior_one(r)  # stays in (the innkeeper going to bed): just move inside
			return
		_walk_out_of_interior(r)
		r.inside = ""
		if from != null:
			r.node = _make_body(r, _root, from.get_door_position() + Vector3.UP * 0.3)
			r.node_inside = false
	if not _alive(r.node) or r.node_inside:
		r.node = _make_body(r, _root, _outside_spot(r))
		r.node_inside = false
	_walk(r)


# Walks toward the goal again after being interrupted (a fight, fleeing)
func _keep_going(r: Resident) -> void:
	if r.node_inside or not _alive(r.node) or r.node.disposition == Enemy.Disposition.HOSTILE:
		return
	if r.node.state != Enemy.State.IDLE and r.node.state != Enemy.State.WANDER:
		return
	if r.walking or r.goal.has("patrol"):
		_walk(r)
	elif r.goal.has("outside") or r.goal.has("field"):
		var at := _outside_spot(r)
		if Vector2(at.x - r.node.global_position.x, at.z - r.node.global_position.z).length() > 8.0:
			_walk(r)


func _walk(r: Resident) -> void:
	if not _alive(r.node):
		return
	var layout := r.town.town
	var here := layout.to_local(r.node.global_position)
	var pts := PackedVector3Array()
	var loop := false
	if r.goal.has("patrol"):
		pts = _patrol_route(r)
		loop = true
	elif r.goal.has("inside"):
		var b := world.get_building(String(r.goal["inside"]))
		if b == null:
			return
		pts = layout.find_route(here, b.get_door_local())
	elif r.goal.has("field"):
		var home := world.get_building(r.data.home_id)
		pts = layout.find_route(here, home.get_door_local())
		pts.append_array(home.get_field_path(int(r.goal["field"])))
	else:
		pts = layout.find_route(here, r.goal["outside"])
	r.walking = not loop
	r.node.wander_radius = 0.0
	if r.node.body != null:
		r.node.body.pose = &""
	r.node.follow_route(_to_world(layout, pts), loop, 0.38 if loop else WALK)


func _on_arrived(r: Resident) -> void:
	r.walking = false
	if not _alive(r.node) or r.node_inside:
		return
	if r.goal.has("inside"):
		r.node.queue_free()
		r.node = null
		r.inside = String(r.goal["inside"])
		var dm := world.dungeons
		if dm != null and dm.is_inside() and dm.current_entrance_id == r.inside:
			_place_inside(r, true)  # you are in there: they come in through the door
	else:
		r.node.wander_radius = 2.5 if r.goal.has("field") else 3.0
		_pose_outside(r)


# ---------------------------------------------------------------- bodies outside

func _on_poi_spawned(placed: PlacedPOI, _node: Node3D) -> void:
	if placed.poi is TownData:
		_on_town_loaded(placed)


func _on_poi_removed(placed: PlacedPOI) -> void:
	if not placed.poi is TownData:
		return
	_loaded.erase(placed.id)
	for r: Resident in _by_town.get(placed.id, []):
		if not r.node_inside:
			_free_body(r)


func _on_town_loaded(t: PlacedPOI) -> void:
	_loaded[t.id] = true
	for r: Resident in _by_town.get(t.id, []):
		_show_outside(r)


func _show_outside(r: Resident) -> void:
	if r.dead or r.inside != "" or (_alive(r.node) and not r.node_inside):
		return
	r.node = _make_body(r, _root, _outside_spot(r))
	r.node_inside = false
	if r.goal.has("patrol"):
		_walk(r)
	elif r.goal.has("field") or r.goal.has("outside"):
		r.node.wander_radius = 3.0
		_pose_outside(r)


# Where someone stands outside right now (their goal; a guard starts somewhere on their rounds)
func _outside_spot(r: Resident) -> Vector3:
	var layout := r.town.town
	var local := Vector3.ZERO
	if r.goal.has("outside"):
		local = r.goal["outside"]
	elif r.goal.has("field"):
		var path := world.get_building(r.data.home_id).get_field_path(int(r.goal["field"]))
		local = path[path.size() - 1]
	elif r.goal.has("patrol"):
		var route := _patrol_route(r)
		return route[(r.data.id.hash() & 0xFFFF) % route.size()] + Vector3.UP * 0.3
	elif r.goal.has("inside"):
		var b := world.get_building(String(r.goal["inside"]))
		if b != null:
			local = b.get_door_local()
	var w := layout.to_world(local)
	return Vector3(w.x, world.get_height_at(w.x, w.z) + 0.3, w.z)


# A guard's rounds: a few street ends and the square, joined along the streets, in a loop
func _patrol_route(r: Resident) -> PackedVector3Array:
	var layout := r.town.town
	var stops: Array[Vector3] = [Vector3.ZERO]
	for s in layout.streets:
		stops.append(s.a.lerp(Vector3.ZERO, 0.08))
		stops.append(s.b.lerp(Vector3.ZERO, 0.08))
	var rng := RandomNumberGenerator.new()
	rng.seed = r.data.id.hash()
	for i in range(stops.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := stops[i]
		stops[i] = stops[j]
		stops[j] = tmp
	var count := mini(4, stops.size())
	var pts := PackedVector3Array()
	for i in count:
		var leg := layout.find_route(stops[i], stops[(i + 1) % count])
		for p in leg:
			if pts.is_empty() or p.distance_to(pts[pts.size() - 1]) > 0.5:
				pts.append(p)
	return _to_world(layout, pts)


func _to_world(layout: TownLayout, local_pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in local_pts:
		var w := layout.to_world(p)
		out.append(Vector3(w.x, world.get_height_at(w.x, w.z) + 0.1, w.z))
	return out


func _make_body(r: Resident, parent: Node3D, pos: Vector3) -> Enemy:
	var d := r.data
	var rng := RandomNumberGenerator.new()
	rng.seed = d.id.hash()
	var e := Enemy.create()
	d.body.apply(e, d.level, rng)
	e.display_name = d.display_name
	e.talk_name = d.display_name
	e.talk_lines = d.talk_lines
	e.placeholder_color = d.color
	e.wander_radius = 0.0
	e.persist_mode = Enemy.PersistMode.CORPSE_ONLY
	e.spawn_key = d.id
	e.set_meta("npc_id", d.id)
	if d.role == NpcData.Role.GUARD:
		e.set_meta("guard", true)  # townsfolk in trouble call for these (Enemy._call_guards)
	e.rotation.y = rng.randf() * TAU
	e.position = parent.to_local(pos) if parent.is_inside_tree() else pos
	parent.add_child(e)
	e.died.connect(_on_died.bind(r))
	if parent == _root:
		var layout := r.town.town
		e.path_provider = func(from: Vector3, to: Vector3) -> PackedVector3Array:
			return _to_world(layout, layout.find_route(layout.to_local(from), layout.to_local(to)))
	if d.role == NpcData.Role.GUARD:
		var lantern := OmniLight3D.new()
		lantern.name = "Lantern"
		lantern.light_color = Color(1.0, 0.75, 0.45)
		lantern.light_energy = 1.3
		lantern.omni_range = 9.0
		lantern.position = Vector3(-0.45, 1.3, -0.3)
		lantern.visible = clock != null and clock.is_night()
		e.add_child(lantern)
	if parent == _root:
		e.route_finished.connect(_on_arrived.bind(r))
	return e


func _on_died(_e: Enemy, r: Resident) -> void:
	r.dead = true
	Rumors.on_murder(r.data.display_name, r.town)
	r.walking = false


func _free_body(r: Resident) -> void:
	if _alive(r.node):
		r.node.queue_free()
	r.node = null
	r.node_inside = false


func _alive(e: Object) -> bool:  # untyped on purpose: a freed body must not crash the check
	return e != null and is_instance_valid(e) and not (e as Enemy).is_queued_for_deletion() and not (e as Enemy).is_dead()


# ---------------------------------------------------------------- inside buildings

func _on_entered(_id: String) -> void:
	_populate_interior()


func _on_exited(_id: String) -> void:
	for r in residents:
		if r.node_inside:
			r.node = null  # the interior (and the bodies in it) is gone
			r.node_inside = false


func _populate_interior() -> void:
	var dm := world.dungeons
	if dm == null or not dm.is_in_building():
		return
	_beds_used = 0
	for r in residents:
		if not r.dead and r.inside == dm.current_entrance_id and not (_alive(r.node) and r.node_inside):
			_place_inside(r, false)


func _populate_interior_one(r: Resident) -> void:
	var dm := world.dungeons
	if dm != null and dm.is_in_building() and dm.current_entrance_id == r.inside:
		if _alive(r.node) and r.node_inside:
			r.node.queue_free()
		_place_inside(r, false)


# A body inside the interior you are in: in bed, at work, or by a table. walk_in = they just came
# through the door and walk to their place first.
func _place_inside(r: Resident, walk_in: bool) -> void:
	var dm := world.dungeons
	var root := dm.get_interior_root()
	var spots := dm.current_spots
	if root == null or spots.is_empty():
		return
	var spot: Vector3 = spots.get("work", Vector3.ZERO)
	var bed := false
	var beds: Array = spots.get("beds", [])
	var seats: Array = spots.get("seats", [])
	var pick := r.data.id.hash() & 0xFFFF
	if r.activity == NpcData.Activity.SLEEP and _beds_used < beds.size():
		spot = beds[_beds_used]
		_beds_used += 1
		bed = true
	elif r.activity != NpcData.Activity.WORK or r.data.work_id != r.inside:
		if not seats.is_empty():
			spot = seats[pick % seats.size()]
		else:
			spot = Vector3(float(pick % 5) - 2.0, 0.0, float((pick / 5) % 3) - 1.0)
	var start: Vector3 = spots.get("exit", Vector3.ZERO) if walk_in else spot
	var e := _make_body(r, root, root.to_global(start + Vector3.UP * 0.2))
	r.node = e
	r.node_inside = true
	var pose := _inside_pose(r, bed)
	if walk_in:
		e.follow_route(_global_route(root, InteriorBuilder.route(spots, start, spot)), false, WALK)
		if bed:
			e.route_finished.connect(func() -> void: _lie_down(e, root.to_global(spot)), CONNECT_ONE_SHOT)
		elif e.body != null:
			e.route_finished.connect(func() -> void:
				if is_instance_valid(e) and e.body != null:
					e.body.pose = pose, CONNECT_ONE_SHOT)
	elif bed:
		_lie_down(e, root.to_global(spot))
	elif e.body != null:
		e.body.pose = pose


# What someone does at their spot indoors: the smith hammers, the priest kneels, guests sit or drink
func _inside_pose(r: Resident, bed: bool) -> StringName:
	if bed:
		return &"sleep"
	if r.activity == NpcData.Activity.WORK and r.data.work_id == r.inside:
		match r.data.role:
			NpcData.Role.SMITH:
				return &"work"
			NpcData.Role.PRIEST:
				return &"pray"
			NpcData.Role.INNKEEPER:
				return &"sweep" if (r.data.id.hash() & 1) == 0 else &""
		return &""
	var p: StringName = r.goal.get("pose", &"sit")
	return p if p != &"" else &"talk"


# Standing about outside: what they do there (and chatting people turn to each other)
func _pose_outside(r: Resident) -> void:
	if not _alive(r.node) or r.node.body == null:
		return
	var p: StringName = r.goal.get("pose", &"")
	if r.goal.has("field"):
		p = &"farm"
	elif r.activity == NpcData.Activity.WORK and NpcData.is_tradesman(r.data.role):
		match r.data.role:
			NpcData.Role.WOODCUTTER:
				p = &"chop"
			NpcData.Role.MINER:
				p = &"work"
			NpcData.Role.HERBALIST:
				p = &"farm"
	r.node.body.pose = p
	if p != &"":
		r.node.wander_radius = 0.0
	if p == &"talk":
		_face_nearest(r)


func _face_nearest(r: Resident) -> void:
	var best: Enemy = null
	var best_d := 3.5
	for o: Resident in _by_town.get(r.town.id, []):
		if o == r or not _alive(o.node) or o.node_inside:
			continue
		var dd := o.node.global_position.distance_to(r.node.global_position)
		if dd < best_d:
			best_d = dd
			best = o.node
	if best != null:
		var to := best.global_position - r.node.global_position
		r.node.rotation.y = atan2(-to.x, -to.z)


# Someone in the interior you are in leaves: they walk to the door and are gone
func _walk_out_of_interior(r: Resident) -> void:
	if not _alive(r.node) or not r.node_inside:
		return
	var e := r.node
	r.node = null
	r.node_inside = false
	_wake(e)
	var dm := world.dungeons
	var root := dm.get_interior_root()
	if root == null:
		e.queue_free()
		return
	var here := root.to_local(e.global_position)
	e.follow_route(_global_route(root, InteriorBuilder.route(dm.current_spots, here, dm.current_spots.get("exit", Vector3.ZERO))), false, WALK)
	e.route_finished.connect(e.queue_free, CONNECT_ONE_SHOT)


# A route indoors (local points, through doorways and up stairs) in world space
func _global_route(root: Node3D, local: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in local:
		out.append(root.to_global(p))
	return out


func _lie_down(e: Enemy, bed: Vector3) -> void:
	if not _alive(e):
		return
	e.stop_route()
	e.set_physics_process(false)
	e.velocity = Vector3.ZERO
	e.global_position = bed + Vector3(0.0, 1.0, -0.9)
	e.rotation = Vector3(PI * 0.5, 0.0, 0.0)  # head on the pillow (+Z)
	e.set_meta("asleep", true)
	if e.body != null:
		e.body.pose = &"sleep"
	var zzz := Label3D.new()
	zzz.name = "Zzz"
	zzz.text = "Zzz"
	zzz.font_size = 36
	zzz.pixel_size = 0.006
	zzz.outline_size = 8
	zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zzz.top_level = true
	e.add_child(zzz)
	zzz.global_position = bed + Vector3(0.0, 1.7, 0.6)
	var talk := e.get_node_or_null("NpcTalk") as NpcTalk
	if talk != null:
		talk.lines = PackedStringArray(["Zzz...", "Mmh... go away... I'm sleeping...", "Wha-? Who's there? ...Zzz..."])
	e.combat.damaged.connect(func(_info: DamageInfo, _amount: float) -> void: _wake(e), CONNECT_ONE_SHOT)


func _wake(e: Enemy) -> void:
	if e == null or not is_instance_valid(e) or not e.get_meta("asleep", false):
		return
	e.set_meta("asleep", false)
	if e.body != null:
		e.body.pose = &""
	e.rotation = Vector3.ZERO
	e.global_position += Vector3(0.0, 0.2, -1.0)
	e.set_physics_process(true)
	var zzz := e.get_node_or_null("Zzz")
	if zzz != null:
		zzz.queue_free()
	var talk := e.get_node_or_null("NpcTalk") as NpcTalk
	var r := get_resident(String(e.get_meta("npc_id", "")))
	if talk != null and r != null:
		talk.lines = r.data.talk_lines
