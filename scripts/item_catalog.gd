class_name ItemCatalog
extends RefCounted
## Finds the item files and builds level-appropriate loot lists from them.
## The files are made by tools/generate_content.gd. Iron-tier gear and the Steel Greatsword keep
## their old paths in scripts/Resources/, other gear is in scripts/Resources/Weapons/ and Armor/,
## called <material>_<kind>.tres, e.g. ebon_warhammer.tres, leather_boots.tres.
##
## Loot follows LevelCurve.tier_weights(): a chest at level 30 is mostly Obsidian, some Silver,
## and a rare Ebon piece once its start level is close. Every item also has loot_tags
## ("kitchen", "smithy", "crypt"...) that furnished rooms use to pick what sits on their shelves.

enum Weapon { SWORD, DAGGER, GREATSWORD, WARHAMMER, WAR_AXE, MACE, SPEAR, BATTLEAXE }

const WEAPON_KINDS: Array[String] = ["sword", "dagger", "greatsword", "warhammer", "waraxe", "mace", "spear", "battleaxe"]
const ARMOR_PIECES: Array[String] = ["helmet", "cuirass", "gauntlets", "greaves", "boots"]
const DIR := "res://scripts/Resources/Weapons/"
const ARMOR_DIR := "res://scripts/Resources/Armor/"
const LEGACY := {
	"iron_sword": "res://scripts/Resources/iron_sword.tres",
	"iron_dagger": "res://scripts/Resources/iron_dagger.tres",
	"iron_warhammer": "res://scripts/Resources/iron_warhammer.tres",
	"iron_shield": "res://scripts/Resources/iron_shield.tres",
	"iron_chestplate": "res://scripts/Resources/iron_chestplate.tres",
	"steel_greatsword": "res://scripts/Resources/steel_greatsword.tres",
}
## Every folder of items (scanned once for all_items() / tagged())
const ITEM_DIRS: Array[String] = [
	"res://scripts/Resources/", "res://scripts/Resources/Weapons/", "res://scripts/Resources/Armor/",
	"res://scripts/Resources/Jewelry/", "res://scripts/Resources/Clothing/", "res://scripts/Resources/Clutter/",
	"res://scripts/Resources/Ingredients/", "res://scripts/Resources/Artifacts/", "res://scripts/Resources/Consumables/",
	"res://scripts/Resources/Treasure/", "res://scripts/Resources/Misc/", "res://scripts/Resources/Materials/",
	"res://scripts/Resources/Books/", "res://scripts/Resources/SoulGems/", "res://scripts/Resources/Ranged/",
]

static var _cache := {}
static var _all: Array[ItemData] = []
static var _by_tag := {}


static func _load(path: String) -> ItemData:
	if _cache.has(path):
		return _cache[path]
	var item: ItemData = null
	if ResourceLoader.exists(path):
		item = load(path) as ItemData
	else:
		push_warning("ItemCatalog: %s does not exist. Run tools/generate_content.gd." % path)
	_cache[path] = item
	return item


static func _item(tier: int, kind: String) -> ItemData:
	tier = clampi(tier, 0, LevelCurve.MAX_TIER)
	var key := "%s_%s" % [LevelCurve.TIER_KEYS[tier], kind]
	return _load(LEGACY.get(key, DIR + key + ".tres"))


## A weapon of this kind (see Weapon) and tier (0 = iron). Null if the file is missing.
static func get_weapon(kind: int, tier: int) -> ItemData:
	return _item(tier, WEAPON_KINDS[kind])


static func get_shield(tier: int) -> ItemData:
	return _item(tier, "shield")


## The heavy cuirass of a tier (the old "chestplate" files)
static func get_chest(tier: int) -> ItemData:
	return _item(tier, "chestplate")


## One armor piece: piece is one of ARMOR_PIECES, heavy or light
static func get_armor(tier: int, piece: String, heavy: bool) -> ItemData:
	tier = clampi(tier, 0, LevelCurve.MAX_TIER)
	if heavy and piece == "cuirass":
		return get_chest(tier)
	var mat: String = LevelCurve.TIER_KEYS[tier] if heavy else LevelCurve.LIGHT_KEYS[tier]
	return _load(ARMOR_DIR + "%s_%s.tres" % [mat, piece])


# ---------------------------------------------------------------- the index

## Every item file in ITEM_DIRS (loaded once)
static func all_items() -> Array[ItemData]:
	if _all.is_empty():
		var seen := {}
		for dir in ITEM_DIRS:
			for f in DirAccess.get_files_at(dir):
				var file := f.trim_suffix(".remap")
				if not file.ends_with(".tres") or seen.has(dir + file):
					continue
				seen[dir + file] = true
				var res := load(dir + file)
				if res is ItemData:
					_all.append(res)
		for item in _all:
			for tag in item.loot_tags:
				if not _by_tag.has(tag):
					_by_tag[tag] = []
				(_by_tag[tag] as Array).append(item)
	return _all


## Items with this loot tag ("kitchen", "smithy", "crypt", ...)
static func tagged(tag: String) -> Array:
	all_items()
	return _by_tag.get(tag, [])


# ---------------------------------------------------------------- loot lists

## Chances for a chest holding gear that suits levels level_min..level_max: the tiers mixed by
## LevelCurve.tier_weights() at the middle level (a tier only starts appearing once level_max
## reaches its preview). quality scales every chance (a boss chest uses more than 1).
static func curve_loot(level_min: int, level_max: int, quality: float = 1.0) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	var lo := mini(level_min, level_max)
	var hi := maxi(level_min, level_max)
	var weights := LevelCurve.tier_weights((lo + hi) / 2)
	var top := LevelCurve.tier_weights(hi)
	for t in weights.size():
		# the tier that is only just appearing at the top of the range still gets its small share
		var w := maxf(weights[t], top[t] * 0.5)
		if w < 0.03:
			continue
		for k in WEAPON_KINDS.size():
			_add(out, get_weapon(k, t), 0.09 * w * quality)
		_add(out, get_shield(t), 0.10 * w * quality)
		for piece in ARMOR_PIECES:
			_add(out, get_armor(t, piece, true), 0.055 * w * quality)
			_add(out, get_armor(t, piece, false), 0.055 * w * quality)
	out.append_array(jewelry_loot(hi, 0.5 * quality))
	return out


## What an enemy of this level may carry besides what it wields (0 quality = nothing)
static func enemy_loot(level: int, quality: float) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	if quality <= 0.0:
		return out
	var tier := LevelCurve.tier_for_level(level)
	for k in WEAPON_KINDS.size():
		_add(out, get_weapon(k, tier), 0.025 * quality)
	_add(out, get_chest(tier), 0.04 * quality)
	_add(out, get_shield(tier), 0.03 * quality)
	for piece in ARMOR_PIECES:
		_add(out, get_armor(tier, piece, false), 0.02 * quality)
	return out


## Rings and amulets that can turn up at this level (better grades rarer)
static func jewelry_loot(level: int, quality: float = 1.0) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for item in tagged("jewelry"):
		var it := item as ItemData
		if it.min_level > level:
			continue
		_add(out, it, 0.02 * quality)
	return out


## A purse of gold for this level (see LevelCurve.gold_range)
static func gold_loot(level: int, chance: float = 0.9) -> LootEntry:
	var e := LootEntry.new()
	e.item = load("res://scripts/Resources/Consumables/gold.tres") as ItemData
	var r := LevelCurve.gold_range(level)
	e.min_count = r.x
	e.max_count = r.y
	e.chance = chance
	return e


## Loot for a furnished room or container: items with any of these tags that suit the level.
## Gear (weapons / armor) in the list follows the tier mix; everything else needs min_level <= level.
static func tag_loot(tags: PackedStringArray, level: int, quality: float = 1.0) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	var seen := {}
	var weights := LevelCurve.tier_weights(level)
	for tag in tags:
		for item in tagged(tag):
			var it := item as ItemData
			if seen.has(it):
				continue
			seen[it] = true
			var chance := 0.12
			if it.item_type == ItemData.ItemType.WEAPON or (it.item_type == ItemData.ItemType.ARMOR and it.tier > 0 and it.armor_set != &""):
				chance *= weights[clampi(it.tier - 1, 0, LevelCurve.MAX_TIER)] * 0.5
			elif it.min_level > level:
				continue
			elif it.artifact:
				chance = 0.04
			elif it.value > 200:
				chance *= 0.3
			_add(out, it, chance * quality)
	return out


## The color an item's name is shown in: artifacts gold, gear above your level's tier blue
## (one tier up) or purple (two or more), gear behind you grey, everything else plain.
static func rarity_color(item: ItemData, player_level: int) -> Color:
	if item == null:
		return Color.WHITE
	if item.artifact:
		return Color(0.95, 0.78, 0.35)
	if item.tier > 0 and (item.item_type == ItemData.ItemType.WEAPON or item.item_type == ItemData.ItemType.ARMOR):
		var ahead := (item.tier - 1) - LevelCurve.tier_for_level(player_level)
		if ahead >= 2:
			return Color(0.78, 0.55, 1.0)
		if ahead == 1:
			return Color(0.5, 0.75, 1.0)
		if ahead <= -2:
			return Color(0.7, 0.7, 0.7)
	if item.treasure:
		return Color(0.75, 0.85, 1.0)
	return Color(0.9, 0.88, 0.82)


const TREASURE_DIR := "res://scripts/Resources/Treasure/"
static var _treasures: Array[ItemData] = []


## Every treasure item (gems, jewelry, relics), cheapest first
static func get_treasures() -> Array[ItemData]:
	if _treasures.is_empty():
		var names := PackedStringArray()
		for f in DirAccess.get_files_at(TREASURE_DIR):
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres") and not names.has(file):
				names.append(file)
		for file in names:
			var item := load(TREASURE_DIR + file) as ItemData
			if item != null and item.treasure:
				_treasures.append(item)
		_treasures.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.value < b.value)
	return _treasures


## Treasure for a chest that suits levels level_min..level_max: the pieces that can turn up at
## those levels, the valuable ones rarer. quality scales every chance (boss chests use more).
static func treasure_loot(level_min: int, level_max: int, quality: float = 1.0) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	var hi := maxi(level_min, level_max)
	for item in get_treasures():
		if item.min_level > hi:
			continue
		# about 0.25 for a 25-gold coin, 0.05 for a 1000-gold diamond
		var chance := clampf(0.25 * pow(25.0 / maxf(float(item.value), 25.0), 0.45), 0.03, 0.25)
		_add(out, item, chance * quality)
	return out


static func _add(list: Array[LootEntry], item: ItemData, chance: float) -> void:
	if item == null or chance <= 0.0:
		return
	var e := LootEntry.new()
	e.item = item
	e.min_count = 1
	e.max_count = 1
	e.chance = clampf(chance, 0.0, 1.0)
	list.append(e)


const RANGED_DIR := "res://scripts/Resources/Ranged/"


## A bow of this tier (0 = the hunting bow). Null if the file is missing.
static func get_bow(tier: int) -> ItemData:
	tier = clampi(tier, 0, LevelCurve.MAX_TIER)
	return _load(RANGED_DIR + ("hunting_bow" if tier == 0 else LevelCurve.TIER_KEYS[tier] + "_bow") + ".tres")


## Arrows of this tier (0 = iron)
static func get_arrow(tier: int) -> ItemData:
	tier = clampi(tier, 0, LevelCurve.MAX_TIER)
	return _load(RANGED_DIR + LevelCurve.TIER_KEYS[tier] + "_arrow.tres")
