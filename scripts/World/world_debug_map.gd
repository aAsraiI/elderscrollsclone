class_name WorldDebugMap
extends CanvasLayer
## The world map. Press M to open and close it (Esc closes it too). Created by WorldManager.
## The game is paused while it is open.
##
##   mouse wheel / + -      zoom in and out (toward the mouse); zoomed in, a sharper picture is drawn
##   drag / WASD / arrows   move around
##   C                      back to where you are
##   hover                  names of towns, places and quest targets
##   right click            (debug builds only) teleport there
## Shows the land (biome colors shaded by height), water, roads, towns, places, active quest
## targets (gold diamonds) and you (the yellow arrow).

signal teleported(position: Vector3)

const ACTION := "world_map_debug"
## Pixels of the whole-world picture along its longer side
const BASE_RESOLUTION := 768
## Pixels of the sharper picture of the zoomed-in area
const DETAIL_RESOLUTION := 640
const MAX_ZOOM := 16.0
const PAN_SPEED := 600.0  # screen pixels per second

## Right click teleports (debug builds only, e.g. playing from the editor)
@export var teleport_enabled := true


# The map picture and everything drawn on it
class MapView extends Control:
	var owner_map: WorldDebugMap

	func _draw() -> void:
		if owner_map != null:
			owner_map.draw_map(self)

	func _gui_input(event: InputEvent) -> void:
		if owner_map != null:
			owner_map.map_input(event)


var _manager: WorldManager
var _root: Control
var _view: MapView
var _title: Label
var _status: Label
var _tooltip: Label
var _open := false
var _was_paused := false
var _was_mouse := Input.MOUSE_MODE_CAPTURED

# The pictures: the whole world, and a sharper one of the area last zoomed into
var _base_tex: Texture2D
var _detail_tex: Texture2D
var _detail_rect := Rect2()
var _generation := 0
var _jobs: Array[Dictionary] = []  # pictures being drawn: {"id" (group task), "rows", "size", "done"}

var _base_pending := false
var _detail_wanted_at := -1.0
var _detail_pending_rect := Rect2()

# View: the world point at the middle of the view, and the zoom (1 = the whole world fits)
var _center := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _drag_moved := 0.0
var _mouse := Vector2.ZERO
var _time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	add_to_group("world_map")
	_manager = get_parent() as WorldManager
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_M
		InputMap.action_add_event(ACTION, ev)
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or _manager == null or _manager.map == null:
		return
	_open = true
	_was_paused = get_tree().paused
	_was_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	center_on_player()
	if _base_tex == null and not _base_pending:
		_start_base()
	_request_detail()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_dragging = false
	if not _was_paused:
		get_tree().paused = false
	Input.mouse_mode = _was_mouse if _was_mouse != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED


## The world changed (new seed): forget the pictures
func invalidate() -> void:
	_generation += 1
	_base_tex = null
	_detail_tex = null
	_base_pending = false
	if _open:
		_start_base()


func center_on_player() -> void:
	var p := _manager.player if _manager != null else null
	if p != null and is_instance_valid(p):
		_center = Vector2(p.global_position.x, p.global_position.z)
		if _zoom < 3.0:
			_zoom = 3.0
	_clamp_view()
	_request_detail()


## Teleports the player to a world spot (x, z) on solid ground. Debug feature.
func teleport_to(spot: Vector2) -> void:
	var p := _manager.player
	if p == null or not is_instance_valid(p):
		return
	var dm := _manager.dungeons
	if dm != null and dm.is_inside():
		return  # leave the dungeon or building first
	var pos := Vector3(spot.x, 0.0, spot.y)
	_manager.ensure_area_loaded(pos, 1)
	pos.y = _manager.get_height_at(spot.x, spot.y) + 1.5
	p.global_position = pos
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	teleported.emit(pos)
	close()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _manager == null or not event.is_action_pressed(ACTION) or event.is_echo():
		return
	if _open:
		close()
	elif not get_tree().paused:
		open()
	else:
		return
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_C:
				center_on_player()
			KEY_EQUAL, KEY_KP_ADD:
				zoom_at(_view.size / 2.0, 1.5)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_at(_view.size / 2.0, 1.0 / 1.5)


func map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(mb.position, 1.25)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(mb.position, 0.8)
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				_drag_moved = 0.0
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and can_teleport():
					teleport_to(screen_to_world(mb.position))
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _dragging:
			_center -= mm.relative / _scale()
			_drag_moved += mm.relative.length()
			_clamp_view()
			_request_detail()
		_view.queue_redraw()


func can_teleport() -> bool:
	return teleport_enabled and OS.is_debug_build()


## Zooms by `factor`, keeping the world point under `at` (view pixels) where it is
func zoom_at(at: Vector2, factor: float) -> void:
	var before := screen_to_world(at)
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	var after := screen_to_world(at)
	_center += before - after
	_clamp_view()
	_request_detail()


func _process(delta: float) -> void:
	_time += delta
	_poll_jobs()
	if not _open:
		return
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		_center += pan * PAN_SPEED * delta / _scale()
		_clamp_view()
		_request_detail()
	if _detail_wanted_at >= 0.0 and _time >= _detail_wanted_at:
		_detail_wanted_at = -1.0
		_start_detail()
	_update_text()
	_view.queue_redraw()


# ---------------------------------------------------------------- view math

func _bounds() -> Rect2:
	return _manager.map.get_bounds()


# Screen pixels per world meter
func _scale() -> float:
	var b := _bounds()
	var fit := minf(_view.size.x / maxf(b.size.x, 1.0), _view.size.y / maxf(b.size.y, 1.0))
	return fit * _zoom


func world_to_screen(w: Vector2) -> Vector2:
	return _view.size / 2.0 + (w - _center) * _scale()


func screen_to_world(s: Vector2) -> Vector2:
	return _center + (s - _view.size / 2.0) / _scale()


func _visible_world_rect() -> Rect2:
	var a := screen_to_world(Vector2.ZERO)
	var c := screen_to_world(_view.size)
	return Rect2(a, c - a)


func _clamp_view() -> void:
	var b := _bounds()
	var half := _view.size / 2.0 / _scale()
	_center.x = clampf(_center.x, b.position.x + half.x, b.end.x - half.x) if half.x * 2.0 < b.size.x else b.get_center().x
	_center.y = clampf(_center.y, b.position.y + half.y, b.end.y - half.y) if half.y * 2.0 < b.size.y else b.get_center().y


# ---------------------------------------------------------------- pictures (worker threads)

func _start_base() -> void:
	_base_pending = true
	var gen := _generation
	var rect := _bounds()
	var res := maxi(BASE_RESOLUTION, _manager.settings.debug_map_resolution)
	_start_render(rect, res, func(img: Image) -> void:
		if gen != _generation:
			return
		_base_pending = false
		_base_tex = ImageTexture.create_from_image(img))


func _request_detail() -> void:
	if _zoom < 1.8:
		_detail_tex = null
		return
	_detail_wanted_at = _time + 0.25  # wait until the view stops moving


func _start_detail() -> void:
	var vis := _visible_world_rect().grow_individual(0, 0, 0, 0)
	var rect := vis.grow(maxf(vis.size.x, vis.size.y) * 0.15).intersection(_bounds())
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	if _detail_tex != null and _detail_rect.encloses(vis) and _detail_rect.size.x < vis.size.x * 1.6:
		return  # the sharp picture still covers the view
	_detail_pending_rect = rect
	var gen := _generation
	_start_render(rect, DETAIL_RESOLUTION, func(img: Image) -> void:
		if gen != _generation or _detail_pending_rect != rect:
			return
		_detail_tex = ImageTexture.create_from_image(img)
		_detail_rect = rect)


# A picture is drawn row by row on every CPU core at once; _process puts it together when done
func _start_render(rect: Rect2, resolution: int, done: Callable) -> void:
	var size := image_size(rect, resolution)
	var rows: Array = []
	rows.resize(size.y)
	var map := _manager.map
	var id := WorkerThreadPool.add_group_task(func(j: int) -> void:
		rows[j] = render_row(map, rect, size.x, size.y, j), size.y, -1, false, "world map")
	_jobs.append({"id": id, "rows": rows, "size": size, "done": done})


func _poll_jobs() -> void:
	for k in range(_jobs.size() - 1, -1, -1):
		var job: Dictionary = _jobs[k]
		if not WorkerThreadPool.is_group_task_completed(job["id"]):
			continue
		WorkerThreadPool.wait_for_group_task_completion(job["id"])  # finished; this cleans it up
		_jobs.remove_at(k)
		var size: Vector2i = job["size"]
		var data := PackedByteArray()
		for row: PackedByteArray in job["rows"]:
			data.append_array(row)
		(job["done"] as Callable).call(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, data))


func _exit_tree() -> void:
	for job in _jobs:
		WorkerThreadPool.wait_for_group_task_completion(job["id"])
	_jobs.clear()


## Pixel size of a picture of `rect` whose longer side is `resolution`
static func image_size(rect: Rect2, resolution: int) -> Vector2i:
	var aspect := rect.size.y / maxf(rect.size.x, 1.0)
	if aspect > 1.0:
		return Vector2i(maxi(int(round(resolution / aspect)), 8), resolution)
	return Vector2i(resolution, maxi(int(round(resolution * aspect)), 8))


## One row of a picture of part of the world, as RGB bytes (thread-safe)
static func render_row(map: WorldMap, rect: Rect2, w: int, h: int, j: int) -> PackedByteArray:
	var s := WorldMap.Sample.new()
	var out := PackedByteArray()
	out.resize(w * 3)
	var sea := map.settings.sea_level
	var z := rect.position.y + (float(j) + 0.5) / float(h) * rect.size.y
	var prev_h := INF
	for i in w:
		var x := rect.position.x + (float(i) + 0.5) / float(w) * rect.size.x
		map.sample(x, z, s)
		var c := s.map_color.lerp(Color(0.1, 0.1, 0.12), s.edge * 0.7)
		if map.settings.water_enabled and s.height < sea:
			c = Color(0.16, 0.34, 0.55).darkened(clampf((sea - s.height) / 25.0, 0.0, 0.5))
		else:
			# hill shading: light from the west
			var shade := clampf(0.5 + (s.height - (prev_h if prev_h != INF else s.height)) * 0.1, 0.25, 0.85)
			c = c.darkened(0.45 - shade * 0.5)
		prev_h = s.height
		out[i * 3] = clampi(roundi(c.r * 255.0), 0, 255)
		out[i * 3 + 1] = clampi(roundi(c.g * 255.0), 0, 255)
		out[i * 3 + 2] = clampi(roundi(c.b * 255.0), 0, 255)
	return out


# ---------------------------------------------------------------- drawing

func draw_map(canvas: Control) -> void:
	if _manager == null or _manager.map == null:
		return
	var b := _bounds()
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.06, 0.06, 0.07))
	var tl := world_to_screen(b.position)
	var br := world_to_screen(b.end)
	if _base_tex != null:
		canvas.draw_texture_rect(_base_tex, Rect2(tl, br - tl), false)
	if _detail_tex != null and _zoom >= 1.8:
		var dtl := world_to_screen(_detail_rect.position)
		var dbr := world_to_screen(_detail_rect.end)
		canvas.draw_texture_rect(_detail_tex, Rect2(dtl, dbr - dtl), false)
	var scale := _scale()
	var font := ThemeDB.fallback_font
	# roads
	var roads := _manager.map.roads
	if roads != null:
		for road in roads.get_roads():
			var line := PackedVector2Array()
			for p: Vector3 in road["points"]:
				line.append(world_to_screen(Vector2(p.x, p.z)))
			canvas.draw_polyline(line, Color(0.28, 0.18, 0.09, 0.95), clampf(5.0 * scale, 1.5, 6.0))
	# places
	for poi in _manager.pois:
		if poi.poi is TownData:
			continue
		var dot := world_to_screen(Vector2(poi.position.x, poi.position.z))
		if not Rect2(Vector2.ZERO, canvas.size).grow(10).has_point(dot):
			continue
		var big := poi.poi is DungeonEntrancePOIData
		canvas.draw_circle(dot, 4.0 if big else 3.0, Color.BLACK)
		canvas.draw_circle(dot, 3.0 if big else 2.0, poi.poi.map_color)
	# towns
	for t in _manager.towns:
		var at := world_to_screen(Vector2(t.position.x, t.position.z))
		var data := t.poi as TownData
		var half := 4.0 + float(data.kind) * 1.5
		if _zoom >= 4.0 and t.town != null:
			# zoomed in: the buildings themselves
			for bp in t.town.buildings:
				var c := world_to_screen(Vector2(bp.world_pos.x, bp.world_pos.z))
				var hs := maxf(bp.size.x, bp.size.z) * 0.5 * scale
				canvas.draw_rect(Rect2(c - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color(0.55, 0.35, 0.25, 0.9))
		else:
			canvas.draw_rect(Rect2(at - Vector2(half + 1.0, half + 1.0), Vector2(half + 1.0, half + 1.0) * 2.0), Color.BLACK)
			canvas.draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), data.map_color)
		if t.town != null:
			var size := 13 + int(data.kind) * 2
			canvas.draw_string_outline(font, at + Vector2(half + 4.0, 5.0), t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color.BLACK)
			canvas.draw_string(font, at + Vector2(half + 4.0, 5.0), t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
	# quest targets
	for target in QuestManager.active_targets():
		var qat := world_to_screen(target["pos"] as Vector2)
		var pulse := 1.0 + 0.15 * sin(_time * 4.0)
		var diamond := PackedVector2Array([qat + Vector2(0, -8) * pulse, qat + Vector2(8, 0) * pulse, qat + Vector2(0, 8) * pulse, qat + Vector2(-8, 0) * pulse])
		canvas.draw_colored_polygon(diamond, Color(1.0, 0.85, 0.2))
		canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color.BLACK, 1.5)
		canvas.draw_string_outline(font, qat + Vector2(11, -6), String(target["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		canvas.draw_string(font, qat + Vector2(11, -6), String(target["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.9, 0.4))
	# you
	var p := _manager.player
	if p != null and is_instance_valid(p):
		var at := world_to_screen(Vector2(p.global_position.x, p.global_position.z))
		var forward3 := -p.global_transform.basis.z
		var f := Vector2(forward3.x, forward3.z).normalized()
		var side := Vector2(-f.y, f.x)
		var tip := at + f * 11.0
		var tail_a := at - f * 6.0 + side * 6.0
		var tail_b := at - f * 6.0 - side * 6.0
		canvas.draw_colored_polygon(PackedVector2Array([tip, tail_a, tail_b]), Color(1.0, 0.85, 0.2))
		canvas.draw_polyline(PackedVector2Array([tip, tail_a, tail_b, tip]), Color.BLACK, 1.5)


# What is under the mouse: a town, a place or a quest target ("" = nothing)
func hover_name(at: Vector2) -> String:
	var best := ""
	var best_d := 14.0
	for target in QuestManager.active_targets():
		var d := world_to_screen(target["pos"] as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = "Quest: " + String(target["name"])
	for t in _manager.towns:
		var d := world_to_screen(Vector2(t.position.x, t.position.z)).distance_to(at)
		if d < best_d and t.town != null:
			best_d = d
			best = "%s (%s)" % [t.town.display_name, (t.poi as TownData).display_name.to_lower()]
	for poi in _manager.pois:
		if poi.poi is TownData:
			continue
		var d := world_to_screen(Vector2(poi.position.x, poi.position.z)).distance_to(at)
		if d < best_d:
			best_d = d
			var n := DialogueEngine.poi_topic_name(_manager, poi)
			best = n if n != "" else poi.poi.display_name
	return best


func _update_text() -> void:
	var w := screen_to_world(_mouse)
	var biome := _manager.map.get_biome_at(w.x, w.y)
	var town := _manager.get_town_at(Vector3(w.x, 0.0, w.y))
	var here := biome.display_name if biome != null else "Outside the world"
	if town != null and town.town != null:
		here = "%s, %s" % [town.town.display_name, here]
	_title.text = "Map  ·  %s  ·  %d, %d  ·  zoom x%.1f" % [here, roundi(w.x), roundi(w.y), _zoom]
	var name := hover_name(_mouse)
	_tooltip.visible = name != ""
	if name != "":
		_tooltip.text = name
		_tooltip.position = _view.position + _mouse + Vector2(16, 12)
	_status.text = "[Wheel / + -] Zoom   [Drag / WASD] Move   [C] Center on me   [M / Esc] Close" + ("   [Right click] Teleport (debug)" if can_teleport() else "")


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title)
	_view = MapView.new()
	_view.owner_map = self
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_view)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(_status)
	_tooltip = Label.new()
	_tooltip.add_theme_constant_override("outline_size", 6)
	_tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tooltip.add_theme_font_size_override("font_size", 16)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_root.add_child(_tooltip)
