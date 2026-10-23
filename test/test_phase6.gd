extends SceneTree
## Headless tests for rebuild phase 6 (quality of life): number-key quick slots, map markers,
## the tracked quest, graphics presets, value per weight, the wait buttons, the loading screen,
## and that tests never touch the player's autosave.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_phase6.gd

var passes := 0
var fails := 0


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await frames(2)
	t_quick_slots()
	t_markers()
	t_tracking()
	t_presets()
	t_value_per_weight()
	await t_loading_screen()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_quick_slots() -> void:
	print("-- quick slots")
	var book := Spellbook.new()
	book.toggle_favorite("spell:firebolt")
	book.toggle_favorite("res://data/consumables/apple.tres")
	book.set_quick_slot(1, "spell:firebolt")
	book.set_quick_slot(2, "res://data/consumables/apple.tres")
	check("favorites go on number keys", book.quick_slot_of("spell:firebolt") == 1 and book.quick_slot_of("res://data/consumables/apple.tres") == 2)
	book.set_quick_slot(3, "spell:firebolt")
	check("a favorite sits on one key at a time", book.quick_slot_of("spell:firebolt") == 3 and not book.quick_slots.has("1"))
	book.set_quick_slot(3, "spell:firebolt")
	check("the same key again takes it off", book.quick_slot_of("spell:firebolt") == 0)
	book.set_quick_slot(4, "spell:firebolt")
	var copy := Spellbook.new()
	copy.from_dict(book.to_dict())
	check("quick slots are saved with the game", copy.quick_slot_of("spell:firebolt") == 4 and copy.quick_slot_of("res://data/consumables/apple.tres") == 2)
	book.toggle_favorite("spell:firebolt")
	check("no longer a favorite: off its key too", book.quick_slot_of("spell:firebolt") == 0)
	book.free()
	copy.free()


func t_markers() -> void:
	print("-- map markers")
	WorldState.clear()
	var i := MapMarkers.add(Vector2(100, 200), "Marker 1")
	MapMarkers.rename(i, "  Bandit cave  ")
	check("a marker is placed and named", MapMarkers.all().size() == 1 and MapMarkers.all()[0]["name"] == "Bandit cave" and MapMarkers.all()[0]["pos"] == Vector2(100, 200))
	MapMarkers.rename(i, "   ")
	check("an empty name keeps the old one", MapMarkers.all()[0]["name"] == "Bandit cave")
	for n in MapMarkers.MAX + 3:
		MapMarkers.add(Vector2(n, n), "m%d" % n)
	check("there is a limit; the oldest go first", MapMarkers.all().size() == MapMarkers.MAX and MapMarkers.all()[0]["name"] != "Bandit cave")
	var saved := WorldState.to_dict()
	WorldState.clear()
	WorldState.from_dict(saved)
	check("markers are saved with the world", MapMarkers.all().size() == MapMarkers.MAX)
	MapMarkers.remove(0)
	check("a marker can be removed", MapMarkers.all().size() == MapMarkers.MAX - 1)
	WorldState.clear()


func t_tracking() -> void:
	print("-- the tracked quest")
	WorldState.clear()
	check("nothing is tracked at first", QuestManager.tracked_id() == "")
	QuestManager.toggle_tracked("G-123")
	check("a quest can be tracked", QuestManager.tracked_id() == "G-123")
	QuestManager.toggle_tracked("G-123")
	check("tracking it again stops it", QuestManager.tracked_id() == "")
	QuestManager.toggle_tracked("nothing-active")
	check("tracking a quest with no target keeps every marker on the compass", QuestManager.compass_targets().size() == QuestManager.active_targets().size())
	WorldState.clear()


func t_presets() -> void:
	print("-- graphics presets")
	var before := {}
	for k in ["graphics_preset"] + GameSettings.PRESET_KEYS:
		before[k] = GameSettings.get_value(k)
	GameSettings.set_value("graphics_preset", 1)
	check("Low sets its options", GameSettings.get_value("grass") == 0 and GameSettings.get_value("view_distance") == 6 and GameSettings.get_value("shadows") == 0)
	GameSettings.set_value("view_distance", 12)
	check("changing one by hand makes it Custom", GameSettings.get_value("graphics_preset") == 0 and GameSettings.get_value("view_distance") == 12)
	GameSettings.set_value("graphics_preset", 4)
	check("Ultra sets its options", GameSettings.get_value("grass") == 3 and GameSettings.get_value("view_distance") == 14)
	for k in before:  # put the player's own settings back
		GameSettings.set_value(k, before[k])
	check("the player's settings are back", GameSettings.get_value("graphics_preset") == before["graphics_preset"])


func t_value_per_weight() -> void:
	print("-- value per weight")
	var gem := ItemData.new()
	gem.value = 300
	gem.weight = 0.5
	var anvil := ItemData.new()
	anvil.value = 30
	anvil.weight = 30.0
	var note := ItemData.new()
	note.value = 5
	note.weight = 0.0
	check("gold per pound", is_equal_approx(InventoryUI._value_per_weight(gem), 600.0) and is_equal_approx(InventoryUI._value_per_weight(anvil), 1.0))
	check("weightless things come first and show a dash", is_inf(InventoryUI._value_per_weight(note)) and InventoryUI._value_per_weight_text(note) == "-")


func t_loading_screen() -> void:
	print("-- the loading screen")
	LoadingScreen.open(self)
	await frames(1)
	var s := root.get_node_or_null(LoadingScreen.NAME)
	check("it opens on the root (it survives a scene change)", s != null and s.get_parent() == root)
	var texts := s.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check("it shows a lore book's opening", texts.size() >= 3 and String(texts[2]).length() > 20 and String(texts[2]).length() <= LoadingScreen.TIP_LENGTH + 3, str(texts))
	LoadingScreen.open(self)
	await frames(1)
	check("opening it twice makes one screen", root.get_children().filter(func(n: Node) -> bool: return n is LoadingScreen).size() == 1)
	LoadingScreen.close(self)
	await frames(1)
	check("it closes", root.get_node_or_null(LoadingScreen.NAME) == null)


func t_in_game() -> void:
	print("-- in the game")
	var autosave_path := "user://saves/autosave/save.json"
	var before := FileAccess.get_modified_time(autosave_path) if FileAccess.file_exists(autosave_path) else 0
	SaveSession.begin_new_game(0, true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	check("the world closed the loading screen when it was ready", root.get_node_or_null(LoadingScreen.NAME) == null)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	check("the real game follows Settings > Video", wm.follow_video_settings and wm.settings.view_distance_chunks == int(GameSettings.get_value("view_distance")))
	var player := get_first_node_in_group("player")
	var sm := SaveManager.of(self)
	sm.autosave()
	var after := FileAccess.get_modified_time(autosave_path) if FileAccess.file_exists(autosave_path) else 0
	check("tests never overwrite the player's autosave", after == before)
	# Quick slot: an apple on key 5, used without opening the list
	var inv := player.get_node("Inventory") as Inventory
	var book := player.get_node("Spellbook") as Spellbook
	var apple: ItemData = load("res://data/consumables/apple.tres")
	inv.add_item(apple, 2)
	var key := SaveUtil.item_to_path(apple)
	if not book.is_favorite(key):
		book.toggle_favorite(key)
	book.set_quick_slot(5, key)
	var had := inv.get_count(apple)
	var fav := player.get_node("FavoritesMenu") as FavoritesMenu
	check("key 5 uses the apple on it", fav.use_quick_slot(5) and inv.get_count(apple) == had - 1, "%d -> %d" % [had, inv.get_count(apple)])
	check("an empty key does nothing", not fav.use_quick_slot(8))
	# Wait: Dawn sets the hours until 06:00
	var clock := get_first_node_in_group("world_clock") as WorldClock
	var wait := player.get_node("WaitMenu") as WaitMenu
	clock.set_time(22.5, clock.day)
	wait._until(6.0)
	check("Dawn waits until 06:00", int(wait._slider.value) == 8, str(wait._slider.value))
	clock.set_time(6.0, clock.day)
	wait._until(6.0)
	check("at 06:00, Dawn is a full day away", int(wait._slider.value) == 24, str(wait._slider.value))
