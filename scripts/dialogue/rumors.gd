class_name Rumors
extends RefCounted
## Rumors about things that really happened: a dungeon cleared, a townsperson murdered, a bandit
## chief killed, a guild's work done, trouble brewing at a camp. Each starts where it happened and
## spreads SPREAD meters a day (up to MAX_REACH), so a town far away hears of it days later.
## People's "latest rumors" answer with the news they have heard; trouble rumors seed bounties
## (a town's bounty board sends you after the camp everyone talks about).
## Saved in WorldState "rumors".

const KEY := "rumors"
const MAX := 60
const SPREAD := 700.0
const MAX_REACH := 5000.0
## Chance a day that trouble starts brewing at a camp somewhere
const TROUBLE_CHANCE := 0.35


static func all() -> Array:
	return WorldState.get_record(KEY).get("list", [])


## A new rumor, starting at a place in the world on a day
static func add(kind: String, text: String, at: Vector3, day: int, poi_id: String = "") -> void:
	var list := all().duplicate(true)
	for r: Dictionary in list:
		if r["text"] == text:
			return
	list.append({"kind": kind, "text": text, "x": at.x, "z": at.z, "day": day, "poi": poi_id})
	while list.size() > MAX:
		list.pop_front()
	WorldState.set_record(KEY, {"list": list, "last_day": int(WorldState.get_record(KEY).get("last_day", day))})


## The rumors that have reached a spot by a day, newest first
static func heard_at(at: Vector3, day: int) -> Array:
	var out: Array = []
	for r: Dictionary in all():
		var reach := minf((day - int(r["day"]) + 1) * SPREAD, MAX_REACH)
		if Vector2(float(r["x"]) - at.x, float(r["z"]) - at.z).length() <= reach:
			out.append(r)
	out.reverse()
	return out


## A camp a town is worried about ("" = none): the bounty board's next target
static func trouble_near(at: Vector3, day: int) -> String:
	for r: Dictionary in heard_at(at, day):
		if r["kind"] == "trouble" and String(r.get("poi", "")) != "" and not Discovery.is_cleared(String(r["poi"])):
			return String(r["poi"])
	return ""


## Once a day (QuestManager): sometimes trouble starts at a camp near a town
static func daily(world: WorldManager, day: int) -> void:
	var rec := WorldState.get_record(KEY)
	if int(rec.get("last_day", 0)) >= day:
		return
	WorldState.set_record(KEY, {"list": all(), "last_day": day})
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|rumor|%d" % [world.world_seed, day]).hash()
	if world.towns.is_empty() or rng.randf() > TROUBLE_CHANCE:
		return
	var town: PlacedPOI = world.towns[rng.randi_range(0, world.towns.size() - 1)]
	var camp := QuestTargets.nearest_poi(world, town.position + Vector3(rng.randf_range(-800, 800), 0, rng.randf_range(-800, 800)), false)
	if camp == null or Discovery.is_cleared(camp.id):
		return
	var where := Discovery.place_name(world, camp)
	add("trouble", ["Raiders from the %s hit a farm near %s two nights ago." % [where, town.town.display_name],
		"Folk say the %s is crawling with cutthroats again." % where,
		"Merchants won't take the road past the %s any more. Too many go missing." % where][rng.randi_range(0, 2)], camp.position, day, camp.id)


# ---------------------------------------------------------------- what makes rumors

static func _day() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var clock := tree.get_first_node_in_group("world_clock") as WorldClock if tree != null else null
	return clock.day if clock != null else 1


static func _world() -> WorldManager:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("world_manager") as WorldManager if tree != null else null


static func on_cleared(poi_id: String) -> void:
	var w := _world()
	var p := w.get_poi(poi_id) if w != null else null
	if p != null:
		add("deed", "Someone went down into the %s and came back out. The thing that lived there didn't." % Discovery.place_name(w, p), p.position, _day(), poi_id)


static func on_murder(name: String, town: PlacedPOI) -> void:
	if town != null and town.town != null:
		add("murder", "Did you hear? %s was found dead in %s. The guards have no idea who did it." % [name, town.town.display_name], town.position, _day())


static func on_job_done(q: Dictionary) -> void:
	var w := _world()
	if w == null or not q.has("pos"):
		return
	var at := Vector3(float(q["pos"][0]), 0.0, float(q["pos"][1]))
	match String(q.get("type", "")):
		"kill", "hunt":
			add("deed", "They say %s is dead. Somebody finally did something about it." % q.get("chief", "the bandit chief"), at, _day())
		"rescue":
			add("deed", "%s came home! Taken by bandits, and someone brought them back." % q.get("target_name", "A captive"), at, _day())
		"protect", "road":
			add("deed", "Raiders tried their luck near %s. They won't try again." % q.get("town_name", "town"), at, _day())
	if Factions.get_data(String(q.get("faction", ""))) != null and String(q.get("type", "")) in ["kill", "hunt", "retrieve"]:
		add("guild", "The %s is doing well for itself. New blood, they say." % Factions.display_name(String(q["faction"])), at, _day())
