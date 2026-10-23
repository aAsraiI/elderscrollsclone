class_name Inventory
extends Node
## Unlimited slots, weight-based encumbrance (Elder Scrolls style).

signal changed

class Stack:
	var item: ItemData
	var count: int

	func _init(i: ItemData, c: int) -> void:
		item = i
		count = c

## Optional: used for carry capacity
@export var stats: Stats

var stacks: Array[Stack] = []


func add_item(item: ItemData, count: int = 1) -> void:
	if item == null or count <= 0:
		return
	if item.stackable:
		for s in stacks:
			if s.item == item and s.count < item.max_stack:
				var moved := mini(item.max_stack - s.count, count)
				s.count += moved
				count -= moved
				if count == 0:
					break
	while count > 0:
		var n: int = mini(count, item.max_stack) if item.stackable else 1
		stacks.append(Stack.new(item, n))
		count -= n
	changed.emit()


func remove_item(item: ItemData, count: int = 1) -> bool:
	if get_count(item) < count:
		return false
	for i in range(stacks.size() - 1, -1, -1):
		if stacks[i].item != item:
			continue
		var taken := mini(stacks[i].count, count)
		stacks[i].count -= taken
		count -= taken
		if stacks[i].count == 0:
			stacks.remove_at(i)
		if count == 0:
			break
	changed.emit()
	return true


func get_count(item: ItemData) -> int:
	var total := 0
	for s in stacks:
		if s.item == item:
			total += s.count
	return total


func has_item(item: ItemData, count: int = 1) -> bool:
	return get_count(item) >= count


func get_total_weight() -> float:
	var total := 0.0
	for s in stacks:
		total += s.item.weight * s.count
	return total


func is_overencumbered() -> bool:
	return stats != null and get_total_weight() > stats.get_stat("carry_capacity")


# ---------------------------------------------------------------- saving

## Items are stored by resource path, so an item must be a saved .tres file to survive a save
func to_dict() -> Dictionary:
	var out: Array = []
	for s in stacks:
		var path := SaveUtil.item_to_path(s.item)
		if path == "":
			push_warning("Inventory: '%s' is not a saved .tres item and cannot be saved." % s.item.display_name)
			continue
		out.append({"item": path, "count": s.count})
	return {"stacks": out}


func from_dict(data: Dictionary) -> void:
	stacks.clear()
	for entry in data.get("stacks", []):
		var path := String(entry.get("item", ""))
		var item := SaveUtil.path_to_item(path)
		if item == null:
			push_warning("Inventory: saved item '%s' no longer exists and was dropped." % path)
			continue
		stacks.append(Stack.new(item, maxi(int(entry.get("count", 1)), 1)))
	changed.emit()
