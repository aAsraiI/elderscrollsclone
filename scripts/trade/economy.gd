class_name Economy
extends RefCounted
## Prices that move. Three things change what a shop asks and pays, on top of the merchant's own
## markup and your Speech, disposition and guild (Barter):
##   the land     what a land makes is cheaper there, what it lacks dearer (REGION)
##   your trades  selling a lot of one kind of thing in a town floods its market (it pays less);
##                buying it up makes it scarce (it asks more). Both fade by DECAY a day.
##   festivals    food and drink cost more in a town keeping a festival, and fetch more too
## A town's market is saved in WorldState "econ/<town id>".

const DECAY := 0.15
## Each item sold lowers what the town pays for that kind by this much (to at least FLOOR)
const GLUT := 0.02
const FLOOR := 0.6
## Each item bought raises what the town asks by this much (to at most CEILING)
const SCARCITY := 0.01
const CEILING := 1.25
const FESTIVAL_FOOD := 1.15

## biome -> {kind of goods: price factor}. Below 1: made here, cheap. Above 1: brought in, dear.
const REGION := {
	"plains": {"consumable": 0.85},
	"forest": {"ingredient": 0.85, "material": 0.9},
	"lakeland": {"consumable": 0.9},
	"coast": {"consumable": 0.9, "misc": 0.9},
	"swamp": {"ingredient": 0.85, "consumable": 1.1},
	"highlands": {"material": 0.85, "weapon": 0.92},
	"badlands": {"material": 0.85, "consumable": 1.15},
	"desert": {"consumable": 1.2, "ingredient": 1.15, "jewelry": 0.9},
	"deadlands": {"consumable": 1.25, "soul_gem": 0.9},
	"ashlands": {"soul_gem": 0.85, "consumable": 1.2},
	"snow_mountains": {"material": 0.9, "consumable": 1.15},
	"tundra": {"material": 0.9, "consumable": 1.2},
	"frozen_crown": {"consumable": 1.25},
}


## The kind of goods an item is, for the market ("consumable", "weapon", "material"...)
static func kind_of(item: ItemData) -> String:
	if item.equip_slot == ItemData.EquipSlot.RING or item.equip_slot == ItemData.EquipSlot.AMULET:
		return "jewelry"
	return String(ItemData.ItemType.keys()[item.item_type]).to_lower()


## How much dearer (above 1) or cheaper a shop in this town sells this item right now
static func buy_factor(item: ItemData, town_id: String, biome: String, festival: bool, today: int) -> float:
	var k := kind_of(item)
	var f := float(REGION.get(biome, {}).get(k, 1.0))
	var v := _pressure(town_id, k, today)
	if v < 0.0:
		f *= minf(1.0 + SCARCITY * -v, CEILING)
	if festival and k == "consumable":
		f *= FESTIVAL_FOOD
	return f


## How much more (above 1) or less a shop in this town pays for this item right now
static func sell_factor(item: ItemData, town_id: String, biome: String, festival: bool, today: int) -> float:
	var k := kind_of(item)
	var f := float(REGION.get(biome, {}).get(k, 1.0))
	var v := _pressure(town_id, k, today)
	if v > 0.0:
		f *= maxf(1.0 - GLUT * v, FLOOR)
	if festival and k == "consumable":
		f *= 1.1
	return f


## The player sold (count > 0) or bought (count < 0) items in a town's shops
static func record(town_id: String, item: ItemData, count: int, today: int) -> void:
	if town_id == "" or item == null or count == 0:
		return
	var rec := WorldState.get_record("econ/" + town_id).duplicate(true)
	var k := kind_of(item)
	var v := _pressure(town_id, k, today) + float(count)
	rec[k] = {"v": clampf(v, -40.0, 40.0), "day": today}
	WorldState.set_record("econ/" + town_id, rec)


# How flooded (above 0) or bought up (below 0) a kind of goods is in a town, faded by the days since
static func _pressure(town_id: String, kind: String, today: int) -> float:
	var e: Dictionary = WorldState.get_record("econ/" + town_id).get(kind, {})
	if e.is_empty():
		return 0.0
	var days := maxi(today - int(e.get("day", today)), 0)
	return float(e.get("v", 0.0)) * pow(1.0 - DECAY, days)


## "Prices here: grain is cheap, iron is dear" style note for the barter window ("" = nothing unusual)
static func note(town_id: String, biome: String, festival: bool, today: int) -> String:
	var cheap := PackedStringArray()
	var dear := PackedStringArray()
	var names := {"consumable": "food and drink", "ingredient": "ingredients", "material": "ore and hides", "weapon": "weapons",
		"armor": "armor", "jewelry": "jewelry", "soul_gem": "soul gems", "misc": "goods", "book": "books"}
	for k in REGION.get(biome, {}):
		var f: float = REGION[biome][k]
		(cheap if f < 1.0 else dear).append(names.get(k, k))
	var glutted := PackedStringArray()
	for k in WorldState.get_record("econ/" + town_id):
		if _pressure(town_id, k, today) > 5.0:
			glutted.append(names.get(k, k))
	var parts := PackedStringArray()
	if not cheap.is_empty():
		parts.append("cheap here: " + ", ".join(cheap))
	if not dear.is_empty():
		parts.append("dear here: " + ", ".join(dear))
	if not glutted.is_empty():
		parts.append("too much on the market: " + ", ".join(glutted))
	if festival:
		parts.append("festival prices on food and drink")
	return ("Prices: " + ";  ".join(parts) + ".") if not parts.is_empty() else ""
