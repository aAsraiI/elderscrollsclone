class_name Discovery
extends Node
## Places you have found, and fast travel between them. Created by WorldManager.
##
## Walking close to a town or a place marks it found (saved in WorldState as "found/<id>"):
## a banner says so, it shows on the map with its name and level, and you get a little player
## XP for it (a deed, see Skills.add_deed_xp). Dungeons whose boss is dead are marked "cleared".
##
## Fast travel: click a found place on the map (M). Time passes by the distance (walking speed),
## and you arrive at its edge. Not possible inside a dungeon or building, while dead, or with
## hostile enemies close by.

signal discovered(poi: PlacedPOI)
signal travelled(poi: PlacedPOI, hours: float)

## How close you have to get, on top of the place's own size
const FIND_RADIUS := 45.0
## Walking speed used to work out how many hours a trip takes (m/s)
const TRAVEL_SPEED := 4.0
## No fast travel with a hostile enemy this close
const DANGER_RADIUS := 40.0

var _manager: WorldManager
var _timer := 0.0


func _ready() -> void:
	add_to_group("discovery")
	_manager = get_parent() as WorldManager


static func is_found(poi_id: String) -> bool:
	return WorldState.has_record("found/" + poi_id)


## The boss of this dungeon entrance is dead (set by the dungeon when it dies)
static func is_cleared(poi_id: String) -> bool:
	return bool(WorldState.get_record("found/" + poi_id).get("cleared", false))


static func mark_cleared(poi_id: String) -> void:
	var rec := WorldState.get_record("found/" + poi_id)
	if not bool(rec.get("cleared", false)):
		DialogueState.system_entry("Place", "Cleared: %s." % _name_of(poi_id), "")
	rec["cleared"] = true
	WorldState.set_record("found/" + poi_id, rec)


## Marks a place found (the first time only). Returns true if it was new.
func mark_found(poi: PlacedPOI) -> bool:
	if poi == null or is_found(poi.id):
		return false
	WorldState.set_record("found/" + poi.id, {"cleared": false})
	var p := _manager.player if _manager != null else null
	if p != null and is_instance_valid(p):
		var skills := p.get_node_or_null("Skills") as Skills
		if skills != null:
			var lvl := LevelCurve.place_level(_manager.map, poi.position)
			skills.add_deed_xp(SkillDatabase.deed_xp(lvl, 1.0))
		var hud := p.get_node_or_null("CompassHUD") as CompassHUD
		if hud != null and poi.town == null:
			hud.show_banner("Discovered: %s" % place_name(_manager, poi), "Level %d" % LevelCurve.place_level(_manager.map, poi.position))
	QuestEvents.discover(get_tree(), poi.id)
	DialogueState.system_entry("Place", "Discovered: %s." % place_name(_manager, poi), "")
	discovered.emit(poi)
	return true


## A place's name the way people say it (towns by their own name)
static func place_name(world: WorldManager, poi: PlacedPOI) -> String:
	if poi.town != null:
		return poi.town.display_name
	var n := DialogueEngine.poi_topic_name(world, poi)
	return n if n != "" else poi.poi.display_name


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _manager == null or _manager.player == null or not is_instance_valid(_manager.player):
		return
	_timer = 0.5
	if _manager.dungeons != null and _manager.dungeons.is_inside():
		return
	var at := _manager.player.global_position
	for poi in _manager.pois:
		var reach := FIND_RADIUS + poi.poi.footprint_radius
		if absf(poi.position.x - at.x) > reach or absf(poi.position.z - at.z) > reach:
			continue
		if Vector2(poi.position.x - at.x, poi.position.z - at.z).length() <= reach:
			mark_found(poi)


# ---------------------------------------------------------------- fast travel

## "" if you can travel to this place now, else why not
func can_travel_to(poi: PlacedPOI) -> String:
	if poi == null or not is_found(poi.id):
		return "You have not found that place yet."
	var p := _manager.player
	if p == null or not is_instance_valid(p):
		return "There is no one to travel."
	var stats := p.get_node_or_null("Stats") as Stats
	if stats != null and stats.is_dead:
		return "You are dead."
	if _manager.dungeons != null and _manager.dungeons.is_inside():
		return "You can't fast travel from inside."
	if not bool(GameRules.get_rule("fast_travel")):
		return "Fast travel is off in this world. Take a carriage from a city gate, or ride."
	if p.has_meta("beast_form"):
		return "The beast can't travel."
	for e in ActorRegistry.near(p.global_position, DANGER_RADIUS):
		var en := e as Enemy
		if en != null and is_instance_valid(en) and not en.is_dead() and en.disposition == Enemy.Disposition.HOSTILE and en.global_position.distance_to(p.global_position) < DANGER_RADIUS:
			return "You can't fast travel with enemies nearby."
	return ""


## Hours a trip from where you are to this place takes
func travel_hours(poi: PlacedPOI) -> float:
	var p := _manager.player
	var d := Vector2(poi.position.x - p.global_position.x, poi.position.z - p.global_position.z).length()
	return d / TRAVEL_SPEED / 3600.0


## Goes there. Returns "" on success, else why not.
func travel_to(poi: PlacedPOI) -> String:
	var why := can_travel_to(poi)
	if why != "":
		return why
	var p := _manager.player
	var hours := travel_hours(poi)
	# arrive at the edge, on the side you came from, facing the place
	var from := Vector2(p.global_position.x - poi.position.x, p.global_position.z - poi.position.z)
	var dir := from.normalized() if from.length() > 1.0 else Vector2(0, 1)
	var spot := Vector2(poi.position.x, poi.position.z) + dir * (poi.poi.footprint_radius + 12.0)
	var pos := Vector3(spot.x, 0.0, spot.y)
	_manager.ensure_area_loaded(pos, 1)
	pos.y = _manager.get_height_at(spot.x, spot.y) + 1.2
	p.global_position = pos
	p.look_at(Vector3(poi.position.x, pos.y, poi.position.z), Vector3.UP)
	p.rotation.x = 0.0
	p.rotation.z = 0.0
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	var clock := _manager.clock
	if clock != null:
		clock.advance_hours(hours)
	travelled.emit(poi, hours)
	return ""


# A place's name from its id (for the journal), without a node at hand
static func _name_of(poi_id: String) -> String:
	var w := (Engine.get_main_loop() as SceneTree).get_first_node_in_group("world_manager") as WorldManager
	var p := w.get_poi(poi_id) if w != null else null
	return place_name(w, p) if p != null else poi_id
