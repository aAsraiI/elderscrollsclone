class_name Tutorial
extends CanvasLayer
## First-time hints: a short tip in the lower left the first time something comes up (your first
## fight, first body, first night, first spell...). Each shows once per character (WorldState
## "tut/<id>"). Turn them off in Settings > Interface > Tutorial hints.

const SHOW_SECONDS := 9.0

var _panel: PanelContainer
var _label: Label
var _queue: Array[String] = []
var _left := 0.0
var _check := 2.0
var _player: Node3D


func _ready() -> void:
	layer = 6
	_player = get_parent() as Node3D
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 20
	_panel.offset_top = -190
	_panel.offset_right = 440
	_panel.offset_bottom = -110
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_label)
	_panel.visible = false


func hint(id: String, text: String) -> void:
	if not bool(GameSettings.get_value("tutorial")) or WorldState.has_record("tut/" + id):
		return
	WorldState.set_record("tut/" + id, {})
	_queue.append(text)


func _process(delta: float) -> void:
	if get_tree().paused:
		_panel.visible = false
		return
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		_watch()
	if _left > 0.0:
		_left -= delta
		_panel.visible = true
		_panel.modulate.a = clampf(_left, 0.0, 1.0)
		return
	_panel.visible = false
	if not _queue.is_empty():
		_label.text = _queue.pop_front()
		_left = SHOW_SECONDS


func _watch() -> void:
	hint("welcome", "WASD to move, mouse to look, Space to jump, Shift to sprint, Ctrl to sneak. E uses things. Tab opens the menu (inventory, map, character, journal, magic, council). V switches to third person.")
	var stats := _player.get_node_or_null("Stats") as Stats
	if stats != null and stats.health < stats.get_stat("max_health") * 0.4:
		hint("low_health", "You are badly hurt. Press H to drink a health potion, or eat food from the inventory.")
	for n in ActorRegistry.near(_player.global_position, 20.0):
		var e := n as Enemy
		if e != null and e.disposition == Enemy.Disposition.HOSTILE and e.is_alerted() and e.global_position.distance_to(_player.global_position) < 20.0:
			hint("combat", "Left click attacks (hold for a heavy blow). With a shield, hold right click to block and raise it just before a hit to parry. A glowing enemy is about to strike.")
			break
	var book := _player.get_node_or_null("Spellbook") as Spellbook
	if book != null and book.spells.size() > 0:
		hint("magic", "You know spells. Press P for the Magic page, E on a spell puts it in your off hand, then right click casts it.")
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock != null and clock.is_night():
		hint("night", "Night has fallen. People go home and lock their doors. Press T to wait, or sleep in an inn's bed.")
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_in_building() and dm.get_interior_root() != null and not dm.get_interior_root().find_children("*", "CraftingStation", true, false).is_empty():
		hint("stations", "There are workstations here: forges, cooking pots, alchemy labs and more. Press E on one to craft.")
	if dm != null and dm.is_inside() and not dm.is_in_building():
		hint("dungeon", "Dungeons hide traps, levers and secret doors. Hold E on a body to drag it by the limb you aim at.")
	var inv := _player.get_node_or_null("Inventory") as Inventory
	if inv != null and stats != null and inv.get_total_weight() > stats.get_stat("carry_capacity"):
		hint("heavy", "You carry too much and move slowly. Drop or sell something (Q in the inventory drops one).")
	if GameRules.survival():
		var s := _player.get_node_or_null("Survival") as Survival
		if s != null and (s.hunger >= 50.0 or s.cold >= 50.0 or s.fatigue >= 50.0):
			hint("survival", "Survival: eat to stop hunger, sleep in a bed to rest, and stay indoors or dress warmly when it is cold.")
	var aff := _player.get_node_or_null("Afflictions") as Afflictions
	if aff != null:
		if not aff.diseases.is_empty():
			hint("disease", "You are sick. Pray at a temple shrine, drink a Cure Disease potion or cast Cure Disease.")
		if aff.vampire:
			hint("vampire", "You are a vampire. Food is useless: press F on sleeping people or fresh bodies to feed (Shift+F fills a bottle). Stay out of the sun when hungry, and never let the hunger grow ravenous in town.")
		if aff.werewolf:
			hint("werewolf", "You are a werewolf. Press B to change (once a day). The full moon changes you anyway. In beast form, F on a body devours it.")
	_watch_quests()


# Quests, the journal and talking: the first time each comes up
func _watch_quests() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if wm == null:
		return
	var active := QuestLog.all(wm).filter(func(q: Dictionary) -> bool: return q["status"] == "active")
	if not active.is_empty():
		hint("quests", "You have a quest. Press J for the journal: its Quests tab shows what to do next. Pick Track to see it on the compass (and on screen: Settings > Interface > Tracked quests on screen).")
	if active.any(func(q: Dictionary) -> bool: return q["source"] == "job" and String(q["next"]).begins_with("Report back")):
		hint("report_back", "A job is done. Go back to whoever gave it and ask about \"report back\". A ? over someone means they want to see you.")
	if DialogueState.journal().size() >= 5:
		hint("journal_notes", "The journal keeps one entry per topic. Write your own notes there too: \"+ New note\" in the Notes tab, or Shift+J from anywhere.")
	for e in ActorRegistry.near(_player.global_position, 6.0):
		if e.talk_name != "" and e.disposition != Enemy.Disposition.HOSTILE:
			hint("talking", "Press E to talk. Click topics on the right or highlighted words; new topics have a dot. Persuade, Gift and the service buttons (Train, Rent Room...) are along the bottom.")
			break
