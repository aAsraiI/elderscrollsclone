class_name Enchanting
extends RefCounted
## Skyrim-style enchanting at an Arcane Enchanter:
##   Disenchant  destroy an enchanted item to LEARN its enchantment (Spellbook.enchantments)
##   Enchant     a plain weapon, armor piece, clothing or jewelry + a learned enchantment + a
##               filled soul gem = an enchanted item. Strength: soul size x Enchanting skill.
## Weapons get "on hit" enchantments (they use charge), everything you wear gets "always on" ones.
## Also LootMagic: now and then gear found in the world is already enchanted.

## Weapon enchantments: id -> [magnitude at full strength, duration]
const WEAPON := {
	&"fire_damage": [12.0, 0.0], &"frost_damage": [12.0, 0.0], &"shock_damage": [12.0, 0.0],
	&"poison_damage": [3.0, 4.0], &"absorb_health": [7.0, 0.0], &"absorb_stamina": [12.0, 0.0],
	&"absorb_magicka": [12.0, 0.0], &"damage_stamina": [18.0, 0.0], &"damage_magicka": [18.0, 0.0],
	&"paralyze": [0.0, 2.0], &"soul_trap": [0.0, 6.0], &"fear": [12.0, 8.0],
}
## Worn enchantments: id -> magnitude at full strength
const WORN := {
	&"fortify_health": 30.0, &"fortify_magicka": 30.0, &"fortify_stamina": 30.0,
	&"fortify_strength": 6.0, &"fortify_agility": 6.0, &"fortify_endurance": 6.0, &"fortify_wisdom": 6.0, &"fortify_charisma": 6.0,
	&"fortify_attack": 12.0, &"regenerate_health": 12.0, &"regenerate_magicka": 35.0, &"regenerate_stamina": 35.0,
	&"resist_fire": 25.0, &"resist_frost": 25.0, &"resist_shock": 25.0, &"resist_poison": 30.0, &"resist_magic": 12.0,
	&"shield": 10.0, &"feather": 30.0, &"haste": 10.0, &"jump": 30.0, &"muffle": 1.0, &"night_eye": 1.0,
	&"fortify_block": 12.0, &"fortify_sneak": 15.0, &"fortify_speech": 10.0, &"fortify_lockpicking": 15.0,
	&"fortify_smithing": 12.0, &"fortify_alchemy": 12.0, &"fortify_magic": 8.0, &"spell_absorption": 8.0, &"reflect": 8.0,
}
const XP_PER_ENCHANT := 25.0


static func can_enchant(item: ItemData) -> bool:
	if item == null or not item.enchant_effects.is_empty():
		return false
	return item.item_type == ItemData.ItemType.WEAPON or item.equip_slot in [ItemData.EquipSlot.HEAD, ItemData.EquipSlot.CHEST,
		ItemData.EquipSlot.HANDS, ItemData.EquipSlot.LEGS, ItemData.EquipSlot.FEET, ItemData.EquipSlot.RING,
		ItemData.EquipSlot.AMULET, ItemData.EquipSlot.OFF_HAND]


static func fits(effect: StringName, item: ItemData) -> bool:
	if item == null:
		return false
	return WEAPON.has(effect) if item.item_type == ItemData.ItemType.WEAPON else WORN.has(effect)


## Strength from the skill and Fortify Enchanting
static func skill_mult(player: Node) -> float:
	var skills := player.get_node_or_null("Skills") as Skills
	var stats := player.get_node_or_null("Stats") as Stats
	var lvl := skills.get_level(&"enchanting") if skills != null else 1
	return 1.0 + float(lvl) * 0.015 + (stats.get_stat("enchanting_potency") if stats != null else 0.0)


## The effect an enchantment would have: {"id", "mag", "dur"}
static func make_effect(effect: StringName, gem_size: int, mult: float, on_weapon: bool) -> Dictionary:
	var power: float = SoulGems.POWER[clampi(gem_size, 0, 4)] * mult
	if on_weapon:
		var w: Array = WEAPON[effect]
		var mag := float(w[0]) * power
		if effect == &"fear":
			mag = float(w[0]) * power * 1.5  # a level cap
		return {"id": effect, "mag": roundf(mag), "dur": roundf(float(w[1]) * (0.6 + power * 0.4))}
	var base: float = WORN[effect]
	var m := base * power if base > 1.0 else 1.0
	return {"id": effect, "mag": maxf(roundf(m), 1.0), "dur": 0.0}


## Enchants an item. Uses up the item and the gem; gives back the new item (or null).
static func enchant(player: Node, item: ItemData, effect: StringName, gem: ItemData, custom_name: String = "") -> ItemData:
	var inv := player.get_node_or_null("Inventory") as Inventory
	var size := SoulGems.filled_size(gem)
	if inv == null or size < 0 or not can_enchant(item) or not fits(effect, item) or not inv.has_item(item) or not inv.has_item(gem):
		return null
	var on_weapon := item.item_type == ItemData.ItemType.WEAPON
	var e := make_effect(effect, size, skill_mult(player), on_weapon)
	var q := item.quality
	var eq := player.get_node_or_null("Equipment") as Equipment
	if eq != null:
		eq.unequip_item(item)
	inv.remove_item(item, 1)
	inv.remove_item(gem, 1)
	var made := CraftedItems.gear(item, q, [e], SoulGems.CHARGE[size] if on_weapon else 0.0, custom_name)
	inv.add_item(made, 1)
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_xp(&"enchanting", XP_PER_ENCHANT * (1.0 + size * 0.5))
	return made


## Destroys an enchanted item and learns what was on it. Returns the learned effect ids.
static func disenchant(player: Node, item: ItemData) -> Array[StringName]:
	var learned: Array[StringName] = []
	var inv := player.get_node_or_null("Inventory") as Inventory
	var book := player.get_node_or_null("Spellbook") as Spellbook
	if inv == null or book == null or item == null or item.enchant_effects.is_empty() or not inv.has_item(item):
		return learned
	var eq := player.get_node_or_null("Equipment") as Equipment
	if eq != null:
		eq.unequip_item(item)
	inv.remove_item(item, 1)
	for e in item.enchant_effects:
		if book.learn_enchantment(StringName(e["id"])):
			learned.append(StringName(e["id"]))
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_xp(&"enchanting", XP_PER_ENCHANT * 0.6)
	return learned
