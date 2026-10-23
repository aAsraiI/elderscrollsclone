class_name Recipes
extends RefCounted
## Every recipe at every workstation, built in code from the item files (like ItemCatalog):
##   forge         weapons and armor of every tier from ingots and leather strips (Smithing)
##   smelter       ore into ingots (Smithing)
##   tanning_rack  pelts into leather, leather into strips (Smithing)
##   workbench     lockpicks, pickaxes, rings and amulets (Tinkering)
##   cooking_pot   meals from raw food (Cooking)
## A recipe: {"id", "station", "result": path, "count", "inputs": [[path, n], ...], "skill", "level", "xp"}
## Improving weapons (grindstone) and armor (workbench) is not a recipe: see improve_cost().

const MAT := "res://data/materials/"
const FOOD := "res://data/consumables/"
const ING := "res://data/ingredients/"
const STATIONS := {
	"forge": "Forge", "smelter": "Smelter", "tanning_rack": "Tanning Rack", "workbench": "Workbench",
	"grindstone": "Grindstone", "cooking_pot": "Cooking Pot", "alchemy_lab": "Alchemy Lab",
	"enchanter": "Arcane Enchanter", "spell_altar": "Altar of Spellmaking",
}
## The ingot each gear tier is forged from (heavy armor and weapons)
const TIER_INGOT: Array[String] = ["iron_ingot", "steel_ingot", "silver_ingot", "obsidian_shard", "ebon_ingot", "dragonbone_plate", "starmetal_ingot"]
## Smithing level needed for each tier
const TIER_LEVEL: Array[int] = [1, 15, 30, 45, 60, 75, 90]

static var _all: Array[Dictionary] = []


static func for_station(station: String) -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for r in _all:
		if r["station"] == station:
			out.append(r)
	return out


static func all() -> Array[Dictionary]:
	_ensure()
	return _all


static func load_item(path: String) -> ItemData:
	return load(path) as ItemData if ResourceLoader.exists(path) else null


static func _ensure() -> void:
	if not _all.is_empty():
		return
	# ---- smelter
	_add("smelter", MAT + "iron_ingot.tres", 1, [["iron_ore", 2]], 1)
	_add("smelter", MAT + "steel_ingot.tres", 1, [["iron_ore", 1], ["corundum_ore", 1]], 10)
	_add("smelter", MAT + "silver_ingot.tres", 1, [["silver_ore", 2]], 20)
	_add("smelter", MAT + "gold_ingot.tres", 1, [["gold_ore", 2]], 25)
	_add("smelter", MAT + "obsidian_shard.tres", 1, [["obsidian_ore", 2]], 40)
	_add("smelter", MAT + "ebon_ingot.tres", 1, [["ebony_ore", 2]], 55)
	_add("smelter", MAT + "dragonbone_plate.tres", 1, [["dragonstone_ore", 2]], 70)
	_add("smelter", MAT + "starmetal_ingot.tres", 1, [["star_ore", 2]], 85)
	# ---- tanning rack
	_add("tanning_rack", MAT + "leather.tres", 1, [["animal_hide", 1]], 1)
	_add("tanning_rack", MAT + "leather.tres", 1, [["wolf_pelt", 1]], 1)
	_add("tanning_rack", MAT + "leather.tres", 3, [["bear_pelt", 1]], 1)
	_add("tanning_rack", MAT + "leather_strips.tres", 4, [["leather", 1]], 1)
	# ---- forge: every weapon and armor piece in every tier
	for tier in LevelCurve.TIER_KEYS.size():
		var ingot: String = TIER_INGOT[tier]
		for k in ItemCatalog.WEAPON_KINDS.size():
			var w := ItemCatalog.get_weapon(k, tier)
			if w != null:
				_forge(w, ingot, tier, false)
		var shield := ItemCatalog.get_shield(tier)
		if shield != null:
			_forge(shield, ingot, tier, false)
		for piece in ItemCatalog.ARMOR_PIECES:
			var heavy := ItemCatalog.get_armor(tier, piece, true)
			if heavy != null:
				_forge(heavy, ingot, tier, false)
			var light := ItemCatalog.get_armor(tier, piece, false)
			if light != null:
				_forge(light, ingot, tier, true)
	# ---- bows (forge) and arrows (forge, 24 at a time)
	for tier in LevelCurve.TIER_KEYS.size():
		var bow := ItemCatalog.get_bow(tier)
		if bow != null:
			_add_path("forge", bow.resource_path, 1, [[MAT + TIER_INGOT[tier] + ".tres", 2], [MAT + "leather_strips.tres", 2]], TIER_LEVEL[tier], "smithing")
		var arrow := ItemCatalog.get_arrow(tier)
		if arrow != null:
			_add_path("forge", arrow.resource_path, 24, [[MAT + TIER_INGOT[tier] + ".tres", 1]], TIER_LEVEL[tier], "smithing")
	# ---- workbench (tinkering)
	_add("workbench", "res://data/misc/lockpick.tres", 5, [["iron_ingot", 1]], 1, "tinkering")
	_add("workbench", MAT + "pickaxe.tres", 1, [["iron_ingot", 2], ["leather_strips", 1]], 1, "tinkering")
	for metal in ["silver", "gold"]:
		for kind in ["ring", "amulet"]:
			for v in ["endurance", "insight", "mule", "vigor", "wind"]:
				var path := "res://data/jewelry/%s_%s_%s.tres" % [metal, kind, v]
				if ResourceLoader.exists(path):
					_add_path("workbench", path, 1, [[MAT + metal + "_ingot.tres", 2 if kind == "amulet" else 1]], 15 if metal == "silver" else 30, "tinkering")
	var gems := ["garnet", "amethyst", "sapphire", "emerald", "ruby"]
	var vi := 0
	for v in ["endurance", "insight", "mule", "vigor", "wind"]:
		for kind in ["ring", "amulet"]:
			var path := "res://data/jewelry/gemmed_%s_%s.tres" % [kind, v]
			if ResourceLoader.exists(path):
				_add_path("workbench", path, 1, [[MAT + "gold_ingot.tres", 1], ["res://data/treasure/%s.tres" % gems[vi % gems.size()], 1]], 45, "tinkering")
		vi += 1
	# ---- cooking pot
	_cook("roast_meat", 1, [["raw_meat", 1]], 1)
	_cook("smoked_fish", 1, [["raw_fish", 1], ["salt", 1]], 1)
	_cook("bread", 2, [["flour", 1], ["salt", 1]], 1)
	_cook("hearty_stew", 1, [["raw_meat", 1], ["potato", 1], ["carrot", 1]], 10)
	_cook("vegetable_soup", 1, [["potato", 1], ["carrot", 1], ["cabbage", 1], ["leek", 1]], 1)
	_cook("grilled_leeks", 1, [["leek", 2], ["salt", 1]], 1)
	_cook("garlic_bread", 1, [["bread", 1], ["butter", 1], [ING + "wild_garlic.tres", 1]], 15)
	_cook("fish_stew", 1, [["raw_fish", 1], ["potato", 1], ["milk", 1], ["salt", 1]], 20)
	_cook("mushroom_soup", 1, [[ING + "glowcap.tres", 2], ["milk", 1], ["salt", 1]], 25)
	_cook("meat_pie", 1, [["raw_meat", 1], ["flour", 1], ["butter", 1], ["potato", 1]], 30)
	_cook("apple_pie", 1, [["apple", 2], ["flour", 1], ["butter", 1], ["honey", 1]], 35)
	_cook("honey_cake", 1, [["flour", 1], ["honey", 1], ["egg", 1], ["butter", 1], ["milk", 1]], 45)
	_cook("spiced_wine", 1, [["wine", 1], ["honey", 1], [ING + "juniper_berries.tres", 1]], 40)
	_cook("venison_feast", 1, [["raw_meat", 2], ["potato", 1], ["leek", 1], ["salt", 1]], 55)


static func _forge(gear: ItemData, ingot: String, tier: int, light: bool) -> void:
	var n := clampi(roundi(gear.weight / (2.0 if light else 4.0)), 1, 6)
	var inputs: Array = []
	if light:
		inputs.append([MAT + "leather.tres", maxi(n, 1)])
		if tier > 1:
			inputs.append([MAT + ingot + ".tres", maxi(n / 2, 1)])
	else:
		inputs.append([MAT + ingot + ".tres", n])
	inputs.append([MAT + "leather_strips.tres", 1 if gear.weight < 8.0 else 2])
	_add_path("forge", gear.resource_path, 1, inputs, TIER_LEVEL[tier], "smithing")


static func _cook(result: String, count: int, inputs: Array, level: int) -> void:
	var fixed: Array = []
	for i in inputs:
		var p: String = i[0]
		if not p.begins_with("res://"):
			p = (FOOD if p in ["bread", "apple", "wine"] else MAT) + p + ".tres"
		fixed.append([p, i[1]])
	_add_path("cooking_pot", FOOD + result + ".tres", count, fixed, level, "cooking")


static func _add(station: String, result: String, count: int, inputs: Array, level: int, skill: String = "smithing") -> void:
	var fixed: Array = []
	for i in inputs:
		var p: String = i[0]
		if not p.begins_with("res://"):
			p = MAT + p + ".tres"
		fixed.append([p, i[1]])
	_add_path(station, result, count, fixed, level, skill)


static func _add_path(station: String, result: String, count: int, inputs: Array, level: int, skill: String) -> void:
	if not ResourceLoader.exists(result):
		return
	var xp := 4.0 + float(level) * 0.35
	for i in inputs:
		xp += float(i[1]) * 1.5
	_all.append({"id": "%s|%s|%d" % [station, result, _all.size()], "station": station, "result": result, "count": count,
		"inputs": inputs, "skill": skill, "level": level, "xp": xp})


# ---------------------------------------------------------------- using them

## How many times you could make it right now (0 = missing something)
static func can_make(r: Dictionary, inv: Inventory) -> int:
	var best := 999
	for i in r["inputs"]:
		var it := load_item(i[0])
		if it == null:
			return 0
		best = mini(best, inv.get_count(it) / int(i[1]))
	return best


static func make(r: Dictionary, player: Node) -> ItemData:
	var inv := player.get_node_or_null("Inventory") as Inventory
	var skills := player.get_node_or_null("Skills") as Skills
	if inv == null or can_make(r, inv) <= 0:
		return null
	if skills != null and skills.get_level(StringName(r["skill"])) < int(r["level"]):
		return null
	for i in r["inputs"]:
		inv.remove_item(load_item(i[0]), int(i[1]))
	var result := load_item(r["result"])
	var count := int(r["count"])
	# Practised cooks and tinkerers sometimes get a little extra
	if skills != null and r["skill"] in ["cooking", "tinkering"] and randf() < float(skills.get_level(StringName(r["skill"]))) * 0.006:
		count += 1
	inv.add_item(result, count)
	if skills != null:
		skills.add_xp(StringName(r["skill"]), float(r["xp"]))
	return result


# ---------------------------------------------------------------- improving

## Weapons at the grindstone, armor at the workbench
static func can_improve_at(item: ItemData, station: String) -> bool:
	if item == null or item.tier <= 0:
		return false
	if station == "grindstone":
		return item.item_type == ItemData.ItemType.WEAPON
	return item.item_type == ItemData.ItemType.ARMOR and item.stat_modifiers.has("armor")


## The best quality your Smithing allows (1 per 15 levels, +1 with Fortify Smithing over 25%)
static func max_quality(player: Node) -> int:
	var skills := player.get_node_or_null("Skills") as Skills
	var stats := player.get_node_or_null("Stats") as Stats
	var q := 1 + (skills.get_level(&"smithing") if skills != null else 1) / 15
	if stats != null and stats.get_stat("smithing_potency") >= 0.25:
		q += 1
	return clampi(q, 1, 6)


## What one more quality level costs: [[ingot path, n]]
static func improve_cost(item: ItemData) -> Array:
	var tier := clampi(item.tier - 1, 0, 6)
	var light := item.governing_skill == "light_armor"
	var mat := (MAT + "leather.tres") if light and tier <= 1 else (MAT + TIER_INGOT[tier] + ".tres")
	return [[mat, 1 + item.quality / 2]]


static func improve(player: Node, item: ItemData) -> ItemData:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or item == null or not inv.has_item(item) or item.quality >= max_quality(player):
		return null
	var cost := improve_cost(item)
	for c in cost:
		var it := Recipes.load_item(c[0])
		if it == null or inv.get_count(it) < int(c[1]):
			return null
	for c in cost:
		inv.remove_item(Recipes.load_item(c[0]), int(c[1]))
	var eq := player.get_node_or_null("Equipment") as Equipment
	var was_worn := eq != null and eq.is_equipped(item)
	if eq != null:
		eq.unequip_item(item)
	inv.remove_item(item, 1)
	var rec := CraftedItems.record_of(item)
	var better := CraftedItems.gear(item, item.quality + 1, rec.get("enchant", []), float(rec.get("charge", 0.0)), String(rec.get("name", "")))
	if not rec.is_empty():
		var key := "crafted/" + String(better.get_meta("crafted_id"))
		var r2 := WorldState.get_record(key).duplicate()
		r2["max_charge"] = rec.get("max_charge", 0.0)
		WorldState.set_record(key, r2)
	inv.add_item(better, 1)
	if was_worn:
		eq.equip(better)
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_xp(&"smithing", 8.0 + float(item.tier) * 3.0)
	return better
