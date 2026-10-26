class_name DebugConsole
extends CanvasLayer
## The debug console: ` (the key left of 1) opens a command line while testing. Debug builds only
## (playing from the editor); an exported game never has it. Type "help" for the commands.
## Up / Down walk back through what you typed.

const ACTION := "debug_console"
const HELP := """help                      this list
tp <town>  |  tp <x> <z>  go to a town by name, or a spot on the map (meters)
give <item> [count]       an item by its id or file name (iron_sword, health_potion...)
gold <amount>             add gold (negative takes it)
skill <skill> [levels]    raise a skill (one_handed, destruction, sneak...)
level [levels]            raise every skill (default 1 level)
spawn <enemy> [count] [level]   a creature in front of you (wolf, bandit, vampire...)
heal                      full health, magicka and stamina
god                       nothing can hurt you (again: off)
time <hour> [day]         set the clock (13.5 = half past one)
weather <kind>            clear, cloudy, overcast, rain, storm, snow, blizzard, fog, sandstorm
kill                      kills every hostile creature within 30 m
quest <id> [done]         show a book quest's state, or finish it (S-KR01, H-VA02...)
quest.list / quest.why    active quests (why: and what blocks each one)
quest.start <id>          start a book quest, or quest.start <guild> <kind> (fighters kill)
quest.setstage <id> <n>   jump a book quest to step n
quest.complete / quest.fail / quest.reset <id>   finish, fail or forget a quest (S-KR01, q3...)
quest.check               look for quests that can never be finished
quest.overlay             show or hide the quest overlay
clear                     empty this window"""

var _root: Control
var _log: RichTextLabel
var _input: LineEdit
var _open := false
var _history: PackedStringArray = []
var _history_at := 0
var _overlay: Label
var _overlay_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_QUOTELEFT
		InputMap.action_add_event(ACTION, ev)
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed(ACTION) and not event.is_echo():
		_set_open(not _open)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	if open and get_tree().paused:
		return  # not over another menu
	_open = open
	_root.visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_input.clear()
		_input.grab_focus.call_deferred()
		if _log.get_parsed_text() == "":
			_print("Debug console. Type [b]help[/b] for the commands. [b]`[/b] closes it.")


func _build() -> void:
	_root = PanelContainer.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_root.offset_bottom = 300
	var v := VBoxContainer.new()
	_root.add_child(v)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "command (help)"
	_input.text_submitted.connect(_submit)
	_input.gui_input.connect(_input_keys)
	v.add_child(_input)


func _input_keys(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_QUOTELEFT:
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif k == KEY_ESCAPE:
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif (k == KEY_UP or k == KEY_DOWN) and not _history.is_empty():
		_history_at = clampi(_history_at + (-1 if k == KEY_UP else 1), 0, _history.size())
		_input.text = _history[_history_at] if _history_at < _history.size() else ""
		_input.caret_column = _input.text.length()
		get_viewport().set_input_as_handled()


func _submit(text: String) -> void:
	_input.clear()
	text = text.strip_edges()
	if text == "":
		return
	_history.append(text)
	_history_at = _history.size()
	_print("[color=#ffd95a]> %s[/color]" % text)
	_print(run(text))


# The quest overlay: active quests, their step, who takes them in and what blocks them (QuestDebug)
func _toggle_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		return
	_overlay = Label.new()
	_overlay.position = Vector2(12, 320)
	_overlay.add_theme_font_size_override("font_size", 13)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 4)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay_timer = 0.0


func _process(delta: float) -> void:
	if _overlay == null:
		return
	_overlay_timer -= delta
	if _overlay_timer > 0.0:
		return
	_overlay_timer = 0.5
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world == null or world.quests == null:
		return
	var lines := QuestDebug.report(world, true)
	_overlay.text = "QUESTS (quest.overlay hides this)\n" + ("\n".join(lines) if not lines.is_empty() else "none active")


func _print(text: String) -> void:
	if text != "":
		_log.append_text(text + "\n")


## Runs one command and returns what to print (also used by the tests)
func run(text: String) -> String:
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	var p := get_parent() as Node3D
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if cmd == "quest.overlay":
		_toggle_overlay()
		return "Quest overlay %s." % ("on" if _overlay != null else "off")
	if cmd.begins_with("quest."):
		return QuestDebug.run(cmd.trim_prefix("quest."), args, world)
	match cmd:
		"help":
			return HELP
		"clear":
			_log.clear()
			return ""
		"tp":
			return _tp(args, p, world)
		"give":
			if args.is_empty():
				return "give <item> [count]"
			var item := _find_item(args[0])
			if item == null:
				return "No item called '%s'." % args[0]
			var n := int(args[1]) if args.size() > 1 else 1
			(p.get_node("Inventory") as Inventory).add_item(item, maxi(n, 1))
			return "Gave %d %s." % [maxi(n, 1), item.display_name]
		"gold":
			var inv := p.get_node("Inventory") as Inventory
			var g := int(args[0]) if not args.is_empty() else 1000
			if g >= 0:
				Currency.add_gold(inv, g)
			else:
				Currency.spend_gold(inv, mini(-g, Currency.get_gold(inv)))
			return "Gold: %d" % Currency.get_gold(inv)
		"skill", "level":
			var skills := p.get_node("Skills") as Skills
			var ids: Array = []
			var times := 1
			if cmd == "skill":
				if args.is_empty() or SkillDatabase.get_skill(StringName(args[0])) == null:
					return "skill <skill> [levels]: a skill id like one_handed, destruction, sneak."
				ids = [StringName(args[0])]
				times = int(args[1]) if args.size() > 1 else 1
			else:
				for s in SkillDatabase.get_all():
					ids.append(s.id)
				times = int(args[0]) if not args.is_empty() else 1
			for id in ids:
				for i in clampi(times, 1, 100):
					skills.debug_level_up(id)
			return "Level %d." % skills.get_player_level()
		"spawn":
			return _spawn(args, p, world)
		"heal":
			var st := p.get_node("Stats") as Stats
			st.modify_vital("health", st.get_stat("max_health"))
			st.modify_vital("magicka", st.get_stat("max_magicka"))
			st.modify_vital("stamina", st.get_stat("max_stamina"))
			return "Healed."
		"god":
			var st := p.get_node("Stats") as Stats
			st.invulnerable = not st.invulnerable
			return "God mode %s." % ("on" if st.invulnerable else "off")
		"time":
			if world == null or world.clock == null or args.is_empty():
				return "time <hour> [day]"
			world.clock.set_time(clampf(float(args[0]), 0.0, 23.99), int(args[1]) if args.size() > 1 else -1)
			world.clock.apply_now()
			return "Day %d, %s." % [world.clock.day, world.clock.get_time_text()]
		"weather":
			var w := Weather.get_instance(get_tree())
			if w == null or args.is_empty():
				return "weather <kind>"
			var k := Weather.Kind.keys().find(args[0].to_upper())
			if k < 0:
				return "Kinds: " + ", ".join(Weather.Kind.keys()).to_lower()
			w.set_weather(k as Weather.Kind)
			return "Weather: %s." % w.get_name_text()
		"kill":
			var n := 0
			for e in ActorRegistry.near(p.global_position, 30.0):
				if e.disposition == Enemy.Disposition.HOSTILE and not e.is_dead():
					e.stats.modify_vital("health", -999999.0)
					n += 1
			return "Killed %d." % n
		"quest":
			if args.is_empty():
				return "quest <id> [done]"
			var id := args[0].to_upper()
			if QuestBook.get_def(id).is_empty():
				return "No quest %s." % id
			if args.size() > 1 and args[1] == "done":
				var book := QuestBook.of(get_tree())
				if QuestBook.status(id) == "":
					book.start(id)
				book.finish(id)
			return "%s (%s): %s" % [id, QuestBook.get_def(id)["name"], QuestBook.status(id) if QuestBook.status(id) != "" else "not started"]
	return "Unknown command '%s'. Type help." % cmd


func _tp(args: Array, p: Node3D, world: WorldManager) -> String:
	if world == null or args.is_empty():
		return "tp <town>  or  tp <x> <z>"
	var spot := Vector2.INF
	if args.size() >= 2 and String(args[0]).is_valid_float() and String(args[1]).is_valid_float():
		spot = Vector2(float(args[0]), float(args[1]))
	else:
		var want := " ".join(args).to_lower()
		for t in world.towns:
			if t.town != null and t.town.display_name.to_lower().begins_with(want):
				spot = Vector2(t.position.x, t.position.z)
				break
		if spot == Vector2.INF:
			return "No town called '%s'." % " ".join(args)
	if world.dungeons != null and world.dungeons.is_inside():
		return "Leave the building or dungeon first."
	var pos := Vector3(spot.x, 0.0, spot.y)
	world.ensure_area_loaded(pos, 1)
	pos.y = world.get_height_at(spot.x, spot.y) + 1.5
	p.global_position = pos
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	return "Teleported to %d, %d." % [roundi(spot.x), roundi(spot.y)]


func _spawn(args: Array, p: Node3D, world: WorldManager) -> String:
	if args.is_empty() or world == null:
		return "spawn <enemy> [count] [level]"
	var path := "res://data/enemies/%s.tres" % String(args[0]).to_lower()
	if not ResourceLoader.exists(path):
		var names := PackedStringArray()
		for f in DirAccess.get_files_at("res://data/enemies"):
			if f.ends_with(".tres"):
				names.append(f.trim_suffix(".tres"))
		return "No enemy '%s'. Some are: %s" % [args[0], ", ".join(names.slice(0, 20))]
	var data := load(path) as EnemyData
	var count := clampi(int(args[1]) if args.size() > 1 else 1, 1, 20)
	var level := int(args[2]) if args.size() > 2 else (p.get_node("Skills") as Skills).get_player_level()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ahead := -p.global_basis.z
	for i in count:
		var at := p.global_position + ahead * (4.0 + i * 1.5) + p.global_basis.x * rng.randf_range(-2.0, 2.0)
		at.y = world.get_height_at(at.x, at.z) + 0.6 if not world.dungeons.is_inside() else p.global_position.y + 0.5
		Population.spawn_enemy(data, level, world, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
	return "Spawned %d %s (level %d)." % [count, data.display_name, level]


# An item by id or file name, e.g. "iron_sword" or "Iron Sword"
static func _find_item(want: String) -> ItemData:
	var key := want.to_lower().replace(" ", "_")
	for dir: String in ItemCatalog.ITEM_DIRS:
		var path := dir + key + ".tres"
		if ResourceLoader.exists(path):
			return load(path) as ItemData
	for item in ItemCatalog.all_items():
		if String(item.id) == key or item.display_name.to_lower() == want.to_lower():
			return item
	return null
