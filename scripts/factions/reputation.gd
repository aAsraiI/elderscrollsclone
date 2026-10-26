class_name Reputation
extends RefCounted
## How the world sees the player: reputation with each guild (it grows with work done for them),
## and fame and infamy in each town (good deeds, and crimes). Saved in WorldState "rep/<key>".
##   guild reputation   jobs, quests; drops on abandoning their work or being expelled
##   town fame          quests done for its people
##   town infamy        crimes seen there
## Reputation (fame minus infamy for towns) changes prices (Barter), what people will say to you
## (disposition, see DialogueEngine) and how guards greet you.

const KEY := "rep/"


static func get_rep(key: String) -> int:
	if Factions.get_data(key) != null:
		return int(WorldState.get_record(KEY + key).get("v", 0))
	return fame(key) - infamy(key)


static func add(key: String, amount: int) -> void:
	if key == "" or amount == 0:
		return
	var rec := WorldState.get_record(KEY + key)
	WorldState.set_record(KEY + key, {"v": int(rec.get("v", 0)) + amount})


static func fame(town: String) -> int:
	return int(WorldState.get_record("fame/" + town).get("v", 0))


static func infamy(town: String) -> int:
	return int(WorldState.get_record("infamy/" + town).get("v", 0))


static func add_fame(town: String, amount: int) -> void:
	if town != "":
		WorldState.set_record("fame/" + town, {"v": fame(town) + amount})


static func add_infamy(town: String, amount: int) -> void:
	if town != "":
		WorldState.set_record("infamy/" + town, {"v": infamy(town) + amount})


## A word for it: "unknown", "liked", "respected", "a hero" / "distrusted", "feared"
static func word(value: int) -> String:
	if value >= 60: return "a hero"
	if value >= 30: return "respected"
	if value >= 10: return "liked"
	if value <= -30: return "feared"
	if value <= -10: return "distrusted"
	return "unknown"


## Disposition bonus from what a person's town and guild think of you (-15..+15)
static func disposition_bonus(town_name: String, guild: String) -> int:
	var v := get_rep(town_name) if town_name != "" else 0
	if guild != "" and Factions.get_data(guild) != null:
		v += get_rep(guild)
	return clampi(v / 4, -15, 15)


## Price factor from a town's opinion: 0.9 for a hero, 1.1 when feared
static func price_factor(town_name: String) -> float:
	return clampf(1.0 - float(get_rep(town_name)) / 600.0, 0.9, 1.1)
