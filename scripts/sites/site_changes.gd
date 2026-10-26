class_name SiteChanges
extends RefCounted
## Outdoor places change hands over time (Alpha 1.14), worked out once a day:
##   new owners   a cleared camp, fort, tower or ruin gets new occupants NEW_OWNERS_DAYS after it was
##                cleared (another kind of place's folk: deserters in a bandit camp, ghouls in a fort);
##                its dead are forgotten and it is no longer cleared
##   taken        now and then bandits take a farm, a mill or a lumber camp that had nobody to fight
## Folk talk about both (Rumors). Saved as "site_owners/<place id>" {"table", "boss", "day", "why"};
## SitePOIData asks occupants() what lives at a place now.

const NEW_OWNERS_DAYS := 21
## The chance a day that bandits take a peaceful place somewhere
const TAKE_CHANCE := 0.08
const TAKEABLE := ["farmstead", "mill", "lumber_camp", "hunters_camp", "dock", "ferry", "quarry"]
const NEWCOMERS := [
	["res://data/spawns/garrison_camp.tres", "res://data/enemies/bandit_brute.tres"],
	["res://data/spawns/dungeon_fort.tres", "res://data/enemies/deserter_captain.tres"],
	["res://data/spawns/enc_dead_ghouls.tres", "res://data/enemies/grave_ghoul.tres"],
	["res://data/spawns/enc_coast_raiders.tres", "res://data/enemies/raider_marauder.tres"],
	["res://data/spawns/enc_wolves.tres", "res://data/enemies/cave_troll.tres"],
]


## Who lives at a place now: [SpawnTable, boss EnemyData] (its own when nothing changed)
static func occupants(d: SitePOIData, placed: PlacedPOI, own_boss: EnemyData) -> Array:
	var rec := WorldState.get_record("site_owners/" + placed.id)
	if rec.is_empty():
		return [d.occupants, own_boss]
	var table := load(String(rec["table"])) as SpawnTable if ResourceLoader.exists(String(rec.get("table", ""))) else d.occupants
	var boss := load(String(rec["boss"])) as EnemyData if ResourceLoader.exists(String(rec.get("boss", ""))) else own_boss
	return [table, boss]


static func daily(world: WorldManager, day: int) -> void:
	if world == null or int(WorldState.get_record("site_changes").get("day", -1)) >= day:
		return
	WorldState.set_record("site_changes", {"day": day})
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|sites|%d" % [world.world_seed, day]).hash()
	var peaceful: Array[PlacedPOI] = []
	for p: PlacedPOI in world.pois:
		var d := p.poi as SitePOIData
		if d == null:
			continue
		var found := WorldState.get_record("found/" + p.id)
		if bool(found.get("cleared", false)) and day - int(found.get("cleared_day", day)) >= NEW_OWNERS_DAYS:
			_new_owners(world, p, day, rng, "new")
		elif d.occupants == null and TAKEABLE.has(String(d.get_key()).trim_prefix("site_")) and not WorldState.has_record("site_owners/" + p.id):
			peaceful.append(p)
	if not peaceful.is_empty() and rng.randf() < TAKE_CHANCE:
		_new_owners(world, peaceful[rng.randi_range(0, peaceful.size() - 1)], day, rng, "taken")


static func _new_owners(world: WorldManager, p: PlacedPOI, day: int, rng: RandomNumberGenerator, why: String) -> void:
	var pick: Array = NEWCOMERS[0] if why == "taken" else NEWCOMERS[rng.randi_range(0, NEWCOMERS.size() - 1)]
	WorldState.set_record("site_owners/" + p.id, {"table": pick[0], "boss": pick[1], "day": day, "why": why})
	# the old dead are forgotten, and it is not cleared any more
	var keys: Array = []
	for k: String in WorldState.records:
		if k.begins_with("kill/%s/" % p.id) or k == "kill/dungeon/%s/boss" % p.id or k == "kill/dungeon/%s/site/boss" % p.id:
			keys.append(k)
	for k in keys:
		WorldState.erase_record(k)
	var found := WorldState.get_record("found/" + p.id)
	if not found.is_empty():
		found.erase("cleared")
		found.erase("cleared_day")
		WorldState.set_record("found/" + p.id, found)
	var name := Discovery.place_name(world, p)
	var text := "Bandits have taken the %s. The folk who worked it fled." % name if why == "taken" else "Someone new has moved into the %s. Best go armed." % name
	Rumors.add("trouble", text, p.position, day, p.id)
