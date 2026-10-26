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
##   notes        your own notes: "+ New note" writes one (a title and the words), click one to
##                read it, then Edit or Delete. A note being written is kept if the journal closes.
## One entry per topic (DialogueState.add_journal): old saves are cleaned when the journal opens.

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
var _track: Button
## "all", "quest" or "topic", and which one
var _filter_kind := "all"
var _filter_value := ""
var _filter_rows: Array = []  # per ItemList row: [kind, value]
## The note editor (shown instead of the entries while writing)
var _editor: VBoxContainer
var _note_title: LineEdit
var _note_body: TextEdit
var _note_count: Label
var _note_delete: Button
var _editing := 0   # the note being edited (0 = a new one)
var _confirm_delete := false


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
	DialogueState.compact_journal()
	_refresh()
	_filters.grab_focus()  # click the search box to type (so 1-4 and Tab still switch pages)
	opened.emit()


func close() -> void:
	if not _open:
		return
	if is_editing():
		save_note()  # never lose what was being written
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
		if is_editing():
			cancel_note()  # Esc while writing: back to the journal (the words are kept if changed)
		else:
			close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- notes

func is_editing() -> bool:
	return _editor != null and _editor.visible


## Opens the editor: a new note (id 0), or an existing one
func edit_note(id: int = 0) -> void:
	var n := DialogueState.get_note(id) if id != 0 else {}
	_editing = int(n.get("id", 0))
	_note_title.text = String(n.get("title", ""))
	_note_body.text = String(n.get("text", ""))
	_confirm_delete = false
	_note_delete.visible = _editing != 0
	_note_delete.text = "Delete"
	_editor.visible = true
	_text.visible = false
	_update_count()
	if _editing != 0:
		_note_body.grab_focus()
	else:
		_note_title.grab_focus()


## Saves what is in the editor and shows the note. Returns its id (0 if there was nothing to save).
func save_note() -> int:
	var body := _note_body.text.strip_edges(false, true)
	var title := _note_title.text
	_editor.visible = false
	_text.visible = true
	if body.strip_edges() == "" and title.strip_edges() == "":
		_refresh()
		return 0
	if _editing != 0:
		DialogueState.edit_note(_editing, title, body)
	else:
		var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
		var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
		_editing = DialogueState.add_note(title, body, clock.day if clock != null else 1, clock.get_time_text() if clock != null else "", _where(world))
	_filter_kind = "note"
	_filter_value = str(_editing)
	_refresh()
	return _editing


## Leaves the editor. A changed note is still saved, so nothing written is ever lost.
func cancel_note() -> void:
	var old := DialogueState.get_note(_editing) if _editing != 0 else {}
	var changed := _note_body.text != String(old.get("text", "")) or (_note_title.text != String(old.get("title", "")) and _note_title.text.strip_edges() != "")
	if changed:
		save_note()
		return
	_editor.visible = false
	_text.visible = true
	_refresh()


func delete_note() -> void:
	if _editing == 0:
		return
	if not _confirm_delete:
		_confirm_delete = true
		_note_delete.text = "Really delete?"
		return
	DialogueState.delete_note(_editing)
	_editing = 0
	_editor.visible = false
	_text.visible = true
	_filter_kind = "notes"
	_filter_value = ""
	_refresh()


func _update_count() -> void:
	_note_count.text = "%d / %d" % [_note_body.text.length(), DialogueState.NOTE_MAX]


# Where the player is: the building or dungeon they are in, else the nearest town
static func _where(world: WorldManager) -> String:
	if world == null:
		return ""
	if world.dungeons != null and world.dungeons.is_inside():
		return world.dungeons.get_current_name()
	var p := world.get_tree().get_first_node_in_group("player") as Node3D
	var t := world.get_nearest_town(p.global_position) if p != null else null
	return t.town.display_name if t != null and t.town != null else ""


func _show_notes(list: Array, q: String) -> void:
	if list.is_empty():
		_text.append_text("[i]No notes yet. Pick \"+ New note\" on the left to write one.[/i]")
		return
	for n: Dictionary in list:
		_show_note(n, q)


func _show_note(n: Dictionary, q: String) -> void:
	var head := "Day %d, %s" % [int(n.get("day", 1)), n.get("time", "")]
	if String(n.get("place", "")) != "":
		head += "  ·  " + String(n["place"])
	_text.append_text("[color=#ffd95a][b]%s[/b][/color]   [url=note:edit:%d][color=#9fc7ff]Edit[/color][/url]\n" % [_mark(String(n["title"]), q), int(n["id"])])
	_text.append_text("[color=#b8a47a]%s[/color]\n%s\n\n" % [DialogueUI._esc(head), _mark(String(n["text"]), q)])


static func _note_matches(n: Dictionary, q: String) -> bool:
	return q == "" or ("%s\n%s\n%s" % [n.get("title", ""), n.get("text", ""), n.get("place", "")]).to_lower().contains(q.to_lower())


func _on_meta(meta: Variant) -> void:
	var m := String(meta)
	if m.begins_with("note:edit:"):
		edit_note(int(m.trim_prefix("note:edit:")))
		return
	show_topic(m.uri_decode())


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
		var pin := "  (tracked)" if QuestManager.tracked_id() == q else ""
		_add_row("   " + String(quests[q]) + ("  (done)" if done else "") + pin, "quest", q)
	_add_header("Topics")
	var tkeys := topics.keys()
	tkeys.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	for t in tkeys:
		_add_row("   %s  (%d)" % [t, topics[t]], "topic", t)
	var notes := DialogueState.notes()
	_add_header("Your notes")
	_add_row("   + New note", "new_note", "")
	if not notes.is_empty():
		_add_row("   All notes  (%d)" % notes.size(), "notes", "")
	for n: Dictionary in notes:
		_add_row("      " + String(n["title"]), "note", str(n["id"]))
	for i in _filter_rows.size():
		var row: Array = _filter_rows[i]
		if row[0] == _filter_kind and row[1] == _filter_value:
			_filters.select(i)

	_track.visible = _filter_kind == "quest"
	_track.text = "Stop tracking" if _filter_kind == "quest" and QuestManager.tracked_id() == _filter_value else "Track on compass"

	_text.clear()
	var q_notes := _search.text.strip_edges()
	if _filter_kind == "notes" or _filter_kind == "note":
		var list := notes.filter(func(n: Dictionary) -> bool:
			return (_filter_kind == "notes" or str(n["id"]) == _filter_value) and _note_matches(n, q_notes))
		_count.text = "%d of %d notes" % [list.size(), notes.size()]
		_show_notes(list, q_notes)
		return
	var shown := filter(entries, _search.text, _filter_kind, _filter_value)
	var job: Dictionary = jobs.get(_filter_value, {}) if _filter_kind == "quest" else {}
	_count.text = "%d of %d entries" % [shown.size(), entries.size()]
	if _filter_kind == "all" and q_notes != "":
		# a search looks through your notes too
		for n: Dictionary in notes:
			if _note_matches(n, q_notes):
				_show_note(n, q_notes)
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
		var who := String(e.get("speaker", ""))
		var heard: Array = e.get("heard", [])
		if heard.size() > 1:
			who += " (and %d other%s)" % [heard.size() - 1, "" if heard.size() == 2 else "s"]
		var head := "Day %d, %s  ·  %s" % [int(e.get("day", 1)), e.get("time", ""), who]
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
	if is_editing():
		save_note()
	if row[0] == "new_note":
		edit_note(0)
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
	center.offset_top = UITheme.HUB_BAR_HEIGHT  # room for the Tab menu bar
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 540)
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
	var title := UITheme.heading("Journal")
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
	# Shown when a quest is picked on the left: pin it so the compass points only at it
	_track = Button.new()
	_track.focus_mode = Control.FOCUS_NONE
	_track.pressed.connect(func() -> void:
		QuestManager.toggle_tracked(_filter_value)
		_refresh())
	top.add_child(_track)

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
	_text.meta_clicked.connect(_on_meta)
	split.add_child(_text)

	# the note editor, in the same place as the entries
	_editor = VBoxContainer.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 8)
	_editor.visible = false
	split.add_child(_editor)
	_note_title = LineEdit.new()
	_note_title.placeholder_text = "Title (optional)"
	_note_title.max_length = 60
	_editor.add_child(_note_title)
	_note_body = TextEdit.new()
	_note_body.placeholder_text = "Write your note here..."
	_note_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_body.add_theme_font_size_override("font_size", 17)
	_note_body.text_changed.connect(func() -> void:
		if _note_body.text.length() > DialogueState.NOTE_MAX:
			_note_body.text = _note_body.text.left(DialogueState.NOTE_MAX)
			_note_body.set_caret_column(_note_body.get_line(_note_body.get_line_count() - 1).length())
			_note_body.set_caret_line(_note_body.get_line_count() - 1)
		_update_count())
	_editor.add_child(_note_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_editor.add_child(row)
	var save := Button.new()
	save.text = "Save"
	save.custom_minimum_size = Vector2(110, 32)
	save.pressed.connect(func() -> void: save_note())
	row.add_child(save)
	var cancel := Button.new()
	cancel.text = "Close"
	cancel.custom_minimum_size = Vector2(110, 32)
	cancel.pressed.connect(cancel_note)
	row.add_child(cancel)
	_note_delete = Button.new()
	_note_delete.text = "Delete"
	_note_delete.custom_minimum_size = Vector2(130, 32)
	_note_delete.pressed.connect(delete_note)
	row.add_child(_note_delete)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_note_count = Label.new()
	_note_count.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_note_count)

	var hint := Label.new()
	hint.text = "Click a highlighted word to see everything about it    + New note writes your own    [J] or [Esc] Close"
	hint.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(hint)
