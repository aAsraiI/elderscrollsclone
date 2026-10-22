class_name JournalUI
extends CanvasLayer
## The journal (J), Morrowind style: every unique thing people have told you, in the order you
## heard it, with who said it, where and when. The same words from two people are only written
## down once (the first time). Created by player.gd. The game pauses while it is open.
##
##   search bar   shows only entries that mention the words (in the text, the speaker, the topic,
##                the place or the quest); matches are highlighted
##   left list    All entries, each Quest (stage 6 fills these in; example topics use it now),
##                each Topic
##   entries      topic names in the text are links: click one to see everything about that topic

signal opened
signal closed

const ACTION := "journal"
const GOLD := Color(1.0, 0.85, 0.35)

var _open := false
var _was_paused := false
var _root: Control
var _search: LineEdit
var _filters: ItemList
var _text: RichTextLabel
var _count: Label
## "all", "quest" or "topic", and which one
var _filter_kind := "all"
var _filter_value := ""
var _filter_rows: Array = []  # per ItemList row: [kind, value]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 16
	add_to_group("journal_ui")
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_J
		InputMap.action_add_event(ACTION, ev)
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_search.grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if not _was_paused:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## Shows only entries about one topic ("" = all)
func show_topic(topic: String) -> void:
	_filter_kind = "topic" if topic != "" else "all"
	_filter_value = topic
	_refresh()


func set_search(text: String) -> void:
	_search.text = text
	_refresh()


## The entries that pass the search and the filter (pure: the tests use it)
static func filter(entries: Array, query: String, kind: String = "all", value: String = "") -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for e: Dictionary in entries:
		if kind == "quest" and String(e.get("quest_id", "")) != value:
			continue
		if kind == "topic" and String(e.get("topic", "")).to_lower() != value.to_lower() and not String(e.get("text", "")).to_lower().contains(value.to_lower()):
			continue
		if q != "":
			var hay := "%s\n%s\n%s\n%s\n%s" % [e.get("text", ""), e.get("speaker", ""), e.get("topic", ""), e.get("place", ""), e.get("quest_name", "")]
			if not hay.to_lower().contains(q):
				continue
		out.append(e)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION) or event.is_echo():
		return
	if _open:
		if not _search.has_focus():
			close()
			get_viewport().set_input_as_handled()
		return
	var dialogue := get_tree().get_first_node_in_group("dialogue_ui") as DialogueUI
	if get_tree().paused and (dialogue == null or not dialogue.is_open()):
		return  # some other menu is open
	open()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- showing

func _refresh() -> void:
	var entries := DialogueState.journal()
	# the filter list: all, quests, topics
	_filters.clear()
	_filter_rows.clear()
	_add_row("All entries  (%d)" % entries.size(), "all", "")
	var quests := {}
	var topics := {}
	for e: Dictionary in entries:
		if String(e.get("quest_id", "")) != "":
			quests[e["quest_id"]] = String(e.get("quest_name", e["quest_id"]))
		var t := String(e.get("topic", ""))
		if t != "":
			topics[t] = int(topics.get(t, 0)) + 1
	# Guild jobs: active ones first, finished ones marked
	var jobs := {}
	for q: Dictionary in QuestManager.all_quests():
		jobs[q["id"]] = q
		quests[q["id"]] = String(q["name"])
	_add_header("Quests")
	if quests.is_empty():
		_add_header("   (none yet)")
	var qkeys := quests.keys()
	qkeys.sort_custom(func(a: String, b: String) -> bool:
		var da: bool = jobs.has(a) and jobs[a]["status"] == "done"
		var db: bool = jobs.has(b) and jobs[b]["status"] == "done"
		if da != db:
			return db
		return String(quests[a]) < String(quests[b]))
	for q in qkeys:
		var done: bool = jobs.has(q) and jobs[q]["status"] == "done"
		_add_row("   " + String(quests[q]) + ("  (done)" if done else ""), "quest", q)
	_add_header("Topics")
	var tkeys := topics.keys()
	tkeys.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	for t in tkeys:
		_add_row("   %s  (%d)" % [t, topics[t]], "topic", t)
	for i in _filter_rows.size():
		var row: Array = _filter_rows[i]
		if row[0] == _filter_kind and row[1] == _filter_value:
			_filters.select(i)

	var shown := filter(entries, _search.text, _filter_kind, _filter_value)
	var job: Dictionary = jobs.get(_filter_value, {}) if _filter_kind == "quest" else {}
	_count.text = "%d of %d entries" % [shown.size(), entries.size()]
	_text.clear()
	if not job.is_empty():
		# The job itself first: what to do, and whether it's finished
		var status := "Finished" if job["status"] == "done" else "In progress"
		_text.append_text("[color=#ffd95a][b]%s[/b]  ·  %s  ·  %s[/color]\n" % [DialogueUI._esc(String(job["name"])), Factions.display_name(String(job["faction"])), status])
		if job["status"] != "done":
			_text.append_text("[color=#e8e0c8]Objective: %s[/color]\n" % DialogueUI._esc(String(job["objective"])))
		_text.append_text("\n")
	elif _filter_kind == "all" and _search.text.strip_edges() == "":
		var active := PackedStringArray()
		for j: Dictionary in jobs.values():
			if j["status"] == "active":
				active.append("[color=#ffd95a]%s[/color]: %s" % [DialogueUI._esc(String(j["name"])), DialogueUI._esc(String(j["objective"]))])
		if not active.is_empty():
			_text.append_text("[b]Active quests[/b]\n" + "\n".join(active) + "\n\n")
	if entries.is_empty():
		_text.append_text("[i]Nothing written yet. Talk to people: what they tell you is written down here.[/i]")
		return
	if shown.is_empty():
		_text.append_text("[i]Nothing matches.[/i]")
		return
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var ix := DialogueEngine.index(world)
	var q := _search.text.strip_edges()
	for e: Dictionary in shown:
		var head := "Day %d, %s  ·  %s" % [int(e.get("day", 1)), e.get("time", ""), e.get("speaker", "")]
		if String(e.get("place", "")) != "":
			head += ", " + String(e["place"])
		if String(e.get("topic", "")) != "":
			head += "  ·  on " + String(e["topic"])
		_text.append_text("[color=#b8a47a]%s[/color]\n" % _mark(head, q))
		if String(e.get("quest_name", "")) != "":
			_text.append_text("[color=#ffd95a]Quest: %s[/color]\n" % _mark(String(e["quest_name"]), q))
		var body := String(e.get("text", ""))
		_text.append_text((_mark(body, q) if q != "" else DialogueUI.linkify(body, ix)) + "\n\n")


# Highlights every match of q (case-insensitive) in plain text, as BBCode
static func _mark(text: String, q: String) -> String:
	if q == "":
		return DialogueUI._esc(text)
	var low := text.to_lower()
	var ql := q.to_lower()
	var out := ""
	var pos := 0
	while true:
		var at := low.find(ql, pos)
		if at < 0:
			break
		out += DialogueUI._esc(text.substr(pos, at - pos))
		out += "[bgcolor=#7a5a10][color=#ffffff]%s[/color][/bgcolor]" % DialogueUI._esc(text.substr(at, ql.length()))
		pos = at + ql.length()
	return out + DialogueUI._esc(text.substr(pos))


func _add_row(label: String, kind: String, value: String) -> void:
	_filters.add_item(label)
	_filter_rows.append([kind, value])


func _add_header(label: String) -> void:
	var i := _filters.add_item(label, null, false)
	_filters.set_item_custom_fg_color(i, GOLD)
	_filter_rows.append(["", ""])


func _on_filter_selected(i: int) -> void:
	var row: Array = _filter_rows[i]
	if row[0] == "":
		return
	_filter_kind = row[0]
	_filter_value = row[1]
	_refresh()


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)  # dark enough to hide the dialogue window behind it
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 600)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vbox.add_child(top)
	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_size_override("font_size", 26)
	top.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search everything ever mentioned..."
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _refresh())
	top.add_child(_search)
	_count = Label.new()
	_count.add_theme_color_override("font_color", GOLD)
	top.add_child(_count)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)
	_filters = ItemList.new()
	_filters.custom_minimum_size = Vector2(260, 0)
	_filters.item_selected.connect(_on_filter_selected)
	split.add_child(_filters)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.meta_clicked.connect(func(meta: Variant) -> void: show_topic(String(meta).uri_decode()))
	split.add_child(_text)

	var hint := Label.new()
	hint.text = "Click a highlighted word to see everything about it    [J] or [Esc] Close"
	hint.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(hint)
