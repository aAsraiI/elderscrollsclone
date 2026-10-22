class_name DialogueResponse
extends Resource
## One possible answer to a hand-written topic (see DialogueTopic, DialogueData). The first answer
## whose conditions all pass is the one spoken.

@export_multiline var text := ""
@export_group("Only when")
## The speaker must like the player at least this much (0-100)
@export_range(0, 100) var min_disposition := 0
## This flag must be set ("" = no check)
@export var need_flag := ""
## This flag must NOT be set ("" = no check)
@export var not_flag := ""
@export_group("Then")
## Sets this flag after speaking
@export var set_flag := ""
## Gives the player an item after speaking
@export var give_item: ItemData
@export var give_count := 1
## Extra topics the player learns (on top of any topic names in the text)
@export var learn_topics: PackedStringArray = []
@export_group("Journal")
## Files the line under a quest in the journal (its Quests filter)
@export var quest_id := ""
@export var quest_name := ""


func passes(disposition: int) -> bool:
	if disposition < min_disposition:
		return false
	if need_flag != "" and not DialogueState.has_flag(need_flag):
		return false
	if not_flag != "" and DialogueState.has_flag(not_flag):
		return false
	return true
