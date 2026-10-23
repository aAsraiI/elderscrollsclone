extends SceneTree
## Headless tests for the menu / HUD update (main menu, settings, Tab menu, inventory,
## separate vitals bars, items in your hands, items bumping into each other). Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage8.gd

const R := "res://data/"

var passes := 0
var fails := 0
var _saved_settings := {}


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


func press(key: Key, shift := false) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.physical_keycode = key
	down.shift_pressed = shift
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _run() -> void:
	GameSettings.get_value("fov")  # load the player's own settings so they can be put back
	_saved_settings = GameSettings._values.duplicate()
	await frames(2)
	t_theme()
	t_models()
	await t_main_menu()
	await t_game()
	GameSettings._values = _saved_settings
	GameSettings.save()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_theme() -> void:
	print("-- theme")
	var theme := ThemeDB.get_project_theme()
	check("the project uses the slim theme", theme != null and theme.default_font_size == UITheme.FONT_SIZE)
	check("the theme has thin buttons", theme != null and theme.has_stylebox("normal", "Button"))


func t_models() -> void:
	print("-- item models")
	var sword: ItemData = load(R + "weapons/iron_sword.tres")
	var shield: ItemData = load(R + "weapons/iron_shield.tres")
	var potion: ItemData = load(R + "consumables/health_potion.tres")
	for it: ItemData in [sword, shield, potion, load(R + "treasure/ruby.tres"), load(R + "weapons/iron_chestplate.tres")]:
		var m := ItemModels.build_world(it)
		check("%s has a placeholder model" % it.display_name, m.find_children("*", "MeshInstance3D", true, false).size() > 0)
		m.free()
	var b := ItemModels.build_view(sword)
	var size := ItemModels.get_bounds(b).size
	check("a sword's model is long along +Y", size.y > 0.6 and size.x < 0.4, str(size))
	b.free()


func t_main_menu() -> void:
	print("-- main menu")
	check("the game starts in the main menu", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/game/main_menu.tscn")
	change_scene_to_file("res://scenes/game/main_menu.tscn")
	await frames(10)
	var menu := current_scene as MainMenu
	check("main menu loads", menu != null)
	if menu == null:
		return
	check("it has its own SaveManager that switches to the game", menu._saves != null and menu._saves.game_scene == SaveManager.GAME_SCENE)
	check("Continue only shows when there is a save", menu._continue.visible == (menu._saves.latest_slot() != ""))
	menu._on_settings()
	check("Settings opens and hides the buttons", menu._settings.is_open() and not menu._buttons.visible)
	await press(KEY_ESCAPE)
	check("Esc closes Settings, back to the buttons", not menu._settings.is_open() and menu._buttons.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	if menu._saves.latest_slot() != "":
		menu._on_load()
		check("Load Game opens the slots without Save / New Game", menu._saves.menu._is_open and not menu._saves.menu._save_button.visible and not menu._saves.menu._new_row.visible)
		menu._saves.menu._set_open(false)
		await frames(2)
		check("closing the slots shows the buttons again", menu._buttons.visible and not paused)
	menu._on_new_game()
	var wiz: NewGameWizard = null
	for c in menu.get_children():
		if c is NewGameWizard:
			wiz = c
	check("New Game opens World and Character Creation", wiz != null)  # stage 11 (was a seed box)
	wiz.begin.emit("", {}, {})
	await frames(40)
	check("Start switches to the game scene", current_scene != null and current_scene.scene_file_path == SaveManager.GAME_SCENE, str(current_scene.scene_file_path if current_scene else ""))


func t_game() -> void:
	print("-- in the game")
	var player := get_first_node_in_group("player") as CharacterBody3D
	check("a player is there", player != null)
	if player == null:
		return
	var hub := player.get_node_or_null("MenuHub") as MenuHub
	var inv_ui := player.get_node("InventoryUI") as InventoryUI
	var stats_ui := player.get_node("StatsUI") as StatsUI
	var map := get_first_node_in_group("world_map") as WorldDebugMap
	check("player made the Tab menu", hub != null)

	# settings reach the player
	GameSettings.set_value("fov", 92.0, self)
	var cam := player.get_node("Head/Camera3D") as Camera3D
	check("field of view setting reaches the camera", is_equal_approx(cam.fov, 92.0), str(cam.fov))
	GameSettings.set_value("mouse_sensitivity", 0.004, self)
	check("mouse sensitivity setting reaches the player", is_equal_approx(player.mouse_sensitivity, 0.004))

	# Tab menu
	await press(KEY_TAB)
	check("Tab opens the inventory and pauses", inv_ui.is_open() and paused and hub._bar.visible)
	await press(KEY_2)
	check("2 switches to the map", map.is_open() and not inv_ui.is_open() and paused)
	await press(KEY_C)
	check("C on the map centers it (does not switch)", map.is_open())
	await press(KEY_3)
	check("3 switches to the character screen", stats_ui.is_open() and not map.is_open() and paused)
	await press(KEY_I)
	check("I switches to the inventory", inv_ui.is_open() and not stats_ui.is_open())
	hub._buttons[3].emit_signal("pressed")
	await frames(2)
	var journal := player.get_node("JournalUI") as JournalUI
	check("clicking Journal on the bar switches to it", journal.is_open() and not inv_ui.is_open())
	await press(KEY_TAB)
	check("Tab closes the menu and unpauses", hub.current_page() == -1 and not paused and not hub._bar.visible)
	await press(KEY_TAB)
	check("Tab opens the page used last", journal.is_open())
	await press(KEY_ESCAPE)
	await frames(3)
	var pm := player.get_node("PauseMenu") as PauseMenu
	check("Esc closes it without the pause screen", hub.current_page() == -1 and not pm.is_open() and not paused)

	# inventory: search, sort, preview, compare
	var inv := player.get_node("Inventory") as Inventory
	inv_ui.open()
	inv_ui._tabs.current_tab = 0
	inv_ui._search.text = "dagger"
	inv_ui._refresh()
	var names := []
	for row in inv_ui._tree.get_root().get_children():
		names.append((row.get_metadata(0) as ItemData).display_name)
	check("search shows only matching items", names.size() >= 1 and names.all(func(n: String) -> bool: return n.to_lower().contains("dagger")), str(names))
	inv_ui._search.text = ""
	inv_ui._on_column_clicked(3, MOUSE_BUTTON_LEFT)
	var values := []
	for row in inv_ui._tree.get_root().get_children():
		values.append((row.get_metadata(0) as ItemData).value)
	var sorted_desc := values.duplicate()
	sorted_desc.sort()
	sorted_desc.reverse()
	check("clicking Value sorts most valuable first", values == sorted_desc, str(values))
	inv_ui._on_column_clicked(3, MOUSE_BUTTON_LEFT)
	inv_ui._on_column_clicked(3, MOUSE_BUTTON_LEFT)
	check("third click goes back to pick-up order", inv_ui._sort_column == -1)
	await frames(2)
	check("the selected item is shown as a 3D model", inv_ui._preview_holder.get_child_count() > 0)
	var hammer: ItemData = load(R + "weapons/iron_warhammer.tres")
	inv_ui._refresh()
	for row in inv_ui._tree.get_root().get_children():
		if row.get_metadata(0) == hammer:
			row.select(0)
	inv_ui._update_details()
	check("unworn gear is compared with what you hold", inv_ui._details.text.contains("damage") and inv_ui._details.text.contains("vs "), inv_ui._details.text.left(200))
	var daggers := inv.get_count(load(R + "weapons/iron_dagger.tres"))
	for row in inv_ui._tree.get_root().get_children():
		if (row.get_metadata(0) as ItemData).resource_path.ends_with("weapons/iron_dagger.tres"):
			row.select(0)
	inv_ui._drop_selected(true)
	check("Shift+Q drops the whole stack", daggers >= 2 and inv.get_count(load(R + "weapons/iron_dagger.tres")) == 0, str(daggers))
	inv_ui.close()

	# HUD bars
	var hud := player.get_node("VitalsHUD") as VitalsHUD
	var hg: Control = hud._groups["health"]
	var mg: Control = hud._groups["magicka"]
	var sg: Control = hud._groups["stamina"]
	await frames(2)
	check("three separate bars: magicka left, health middle, stamina right", mg.get_global_rect().position.x < hg.get_global_rect().position.x and hg.get_global_rect().end.x < sg.get_global_rect().position.x)
	var st := player.get_node("Stats") as Stats
	st.modify_vital("health", -20.0)
	await frames(3)
	var hb: VitalsHUD.VitalBar = hud._bars["health"]
	check("losing health shows a trail of what was lost", hb.trail > hb.value and hg.modulate.a > 0.5)

	# items bump into each other
	var floor_y := 900.0
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	shape.shape = box
	floor_body.add_child(shape)
	current_scene.add_child(floor_body)
	floor_body.global_position = Vector3(player.global_position.x, floor_y, player.global_position.z)
	var p := floor_body.global_position + Vector3.UP * 1.0
	var bread: ItemData = load(R + "consumables/bread.tres")
	var a := WorldItem.spawn(bread, 1, current_scene, p)
	var b := WorldItem.spawn(bread, 1, current_scene, p + Vector3.UP * 0.6)
	check("items are on the Items physics layer and collide with it", (a.collision_layer & WorldItem.ITEM_LAYER) != 0 and (a.collision_mask & WorldItem.ITEM_LAYER) != 0)
	for i in 120:
		await physics_frame
	check("an item dropped on another lands on top of it", b.global_position.y > a.global_position.y + 0.05, "%f %f" % [a.global_position.y, b.global_position.y])
	a.queue_free()
	b.queue_free()
	floor_body.queue_free()

	# own first-person model with an offset
	var ps := PackedScene.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "CustomBlade"
	mesh.mesh = BoxMesh.new()
	ps.pack(mesh)
	mesh.free()
	var custom := (load(R + "weapons/iron_sword.tres") as ItemData).duplicate() as ItemData
	custom.display_name = "Test Blade"
	custom.view_scene = ps
	custom.view_offset = Vector3(0.0, 0.1, 0.0)
	custom.view_rotation = Vector3(0.0, 90.0, 0.0)
	inv.add_item(custom)
	var eq := player.get_node("Equipment") as Equipment
	eq.equip(custom)
	await frames(3)
	var vm := player.get_node("Head/Camera3D/ViewModel") as ViewModel
	var found := vm.find_child("CustomBlade", true, false) as Node3D
	check("an item's View Scene is held in first person", found != null)
	check("its offset and rotation are used", found != null and found.position.is_equal_approx(Vector3(0.0, 0.1, 0.0)) and is_equal_approx(found.rotation_degrees.y, 90.0))

	# pause menu: settings and main menu
	pm.open()
	pm._on_settings()
	check("pause menu opens Settings", pm._settings.is_open() and not pm.is_open() and paused)
	pm._settings.close()
	await frames(1)
	check("closing Settings brings the pause menu back", pm.is_open() and paused)
	pm._on_main_menu()
	check("Main Menu asks first", pm._menu_button.text.begins_with("Leave?") and current_scene.scene_file_path == SaveManager.GAME_SCENE)
	pm._on_quit()
	check("Quit after Main Menu only asks, never quits at once", pm._quit.text.begins_with("Quit?") and not pm._menu_button.text.begins_with("Leave?"))
	pm._on_main_menu()
	pm._on_main_menu()
	await frames(10)
	check("second press goes to the main menu", current_scene is MainMenu and not paused)
