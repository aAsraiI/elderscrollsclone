class_name QuestChoice
extends Resource
## A branch in a quest: asking person Who about Topic picks it (see QuestStage.choices). The
## quest then goes to stage Next (-1 = finish), and Flag is remembered for later checks
## (QuestCondition FLAG "<quest id>:<flag>").

@export var who := ""
@export var topic := ""
@export_multiline var say := ""
@export var next := -1
@export var flag := ""
## Picking this fails the quest instead (a wrong choice)
@export var fails := false
## Only offered when these pass
@export var conditions: Array[QuestCondition] = []
