@tool
extends McpTestSuite
## Checks the game's content without playing it: every quest, faction, book, item and data file
## points at things that exist. Runs inside the editor in a few seconds (Godot AI test runner):
## ask Claude to "run the editor tests", or use the test_run tool.
## The gameplay tests that need a running game are in res://test/ (see tools/run_tests.ps1).


func suite_name() -> String:
	return "game_data"


# Every quest's town names, as the quest data writes them ({"town": ...} and {"lord": ...})
func _towns_in(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			if (k == "town" or k == "lord") and v[k] is String:
				out[v[k]] = true
			_towns_in(v[k], out)
	elif v is Array:
		for x in v:
			_towns_in(x, out)


# Every res:// path written anywhere in a value
func _paths_in(v: Variant, out: Array) -> void:
	if v is String and (v as String).begins_with("res://"):
		out.append(v)
	elif v is Dictionary:
		for k in v:
			_paths_in(v[k], out)
	elif v is Array:
		for x in v:
			_paths_in(x, out)


func _settlement_names() -> Dictionary:
	var names := {}
	for biome in NamedSettlements.LIST:
		for s: Dictionary in NamedSettlements.LIST[biome]:
			names[String(s["name"])] = true
	return names


func test_all_quests_are_there() -> void:
	assert_eq(QuestBook.ids().size(), 336, "the lore bible's 336 quests")


func test_quests_name_real_towns() -> void:
	var known := _settlement_names()
	var bad: Array[String] = []
	for id in QuestBook.ids():
		var towns := {}
		_towns_in(QuestBook.get_def(id), towns)
		for t in towns:
			if not known.has(t):
				bad.append("%s: %s" % [id, t])
	assert_eq(bad, [] as Array[String], "quests that name a town that doesn't exist")


func test_quest_files_exist() -> void:
	var missing: Array[String] = []
	for id in QuestBook.ids():
		var paths := []
		_paths_in(QuestBook.get_def(id), paths)
		for p: String in paths:
			if not ResourceLoader.exists(p):
				missing.append("%s: %s" % [id, p])
	assert_eq(missing, [] as Array[String], "quest items and enemies that have no file")


func test_quest_order_is_possible() -> void:
	var bad: Array[String] = []
	for id in QuestBook.ids():
		for before: String in QuestBook.get_def(id).get("after", []):
			if QuestBook.get_def(before).is_empty():
				bad.append("%s waits for %s" % [id, before])
	assert_eq(bad, [] as Array[String], "quests that wait for a quest that doesn't exist")


func test_factions_point_at_real_quests() -> void:
	var bad: Array[String] = []
	var count := 0
	for f in DirAccess.get_files_at("res://data/factions"):
		if not f.ends_with(".tres"):
			continue
		var d := load("res://data/factions/" + f) as FactionData
		assert_true(d != null, "faction %s loads" % f)
		count += 1
		for q in [d.join_quest, d.penance_quest]:
			if q != "" and QuestBook.get_def(q).is_empty():
				bad.append("%s: %s" % [f, q])
	assert_eq(count, 20, "20 factions")
	assert_eq(bad, [] as Array[String], "factions whose join or penance quest doesn't exist")


func test_lore_books() -> void:
	assert_eq(LoreBooks.LIST.size(), 72, "72 lore books")


func test_every_data_file_loads() -> void:
	var broken: Array[String] = []
	var dirs: Array[String] = ["res://data"]
	var count := 0
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tres"):
				count += 1
				if load(dir + "/" + f) == null:
					broken.append(dir + "/" + f)
	assert_gt(count, 600, "the data folder has all its files")
	assert_eq(broken, [] as Array[String], "data files that don't load")


# Loads the item folders the catalog scans (ItemCatalog.all_items() itself crashes when run inside
# the editor, so the folders are read here directly)
func test_items_catalog() -> void:
	var count := 0
	var not_items: Array[String] = []
	for dir: String in ItemCatalog.ITEM_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tres"):
				count += 1
				if not (load(dir + f) is ItemData):
					not_items.append(dir + f)
	assert_gt(count, 300, "the item folders hold the items")
	assert_eq(not_items, [] as Array[String], "files in item folders that aren't items")


func test_old_save_paths_map_to_real_files() -> void:
	var missing: Array[String] = []
	for pair in SaveUtil.MOVED_PATHS:
		var to := String(pair[1])
		if not to.ends_with("/") and not ResourceLoader.exists(to):
			missing.append(to)
	assert_eq(missing, [] as Array[String], "moved files that aren't where old saves are sent")
	assert_eq(SaveUtil.migrate_moved_paths("res://scripts/Resources/Consumables/apple.tres"), "res://data/consumables/apple.tres")
	assert_eq(SaveUtil.migrate_moved_paths({"item": "res://scripts/Resources/iron_sword.tres"}), {"item": "res://data/weapons/iron_sword.tres"})
