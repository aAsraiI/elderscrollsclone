class_name WeaponMagic
extends RefCounted
## What rides on a weapon hit besides the steel: the weapon's enchantment (uses up charge) and a
## poison you put on the blade (lasts a few hits). MeleeCombat._deal calls on_hit().

const POISON_HITS := 3
## Charge used per hit = the enchantment's magicka cost x this
const CHARGE_PER_COST := 0.6


static func on_hit(attacker: Node3D, victim: Node3D, weapon: ItemData, _info: DamageInfo) -> void:
	if attacker == null or victim == null or not is_instance_valid(victim):
		return
	var m := ActiveMagic.of(victim)
	if m == null or m.stats == null or m.stats.is_dead:
		return
	if weapon != null and not weapon.enchant_effects.is_empty():
		var cost := charge_cost(weapon)
		var charge := CraftedItems.get_charge(weapon) if CraftedItems.is_crafted(weapon) else INF
		if charge >= cost:
			m.apply_list(weapon.enchant_effects, attacker, weapon.display_name, "enchant")
			if CraftedItems.is_crafted(weapon):
				CraftedItems.set_charge(weapon, charge - cost)
				if charge - cost < cost and attacker.is_in_group("player"):
					Locks.toast(attacker.get_tree(), "%s is out of charge. Recharge it with a filled soul gem." % weapon.display_name, true)
	var poison: Dictionary = attacker.get_meta("weapon_poison", {})
	if not poison.is_empty():
		m.apply_list(poison.get("effects", []), attacker, String(poison.get("name", "Poison")), "poison")
		poison["hits"] = int(poison.get("hits", 1)) - 1
		if int(poison["hits"]) <= 0:
			attacker.remove_meta("weapon_poison")
		else:
			attacker.set_meta("weapon_poison", poison)


static func charge_cost(weapon: ItemData) -> float:
	var c := 0.0
	for e in weapon.enchant_effects:
		c += SpellData.effect_cost(e)
	return maxf(c * CHARGE_PER_COST, 4.0)


## Puts a poison on whatever is in your main hand. Returns "" or why not.
static func apply_poison(player: Node, poison: ItemData) -> String:
	var eq := player.get_node_or_null("Equipment") as Equipment
	var inv := player.get_node_or_null("Inventory") as Inventory
	if eq == null or inv == null or not inv.has_item(poison):
		return "You have none."
	if eq.get_main_hand() == null:
		return "Hold a weapon first."
	inv.remove_item(poison, 1)
	var hits := POISON_HITS
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		hits += skills.get_level(&"alchemy") / 30
	player.set_meta("weapon_poison", {"effects": poison.magic_effects.duplicate(true), "hits": hits, "name": poison.display_name})
	return ""


## Fills a weapon's charge from a filled soul gem. Returns "" or why not.
static func recharge(player: Node, weapon: ItemData) -> String:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or not CraftedItems.is_crafted(weapon) or weapon.enchant_effects.is_empty():
		return "That isn't an enchanted weapon."
	if CraftedItems.get_charge(weapon) >= CraftedItems.get_max_charge(weapon) - 0.5:
		return "It is fully charged."
	for size in 5:
		var gem := SoulGems.gem(size, true)
		if gem != null and inv.has_item(gem):
			inv.remove_item(gem, 1)
			CraftedItems.set_charge(weapon, CraftedItems.get_charge(weapon) + SoulGems.CHARGE[size])
			return ""
	return "You need a filled soul gem."
