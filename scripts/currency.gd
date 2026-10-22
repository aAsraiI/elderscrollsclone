class_name Currency
extends RefCounted
## Gold is an ordinary stackable item (scripts/Resources/Consumables/gold.tres), so it is saved,
## dropped, looted and weighed like everything else. Shops, quests and rewards use these helpers
## so nobody has to remember how it is stored.

const GOLD_PATH := "res://scripts/Resources/Consumables/gold.tres"

static var _gold: ItemData


static func gold_item() -> ItemData:
	if _gold == null and ResourceLoader.exists(GOLD_PATH):
		_gold = load(GOLD_PATH) as ItemData
	return _gold


static func get_gold(inv: Inventory) -> int:
	var g := gold_item()
	return inv.get_count(g) if g != null and inv != null else 0


static func add_gold(inv: Inventory, amount: int) -> void:
	var g := gold_item()
	if g != null and inv != null and amount > 0:
		inv.add_item(g, amount)


## false (and nothing taken) if there is not enough
static func spend_gold(inv: Inventory, amount: int) -> bool:
	var g := gold_item()
	if g == null or inv == null or amount < 0 or inv.get_count(g) < amount:
		return false
	if amount > 0:
		inv.remove_item(g, amount)
	return true
