class_name QuestItems
extends RefCounted
## Items that only exist for one quest (a stolen ledger, a sealed package), made at runtime like
## keys. They save as "quest://<quest id>#<name>" (see SaveUtil) and merchants won't buy them.

const PREFIX := "quest://"

static var _items := {}  # quest id -> ItemData


static func get_item(quest_id: String, item_name: String = "") -> ItemData:
	if _items.has(quest_id):
		return _items[quest_id]
	var it := ItemData.new()
	it.id = &"quest_item"
	it.display_name = item_name if item_name != "" else "Quest Item"
	it.description = "Wanted by someone for a job. Not worth selling."
	it.item_type = ItemData.ItemType.MISC
	it.weight = 0.5
	it.value = 0
	it.set_meta("quest_id", quest_id)
	it.set_meta("save_path", "%s%s#%s" % [PREFIX, quest_id, item_name])
	_items[quest_id] = it
	return it


static func is_quest_item(item: ItemData) -> bool:
	return item != null and item.has_meta("quest_id")


static func is_path(path: String) -> bool:
	return path.begins_with(PREFIX)


static func from_path(path: String) -> ItemData:
	var rest := path.trim_prefix(PREFIX)
	var cut := rest.find("#")
	if cut < 0:
		return get_item(rest)
	return get_item(rest.substr(0, cut), rest.substr(cut + 1))
