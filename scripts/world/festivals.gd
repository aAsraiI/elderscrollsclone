class_name Festivals
extends Node
## The festival calendar (lore bible): one festival a month, held for FESTIVAL_DAYS days from
## FIRST_DAY. While one is on, the towns that keep it hang banners and lanterns around their plaza,
## a festival stall sells food and drink there, the town's name banner says what is on, the date
## shows it, and some change what walks the roads (no vampires on the Day of the Dawn, wolves
## everywhere under the Blood Moon). Created by WorldManager; decorations only exist while it is on.

const FIRST_DAY := 8
const FESTIVAL_DAYS := 5
const DECOR := "FestivalDecor"

## month -> [name, where it is kept, what happens, banner colour]. "where" is biome keys, town names,
## "cities" or "all".
const LIST := {
	0: ["The Long Night", ["snow_mountains", "tundra", "frozen_crown"], "Bonfires and sagas in every longhall; the Winter Queen's call is strongest.", Color(0.35, 0.55, 0.85)],
	1: ["Feast of the Thaw", ["lakeland"], "Boats return to the lakes; the Merewater Regatta.", Color(0.4, 0.75, 0.8)],
	2: ["Feast of Seedfall", ["Kingsreach"], "The court feast, where every great house sends envoys.", Color(0.85, 0.7, 0.25)],
	3: ["Tide Blessing", ["coast"], "Ships blessed by Oshra's priests; pirates raid more.", Color(0.2, 0.5, 0.7)],
	4: ["Green Hunt", ["forest"], "The Earl's hunt; Woodborn dances.", Color(0.35, 0.65, 0.3)],
	5: ["The Highland Games", ["highlands"], "Games at Cragmoor.", Color(0.6, 0.3, 0.25)],
	6: ["Day of the Dawn", ["desert", "Kingsreach"], "Sun festival; vampires stay hidden; the Sunhold Tournament.", Color(0.95, 0.75, 0.3)],
	7: ["Hearth Feast", ["plains"], "Harvest fairs, the Wheatley scarecrow festival, the horse fair at Harrowford.", Color(0.8, 0.5, 0.2)],
	8: ["Night of Masks", ["cities"], "Masked balls; the Velvet Court's favourite night.", Color(0.55, 0.2, 0.5)],
	9: ["Feast of the Dead", ["all"], "Graves cleaned, ghosts walk; Vey's ferry runs.", Color(0.5, 0.5, 0.55)],
	10: ["The Blood Moon", ["forest", "highlands"], "The Hunter's Moon rises red; werewolves are strongest.", Color(0.65, 0.12, 0.1)],
	11: ["The Penance Walk", ["ashlands"], "The Archon's barefoot walk.", Color(0.4, 0.35, 0.3)],
}

var world: WorldManager
var _timer := 0.0
var _decorated := {}  # town id -> stall keeper (Enemy)


func _ready() -> void:
	world = get_parent() as WorldManager


## The festival on today, as {"month", "name", "where", "text", "color"}, or {} if none
static func current(clock: WorldClock) -> Dictionary:
	if clock == null:
		return {}
	var d := clock.get_day_of_month()
	if d < FIRST_DAY or d >= FIRST_DAY + FESTIVAL_DAYS:
		return {}
	var m := clock.get_month()
	var f: Array = LIST[m]
	return {"month": m, "name": f[0], "where": f[1], "text": f[2], "color": f[3]}


## Does this town keep the festival?
static func keeps(festival: Dictionary, world_manager: WorldManager, town: PlacedPOI) -> bool:
	if festival.is_empty() or town == null or town.town == null:
		return false
	var where: Array = festival["where"]
	if where.has("all") or where.has(town.town.display_name):
		return true
	if where.has("cities") and (town.poi as TownData).kind == TownData.Kind.CITY:
		return true
	var biome := world_manager.get_biome_at(town.position.x, town.position.z)
	return biome != null and where.has(biome.get_key())


## How likely an encounter is today (EncounterManager): some festivals change what walks at night
static func encounter_factor(clock: WorldClock, encounter_key: String) -> float:
	var f := current(clock)
	if f.is_empty():
		return 1.0
	match String(f["name"]):
		"Day of the Dawn":
			return 0.0 if encounter_key.contains("vampire") else 1.0
		"The Blood Moon":
			return 3.0 if encounter_key.contains("werewolf") else 1.0
	return 1.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 4.0
	if world == null or world.clock == null:
		return
	var f := current(world.clock)
	_announce(f)
	for t in world.towns:
		var node := world.get_poi_node(t.id)
		var on := node != null and keeps(f, world, t)
		var has := node != null and node.get_node_or_null(DECOR) != null
		if on and not has:
			_decorate(t, node, f)
		elif not on and _decorated.has(t.id):
			_undecorate(t.id, node)


# A toast on the first day a festival is noticed
func _announce(f: Dictionary) -> void:
	if f.is_empty():
		return
	var key := "%d|%d" % [world.clock.get_year(), int(f["month"])]
	if String(WorldState.get_record("festival_seen").get("key", "")) == key:
		return
	WorldState.set_record("festival_seen", {"key": key})
	Locks.toast(get_tree(), "%s has begun. %s" % [f["name"], f["text"]])


# Banners on poles around the plaza, a few lanterns, and the festival stall
func _decorate(t: PlacedPOI, node: Node3D, f: Dictionary) -> void:
	var decor := Node3D.new()
	decor.name = DECOR
	node.add_child(decor)
	var col: Color = f["color"]
	var rng := RandomNumberGenerator.new()
	rng.seed = t.id.hash()
	var radius := 9.0
	# the town's own dressing spots near the square, when it has them (Alpha 1.14): the banners go up
	# beside its lamps, benches and trees, and the festival stall takes a market stall's place
	var spots: Array[Vector3] = []
	var stall_spot := Vector3.INF
	if t.town != null and not t.town.dress.is_empty():
		var near := t.town.dress.duplicate()
		near.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return Vector3(x["pos"]).length() < Vector3(y["pos"]).length())
		for d: Dictionary in near:
			if String(d["what"]) == "stall" and stall_spot == Vector3.INF:
				stall_spot = Vector3(d["pos"]) + Vector3(0, 0, 2.0)
			elif String(d["what"]) in ["lamp", "bench", "tree", "flowers", "banner"] and spots.size() < 8:
				spots.append(Vector3(d["pos"]) + Vector3(0.8, 0, 0))
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var at := spots[i] if i < spots.size() else Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		at.y = POIBuilder.ground_y(t, world.map, at.x, at.z)
		POIBuilder.add_box(decor, Vector3(0.12, 3.4, 0.12), at + Vector3(0, 1.7, 0), Color(0.35, 0.25, 0.15), 0.0, Vector3.ZERO, false)
		POIBuilder.add_box(decor, Vector3(0.7, 1.4, 0.04), at + Vector3(0.36, 2.6, 0), col.darkened(0.15 * (i % 2)), -a, Vector3.ZERO, false)
		if i % 2 == 0:
			POIBuilder.add_box(decor, Vector3(0.22, 0.28, 0.22), at + Vector3(0, 3.5, 0), Color(1.0, 0.8, 0.45), 0.0, Vector3.ZERO, false, true)
	# The stall: a table under an awning, and its keeper
	var stall_at := Vector3(4.5, 0.0, -4.5) if stall_spot == Vector3.INF else stall_spot
	stall_at.y = POIBuilder.ground_y(t, world.map, stall_at.x, stall_at.z)
	POIBuilder.add_box(decor, Vector3(2.2, 0.9, 0.9), stall_at + Vector3(0, 0.45, 0), Color(0.45, 0.32, 0.2))
	POIBuilder.add_box(decor, Vector3(2.6, 0.08, 1.6), stall_at + Vector3(0, 2.3, 0.3), col, 0.0, Vector3.ZERO, false)
	var keeper := _stall_keeper(t, node.global_transform * (stall_at + Vector3(0, 0.6, 1.0)), f)
	if keeper != null:
		_decorated[t.id] = keeper
	else:
		_decorated[t.id] = null


func _stall_keeper(t: PlacedPOI, at: Vector3, f: Dictionary) -> Enemy:
	var body := load(RoadLife.FOLK_BODY) as EnemyData
	if body == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|festival|%d" % [t.id, int(f["month"])]).hash()
	var e := Enemy.create()
	body.apply(e, LevelCurve.zone_range(world.map, at).x, rng)
	e.persist_mode = Enemy.PersistMode.NEVER
	e.wander_radius = 0.0
	var who := NameGen.person(rng)
	e.display_name = "%s, Festival Stall" % NameGen.first_name(who)
	e.talk_name = e.display_name
	e.talk_lines = PackedStringArray(["Happy %s! Something to eat? Something to drink?" % f["name"], "Only for the festival days, friend. Then I'm back on the road."])
	e.placeholder_color = Color(f["color"]).darkened(0.2)
	e.set_meta("merchant", "festival")
	e.set_meta("shop_id", "festival/%s" % t.id)
	world.add_child(e)
	e.global_position = at
	return e


func _undecorate(id: String, node: Node3D) -> void:
	if node != null:
		var d := node.get_node_or_null(DECOR)
		if d != null:
			d.queue_free()
	var keeper: Variant = _decorated.get(id)
	if keeper != null and is_instance_valid(keeper):
		(keeper as Node).queue_free()
	_decorated.erase(id)
