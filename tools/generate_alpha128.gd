extends SceneTree
## Alpha 1.28: tomes for the new spells (Levitate, Water Walking, and the far islands' Grandmaster
## and Ascendant ranks) and scrolls (one-use spells anyone can read). Run with:
##   godot --headless --path . -s res://tools/generate_alpha128.gd

const PRICE := [30, 90, 240, 520, 1100, 6000, 15000]
## spell id -> [value, level it turns up from, loot tags]
const SCROLLS := {
	"fireball": [60, 5, ["mage", "library", "camp"]], "lightning_bolt": [45, 3, ["mage", "library", "camp"]],
	"frost_nova": [70, 8, ["mage", "library"]], "healing_hands": [30, 1, ["mage", "library", "shop", "camp"]],
	"close_wounds": [120, 15, ["mage", "library", "vault"]], "paralyze_spell": [140, 15, ["mage", "library", "vault"]],
	"invisibility_spell": [150, 15, ["mage", "library", "vault"]], "calm_spell": [40, 3, ["mage", "library"]],
	"levitate_spell": [160, 15, ["mage", "library", "vault"]], "water_walking_spell": [60, 5, ["mage", "library", "shop"]],
	"summon_skeleton_spell": [50, 5, ["mage", "library", "camp"]], "mass_paralysis": [400, 30, ["vault"]],
	"meteor": [1800, 100, ["vault", "mage"]], "radiant_heal": [1500, 100, ["vault", "mage"]], "stasis": [3500, 150, ["vault"]],
}


func _initialize() -> void:
	var made := 0
	for id in SpellCatalog.tome_ids():
		var rank := SpellCatalog.rank_of(id)
		var path := SpellCatalog.TOME_DIR + "tome_" + id + ".tres"
		if ResourceLoader.exists(path) and rank < 5:
			continue  # the old ones stay as they are
		var s := SpellCatalog.get_spell(id)
		var it := ItemData.new()
		it.id = StringName("tome_" + id)
		it.display_name = "Spell Tome: %s" % s.display_name
		it.description = "%s %s spell. Read it to learn the spell.%s" % [SpellCatalog.RANK_NAMES[rank], MagicEffects.SCHOOL_NAMES.get(s.get_school(), ""),
			" Written on the far islands." if rank >= 5 else ""]
		it.item_type = ItemData.ItemType.BOOK
		it.teaches_spell = id
		it.weight = 1.0
		it.value = PRICE[rank]
		it.min_level = int(SpellCatalog.ISLAND_RANKS.get(rank, 1))
		it.tier = 8 if rank == 5 else (10 if rank == 6 else 1)
		it.loot_tags = PackedStringArray(["mage", "library", "vault"] if rank >= 5 else ["mage", "library"])
		made += int(ResourceSaver.save(it, path) == OK)
	for id in SCROLLS:
		var s := SpellCatalog.get_spell(id)
		if s == null:
			push_error("no spell " + id)
			continue
		var d: Array = SCROLLS[id]
		var it := ItemData.new()
		it.id = StringName("scroll_" + id)
		it.display_name = "Scroll of %s" % s.display_name
		it.description = "Read it (E in the inventory) to cast %s once, for free, whatever your skill. Used up." % s.display_name
		it.item_type = ItemData.ItemType.BOOK
		it.scroll_spell = id
		it.use_verb = "Read"
		it.weight = 0.2
		it.value = int(d[0])
		it.min_level = int(d[1])
		it.stackable = true
		it.max_stack = 99
		it.loot_tags = PackedStringArray(d[2])
		made += int(ResourceSaver.save(it, "res://data/consumables/scroll_%s.tres" % id) == OK)
	for id in Rituals.LIST:
		var r: Array = Rituals.LIST[id]
		var it := ItemData.new()
		it.id = StringName("ritual_book_" + id)
		it.display_name = "Ritual: %s" % r[0]
		it.description = "%s Perform it (E in the inventory) standing in a ritual circle: it takes %d seconds of stillness, %d magicka and a filled soul gem. The book is kept." % [r[1], int(Rituals.RITUAL_SECONDS), int(Rituals.MAGICKA)]
		it.item_type = ItemData.ItemType.BOOK
		it.weight = 2.0
		it.value = 1500
		it.min_level = 20
		it.loot_tags = PackedStringArray(["mage", "library", "vault"])
		made += int(ResourceSaver.save(it, "res://data/books/ritual_book_%s.tres" % id) == OK)
	var chalk := ItemData.new()
	chalk.id = &"ritual_chalk"
	chalk.display_name = "Ritual Chalk"
	chalk.description = "Draws a ritual circle where you stand (E in the inventory). It fades after an hour."
	chalk.item_type = ItemData.ItemType.MISC
	chalk.weight = 0.2
	chalk.value = 15
	chalk.stackable = true
	chalk.max_stack = 99
	chalk.loot_tags = PackedStringArray(["mage", "shop"])
	made += int(ResourceSaver.save(chalk, "res://data/misc/ritual_chalk.tres") == OK)
	print("made %d items" % made)
	quit()
