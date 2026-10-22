class_name SpawnEntry
extends Resource
## One line of a SpawnTable: a group that can spawn, and when. `members` is the group (one wolf, or
## a merchant with two guards), `count` is how many copies of it appear.

@export var members: Array[EnemyData] = []
## Chance relative to the other entries that are allowed at this level
@export var weight := 1.0
@export var count_min := 1
@export var count_max := 1
## Only used at levels min_level..max_level
@export var min_level := 1
@export var max_level := 100


func allows(level: int) -> bool:
	return not members.is_empty() and weight > 0.0 and level >= min_level and level <= max_level
