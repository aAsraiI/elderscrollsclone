extends SceneTree
## Generates the game's item files (.tres) from the tables below. Run with:
##   godot --headless --path . -s res://tools/generate_content.gd
## (replaces tools/generate_content.py, which needed Python).
##
## It writes:
##   scripts/Resources/Weapons/      8 weapon kinds and the shield, in 7 tiers (+ heavy cuirasses)
##   scripts/Resources/Armor/        the other heavy pieces and every light piece, 7 tiers
##   scripts/Resources/Jewelry/      wearable rings and amulets
##   scripts/Resources/Clothing/     clothes (no armor)
##   scripts/Resources/Clutter/      things that sit on tables and shelves
##   scripts/Resources/Ingredients/  herbs, mushrooms, monster parts
##   scripts/Resources/Artifacts/    ancient relics for the Antiquarian Society
##   scripts/Resources/Consumables/  the new potions and foods (old ones are left alone)
##
## A file that already exists is LOADED and only the fields below are set, so anything you set by
## hand that this tool does not own (a View Scene, a World Scene, an icon) survives a rerun.
## Iron gear and the Steel Greatsword keep their old paths in scripts/Resources/ (saves use paths).

const RES := "res://data/"
const TIER_KEYS := LevelCurve.TIER_KEYS
const TIER_NAMES := LevelCurve.TIER_NAMES
const LIGHT_KEYS := LevelCurve.LIGHT_KEYS
const LIGHT_NAMES := LevelCurve.LIGHT_NAMES
const TIER_MIN_LEVEL := LevelCurve.TIER_MIN_LEVEL
const DAMAGE_MULT := [1.0, 1.5, 2.1, 2.9, 3.9, 5.2, 7.4]
const VALUE_MULT := [1.0, 2.5, 6.0, 14.0, 32.0, 75.0, 170.0]
const WEIGHT_MULT := [1.0, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25]
const POISE_MULT := [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6]
const STAMINA_MULT := [1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3]
const SHIELD_ARMOR := [10, 13, 17, 21, 26, 31, 37]
## Armor of a full HEAVY set per tier; light is LIGHT_ARMOR of that. Shield armor comes on top.
const SET_ARMOR := [30, 38, 46, 54, 62, 70, 78]
const LIGHT_ARMOR := 0.65
const LIGHT_WEIGHT := 0.4
const TIER_FLAVOR := [
	"Plain, sturdy iron.",
	"Well-forged steel with a keen edge.",
	"Silvered steel that gleams even in the dark.",
	"Volcanic glass ground to a razor edge, tougher than it looks.",
	"Blackened ebon steel, cold to the touch.",
	"Carved from the bones of great wyrms.",
	"Forged from fallen star-metal that hums faintly.",
]
const LIGHT_FLAVOR := [
	"Stitched animal hide.",
	"Boiled and hardened leather.",
	"Cloth woven with silver thread, light as silk.",
	"Overlapping scales of dark volcanic glass.",
	"Ebon rings woven fine as cloth.",
	"Shed scales of a dragon, still warm.",
	"Star-metal spun into thread.",
]

# Iron-tier numbers. heavy = [charge, windup, damage x, stamina x, poise x, reach bonus]
const WEAPONS := {
	"sword": {"name": "Sword", "desc": "A balanced blade. Swings in an arc and can hit several enemies. Tap to chain a combo, hold to charge a heavy attack.",
		"weight": 5.0, "value": 25, "skill": "one_handed", "aset": "sword", "damage": 10.0, "reach": 2.2, "style": 1, "arc": 100.0,
		"cooldown": 0.7, "windup": 0.12, "active": 0.14, "stamina": 6.0, "knock": 2.5, "poise": 15.0, "combo": 3,
		"heavy": [0.45, 0.18, 1.7, 2.0, 2.0, 0.3]},
	"dagger": {"name": "Dagger", "desc": "Quick and light. Carry two and wield one in each hand. Low stagger, but long combos.",
		"weight": 1.5, "value": 15, "skill": "one_handed", "aset": "dagger", "damage": 6.0, "reach": 1.6, "style": 0,
		"cooldown": 0.35, "windup": 0.05, "active": 0.12, "stamina": 3.0, "knock": 1.0, "poise": 8.0, "combo": 4, "dual": true,
		"heavy": [0.4, 0.12, 1.5, 2.0, 1.5, 0.2]},
	"greatsword": {"name": "Greatsword", "desc": "Two-handed. Slow, with a long reach and a wide swing. One clean hit staggers most foes.",
		"weight": 14.0, "value": 70, "skill": "two_handed", "aset": "greatsword", "damage": 18.0, "reach": 3.2, "style": 1, "arc": 130.0,
		"cooldown": 1.4, "windup": 0.35, "active": 0.22, "stamina": 14.0, "knock": 4.0, "poise": 40.0, "combo": 2, "two_handed": true,
		"heavy": [0.6, 0.25, 1.7, 2.0, 1.6, 0.4]},
	"warhammer": {"name": "Warhammer", "desc": "Two-handed. Strikes one target and staggers hard. Right click to slam the ground and hurt everything nearby.",
		"weight": 18.0, "value": 60, "skill": "two_handed", "aset": "hammer", "damage": 16.0, "reach": 2.4, "style": 0,
		"cooldown": 1.1, "windup": 0.3, "active": 0.16, "stamina": 12.0, "knock": 5.0, "poise": 35.0, "combo": 2, "two_handed": true,
		"heavy": [0.55, 0.22, 1.8, 2.0, 1.8, 0.3], "slam": [4.0, 0.5, 25.0, 1.6, 3.5]},
	"waraxe": {"name": "War Axe", "desc": "A one-handed axe. A little quicker than a sword and bites deeper, with a shorter arc.",
		"weight": 7.0, "value": 30, "skill": "one_handed", "aset": "axe", "damage": 11.0, "reach": 2.0, "style": 1, "arc": 80.0,
		"cooldown": 0.62, "windup": 0.11, "active": 0.13, "stamina": 6.5, "knock": 2.0, "poise": 18.0, "combo": 3,
		"heavy": [0.45, 0.18, 1.7, 2.0, 2.0, 0.3]},
	"mace": {"name": "Mace", "desc": "A one-handed club of metal. Slow, but it crushes through armor and staggers hard.",
		"weight": 10.0, "value": 35, "skill": "one_handed", "aset": "mace", "damage": 12.0, "reach": 2.0, "style": 0,
		"cooldown": 0.85, "windup": 0.18, "active": 0.14, "stamina": 8.0, "knock": 3.5, "poise": 28.0, "combo": 2, "pierce": 0.25,
		"heavy": [0.5, 0.2, 1.8, 2.0, 2.0, 0.2]},
	"spear": {"name": "Spear", "desc": "Two-handed. The longest reach of any weapon and quick thrusts, but it only hits one foe at a time.",
		"weight": 9.0, "value": 45, "skill": "two_handed", "aset": "spear", "damage": 14.0, "reach": 3.0, "style": 0,
		"cooldown": 0.8, "windup": 0.14, "active": 0.15, "stamina": 8.0, "knock": 3.0, "poise": 20.0, "combo": 3, "two_handed": true,
		"heavy": [0.5, 0.18, 1.7, 2.0, 1.8, 0.6]},
	"battleaxe": {"name": "Battleaxe", "desc": "Two-handed. The heaviest hits and the widest swing, at the slowest speed.",
		"weight": 20.0, "value": 75, "skill": "two_handed", "aset": "battleaxe", "damage": 20.0, "reach": 2.8, "style": 1, "arc": 140.0,
		"cooldown": 1.5, "windup": 0.38, "active": 0.24, "stamina": 16.0, "knock": 4.5, "poise": 42.0, "combo": 2, "two_handed": true,
		"heavy": [0.65, 0.26, 1.7, 2.0, 1.6, 0.3]},
	"shortsword": {"name": "Shortsword", "desc": "A short blade, quick in close quarters. Lighter and faster than a sword, with a shorter reach.",
		"weight": 4.0, "value": 20, "skill": "one_handed", "aset": "sword", "damage": 8.0, "reach": 1.9, "style": 1, "arc": 90.0,
		"cooldown": 0.55, "windup": 0.09, "active": 0.12, "stamina": 4.5, "knock": 1.8, "poise": 11.0, "combo": 3,
		"heavy": [0.42, 0.16, 1.6, 2.0, 2.0, 0.25]},
	"club": {"name": "Club", "desc": "A heavy cudgel bound with metal. Cheap and brutal: it staggers well, but bites shallow.",
		"weight": 7.0, "value": 12, "skill": "one_handed", "aset": "mace", "damage": 9.0, "reach": 1.9, "style": 0,
		"cooldown": 0.75, "windup": 0.15, "active": 0.13, "stamina": 6.0, "knock": 3.0, "poise": 22.0, "combo": 2,
		"heavy": [0.48, 0.2, 1.8, 2.0, 2.0, 0.2]},
	"halberd": {"name": "Halberd", "desc": "Two-handed. An axe blade on a long pole: the reach of a spear with a wide, heavy sweep.",
		"weight": 16.0, "value": 65, "skill": "two_handed", "aset": "spear", "damage": 17.0, "reach": 3.0, "style": 1, "arc": 110.0,
		"cooldown": 1.25, "windup": 0.32, "active": 0.2, "stamina": 13.0, "knock": 4.0, "poise": 34.0, "combo": 2, "two_handed": true,
		"heavy": [0.58, 0.24, 1.7, 2.0, 1.7, 0.4]},
}

## piece -> [heavy name, light name, slot, share of the set's armor, heavy weight, value share]
const PIECES := {
	"helmet": ["Helmet", "Hood", ItemData.EquipSlot.HEAD, 0.15, 5.0, 0.15],
	"cuirass": ["Cuirass", "Armor", ItemData.EquipSlot.CHEST, 0.45, 15.0, 0.45],
	"gauntlets": ["Gauntlets", "Bracers", ItemData.EquipSlot.HANDS, 0.10, 3.0, 0.10],
	"greaves": ["Greaves", "Leggings", ItemData.EquipSlot.LEGS, 0.20, 8.0, 0.20],
	"boots": ["Boots", "Boots", ItemData.EquipSlot.FEET, 0.10, 4.0, 0.10],
}

const LEGACY := {
	"iron_sword": "weapons/iron_sword.tres", "iron_dagger": "weapons/iron_dagger.tres", "iron_warhammer": "weapons/iron_warhammer.tres",
	"iron_shield": "weapons/iron_shield.tres", "iron_chestplate": "weapons/iron_chestplate.tres", "steel_greatsword": "weapons/steel_greatsword.tres",
}

## grade -> [name, min level, tier, ring value]
const GRADES := [["Copper", 1, 1, 60], ["Silver", 15, 3, 180], ["Gold", 35, 5, 500], ["Gemmed", 60, 7, 1400]]
## effect key -> [name, stat, amounts per grade]
const JEWEL_EFFECTS := {
	"vigor": ["Vigor", "max_health", [10, 20, 35, 55]],
	"insight": ["Insight", "max_magicka", [10, 20, 35, 55]],
	"endurance": ["Endurance", "max_stamina", [10, 20, 35, 55]],
	"mule": ["the Mule", "carry_capacity", [15, 30, 50, 80]],
	"wind": ["Second Wind", "stamina_regen_mult", [0.1, 0.2, 0.35, 0.5]],
}

## key -> [name, slot, weight, value, tags]
const CLOTHING := {
	"linen_shirt": ["Linen Shirt", ItemData.EquipSlot.CHEST, 1.0, 3, ["home", "clothes"]],
	"fine_tunic": ["Fine Tunic", ItemData.EquipSlot.CHEST, 1.0, 25, ["rich_home", "shop", "clothes"]],
	"plain_robe": ["Plain Robe", ItemData.EquipSlot.CHEST, 1.5, 8, ["temple", "home", "clothes"]],
	"scholar_robe": ["Scholar's Robe", ItemData.EquipSlot.CHEST, 1.5, 45, ["library", "clothes"]],
	"noble_garb": ["Noble Garb", ItemData.EquipSlot.CHEST, 2.0, 120, ["rich_home", "clothes"]],
	"wool_hood": ["Wool Hood", ItemData.EquipSlot.HEAD, 0.5, 4, ["home", "camp", "clothes"]],
	"felt_cap": ["Felt Cap", ItemData.EquipSlot.HEAD, 0.5, 6, ["home", "tavern", "clothes"]],
	"shoes": ["Shoes", ItemData.EquipSlot.FEET, 1.0, 4, ["home", "clothes"]],
	"fine_boots": ["Fine Boots", ItemData.EquipSlot.FEET, 1.5, 30, ["rich_home", "shop", "clothes"]],
	"wool_gloves": ["Wool Gloves", ItemData.EquipSlot.HANDS, 0.3, 5, ["home", "camp", "clothes"]],
}

## key -> [name, weight, value, tags, junk]
const CLUTTER := {
	"tankard": ["Pewter Tankard", 0.5, 3, ["kitchen", "tavern"], true],
	"plate": ["Clay Plate", 0.5, 1, ["kitchen", "tavern"], true],
	"bowl": ["Wooden Bowl", 0.3, 1, ["kitchen", "home"], true],
	"cup": ["Clay Cup", 0.2, 1, ["kitchen", "tavern"], true],
	"silver_goblet": ["Silver Goblet", 0.5, 25, ["rich_home", "temple", "crypt"], true],
	"candlestick": ["Iron Candlestick", 1.0, 6, ["home", "temple", "crypt", "library"], true],
	"silver_candlestick": ["Silver Candlestick", 1.0, 40, ["rich_home", "temple"], true],
	"old_book": ["Old Book", 1.0, 10, ["library", "home", "rich_home"], true],
	"torn_journal": ["Torn Journal", 0.5, 4, ["library", "camp"], true],
	"blank_scroll": ["Blank Scroll", 0.1, 6, ["library"], true],
	"quill": ["Quill", 0.1, 2, ["library", "shop"], true],
	"inkwell": ["Inkwell", 0.3, 3, ["library", "shop"], true],
	"ledger": ["Merchant Ledger", 1.0, 8, ["shop"], true],
	"bone_dice": ["Bone Dice", 0.1, 5, ["tavern", "camp"], true],
	"lute": ["Lute", 4.0, 40, ["tavern"], true],
	"broom": ["Broom", 2.0, 1, ["home"], true],
	"bucket": ["Bucket", 2.0, 2, ["home", "mine"], true],
	"pickaxe": ["Pickaxe", 10.0, 12, ["mine", "smithy", "tools"], false],
	"shovel": ["Shovel", 6.0, 6, ["mine", "home", "tools"], false],
	"smith_hammer": ["Smith's Hammer", 4.0, 8, ["smithy", "tools"], true],
	"tongs": ["Tongs", 2.0, 5, ["smithy", "tools"], true],
	"iron_ore": ["Iron Ore", 1.0, 5, ["mine", "smithy"], false],
	"silver_ore": ["Silver Ore", 1.0, 15, ["mine"], false],
	"gold_ore": ["Gold Ore", 1.0, 30, ["mine"], false],
	"iron_ingot": ["Iron Ingot", 1.0, 8, ["smithy", "mine"], false],
	"steel_ingot": ["Steel Ingot", 1.0, 15, ["smithy"], false],
	"silver_ingot": ["Silver Ingot", 1.0, 40, ["smithy", "jeweler"], false],
	"gold_ingot": ["Gold Ingot", 1.0, 80, ["jeweler", "rich_home", "vault"], false],
	"wolf_pelt": ["Wolf Pelt", 3.0, 20, ["hunter", "camp"], false],
	"bear_pelt": ["Bear Pelt", 6.0, 50, ["hunter"], false],
	"leather_strips": ["Leather Strips", 0.5, 4, ["smithy", "hunter"], false],
	"rope": ["Coil of Rope", 1.0, 3, ["camp", "mine", "home"], true],
	"old_bone": ["Old Bone", 0.5, 1, ["crypt", "cave"], true],
	"skull": ["Skull", 1.0, 1, ["crypt", "camp", "cave"], true],
	"burial_urn": ["Burial Urn", 3.0, 6, ["crypt", "barrow"], true],
	"grain_sack": ["Grain Sack", 5.0, 2, ["kitchen", "home"], true],
	"fork": ["Iron Fork", 0.1, 1, ["kitchen", "tavern"], true],
	"kitchen_knife": ["Kitchen Knife", 0.3, 2, ["kitchen"], true],
	"spoon": ["Wooden Spoon", 0.1, 1, ["kitchen", "home"], true],
	"ladle": ["Iron Ladle", 0.5, 2, ["kitchen", "tavern"], true],
	"rolling_pin": ["Rolling Pin", 1.0, 2, ["kitchen"], true],
	"shears": ["Shears", 0.5, 6, ["shop", "home"], true],
	"spool": ["Spool of Thread", 0.1, 3, ["shop", "home"], true],
	"cloth_bolt": ["Bolt of Cloth", 4.0, 20, ["shop", "rich_home"], false],
	"pillow": ["Pillow", 0.5, 3, ["home", "rich_home"], true],
	"clay_pitcher": ["Clay Pitcher", 1.0, 3, ["kitchen", "tavern"], true],
	"redware_vase": ["Redware Vase", 1.0, 15, ["rich_home", "shop"], true],
	"clay_pot": ["Clay Pot", 2.0, 4, ["kitchen", "home"], true],
	"wicker_basket": ["Wicker Basket", 1.0, 2, ["home", "shop"], true],
	"hand_drum": ["Hand Drum", 2.0, 18, ["tavern"], true],
	"mortar_pestle": ["Mortar and Pestle", 2.0, 15, ["alchemist"], false],
	"scrap_metal": ["Scrap Metal", 2.0, 4, ["smithy", "mine", "ruin"], false],
	"scrap_wood": ["Scrap Wood", 1.0, 1, ["camp", "home"], true],
	"shackles": ["Iron Shackles", 2.0, 5, ["camp", "crypt"], true],
	"wheat_bundle": ["Wheat Bundle", 1.0, 2, ["kitchen", "home"], true],
	"oil_lamp": ["Oil Lamp", 1.0, 12, ["home", "library"], true],
	"fishing_pole": ["Fishing Pole", 2.0, 6, ["coast", "home"], true],
	"silver_bowl": ["Silver Bowl", 0.5, 30, ["rich_home", "vault"], true],
	"silver_plate": ["Silver Plate", 0.5, 35, ["rich_home", "vault"], true],
	"glass_goblet": ["Glass Goblet", 0.3, 18, ["rich_home", "tavern"], true],
	"wine_bottle": ["Empty Wine Bottle", 0.5, 1, ["tavern", "kitchen"], true],
	"ancient_gear": ["Ancient Gear", 3.0, 40, ["ruin", "vault"], false],
	"ancient_coin": ["Ancient Coin", 0.05, 25, ["ruin", "vault"], true],
}

## key -> [name, value, tags]
const INGREDIENTS := {
	"lavender": ["Lavender", 2, ["alchemist", "home", "forest"]],
	"blue_mountain_flower": ["Blue Mountain Flower", 3, ["alchemist", "highlands"]],
	"snowberries": ["Snowberries", 3, ["alchemist", "snow"]],
	"thistle": ["Thistle", 2, ["alchemist", "plains"]],
	"bloodmoss": ["Bloodmoss", 5, ["alchemist", "cave", "crypt"]],
	"glowcap": ["Glowcap Mushroom", 6, ["alchemist", "cave", "mine"]],
	"nightshade": ["Nightshade", 8, ["alchemist", "swamp", "crypt"]],
	"sandroot": ["Sandroot", 6, ["alchemist", "desert"]],
	"swamp_lily": ["Swamp Lily", 7, ["alchemist", "swamp"]],
	"frost_mirriam": ["Frost Mirriam", 9, ["alchemist", "snow", "ice"]],
	"ash_salt": ["Ash Salt", 12, ["alchemist", "ashlands"]],
	"fire_salts": ["Fire Salts", 30, ["alchemist", "ashlands", "vault"]],
	"wolf_fang": ["Wolf Fang", 4, ["alchemist", "hunter", "camp"]],
	"bear_claw": ["Bear Claw", 10, ["alchemist", "hunter"]],
	"troll_fat": ["Troll Fat", 20, ["alchemist", "cave"]],
	"bone_meal": ["Bone Meal", 4, ["alchemist", "crypt", "barrow"]],
	"venom_sac": ["Spider Venom Sac", 14, ["alchemist", "cave", "mine"]],
	"crawler_eye": ["Crawler Eye", 18, ["alchemist", "mine"]],
	"wisp_dust": ["Wisp Dust", 35, ["alchemist", "barrow", "ice"]],
	"void_salt": ["Void Salt", 60, ["alchemist", "vault", "ashlands"]],
}

## key -> [name, min level, value, weight, tags]
const ARTIFACTS := {
	"mourners_locket": ["Mourner's Locket", 5, 150, 0.3, ["crypt"]],
	"sunfire_idol": ["Sunfire Idol", 8, 260, 2.0, ["ruin", "desert"]],
	"barrow_kings_torc": ["Barrow King's Torc", 10, 350, 1.0, ["barrow"]],
	"saints_finger": ["Saint's Finger Bone", 12, 220, 0.1, ["crypt", "temple"]],
	"star_map": ["Shattered Star Map", 15, 380, 1.0, ["ruin"]],
	"wight_shield_boss": ["Wight-Bound Shield Boss", 18, 280, 3.0, ["barrow"]],
	"oracle_tablet": ["Clay Oracle Tablet", 20, 300, 4.0, ["ruin"]],
	"funeral_bell": ["Gilded Funeral Bell", 22, 420, 2.0, ["crypt"]],
	"runed_mask": ["Runed Burial Mask", 25, 500, 1.5, ["barrow"]],
	"old_queen_sandglass": ["Sandglass of the Old Queen", 25, 550, 2.0, ["vault", "desert"]],
	"quiet_ash_censer": ["Censer of Quiet Ash", 30, 600, 2.0, ["crypt", "temple"]],
	"drowned_astrolabe": ["Drowned Astrolabe", 30, 950, 2.5, ["vault", "coast"]],
	"first_chieftain_horn": ["Horn of the First Chieftain", 35, 800, 2.0, ["barrow"]],
	"tide_coral_crown": ["Coral Crown of the Tide", 35, 850, 1.0, ["vault", "coast"]],
	"bronze_sky_disc": ["Bronze Sky Disc", 40, 900, 3.0, ["ruin"]],
	"construct_heart": ["Construct's Heart Gear", 45, 1400, 4.0, ["vault"]],
	"glacier_pearl": ["Glacier Pearl", 50, 1500, 0.5, ["ice"]],
	"obsidian_prayer_wheel": ["Obsidian Prayer Wheel", 50, 1600, 3.0, ["ashen"]],
	"frozen_crown_shard": ["Frozen Crown Shard", 55, 1800, 1.0, ["ice"]],
	"deep_kings_prism": ["Prism of the Deep Kings", 60, 2200, 1.5, ["vault"]],
	"ember_heart": ["Ember Heart of Ash", 60, 2300, 1.0, ["ashen"]],
	"rime_horn": ["Rime-Etched Horn", 65, 2400, 2.0, ["ice"]],
	"vault_keystone": ["Vault Keystone Fragment", 70, 2800, 5.0, ["vault"]],
	"molten_scripture": ["Molten Scripture", 75, 3200, 3.0, ["ashen"]],
}

## key -> [name, verb, group, heal, duration, stamina regen, restore stamina, restore magicka, value, weight, min level, tags]
const CONSUMABLES := {
	"minor_stamina_potion": ["Minor Stamina Potion", "Drink", "potion", 0.0, 1.0, 0.0, 40.0, 0.0, 20, 0.3, 1, ["alchemist"]],
	"stamina_potion": ["Stamina Potion", "Drink", "potion", 0.0, 1.0, 0.0, 80.0, 0.0, 45, 0.4, 15, ["alchemist"]],
	"greater_stamina_potion": ["Greater Stamina Potion", "Drink", "potion", 0.0, 1.0, 0.0, 150.0, 0.0, 110, 0.5, 40, ["alchemist"]],
	"minor_magicka_potion": ["Minor Magicka Potion", "Drink", "potion", 0.0, 1.0, 0.0, 0.0, 30.0, 20, 0.3, 1, ["alchemist", "library"]],
	"magicka_potion": ["Magicka Potion", "Drink", "potion", 0.0, 1.0, 0.0, 0.0, 60.0, 45, 0.4, 15, ["alchemist", "library"]],
	"greater_magicka_potion": ["Greater Magicka Potion", "Drink", "potion", 0.0, 1.0, 0.0, 0.0, 120.0, 110, 0.5, 40, ["alchemist", "library"]],
	"cheese_wedge": ["Cheese Wedge", "Eat", "food", 15.0, 60.0, 0.0, 0.0, 0.0, 4, 0.3, 1, ["kitchen", "tavern"]],
	"smoked_fish": ["Smoked Fish", "Eat", "food", 20.0, 60.0, 0.0, 0.0, 0.0, 5, 0.3, 1, ["kitchen", "coast"]],
	"ale": ["Ale", "Drink", "food", 5.0, 60.0, 0.2, 0.0, 0.0, 5, 0.5, 1, ["tavern", "kitchen"]],
	"wine": ["Wine", "Drink", "food", 10.0, 60.0, 0.15, 0.0, 0.0, 12, 0.5, 1, ["tavern", "rich_home"]],
	"beef_stew": ["Beef Stew", "Eat", "food", 30.0, 60.0, 0.0, 10.0, 0.0, 8, 0.8, 1, ["kitchen", "tavern"]],
	"onion_soup": ["Onion Soup", "Eat", "food", 18.0, 60.0, 0.0, 5.0, 0.0, 5, 0.6, 1, ["kitchen", "tavern"]],
	"cabbage_soup": ["Cabbage Soup", "Eat", "food", 16.0, 60.0, 0.0, 5.0, 0.0, 4, 0.6, 1, ["kitchen", "home"]],
	"porridge": ["Bowl of Porridge", "Eat", "food", 14.0, 60.0, 0.0, 8.0, 0.0, 3, 0.5, 1, ["kitchen", "home"]],
	"roast_chicken": ["Roast Chicken", "Eat", "food", 28.0, 60.0, 0.0, 0.0, 0.0, 9, 1.0, 1, ["kitchen", "tavern"]],
	"salted_beef": ["Salted Beef", "Eat", "food", 15.0, 60.0, 0.0, 0.0, 0.0, 5, 0.3, 1, ["camp", "kitchen"]],
	"jerky": ["Strip of Jerky", "Eat", "food", 10.0, 60.0, 0.0, 5.0, 0.0, 3, 0.1, 1, ["camp", "hunter"]],
	"boiled_eggs": ["Boiled Eggs", "Eat", "food", 10.0, 60.0, 0.0, 0.0, 0.0, 2, 0.2, 1, ["kitchen", "home"]],
	"cheese_wheel": ["Cheese Wheel", "Eat", "food", 40.0, 60.0, 0.0, 0.0, 0.0, 15, 2.0, 1, ["kitchen", "tavern"]],
	"berry_tart": ["Berry Tart", "Eat", "food", 14.0, 60.0, 0.0, 10.0, 0.0, 6, 0.3, 1, ["kitchen", "rich_home"]],
	"baked_potato": ["Baked Potato", "Eat", "food", 12.0, 60.0, 0.0, 0.0, 0.0, 2, 0.3, 1, ["kitchen", "home"]],
	"pear": ["Pear", "Eat", "food", 6.0, 60.0, 0.0, 5.0, 0.0, 2, 0.1, 1, ["kitchen", "home"]],
	"carrot": ["Carrot", "Eat", "food", 4.0, 60.0, 0.0, 5.0, 0.0, 1, 0.1, 1, ["kitchen", "home"]],
	"sweet_roll": ["Sweet Roll", "Eat", "food", 10.0, 60.0, 0.0, 5.0, 0.0, 4, 0.2, 1, ["kitchen", "tavern"]],
	"mead": ["Honey Mead", "Drink", "food", 8.0, 60.0, 0.2, 0.0, 0.0, 10, 0.5, 1, ["tavern", "kitchen"]],
	"cider": ["Apple Cider", "Drink", "food", 6.0, 60.0, 0.15, 0.0, 0.0, 6, 0.5, 1, ["tavern", "kitchen"]],
	"brandy": ["Brandy", "Drink", "food", 12.0, 60.0, 0.25, 0.0, 0.0, 25, 0.5, 1, ["tavern", "rich_home"]],
	"milk": ["Jug of Milk", "Drink", "food", 8.0, 60.0, 0.0, 10.0, 0.0, 3, 1.0, 1, ["kitchen", "home"]],
	"healing_draught": ["Healing Draught", "Drink", "potion", 60.0, 10.0, 0.0, 0.0, 0.0, 35, 0.4, 5, ["alchemist", "temple"]],
	"elixir_of_vigor": ["Elixir of Vigor", "Drink", "potion", 40.0, 1.0, 0.0, 80.0, 0.0, 70, 0.4, 20, ["alchemist"]],
	"philter_of_clarity": ["Philter of Clarity", "Drink", "potion", 0.0, 1.0, 0.0, 0.0, 90.0, 80, 0.4, 25, ["alchemist", "library"]],
	"tonic_of_endurance": ["Tonic of Endurance", "Drink", "potion", 0.0, 120.0, 0.5, 30.0, 0.0, 55, 0.4, 10, ["alchemist", "hunter"]],
	"superior_health_potion": ["Superior Health Potion", "Drink", "potion", 250.0, 1.0, 0.0, 0.0, 0.0, 260, 0.5, 60, ["alchemist", "vault"]],
	"superior_magicka_potion": ["Superior Magicka Potion", "Drink", "potion", 0.0, 1.0, 0.0, 0.0, 240.0, 260, 0.5, 60, ["alchemist", "vault"]],
	"superior_stamina_potion": ["Superior Stamina Potion", "Drink", "potion", 0.0, 1.0, 0.0, 280.0, 0.0, 240, 0.5, 60, ["alchemist", "vault"]],
}

var _count := 0


func _initialize() -> void:
	for t in 7:
		for kind in WEAPONS:
			_weapon(kind, t)
		_shield(t)
		for piece in PIECES:
			_armor(piece, t, true)
			_armor(piece, t, false)
	for g in GRADES.size():
		for e in JEWEL_EFFECTS:
			_jewel(g, e, false)
			_jewel(g, e, true)
	for k in CLOTHING:
		_clothing(k)
	for k in CLUTTER:
		_clutter(k)
	for k in INGREDIENTS:
		_ingredient(k)
	for k in ARTIFACTS:
		_artifact(k)
	for k in CONSUMABLES:
		_consumable(k)
	_tag_existing()
	print("generate_content: wrote %d item files" % _count)
	quit()


# ---------------------------------------------------------------- writing

## The file for this key, loaded if it exists (keeps hand-set fields), else a new ItemData
func _open(path: String) -> ItemData:
	if ResourceLoader.exists(path):
		var existing := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemData
		if existing != null:
			return existing
	return ItemData.new()


func _save(item: ItemData, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var uid := _file_uid(path)
	var err := ResourceSaver.save(item, path)
	if err != OK:
		push_error("generate_content: could not write %s (error %d)" % [path, err])
		return
	_count += 1
	# Other files may point at this one by its uid: keep it
	if uid != "" and _file_uid(path) == "":
		var text := FileAccess.get_file_as_string(path)
		var nl := text.find("\n")
		var head := text.substr(0, nl).trim_suffix("]") + ' uid="%s"]' % uid
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(head + text.substr(nl))
		f.close()


## The uid="..." in a .tres file's first line ("" = none)
func _file_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	var first := f.get_line()
	f.close()
	var at := first.find('uid="')
	return first.substr(at + 5, first.find('"', at + 5) - at - 5) if at >= 0 else ""


func _gear_path(key: String, folder: String) -> String:
	return RES + LEGACY[key] if LEGACY.has(key) else RES + folder + "/" + key + ".tres"


func _weapon(kind: String, t: int) -> void:
	var w: Dictionary = WEAPONS[kind]
	var key := "%s_%s" % [TIER_KEYS[t], kind]
	var path := _gear_path(key, "weapons")
	var it := _open(path)
	it.id = StringName(key)
	it.display_name = "%s %s" % [TIER_NAMES[t], w["name"]]
	it.description = "%s %s" % [TIER_FLAVOR[t], w["desc"]]
	it.item_type = ItemData.ItemType.WEAPON
	it.equip_slot = ItemData.EquipSlot.MAIN_HAND
	it.weight = snappedf(float(w["weight"]) * WEIGHT_MULT[t], 0.01)
	it.value = roundi(float(w["value"]) * VALUE_MULT[t])
	it.governing_skill = w["skill"]
	it.tier = t + 1
	it.min_level = TIER_MIN_LEVEL[t]
	it.weapon_damage = snappedf(float(w["damage"]) * DAMAGE_MULT[t], 0.01)
	it.reach = w["reach"]
	it.attack_style = w["style"]
	it.arc_degrees = w.get("arc", 90.0)
	it.attack_cooldown = w["cooldown"]
	it.attack_windup = w["windup"]
	it.attack_active = w["active"]
	it.stamina_cost = snappedf(float(w["stamina"]) * STAMINA_MULT[t], 0.01)
	it.knockback = snappedf(float(w["knock"]) * (1.0 + 0.05 * t), 0.01)
	it.poise_damage = snappedf(float(w["poise"]) * POISE_MULT[t], 0.01)
	it.combo_length = w["combo"]
	it.two_handed = w.get("two_handed", false)
	it.can_dual_wield = w.get("dual", false)
	it.armor_pierce = w.get("pierce", 0.0)
	var h: Array = w["heavy"]
	it.heavy_charge_time = h[0]
	it.heavy_windup = h[1]
	it.heavy_damage_mult = h[2]
	it.heavy_stamina_mult = h[3]
	it.heavy_poise_mult = h[4]
	it.heavy_reach_bonus = h[5]
	if w.has("slam"):
		var s: Array = w["slam"]
		it.secondary_action = ItemData.SecondaryAction.SLAM
		it.secondary_cooldown = s[0]
		it.secondary_windup = s[1]
		it.secondary_stamina_cost = s[2]
		it.secondary_damage_mult = s[3]
		it.secondary_radius = s[4]
	it.animation_set = StringName(w["aset"])
	it.loot_tags = PackedStringArray(["weapon", "smithy"])
	_save(it, path)


func _shield(t: int) -> void:
	var key := "%s_shield" % TIER_KEYS[t]
	var path := _gear_path(key, "weapons")
	var it := _open(path)
	it.id = StringName(key)
	it.display_name = "%s Shield" % TIER_NAMES[t]
	it.description = "%s Hold right click to block. Raise it just before a hit lands to parry. Left click while blocking to bash." % TIER_FLAVOR[t]
	it.item_type = ItemData.ItemType.ARMOR
	it.equip_slot = ItemData.EquipSlot.OFF_HAND
	it.weight = snappedf(8.0 * WEIGHT_MULT[t], 0.01)
	it.value = roundi(30.0 * VALUE_MULT[t])
	it.governing_skill = "block"
	it.tier = t + 1
	it.min_level = TIER_MIN_LEVEL[t]
	it.stat_modifiers = {"armor": float(SHIELD_ARMOR[t])}
	it.secondary_action = ItemData.SecondaryAction.BLOCK
	it.block_reduction = 0.6 + 0.02 * t
	it.block_angle = 120.0
	it.parry_window = 0.2
	it.bash_damage = snappedf(3.0 * DAMAGE_MULT[t], 0.01)
	it.bash_poise = snappedf(30.0 * POISE_MULT[t], 0.01)
	it.bash_stamina_cost = 8.0
	it.animation_set = &"shield"
	it.loot_tags = PackedStringArray(["armor", "smithy"])
	_save(it, path)


## Heavy cuirasses keep their old files (<tier>_chestplate in Weapons/), every other piece is in Armor/
func _armor(piece: String, t: int, heavy: bool) -> void:
	var p: Array = PIECES[piece]
	var material: String = TIER_NAMES[t] if heavy else LIGHT_NAMES[t]
	var mat_key: String = TIER_KEYS[t] if heavy else LIGHT_KEYS[t]
	var key := "%s_%s" % [mat_key, piece]
	var path := RES + "armor/" + key + ".tres"
	if heavy and piece == "cuirass":
		key = "%s_chestplate" % TIER_KEYS[t]
		path = _gear_path(key, "weapons")
	var it := _open(path)
	it.id = StringName(key)
	it.display_name = "%s %s" % [material, p[0] if heavy else p[1]]
	it.description = "%s %s armor for the %s." % [TIER_FLAVOR[t] if heavy else LIGHT_FLAVOR[t], "Heavy" if heavy else "Light",
		String(ItemData.EquipSlot.keys()[p[2]]).to_lower()]
	it.item_type = ItemData.ItemType.ARMOR
	it.equip_slot = p[2]
	var armor := float(SET_ARMOR[t]) * float(p[3]) * (1.0 if heavy else LIGHT_ARMOR)
	it.stat_modifiers = {"armor": snappedf(armor, 0.1)}
	it.weight = snappedf(float(p[4]) * WEIGHT_MULT[t] * (1.0 if heavy else LIGHT_WEIGHT), 0.1)
	it.value = roundi(90.0 * float(p[5]) * VALUE_MULT[t] * (1.0 if heavy else 0.8))
	it.governing_skill = "heavy_armor" if heavy else "light_armor"
	it.tier = t + 1
	it.min_level = TIER_MIN_LEVEL[t]
	it.armor_set = StringName("%s_%s" % [TIER_KEYS[t], "heavy" if heavy else "light"])
	it.animation_set = StringName(piece)
	it.loot_tags = PackedStringArray(["armor", "smithy"] if heavy else ["armor", "smithy", "hunter"])
	_save(it, path)


func _jewel(g: int, effect: String, amulet: bool) -> void:
	var grade: Array = GRADES[g]
	var e: Array = JEWEL_EFFECTS[effect]
	var key := "%s_%s_%s" % [String(grade[0]).to_lower(), "amulet" if amulet else "ring", effect]
	var path := RES + "jewelry/" + key + ".tres"
	var it := _open(path)
	var amount: float = float(e[2][g]) * (1.5 if amulet else 1.0)
	it.id = StringName(key)
	it.display_name = "%s %s of %s" % [grade[0], "Amulet" if amulet else "Ring", e[0]]
	var shown := "+%d%%" % roundi(amount * 100.0) if e[1] == "stamina_regen_mult" else "+%d" % roundi(amount)
	it.description = "%s %s while worn." % [shown, String(e[1]).replace("_mult", "").replace("_", " ").replace("max ", "maximum ")]
	it.item_type = ItemData.ItemType.ARMOR
	it.equip_slot = ItemData.EquipSlot.AMULET if amulet else ItemData.EquipSlot.RING
	it.stat_modifiers = {e[1]: snappedf(amount, 0.01)}
	it.weight = 0.3 if amulet else 0.1
	it.value = roundi(float(grade[3]) * (1.4 if amulet else 1.0))
	it.tier = grade[2]
	it.min_level = grade[1]
	it.loot_tags = PackedStringArray(["jewelry", "jeweler", "rich_home", "crypt", "vault"])
	_save(it, path)


func _clothing(k: String) -> void:
	var c: Array = CLOTHING[k]
	var path := RES + "clothing/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.description = "Everyday clothes. No protection, but they look the part."
	it.item_type = ItemData.ItemType.ARMOR
	it.equip_slot = c[1]
	it.weight = c[2]
	it.value = c[3]
	it.min_level = 1
	it.loot_tags = PackedStringArray(c[4])
	_save(it, path)


func _clutter(k: String) -> void:
	var c: Array = CLUTTER[k]
	var path := RES + "clutter/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.description = "Worth a few coins to the right buyer." if c[4] else "Useful, or worth selling."
	it.item_type = ItemData.ItemType.MISC
	it.weight = c[1]
	it.value = c[2]
	it.junk = c[4]
	it.stackable = true
	it.max_stack = 99
	it.min_level = 1
	it.loot_tags = PackedStringArray(c[3])
	_save(it, path)


func _ingredient(k: String) -> void:
	var c: Array = INGREDIENTS[k]
	var path := RES + "ingredients/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.description = "An alchemical ingredient. Alchemists buy it."
	it.item_type = ItemData.ItemType.INGREDIENT
	it.weight = 0.1
	it.value = c[1]
	it.stackable = true
	it.max_stack = 99
	it.min_level = 1
	it.loot_tags = PackedStringArray(c[2])
	_save(it, path)


func _artifact(k: String) -> void:
	var c: Array = ARTIFACTS[k]
	var path := RES + "artifacts/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.description = "An ancient relic. Ordinary merchants pay little for it; the Antiquarian Society pays its full worth."
	it.item_type = ItemData.ItemType.MISC
	it.min_level = c[1]
	it.value = c[2]
	it.weight = c[3]
	it.treasure = true
	it.artifact = true
	it.loot_tags = PackedStringArray(c[4])
	_save(it, path)


## Older hand-made items only get loot tags (so furnished rooms can use them); nothing else changes
const EXISTING_TAGS := {
	"consumables/apple.tres": ["kitchen", "home", "farm"],
	"consumables/bread.tres": ["kitchen", "home", "tavern"],
	"consumables/hearty_stew.tres": ["kitchen", "tavern"],
	"consumables/roast_meat.tres": ["kitchen", "tavern", "camp"],
	"consumables/venison_feast.tres": ["tavern", "rich_home"],
	"consumables/minor_health_potion.tres": ["alchemist", "temple", "camp", "home"],
	"consumables/health_potion.tres": ["alchemist", "temple", "camp"],
	"consumables/greater_health_potion.tres": ["alchemist", "vault"],
	"misc/lockpick.tres": ["shop", "camp", "sewer"],
}


func _tag_existing() -> void:
	for rel in EXISTING_TAGS:
		var path: String = RES + rel
		if not ResourceLoader.exists(path):
			continue
		var it := _open(path)
		it.loot_tags = PackedStringArray(EXISTING_TAGS[rel])
		_save(it, path)
	for f in DirAccess.get_files_at(RES + "treasure/"):
		if not f.ends_with(".tres"):
			continue
		var it := _open(RES + "treasure/" + f)
		var n := it.display_name.to_lower()
		var tags := ["jeweler", "rich_home"]
		if n.contains("coin") or n.contains("idol") or n.contains("crown") or n.contains("reliquary"):
			tags = ["crypt", "barrow", "ruin", "rich_home"]
		elif n.contains("ring") or n.contains("necklace") or n.contains("circlet"):
			tags.append("crypt")
		else:
			tags.append_array(["mine", "cave"])  # gems
		it.loot_tags = PackedStringArray(tags)
		_save(it, RES + "treasure/" + f)


func _consumable(k: String) -> void:
	var c: Array = CONSUMABLES[k]
	var path := RES + "consumables/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.use_verb = c[1]
	it.effect_group = c[2]
	it.heal_amount = c[3]
	it.effect_duration = c[4]
	it.stamina_regen_bonus = c[5]
	it.restore_stamina = c[6]
	it.restore_magicka = c[7]
	it.value = c[8]
	it.weight = c[9]
	it.min_level = c[10]
	it.loot_tags = PackedStringArray(c[11])
	it.item_type = ItemData.ItemType.CONSUMABLE
	it.stackable = true
	it.max_stack = 99
	it.description = ""
	_save(it, path)
