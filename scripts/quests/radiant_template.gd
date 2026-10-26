class_name RadiantTemplate
extends Resource
## How one kind of generated job reads and pays: one file per kind in data/radiant/ (kill.tres,
## gather.tres...). Edit the wording and numbers in the Inspector; the generator (QuestManager,
## Radiant) fills in the places and people from the world.
##
## Placeholders in Names and Objectives: {thing} {place} {target} {chief} {giver} {town} {count}
## {destination}

## The kind of job: retrieve, kill, hunt, steal, persuade, deliver, assassinate, excavate, survey,
## gather, rescue, escort, investigate, protect, road
@export var type := ""
## Job names, one picked per job (the same job always gets the same one)
@export var names: PackedStringArray = []
## What the job asks, one picked per job
@export var objectives: PackedStringArray = []
@export var reward_base := 100
@export var reward_per_level := 8
## Only offered from this player level to this one (0 = no top)
@export var min_level := 1
@export var max_level := 0
## Only in these lands (biome keys like "taiga", "desert"; empty = anywhere)
@export var biomes: PackedStringArray = []
## Things to find, steal or gather (names, or res:// item paths for gather)
@export var things: PackedStringArray = []
## Who to fight (enemy file names in data/enemies, by biome: "taiga=frost_raider")
@export var enemies: PackedStringArray = []
## How many to fight, gather or protect against
@export var count_min := 1
@export var count_max := 3
## Days to finish it in (0 = the usual)
@export var days := 0


## The enemy file for a biome (an "biome=enemy" line, else the first plain one)
func enemy_for(biome_key: String) -> String:
	var plain := ""
	for e in enemies:
		if e.contains("="):
			if e.get_slice("=", 0) == biome_key:
				return e.get_slice("=", 1)
		elif plain == "":
			plain = e
	return plain
