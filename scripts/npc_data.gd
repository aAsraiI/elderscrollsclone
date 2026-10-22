class_name NpcData
extends Resource
## One townsperson: who they are, where they live and work, and their day. The body (how they
## look and fight) is an ordinary Enemy built from `body` (an EnemyData) at `level`.
##
## Every town makes its residents from its buildings (see Residents): each building's owner
## lives in it, and works in it too if it is a shop, inn, smithy, temple or guild hall. Guards
## have no home: they walk their rounds day and night. TownLife moves everyone through the day.
##
## A hand-made NPC can be a saved NpcData resource later (and Dialogue, stage 4, can hang off it).

enum Role { COMMONER, FARMER, MERCHANT, INNKEEPER, SMITH, PRIEST, GUILD_MEMBER, GUARD, WOODCUTTER, FISHERMAN, HUNTER, MINER, HERBALIST }
enum Personality { FRIENDLY, CHEERFUL, GRUMPY, NERVOUS, PROUD, PIOUS }
## What someone is doing at a given hour
enum Activity { SLEEP, WORK, LEISURE, PATROL }

## Stable id, "npc/<building id>" for residents. Kills are remembered under it.
@export var id := ""
@export var display_name := "Townsperson"
@export var role: Role = Role.COMMONER
## "fighters", "mages", "knights", "guard", or the town for ordinary people
@export var faction := ""
@export var personality: Personality = Personality.FRIENDLY
## How much they like the player to start with, 0-100 (dialogue and prices use it later)
@export_range(0, 100) var base_disposition := 50
## The building they own and sleep in (BuildingPlot.id). Empty for guards.
@export var home_id := ""
## The building they work in. Empty = they work outside (farmers in their field, others on the square).
@export var work_id := ""
## The town they belong to (its POI id)
@export var town_id := ""
## How they look and fight
@export var body: EnemyData
@export var level := 1
## Guards: the gate they stand watch at (0 or 1), or -1 to walk rounds
@export var post := -1
## Placeholder body color
@export var color := Color(0.4, 0.5, 0.6)
## Short lines for the speech bubble (used when there is no dialogue window)
@export var talk_lines: PackedStringArray = []
## Hand-written topics just for this person (on top of the generated ones and scripts/Resources/Dialogue/)
@export var dialogue: DialogueData

@export_group("Day")
@export_range(0.0, 24.0, 0.25) var wake_hour := 6.0
@export_range(0.0, 24.0, 0.25) var work_start := 8.0
@export_range(0.0, 24.0, 0.25) var work_end := 18.0
@export_range(0.0, 24.0, 0.25) var sleep_hour := 21.0


## What this person does at `hour` (0-24)
func activity_at(hour: float) -> Activity:
	if role == Role.GUARD:
		return Activity.PATROL
	if WorldClock.hour_in_range(hour, sleep_hour, wake_hour):
		return Activity.SLEEP
	if WorldClock.hour_in_range(hour, work_start, work_end):
		return Activity.WORK
	return Activity.LEISURE


static func role_for(kind: BuildingPlot.Kind) -> Role:
	match kind:
		BuildingPlot.Kind.FARM:
			return Role.FARMER
		BuildingPlot.Kind.SHOP:
			return Role.MERCHANT
		BuildingPlot.Kind.INN:
			return Role.INNKEEPER
		BuildingPlot.Kind.SMITHY:
			return Role.SMITH
		BuildingPlot.Kind.TEMPLE:
			return Role.PRIEST
		BuildingPlot.Kind.GUILD_HALL:
			return Role.GUILD_MEMBER
	return Role.COMMONER


## The role of a building's owner: from the kind of building, or a house's trade (woodcutter...)
static func role_for_plot(b: BuildingPlot) -> Role:
	if b.kind == BuildingPlot.Kind.HOUSE:
		match b.trade:
			"woodcutter":
				return Role.WOODCUTTER
			"fisherman":
				return Role.FISHERMAN
			"hunter":
				return Role.HUNTER
			"miner":
				return Role.MINER
			"herbalist":
				return Role.HERBALIST
	return role_for(b.kind)


## Tradesmen work outside by their house (or on the shore): woodcutters, fishermen...
static func is_tradesman(r: Role) -> bool:
	return r >= Role.WOODCUTTER


static func role_name(r: Role) -> String:
	return ["Townsperson", "Farmer", "Merchant", "Innkeeper", "Smith", "Priest", "Guild Member", "Guard", "Woodcutter", "Fisherman", "Hunter", "Miner", "Herbalist"][int(r)]
