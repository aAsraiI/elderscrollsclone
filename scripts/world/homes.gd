class_name Homes
extends RefCounted
## Houses you can buy. Every town and city has one empty house for sale (nobody lives there): its
## door says so, and E on it buys it. Your home: the door opens for you, nothing inside is stolen,
## the chest is yours to store things in, the beds are free, and it has a cooking pot, an alchemy
## lab, a workbench and two planters for growing food and herbs (see Planter).
## Owned homes are WorldState records "home/<building id>".

const PRICES := [0, 2500, 5000]  # village (none), town, city


static func owns(building_id: String) -> bool:
	return building_id != "" and WorldState.has_record("home/" + building_id)


## The building for sale in a town ("" for villages and small towns)
static func for_sale_id(layout: TownLayout, kind: int) -> String:
	if layout == null or kind <= 0:
		return ""
	var best := ""
	var best_h := 0x7FFFFFFF
	var houses := 0
	for b in layout.buildings:
		if b.kind == BuildingPlot.Kind.HOUSE and b.trade == "":
			houses += 1
			var h := ("%s|sale" % b.id).hash() & 0x7FFFFFFF
			if h < best_h:
				best_h = h
				best = b.id
	return best if houses >= 3 else ""


static func is_for_sale(b: BuildingPlot, world: WorldManager) -> bool:
	if b == null or world == null:
		return false
	var t := world.get_poi(b.town_id)
	if t == null or not (t.poi is TownData):
		return false
	return for_sale_id(t.town, int((t.poi as TownData).kind)) == b.id


static func price(b: BuildingPlot, world: WorldManager) -> int:
	var t := world.get_poi(b.town_id) if world != null else null
	if t == null or not (t.poi is TownData):
		return 3000
	return PRICES[clampi(int((t.poi as TownData).kind), 0, 2)]


## Buys it. Returns "" or why not.
static func buy(b: BuildingPlot, inv: Inventory, world: WorldManager) -> String:
	if owns(b.id):
		return "You already own it"
	var cost := price(b, world)
	if Currency.get_gold(inv) < cost:
		return "You need %d gold to buy this house" % cost
	Currency.spend_gold(inv, cost)
	WorldState.set_record("home/" + b.id, {"town": b.town_name})
	Locks.set_locked(b.id, false)
	inv.add_item(KeyRing.get_key(b.id, b.display_name), 1)
	return ""


## Every home you own: [{"id", "town"}]
static func owned() -> Array:
	var out := []
	for k in WorldState.records:
		if String(k).begins_with("home/"):
			out.append({"id": String(k).trim_prefix("home/"), "town": WorldState.records[k].get("town", "")})
	return out
