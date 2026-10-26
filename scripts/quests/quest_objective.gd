class_name QuestObjective
extends Resource
## One thing a quest stage asks for (see QuestStage, QuestData). Progress comes from QuestEvents
## (kills, talks, thefts...) and from looking at the world (what you carry, where you stand).
##
##   KILL       kill Count creatures whose enemy id, name or spawn key is Target ("wolf",
##              "Osric the Black"). With Spawn set, they are made at Place when you come near.
##   COLLECT    carry Count of item Target (res:// path or item id); handed over at turn-in
##   DELIVER    carry item Target to person Who and ask them about Topic (it is taken)
##   TALK       ask person Who about Topic; they answer Say
##   REACH      come within Radius meters of Place
##   STEAL      steal Count of item Target (from someone else's container)
##   PERSUADE   make person Who like you to at least Count (disposition)
##   USE_ITEM   use (eat, drink, read) item Target Count times
##   DISCOVER   discover the place Place (its POI id, or "nearest:<kind>")

enum Type { KILL, COLLECT, DELIVER, TALK, REACH, STEAL, PERSUADE, USE_ITEM, DISCOVER }

@export var type: Type = Type.KILL
## What the journal and tracker say ("Kill the wolves of Greyholt")
@export var text := ""
## An enemy id or name, an item path or id (see Type)
@export var target := ""
@export var count := 1
## A person: "npc/<building id>", "custom/<id>", or "Name@Town" for a named townsperson
@export var who := ""
@export var topic := ""
@export_multiline var say := ""
## A place: a town's name, a POI id, "dungeon near <Town>", "camp near <Town>", or "x,z" in meters
@export var place := ""
@export var radius := 30.0
## KILL: an enemy file to make at Place (res://data/enemies/....tres); "" = any already there
@export var spawn := ""
@export_group("Kind")
## Not needed to finish the stage
@export var optional := false
## Optional, and pays BonusGold when done
@export var bonus := false
@export var bonus_gold := 0
## Not shown until it is done
@export var hidden := false
