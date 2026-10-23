class_name SpawnTable
extends Resource
## What can appear somewhere: a bandit camp's garrison, a dungeon's rooms, a biome's random
## encounters. Each roll picks one entry (weighted, only entries allowed at that level) and
## returns its members, repeated a random number of times.
## Create in the editor: FileSystem > right-click > New Resource > SpawnTable, add SpawnEntry elements.

@export var entries: Array[SpawnEntry] = []


func has_entries_for(level: int) -> bool:
	for e in entries:
		if e != null and e.allows(level):
			return true
	return false


## One group for an area of this level. Empty if nothing is allowed at that level.
func roll(rng: RandomNumberGenerator, level: int) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	var total := 0.0
	for e in entries:
		if e != null and e.allows(level):
			total += e.weight
	if total <= 0.0:
		return out
	var pick := rng.randf() * total
	var chosen: SpawnEntry = null
	for e in entries:
		if e == null or not e.allows(level):
			continue
		chosen = e
		pick -= e.weight
		if pick <= 0.0:
			break
	if chosen == null:
		return out
	var copies := rng.randi_range(mini(chosen.count_min, chosen.count_max), maxi(chosen.count_min, chosen.count_max))
	for i in copies:
		for m in chosen.members:
			if m != null:
				out.append(m)
	return out
