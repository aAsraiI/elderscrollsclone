class_name LootMagic
extends RefCounted
## Now and then a weapon, armor piece or piece of jewelry found in a chest or on a body is already
## enchanted. That is where you learn enchantments: disenchant it at an Arcane Enchanter.

const CHANCE := 0.12
const JEWELRY_CHANCE := 0.35


## The item as rolled, or an enchanted copy of it
static func maybe_enchant(item: ItemData, rng: RandomNumberGenerator) -> ItemData:
	if item == null or not Enchanting.can_enchant(item) or CraftedItems.is_crafted(item):
		return item
	var jewelry := item.equip_slot == ItemData.EquipSlot.RING or item.equip_slot == ItemData.EquipSlot.AMULET
	if rng.randf() > (JEWELRY_CHANCE if jewelry else CHANCE):
		return item
	var on_weapon := item.item_type == ItemData.ItemType.WEAPON
	var keys: Array = Enchanting.WEAPON.keys() if on_weapon else Enchanting.WORN.keys()
	var effect: StringName = keys[rng.randi() % keys.size()]
	var size := clampi(item.tier - 1 + rng.randi_range(-1, 1), 0, 4)
	var e := Enchanting.make_effect(effect, size, 1.0 + float(item.tier) * 0.1, on_weapon)
	return CraftedItems.gear(item, 0, [e], SoulGems.CHARGE[size] if on_weapon else 0.0)
