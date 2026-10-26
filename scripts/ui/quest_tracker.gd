class_name QuestTracker
extends CanvasLayer
## The tracked quests (up to MAX, picked with Track in the journal): the compass then points at
## them, and, when Settings > Interface > Tracked quests on screen is on, a few quiet lines in the
## top right say each one's next step with its counts ("Kill the wolves 1/3"). A finished
## objective flashes green with a tick before the line moves on. Created by WorldManager.
## Saved in WorldState "tracked_quests" (old saves' single "tracked_quest" carries over).

const MAX := 3
const KEY := "tracked_quests"
const FLASH := 1.4

var _box: VBoxContainer
var _timer := 0.0
var _last := {}    # quest id -> its last next-step text
var _flash := {}   # quest id -> seconds of green left


## The tracked quest ids, oldest first
static func tracked() -> Array:
	var rec := WorldState.get_record(KEY)
	if rec.has("list"):
		return rec["list"]
	var old := String(WorldState.get_record("tracked_quest").get("id", ""))
	return [old] if old != "" else []


static func is_tracked(id: String) -> bool:
	return tracked().has(id)


## Tracks a quest, or stops tracking it. Past MAX, the oldest one drops off.
static func toggle(id: String) -> void:
	var list := tracked().duplicate()
	if list.has(id):
		list.erase(id)
	elif id != "":
		list.append(id)
		while list.size() > MAX:
			list.pop_front()
	WorldState.set_record(KEY, {"list": list})


func _ready() -> void:
	layer = 5
	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_box.position = Vector2(-380, 70)
	_box.custom_minimum_size = Vector2(360, 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func _process(delta: float) -> void:
	for id in _flash.keys():
		_flash[id] = float(_flash[id]) - delta
		if _flash[id] <= 0.0:
			_flash.erase(id)
	_timer -= delta
	if _timer > 0.0 and _flash.is_empty():
		return
	_timer = 0.5
	var world := get_parent() as WorldManager
	var on := bool(GameSettings.get_value("quest_tracker"))
	_box.visible = on and not get_tree().paused
	if not on or world == null:
		return
	for c in _box.get_children():
		c.queue_free()
	var size := float(GameSettings.get_value("text_size"))
	for id in tracked():
		var q := QuestLog.find(world, String(id))
		if q.is_empty() or q["status"] != "active":
			continue
		var next := String(q["next"])
		if _last.has(id) and _last[id] != next:
			_flash[id] = FLASH  # the objective moved on: a tick and a flash
		_last[id] = next
		var title := Label.new()
		title.text = String(q["name"])
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.add_theme_font_size_override("font_size", roundi(15 * size))
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_outline(title)
		_box.add_child(title)
		var line := Label.new()
		var flashing := _flash.has(id)
		line.text = ("✓ " if flashing else "") + next
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_theme_font_size_override("font_size", roundi(14 * size))
		var good := Color(0.45, 0.7, 1.0) if bool(GameSettings.get_value("colorblind_markers")) else Color(0.55, 0.9, 0.55)
		line.add_theme_color_override("font_color", good if flashing else Color(0.92, 0.9, 0.85))
		_outline(line)
		_box.add_child(line)


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
