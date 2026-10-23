class_name Marriage
extends RefCounted
## Marriage. Anyone in a town who likes you enough (disposition 80+; not guards or lords) will
## talk about "marriage"; bring a ring and ask, and they say yes. Your spouse then keeps a little
## shop: you can always trade with them (general goods), and "our shop" hands you their takings,
## SHOP_TAKINGS gold for every day since you last asked (up to a week's worth).
## Saved in WorldState under "marriage": {"spouse", "name", "town", "day", "paid"}.

const MIN_DISPOSITION := 80
const SHOP_TAKINGS := 60
const MAX_DAYS := 7
const TOPICS: Array[String] = ["marriage", "our shop"]
const SHOP_ID := "spouse"


static func spouse_id() -> String:
	return String(WorldState.get_record("marriage").get("spouse", ""))


static func spouse_name() -> String:
	return String(WorldState.get_record("marriage").get("name", ""))


static func is_married() -> bool:
	return spouse_id() != ""


static func is_spouse(s: DialogueEngine.Speaker) -> bool:
	return s != null and s.data != null and is_married() and s.data.id == spouse_id()


## Could this person marry you (if they liked you enough)?
static func can_marry(s: DialogueEngine.Speaker) -> bool:
	if s == null or s.data == null or s.id == "" or s.asleep or is_married():
		return false
	return not s.role in [NpcData.Role.GUARD, NpcData.Role.LORD]


static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	if is_spouse(s):
		return PackedStringArray(["our shop"])
	if can_marry(s) and DialogueEngine.get_disposition(s) >= MIN_DISPOSITION:
		return PackedStringArray(["marriage"])
	return PackedStringArray()


## A ring the player carries (any ring will do), or null
static func _ring(inv: Inventory) -> ItemData:
	for st in inv.stacks:
		if st.item != null and st.item.equip_slot == ItemData.EquipSlot.RING:
			return st.item
	return null


## The answer for "marriage" / "our shop", or {} when it isn't one of those
static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, today: int) -> Dictionary:
	if not TOPICS.has(topic) or not topics_for(s).has(topic):
		return {}
	var inv := player.get_node("Inventory") as Inventory
	if topic == "marriage":
		var ring := _ring(inv)
		if ring == null:
			return _say("Marriage? ...You'd have to ask me properly. With a ring.")
		var equipment := player.get_node_or_null("Equipment") as Equipment
		if equipment != null and inv.get_count(ring) <= 1:
			equipment.unequip_item(ring)
		inv.remove_item(ring, 1)
		WorldState.set_record("marriage", {"spouse": s.data.id, "name": s.name, "town": s.town.id if s.town != null else "",
			"day": today, "paid": today})
		return _say("Yes. Yes! I'll wear it always. And listen: I've always wanted a little shop of my own. "
			+ "Come and trade with me any time, and ask about our shop, I'll keep your share of the takings.")
	# our shop
	var rec := WorldState.get_record("marriage")
	var days := clampi(today - int(rec.get("paid", today)), 0, MAX_DAYS)
	if days == 0:
		return _say("Nothing yet today, love. Come back tomorrow and there'll be something for you.")
	var gold := days * SHOP_TAKINGS
	Currency.add_gold(inv, gold)
	rec["paid"] = today
	WorldState.set_record("marriage", rec)
	return _say("Business is good. Here's your share: %d gold." % gold)


static func _say(text: String) -> Dictionary:
	return {"text": text, "journal": false, "quest_id": "", "quest_name": "", "learn": PackedStringArray()}
