class_name ItemUse
extends RefCounted
## What "use" means for the stage 10 item kinds (the inventory's E button and the favorites menu):
## read a spell tome, eat a raw ingredient, put a poison on your blade, recharge an enchanted weapon.


## The button text, or "" when the item has no such use
static func verb(_player: Node, item: ItemData) -> String:
	if item == null:
		return ""
	if item.teaches_spell != "":
		return "Read"
	if LoreBooks.is_book(item):
		return "Read book"
	if String(item.id) == "horse_deed":
		return "Call your horse"
	if String(item.id) == "sellsword_contract":
		return "Hire a sellsword"
	if item.is_poison:
		return "Apply poison"
	if item.item_type == ItemData.ItemType.INGREDIENT and Alchemy.is_ingredient(item):
		return "Eat"
	if item.item_type == ItemData.ItemType.WEAPON and not item.enchant_effects.is_empty() and CraftedItems.is_crafted(item) \
			and CraftedItems.get_charge(item) < CraftedItems.get_max_charge(item) - 0.5:
		return "Recharge"
	return ""


static func use(player: Node, item: ItemData) -> void:
	var tree := player.get_tree()
	match verb(player, item):
		"Read book":
			BookUI.open(tree, item.display_name, LoreBooks.read(player, item))
		"Read":
			var book := player.get_node_or_null("Spellbook") as Spellbook
			var spell := SpellCatalog.get_spell(item.teaches_spell)
			var inv := player.get_node_or_null("Inventory") as Inventory
			if book == null or spell == null or inv == null:
				return
			if book.knows(spell.id):
				Locks.toast(tree, "You already know %s" % spell.display_name, true)
				return
			inv.remove_item(item, 1)
			book.learn(spell)
			Locks.toast(tree, "You learned the spell %s. Equip it from the Magic menu." % spell.display_name)
		"Hire a sellsword":
			var f := player.get_node_or_null("Followers") as Followers
			if f != null:
				var why := f.hire()
				if why == "":
					(player.get_node("Inventory") as Inventory).remove_item(item, 1)
					Locks.toast(tree, "A sellsword joins you")
				else:
					Locks.toast(tree, why, true)
		"Call your horse":
			var rider := player.get_node_or_null("Rider") as Rider
			if rider != null:
				rider.use_deed()
		"Apply poison":
			var why := WeaponMagic.apply_poison(player, item)
			Locks.toast(tree, why if why != "" else "Your weapon is poisoned (%s)" % item.display_name, why != "")
		"Eat":
			var learned := Alchemy.eat(player, item)
			if learned != "":
				Locks.toast(tree, learned)
		"Recharge":
			var why := WeaponMagic.recharge(player, item)
			Locks.toast(tree, why if why != "" else "%s is recharged" % item.display_name, why != "")
