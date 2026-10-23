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


# ---------------------------------------------------------------- the Night map

## Each clan's colour on the Night layer of the map
const COLORS := {"velvet_court": Color(0.75, 0.15, 0.35), "hollow_kin": Color(0.55, 0.4, 0.2), "ashen_choir": Color(0.45, 0.35, 0.85)}


## Only vampires see who rules the night (the N layer on the map)
static func can_see_night(tree: SceneTree) -> bool:
	var aff := Afflictions.of(tree)
	return aff != null and aff.vampire


## The clan the player is sworn to, or ""
static func player_clan() -> String:
	for c in CLANS:
		if Factions.is_member(c):
			return c
	return ""


## Takes control away from a clan in a land (a lost war event); the others share what it loses
static func lose(biome: String, clan: String, amount: int) -> void:
	if not CLANS.has(clan) or not START.has(biome):
		return
	var s := scores(biome).duplicate()
	for c in CLANS:
		s[c] = clampi(int(s[c]) + (-amount if c == clan else amount / 2), 0, 100)
	WorldState.set_record("clan_land/" + biome, s)


# ---------------------------------------------------------------- feeding grounds
# About one dungeon or lair in four is some clan's feeding ground. A sworn vampire who clears a
# rival clan's ground leaves their own clan's blood-sigil there: +GAIN control in that land.

## The clan whose feeding ground this place is ("" = nobody's)
static func ground_owner(poi_id: String, biome: String) -> String:
	if not START.has(biome):
		return ""
	var rec := WorldState.get_record("clan_ground/" + poi_id)
	if not rec.is_empty():
		return String(rec.get("clan", ""))
	var h := absi(poi_id.hash())
	if h % 4 != 0:
		return ""
	# Mostly the land's ruler, sometimes a rival that has a foothold there
	var s: Array = START[biome]
	var best := 0
	for i in 3:
		if int(s[i]) > int(s[best]):
			best = i
	return CLANS[best] if (h / 4) % 3 != 0 else CLANS[(best + 1 + (h / 12) % 2) % 3]


## A dungeon's boss died (DungeonBuilder): a rival's feeding ground becomes the player's clan's
static func on_cleared(tree: SceneTree, poi_id: String) -> void:
	var clan := player_clan()
	var wm := tree.get_first_node_in_group("world_manager") as WorldManager if tree != null else null
	if clan == "" or wm == null or wm.map == null:
		return
	var poi := wm.get_poi(poi_id)
	var biome := wm.get_biome_at(poi.position.x, poi.position.z) if poi != null else null
	if biome == null:
		return
	var key := biome.get_key()
	var owner_clan := ground_owner(poi_id, key)
	if owner_clan == "" or owner_clan == clan:
		return
	WorldState.set_record("clan_ground/" + poi_id, {"clan": clan})
	gain(key, clan, GAIN)
	Locks.toast(tree, "You leave the blood-sigil of the %s here: %s gains ground in the %s." % [Factions.display_name(clan), Factions.display_name(clan), biome.display_name])
