class_name DialogueUI
extends CanvasLayer
## The conversation window, Morrowind style. Opens when you press E on someone who talks (NpcTalk
## calls open_with). Created by player.gd. The game pauses while it is open.
##
##   top     their name, job and town, and how much they like you
##   left    what has been said; highlighted words are topics: click one to ask about it
##   right   the topics you know that this person can talk about
##   bottom  Persuade (Admire / Intimidate / Joke / Bribe, with the chance of success), Journal, Goodbye
##
## Every topic named in an answer is learned. Answers worth remembering go into the journal (J).

signal opened
signal closed
signal answered(topic: String, result: Dictionary)

const GOLD := Color(1.0, 0.85, 0.35)
const LINK := "#e8c46a"
const TOPIC_COLOR := "#9fc7ff"
## Letters a second, for typewriter text
const TYPE_SPEED := 90.0

var speaker: DialogueEngine.Speaker

var _open := false
var _world: WorldManager
var _player: Node
var _root: Control
var _name_label: Label
var _sub_label: Label
var _disp_bar: ProgressBar
var _disp_label: Label
var _log: RichTextLabel
var _topics: VBoxContainer
var _persuade_row: HBoxContainer
var _persuade_buttons: Array[Button] = []
var _barter_button: Button
var _services: HFlowContainer
var _panel: PanelContainer
var _last_answer := ""
var _focus_topic := ""  # the topic the keyboard was on (kept after asking)
var _fov_before := 0.0
## Typewriter text (Settings): characters still to reveal
var _typing := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	add_to_group("dialogue_ui")
	_player = get_parent()
	_rng.randomize()
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


## Starts talking to this body. Returns false if they won't talk (hostile, fighting, running, dead).
func open_with(e: Enemy) -> bool:
	if _open or e == null or not is_instance_valid(e) or e.is_dead():
		return false
	if e.disposition == Enemy.Disposition.HOSTILE or e.state in [Enemy.State.CHASE, Enemy.State.ATTACK, Enemy.State.FLEE, Enemy.State.STAGGER]:
		return false
	_world = get_tree().get_first_node_in_group("world_manager") as WorldManager
	speaker = DialogueEngine.speaker_for(e, _world)
	if speaker.asleep:
		DialogueState.change_disposition(speaker.id, speaker.base_disposition, -3)  # nobody likes being woken
	for t in DialogueEngine.greeting_topics(speaker):
		DialogueState.learn(t)
	if _world != null and _world.quests != null:
		for t in _world.quests.extra_topics(speaker):  # a guild leader's membership, a delivery...
			DialogueState.learn(t)
	_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_persuade_row.visible = false
	_focus_topic = ""
	_log.clear()
	_last_answer = ""
	_apply_text_size()
	# never bigger than the window (a small window or a big text size)
	var vp := get_viewport().get_visible_rect().size
	if _panel != null:
		_panel.custom_minimum_size = Vector2(minf(980.0, vp.x - 40.0), minf(580.0, vp.y - 40.0))
	_face_player(e)
	_camera_in(true)
	_say(speaker.name, DialogueEngine.greeting(speaker, _world), "")
	_refresh()
	opened.emit()
	return true


# The person turns to look at you (and plays a "talk" animation once animations exist)
func _face_player(e: Enemy) -> void:
	var p := _player as Node3D
	if p == null or not e.is_inside_tree():
		return
	var d := p.global_position - e.global_position
	d.y = 0.0
	if d.length() > 0.1:
		e.rotation.y = atan2(-d.x, -d.z)
	var hooks := e.get_node_or_null("AnimationHooks") as AnimationHooks
	if hooks != null:
		hooks.trigger(&"talk")


# Settings > Interface > Camera in conversations: "Ease in" narrows the view a little
func _camera_in(on: bool) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or int(GameSettings.get_value("dialogue_camera")) != 1:
		return
	if on:
		_fov_before = cam.fov
		var tw := create_tween()
		tw.tween_property(cam, "fov", _fov_before * 0.82, 0.35)
	elif _fov_before > 0.0:
		var tw := create_tween()
		tw.tween_property(cam, "fov", _fov_before, 0.25)
		_fov_before = 0.0


func _apply_text_size() -> void:
	var size := float(GameSettings.get_value("text_size"))
	_log.add_theme_font_size_override("normal_font_size", roundi(17 * size))
	_log.add_theme_font_size_override("bold_font_size", roundi(17 * size))
	_log.add_theme_font_size_override("italics_font_size", roundi(17 * size))
	var contrast := bool(GameSettings.get_value("high_contrast"))
	_log.add_theme_color_override("default_color", Color(1, 1, 1) if contrast else Color(0.92, 0.9, 0.85))


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_camera_in(false)
	if speaker != null and speaker.enemy != null and is_instance_valid(speaker.enemy) and not speaker.enemy.is_dead():
		var talk := speaker.enemy.get_node_or_null("NpcTalk") as NpcTalk
		if talk != null:
			talk.say(DialogueEngine.farewell(speaker, _world))  # their goodbye, over their head
	var journal := get_tree().get_first_node_in_group("journal_ui") as JournalUI
	var barter := get_tree().get_first_node_in_group("barter_ui") as BarterUI
	if barter != null and barter.is_open():
		barter.close()
	if journal == null or not journal.is_open():
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## Asks about a topic (what clicking it does). Returns DialogueEngine.respond()'s result.
func ask(topic: String) -> Dictionary:
	if not _open or speaker == null:
		return {}
	_focus_topic = topic
	var r := DialogueEngine.respond(speaker, topic, _world)
	QuestEvents.talk(get_tree(), speaker, topic)
	var text := String(r["text"])
	_say(speaker.name, text, topic)
	Barks.voice(get_tree(), speaker.name, text)
	var ix := DialogueEngine.index(_world)
	for f in DialogueEngine.find_topics(text, ix):
		DialogueState.learn(String(f["name"]))
	for t in r.get("learn", PackedStringArray()):
		DialogueState.learn(String(t))
	var resp := r.get("response") as DialogueResponse
	if resp != null:
		for c in resp.choices:  # branching: the player's possible replies, right here
			DialogueState.learn(c)
			_log.append_text("   [url=%s][color=%s]> %s[/color][/url]\n" % [String(c).uri_encode(), LINK, _esc(c)])
		if resp.set_flag != "":
			DialogueState.set_flag(resp.set_flag)
		if resp.give_item != null:
			var inv := _player.get_node_or_null("Inventory") as Inventory if _player != null else null
			if inv != null:
				inv.add_item(resp.give_item, maxi(resp.give_count, 1))
				_note("You received %s." % resp.give_item.display_name)
	_last_answer = text
	DialogueState.mark_asked(topic)
	var kind := DialogueState.entry_type(topic, String(r.get("quest_id", "")), String(DialogueEngine.index(_world).entries.get(topic.to_lower(), {}).get("kind", "")))
	if bool(r.get("journal", false)) and kind != "":
		var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
		var added := DialogueState.add_journal({
			"text": text,
			"speaker": speaker.name,
			"npc_id": speaker.id,
			"type": kind,
			"topic": topic,
			"place": speaker.town.town.display_name if speaker.town != null and speaker.town.town != null else "",
			"day": clock.day if clock != null else 1,
			"time": clock.get_time_text() if clock != null else "",
			"quest_id": r.get("quest_id", ""),
			"quest_name": r.get("quest_name", ""),
		})
		if added:
			_note("Your journal has been updated.")
	_refresh()
	answered.emit(topic, r)
	return r


## One persuasion attempt (what the Persuade buttons do)
func persuade(kind: Persuasion.Kind) -> Dictionary:
	if not _open or speaker == null:
		return {}
	if Persuasion.locked(kind, speaker, _hours()):
		_note("They won't fall for that again so soon.")
		return {"success": false, "change": 0, "text": ""}
	var res := Persuasion.attempt(kind, speaker, _player, _rng)
	if res["success"]:
		QuestEvents.persuade(get_tree(), speaker, int(res.get("disposition", 0)))
	else:
		Persuasion.lock(kind, speaker, _hours())  # failing has a cost: that approach is closed for a while
	_log.append_text("\n[i]You try: %s.[/i]  %s\n" % [Persuasion.LABELS[kind], "[color=#8fd18f]It works.[/color]" if res["success"] else "[color=#e07a6f]It doesn't work.[/color]"])
	_say(speaker.name, String(res["text"]), "")
	_refresh()
	return res


## Opens the trade window with this person (their shop must be open). Returns false if not.
func open_barter() -> bool:
	var barter := get_tree().get_first_node_in_group("barter_ui") as BarterUI
	if not _open or barter == null:
		return false
	if not barter.closed.is_connected(_refresh):
		barter.closed.connect(_refresh)  # disposition and Speech may have changed
	return barter.open_for(speaker)


func _input(event: InputEvent) -> void:
	if not _open or not event.is_action_pressed("ui_cancel"):
		return
	var journal := get_tree().get_first_node_in_group("journal_ui") as JournalUI
	if journal != null and journal.is_open():
		return  # Esc closes the journal first
	var barter := get_tree().get_first_node_in_group("barter_ui") as BarterUI
	if barter != null and barter.is_open():
		return  # and the trade window
	close()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- showing things

func _say(who: String, text: String, topic: String) -> void:
	var shown_before := _log.get_total_character_count()
	if topic != "":
		_log.append_text("\n[color=%s][b]%s[/b][/color]\n" % [TOPIC_COLOR, _esc(topic)])
	else:
		_log.append_text("\n")
	_log.append_text("[color=#d9cfbf]%s:[/color] %s\n" % [_esc(who), linkify(text, DialogueEngine.index(_world))])
	if bool(GameSettings.get_value("dialogue_typewriter")) and _open:
		_log.visible_characters = shown_before  # then revealed letter by letter (_process)
		_typing = true


## Shows the whole answer at once (a click on the text)
func skip_typing() -> void:
	_typing = false
	_log.visible_characters = -1


func _process(delta: float) -> void:
	if not _open:
		return
	if _typing:
		_log.visible_characters += maxi(1, roundi(delta * TYPE_SPEED))
		if _log.visible_characters >= _log.get_total_character_count():
			skip_typing()
	# the person died, turned on you, or a save is loading: the conversation is over
	var e := speaker.enemy if speaker != null else null
	var sm := SaveManager.of(get_tree())
	if (e != null and (not is_instance_valid(e) or e.is_dead() or e.disposition == Enemy.Disposition.HOSTILE)) or (sm != null and sm.is_loading()):
		close()


func _note(text: String) -> void:
	_log.append_text("[color=#8fd18f][i]%s[/i][/color]\n" % _esc(text))


## The text as BBCode with every topic name made a clickable link
static func linkify(text: String, ix: DialogueEngine.Index) -> String:
	var out := ""
	var pos := 0
	for f in DialogueEngine.find_topics(text, ix):
		out += _esc(text.substr(pos, int(f["at"]) - pos))
		# the link target is URI-encoded: names like "Brenna's House" would break the BBCode otherwise
		out += "[color=%s][url=%s]%s[/url][/color]" % [LINK, String(f["name"]).uri_encode(), _esc(text.substr(int(f["at"]), int(f["end"]) - int(f["at"])))]
		pos = int(f["end"])
	return out + _esc(text.substr(pos))


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


func _refresh() -> void:
	if speaker == null:
		return
	var role := NpcData.role_name(speaker.role) if speaker.data != null else "Traveler"
	var where := speaker.town.town.display_name if speaker.data != null and speaker.town != null and speaker.town.town != null else ""
	_name_label.text = speaker.name
	_sub_label.text = role + ((", " + where) if where != "" else "")
	var disp := DialogueEngine.get_disposition(speaker)
	_disp_bar.value = disp
	_disp_label.text = "Disposition %d" % disp
	var old_count := _topics.get_child_count()  # the old buttons stay until the frame ends
	for c in _topics.get_children():
		c.queue_free()
	for t in DialogueEngine.topics_for(speaker, _world):
		var b := Button.new()
		b.text = t
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long topic wraps in its column, never widens the window
		b.custom_minimum_size = Vector2(1, 0)
		# new topics stand out (Morrowind style), ones already asked about are dimmed
		var c := Color(0.85, 0.9, 1.0) if not DialogueEngine.GENERIC.has(t) else Color(1, 1, 1)
		if not DialogueState.was_asked(t):
			c = Color(1.0, 0.85, 0.45)
			b.text = t + "  •"
		elif not QuestManager.TOPICS.has(t):
			c = c.darkened(0.35)
		b.add_theme_color_override("font_color", c)
		b.pressed.connect(ask.bind(t))
		_topics.add_child(b)
		if (_focus_topic == "" and b.get_index() == old_count) or t == _focus_topic:
			b.grab_focus.call_deferred()  # the keyboard: Up / Down through the topics, Enter asks
	var trade := Barter.trade_status(speaker, _world)
	_barter_button.visible = trade["merchant"] != null
	_barter_button.disabled = not trade["open"]
	_barter_button.text = "Barter" if trade["open"] else "Barter (%s)" % trade["why"]
	for c in _services.get_children():
		c.queue_free()
	for sv: Dictionary in Services.for_speaker(speaker, _world, _player):
		if sv["id"] == "trade":
			continue  # the Barter button above
		var sb := Button.new()
		sb.text = tr(String(sv["label"]))
		if sv["why"] != "":
			sb.tooltip_text = String(sv["why"])  # why it is not offered: on hover, so the row stays short
			sb.text += " *"
		sb.disabled = sv["why"] != ""
		sb.custom_minimum_size = Vector2(110, 32)
		sb.pressed.connect(use_service.bind(String(sv["id"])))
		_services.add_child(sb)
	for i in _persuade_buttons.size():
		var kind := i as Persuasion.Kind
		var why := Persuasion.blocked(kind, _player)
		if why == "" and Persuasion.locked(kind, speaker, _hours()):
			why = "not again yet"
		var btn := _persuade_buttons[i]
		btn.disabled = why != ""
		btn.text = "%s  %d%%" % [Persuasion.LABELS[i], roundi(Persuasion.chance_for(kind, speaker, _player) * 100.0)] if why == "" else "%s  (%s)" % [Persuasion.LABELS[i], why]
		btn.tooltip_text = "A %s check, helped by %s" % [Persuasion.SKILL, String(Persuasion.STAT_OF[kind]).capitalize()]


## A service button (Services): Train, Rent Room, Duties, Travel, Repair, Enchant
func use_service(id: String) -> void:
	if not _open or speaker == null:
		return
	match id:
		"duties":
			ask("duties")
		"train":
			var sk := _player.get_node("Skills") as Skills
			_log.append_text("\n[i]Training (%d left at this level):[/i]\n" % Services.trainings_left(_player))
			for skill in Services.trains(speaker, _world):
				var lvl := sk.get_level(StringName(skill))
				var line := "%s %d" % [String(skill).capitalize(), lvl]
				if lvl >= Services.train_max(speaker, _world):
					_log.append_text("   %s  (can't teach you more)\n" % line)
				else:
					_log.append_text("   [url=train:%s][color=%s]%s → %d   %d gold[/color][/url]\n" % [skill, LINK, line, lvl + 1, Services.train_cost(lvl, speaker)])
		"rent":
			var text := Services.rent(speaker, _player)
			close()
			Locks.toast(get_tree(), text)
		"travel":
			close()
			Services.travel(speaker, _world, _player)
		"repair", "enchant":
			var text := Services.repair(_player) if id == "repair" else Services.enchant(_player)
			if Currency.get_gold(_player.get_node("Inventory") as Inventory) >= 0 and (text.begins_with("Use") or text.begins_with("The table is yours")):
				close()
			else:
				_say(speaker.name, text, "")
	_refresh()


## Gives the person a small gift from your pack (food, flowers, jewelry): they like you more
func give_gift() -> void:
	if not _open or speaker == null:
		return
	var inv := _player.get_node("Inventory") as Inventory
	var best: ItemData = null
	for s in inv.stacks:
		var it := s.item
		if QuestItems.is_quest_item(it) or it.item_type in [ItemData.ItemType.WEAPON, ItemData.ItemType.ARMOR, ItemData.ItemType.KEY] or it.id == &"gold":
			continue
		if best == null or it.value > best.value:
			best = it
	if best == null:
		_note("You have nothing to give.")
		return
	inv.remove_item(best, 1)
	var gain := clampi(2 + best.value / 10, 2, 15)
	DialogueState.change_disposition(speaker.id, speaker.base_disposition, gain)
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	NpcMemory.remember(speaker.name, speaker.town.town.display_name if speaker.town != null and speaker.town.town != null else "", "gift", best.display_name, clock.day if clock != null else 1)
	_note("You give %s %s." % [speaker.name, best.display_name])
	_say(speaker.name, ["For me? Thank you.", "How kind. I won't forget it.", "Oh! You shouldn't have."][_rng.randi_range(0, 2)], "")
	_refresh()


## Copies what was just said into a new note in the journal
func note_last() -> void:
	var j := get_tree().get_first_node_in_group("journal_ui") as JournalUI
	if j == null or _last_answer == "":
		return
	j.open()
	j.edit_note(0, "%s: %s" % [speaker.name if speaker != null else "", _last_answer])


func _on_meta(meta: Variant) -> void:
	var m := String(meta)
	if m.begins_with("train:"):
		var said := Services.train(m.trim_prefix("train:"), speaker, _world, _player)
		_say(speaker.name, said, "")
		_refresh()
		return
	ask(m.uri_decode())


func _hours() -> float:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	return float(clock.day) * 24.0 + clock.hour if clock != null else 0.0


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	var panel := _panel
	panel.custom_minimum_size = Vector2(980, 580)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# header
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(names)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 26)
	names.add_child(_name_label)
	_sub_label = Label.new()
	_sub_label.add_theme_color_override("font_color", GOLD)
	names.add_child(_sub_label)
	var disp_box := VBoxContainer.new()
	disp_box.custom_minimum_size = Vector2(220, 0)
	header.add_child(disp_box)
	_disp_label = Label.new()
	_disp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	disp_box.add_child(_disp_label)
	_disp_bar = ProgressBar.new()
	_disp_bar.max_value = 100
	_disp_bar.show_percentage = false
	_disp_bar.custom_minimum_size = Vector2(220, 14)
	disp_box.add_child(_disp_bar)

	# talk and topics
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_stretch_ratio = 2.6
	_log.meta_clicked.connect(_on_meta)
	_log.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			skip_typing())
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.add_theme_font_size_override("bold_font_size", 17)
	split.add_child(_log)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var topics_title := Label.new()
	topics_title.text = "Topics"
	topics_title.add_theme_color_override("font_color", GOLD)
	right.add_child(topics_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_topics = VBoxContainer.new()
	_topics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_topics)

	# persuasion
	_persuade_row = HBoxContainer.new()
	_persuade_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_persuade_row)
	for i in Persuasion.LABELS.size():
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: persuade(i as Persuasion.Kind))
		_persuade_row.add_child(b)
		_persuade_buttons.append(b)

	# buttons
	var buttons := HFlowContainer.new()  # wraps to a second row rather than running off the screen
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 6)
	vbox.add_child(buttons)
	var persuade_btn := Button.new()
	persuade_btn.text = "Persuade"
	persuade_btn.custom_minimum_size = Vector2(140, 36)
	persuade_btn.pressed.connect(func() -> void: _persuade_row.visible = not _persuade_row.visible)
	buttons.add_child(persuade_btn)
	_barter_button = Button.new()
	_barter_button.text = "Barter"
	_barter_button.custom_minimum_size = Vector2(140, 36)
	_barter_button.pressed.connect(open_barter)
	buttons.add_child(_barter_button)
	_services = HFlowContainer.new()
	_services.add_theme_constant_override("h_separation", 6)
	buttons.add_child(_services)
	var gift := Button.new()
	gift.text = "Gift"
	gift.tooltip_text = "Give them something from your pack: they will like you more"
	gift.custom_minimum_size = Vector2(80, 36)
	gift.pressed.connect(give_gift)
	buttons.add_child(gift)
	var note := Button.new()
	note.text = "Add to notes"
	note.tooltip_text = "Copy what was just said into a new note in your journal"
	note.custom_minimum_size = Vector2(120, 36)
	note.pressed.connect(note_last)
	buttons.add_child(note)
	var journal_btn := Button.new()
	journal_btn.text = "Journal"
	journal_btn.custom_minimum_size = Vector2(140, 36)
	journal_btn.pressed.connect(func() -> void:
		var j := get_tree().get_first_node_in_group("journal_ui") as JournalUI
		if j != null:
			j.open())
	buttons.add_child(journal_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var hint := Label.new()
	hint.text = "Click a topic or a highlighted word    [Esc] Goodbye"
	hint.modulate = Color(1, 1, 1, 0.5)
	buttons.add_child(hint)
	var bye := Button.new()
	bye.text = "Goodbye"
	bye.custom_minimum_size = Vector2(140, 36)
	bye.pressed.connect(close)
	buttons.add_child(bye)
