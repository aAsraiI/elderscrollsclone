class_name KeyRing
extends RefCounted
## Keys are items made at runtime, one per lock: KeyRing.get_key("r0_1/village/0/b3", "Brenna's House").
## Asking twice for the same lock gives the very same ItemData, so keys stack and compare like any
## other item. They save as "key://<lock id>#<name>" (see SaveUtil), so no .tres file is needed.

const PREFIX := "key://"

static var _keys := {}  # lock id -> ItemData


static func get_key(lock_id: String, lock_name: String = "") -> ItemData:
	if _keys.has(lock_id):
		return _keys[lock_id]
	var key := ItemData.new()
	key.id = &"key"
	key.display_name = "Key: %s" % (lock_name if lock_name != "" else lock_id)
	key.description = "Opens the door of %s." % (lock_name if lock_name != "" else "a building")
	key.item_type = ItemData.ItemType.KEY
	key.weight = 0.0
	key.value = 0
	key.set_meta("lock_id", lock_id)
	key.set_meta("save_path", "%s%s#%s" % [PREFIX, lock_id, lock_name])
	_keys[lock_id] = key
	return key


## The lock a key opens, "" for anything that is not a key
static func lock_id_of(item: ItemData) -> String:
	return String(item.get_meta("lock_id", "")) if item != null else ""


static func is_key_path(path: String) -> bool:
	return path.begins_with(PREFIX)


static func from_path(path: String) -> ItemData:
	var rest := path.trim_prefix(PREFIX)
	var cut := rest.find("#")
	if cut < 0:
		return get_key(rest)
	return get_key(rest.substr(0, cut), rest.substr(cut + 1))


## Forgets every key made so far (GameState.reset)
static func clear() -> void:
	_keys.clear()
