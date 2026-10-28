extends SceneTree
## Headless tests for stage 1 (clock, gold, food and potions, pause screen). Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage1.gd

const R := "res://data/"
const C := "res://data/consumables/"

var passes := 0
var fails := 0
var world: Node3D


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


func reset_world() -> void:
	paused = false
	if world != null:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)


func make_player(with_hud := false) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	var head := Node3D.new()
	head.name = "Head"
	p.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	p.add_child(stats)
	var inv := Inventory.new()
	inv.name = "Inventory"
	inv.stats = stats
	p.add_child(inv)
	var eq := Equipment.new()
	eq.name = "Equipment"
	eq.inventory = inv
	eq.stats = stats
	p.add_child(eq)
	var fx := StatusEffects.new()
	fx.name = "StatusEffects"
	fx.create_hud = with_hud
	p.add_child(fx)
	p.add_to_group("player")
	world.add_child(p)
	return p


func make_item(item_name: String, heal: float, dur: float, group: String, stam := 0.0) -> ItemData:
	var it := ItemData.new()
	it.display_name = item_name
	it.item_type = ItemData.ItemType.CONSUMABLE
	it.heal_amount = heal
	it.effect_duration = dur
	it.effect_group = group
	it.stamina_regen_bonus = stam
	it.stackable = true
	it.max_stack = 99
	return it


func first_in_group(group: String) -> Node:
	var list := get_nodes_in_group(group)
	return list[0] if not list.is_empty() else null


# A real key press, so both _input handlers and is_action_just_pressed see it
func press_esc() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _run() -> void:
	await frames(2)
	t_items()
	await t_regen()
	await t_effects()
	await t_quick_heal()
	await t_clock()
	await t_save()
	await t_pause()
	await t_inventory_ui()
	await t_hud()
	await t_world_manager()
	await t_player_scene()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- tests

func t_items() -> void:
	print("-- item files")
	var gold: ItemData = load(C + "gold.tres")
	var names := ["apple", "bread", "roast_meat", "hearty_stew", "venison_feast", "minor_health_potion", "health_potion", "greater_health_potion"]
	var all := {}
	var ok := gold != null
	for n in names:
		all[n] = load(C + n + ".tres")
		ok = ok and all[n] != null
	check("gold and all 8 food / potion files load", ok)
	if not ok:
		return
	check("gold is stackable, weightless and not usable", gold.stackable and gold.weight == 0.0 and gold.max_stack >= 1000000 and not gold.is_consumable())
	var slow := true
	for n in ["apple", "bread", "roast_meat", "hearty_stew", "venison_feast"]:
		var f: ItemData = all[n]
		slow = slow and f.is_consumable() and f.effect_group == "food" and f.effect_duration >= 30.0 and f.heal_amount / f.effect_duration < 1.6
	check("food is slow: 30 s or more, under 1.6 HP per second", slow)
	var fast := true
	for n in ["minor_health_potion", "health_potion", "greater_health_potion"]:
		var p: ItemData = all[n]
		fast = fast and p.is_consumable() and p.effect_group == "potion" and p.effect_duration <= 4.0 and p.heal_amount / p.effect_duration > 10.0
	check("potions are fast: 4 s or less, over 10 HP per second", fast)
	var s := [all["apple"].stamina_regen_bonus, all["bread"].stamina_regen_bonus, all["roast_meat"].stamina_regen_bonus, all["hearty_stew"].stamina_regen_bonus, all["venison_feast"].stamina_regen_bonus]
	check("better food gives a bigger stamina regen bonus", s[0] == 0.0 and s[2] > s[1] and s[3] > s[2] and s[4] > s[3], str(s))
	var mods: Dictionary = all["hearty_stew"].get_effect_mods()
	check("stew effect mods are 0.75 HP/s and +0.4 stamina regen", absf(float(mods["health_regen"]) - 0.75) < 0.001 and absf(float(mods["stamina_regen_mult"]) - 0.4) < 0.001, str(mods))
	var desc: String = all["hearty_stew"].get_combat_description()
	check("description mentions the effect", "Restores 90" in desc and "+40%" in desc, desc)
	check("a sword is not consumable", not (load(R + "weapons/iron_sword.tres") as ItemData).is_consumable())
	check("weapon description unchanged for a sword", "Damage" in (load(R + "weapons/iron_sword.tres") as ItemData).get_combat_description())


func t_regen() -> void:
	print("-- Stats regen")
	await reset_world()
	var p := make_player()
	var stats := p.get_node("Stats") as Stats
	await frames(3)
	check("health_regen and stamina_regen_mult exist in the base stats", stats.get_stat("health_regen") == 0.0 and stats.get_stat("stamina_regen_mult") == 1.0)
	stats.modify_vital("health", -50.0)
	stats.add_modifiers("t", {"health_regen": 10.0})
	await frames(60)
	check("10 HP/s heals about 10 in one second", absf(stats.health - 60.0) < 1.6, str(stats.health))
	stats.remove_modifiers("t")
	var h := stats.health
	await frames(30)
	check("no regen once the modifier is gone", absf(stats.health - h) < 0.01)
	stats.add_modifiers("t", {"health_regen": 1000.0})
	await frames(30)
	check("health never goes past the maximum", stats.health <= stats.get_stat("max_health") + 0.001, str(stats.health))
	stats.remove_modifiers("t")
	stats.modify_vital("stamina", -stats.stamina)
	await frames(95)
	var s0 := stats.stamina
	await frames(60)
	var base_gain := stats.stamina - s0
	check("normal stamina regen is about 10 per second", base_gain > 8.0 and base_gain < 11.5, str(base_gain))
	stats.modify_vital("stamina", -stats.stamina)
	stats.add_modifiers("t2", {"stamina_regen_mult": 1.0})
	await frames(95)
	s0 = stats.stamina
	await frames(60)
	var boosted := stats.stamina - s0
	check("+100% stamina regen doubles it", boosted > 17.0 and boosted < 23.0, str(boosted))


func t_effects() -> void:
	print("-- eating and drinking")
	await reset_world()
	var p := make_player()
	var stats := p.get_node("Stats") as Stats
	var inv := p.get_node("Inventory") as Inventory
	var fx := p.get_node("StatusEffects") as StatusEffects
	await frames(3)
	var fails_seen: Array = []
	fx.use_failed.connect(func(r): fails_seen.append(r))
	var f1 := make_item("Meal A", 20.0, 10.0, "food", 0.3)
	var f2 := make_item("Meal B", 30.0, 10.0, "food")
	inv.add_item(f1, 2)
	inv.add_item(f2, 1)
	check("eating works", fx.use_item(f1))
	check("it was taken from the inventory", inv.get_count(f1) == 1)
	check("one effect running", fx.get_active().size() == 1)
	check("health_regen = 20 / 10 = 2", absf(stats.get_stat("health_regen") - 2.0) < 0.001)
	check("stamina regen multiplier = 1.3", absf(stats.get_stat("stamina_regen_mult") - 1.3) < 0.001)
	check("a second use right away is refused (cooldown)", not fx.use_item(f2) and fails_seen.back() == &"cooldown")
	check("the refused item stays in the inventory", inv.get_count(f2) == 1)
	await frames(60)
	check("after the cooldown a new meal works", fx.use_item(f2))
	check("a new meal REPLACES the old one", fx.get_active().size() == 1 and fx.get_active()[0]["item"] == f2)
	check("regen now 3, stamina bonus gone", absf(stats.get_stat("health_regen") - 3.0) < 0.001 and absf(stats.get_stat("stamina_regen_mult") - 1.0) < 0.001)
	fx.clear_effects()
	check("clearing removes the modifiers", stats.get_stat("health_regen") == 0.0)
	await frames(60)
	var quick := make_item("Test Tonic", 40.0, 2.0, "potion")
	inv.add_item(quick, 1)
	stats.health = 10.0
	fx.use_item(quick)
	await frames(150)
	check("40 HP over 2 s heals 40 in total", absf(stats.health - 50.0) < 2.0, str(stats.health))
	check("the effect ended by itself", fx.get_active().is_empty() and stats.get_stat("health_regen") == 0.0)
	await frames(60)
	var pot := make_item("Test Potion", 20.0, 3.0, "potion")
	inv.add_item(pot, 3)
	fx.use_item(pot)
	await frames(60)
	fx.use_item(pot)
	check("two potions run together", fx.get_active().size() == 2 and absf(stats.get_stat("health_regen") - 2.0 * 20.0 / 3.0) < 0.01)
	fx.clear_effects()
	fails_seen.clear()
	await frames(60)
	check("an item you don't carry fails with 'missing'", not fx.use_item(make_item("Ghost", 5.0, 5.0, "food")) and fails_seen.back() == &"missing")
	var sword: ItemData = load(R + "weapons/iron_sword.tres")
	inv.add_item(sword)
	check("a sword can't be eaten", not fx.use_item(sword) and fails_seen.back() == &"not_usable")
	var long := make_item("Long Meal", 10.0, 20.0, "food")
	inv.add_item(long)
	await frames(60)
	fx.use_item(long)
	var left := float(fx.get_active()[0]["remaining"])
	paused = true
	await frames(60)
	paused = false
	check("effects do not tick while the game is paused", absf(float(fx.get_active()[0]["remaining"]) - left) < 0.1)
	stats.modify_vital("health", -1000.0)
	check("dying clears every effect", stats.is_dead and fx.get_active().is_empty())
	inv.add_item(f1)
	check("the dead can't eat", not fx.use_item(f1) and fails_seen.back() == &"dead")


func t_quick_heal() -> void:
	print("-- H key: quick potion")
	await reset_world()
	var p := make_player()
	var stats := p.get_node("Stats") as Stats
	var inv := p.get_node("Inventory") as Inventory
	var fx := p.get_node("StatusEffects") as StatusEffects
	var minor: ItemData = load(C + "minor_health_potion.tres")
	var mid: ItemData = load(C + "health_potion.tres")
	var big: ItemData = load(C + "greater_health_potion.tres")
	inv.add_item(minor)
	inv.add_item(mid)
	inv.add_item(big)
	await frames(3)
	var fails_seen: Array = []
	fx.use_failed.connect(func(r): fails_seen.append(r))
	stats.health = 70.0
	check("missing 30: drinks the minor potion", fx.quick_heal() and inv.get_count(minor) == 0 and inv.get_count(mid) == 1)
	fx.clear_effects()
	await frames(60)
	stats.health = 40.0
	check("missing 60: drinks the 80 HP potion", fx.quick_heal() and inv.get_count(mid) == 0 and inv.get_count(big) == 1)
	fx.clear_effects()
	await frames(60)
	stats.health = 1.0
	check("missing 99: drinks the greater potion", fx.quick_heal() and inv.get_count(big) == 0)
	fx.clear_effects()
	await frames(60)
	check("no potions left: fails with 'no_potion'", not fx.quick_heal() and fails_seen.back() == &"no_potion")
	var bread: ItemData = load(C + "bread.tres")
	inv.add_item(bread)
	check("food is never picked by the quick key", not fx.quick_heal() and inv.get_count(bread) == 1)
	inv.add_item(mid)
	stats.health = 30.0
	await frames(3)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_H
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_H
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)
	check("pressing H drinks a potion", inv.get_count(mid) == 0)


func t_clock() -> void:
	print("-- world clock")
	await reset_world()
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	var env := Environment.new()
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var clock := WorldClock.new()
	clock.day_length_minutes = 1.0
	clock.start_hour = 8.0
	clock.debug_keys = false
	world.add_child(clock)
	await frames(1)
	var h0 := clock.hour
	check("starts at about 08:00 on day 1", absf(h0 - 8.0) < 0.05 and clock.day == 1, str(h0))
	await frames(60)
	check("one real second = 0.4 hours with 1-minute days", absf(clock.hour - (h0 + 0.4)) < 0.03, str(clock.hour))
	clock.set_time(8.5)
	check("time text 08:30", clock.get_time_text() == "08:30", clock.get_time_text())
	clock.set_time(22.0)
	check("22:00 is night", clock.is_night())
	clock.set_time(12.0)
	check("12:00 is day", not clock.is_night())
	clock.set_time(5.9)
	check("05:54 is still night", clock.is_night())
	clock.set_time(6.0)
	check("06:00 is day", not clock.is_night())
	check("hour_in_range across midnight", WorldClock.hour_in_range(23.0, 22.0, 6.0) and WorldClock.hour_in_range(3.0, 22.0, 6.0) and not WorldClock.hour_in_range(12.0, 22.0, 6.0) and WorldClock.hour_in_range(9.0, 8.0, 18.0))
	clock.set_time(8.0, 1)
	var hours: Array = []
	var days: Array = []
	var nights := [0]
	var dawns := [0]
	clock.hour_changed.connect(func(h): hours.append(h))
	clock.day_changed.connect(func(day): days.append(day))
	clock.night_started.connect(func(): nights[0] += 1)
	clock.day_started.connect(func(): dawns[0] += 1)
	clock.advance_hours(1.2)
	check("hour_changed fired once with 9", hours == [9], str(hours))
	clock.set_time(20.9)
	clock.advance_hours(0.2)
	check("night_started fired at 21:00", nights[0] == 1 and dawns[0] == 0)
	clock.set_time(5.9)
	clock.advance_hours(0.2)
	check("day_started fired at 06:00", dawns[0] == 1)
	clock.set_time(23.5, 3)
	days.clear()
	clock.advance_hours(1.0)
	check("midnight rolls the day over", clock.day == 4 and absf(clock.hour - 0.5) < 0.001 and days == [4], "%d %f %s" % [clock.day, clock.hour, str(days)])
	clock.set_time(13.0)
	var dir_noon := -sun.global_transform.basis.z
	check("midday: full light, sun high, sky bright", sun.light_energy > 0.95 and dir_noon.y < -0.6 and absf(env.ambient_light_energy - WorldClock.DAY_AMBIENT) < 0.05 and env.background_energy_multiplier > 0.95, "%f %s %f" % [sun.light_energy, str(dir_noon), env.ambient_light_energy])
	clock.set_time(0.0)
	check("midnight: sun off, sky and ambient dark", sun.light_energy < 0.01 and env.ambient_light_energy < 0.12 and env.background_energy_multiplier < 0.05, "%f %f" % [sun.light_energy, env.ambient_light_energy])
	check("midnight fog is dark", env.fog_light_color.v < 0.1)
	clock.set_time(7.0)
	var dir_morning := -sun.global_transform.basis.z
	check("07:00: sun low, its light is warm", dir_morning.y > dir_noon.y and sun.light_color.b < sun.light_color.r, str(sun.light_color))
	clock.set_time(9.0)
	var east := -sun.global_transform.basis.z
	clock.set_time(17.0)
	var west := -sun.global_transform.basis.z
	check("the sun crosses the sky (morning and evening light come from opposite sides)", east.x * west.x < 0.0, "%s %s" % [str(east), str(west)])
	clock.set_time(13.0)
	var a := clock.get_daylight()
	clock.set_time(0.0)
	check("daylight 1 at midday, 0 at midnight", a == 1.0 and clock.get_daylight() == 0.0)
	clock.set_time(15.25, 7)
	var d := clock.to_dict()
	clock.set_time(1.0, 1)
	clock.from_dict(JSON.parse_string(JSON.stringify(d)))
	check("to_dict / from_dict (through JSON) keeps the time and day", absf(clock.hour - 15.25) < 0.001 and clock.day == 7)
	var before := clock.hour
	paused = true
	await frames(60)
	paused = false
	check("time stands still while paused", absf(clock.hour - before) < 0.001)
	clock.control_environment = false
	clock.set_time(13.0)
	var e1 := env.ambient_light_energy
	clock.set_time(0.0)
	check("control_environment off leaves the sky alone", env.ambient_light_energy == e1)


func t_save() -> void:
	print("-- save and load of clock and effects")
	await reset_world()
	var p := make_player()
	var inv := p.get_node("Inventory") as Inventory
	var fx := p.get_node("StatusEffects") as StatusEffects
	var clock := WorldClock.new()
	clock.control_environment = false
	clock.debug_keys = false
	world.add_child(clock)
	var sm := SaveManager.new()
	sm.name = "SaveManager"
	world.add_child(sm)
	var stew: ItemData = load(C + "hearty_stew.tres")
	inv.add_item(stew)
	await frames(3)
	fx.use_item(stew)
	await frames(30)
	clock.set_time(17.5, 5)
	var data := sm.build_save_data()
	check("save data has the clock", data.has("clock") and int(data["clock"]["day"]) == 5)
	check("save data has the active effects", data["player"].has("effects") and data["player"]["effects"]["effects"].size() == 1)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data))
	fx.clear_effects()
	clock.set_time(1.0, 1)
	sm._restore_player(p, parsed["player"])
	clock.from_dict(parsed["clock"])
	check("the effect is back after loading", fx.get_active().size() == 1 and fx.get_active()[0]["item"] == stew)
	var remaining := float(fx.get_active()[0]["remaining"]) if not fx.get_active().is_empty() else 0.0
	check("with the time that was left (about 119.5 s)", remaining > 118.0 and remaining < 120.0, str(remaining))
	check("and its stat modifiers are applied again", absf((p.get_node("Stats") as Stats).get_stat("health_regen") - 0.75) < 0.001)
	check("the clock is restored", absf(clock.hour - 17.5) < 0.01 and clock.day == 5, "%f %d" % [clock.hour, clock.day])
	sm._restore_player(p, {"pos": [0, 1, 0]})
	check("an old save without effects loads cleanly and clears them", fx.get_active().is_empty())
	var bonus := make_item("Runtime item", 10.0, 5.0, "food")
	inv.add_item(bonus)
	await frames(60)
	fx.use_item(bonus)
	check("a runtime-made item is left out of the save (it has no file)", fx.to_dict()["effects"].is_empty())
	sm.queue_free()
	await frames(2)


func t_pause() -> void:
	print("-- pause menu")
	await reset_world()
	var p := make_player()
	var stats := p.get_node("Stats") as Stats
	var pm := PauseMenu.new()
	pm.name = "PauseMenu"
	p.add_child(pm)
	var sm := SaveManager.new()
	sm.name = "SaveManager"
	world.add_child(sm)
	await frames(3)
	var opened := [0]
	var closed := [0]
	var quits := [0]
	pm.opened.connect(func(): opened[0] += 1)
	pm.closed.connect(func(): closed[0] += 1)
	pm.quit_requested.connect(func(): quits[0] += 1)
	pm.open()
	check("open() pauses the game and shows the menu", pm.is_open() and paused and opened[0] == 1 and pm._root.visible)
	pm.close()
	check("close() resumes", not pm.is_open() and not paused and closed[0] == 1 and not pm._root.visible)
	await press_esc()
	check("pressing Esc in the game opens the pause screen", pm.is_open() and paused)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(2)
	var esc_up := InputEventAction.new()
	esc_up.action = "ui_cancel"
	esc_up.pressed = false
	Input.parse_input_event(esc_up)
	await frames(3)
	check("Esc again resumes", not pm.is_open() and not paused)
	# Another menu closed by this very Esc press: no pause screen
	paused = true
	await frames(2)
	Input.action_press("ui_cancel")
	paused = false
	await frames(3)
	Input.action_release("ui_cancel")
	await frames(2)
	check("an Esc that closed another menu does NOT open the pause screen", not pm.is_open() and not paused)
	paused = true
	await frames(2)
	await press_esc()
	check("Esc while another menu is open does nothing", not pm.is_open())
	paused = false
	await frames(3)
	pm.open()
	pm._on_save()
	check("Save Game hides the pause menu and opens the slot screen", not pm.is_open() and sm.menu != null and sm.menu._is_open and paused)
	sm.menu._set_open(false)
	await frames(1)
	check("closing the slot screen brings the pause menu back, still paused", pm.is_open() and paused)
	pm._on_load()
	check("Load Game opens the slot screen too", not pm.is_open() and sm.menu._is_open)
	sm.menu._set_open(false)
	await frames(1)
	pm.close()
	sm.menu._set_open(true)
	sm.menu._set_open(false)
	await frames(1)
	check("F10 slot screen on its own does not open the pause menu when closed", not pm.is_open() and not paused)
	pm.open()
	pm._on_quit()
	check("first Quit press only asks to confirm", quits[0] == 0 and pm._quit.text.begins_with("Quit?"))
	await frames(200)
	check("the confirmation expires after a few seconds", pm._quit.text == "Quit Game" and quits[0] == 0)
	pm.close()
	stats.modify_vital("health", -1000.0)
	await frames(3)
	await press_esc()
	check("no pause screen while dead", not pm.is_open())
	sm.queue_free()
	await frames(2)


func t_inventory_ui() -> void:
	print("-- inventory screen")
	await reset_world()
	var p := make_player()
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	var stew: ItemData = load(C + "hearty_stew.tres")
	var sword: ItemData = load(R + "weapons/iron_sword.tres")
	inv.add_item(stew, 2)
	inv.add_item(sword)
	Currency.add_gold(inv, 150)
	var ui := InventoryUI.new()
	ui.name = "InventoryUI"
	p.add_child(ui)
	await frames(3)
	ui._set_open(true)
	check("gold is spendable through Currency", Currency.get_gold(inv) == 150 and Currency.spend_gold(inv, 50) and Currency.get_gold(inv) == 100 and not Currency.spend_gold(inv, 101) and Currency.get_gold(inv) == 100)
	ui._update_footer()
	check("the footer shows gold", "Gold 100" in ui._stats_label.text, ui._stats_label.text)
	var select := func(item: ItemData) -> bool:
		for tab in ui._tabs.tab_count:
			ui._tabs.current_tab = tab
			ui._refresh()
			for row in ui._tree.get_root().get_children():
				if row.get_metadata(0) == item:
					row.select(0)
					ui._update_details()
					return true
		return false
	check("the stew is listed", select.call(stew))
	check("its button says Eat (E)", ui._equip_button.text == "Eat (E)" and not ui._equip_button.disabled, ui._equip_button.text)
	ui._activate_selected()
	var fx := p.get_node("StatusEffects") as StatusEffects
	check("Enter / E eats it: one gone, effect running", inv.get_count(stew) == 1 and fx.get_active().size() == 1)
	check("a one-handed sword offers the right hand", select.call(sword) and ui._equip_button.text.begins_with("Right hand (E)"), ui._equip_button.text)
	ui._activate_selected()
	check("sword equipped in the right hand", eq.get_main_hand() == sword)
	select.call(sword)
	ui._on_item_clicked(Vector2.ZERO, MOUSE_BUTTON_RIGHT)
	await frames(1)
	check("right click moves it to the left hand (one copy)", eq.get_off_hand() == sword and eq.get_main_hand() != sword)
	select.call(sword)
	ui._activate_selected()
	check("E puts it back in the right hand", eq.get_main_hand() == sword and eq.get_off_hand() != sword)
	var names := []
	for tab in ui._tabs.tab_count:
		names.append(ui._tabs.get_tab_title(tab))
	check("tab renamed to Food & Drink", "Food & Drink" in names, str(names))
	ui._set_open(false)
	paused = false


func t_hud() -> void:
	print("-- status HUD")
	await reset_world()
	var clock := WorldClock.new()
	clock.control_environment = false
	clock.debug_keys = false
	world.add_child(clock)
	var p := make_player(true)
	var fx := p.get_node("StatusEffects") as StatusEffects
	var inv := p.get_node("Inventory") as Inventory
	await frames(3)
	var hud := fx.get_node_or_null("StatusHUD") as StatusHUD
	check("StatusEffects made its HUD", hud != null)
	if hud == null:
		return
	clock.set_time(9.5, 2)
	await frames(2)
	check("HUD shows day and time", hud._time_label.text == "Day 2   09:30", hud._time_label.text)
	var stew: ItemData = load(C + "hearty_stew.tres")
	inv.add_item(stew)
	fx.use_item(stew)
	await frames(2)
	check("HUD lists the effect", "Hearty Stew" in hud._list_label.text and "+0.8 HP/s" in hud._list_label.text and "+40% stamina regen" in hud._list_label.text, hud._list_label.text)
	check("toast says Ate Hearty Stew", hud._toast.text == "Ate Hearty Stew" and hud._toast.modulate.a > 0.5, hud._toast.text)
	paused = true
	await frames(2)
	check("HUD hides while paused", not hud._root.visible)
	paused = false
	await frames(2)


func t_world_manager() -> void:
	print("-- WorldManager creates the clock")
	await reset_world()
	make_player()
	var wm := WorldManager.new()
	wm.name = "WorldManager"
	world.add_child(wm)
	await frames(10)
	check("WorldManager made a WorldClock", wm.clock != null and wm.clock.is_inside_tree() and first_in_group("world_clock") == wm.clock)
	var env: Environment = null
	for we in root.find_children("*", "WorldEnvironment", true, false):
		env = (we as WorldEnvironment).environment
	check("the auto sky exists", env != null)
	if env != null:
		wm.clock.set_time(13.0)
		var noon := env.ambient_light_energy
		wm.clock.set_time(1.0)
		check("the clock dims the world's sky at night", env.ambient_light_energy < noon * 0.3, "%f %f" % [noon, env.ambient_light_energy])
	wm.queue_free()
	await frames(3)


func t_player_scene() -> void:
	print("-- the real player scene")
	await reset_world()
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	check("player.tscn loads", scene != null)
	if scene == null:
		return
	var p := scene.instantiate()
	p.set("spawn_test_enemy", false)
	world.add_child(p)
	await frames(5)
	check("player made StatusEffects and PauseMenu", p.get_node_or_null("StatusEffects") is StatusEffects and p.get_node_or_null("PauseMenu") is PauseMenu)
	var inv := p.get_node("Inventory") as Inventory
	check("test loadout includes gold, food and potions", Currency.get_gold(inv) == 150 and inv.get_count(load(C + "health_potion.tres")) == 2 and inv.get_count(load(C + "bread.tres")) == 3)
	await press_esc()
	var pm := p.get_node("PauseMenu") as PauseMenu
	check("Esc opens pause in the real scene", pm.is_open() and paused)
	pm.close()
	await frames(2)
	# Inventory closed with Esc must not open pause too
	var ui := p.get_node_or_null("InventoryUI") as InventoryUI
	if ui != null:
		ui._set_open(true)
		await frames(2)
		await press_esc()
		await frames(2)
		check("Esc closes the inventory without opening the pause screen", not ui._is_open and not pm.is_open() and not paused, "inv %s pause %s paused %s" % [ui._is_open, pm.is_open(), paused])
	p.queue_free()
	await frames(2)
