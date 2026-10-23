class_name SoulGems
extends RefCounted
## Soul gems: empty ones are filled by Soul Trap, filled ones power enchanting (and recharge
## enchanted weapons). Five sizes; a soul fills the smallest empty gem big enough for it.
## Item files: Resources/SoulGems/<size>_soul_gem.tres and <size>_soul_gem_filled.tres
## (made by tools/generate_stage10.gd).

const DIR := "res://data/soul_gems/"
const SIZES: Array[String] = ["petty", "lesser", "common", "greater", "grand"]
const NAMES: Array[String] = ["Petty", "Lesser", "Common", "Greater", "Grand"]
## Enchantment strength from each size (the rest comes from the Enchanting skill)
const POWER: Array[float] = [0.4, 0.55, 0.7, 0.85, 1.0]
## Charge a weapon gets from each size
const CHARGE: Array[float] = [250.0, 500.0, 1000.0, 2000.0, 3000.0]


static func gem(size: int, filled: bool) -> ItemData:
	size = clampi(size, 0, 4)
	var path := DIR + SIZES[size] + "_soul_gem" + ("_filled" if filled else "") + ".tres"
	return load(path) as ItemData if ResourceLoader.exists(path) else null


## The soul size of a creature: by its level (bosses and big beasts are bigger)
static func soul_size(e: Enemy) -> int:
	var lv := e.level
	var s := 0
	if lv >= 6:
		s = 1
	if lv >= 14:
		s = 2
	if lv >= 26:
		s = 3
	if lv >= 40:
		s = 4
	if e.body_scale >= 1.4:
		s += 1
	return clampi(s, 0, 4)


## Fills the smallest empty gem that can hold this creature's soul. Returns true if one was filled.
static func capture(caster: Node, e: Enemy) -> bool:
	var inv := caster.get_node_or_null("Inventory") as Inventory
	if inv == null:
		return false
	var need := soul_size(e)
	for size in range(need, 5):
		var empty := gem(size, false)
		if empty != null and inv.has_item(empty):
			inv.remove_item(empty, 1)
			var full := gem(size, true)
			if full != null:
				inv.add_item(full, 1)
			if caster.is_in_group("player"):
				Locks.toast(caster.get_tree(), "%s soul captured (%s Soul Gem)" % [NAMES[need], NAMES[size]])
			return true
	if caster.is_in_group("player"):
		Locks.toast(caster.get_tree(), "No empty soul gem big enough for that soul", true)
	return false


## Size of a filled gem item (-1 if it isn't one)
static func filled_size(item: ItemData) -> int:
	if item == null or item.soul_gem_size <= 0 or not item.soul_filled:
		return -1
	return item.soul_gem_size - 1
