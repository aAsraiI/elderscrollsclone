class_name SaveUtil
extends RefCounted
## Small helpers shared by everything that saves: JSON-friendly conversions and safe file IO.
## Save data may only contain things JSON can hold: numbers, strings, bools, arrays and
## dictionaries. Vector3 becomes [x, y, z]; items are stored by their resource path.

static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## "res://scripts/Resources/iron_sword.tres". Keys made at runtime save as "key://..." (KeyRing).
## Empty for other items made at runtime (they can't be saved).
static func item_to_path(item: ItemData) -> String:
	if item == null:
		return ""
	if item.has_meta("save_path"):
		return String(item.get_meta("save_path"))
	return item.resource_path


static func path_to_item(path: String) -> ItemData:
	if KeyRing.is_key_path(path):
		return KeyRing.from_path(path)
	if QuestItems.is_path(path):
		return QuestItems.from_path(path)
	if LoreBooks.is_path(path):
		return LoreBooks.from_path(path)
	if CraftedItems.is_path(path):
		return CraftedItems.from_path(path)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as ItemData


## Writes JSON so that a crash or a full disk can never leave a half-written save behind:
## write to .tmp, check it reads back, keep the old file as .bak, then rename into place.
static func write_json_atomic(path: String, data: Variant, keep_backup: bool = true) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if read_json(tmp) == null:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if keep_backup:
			DirAccess.rename_absolute(path, path + ".bak")
		else:
			DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Parsed JSON, or null if the file is missing or damaged
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## "1h 05m" / "12m" / "40s"
static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm" % (s / 60)
	return "%ds" % s
