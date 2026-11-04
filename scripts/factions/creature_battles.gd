class_name CreatureBattles
extends Node
## Alpha 1.24: fights between factions you can come across. Every few minutes outside (not near a
## town), two groups of sides that fight on sight are placed out ahead of you, a little way apart:
##   a border skirmish: between two nearby places held by hostile sides (a bandit camp and a crypt)
##   a roadside battle: otherwise, on the land ahead
## They find each other by themselves (Enemy._scan_for_foes). Pick a side, or wait and loot the winner.
## Their dead come back with the place (CreatureFactions: only your kills last). Created by WorldManager.

const EVERY_MIN := 240.0  # seconds between battles (real time)
const EVERY_MAX := 420.0
const NEAR := 90.0   # how far ahead they are placed
const FAR := 160.0
const GONE := 450.0  # further than this from you: they are cleared away

## Pairs that make sense to meet on the road, with how often
const PAIRS := [["bandits", "undead", 3], ["bandits", "town", 3], ["beasts", "undead", 2], ["smugglers", "undead", 1],
	["vampires", "werewolves", 1], ["cultists", "town", 2], ["werewolves", "bandits", 1], ["beasts", "livestock", 1]]

var world: WorldManager
var enabled := true
var _timer := 0.0
var _alive: Array = []  # Enemy


func _ready() -> void:
	add_to_group("creature_battles")
	world = get_parent() as WorldManager
	_timer = randf_range(EVERY_MIN * 0.5, EVERY_MAX)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 5.0
	_clean_up()
	if not enabled or world == null or world.map == null or get_tree().paused:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or (world.dungeons != null and world.dungeons.is_inside()) or _near_town(p.global_position):
		return
	if not _alive.is_empty():
		return  # one at a time
	_timer = randf_range(EVERY_MIN, EVERY_MAX)
	var border := _border(p.global_position)
	if not border.is_empty():
		start(world, border["at"], border["a"], border["b"])
		return
	var pair := _pick_pair()
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	var ang := randf_range(-0.8, 0.8)
	var at := p.global_position + fwd.normalized().rotated(Vector3.UP, ang) * randf_range(NEAR, FAR)
	start(world, at, pair[0], pair[1])


## Two groups of these sides, 9 m apart around `at`. Returns a line for the debug console.
static func start(w: WorldManager, at: Vector3, a: String, b: String) -> String:
	if CreatureFactions.relation(a, b) != CreatureFactions.Rel.HOSTILE:
		return "%s and %s are not at war (%s)." % [a, b, CreatureFactions.rel_name(CreatureFactions.relation(a, b))]
	var zone := LevelCurve.zone_range(w.map, at) if w.map != null else Vector2i(3, 6)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var made := 0
	var director := w.get_tree().get_first_node_in_group("creature_battles") as CreatureBattles
	var side := Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
	var was := SpawnQueue.defer
	SpawnQueue.defer = true  # they join a few per frame
	for g in 2:
		var faction := a if g == 0 else b
		var kinds := members_of(faction)
		if kinds.is_empty():
			continue
		var centre := at + side * (4.5 if g == 0 else -4.5)
		for i in rng.randi_range(2, 4):
			var data := load("res://data/%s/%s.tres" % ["npcs" if faction in ["town", "livestock"] else "enemies", kinds[rng.randi() % kinds.size()]]) as EnemyData
			if data == null:
				continue
			var pos := centre + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
			pos.y = w.get_height_at(pos.x, pos.z) + 0.6
			var e := Population.spawn_enemy(data, rng.randi_range(zone.x, zone.y), w, pos, rng, {"persist_mode": Enemy.PersistMode.NEVER})
			e.faction = faction
			if faction == "town":
				e.set_meta("guard", true)  # a patrol: they fight, they don't run
			e.set_meta("battle", true)
			e.detection_range = maxf(e.detection_range, 16.0)  # they see the other side straight away
			if director != null:
				director._alive.append(e)
			made += 1
	SpawnQueue.defer = was
	return "A battle: %s against %s (%d) at %d, %d." % [CreatureFactions.display_name(a), CreatureFactions.display_name(b), made, roundi(at.x), roundi(at.z)]


## The enemy kinds (data ids) of a faction that have a data file
static func members_of(faction: String) -> Array:
	CreatureFactions.all()  # loads the table
	var out: Array = []
	for id in CreatureFactions._members:
		if String(CreatureFactions._members[id]) != faction:
			continue
		var sub := "npcs" if faction in ["town", "livestock"] else "enemies"
		if ResourceLoader.exists("res://data/%s/%s.tres" % [sub, id]) and not String(id) in ["dragon", "crawler_queen", "wight_lord", "smuggler_chief", "deserter_captain", "merchant"]:
			out.append(id)
	return out


func _pick_pair() -> Array:
	var total := 0
	for pr in PAIRS:
		total += int(pr[2])
	var roll := randi() % total
	for pr in PAIRS:
		roll -= int(pr[2])
		if roll < 0:
			return pr
	return PAIRS[0]


# Two places near you held by sides at war: the fight is halfway between them
func _border(from: Vector3) -> Dictionary:
	var held: Array = []  # [pos, faction]
	for poi in world.pois:
		if Vector2(poi.position.x - from.x, poi.position.z - from.z).length() > 500.0:
			continue
		for e in world.get_garrison(poi.id):
			if is_instance_valid(e) and not (e as Enemy).is_dead():
				held.append([poi.position, CreatureFactions.of(e)])
				break
	held.shuffle()
	for i in held.size():
		for j in range(i + 1, held.size()):
			var d: float = (held[i][0] as Vector3).distance_to(held[j][0])
			if d > 60.0 and d < 500.0 and CreatureFactions.relation(held[i][1], held[j][1]) == CreatureFactions.Rel.HOSTILE:
				var mid: Vector3 = ((held[i][0] as Vector3) + (held[j][0] as Vector3)) * 0.5
				if Vector2(mid.x - from.x, mid.z - from.z).length() > 60.0:
					return {"at": mid, "a": held[i][1], "b": held[j][1]}
	return {}


func _near_town(pos: Vector3) -> bool:
	for t in world.towns:
		if Vector2(t.position.x - pos.x, t.position.z - pos.z).length() < 220.0:
			return true
	return false


func _clean_up() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var keep: Array = []
	for e in _alive:
		if not is_instance_valid(e):
			continue
		if p != null and (e as Node3D).is_inside_tree() and (e as Node3D).global_position.distance_to(p.global_position) > GONE:
			(e as Node).queue_free()
			continue
		if not (e as Enemy).is_dead():
			keep.append(e)
	_alive = keep
