class_name CraftStock
extends RefCounted
## Where crafting materials come from besides mining and picking: what animals drop, and what each
## kind of merchant sells (on top of their MerchantData stock, see Barter._restock).

const MAT := "res://data/materials/"
const ING := "res://data/ingredients/"
const FOOD := "res://data/consumables/"


static func _e(path: String, chance: float, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.item = load(path) as ItemData if ResourceLoader.exists(path) else null
	e.chance = chance
	e.min_count = lo
	e.max_count = hi
	return e


## Pelts, meat and other parts a creature leaves on its body
static func creature_drops(key: String, level: int) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	match key:
		"wolf":
			out = [_e(MAT + "wolf_pelt.tres", 0.9, 1, 1), _e(MAT + "raw_meat.tres", 0.8, 1, 2)]
		"frost_bear":
			out = [_e(MAT + "bear_pelt.tres", 0.95, 1, 1), _e(MAT + "raw_meat.tres", 0.9, 2, 4)]
		"giant_rat":
			out = [_e(MAT + "animal_hide.tres", 0.5, 1, 1), _e(MAT + "raw_meat.tres", 0.4, 1, 1)]
		"dune_stalker":
			out = [_e(MAT + "animal_hide.tres", 0.9, 1, 2), _e(MAT + "raw_meat.tres", 0.6, 1, 2)]
		"deep_crawler", "crawler_queen":
			out = [_e(ING + "crawler_eye.tres", 0.6, 1, 2), _e(ING + "venom_sac.tres", 0.5, 1, 1), _e(ING + "spider_egg.tres", 0.5, 1, 2)]
		"fire_spirit":
			out = [_e(ING + "fire_salts.tres", 0.9, 1, 2)]
		"vault_sentinel", "vault_guardian":
			out = [_e(ING + "storm_crystal.tres", 0.6, 1, 2)]
		"ice_wraith":
			out = [_e(ING + "frost_mirriam.tres", 0.3, 1, 1), _e(ING + "void_salt.tres", 0.4, 1, 1)]
		"skeleton", "skeleton_knight":
			out = [_e(ING + "bone_meal.tres", 0.8, 1, 2)]
		"ash_cultist", "ashen_priest", "barrow_wight", "wight_lord":
			out = [_e(SoulGems.DIR + "petty_soul_gem.tres", 0.3, 1, 1), _e(SoulGems.DIR + "lesser_soul_gem.tres", 0.15, 1, 1)]
	if level >= 20 and key in ["ash_cultist", "ashen_priest", "wight_lord"]:
		out.append(_e(SoulGems.DIR + "common_soul_gem.tres", 0.2, 1, 1))
	return out.filter(func(e: LootEntry) -> bool: return e.item != null)


## Extra stock for a merchant (by MerchantData id)
static func extra_for(merchant_id: String, _level_min: int, level_max: int) -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	match merchant_id:
		"smith":
			for k in ["iron_ingot", "steel_ingot", "leather", "leather_strips", "iron_ore", "corundum_ore"]:
				out.append(_e(MAT + k + ".tres", 0.8, 2, 6))
			out.append(_e(MAT + "pickaxe.tres", 0.9, 1, 1))
			if level_max >= 15:
				out.append(_e(MAT + "silver_ingot.tres", 0.6, 1, 4))
			if level_max >= 28:
				out.append(_e(MAT + "obsidian_shard.tres", 0.5, 1, 3))
			if level_max >= 41:
				out.append(_e(MAT + "ebon_ingot.tres", 0.4, 1, 2))
			if level_max >= 56:
				out.append(_e(MAT + "dragonbone_plate.tres", 0.25, 1, 2))
			out.append(_e(MAT + "animal_hide.tres", 0.5, 1, 3))
			out.append(_e(ItemCatalog.RANGED_DIR + "hunting_bow.tres", 0.7, 1, 1))
			var tb := LevelCurve.tier_for_level(level_max)
			if ItemCatalog.get_bow(tb) != null:
				out.append(_e(ItemCatalog.get_bow(tb).resource_path, 0.4, 1, 1))
			for t in range(0, tb + 1):
				if ItemCatalog.get_arrow(t) != null:
					out.append(_e(ItemCatalog.get_arrow(t).resource_path, 0.8, 20, 50))
		"general", "provisioner":
			for k in ["raw_meat", "raw_fish", "potato", "carrot", "cabbage", "leek", "flour", "salt", "butter", "egg", "milk", "honey"]:
				out.append(_e(MAT + k + ".tres", 0.7, 1, 5))
			out.append(_e(ING + "river_scale.tres", 0.4, 1, 3))
			out.append(_e(ING + "hawk_feather.tres", 0.4, 1, 3))
			out.append(_e(MAT + "pickaxe.tres", 0.4, 1, 1))
			out.append(_e("res://data/misc/empty_bottle.tres", 0.7, 2, 6))
			out.append(_e("res://data/misc/horse_deed.tres", 0.6 if merchant_id == "provisioner" else 0.3, 1, 1))
			out.append(_e(ItemCatalog.RANGED_DIR + "iron_arrow.tres", 0.6, 15, 40))
			out.append(_e(MAT + "leather.tres", 0.4, 1, 3))
			out.append(_e(SoulGems.DIR + "petty_soul_gem.tres", 0.3, 1, 2))
		"innkeeper":
			for k in ["raw_meat", "potato", "salt", "milk", "egg", "flour"]:
				out.append(_e(MAT + k + ".tres", 0.6, 1, 4))
			out.append(_e("res://data/misc/sellsword_contract.tres", 0.9, 1, 2))
		"alchemy":
			for id in Alchemy.INGREDIENTS:
				out.append(_e(ING + id + ".tres", 0.45, 1, 4))
			for id in SpellCatalog.ids_for(&"restoration", 2):
				out.append(_e(SpellCatalog.TOME_DIR + "tome_" + id + ".tres", 0.25, 1, 1))
			out.append(_e(SoulGems.DIR + "petty_soul_gem.tres", 0.5, 1, 3))
			out.append(_e(SoulGems.DIR + "lesser_soul_gem.tres", 0.3, 1, 2))
		"temple":
			for id in SpellCatalog.ids_for(&"restoration", 3):
				out.append(_e(SpellCatalog.TOME_DIR + "tome_" + id + ".tres", 0.4, 1, 1))
		"jeweler":
			for k in ["silver_ingot", "gold_ingot"]:
				out.append(_e(MAT + k + ".tres", 0.6, 1, 4))
			for s in ["petty", "lesser", "common", "greater"]:
				out.append(_e(SoulGems.DIR + s + "_soul_gem.tres", 0.35, 1, 2))
		"mages":
			var max_rank := clampi(level_max / 15, 1, 4)
			for id in SpellCatalog.tome_ids():
				if SpellCatalog.rank_of(id) <= max_rank:
					out.append(_e(SpellCatalog.TOME_DIR + "tome_" + id + ".tres", 0.5 if SpellCatalog.rank_of(id) <= 1 else 0.3, 1, 1))
			for s in ["petty", "lesser", "common", "greater", "grand"]:
				out.append(_e(SoulGems.DIR + s + "_soul_gem.tres", 0.6 - 0.1 * ["petty", "lesser", "common", "greater", "grand"].find(s), 1, 3))
			out.append(_e(FOOD + "magicka_potion.tres", 0.6, 1, 3))
	return out.filter(func(e: LootEntry) -> bool: return e.item != null)
