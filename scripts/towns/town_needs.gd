class_name TownNeeds
extends RefCounted
## Alpha 1.24: how a town is doing, worked out once a day (TownSociety) and kept in WorldState
## "town_needs/<town id>" {food, safety, wealth, day}, each 0-100:
##   food    the season (lean in winter, plenty after harvest) and, now and then, a failed harvest
##   safety  hostile places near the town (camps, crypts, dens) still held; cleared ones help
##   wealth  what the town thinks of you, and its size
## A hungry town asks more for food and drink (Economy) and has beggars; an unsafe one talks of it.

const RECORD := "town_needs/"
const HUNGRY := 35
const UNSAFE := 40

static func get_needs(town_id: String) -> Dictionary:
	return WorldState.get_record(RECORD + town_id)


static func food(town_id: String) -> int:
	return int(get_needs(town_id).get("food", 60))


static func safety(town_id: String) -> int:
	return int(get_needs(town_id).get("safety", 60))


## Food and drink cost more in a hungry town, a little less in a well-fed one
static func food_price(town_id: String) -> float:
	if not WorldState.has_record(RECORD + town_id):
		return 1.0
	return clampf(1.0 + float(55 - food(town_id)) / 100.0, 0.9, 1.45)


static func is_hungry(town_id: String) -> bool:
	return WorldState.has_record(RECORD + town_id) and food(town_id) < HUNGRY


## Works out a town's needs for today. Returns the new record.
static func update(world: WorldManager, t: PlacedPOI, day: int) -> Dictionary:
	var before := get_needs(t.id)
	var season := world.clock.get_season() if world.clock != null else 1
	var year := (day - 1) / WorldClock.DAYS_PER_YEAR if world.clock != null else 0
	var f: int = 60 + int([-15, -5, 5, 15][season])
	# a failed harvest: decided once a season per town (the same in every game)
	var failed := absi(("%s|harvest|%d|%d" % [t.id, year, season]).hash()) % 100 < 12 and season in [2, 3]
	if failed:
		f -= 35
	var s := 75
	for p in world.pois:
		if p.poi is TownData or p.poi.garrison == null:
			continue
		var d := Vector2(p.position.x - t.position.x, p.position.z - t.position.z).length()
		if d > 650.0:
			continue
		s += 6 if Discovery.is_cleared(p.id) else -8
	s -= Chaos.safety_cost()  # 1.24: the killings frighten everyone
	var name := t.town.display_name if t.town != null else ""
	var w := 50 + clampi(Reputation.get_rep(name) / 4, -20, 25) + (10 if (t.poi as TownData).kind == TownData.Kind.CITY else 0)
	var out := {"food": clampi(f, 0, 100), "safety": clampi(s, 0, 100), "wealth": clampi(w, 0, 100), "day": day, "failed": failed}
	WorldState.set_record(RECORD + t.id, out)
	if failed and not bool(before.get("failed", false)) and name != "":
		Rumors.add("harvest", "The harvest failed around %s. Bread costs twice what it did, and there are beggars in the streets." % name, t.position, day)
	return out


## A remark about how the town is doing ("" = nothing to say)
static func remark(town_id: String, k: int) -> String:
	if not WorldState.has_record(RECORD + town_id):
		return ""
	if is_hungry(town_id):
		return ["Spare a coin? The harvest failed.", "Bread at these prices... we'll starve before spring.", "My children haven't eaten today."][k % 3]
	if safety(town_id) < UNSAFE:
		return ["Bandits on every road. Nobody travels alone any more.", "Bar your door at night. Things are bad out there.", "The guard can't be everywhere."][k % 3]
	if food(town_id) > 75:
		return ["Good harvest this year. Thank the gods.", "Full barns, full bellies."][k % 2]
	return ""
