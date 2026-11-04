class_name Durability
extends RefCounted
## Alpha 1.27.2: weapons and armour wear down (World Creation: Gear wears down, on by default).
## Every hit you land wears your weapon a little, every hit you take wears a piece of the armour
## you have on; Smithing slows it. Kept per kind of item (most people carry one of each), 0-100,
## in WorldState "wear" {item id: condition}; an item never used is at 100.
##   100-50  as good as new
##   50-0    a weapon hits softer and armour stops less, down to half at 0 (broken)
## Repair: a Repair Hammer (workbench; E in the inventory mends what you wear, more with Smithing),
## or a smith's Repair button (gold, by how worn it is). Morrowind's armorer, kept simple.

const RECORD := "wear"
const WEAPON_WEAR := 0.2
const ARMOR_WEAR := 0.3
const FULL_AT := 50.0
const BROKEN_MULT := 0.5
## A repair hammer mends this much, plus HAMMER_PER_SKILL x Smithing, on every piece worn
const HAMMER := 20.0
const HAMMER_PER_SKILL := 0.4
## Gold per point of wear a smith mends, per 100 value of the item (at least 1)
const SMITH_RATE := 0.02


static func enabled() -> bool:
	return bool(GameRules.get_rule("durability"))


static func condition(item: ItemData) -> float:
	if item == null:
		return 100.0
	return float(WorldState.get_record(RECORD).get(String(item.id), 100.0))


static func _store(item: ItemData, c: float) -> void:
	var rec: Dictionary = WorldState.get_record(RECORD).duplicate()
	c = clampf(c, 0.0, 100.0)
	if c >= 100.0:
		rec.erase(String(item.id))
	else:
		rec[String(item.id)] = snappedf(c, 0.01)
	WorldState.set_record(RECORD, rec)


## Does this item wear? (weapons, shields and armour; not arrows, bolts or thrown weapons)
static func wears(item: ItemData) -> bool:
	if item == null or item.is_arrow or item.is_thrown or item.stackable:
		return false
	return item.item_type in [ItemData.ItemType.WEAPON, ItemData.ItemType.ARMOR]


static func mult_for(c: float) -> float:
	if c >= FULL_AT:
		return 1.0
	return lerpf(BROKEN_MULT, 1.0, c / FULL_AT)


## The damage of a hit with this weapon, as a part of new
static func weapon_mult(item: ItemData) -> float:
	if not enabled() or not wears(item):
		return 1.0
	return mult_for(condition(item))


static func _skill_slow(player: Node) -> float:
	var sk := player.get_node_or_null("Skills") as Skills if player != null else null
	return 1.0 - minf(float(sk.get_level(&"smithing")) / 200.0, 0.75) if sk != null else 1.0


## A hit landed (BuildHooks.outgoing_mult, for the player)
static func wear_weapon(item: ItemData, player: Node) -> void:
	if not enabled() or not wears(item):
		return
	var before := condition(item)
	var after := before - WEAPON_WEAR * _skill_slow(player)
	_store(item, after)
	_warn(player, item, before, after)


## The armour worn, as a part of new (the average of the worn pieces)
static func armor_mult(player: Node) -> float:
	if not enabled():
		return 1.0
	var worn := _worn_armor(player)
	if worn.is_empty():
		return 1.0
	var total := 0.0
	for it in worn:
		total += mult_for(condition(it))
	return total / worn.size()


## A hit taken (MeleeCombat.take_damage, for the player): one piece takes it
static func wear_armor(player: Node) -> void:
	if not enabled():
		return
	var worn := _worn_armor(player)
	if worn.is_empty():
		return
	var it: ItemData = worn[randi() % worn.size()]
	var before := condition(it)
	var after := before - ARMOR_WEAR * _skill_slow(player)
	_store(it, after)
	_warn(player, it, before, after)


static func _worn_armor(player: Node) -> Array[ItemData]:
	var out: Array[ItemData] = []
	var eq := player.get_node_or_null("Equipment") as Equipment if player != null else null
	if eq == null:
		return out
	for slot in eq.slots:
		var it: ItemData = eq.slots[slot]
		if it != null and wears(it) and (it.item_type == ItemData.ItemType.ARMOR or it.secondary_action == ItemData.SecondaryAction.BLOCK) and it.item_type != ItemData.ItemType.WEAPON:
			out.append(it)
	return out


static func worn_gear(player: Node) -> Array[ItemData]:
	var out: Array[ItemData] = []
	var eq := player.get_node_or_null("Equipment") as Equipment if player != null else null
	if eq == null:
		return out
	for slot in eq.slots:
		var it: ItemData = eq.slots[slot]
		if it != null and wears(it) and not out.has(it):
			out.append(it)
	return out


static func _warn(player: Node, item: ItemData, before: float, after: float) -> void:
	if player == null or not player.is_inside_tree():
		return
	if before >= FULL_AT and after < FULL_AT:
		Locks.toast(player.get_tree(), "Your %s is wearing out. Have it repaired." % item.display_name, true)
	elif before > 0.0 and after <= 0.0:
		Locks.toast(player.get_tree(), "Your %s is broken." % item.display_name, true)


## "Condition 42%" for the inventory ("" when it is like new or wear is off)
static func text(item: ItemData) -> String:
	if not enabled() or not wears(item):
		return ""
	var c := condition(item)
	if c >= 100.0:
		return ""
	return "Condition %d%%%s" % [roundi(c), "  (broken)" if c <= 0.0 else ("  (worn: weaker)" if c < FULL_AT else "")]


## Mends everything worn by this much. Returns how many pieces were mended.
static func mend_worn(player: Node, amount: float) -> int:
	var n := 0
	for it in worn_gear(player):
		if condition(it) < 100.0:
			_store(it, condition(it) + amount)
			n += 1
	return n


## A smith's price to mend everything worn
static func smith_price(player: Node) -> int:
	var gold := 0.0
	for it in worn_gear(player):
		gold += (100.0 - condition(it)) * maxf(float(it.value) / 100.0, 1.0) * SMITH_RATE
	return ceili(gold) if gold > 0.0 else 0


## A Repair Hammer (ItemUse)
static func use_hammer(player: Node, hammer: ItemData) -> String:
	if not enabled():
		return "Your gear does not wear in this world."
	var sk := player.get_node_or_null("Skills") as Skills
	var amount := HAMMER + HAMMER_PER_SKILL * (float(sk.get_level(&"smithing")) if sk != null else 15.0)
	var n := mend_worn(player, amount)
	if n == 0:
		return "Nothing you wear needs mending."
	(player.get_node("Inventory") as Inventory).remove_item(hammer, 1)
	if sk != null:
		sk.add_xp(&"smithing", 3.0 * n)
	Achievements.note("repair")
	return "You mend %d piece%s (+%d)." % [n, "" if n == 1 else "s", roundi(amount)]
