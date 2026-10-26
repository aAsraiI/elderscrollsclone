class_name Services
extends RefCounted
## The service buttons of a conversation, in one place. Each one says which profiles may show it
## (DialogueProfile.services) and when it works; the dialogue window shows the allowed ones and
## greys out those that can't be used right now, with the reason.
##   Barter     merchants (their shop must be open)        Train    trainers (skills, gold, caps)
##   Rent Room  innkeepers (a night's bed)                  Duties   guild officers
##   Travel     innkeepers of towns with a carriage         Repair   smiths (the forge, for a fee)
##   Enchant    Mages Guild officers (the enchanting table)

const LIST := [
	{"id": "trade", "label": "Barter"},
	{"id": "train", "label": "Train"},
	{"id": "rent", "label": "Rent Room"},
	{"id": "duties", "label": "Duties"},
	{"id": "travel", "label": "Travel"},
	{"id": "repair", "label": "Repair"},
	{"id": "enchant", "label": "Enchant"},
]
## Trainings allowed per player level (all skills together)
const TRAININGS_PER_LEVEL := 5
const REPAIR_FEE := 25
const ENCHANT_FEE := 50
## What guild officers train, by guild
const GUILD_TRAINS := {
	"fighters": ["one_handed", "two_handed", "block"], "mages": ["destruction", "restoration", "alteration", "conjuration"],
	"knights": ["heavy_armor", "block", "one_handed"], "thieves": ["sneak", "security"], "assassins": ["sneak", "archery"],
}


## The buttons this person shows: [{"id", "label", "why" ("" = usable)}]
static func for_speaker(s: DialogueEngine.Speaker, world: WorldManager, player: Node) -> Array:
	var out: Array = []
	if s == null:
		return out
	var prof := DialogueEngine.profile_for(s, world)
	var trade := Barter.trade_status(s, world)
	for sv: Dictionary in LIST:
		var id := String(sv["id"])
		var allowed := prof.services.has(id)
		if id == "trade":
			allowed = trade["merchant"] != null  # anyone who keeps a shop (and travelling merchants)
		if id == "train":
			allowed = allowed and not trains(s, world).is_empty()
		if id == "enchant":
			allowed = allowed and Factions.leader_of(s, world) == "mages"
		if id == "travel":
			allowed = allowed and _carriage(s, world) != null
		if not allowed:
			continue
		out.append({"id": id, "label": sv["label"], "why": why_not(id, s, world, player, trade)})
	return out


## Why a service can't be used now ("" = it can)
static func why_not(id: String, s: DialogueEngine.Speaker, world: WorldManager, player: Node, trade: Dictionary = {}) -> String:
	var inv := player.get_node_or_null("Inventory") as Inventory if player != null else null
	if s.asleep:
		return "asleep"
	match id:
		"trade":
			if trade.is_empty():
				trade = Barter.trade_status(s, world)
			return "" if trade["open"] else String(trade["why"])
		"train":
			if trainings_left(player) <= 0:
				return "trained enough this level"
		"rent":
			if inv != null and Currency.get_gold(inv) < RestSpot.INN_PRICE:
				return "%d gold" % RestSpot.INN_PRICE
		"duties":
			var leader := Factions.leader_of(s, world)
			if not Factions.is_member(leader):
				return "members only"
		"repair":
			if inv != null and Currency.get_gold(inv) < REPAIR_FEE:
				return "%d gold" % REPAIR_FEE
		"enchant":
			if not Factions.is_member("mages"):
				return "members only"
			if inv != null and Currency.get_gold(inv) < ENCHANT_FEE:
				return "%d gold" % ENCHANT_FEE
	return ""


# ---------------------------------------------------------------- training

## The skills this person trains, and how far: {"skills": [...], "max": level}
static func trains(s: DialogueEngine.Speaker, world: WorldManager) -> Array:
	var prof := DialogueEngine.profile_for(s, world)
	var list: Array = Array(prof.trains)
	if s.role == NpcData.Role.GUILD_MEMBER:
		list.append_array(GUILD_TRAINS.get(s.faction, []))
	var out: Array = []
	for k in list:
		if not out.has(k) and SkillDatabase.get_skill(StringName(k)) != null:
			out.append(k)
	return out


static func train_max(s: DialogueEngine.Speaker, world: WorldManager) -> int:
	var m := DialogueEngine.profile_for(s, world).train_max
	if s.role == NpcData.Role.GUILD_MEMBER:
		m = maxi(m, 40 + 10 * Factions.rank(s.faction))  # a guild trains its own further
	return m


## The gold one level costs: grows with the level (10 + level squared / 4), less for guild members
static func train_cost(skill_level: int, s: DialogueEngine.Speaker) -> int:
	var cost := 10 + (skill_level * skill_level) / 4
	if s.faction != "" and Factions.is_member(s.faction):
		cost = roundi(cost * 0.8)
	return cost


static func trainings_left(player: Node) -> int:
	var sk := player.get_node_or_null("Skills") as Skills if player != null else null
	if sk == null:
		return 0
	var rec := WorldState.get_record("training")
	if int(rec.get("level", -1)) != sk.get_player_level():
		return TRAININGS_PER_LEVEL
	return TRAININGS_PER_LEVEL - int(rec.get("n", 0))


## One level of a skill for gold. Returns what happened, for the dialogue.
static func train(skill: String, s: DialogueEngine.Speaker, world: WorldManager, player: Node) -> String:
	var sk := player.get_node("Skills") as Skills
	var inv := player.get_node("Inventory") as Inventory
	var lvl := sk.get_level(StringName(skill))
	if lvl >= train_max(s, world):
		return "I can't teach you any more %s. You know as much as I do." % skill.capitalize()
	if trainings_left(player) <= 0:
		return "That's enough training for now. Go and use what you've learned."
	var cost := train_cost(lvl, s)
	if not Currency.spend_gold(inv, cost):
		return "That's %d gold. Come back when you have it." % cost
	sk.debug_level_up(StringName(skill))
	var rec := WorldState.get_record("training")
	var n := int(rec.get("n", 0)) if int(rec.get("level", -1)) == sk.get_player_level() else 0
	WorldState.set_record("training", {"level": sk.get_player_level(), "n": n + 1})
	if world != null and world.clock != null:
		world.clock.advance_hours(2.0)
	return "Two hours of practice. Your %s is now %d. (%d gold)" % [skill.capitalize(), sk.get_level(StringName(skill)), cost]


# ---------------------------------------------------------------- the rest

## A night at the inn: the sleep screen opens (paid when you sleep, like the inn's beds)
static func rent(s: DialogueEngine.Speaker, player: Node) -> String:
	var inv := player.get_node("Inventory") as Inventory
	if Currency.get_gold(inv) < RestSpot.INN_PRICE:
		return "You can't afford a room."
	var bed := RestSpot.new()
	bed.name = "RentedRoom"
	bed.building_id = s.data.work_id if s.data != null else ""
	bed.building_kind = BuildingPlot.Kind.INN
	player.add_child(bed)
	bed.collision_layer = 0  # only a paper bed: nothing to bump into
	player.get_tree().create_timer(120.0, true, false, true).timeout.connect(bed.queue_free)
	var wm := player.get_node_or_null("WaitMenu") as WaitMenu
	if wm != null:
		wm.open_sleep(bed)
	return "Here's your key. Sleep well."


static func _carriage(s: DialogueEngine.Speaker, world: WorldManager) -> Carriage:
	if s.town == null or world == null:
		return null
	for c in world.get_tree().get_nodes_in_group("carriage"):
		if (c as Carriage).town_id == s.town.id:
			return c
	return null


## The town's carriage takes you to another city
static func travel(s: DialogueEngine.Speaker, world: WorldManager, player: Node) -> String:
	var c := _carriage(s, world)
	if c == null:
		return "No carriage stops here."
	c.interact(player.get_node("Inventory") as Inventory)
	return ""


## The smith mends your gear at the forge (Smithing improves it)
static func repair(player: Node) -> String:
	var inv := player.get_node("Inventory") as Inventory
	if not Currency.spend_gold(inv, REPAIR_FEE):
		return "That's %d gold for the forge." % REPAIR_FEE
	var ui := player.get_tree().get_first_node_in_group("crafting_ui") as CraftingUI
	if ui != null:
		ui.open_station("forge")
	return "Use my forge, then. Mind the tongs."


static func enchant(player: Node) -> String:
	var inv := player.get_node("Inventory") as Inventory
	if not Currency.spend_gold(inv, ENCHANT_FEE):
		return "The enchanting table is %d gold." % ENCHANT_FEE
	var ui := player.get_tree().get_first_node_in_group("crafting_ui") as CraftingUI
	if ui != null:
		ui.open_station("enchanter")
	return "The table is yours for the hour."
