extends SceneTree
## Makes the item files of the magic and crafting update (stage 10). Run with:
##   godot --headless --path . -s res://tools/generate_stage10.gd
## Writes:
##   scripts/Resources/Materials/    ore, ingots, leather, pelts, the pickaxe, raw food for cooking
##   scripts/Resources/SoulGems/     five sizes, empty and filled
##   scripts/Resources/Books/        a spell tome for every spell in SpellCatalog
##   scripts/Resources/Ingredients/  four new herbs; every ingredient gets its 4 alchemy effects
##   scripts/Resources/Consumables/  cooked meals with magic effects (buffs)
##   scripts/Resources/Merchants/mages.tres   the Mages Guild's shop
## Like generate_content.gd, an existing file is loaded and only these fields are set.

const RES := "res://data/"
const MAT := RES + "materials/"


func _initialize() -> void:
	for d in ["materials", "soul_gems", "books"]:
		DirAccess.make_dir_recursive_absolute(RES + d)
	_materials()
	_soul_gems()
	_tomes()
	_ingredients()
	_foods()
	_merchant()
	print("stage 10 content written")
	quit()


func _item(path: String) -> ItemData:
	if ResourceLoader.exists(path):
		var it := load(path) as ItemData
		if it != null:
			return it
	return ItemData.new()


func _save(it: ItemData, path: String) -> void:
	var err := ResourceSaver.save(it, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])


func _mat(id: String, name: String, desc: String, weight: float, value: int, tags: Array = [], type: int = ItemData.ItemType.MATERIAL) -> void:
	var path := MAT + id + ".tres"
	var it := _item(path)
	it.id = StringName(id)
	it.display_name = name
	it.description = desc
	it.item_type = type as ItemData.ItemType
	it.weight = weight
	it.value = value
	it.stackable = type != ItemData.ItemType.TOOL
	it.max_stack = 999 if it.stackable else 1
	it.loot_tags = PackedStringArray(tags)
	_save(it, path)


func _materials() -> void:
	var ores := [["iron_ore", "Iron Ore", 4], ["corundum_ore", "Corundum Ore", 6], ["silver_ore", "Silver Ore", 12],
		["gold_ore", "Gold Ore", 20], ["obsidian_ore", "Obsidian Ore", 18], ["ebony_ore", "Ebony Ore", 35],
		["dragonstone_ore", "Dragonstone Ore", 60], ["star_ore", "Star Ore", 90]]
	for o in ores:
		_mat(o[0], o[1], "Raw ore. Smelt it into ingots at a smelter.", 1.0, o[2], ["smithy", "mine"])
	var ingots := [["iron_ingot", "Iron Ingot", 8], ["steel_ingot", "Steel Ingot", 16], ["silver_ingot", "Silver Ingot", 30],
		["gold_ingot", "Gold Ingot", 50], ["obsidian_shard", "Refined Obsidian", 45], ["ebon_ingot", "Ebon Ingot", 90],
		["dragonbone_plate", "Dragonbone Plate", 150], ["starmetal_ingot", "Starmetal Ingot", 220]]
	for i in ingots:
		_mat(i[0], i[1], "Forge weapons and armor from it, or improve gear of its kind at a grindstone or workbench.", 1.0, i[2], ["smithy"])
	_mat("animal_hide", "Animal Hide", "Tan it into leather at a tanning rack.", 2.0, 5, ["smithy", "hunter"])
	_mat("wolf_pelt", "Wolf Pelt", "Tan it into leather at a tanning rack.", 2.0, 8, ["hunter"])
	_mat("bear_pelt", "Bear Pelt", "A heavy pelt. Tans into three pieces of leather.", 6.0, 30, ["hunter"])
	_mat("leather", "Leather", "Light armor is made of it. Cut it into strips at a tanning rack.", 2.0, 10, ["smithy"])
	_mat("leather_strips", "Leather Strips", "Every weapon and armor piece needs a few for grips and straps.", 0.1, 3, ["smithy"])
	_mat("pickaxe", "Pickaxe", "Needed to mine ore veins in the rocks.", 8.0, 25, ["smithy", "mine"], ItemData.ItemType.TOOL)
	var food := [["raw_meat", "Raw Meat", 3], ["raw_fish", "Raw Fish", 3], ["potato", "Potato", 1], ["carrot", "Carrot", 1],
		["cabbage", "Cabbage", 2], ["leek", "Leek", 1], ["flour", "Sack of Flour", 2], ["salt", "Salt Pile", 2],
		["butter", "Butter", 3], ["egg", "Egg", 1], ["milk", "Jug of Milk", 2], ["honey", "Honey Jar", 4]]
	for f in food:
		_mat(f[0], f[1], "Something to cook with at a cooking pot.", 0.3, f[2], ["kitchen"])


func _soul_gems() -> void:
	var values := [20, 45, 80, 150, 300]
	for i in 5:
		for filled in [false, true]:
			var id: String = SoulGems.SIZES[i] + "_soul_gem" + ("_filled" if filled else "")
			var path: String = SoulGems.DIR + id + ".tres"
			var it := _item(path)
			it.id = StringName(id)
			it.display_name = "%s Soul Gem%s" % [SoulGems.NAMES[i], " (Filled)" if filled else ""]
			it.description = "A crystal that can hold a soul. Filled ones power enchanting and recharge enchanted weapons." if filled else "An empty soul gem. Cast Soul Trap on a creature and kill it to fill this."
			it.item_type = ItemData.ItemType.SOUL_GEM
			it.soul_gem_size = i + 1
			it.soul_filled = filled
			it.weight = 0.5
			it.value = values[i] * (3 if filled else 1)
			it.stackable = true
			it.max_stack = 99
			it.loot_tags = PackedStringArray(["mage", "crypt"])
			_save(it, path)


func _tomes() -> void:
	for id in SpellCatalog.tome_ids():
		var s := SpellCatalog.get_spell(id)
		var rank := SpellCatalog.rank_of(id)
		var path := SpellCatalog.TOME_DIR + "tome_" + id + ".tres"
		var it := _item(path)
		it.id = StringName("tome_" + id)
		it.display_name = "Spell Tome: %s" % s.display_name
		it.description = "%s %s spell. Read it to learn the spell." % [SpellCatalog.RANK_NAMES[rank], MagicEffects.SCHOOL_NAMES.get(s.get_school(), "")]
		it.item_type = ItemData.ItemType.BOOK
		it.teaches_spell = id
		it.weight = 1.0
		it.value = [30, 90, 240, 520, 1100][rank]
		it.loot_tags = PackedStringArray(["mage", "library"])
		_save(it, path)


func _ingredients() -> void:
	var new_ones := {"red_mountain_flower": "Red Mountain Flower", "juniper_berries": "Juniper Berries",
		"cactus_flower": "Cactus Flower", "wild_garlic": "Wild Garlic", "spider_egg": "Spider Egg",
		"river_scale": "River Scale", "hawk_feather": "Hawk Feather", "storm_crystal": "Storm Crystal", "mandrake_root": "Mandrake Root"}
	for id in Alchemy.INGREDIENTS:
		var path: String = RES + "ingredients/" + id + ".tres"
		var it := _item(path)
		if it.display_name == "":
			it.display_name = new_ones.get(id, String(id).capitalize())
			it.description = "An alchemical ingredient. Alchemists buy it."
			it.weight = 0.1
			it.value = 4
			it.stackable = true
			it.max_stack = 999
			it.loot_tags = PackedStringArray(["alchemy", "kitchen"])
		it.id = StringName(id)
		it.item_type = ItemData.ItemType.INGREDIENT
		it.ingredient_effects = PackedStringArray(Alchemy.INGREDIENTS[id])
		_save(it, path)


func _food(id: String, name: String, desc: String, value: int, effects: Array, verb: String = "Eat") -> void:
	var path := RES + "consumables/" + id + ".tres"
	var it := _item(path)
	it.id = StringName(id)
	it.display_name = name
	it.description = desc
	it.item_type = ItemData.ItemType.CONSUMABLE
	it.weight = 0.5
	it.value = value
	it.stackable = true
	it.max_stack = 99
	it.use_verb = verb
	it.effect_group = "food"
	it.effect_duration = 1.0
	var list: Array[Dictionary] = []
	for e in effects:
		list.append({"id": StringName(e[0]), "mag": float(e[1]), "dur": float(e[2])})
	it.magic_effects = list
	it.loot_tags = PackedStringArray(["kitchen", "tavern"])
	_save(it, path)


func _foods() -> void:
	_food("vegetable_soup", "Vegetable Soup", "Warm and filling.", 12, [["restore_stamina", 30, 0], ["regenerate_stamina", 25, 300]])
	_food("grilled_leeks", "Grilled Leeks", "Simple and salty.", 6, [["restore_health", 15, 0]])
	_food("garlic_bread", "Garlic Bread", "Keeps the sickness away, they say.", 10, [["resist_poison", 25, 300], ["restore_health", 15, 0]])
	_food("fish_stew", "Fish Stew", "A sailor's supper.", 16, [["regenerate_magicka", 30, 600]])
	_food("mushroom_soup", "Mushroom Soup", "Glowcaps in milk. Sharpens the mind.", 18, [["fortify_wisdom", 5, 600], ["restore_magicka", 30, 0]])
	_food("meat_pie", "Meat Pie", "Heavy and good.", 20, [["fortify_health", 25, 600]])
	_food("apple_pie", "Apple Pie", "Sweet and golden.", 22, [["fortify_stamina", 30, 600]])
	_food("honey_cake", "Honey Cake", "A treat for a feast day.", 26, [["fortify_magicka", 30, 600]])
	_food("spiced_wine", "Spiced Wine", "Warms you through on a cold night.", 24, [["resist_frost", 40, 600]], "Drink")


func _merchant() -> void:
	var path := RES + "merchants/mages.tres"
	var m: MerchantData = load(path) as MerchantData if ResourceLoader.exists(path) else MerchantData.new()
	m.id = &"mages"
	m.display_name = "Mages Guild Supplies"
	m.buys = PackedStringArray(["ingredient", "consumable", "book", "soul_gem", "misc"])
	m.sell_rate = 0.5
	m.markup = 1.2
	m.gold_min = 500
	m.gold_max = 1000
	m.restock_days = 3
	ResourceSaver.save(m, path)
