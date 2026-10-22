class_name LevelCurve
extends RefCounted
## The numbers that make the game harder as the player levels up. This is the file to edit when
## balancing difficulty, like SkillDatabase.gd is for skills.
##
## Two ideas:
##  * TIERS: gear comes in 7 steps (Iron .. Starforged) spread over levels 1-100. Loot does not
##    switch tier at once: roll_tier() / tier_weights() mix the tiers around a level, so a new tier
##    shows up as a rare find a little before its start level and the old one fades out slowly.
##  * ZONES: every biome has a level_min..level_max. Dungeons and point-of-interest garrisons are
##    fixed difficulty (the same every visit, rolled from the world seed). Random encounters scale
##    to the player: the player's level, held inside the biome's range.
##
## What a tier is worth is in the item files themselves, made by tools/generate_content.gd:
##   tier        iron  steel  silver  obsidian  ebon  dragonbone  starforged
##   from level   1     8      17      28        41    56          74
##   damage x     1.0   1.5    2.1     2.9       3.9   5.2         7.4

## The highest player level (see SkillDatabase for how XP turns into levels)
const MAX_LEVEL := 100
const TIER_KEYS: Array[String] = ["iron", "steel", "silver", "obsidian", "ebon", "dragonbone", "starforged"]
const TIER_NAMES: Array[String] = ["Iron", "Steel", "Silver", "Obsidian", "Ebon", "Dragonbone", "Starforged"]
## Light armor's material name for each tier
const LIGHT_NAMES: Array[String] = ["Hide", "Leather", "Silverweave", "Shadowscale", "Ebonweave", "Dragonscale", "Starweave"]
const LIGHT_KEYS: Array[String] = ["hide", "leather", "silverweave", "shadowscale", "ebonweave", "dragonscale", "starweave"]
## The level at which each tier starts (it shows up as a rare find PREVIEW_LEVELS before this)
const TIER_MIN_LEVEL: Array[int] = [1, 8, 17, 28, 41, 56, 74]
const MAX_TIER := 6
const PREVIEW_LEVELS := 2


## Index (0 = iron) of the best tier that has started at this level
static func tier_for_level(level: int) -> int:
	var tier := 0
	for i in TIER_MIN_LEVEL.size():
		if level >= TIER_MIN_LEVEL[i]:
			tier = i
	return tier


## How likely each tier is at this level (sums to 1). Each tier is a bell around the middle of
## its own level band, so neighbouring tiers overlap and nothing jumps.
static func tier_weights(level: int) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(TIER_MIN_LEVEL.size())
	var total := 0.0
	for i in TIER_MIN_LEVEL.size():
		var start := TIER_MIN_LEVEL[i]
		var finish := TIER_MIN_LEVEL[i + 1] if i < MAX_TIER else MAX_LEVEL + 1
		var mid := (start + finish) * 0.5
		var span := maxf(float(finish - start), 4.0)
		var v := exp(-pow((float(level) - mid) / (span * 0.75), 2.0))
		# Fades in from PREVIEW_LEVELS + 1 levels before its start to 6 levels after (iron is there from the start)
		if i > 0:
			v *= smoothstep(float(start - PREVIEW_LEVELS - 1), float(start + 6), float(level))
		w[i] = v
		total += v
	if total <= 0.0:
		w[0] = 1.0
		return w
	for i in w.size():
		w[i] = w[i] / total
	return w


## A random tier for loot at this level, following tier_weights()
static func roll_tier(level: int, rng: RandomNumberGenerator) -> int:
	var w := tier_weights(level)
	var r := rng.randf()
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return tier_for_level(level)


## Gold in a chest or purse at this level: [min, max]
static func gold_range(level: int) -> Vector2i:
	return Vector2i(8 + 4 * level, 25 + 11 * level)


## Hit points of an average enemy of this level (archetypes multiply it: a wolf 0.6, a brute 1.7)
static func enemy_health(level: int) -> float:
	return 50.0 + 7.0 * float(level)


## How much a hit chips at the enemy's poise before it staggers
static func enemy_poise(level: int) -> float:
	return 40.0 + 0.8 * float(level)


## Multiplier on the damage of an enemy's weapon. Gently below 1 at high level, because weapon
## damage itself grows steeply with the tier.
static func enemy_damage_mult(level: int) -> float:
	return maxf(1.0 - 0.005 * float(level), 0.6)


## Damage of an unarmed creature (wolves, bears, trolls): it has no weapon to add damage
static func beast_damage(level: int) -> float:
	return 6.0 + 1.2 * float(level)


## A random encounter's level: the player's, held inside the biome's range
static func scale_level(player_level: int, zone_min: int, zone_max: int) -> int:
	return clampi(player_level, zone_min, maxi(zone_max, zone_min))


## Meters from a town at which a place reaches the top of its biome's level range
const WILD_DISTANCE := 1600.0
## Width of the range a single place gets (its level +- this)
const PLACE_SPREAD := 3


## The level range of a place at a world position (1..10 outside any biome). The biome's range
## (blended across borders, see WorldMap.get_level_band) is narrowed by how far the spot is from
## the nearest town: next to a town it sits at the bottom of the range, deep in the wild at the top.
static func zone_range(map: WorldMap, pos: Vector3) -> Vector2i:
	if map == null or map.get_placement_index_at(pos.x, pos.z) < 0:
		return Vector2i(1, 10)
	var band := map.get_level_band(pos.x, pos.z)
	var d := map.get_town_distance(pos.x, pos.z)
	if d == INF:
		return Vector2i(roundi(band.x), maxi(roundi(band.y), roundi(band.x)))
	var t := clampf(d / WILD_DISTANCE, 0.0, 1.0)
	var lvl := roundi(lerpf(band.x, band.y, 0.15 + 0.85 * t))
	var lo := maxi(roundi(band.x), lvl - PLACE_SPREAD)
	var hi := mini(maxi(roundi(band.y), lo), lvl + PLACE_SPREAD)
	return Vector2i(lo, maxi(hi, lo))


## The single level of a place (the middle of zone_range)
static func place_level(map: WorldMap, pos: Vector3) -> int:
	var r := zone_range(map, pos)
	return (r.x + r.y) / 2
