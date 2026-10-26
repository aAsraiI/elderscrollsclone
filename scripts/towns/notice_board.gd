class_name NoticeBoard
extends StaticBody3D
## The notice board in every inn: E shows a few jobs posted by the townsfolk (gathering, rescues,
## escorts, investigations, farms to protect, roads to clear, deliveries). The offers change every
## few days (Radiant.BOARD_DAYS); an offer not taken before then is gone. Take one, do it, and
## E again claims the pay. One job from a board at a time. The jobs are QuestManager jobs: they
## show in the journal, on the map and the compass.

const INTERACTABLE_LAYER := 4

var town_id := ""
var _menu: CanvasLayer


static func make(parent: Node3D, at: Vector3, yaw: float, town: String) -> NoticeBoard:
	var b := NoticeBoard.new()
	b.name = "NoticeBoard"
	b.town_id = town
	parent.add_child(b)
	b.position = at
	b.rotation.y = yaw
	return b


func board_id() -> String:
	return "notice:" + town_id


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER | 1
	var wood := POIBuilder.get_material(Color(0.32, 0.22, 0.13))
	var paper := POIBuilder.get_material(Color(0.88, 0.84, 0.72))
	_box(Vector3(1.2, 0.9, 0.06), Vector3(0, 1.4, 0), wood)
	for i in 3:
		_box(Vector3(0.28, 0.34, 0.01), Vector3(-0.38 + i * 0.38, 1.42 + (0.08 if i % 2 == 0 else -0.06), 0.04), paper)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.0, 0.2)
	shape.shape = box
	shape.position = Vector3(0, 1.4, 0)
	add_child(shape)


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	add_child(mi)


func _world() -> WorldManager:
	return get_tree().get_first_node_in_group("world_manager") as WorldManager


func get_prompt() -> String:
	var wm := _world()
	if wm == null or wm.quests == null:
		return "Read the Notice Board"
	var q := wm.quests.bounty_of(board_id())
	if not q.is_empty():
		return "Claim your pay: %s" % q["name"] if wm.quests.is_ready(q) else "Notice Board (%s)" % q["name"]
	return "Read the Notice Board"


## The offers posted now
func offers() -> Array:
	var wm := _world()
	var town := wm.get_poi(town_id) if wm != null else null
	if town == null or wm.clock == null:
		return []
	return Radiant.board_offers(wm.quests, town, wm.clock.day)


## Takes an offer (by its place in offers()). Returns the job, or {} if it can't be taken now.
func take(index: int) -> Dictionary:
	var wm := _world()
	if not wm.quests.bounty_of(board_id()).is_empty():
		return {}
	var list := offers()
	if index < 0 or index >= list.size():
		return {}
	return wm.quests.take_offer(list[index], board_id(), wm.get_poi(town_id))


## Claims a finished job's pay. Returns the gold (0 if nothing was ready).
func claim() -> int:
	var wm := _world()
	var q := wm.quests.bounty_of(board_id())
	if q.is_empty() or not wm.quests.is_ready(q):
		return 0
	return wm.quests.complete(q)


func interact(_actor: Inventory) -> void:
	var gold := claim()
	if gold > 0:
		Locks.toast(get_tree(), "The townsfolk leave you %d gold." % gold)
		return
	_open_menu()


func _open_menu() -> void:
	var wm := _world()
	_menu = CanvasLayer.new()
	_menu.layer = 12
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UITheme.heading("Notice Board"))
	var current := wm.quests.bounty_of(board_id())
	if not current.is_empty():
		v.add_child(UITheme.hint("You took: %s. %s" % [current["name"], current["objective"]]))
	else:
		var list := offers()
		if list.is_empty():
			v.add_child(UITheme.hint("Nothing posted right now."))
		for i in list.size():
			var q: Dictionary = list[i]
			var b := Button.new()
			b.text = "%s   (%d gold)" % [q["name"], int(q.get("template_reward", 100))]
			b.tooltip_text = String(q["objective"])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func() -> void:
				var job := take(i)
				_close()
				if not job.is_empty():
					Locks.toast(get_tree(), "Taken: %s" % job["name"]))
			v.add_child(b)
			var l := Label.new()
			l.text = String(q["objective"])
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.modulate = Color(1, 1, 1, 0.7)
			v.add_child(l)
		v.add_child(UITheme.hint("New notices every %d days." % Radiant.BOARD_DAYS))
	var close := Button.new()
	close.text = "Leave it"
	close.pressed.connect(_close)
	v.add_child(close)
	get_tree().root.add_child(_menu)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
