class_name LevelCurve
extends RefCounted
## The numbers that make the game harder as the player levels up. This is the file to edit when
## balancing difficulty, like SkillDatabase.gd is for skills.
##
## Two ideas:
##  * TIERS: gear comes in 7 steps (Iron .. Starforged). A level maps to a tier, and everything
##    that hands out gear (enemy weapons, chest loot, drops) asks for the tier of its level.
##  * ZONES: every biome has a level_min..level_max. Dungeons and point-of-interest garrisons are
##    fixed difficulty (the same every visit, rolled from the world seed). Random encounters scale
##    to the player: the player's level, held inside the biome's range.
##
## What a tier is worth (damage multiplier on the Iron weapon, chest armor points) is in the item
## files themselves (scripts/Resources/Weapons), made by tools/generate_content.py:
##   tier        iron  steel  silver  obsidian  ebon  dragonbone  starforged
##   from level   1     6      12      18        25    33          42
##   damage x     1.0   1.5    2.1     2.9       3.9   5.2         6.8
##   chest armor  25    33     42      52        62    71          78

const TIER_KEYS: Array[String] = ["iron", "steel", "silver", "obsidian", "ebon", "dragonbone", "starforged"]
const TIER_NAMES: Array[String] = ["Iron", "Steel", "Silver", "Obsidian", "Ebon", "Dragonbone", "Starforged"]
## The player level at which each tier starts to appear
const TIER_MIN_LEVEL: Array[int] = [1, 6, 12, 18, 25, 33, 42]
const MAX_TIER := 6


## Index (0 = iron) of the best tier that is available at this level
static func tier_for_level(level: int) -> int:
	var tier := 0
	for i in TIER_MIN_LEVEL.size():
		if level >= TIER_MIN_LEVEL[i]:
			tier = i
	return tier


## Hit points of an average enemy of this level (archetypes multiply it: a wolf 0.6, a brute 1.7)
static func enemy_health(level: int) -> float:
	return 50.0 + 9.0 * float(level)


## How much a hit chips at the enemy's poise before it staggers
static func enemy_poise(level: int) -> float:
	return 40.0 + float(level)


## Multiplier on the damage of an enemy's weapon. Gently below 1 at high level, because weapon
## damage itself grows steeply with the tier.
static func enemy_damage_mult(level: int) -> float:
	return maxf(1.0 - 0.008 * float(level), 0.7)


## Damage of an unarmed creature (wolves, bears, trolls): it has no weapon to add damage
static func beast_damage(level: int) -> float:
	return 6.0 + 1.6 * float(level)


## A random encounter's level: the player's, held inside the biome's range
static func scale_level(player_level: int, zone_min: int, zone_max: int) -> int:
	return clampi(player_level, zone_min, maxi(zone_max, zone_min))


## The level range of the biome at a world position (1..10 outside any biome)
static func zone_range(map: WorldMap, pos: Vector3) -> Vector2i:
	var biome := map.get_biome_at(pos.x, pos.z) if map != null else null
	if biome == null:
		return Vector2i(1, 10)
	return Vector2i(biome.level_min, maxi(biome.level_max, biome.level_min))
