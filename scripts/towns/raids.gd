class_name Raids
extends Node
## Alpha 1.25: the wild comes for what you built, and once a month for everyone.
##   raids      a homestead with three parts or two settlers draws raiders every week or two: the
##              hostile side nearest it (bandits, the undead, beasts). Word comes a day ahead (the
##              journal). Be there after dark and they come: your settlers' guards fight with you. Be
##              away and your guards hold them off or not: a lost raid scares the settlers and
##              takes what was in their store.
##   blood moon on the last night of every month the moon rises red (Settings: Blood moon, on by
##              default) and the dead walk on walled places: a horde comes at the gates of the towns
##              near you, and at your homestead.
## Created by WorldManager. Hordes and raiders join through SpawnQueue.

const RAID_EVERY := [7, 12]
const RAID_HOUR := 21.0
const RAID_SIZE := [3, 6]
const HORDE_SIZE := [5, 8]
const HORDE_REACH := 320.0
const UNDEAD := ["skeleton", "skeleton", "grave_ghoul", "skeleton_knight", "barrow_wight"]

var world: WorldManager
var enabled := true
var _t := 3.0
var _alive: Array = []
var _blood_on := false
var _horded := {}  # town id -> night


func _ready() -> void:
	add_to_group("raids")
	world = get_parent() as WorldManager


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null or world.clock == null or get_tree().paused:
		return
	_t = 3.0
	_alive = _alive.filter(func(e): return is_instance_valid(e) and not (e as Enemy).is_dead())
	if not enabled:
		return
	_raid_tick()
	_blood_moon_tick()


# ---------------------------------------------------------------- raids on your homestead

static func eligible() -> bool:
	return Homestead.owns() and (Homestead.built().size() >= 3 or Settlers.all().size() >= 2)


func _raid_tick() -> void:
	if not eligible() or float(GameRules.get_rule("raid_rate")) <= 0.0:
		return
	var day := world.clock.day
	var rec := WorldState.get_record("raid_next")
	if rec.is_empty():
		WorldState.set_record("raid_next", {"day": day + _gap(), "warned": false})
		return
	var due := int(rec["day"])
	if not bool(rec.get("warned", false)) and day >= due - 1:
		var foe := nearest_foe()
		var r := rec.duplicate()
		r["warned"] = true
		r["faction"] = foe
		WorldState.set_record("raid_next", r)
		DialogueState.system_entry("Homestead", "Word from your homestead: %s have been seen nearby. They will come after dark tomorrow." % CreatureFactions.display_name(foe), "")
		Locks.toast(get_tree(), "%s will raid your homestead tomorrow night." % CreatureFactions.display_name(foe), true)
		return
	if day >= due and world.clock.hour >= RAID_HOUR:
		var foe := String(rec.get("faction", "bandits"))
		WorldState.set_record("raid_next", {"day": day + _gap(), "warned": false})
		var p := get_tree().get_first_node_in_group("player") as Node3D
		var plot := Homestead.plot_position()
		if p != null and Vector2(plot.x - p.global_position.x, plot.z - p.global_position.z).length() < 300.0:
			start_raid(foe, plot)
		else:
			_raid_while_away(foe)


## The hostile side closest to the homestead (bandits if none)
func nearest_foe() -> String:
	var plot := Homestead.plot_position()
	var best := "bandits"
	var best_d := INF
	for poi in world.pois:
		if poi.poi is TownData or poi.poi.garrison == null or Discovery.is_cleared(poi.id):
			continue
		var d := poi.position.distance_to(plot)
		if d < best_d and d < 1200.0:
			var kinds := poi.poi.garrison.roll(RandomNumberGenerator.new(), 5) if poi.poi.garrison.has_method("roll") else []
			if not kinds.is_empty():
				var probe := Enemy.create()
				(kinds[0] as EnemyData).apply(probe, 1, RandomNumberGenerator.new())
				var f := CreatureFactions.of(probe)
				probe.free()
				if CreatureFactions.relation(f, "town") == CreatureFactions.Rel.HOSTILE:
					best = f
					best_d = d
	return best


## Raiders come at the homestead (you are there)
func start_raid(foe: String, plot: Vector3) -> int:
	var kinds := CreatureBattles.members_of(foe)
	if kinds.is_empty():
		kinds = CreatureBattles.members_of("bandits")
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	var level := skills.get_player_level() if skills != null else 5
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dir := Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
	var n := rng.randi_range(RAID_SIZE[0], RAID_SIZE[1])
	var was := SpawnQueue.defer
	SpawnQueue.defer = true
	for i in n:
		var data := _data(String(kinds[rng.randi() % kinds.size()]), foe)
		if data == null:
			continue
		var at := plot + dir * 40.0 + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
		at.y = world.get_height_at(at.x, at.z) + 0.6
		var e := Population.spawn_enemy(data, level, world, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
		e.faction = foe
		e.set_meta("raider", true)
		e.set_meta("lod_keep", true)
		_walk_to(e, plot, 0.9)
		_alive.append(e)
	SpawnQueue.defer = was
	WorldState.set_record("homestead_raid", {"day": world.clock.day, "faction": foe})
	Locks.toast(get_tree(), "Raiders! %s are coming for your homestead." % CreatureFactions.display_name(foe), true)
	SoundFX.at(get_tree(), plot + Vector3.UP * 10.0, "horn", 400.0)
	return n


# You weren't there: your guards against their numbers
func _raid_while_away(foe: String) -> void:
	var guards := Settlers.guards()
	var won := randf() < clampf(0.25 + 0.2 * float(guards), 0.1, 0.95)
	if won:
		DialogueState.system_entry("Homestead", "%s raided your homestead in the night. Your people drove them off." % CreatureFactions.display_name(foe), "")
		return
	WorldState.set_record("homestead_raid", {"day": world.clock.day, "faction": foe})
	WorldState.erase_record(Settlers.STORE)
	DialogueState.system_entry("Homestead", "%s raided your homestead in the night and carried off the settlers' store. Your people are shaken." % CreatureFactions.display_name(foe), "")
	Locks.toast(get_tree(), "Your homestead was raided while you were away.", true)


func _data(kind: String, faction: String) -> EnemyData:
	var sub := "npcs" if faction in ["town", "livestock"] else "enemies"
	var path := "res://data/%s/%s.tres" % [sub, kind]
	return load(path) as EnemyData if ResourceLoader.exists(path) else null


# ---------------------------------------------------------------- the blood moon

## The last night of the month (blood moon on in Settings)
func is_blood_moon() -> bool:
	if world.clock == null or not bool(GameSettings.get_value("blood_moon")):
		return false
	var night := world.clock.is_night()
	return night and world.clock.get_day_of_month() == WorldClock.DAYS_PER_MONTH and world.clock.day > 7


func _blood_moon_tick() -> void:
	var on := is_blood_moon()
	if on and not _blood_on:
		Locks.toast(get_tree(), "The moon rises red. The dead will walk tonight.", true)
		DialogueState.system_entry("Omens", "A blood moon. Tonight the dead walk on the walled places.", "")
	if on != _blood_on:
		_blood_on = on
		_tint_sky(on)
	if not on:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or (world.dungeons != null and world.dungeons.is_inside()):
		return
	var night_id := world.clock.day
	for t in world.towns:
		if Vector2(t.position.x - p.global_position.x, t.position.z - p.global_position.z).length() > HORDE_REACH:
			continue
		if int(_horded.get(t.id, -1)) == night_id:
			continue
		_horded[t.id] = night_id
		horde(t.position)
	if Homestead.owns():
		var plot := Homestead.plot_position()
		if int(_horded.get("homestead", -1)) != night_id and Vector2(plot.x - p.global_position.x, plot.z - p.global_position.z).length() < HORDE_REACH:
			_horded["homestead"] = night_id
			horde(plot)


## The dead come at a walled place from outside: they walk on its middle
func horde(at: Vector3) -> int:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	var level := skills.get_player_level() if skills != null else 5
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dir := Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
	var n := roundi(rng.randi_range(HORDE_SIZE[0], HORDE_SIZE[1]) * float(GameRules.get_rule("raid_rate")))  # 1.26: the Raids and hordes setting
	var was := SpawnQueue.defer
	SpawnQueue.defer = true
	for i in n:
		var data := _data(UNDEAD[rng.randi() % UNDEAD.size()], "undead")
		if data == null:
			continue
		var from := at + dir * 70.0 + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		from.y = world.get_height_at(from.x, from.z) + 0.6
		var e := Population.spawn_enemy(data, level, world, from, rng, {"persist_mode": Enemy.PersistMode.NEVER})
		e.faction = "undead"
		e.set_meta("horde", true)
		_walk_to(e, at, 0.7)
		_alive.append(e)
	SpawnQueue.defer = was
	return n


func _tint_sky(on: bool) -> void:
	var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if we.is_empty() or (we[0] as WorldEnvironment).environment == null:
		return
	var env := (we[0] as WorldEnvironment).environment
	if on:
		set_meta("fog_before", env.fog_light_color)
		env.fog_light_color = Color(0.55, 0.12, 0.1)
	elif has_meta("fog_before"):
		env.fog_light_color = get_meta("fog_before")


# Sets off toward a spot once it has joined the world (it may still be waiting in SpawnQueue)
static func _walk_to(e: Enemy, to: Vector3, speed: float) -> void:
	if e.is_inside_tree() and e.is_node_ready():
		e.follow_route(PackedVector3Array([to]), false, speed)
	else:
		e.ready.connect(func() -> void: e.follow_route(PackedVector3Array([to]), false, speed), CONNECT_ONE_SHOT)


# Days to the next raid, by the Raids and hordes setting (1.26)
func _gap() -> int:
	var rate := maxf(float(GameRules.get_rule("raid_rate")), 0.1)
	return maxi(roundi(randi_range(RAID_EVERY[0], RAID_EVERY[1]) / rate), 2)
