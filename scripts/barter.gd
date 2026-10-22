class_name Barter
extends RefCounted
## Trading with merchants: prices, a shop's stock and gold, buying and selling.
##
## Prices. What a merchant CHARGES you:
##     value x markup x your buy_price_mult (Speech milestones) x (1 - Speech/400)
##           x disposition (1.2 at 0 .. 1.0 at 50 .. 0.8 at 100) x (1 - guild discount)
## What a merchant PAYS you:
##     value x sell_rate (treasure_rate for treasure) x your sell_price_mult x (1 + Speech/300)
##           x disposition (0.8 at 0 .. 1.0 at 50 .. 1.2 at 100) x (1 + guild discount)
## and never as much as they would charge for the same thing, so buying and selling back never
## makes money. The guild discount is 0 until guilds arrive (stage 6, see Deal.guild).
##
## A shop's stock and gold live in WorldState ("shop/<building id>"), so they are saved. Every
## restock_days days the shelves are rolled fresh and the gold is topped up.

const MERCHANT_DIR := "res://scripts/Resources/Merchants/"
## Merchant gold by kind of settlement (village, town, city)
const GOLD_SCALE := [0.7, 1.0, 1.5]

static var _merchants := {}


## The prices one player gets from one merchant
class Deal:
	var speech := 1
	var disposition := 50
	var buy_mult := 1.0
	var sell_mult := 1.0
	## Stage 6: standing in the merchant's guild (0.1 = 10% better prices)
	var guild := 0.0


## A shop while you are trading with it
class Shop:
	var id := ""
	var data: MerchantData
	var inventory: Inventory
	var gold := 0
	var restocked_day := 1


static func deal_for(player: Node, disposition: int) -> Deal:
	var d := Deal.new()
	d.disposition = disposition
	var skills := player.get_node_or_null("Skills") as Skills if player != null else null
	var stats := player.get_node_or_null("Stats") as Stats if player != null else null
	if skills != null:
		d.speech = skills.get_level(&"speech")
	if stats != null:
		d.buy_mult = maxf(stats.get_stat("buy_price_mult"), 0.1)
		d.sell_mult = maxf(stats.get_stat("sell_price_mult"), 0.1)
	return d


# ---------------------------------------------------------------- prices

static func buy_price(item: ItemData, m: MerchantData, d: Deal) -> int:
	var f := m.markup * d.buy_mult * (1.0 - float(d.speech) / 400.0) * (1.2 - float(d.disposition) * 0.004) * (1.0 - d.guild)
	return maxi(1, ceili(float(item.value) * f))


## 0 = they won't buy it
static func sell_price(item: ItemData, m: MerchantData, d: Deal) -> int:
	if not m.will_buy(item) or item.value <= 0:
		return 0
	var rate := m.treasure_rate if item.treasure else m.sell_rate
	var f := rate * d.sell_mult * (1.0 + float(d.speech) / 300.0) * (0.8 + float(d.disposition) * 0.004) * (1.0 + d.guild)
	var p := floori(float(item.value) * f)
	return clampi(maxi(p, 1), 1, maxi(buy_price(item, m, d) - 1, 1))


# ---------------------------------------------------------------- who trades

## The MerchantData for a building (null if it is not a shop)
static func merchant_for(b: BuildingPlot) -> MerchantData:
	if b == null:
		return null
	var key := ""
	match b.kind:
		BuildingPlot.Kind.SHOP:
			key = b.trade
		BuildingPlot.Kind.INN:
			key = "innkeeper"
		BuildingPlot.Kind.SMITHY:
			key = "smith"
		BuildingPlot.Kind.TEMPLE:
			key = "temple"
	if key == "":
		return null
	if not _merchants.has(key):
		var path := MERCHANT_DIR + key + ".tres"
		_merchants[key] = load(path) as MerchantData if ResourceLoader.exists(path) else null
	return _merchants[key]


## Can this speaker trade right now? {"merchant": MerchantData or null, "open": bool, "why": String}
static func trade_status(s: DialogueEngine.Speaker, world: WorldManager) -> Dictionary:
	if s == null or s.data == null or s.data.work_id == "" or world == null:
		return {"merchant": null, "open": false, "why": ""}
	var m := merchant_for(world.get_building(s.data.work_id))
	if m == null:
		return {"merchant": null, "open": false, "why": ""}
	var r: TownLife.Resident = world.life.get_resident(s.data.id) if world.life != null else null
	var at_work := r != null and r.activity == NpcData.Activity.WORK and r.inside == s.data.work_id
	var why := "" if at_work else "Open %s to %s" % [Residents._hour(s.data.work_start), Residents._hour(s.data.work_end)]
	return {"merchant": m, "open": at_work, "why": why}


# ---------------------------------------------------------------- the shop

## Opens a shop for trading: loads its stock and gold, or restocks it if it is time.
## level_min / level_max: the land's levels (for gear and treasure). gold_scale: see GOLD_SCALE.
## Call close_shop() when done.
static func open_shop(shop_id: String, data: MerchantData, day: int, level_min: int = 1, level_max: int = 10, gold_scale: float = 1.0) -> Shop:
	var s := Shop.new()
	s.id = shop_id
	s.data = data
	s.inventory = Inventory.new()
	var rec := WorldState.get_record("shop/" + shop_id)
	var last := int(rec.get("restocked", -9999))
	if rec.is_empty() or day - last >= data.restock_days or day < last:
		_restock(s, day, level_min, level_max, gold_scale)
		save_shop(s)
	else:
		s.gold = int(rec.get("gold", 0))
		s.restocked_day = last
		s.inventory.from_dict(rec.get("stock", {}))
	return s


static func close_shop(s: Shop) -> void:
	if s != null and s.inventory != null and is_instance_valid(s.inventory):
		s.inventory.free()


static func save_shop(s: Shop) -> void:
	WorldState.set_record("shop/" + s.id, {"gold": s.gold, "restocked": s.restocked_day, "stock": s.inventory.to_dict()})


static func _restock(s: Shop, day: int, level_min: int, level_max: int, gold_scale: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|stock|%d" % [s.id, day]).hash()
	s.inventory.stacks.clear()
	var entries: Array[LootEntry] = s.data.stock.duplicate()
	if s.data.curve_stock:
		entries.append_array(ItemCatalog.curve_loot(level_min, level_max, s.data.curve_quality))
	if s.data.treasure_stock:
		entries.append_array(ItemCatalog.treasure_loot(level_min, level_max, 2.5))
	for e in entries:
		if e == null or e.item == null or rng.randf() > e.chance:
			continue
		s.inventory.add_item(e.item, rng.randi_range(e.min_count, maxi(e.min_count, e.max_count)))
	s.gold = roundi(float(rng.randi_range(s.data.gold_min, maxi(s.data.gold_min, s.data.gold_max))) * gold_scale)
	s.restocked_day = day


## Buys up to `count` of an item. Returns {"error": "" or why not, "count": bought, "gold": paid}
static func buy(s: Shop, player_inv: Inventory, item: ItemData, count: int, d: Deal) -> Dictionary:
	count = mini(count, s.inventory.get_count(item))
	if count <= 0:
		return {"error": "Sold out.", "count": 0, "gold": 0}
	var unit := buy_price(item, s.data, d)
	count = mini(count, Currency.get_gold(player_inv) / unit)
	if count <= 0:
		return {"error": "You can't afford that.", "count": 0, "gold": 0}
	var total := unit * count
	Currency.spend_gold(player_inv, total)
	s.inventory.remove_item(item, count)
	player_inv.add_item(item, count)
	s.gold += total
	save_shop(s)
	return {"error": "", "count": count, "gold": total}


## Sells up to `count` of an item. Never sells the last one you have equipped.
## Returns {"error": "" or why not, "count": sold, "gold": received}
static func sell(s: Shop, player_inv: Inventory, equipment: Equipment, item: ItemData, count: int, d: Deal) -> Dictionary:
	var unit := sell_price(item, s.data, d)
	if unit <= 0:
		return {"error": "%s doesn't buy that." % s.data.display_name, "count": 0, "gold": 0}
	count = mini(count, player_inv.get_count(item))
	var stolen := CrimeManager.stolen_count(player_inv, item)
	if not s.data.buys_stolen:
		count = mini(count, player_inv.get_count(item) - stolen)
		if count <= 0:
			return {"error": "%s won't touch stolen goods." % s.data.display_name, "count": 0, "gold": 0}
	if equipment != null and equipment.is_equipped(item) and player_inv.get_count(item) - count < 1:
		count -= 1
		if count <= 0:
			return {"error": "Unequip it first.", "count": 0, "gold": 0}
	count = mini(count, s.gold / unit)
	if count <= 0:
		return {"error": "The merchant doesn't have enough gold.", "count": 0, "gold": 0}
	var total := unit * count
	player_inv.remove_item(item, count)
	s.inventory.add_item(item, count)
	if s.data.buys_stolen and stolen > 0:
		CrimeManager.remove_stolen(item, mini(count, stolen))  # a fence takes the stolen ones first
	Currency.add_gold(player_inv, total)
	s.gold -= total
	save_shop(s)
	return {"error": "", "count": count, "gold": total}
