class_name MerchantData
extends Resource
## One kind of trader: what they sell, how much gold they keep, what they buy and how they price
## it. Every shop, inn, smithy and temple uses one, picked from scripts/Resources/Merchants/ by the
## building's trade (see Barter.merchant_for). Make a new kind of shop: duplicate a file there.
##
## Stock is rolled fresh every `restock_days` days (the same roll for the same shop and day).
## What you sell them stays on their shelves until then.

@export var id: StringName
@export var display_name := "General Goods"
@export_group("Stock")
## Rolled at every restock, like a chest's contents
@export var stock: Array[LootEntry] = []
## Also stock weapons and armor that suit the land around the town (smiths)
@export var curve_stock := false
## Scales the chance of each piece of gear in curve_stock
@export var curve_quality := 4.0
## Also stock treasure (gems, jewelry) that suits the land
@export var treasure_stock := false
@export var restock_days := 3
@export_group("Gold")
## Gold the merchant has to buy things with after a restock (a city's merchants have more)
@export var gold_min := 300
@export var gold_max := 600
@export_group("Buying from you")
## What they will buy: "weapon", "armor", "consumable", "misc", "ingredient", "treasure", or "all".
## Keys are never bought.
@export var buys: PackedStringArray = ["all"]
## What they pay for an ordinary item, as a part of its value (before Speech and disposition)
@export_range(0.05, 1.0, 0.01) var sell_rate := 0.45
## What they pay for treasure, as a part of its value
@export_range(0.05, 1.2, 0.01) var treasure_rate := 0.6
## A fence: also buys stolen goods (ordinary merchants refuse them)
@export var buys_stolen := false
@export_group("Selling to you")
## What they charge, as a multiple of the value (before Speech and disposition)
@export_range(0.5, 3.0, 0.01) var markup := 1.25


func will_buy(item: ItemData) -> bool:
	if item == null or item.item_type == ItemData.ItemType.KEY or item.id == &"gold":
		return false
	if buys.has("all"):
		return true
	if item.treasure:
		return buys.has("treasure")
	return buys.has(String(ItemData.ItemType.keys()[item.item_type]).to_lower())
