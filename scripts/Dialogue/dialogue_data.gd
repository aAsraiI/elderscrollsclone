class_name DialogueData
extends Resource
## Hand-written dialogue that adds to (or replaces) what the game generates for some people.
## Every DialogueData in scripts/Resources/Dialogue/ is used automatically; one can also be put
## on a hand-made NpcData. Who it applies to: listed npc ids, roles, or everyone.
##
## Make one: FileSystem > right-click > New Resource > DialogueData, add Topics (New DialogueTopic),
## give each topic Responses (New DialogueResponse). See example_rare_vintage.tres.

## Specific people: "npc/<building id>" (see a townsperson's id in their NpcData)
@export var npc_ids: PackedStringArray = []
## Whole jobs: "commoner", "farmer", "merchant", "innkeeper", "smith", "priest", "guild_member", "guard"
@export var roles: PackedStringArray = []
## Applies to absolutely everyone who talks
@export var everyone := false
@export var topics: Array[DialogueTopic] = []


func applies_to(npc_id: String, role: NpcData.Role) -> bool:
	if everyone:
		return true
	if npc_id != "" and npc_ids.has(npc_id):
		return true
	return roles.has(String(NpcData.Role.keys()[int(role)]).to_lower())


func get_topic(topic_name: String) -> DialogueTopic:
	for t in topics:
		if t != null and t.topic.to_lower() == topic_name.to_lower():
			return t
	return null
