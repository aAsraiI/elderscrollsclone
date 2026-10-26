class_name QuestData
extends Resource
## A handmade quest, edited in the Inspector like an ItemData. Every QuestData in data/quests/ is
## run by QuestRunner (templates are skipped: copy one, untick Template, change it).
## This is the template: what is saved while you play it is a separate live copy (the instance,
## WorldState "qi/<id>"), so nothing here ever changes in a game.
##
## Life of a quest: Unavailable (requirements not met) -> Available (the giver offers it as a
## topic) -> Active (stages) -> ReadyToTurnIn (turn-in quests) -> Completed. It can also end as
## Failed, Abandoned or Expired. See QuestRunner.

enum Completion { TURN_IN, AUTO }

@export var id := ""
@export var title := "A Quest"
## Copy this to make your own: templates are never offered in a game
@export var template := false
@export_multiline var description := ""
@export var level := 1

@export_group("Giver")
## Who offers it: "npc/<building id>", "custom/<id>" or "Name@Town" ("" = it starts by itself)
@export var giver := ""
## The topic the giver offers it under ("a lost ring")
@export var hook := ""
@export_multiline var intro := ""
## All must pass before it is offered
@export var requirements: Array[QuestCondition] = []
## Other quests (ids) that must be finished first: chains and story arcs
@export var after: PackedStringArray = []

@export_group("Stages")
@export var stages: Array[QuestStage] = []

@export_group("Ending")
@export var completion: Completion = Completion.TURN_IN
## Who takes it in ("" = the giver)
@export var turn_in := ""
## If that person is dead or gone: "lord" (the town's lord), a guild id (any of its leaders),
## or "board" (the town's notice board)
@export var fallback := "lord"
@export_multiline var turn_in_say := "Well done."
## Hours to finish it in (0 = no limit); past it the quest fails
@export var time_limit_hours := 0.0
## Can be offered again after failing (else closed for good)
@export var retry := true
## Days an offer stays open if never accepted (0 = forever); then it is Expired
@export var offer_days := 0

@export_group("Rewards")
@export var reward_gold := 0
## Extra gold per player level (rewards that grow with you)
@export var gold_per_level := 0
@export var reward_items: Array[ItemData] = []
## Pick ONE of these instead of getting them all (empty = no choice)
@export var reward_choice: Array[ItemData] = []
## Skill id and XP ("speech", 40)
@export var reward_skill := ""
@export var reward_skill_xp := 0.0
## Reputation with a guild id or a town's name
@export var reward_rep_with := ""
@export var reward_rep := 0
## A flag set on completion (unlocks dialogue, doors...)
@export var reward_flag := ""
## A quest offered right after this one (its id)
@export var follow_up := ""


## The person who takes it in
func turn_in_who() -> String:
	return turn_in if turn_in != "" else giver
