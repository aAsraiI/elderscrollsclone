class_name Chaos
extends RefCounted
## Alpha 1.24 (immersive sim): how much blood you leave behind, and how the land answers it.
## Worked out from the tally (Takedowns): people you killed count, townsfolk you murdered count five
## times over, people you only knocked out count for nothing.
##   0 calm      nothing changes
##   1 uneasy    people talk of the killings
##   2 grim      towns feel less safe (TownNeeds), more road wardens patrol, guards are short with you
##   3 dark      everyone talks of it; the roads are guarded; the epilogue remembers
## Debug console: "chaos".

const LEVELS := [10, 30, 80]
const NAMES := ["calm", "uneasy", "grim", "dark"]


static func score() -> int:
	var murders := 0
	for key in WorldState.records.keys():
		if String(key).begins_with("npc_killer/"):
			murders += 1
	return Takedowns.tally("kills") + murders * 5


static func level() -> int:
	var s := score()
	var l := 0
	for t in LEVELS:
		if s >= t:
			l += 1
	return l


static func level_name() -> String:
	return NAMES[level()]


## A line about the killings for a townsperson to say ("" = they don't mention it)
static func remark(k: int) -> String:
	match level():
		1:
			return ["They say there's a killer on the roads.", "Another body found on the north road, I heard."][k % 2]
		2:
			return ["So many dead this season. Lock your door at night.", "The guard's doubled at the gates. Can't say I blame them.", "Whoever's doing this killing, I hope they hang."][k % 3]
		3:
			return ["Every week, more graves. What's become of this land?", "Mothers keep their children in. Nobody walks alone.", "There's a butcher loose in the land, and nobody can stop them."][k % 3]
	return ""


## How much a town's safety drops for it (TownNeeds)
static func safety_cost() -> int:
	return [0, 0, 10, 20][level()]


## The epilogue's last word
static func epilogue_line() -> String:
	match level():
		0:
			return "They will say you brought the land through its darkest hour and spilled as little blood as you could."
		1:
			return "They will say you did what you had to, and not much more."
		2:
			return "The land was saved, and the graveyards are fuller for it. Some still lock their doors when they hear your name."
	return "The land was saved, but the songs about it are not kind. In the villages they tell their children to be good, or you will come for them."
