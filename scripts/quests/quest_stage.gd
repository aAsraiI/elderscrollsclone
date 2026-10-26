class_name QuestStage
extends Resource
## One stage of a QuestData: its journal line and what it asks for. Objectives run side by side
## (parallel), or one after another when Sequential is on. A stage with Choices ends when one
## is picked (a branch); otherwise it ends when every objective that isn't optional is done and
## the quest moves to Next (-1 = the next stage in the list).

@export_multiline var text := ""
@export var objectives: Array[QuestObjective] = []
@export var sequential := false
@export var choices: Array[QuestChoice] = []
@export var next := -1
