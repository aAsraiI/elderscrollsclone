class_name CustomNpcData
extends Resource
## A hand-made person, with no code: who they are, where they stand and what they say.
## Every CustomNpcData in data/npcs/custom/ is put in the world by CustomNpcs (they appear when you
## come near their spot). One can also be placed by hand in any scene with a CustomNpcSpot node.
##
## Make one: FileSystem > data/npcs/custom > right-click > New Resource > CustomNpcData. Give it a
## name, a town (or a world position) and a DialogueData with their topics. See example_hermit.tres.
## They live alongside the generated townspeople, guild jobs and written quests.

## Saved with this id ("custom/<id>"): their disposition, and whether they were killed
@export var id := ""
@export var display_name := "Stranger"
@export var role: NpcData.Role = NpcData.Role.COMMONER
@export var personality: NpcData.Personality = NpcData.Personality.FRIENDLY
@export_range(0, 100) var base_disposition := 50
## A guild or faction id ("fighters", "mages"...), or ""
@export var faction := ""
@export var level := 5
## Their body and gear ("" = an ordinary townsperson's)
@export var body: EnemyData
@export var color := Color(0.45, 0.4, 0.32)
## Their own first words (instead of a generated greeting)
@export_multiline var greeting := ""
## Hand-written topics and answers (DialogueData: FileSystem > New Resource > DialogueData)
@export var dialogue: DialogueData
## On: they also talk about the usual things (rumors, their town, places nearby) like everyone.
## Off: only their own topics.
@export var generated_topics := false
## Their own topic profile (what kinds of things they talk about, their buttons); empty = their role's
@export var profile: DialogueProfile
## Quests they give (QuestData): their Giver is set to this person automatically
@export var quests: Array[QuestData] = []

@export_group("Gear")
## What they carry (lootable if they die)
@export var inventory: Array[ItemData] = []
## What they wear and wield
@export var equipment: Array[ItemData] = []

@export_group("Day")
## From Work Start to Work End they stand at their spot; outside it, at Home Offset (or home)
@export_range(0.0, 24.0, 0.25) var work_start := 0.0
@export_range(0.0, 24.0, 0.25) var work_end := 24.0
## Where they go outside work hours: meters from the middle of the town (or from World Position)
@export var home_offset := Vector3.ZERO

@export_group("Where")
## A place by id or name (a POI id, a building id, "dungeon near Kingsreach"...): beats Town
@export var place := ""
## The town they stand in (its name, like "Kingsreach"), "" = use World Position
@export var town := ""
## Meters from the middle of the town (x = east, z = south)
@export var offset := Vector3.ZERO
## Where they stand when Town is empty (meters on the map)
@export var world_position := Vector3.ZERO


## The NpcData the dialogue reads (a townsperson's sheet, made from this one)
func to_npc_data() -> NpcData:
	var n := NpcData.new()
	n.id = save_id()
	n.display_name = display_name
	n.role = role
	n.personality = personality
	n.base_disposition = base_disposition
	n.faction = faction
	n.level = level
	n.color = color
	n.dialogue = dialogue
	return n


func save_id() -> String:
	return "custom/" + (id if id != "" else display_name.to_snake_case())
