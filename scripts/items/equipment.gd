class_name Equipment
extends Node
## Equipped items STAY in the inventory (like Skyrim), so their weight still counts.
## Equipping only marks the item as worn and applies its stat modifiers.
##
## Hand rules:
##   - A two-handed item goes in the main hand and clears the off hand.
##   - Anything equipped to the off hand (shield, dual-wield weapon) clears a two-hander.
##   - A can_dual_wield weapon fills a free hand: main first, then off hand. equip_to() puts any
##     one-handed weapon in the hand you choose (the inventory: double click = right hand, right
##     click = left hand). Wielding the
##     same dagger in both hands needs two copies in the inventory.

signal equipped(slot: int, item: ItemData)
signal unequipped(slot: int, item: ItemData)

@export var inventory: Inventory
@export var stats: Stats

# ItemData.EquipSlot -> ItemData
var slots: Dictionary = {}


func _ready() -> void:
	# Falls back to sibling nodes named Inventory / Stats if the Inspector slots are empty
	if inventory == null:
		inventory = get_node_or_null("../Inventory")
	if stats == null:
		stats = get_node_or_null("../Stats")
	inventory.changed.connect(_on_inventory_changed)
	equipped.connect(func(_s, _i): _update_set_bonus())
	unequipped.connect(func(_s, _i): _update_set_bonus())


## All five pieces of one armor set worn: +10% armor
const SET_PIECES := 5
const SET_BONUS := {"armor_pct": 0.1}


func has_full_set() -> bool:
	var counts := {}
	for slot in slots:
		var item: ItemData = slots[slot]
		if item != null and item.armor_set != &"":
			counts[item.armor_set] = int(counts.get(item.armor_set, 0)) + 1
			if counts[item.armor_set] >= SET_PIECES:
				return true
	return false


func _update_set_bonus() -> void:
	if stats == null:
		return
	stats.remove_modifiers("equip_set")
	if has_full_set():
		stats.add_modifiers("equip_set", SET_BONUS)


func equip(item: ItemData) -> bool:
	if item == null or item.equip_slot == ItemData.EquipSlot.NONE:
		return false
	var owner_node := get_parent()
	if owner_node != null and owner_node.is_in_group("player"):
		if owner_node.has_meta("beast_form"):
			return false
		if CharacterSetup.forbidden(owner_node, item):
			Locks.toast(get_tree(), "You are forbidden to use %s" % item.display_name, true)
			return false
	if not inventory.has_item(item):
		return false
	# Every copy you own is already worn
	if equipped_count(item) >= inventory.get_count(item):
		return true

	var slot := _pick_slot(item)
	if slots.get(slot) == item:
		return true

	if item.two_handed:
		unequip(ItemData.EquipSlot.OFF_HAND)
	elif slot == ItemData.EquipSlot.OFF_HAND:
		var main: ItemData = slots.get(ItemData.EquipSlot.MAIN_HAND)
		if main != null and main.two_handed:
			unequip(ItemData.EquipSlot.MAIN_HAND)
	if slots.has(slot):
		unequip(slot)
	slots[slot] = item
	stats.add_modifiers(_source(slot), item.stat_modifiers)
	equipped.emit(slot, item)
	return true


func unequip(slot: int) -> void:
	if not slots.has(slot):
		return
	var item: ItemData = slots[slot]
	slots.erase(slot)
	stats.remove_modifiers(_source(slot))
	unequipped.emit(slot, item)


## Unequips every slot that holds this item (both hands for a pair of daggers)
func unequip_item(item: ItemData) -> void:
	for slot in slots.keys():
		if slots[slot] == item:
			unequip(slot)


## Puts a one-handed weapon in the hand you choose (MAIN_HAND right, OFF_HAND left); again on the
## same hand takes it off. With only one copy, it moves from the other hand. Anything else equips as usual.
func equip_to(item: ItemData, slot: int) -> bool:
	if item == null or not item.is_one_handed_weapon():
		return equip(item)
	if slots.get(slot) == item:
		unequip(slot)
		return true
	var other := ItemData.EquipSlot.OFF_HAND if slot == ItemData.EquipSlot.MAIN_HAND else ItemData.EquipSlot.MAIN_HAND
	if not _may_wear(item):
		return false
	if slots.get(other) == item and inventory.get_count(item) < 2:
		unequip(other)
	var main: ItemData = slots.get(ItemData.EquipSlot.MAIN_HAND)
	if slot == ItemData.EquipSlot.OFF_HAND and main != null and main.two_handed:
		unequip(ItemData.EquipSlot.MAIN_HAND)
	if slots.has(slot):
		unequip(slot)
	slots[slot] = item
	stats.add_modifiers(_source(slot), item.stat_modifiers)
	equipped.emit(slot, item)
	return true


# You own it, and nothing forbids you from using it
func _may_wear(item: ItemData) -> bool:
	var owner_node := get_parent()
	if owner_node != null and owner_node.is_in_group("player"):
		if owner_node.has_meta("beast_form"):
			return false
		if CharacterSetup.forbidden(owner_node, item):
			Locks.toast(get_tree(), "You are forbidden to use %s" % item.display_name, true)
			return false
	return inventory.has_item(item)


## Used by the inventory screen. Equips the item; with a second copy of a dual-wield weapon,
## pressing again fills the other hand; pressing once more takes it off.
func toggle(item: ItemData) -> void:
	var worn := equipped_count(item)
	if worn == 0:
		equip(item)
	elif worn < inventory.get_count(item) and _has_free_hand_for(item):
		equip(item)
	else:
		unequip_item(item)


## True if the item is worn in any slot
func is_equipped(item: ItemData) -> bool:
	return equipped_count(item) > 0


## How many slots hold this item (2 for a pair of daggers)
func equipped_count(item: ItemData) -> int:
	if item == null:
		return 0
	var n := 0
	for slot in slots:
		if slots[slot] == item:
			n += 1
	return n


func get_equipped(slot: int) -> ItemData:
	return slots.get(slot, null)


func get_main_hand() -> ItemData:
	return slots.get(ItemData.EquipSlot.MAIN_HAND, null)


func get_off_hand() -> ItemData:
	return slots.get(ItemData.EquipSlot.OFF_HAND, null)


# Which slot an item goes into. Only dual-wield weapons have a choice.
func _pick_slot(item: ItemData) -> int:
	if item.two_handed or not item.can_dual_wield or item.equip_slot != ItemData.EquipSlot.MAIN_HAND:
		return item.equip_slot
	var main: ItemData = slots.get(ItemData.EquipSlot.MAIN_HAND)
	var off: ItemData = slots.get(ItemData.EquipSlot.OFF_HAND)
	if main == null or main.two_handed:
		return ItemData.EquipSlot.MAIN_HAND
	if off == null:
		return ItemData.EquipSlot.OFF_HAND
	return ItemData.EquipSlot.MAIN_HAND


func _has_free_hand_for(item: ItemData) -> bool:
	if item.two_handed or not item.can_dual_wield:
		return false
	var main: ItemData = slots.get(ItemData.EquipSlot.MAIN_HAND)
	var off: ItemData = slots.get(ItemData.EquipSlot.OFF_HAND)
	return main == null or (off == null and not main.two_handed)


# If the last copy of an equipped item leaves the inventory (dropped, sold...), unequip it.
# Two daggers with one copy left: the off hand goes first.
func _on_inventory_changed() -> void:
	var keys := slots.keys()
	keys.sort()
	keys.reverse()
	for slot in keys:
		var item: ItemData = slots.get(slot)
		if item != null and equipped_count(item) > inventory.get_count(item):
			unequip(slot)


func _source(slot: int) -> String:
	return "equip_%d" % slot


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var out := {}
	for slot in slots:
		var path := SaveUtil.item_to_path(slots[slot])
		if path != "":
			out[str(slot)] = path
	return {"slots": out}


## Restores the exact slots that were saved (no hand-picking rules). Load the Inventory first:
## an item that is not in the inventory cannot be worn.
func from_dict(data: Dictionary) -> void:
	for slot in slots.keys():
		unequip(slot)
	var saved: Dictionary = data.get("slots", {})
	for key in saved:
		var item := SaveUtil.path_to_item(String(saved[key]))
		var slot := int(key)
		if item == null or equipped_count(item) >= inventory.get_count(item):
			continue
		slots[slot] = item
		stats.add_modifiers(_source(slot), item.stat_modifiers)
		equipped.emit(slot, item)
	_update_set_bonus()
