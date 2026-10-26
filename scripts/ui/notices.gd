class_name Notices
extends CanvasLayer
## Quest notices in the top middle of the screen: Quest Started, Objective Updated, Ready to Turn
## In, Quest Completed, Quest Failed, Journal Updated. They wait in a queue, so two never overlap
## and none is lost; each shows for SHOW_TIME seconds. Settings > Interface > Quest notices turns
## them off. Each kind calls a sound hook (sound_for): silent until real audio exists.
## Made on first use, nothing to add by hand.

signal shown(title: String, text: String)

const SHOW_TIME := 2.6
const FADE := 0.3
const MAX_QUEUE := 12

var _queue: Array = []
var _left := 0.0
var _panel: PanelContainer
var _title: Label
var _text: Label


static func of(tree: SceneTree) -> Notices:
	if tree == null or tree.root == null:
		return null
	var n := tree.get_first_node_in_group("notices") as Notices
	if n == null:
		n = Notices.new()
		n.name = "Notices"
		tree.root.add_child.call_deferred(n)
		n.add_to_group("notices")
	return n


## Shows a quest notice (queued). is_error: in red (failed, abandoned).
static func quest(tree: SceneTree, title: String, text: String, is_error: bool = false) -> void:
	var n := of(tree)
	if n != null:
		n.push(title, text, is_error)


func push(title: String, text: String, is_error: bool = false) -> void:
	print("[Notice] %s: %s" % [title, text])
	sound_for(title)
	if not bool(GameSettings.get_value("quest_popups")):
		return
	if not _queue.is_empty() and _queue[-1]["title"] == title and _queue[-1]["text"] == text:
		return  # the same notice twice in a row
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append({"title": title, "text": text, "error": is_error})


## What is waiting (the tests look)
func pending() -> Array:
	return _queue


## The sound hook for a kind of notice: nothing plays until audio exists
func sound_for(title: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sound_fx") if is_inside_tree() else null
	if sfx != null and sfx.has_method("play_ui"):
		sfx.call("play_ui", title.to_snake_case())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.position.y = 70
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	v.add_child(_title)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_text)


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		_panel.modulate.a = clampf(minf(_left, SHOW_TIME - _left) / FADE, 0.0, 1.0)
		if _left <= 0.0:
			_panel.visible = false
		return
	if _queue.is_empty():
		return
	var n: Dictionary = _queue.pop_front()
	var size := float(GameSettings.get_value("text_size"))
	_title.text = tr(String(n["title"])).to_upper()  # text keys: ready for translation
	_title.add_theme_font_size_override("font_size", roundi(15 * size))
	_text.text = String(n["text"])
	_text.add_theme_font_size_override("font_size", roundi(19 * size))
	var bad := Color(0.95, 0.55, 0.2) if bool(GameSettings.get_value("colorblind_markers")) else Color(0.95, 0.45, 0.4)
	_text.add_theme_color_override("font_color", bad if n["error"] else Color(0.95, 0.93, 0.88))
	_panel.visible = true
	_panel.reset_size()
	_panel.position.x = (get_viewport().get_visible_rect().size.x - _panel.size.x) * 0.5
	_left = SHOW_TIME
	shown.emit(n["title"], n["text"])
