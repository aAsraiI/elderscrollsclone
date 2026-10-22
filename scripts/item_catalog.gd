class_name ItemCatalog
extends RefCounted
## Finds the tiered gear files and builds level-appropriate loot lists from them.
## The files are made by tools/generate_content.py. Iron-tier gear and the Steel Greatsword keep
## their old paths in scripts/Resources/, everything else is in scripts/Resources/Weapons/ and is
## called <tier>_<kind>.tres, e.g. ebon_warhammer.tres.

enum Weapon { SWORD, DAGGER, GREATSWORD, WARHAMMER }

const WEAPON_KINDS: Array[String] = ["sword", "dagger", "greatsword", "warhammer"]
const DIR := "res://scripts/Resources/Weapons/"
const LEGACY := {
	"iron_sword": "res://scripts/Resources/iron_sword.tres",
	"iron_dagger": "res://scripts/Resources/iron_dagger.tres",
	"iron_warhammer": "res://scripts/Resources/iron_warhammer.tres",
	"iron_shield": "res://scripts/Resources/iron_shield.tres",
	"iron_chestplate": "res://scripts/Resources/iron_chestplate.tres",
	"steel_greatsword": "res://scripts/Resources/steel_greatsword.tres",
}

static var _cache := {}


static func _item(tier: int, kind: String) -> ItemData:
	tier = clampi(tier, 0, LevelCurve.MAX_TIER)
	var key := "%s_%s" % [LevelCurve.TIER_KEYS[tier], kind]
	if _cache.has(key):
		return _cache[key]
	var path: String = LEGACY.get(key, DIR + key + ".tres")
	var item: ItemData = null
	if ResourceLoader.exists(path):
		item = load(path) as ItemData
	else:
		push_warning("ItemCatalog: %s does not exist. Run tools/generate_content.py or copy the Weapons folder." % path)
	_cache[key] = item
	return item


## A weapon of this kind (see Weapon) and tier (0 = iron). Null if the file is missing.
static func get_weapon(kind: int, tier: int) -> ItemData:
	return _item(tier, WEAPON_KINDS[kind])


static func get_shield(tier: int) -> ItemData:
	return _item(tier, "shield")


static func get_chest(tier: int) -> ItemData:
	return _item(tier, "chestplate")


## Chances for a chest holding gear that suits levels level_min..level_max: mostly the tier of the
## middle of the range, some of the tier below, a little of the tier above if the range reaches it.
## quality scales every chance (a boss chest uses more than 1).
static func curve_loot(level_min: int, level_max: int, quality: float = 1.0) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	var lo := mini(level_min, level_max)
	var hi := maxi(level_min, level_max)
	var tier := LevelCurve.tier_for_level((lo + hi) / 2)
	for t in [tier - 1, tier, tier + 1]:
		if t < 0 or t > LevelCurve.MAX_TIER:
			continue
		var weight := 1.0
		if t < tier:
			weight = 0.6
		elif t > tier:
			if hi < LevelCurve.TIER_MIN_LEVEL[t]:
				continue
			weight = 0.25
		for k in WEAPON_KINDS.size():
			_add(out, get_weapon(k, t), 0.12 * weight * quality)
		_add(out, get_shield(t), 0.10 * weight * quality)
		_add(out, get_chest(t), 0.10 * weight * quality)
	return out


## What an enemy of this level may carry besides what it wields (0 quality = nothing)
static func enemy_loot(level: int, quality: float) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	if quality <= 0.0:
		return out
	var tier := LevelCurve.tier_for_level(level)
	for k in WEAPON_KINDS.size():
		_add(out, get_weapon(k, tier), 0.04 * quality)
	_add(out, get_chest(tier), 0.05 * quality)
	_add(out, get_shield(tier), 0.04 * quality)
	return out


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
