class_name CharacterSetup
extends RefCounted
## Turns the choices of the Character Creation screen into the player: race and birthsign traits,
## advantages and disadvantages, class skills, starting gear and spells, the racial power, and an
## affliction you chose to start with. The choices are kept in the save ("character") and the
## lasting parts (traits, forbidden gear, leveling speed) are applied again on every load.
##
## data: {"name", "race", "sex", "skin", "hair", "height", "class", "advantages": [], "disadvantages": [],
##        "sign", "affliction": "" | "vampire" | "werewolf"}

static var pending: Dictionary = {}


static func has_pending() -> bool:
	return not pending.is_empty()


static func default_data() -> Dictionary:
	return {"name": "Traveler", "race": "heartlander", "sex": 0, "skin": 0, "hair": 0, "height": 1.0, "class": "warrior",
		"advantages": [], "disadvantages": [], "sign": "sword", "affliction": ""}


## fresh = a brand new character (skills, gear and spells too); otherwise only the lasting traits
static func apply(player: Node, data: Dictionary, fresh: bool) -> void:
	if data.is_empty():
		return
	player.set_meta("character", data.duplicate(true))
	var stats := player.get_node_or_null("Stats") as Stats
	var skills := player.get_node_or_null("Skills") as Skills
	var race := Races.get_race(String(data.get("race", "heartlander")))
	if stats != null:
		stats.add_modifiers("race", race.get("stats", {}))
		var birth_sign: Dictionary = Classes.SIGNS.get(String(data.get("sign", "")), {})
		stats.add_modifiers("sign", birth_sign.get("stats", {}))
		var traits := {}
		var forbid := {}
		var sun_sick := false
		for a in data.get("advantages", []):
			_merge(traits, Classes.ADVANTAGES.get(a, {}).get("stats", {}))
		for d in data.get("disadvantages", []):
			var dd: Dictionary = Classes.DISADVANTAGES.get(d, {})
			_merge(traits, dd.get("stats", {}))
			if dd.has("forbid"):
				forbid[dd["forbid"]] = true
			if dd.get("sun_sick", false):
				sun_sick = true
		stats.add_modifiers("traits", traits)
		player.set_meta("forbid", forbid)
		player.set_meta("sun_sick", sun_sick)
	if skills != null:
		skills.xp_rate = float(GameRules.get_rule("xp_rate")) * Classes.xp_mult(data.get("advantages", []), data.get("disadvantages", []))
	var powers := player.get_node_or_null("Powers") as Powers
	if powers != null:
		powers.racial = String(race.get("power", ""))
	if not fresh:
		return
	# ---- a new character: skills, gear, spells
	var cls := Classes.get_class_data(String(data.get("class", "warrior")))
	if skills != null:
		var bonus := {}
		for s in cls["major"]:
			bonus[s] = int(bonus.get(s, 0)) + 10
		for s in cls["minor"]:
			bonus[s] = int(bonus.get(s, 0)) + 5
		for s in race.get("skills", {}):
			bonus[s] = int(bonus.get(s, 0)) + int(race["skills"][s])
		skills.set_starting_levels(bonus)
	var inv := player.get_node_or_null("Inventory") as Inventory
	var eq := player.get_node_or_null("Equipment") as Equipment
	if inv != null:
		for slot in eq.slots.keys() if eq != null else []:
			eq.unequip(slot)
		var gold := Currency.get_gold(inv)
		inv.stacks.clear()
		inv.changed.emit()
		Currency.add_gold(inv, maxi(gold, 0) if gold > 0 else 100)
		for g in cls["gear"]:
			var it := load(String(g[0])) as ItemData if ResourceLoader.exists(String(g[0])) else null
			if it == null:
				continue
			inv.add_item(it, int(g[1]))
			if eq != null and it.equip_slot != ItemData.EquipSlot.NONE and not CharacterSetup.forbidden(player, it):
				eq.equip(it)
		for f in ["bread", "apple"]:
			var food := load("res://data/consumables/%s.tres" % f) as ItemData
			if food != null:
				inv.add_item(food, 2)
	var book := player.get_node_or_null("Spellbook") as Spellbook
	if book != null:
		for id in cls["spells"]:
			book.learn(SpellCatalog.get_spell(id), true)
	var aff := player.get_node_or_null("Afflictions") as Afflictions
	if aff != null:
		match String(data.get("affliction", "")):
			"vampire":
				aff.become_vampire()
			"werewolf":
				aff.become_werewolf()


static func _merge(into: Dictionary, add: Dictionary) -> void:
	for k in add:
		into[k] = float(into.get(k, 0.0)) + float(add[k])


## Gear this character may not use (a disadvantage)
static func forbidden(player: Node, item: ItemData) -> bool:
	if item == null or not player.has_meta("forbid"):
		return false
	var f: Dictionary = player.get_meta("forbid")
	if f.has("heavy_armor") and item.governing_skill == "heavy_armor":
		return true
	if f.has("two_handed") and item.two_handed:
		return true
	if f.has("shield") and item.item_type != ItemData.ItemType.WEAPON and item.secondary_action == ItemData.SecondaryAction.BLOCK:
		return true
	return false


## "Ysolda the Woodborn Ranger"
static func title_of(data: Dictionary) -> String:
	return "%s, %s %s" % [data.get("name", "Traveler"), Races.get_race(String(data.get("race", ""))).get("name", ""),
		Classes.get_class_data(String(data.get("class", ""))).get("name", "")]
