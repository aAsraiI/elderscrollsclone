class_name DungeonMap
extends CanvasLayer
## The map of the dungeon you are in (M inside a stitched dungeon; M or Esc closes it). Only the
## rooms you have walked into are drawn (InteriorNav.explored), seen from above: your floor in
## parchment, floors above and below faint, the way out, the place a quest wants you and you
## (the yellow arrow). The game is paused while it is open.

const PAPER := Color(0.82, 0.74, 0.58)
const INK := Color(0.22, 0.16, 0.10)

var nav: InteriorNav
var _view: Control
var _was_paused := false
var _was_mouse := Input.MOUSE_MODE_CAPTURED


static func open_for(tree: SceneTree, p_nav: InteriorNav) -> DungeonMap:
	var m := DungeonMap.new()
	m.nav = p_nav
	m.layer = 60
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(m)
	return m


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_map)
	add_child(_view)
	_was_paused = get_tree().paused
	_was_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not _was_paused:
		get_tree().paused = false
	Input.mouse_mode = _was_mouse if _was_mouse != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED
	queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(WorldDebugMap.ACTION):
		close()
		get_viewport().set_input_as_handled()


## The outline of room i from above (in the dungeon's space), and its floor
func room_outline(i: int) -> PackedVector2Array:
	var p = nav.plan.placed[i]
	var a: AABB = p.entry.aabb
	var out := PackedVector2Array()
	for c in [Vector3(a.position.x, 0, a.position.z), Vector3(a.end.x, 0, a.position.z), Vector3(a.end.x, 0, a.end.z), Vector3(a.position.x, 0, a.end.z)]:
		var w: Vector3 = p.xform * c
		out.append(Vector2(w.x, w.z))
	return out


func _draw_map() -> void:
	if nav == null or not is_instance_valid(nav):
		return
	var size := _view.size
	var panel := Rect2(size * 0.08, size * 0.84)
	_view.draw_rect(panel, PAPER)
	_view.draw_rect(panel, INK, false, 3.0)
	var font := ThemeDB.fallback_font
	var title := Discovery._name_of(nav.dungeon_id)
	_view.draw_string(font, panel.position + Vector2(18, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	var seen: Array = nav.explored()
	var root := nav.get_parent() as Node3D
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var here := root.to_local(p.global_position) if p != null else Vector3.ZERO
	var my_floor := floori((here.y + 0.5) / RoomModule.LEVEL)
	# fit the explored rooms into the panel
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in seen:
		for v in room_outline(int(i)):
			lo = lo.min(v)
			hi = hi.max(v)
	if seen.is_empty():
		lo = Vector2(here.x, here.z) - Vector2(10, 10)
		hi = Vector2(here.x, here.z) + Vector2(10, 10)
	var inner := panel.grow(-50)
	var span := (hi - lo).max(Vector2(8, 8))
	var scale := minf(inner.size.x / span.x, inner.size.y / span.y)
	var origin := inner.get_center() - (lo + hi) * 0.5 * scale
	var to_map := func(v: Vector2) -> Vector2: return origin + v * scale
	for i in seen:
		var room_floor := floori((nav.plan.placed[int(i)].xform.origin.y + 0.5) / RoomModule.LEVEL)
		var pts := PackedVector2Array()
		for v in room_outline(int(i)):
			pts.append(to_map.call(v))
		var on := room_floor == my_floor
		_view.draw_colored_polygon(pts, Color(0.93, 0.87, 0.72) if on else Color(0.86, 0.79, 0.64, 0.6))
		pts.append(pts[0])
		_view.draw_polyline(pts, INK if on else Color(INK, 0.35), 2.0 if on else 1.0)
	# the way out (the entrance room), and where a quest wants you (the boss's room)
	var exit_room := 0
	if seen.has(exit_room):
		var c: Vector3 = nav.plan.placed[exit_room].xform.origin
		_view.draw_string(font, to_map.call(Vector2(c.x, c.z)) + Vector2(-14, 5), "Exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	var boss := nav.boss_room()
	if boss >= 0 and _quest_here():
		var b: Vector3 = nav.plan.placed[boss].xform.origin
		var at: Vector2 = to_map.call(Vector2(b.x, b.z))
		_view.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -9), at + Vector2(8, 0), at + Vector2(0, 9), at + Vector2(-8, 0)]), Color(1.0, 0.8, 0.2))
	# you
	if p != null:
		var at: Vector2 = to_map.call(Vector2(here.x, here.z))
		var f := -p.global_transform.basis.z
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		_view.draw_colored_polygon(PackedVector2Array([at + dir * 12, at - dir * 7 + side * 7, at - dir * 7 - side * 7]), Color(1.0, 0.85, 0.2))
	var floors := "Floor %d" % (my_floor + 1)
	_view.draw_string(font, panel.position + Vector2(18, panel.size.y - 16), "%s   ·   %d rooms explored   ·   M to close" % [floors, seen.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)


# Does an active quest point at this dungeon?
func _quest_here() -> bool:
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var poi := world.get_poi(nav.dungeon_id) if world != null else null
	if poi == null:
		return false
	for t in QuestManager.compass_targets():
		var pos: Vector2 = t["pos"]
		if pos.distance_to(Vector2(poi.position.x, poi.position.z)) < 60.0:
			return true
	return false
