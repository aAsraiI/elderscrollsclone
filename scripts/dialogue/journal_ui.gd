class_name JournalUI
extends CanvasLayer
## The journal (J; Shift+J writes a new note from anywhere; also on the pause screen). Created by
## player.gd. The game pauses while it is open. It reopens on the tab and page you left.
##
##   tabs       Quests, Topics, Places, People, Notes, All
##   left       the tab's list in collapsible groups (Bookmarks first). Quests: Active, Completed,
##              Failed, Abandoned. A dot marks something new or updated (unread).
##   top        search (everything, notes too), a filter (guild, town or type) and the order
##              (newest, oldest, A-Z), and Mark all read
##   page       a quest: what it is, who gave it, its objectives (ticked when done), the next
##              step, the reward, your linked notes and everything written about it, with Track,
##              Abandon and Bookmark. A topic: everything said about it, each with "Add to notes".
##   notes      your own notes: a title and the words, pinned ones first, a colour, a link to a
##              quest or place (shown on its page). Ctrl+Enter saves, Esc leaves (asking first if
##              something is unsaved). Closing the journal mid-note keeps it. Export writes them
##              all to a text file.
## One entry per topic (DialogueState.add_journal): old saves are cleaned when the journal opens.

signal opened
signal closed

const ACTION := "journal"
const GOLD := Color(1.0, 0.85, 0.35)
const TABS := ["Quests", "Topics", "Places", "People", "Notes", "All"]
const TAB_QUESTS := 0
const TAB_TOPICS := 1
const TAB_PLACES := 2
const TAB_PEOPLE := 3
const TAB_NOTES := 4
const TAB_ALL := 5
const SORTS := ["Newest", "Oldest", "A-Z"]
## Note colours: chosen to stay apart for colourblind eyes (blue, orange, yellow, purple, grey)
const NOTE_COLORS := ["None", "Blue", "Orange", "Yellow", "Purple", "Grey"]
const NOTE_HEX := ["", "#6ea8fe", "#f0a050", "#ffe066", "#c39bf0", "#a0a0a0"]

## Where the journal was left (it reopens there)
static var _last_tab := TAB_ALL
static var _last_kind := "all"
static var _last_value := ""

var _open := false
var _was_paused := false
var _root: Control
var _tabs: TabBar
var _search: LineEdit
var _filter_opt: OptionButton
var _sort_opt: OptionButton
var _list: Tree
var _text: RichTextLabel
var _count: Label
var _actions: HBoxContainer
var _track: Button
var _abandon: Button
var _bookmark: Button
var _status: Label
## "all", "quest", "topic", "type", "notes", "note", and which one
var _filter_kind := "all"
var _filter_value := ""
var _confirm_abandon := false
var _filter_values: Array = []
## The note editor (shown instead of the page while writing)
var _editor: VBoxContainer
var _note_title: LineEdit
var _note_body: TextEdit
var _note_count: Label
var _note_delete: Button
var _note_pin: CheckBox
var _note_link: OptionButton
var _note_color: OptionButton
var _link_values: Array = []
var _editing := 0   # the note being edited (0 = a new one)
var _confirm_delete := false
var _confirm_discard := false


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
	_apply_text_size()
	_tabs.current_tab = _last_tab
	_filter_kind = _last_kind
	_filter_value = _last_value
	_rebuild_filter()
	_refresh()
	_list.grab_focus()  # click the search box to type (so 1-4 and Tab still switch pages)
	opened.emit()


func close() -> void:
	if not _open:
		return
	if is_editing():
		save_note()  # never lose what was being written
	_last_tab = _tabs.current_tab
	_last_kind = _filter_kind
	_last_value = _filter_value
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


## Opens a quest's page
func show_quest(id: String) -> void:
	_tabs.current_tab = TAB_QUESTS
	_filter_kind = "quest"
	_filter_value = id
	_rebuild_filter()
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
		if kind == "type" and type_of(e) != value:
			continue
		if q != "":
			var hay := "%s\n%s\n%s\n%s\n%s" % [e.get("text", ""), e.get("speaker", ""), e.get("topic", ""), e.get("place", ""), e.get("quest_name", "")]
			if not hay.to_lower().contains(q):
				continue
		out.append(e)
	return out


## An entry's type (old saves' entries are worked out from what they are about)
static func type_of(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	if t != "":
		return t
	if String(e.get("quest_id", "")) != "":
		return "Quest"
	if String(e.get("topic", "")) == "":
		return "System"
	var w := (Engine.get_main_loop() as SceneTree).get_first_node_in_group("world_manager") as WorldManager
	var kind := String(DialogueEngine.index(w).entries.get(String(e["topic"]).to_lower(), {}).get("kind", ""))
	var et := DialogueState.entry_type(String(e["topic"]), "", kind)
	return et if et != "" else "Knowledge"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION) or event.is_echo():
		return
	var quick := event is InputEventKey and (event as InputEventKey).shift_pressed
	if _open:
		if not _search.has_focus() and not is_editing():
			close()
			get_viewport().set_input_as_handled()
		return
	var dialogue := get_tree().get_first_node_in_group("dialogue_ui") as DialogueUI
	if get_tree().paused and (dialogue == null or not dialogue.is_open()):
		return  # some other menu is open
	open()
	if quick:
		edit_note(0)  # Shift+J: a new note at once
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if is_editing() and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ENTER and (event as InputEventKey).ctrl_pressed:
		save_note()  # Ctrl+Enter saves
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if is_editing():
			cancel_note()  # Esc while writing: back to the journal (asks first if unsaved)
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	# the keyboard: Ctrl+Left / Ctrl+Right switch tabs
	if not is_editing() and event is InputEventKey and event.pressed and (event as InputEventKey).ctrl_pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT or k == KEY_RIGHT:
			_tabs.current_tab = wrapi(_tabs.current_tab + (1 if k == KEY_RIGHT else -1), 0, TABS.size())
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- notes

func is_editing() -> bool:
	return _editor != null and _editor.visible


## Opens the editor: a new note (id 0), or an existing one. body: words to start a new note with
## ("Add to notes" in a conversation or on an entry).
func edit_note(id: int = 0, body: String = "") -> void:
	var n := DialogueState.get_note(id) if id != 0 else {}
	_editing = int(n.get("id", 0))
	_note_title.text = String(n.get("title", ""))
	_note_body.text = String(n.get("text", body))
	_note_body.clear_undo_history()
	_note_pin.button_pressed = bool(n.get("pinned", false))
	_note_color.selected = int(n.get("color", 0))
	_fill_links(String(n.get("link", "")))
	_confirm_delete = false
	_confirm_discard = false
	_note_delete.visible = _editing != 0
	_note_delete.text = "Delete"
	_status.text = ""
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
	_status.text = ""
	if body.strip_edges() == "" and title.strip_edges() == "":
		_refresh()
		return 0
	if _editing != 0:
		DialogueState.edit_note(_editing, title, body)
	else:
		var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
		var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
		_editing = DialogueState.add_note(title, body, clock.day if clock != null else 1, clock.get_time_text() if clock != null else "", _where(world))
	var link: String = _link_values[_note_link.selected] if _note_link.selected >= 0 and _note_link.selected < _link_values.size() else ""
	DialogueState.set_note_fields(_editing, {"pinned": _note_pin.button_pressed, "color": _note_color.selected, "link": link})
	_tabs.current_tab = TAB_NOTES
	_filter_kind = "note"
	_filter_value = str(_editing)
	_refresh()
	return _editing


func _changed() -> bool:
	var old := DialogueState.get_note(_editing) if _editing != 0 else {}
	return _note_body.text != String(old.get("text", "")) or (_note_title.text != String(old.get("title", "")) and _note_title.text.strip_edges() != "")


## Leaves the editor. Unsaved words: the first Esc asks, the second throws them away.
func cancel_note() -> void:
	if _changed() and not _confirm_discard:
		_confirm_discard = true
		_status.text = "Unsaved changes: Esc again to throw them away, Ctrl+Enter to save."
		return
	_confirm_discard = false
	_status.text = ""
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


# The note's "Linked to" choices: nothing, where you are, and the active quests
func _fill_links(current: String) -> void:
	_note_link.clear()
	_link_values = [""]
	_note_link.add_item("Linked to: nothing")
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var here := _where(world)
	if here != "":
		_link_values.append("place:" + here)
		_note_link.add_item("Linked to: " + here)
	for q: Dictionary in QuestLog.all(world):
		if q["status"] == "active" or "quest:" + String(q["id"]) == current:
			_link_values.append("quest:" + String(q["id"]))
			_note_link.add_item("Linked to: " + String(q["name"]))
	if current != "" and not _link_values.has(current):
		_link_values.append(current)
		_note_link.add_item("Linked to: " + current.get_slice(":", 1))
	_note_link.selected = maxi(_link_values.find(current), 0)


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
		_text.append_text("[i]No notes yet. Pick \"+ New note\" on the left (or press Shift+J anywhere) to write one.[/i]")
		return
	for n: Dictionary in list:
		_show_note(n, q)


func _show_note(n: Dictionary, q: String) -> void:
	var head := "%s, %s" % [WorldClock.short_date_of(int(n.get("day", 1))), n.get("time", "")]
	if String(n.get("place", "")) != "":
		head += "  ·  " + String(n["place"])
	if String(n.get("link", "")) != "":
		head += "  ·  about " + String(n["link"]).get_slice(":", 1)
	var col: String = NOTE_HEX[clampi(int(n.get("color", 0)), 0, NOTE_HEX.size() - 1)]
	var title := _mark(String(n["title"]), q)
	if col != "":
		title = "[color=%s]■[/color] %s" % [col, title]
	_text.append_text("[color=#ffd95a][b]%s%s[/b][/color]   [url=note:edit:%d][color=#9fc7ff]Edit[/color][/url]\n" % ["(pinned) " if bool(n.get("pinned", false)) else "", title, int(n["id"])])
	_text.append_text("[color=#b8a47a]%s[/color]\n%s\n\n" % [DialogueUI._esc(head), _mark(String(n["text"]), q)])


static func _note_matches(n: Dictionary, q: String) -> bool:
	return q == "" or ("%s\n%s\n%s" % [n.get("title", ""), n.get("text", ""), n.get("place", "")]).to_lower().contains(q.to_lower())


func _on_meta(meta: Variant) -> void:
	var m := String(meta)
	if m.begins_with("note:edit:"):
		edit_note(int(m.trim_prefix("note:edit:")))
		return
	if m.begins_with("note:from:"):
		for e: Dictionary in DialogueState.journal():
			if str(e.get("id", "")) == m.trim_prefix("note:from:"):
				edit_note(0, "%s%s" % [(String(e["speaker"]) + ": ") if String(e.get("speaker", "")) != "" else "", e["text"]])
		return
	if m.begins_with("quest:"):
		show_quest(m.trim_prefix("quest:"))
		return
	show_topic(m.uri_decode())


# ---------------------------------------------------------------- the left list

func _rebuild_filter() -> void:
	_filter_opt.clear()
	_filter_values = [""]
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	match _tabs.current_tab:
		TAB_QUESTS:
			_filter_opt.add_item("Every guild")
			var quests := QuestLog.all(world)
			for f in Factions.IDS:
				if quests.any(func(q: Dictionary) -> bool: return q["guild"] == f):
					_filter_values.append(f)
					_filter_opt.add_item(Factions.display_name(f))
		TAB_TOPICS, TAB_PLACES, TAB_PEOPLE:
			_filter_opt.add_item("Every town")
			var towns := {}
			for e: Dictionary in DialogueState.journal():
				if String(e.get("place", "")) != "":
					towns[e["place"]] = true
			var names := towns.keys()
			names.sort()
			for t in names:
				_filter_values.append(t)
				_filter_opt.add_item(t)
		TAB_ALL:
			_filter_opt.add_item("Every type")
			for t in DialogueState.ENTRY_TYPES:
				if t != "Note":
					_filter_values.append(t)
					_filter_opt.add_item(t)
		_:
			_filter_opt.add_item("Every note")
			for i in range(1, NOTE_COLORS.size()):
				_filter_values.append(str(i))
				_filter_opt.add_item(NOTE_COLORS[i])
	_filter_opt.selected = 0


func _sorted(entries: Array) -> Array:
	var out := entries.duplicate()
	match _sort_opt.selected:
		0:
			out.reverse()
		2:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("topic", a.get("title", ""))).to_lower() < String(b.get("topic", b.get("title", ""))).to_lower())
	return out


func _add_group(label: String) -> TreeItem:
	var it := _list.create_item(_list.get_root())
	it.set_text(0, label)
	it.set_selectable(0, false)
	it.set_custom_color(0, GOLD)
	return it


func _add_row(parent: TreeItem, label: String, kind: String, value: String, unread: bool = false) -> TreeItem:
	var it := _list.create_item(parent)
	it.set_text(0, ("● " if unread else "") + label)
	it.set_metadata(0, [kind, value])
	if kind == _filter_kind and value == _filter_value:
		it.select(0)
	return it


func _wanted() -> String:
	return _filter_values[_filter_opt.selected] if _filter_opt.selected >= 0 and _filter_opt.selected < _filter_values.size() else ""


func _fill_list(world: WorldManager, entries: Array) -> void:
	_list.set_block_signals(true)
	_list.clear()
	_list.create_item()
	var tab := _tabs.current_tab
	var want := _wanted()
	var tab_marks := DialogueState.bookmarks().filter(func(k: String) -> bool:
		return (tab == TAB_QUESTS and k.begins_with("quest:")) or (tab != TAB_QUESTS and tab != TAB_NOTES and k.begins_with("topic:")))
	if not tab_marks.is_empty():
		var g := _add_group("Bookmarks")
		for k: String in tab_marks:
			var value := k.substr(k.find(":") + 1)
			var label := value if k.begins_with("topic:") else String(QuestLog.find(world, value).get("name", value))
			_add_row(g, "★ " + label, k.get_slice(":", 0), value)
	match tab:
		TAB_QUESTS:
			var quests := QuestLog.all(world)
			if want != "":
				quests = quests.filter(func(q: Dictionary) -> bool: return q["guild"] == want)
			if _sort_opt.selected == 2:
				quests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
			elif _sort_opt.selected == 0:
				quests.reverse()
			for status in ["active", "completed", "failed", "abandoned"]:
				var these := quests.filter(func(q: Dictionary) -> bool: return q["status"] == status)
				if these.is_empty():
					continue
				var g := _add_group("%s  (%d)" % [String(status).capitalize(), these.size()])
				g.collapsed = status != "active" and _filter_value == ""
				for q: Dictionary in these:
					var unread := entries.any(func(e: Dictionary) -> bool: return e.get("quest_id", "") == q["id"] and not bool(e.get("read", true)))
					var pin := "  (tracked)" if QuestTracker.is_tracked(String(q["id"])) else ""
					_add_row(g, String(q["name"]) + pin, "quest", String(q["id"]), unread)
		TAB_NOTES:
			var g := _add_group("Your notes")
			_add_row(g, "+ New note", "new_note", "")
			var notes := DialogueState.notes().duplicate()
			if want != "":
				notes = notes.filter(func(n: Dictionary) -> bool: return str(int(n.get("color", 0))) == want)
			notes = _sorted(notes)
			notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.get("pinned", false)) and not bool(b.get("pinned", false)))
			if not notes.is_empty():
				_add_row(g, "All notes  (%d)" % notes.size(), "notes", "")
			for n: Dictionary in notes:
				_add_row(g, ("(pinned) " if bool(n.get("pinned", false)) else "") + String(n["title"]), "note", str(n["id"]))
		TAB_ALL:
			var g := _add_group("Everything")
			_add_row(g, "All entries  (%d)" % entries.size(), "all", "")
			for t in DialogueState.ENTRY_TYPES:
				var n := entries.filter(func(e: Dictionary) -> bool: return type_of(e) == t).size()
				if n > 0:
					_add_row(g, "%s  (%d)" % [t, n], "type", t)
		_:
			var types: Array = {TAB_TOPICS: ["Rumor", "Knowledge"], TAB_PLACES: ["Place"], TAB_PEOPLE: ["Person"]}[tab]
			var groups := {}
			for e: Dictionary in _sorted(entries):
				if not types.has(type_of(e)):
					continue
				if want != "" and String(e.get("place", "")) != want:
					continue
				var key := String(e.get("topic", "")) if String(e.get("topic", "")) != "" else String(e["text"]).left(40)
				var group := String(e.get("place", "")) if tab != TAB_TOPICS else type_of(e)
				if group == "":
					group = "Elsewhere"
				if not groups.has(group):
					groups[group] = {}
				groups[group][key] = bool(groups[group].get(key, false)) or not bool(e.get("read", true))
			var names := groups.keys()
			names.sort()
			for gname in names:
				var g := _add_group(String(gname))
				for key in groups[gname]:
					_add_row(g, key, "topic", key, groups[gname][key])
			if groups.is_empty():
				_add_group("   (nothing yet)")
	_list.set_block_signals(false)


func _on_list_selected() -> void:
	var it := _list.get_selected()
	if it == null or it.get_metadata(0) == null:
		return
	var row: Array = it.get_metadata(0)
	if is_editing():
		save_note()
	if row[0] == "new_note":
		edit_note(0)
		return
	_filter_kind = row[0]
	_filter_value = row[1]
	_confirm_abandon = false
	_refresh.call_deferred()


# ---------------------------------------------------------------- the page

func _refresh() -> void:
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var entries := DialogueState.journal()
	_fill_list(world, entries)
	var tab := _tabs.current_tab
	_text.clear()
	var q_text := _search.text.strip_edges()
	var notes := DialogueState.notes()
	_actions.visible = _filter_kind == "quest" or _filter_kind == "topic"
	_track.visible = _filter_kind == "quest"
	_abandon.visible = _filter_kind == "quest"
	if tab == TAB_NOTES or _filter_kind == "notes" or _filter_kind == "note":
		var list := notes.filter(func(n: Dictionary) -> bool:
			return (_filter_kind != "note" or str(n["id"]) == _filter_value) and _note_matches(n, q_text))
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.get("pinned", false)) and not bool(b.get("pinned", false)))
		_count.text = "%d of %d notes" % [list.size(), notes.size()]
		_show_notes(list, q_text)
		return
	var shown := filter(entries, _search.text, _filter_kind, _filter_value)
	_count.text = "%d of %d entries" % [shown.size(), entries.size()]
	if _filter_kind == "topic" or _filter_kind == "quest":
		_bookmark.text = "Unbookmark" if DialogueState.bookmarks().has("%s:%s" % [_filter_kind, _filter_value]) else "Bookmark"
	if _filter_kind == "quest":
		_quest_page(world, _filter_value)
	elif _filter_kind == "all" and q_text == "":
		var active := QuestLog.all(world).filter(func(q: Dictionary) -> bool: return q["status"] == "active")
		if not active.is_empty():
			_text.append_text("[b]Active quests[/b]\n")
			for q: Dictionary in active:
				_text.append_text("[url=quest:%s][color=#ffd95a]%s[/color][/url]: %s\n" % [q["id"], DialogueUI._esc(String(q["name"])), DialogueUI._esc(String(q["next"]))])
			_text.append_text("\n")
	if q_text != "":
		for n: Dictionary in notes:
			if _note_matches(n, q_text):
				_show_note(n, q_text)  # a search looks through your notes too
	if entries.is_empty():
		_text.append_text("[i]Nothing written yet. Talk to people: what matters is written down here.[/i]")
		return
	if shown.is_empty():
		_text.append_text("[i]Nothing matches.[/i]")
		return
	var ix := DialogueEngine.index(world)
	for e: Dictionary in _sorted(shown):
		var who := String(e.get("speaker", ""))
		var heard: Array = e.get("heard", [])
		if heard.size() > 1:
			who += " (and %d other%s)" % [heard.size() - 1, "" if heard.size() == 2 else "s"]
		var head := "%s, %s" % [WorldClock.short_date_of(int(e.get("day", 1))), e.get("time", "")]
		if who != "":
			head += "  ·  " + who
		if String(e.get("place", "")) != "":
			head += ", " + String(e["place"])
		if String(e.get("topic", "")) != "":
			head += "  ·  on " + String(e["topic"])
		var new := "  [color=#ffb347]NEW[/color]" if not bool(e.get("read", true)) else ""
		_text.append_text("[color=#b8a47a]%s[/color]%s   [url=note:from:%s][color=#7f9fbf]Add to notes[/color][/url]\n" % [_mark(head, q_text), new, str(e.get("id", ""))])
		if String(e.get("quest_name", "")) != "" and _filter_kind != "quest":
			_text.append_text("[color=#ffd95a]Quest: [url=quest:%s]%s[/url][/color]\n" % [e["quest_id"], _mark(String(e["quest_name"]), q_text)])
		var body := String(e.get("text", ""))
		_text.append_text((_mark(body, q_text) if q_text != "" else DialogueUI.linkify(body, ix)) + "\n\n")
	# what was looked at is read now
	for e: Dictionary in shown:
		if not bool(e.get("read", true)):
			DialogueState.mark_read(int(e.get("id", -1)))


func _quest_page(world: WorldManager, id: String) -> void:
	var q := QuestLog.find(world, id)
	if q.is_empty():
		return
	_track.text = "Stop tracking" if QuestTracker.is_tracked(id) else "Track"
	_track.disabled = q["status"] != "active"
	_abandon.disabled = q["status"] != "active" or q["source"] == "story"
	_abandon.text = "Really abandon?" if _confirm_abandon else "Abandon"
	var guild := Factions.display_name(String(q["guild"])) if String(q["guild"]) != "" else ""
	_text.append_text("[color=#ffd95a][b][font_size=22]%s[/font_size][/b][/color]\n" % DialogueUI._esc(String(q["name"])))
	_text.append_text("[color=#b8a47a]%s%s  ·  %s[/color]\n\n" % [DialogueUI._esc(String(q["giver"])), ("  ·  " + guild) if guild != "" else "", String(q["status"]).capitalize()])
	if String(q["description"]) != "":
		_text.append_text("%s\n\n" % DialogueUI._esc(String(q["description"])))
	if not (q["objectives"] as Array).is_empty():
		_text.append_text("[b]Objectives[/b]\n")
		for o: Dictionary in q["objectives"]:
			var tick := "[color=#8fd18f][lb]x][/color]" if o["done"] else "[lb] ]"
			_text.append_text("%s %s\n" % [tick,("[color=#9a9a9a]%s[/color]" % DialogueUI._esc(String(o["text"]))) if o["done"] else DialogueUI._esc(String(o["text"]))])
		_text.append_text("\n")
	if q["status"] == "active" and String(q["next"]) != "":
		_text.append_text("[b]Next:[/b] %s\n" % DialogueUI._esc(String(q["next"])))
	if String(q["rewards"]) != "":
		_text.append_text("[b]Reward:[/b] %s\n" % DialogueUI._esc(String(q["rewards"])))
	if String(q["why"]) != "":
		_text.append_text("[color=#e07a6f]%s[/color]\n" % DialogueUI._esc(String(q["why"])))
	var linked := DialogueState.notes_linked("quest:" + id)
	if not linked.is_empty():
		_text.append_text("\n[b]Your notes[/b]\n")
		for n: Dictionary in linked:
			_show_note(n, "")
	_text.append_text("\n[b]What was said[/b]\n")


func _apply_text_size() -> void:
	var size := float(GameSettings.get_value("text_size"))
	_text.add_theme_font_size_override("normal_font_size", roundi(17 * size))
	_text.add_theme_font_size_override("bold_font_size", roundi(17 * size))
	_note_body.add_theme_font_size_override("font_size", roundi(17 * size))
	_text.add_theme_color_override("default_color", Color(1, 1, 1) if bool(GameSettings.get_value("high_contrast")) else Color(0.92, 0.9, 0.85))


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
	panel.custom_minimum_size = Vector2(1040, 580)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vbox.add_child(top)
	top.add_child(UITheme.heading("Journal"))
	_tabs = TabBar.new()
	for t in TABS:
		_tabs.add_tab(tr(t))  # text keys: ready for translation
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tooltip_text = "Ctrl+Left / Ctrl+Right switch tabs"
	_tabs.tab_changed.connect(func(_i: int) -> void:
		_filter_kind = "notes" if _tabs.current_tab == TAB_NOTES else "all"
		_filter_value = ""
		_rebuild_filter()
		_refresh())
	top.add_child(_tabs)
	_count = Label.new()
	_count.add_theme_color_override("font_color", GOLD)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_count)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	vbox.add_child(bar)
	_search = LineEdit.new()
	_search.placeholder_text = "Search everything, your notes too..."
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _refresh())
	bar.add_child(_search)
	_filter_opt = OptionButton.new()
	_filter_opt.focus_mode = Control.FOCUS_NONE
	_filter_opt.tooltip_text = "Show only one guild, town, type or note colour"
	_filter_opt.item_selected.connect(func(_i: int) -> void: _refresh())
	bar.add_child(_filter_opt)
	_sort_opt = OptionButton.new()
	_sort_opt.focus_mode = Control.FOCUS_NONE
	_sort_opt.tooltip_text = "The order of the list and the entries"
	for s in SORTS:
		_sort_opt.add_item(s)
	_sort_opt.item_selected.connect(func(_i: int) -> void: _refresh())
	bar.add_child(_sort_opt)
	var read_all := Button.new()
	read_all.text = "Mark all read"
	read_all.tooltip_text = "Clear every NEW mark"
	read_all.focus_mode = Control.FOCUS_NONE
	read_all.pressed.connect(func() -> void:
		DialogueState.mark_read()
		_refresh())
	bar.add_child(read_all)
	var export := Button.new()
	export.text = "Export notes"
	export.tooltip_text = "Writes all your notes to a text file"
	export.focus_mode = Control.FOCUS_NONE
	export.pressed.connect(func() -> void:
		var path := DialogueState.export_notes()
		_status.text = "Notes written to %s" % path if path != "" else "Couldn't write the notes file.")
	bar.add_child(export)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)
	_list = Tree.new()
	_list.hide_root = true
	_list.custom_minimum_size = Vector2(280, 0)
	_list.item_selected.connect(_on_list_selected)
	split.add_child(_list)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(page)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	page.add_child(_actions)
	_track = Button.new()
	_track.focus_mode = Control.FOCUS_NONE
	_track.tooltip_text = "Show it on the compass and on screen"
	_track.pressed.connect(func() -> void:
		QuestTracker.toggle(_filter_value)
		_refresh())
	_actions.add_child(_track)
	_abandon = Button.new()
	_abandon.text = "Abandon"
	_abandon.focus_mode = Control.FOCUS_NONE
	_abandon.tooltip_text = "Give the quest up (asks first). The giver will think less of you."
	_abandon.pressed.connect(func() -> void:
		if not _confirm_abandon:
			_confirm_abandon = true
		else:
			_confirm_abandon = false
			QuestLog.abandon(get_tree().get_first_node_in_group("world_manager") as WorldManager, _filter_value)
		_refresh())
	_actions.add_child(_abandon)
	_bookmark = Button.new()
	_bookmark.text = "Bookmark"
	_bookmark.focus_mode = Control.FOCUS_NONE
	_bookmark.tooltip_text = "Keep it at the top of the list"
	_bookmark.pressed.connect(func() -> void:
		DialogueState.toggle_bookmark("%s:%s" % [_filter_kind, _filter_value])
		_refresh())
	_actions.add_child(_bookmark)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.meta_clicked.connect(_on_meta)
	page.add_child(_text)

	# the note editor, in the same place as the page
	_editor = VBoxContainer.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 8)
	_editor.visible = false
	page.add_child(_editor)
	_note_title = LineEdit.new()
	_note_title.placeholder_text = "Title (optional)"
	_note_title.max_length = 60
	_editor.add_child(_note_title)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	_editor.add_child(opts)
	_note_pin = CheckBox.new()
	_note_pin.text = "Pin to the top"
	opts.add_child(_note_pin)
	_note_color = OptionButton.new()
	for c in NOTE_COLORS:
		_note_color.add_item("Colour: " + c)
	opts.add_child(_note_color)
	_note_link = OptionButton.new()
	_note_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_child(_note_link)
	_note_body = TextEdit.new()
	_note_body.placeholder_text = "Write your note here... (Ctrl+Z undoes, Ctrl+Enter saves)"
	_note_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_body.add_theme_font_size_override("font_size", 17)
	_note_body.text_changed.connect(func() -> void:
		_confirm_discard = false
		if _note_body.text.length() > DialogueState.NOTE_MAX:
			_note_body.text = _note_body.text.left(DialogueState.NOTE_MAX)
			_note_body.set_caret_line(_note_body.get_line_count() - 1)
			_note_body.set_caret_column(_note_body.get_line(_note_body.get_line_count() - 1).length())
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

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	vbox.add_child(_status)
	var hint := Label.new()
	hint.text = "Click a highlighted word to see everything about it    Shift+J: a new note from anywhere    [J] or [Esc] Close"
	hint.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(hint)
