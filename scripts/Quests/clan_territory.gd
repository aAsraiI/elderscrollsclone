class_name ClanTerritory
extends RefCounted
## The territory war of the three vampire clans. Every land (biome) has a control score for each
## clan (0-100); the highest rules it. Finishing a clan quest in a land gives your clan control there
## (QuestBook), and clan leaders tell you who holds what ("the territory war").
## Saved in WorldState "clan_land/<biome>".

const CLANS: Array[String] = ["velvet_court", "hollow_kin", "ashen_choir"]
const GAIN := 10

## Who held what in 412 CA (the design bible's starting table)
const START := {
	"swamp": [70, 15, 15], "lakeland": [70, 15, 15], "coast": [70, 15, 15],
	"plains": [40, 40, 20], "forest": [40, 40, 20],
	"highlands": [15, 70, 30], "badlands": [15, 70, 30],
	"desert": [40, 20, 40], "deadlands": [40, 20, 40],
	"ashlands": [15, 15, 70], "snow_mountains": [15, 15, 70], "frozen_crown": [15, 15, 70], "tundra": [15, 15, 70],
}


static func scores(biome: String) -> Dictionary:
	var rec := WorldState.get_record("clan_land/" + biome)
	if not rec.is_empty():
		return rec
	var s: Array = START.get(biome, [33, 33, 33])
	return {CLANS[0]: s[0], CLANS[1]: s[1], CLANS[2]: s[2]}


static func ruler(biome: String) -> String:
	var s := scores(biome)
	var best := ""
	for c in CLANS:
		if best == "" or int(s[c]) > int(s[best]):
			best = c
	return best


## A clan gains ground in a land; the others lose half as much each
static func gain(biome: String, clan: String, amount: int = GAIN) -> void:
	if not CLANS.has(clan) or not START.has(biome):
		return
	var s := scores(biome).duplicate()
	for c in CLANS:
		s[c] = clampi(int(s[c]) + (amount if c == clan else -amount / 2), 0, 100)
	WorldState.set_record("clan_land/" + biome, s)


## "The Velvet Court holds the Swamp, the Lakeland and the Coast. ..."
static func summary() -> String:
	var held := {}
	for c in CLANS:
		held[c] = PackedStringArray()
	for biome: String in START:
		(held[ruler(biome)] as PackedStringArray).append(biome.replace("_", " ").capitalize())
	var parts := PackedStringArray()
	for c in CLANS:
		var lands: PackedStringArray = held[c]
		parts.append("%s holds %s." % [Factions.display_name(c), ", ".join(lands) if not lands.is_empty() else "nothing"])
	return " ".join(parts)
