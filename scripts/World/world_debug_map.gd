class_name WorldDebugMap
extends CanvasLayer
## Top-down map of the whole world. Press M to show / hide it. Created by WorldManager.
## Shows biome colors (shaded by height), the biome rectangles you laid out (white outlines,
## the real borders are bent away from them), the dark cliff ring, and where you are.

const ACTION := "world_map_debug"
const MAP_VIEW_WIDTH := 560.0
const MAP_VIEW_MAX_HEIGHT := 640.0

# Draws the outlines and the player arrow on top of the map picture
class Overlay extends Control:
	var owner_map: WorldDebugMap

	func _draw() -> void:
		if owner_map != null:
			owner_map.draw_overlay(self)


var _manager: WorldManager
var _root: Control
var _picture: TextureRect
var _overlay: Overlay
var _label: Label
var _status: Label
var _open := false
var _generating := false
var _generation := 0
var _have_image := false
var _tasks := {}  # generation -> worker task id (every task must be waited for before exit)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 7
	_manager = get_parent() as WorldManager
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_M
		InputMap.action_add_event(ACTION, ev)
	_build_ui()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _manager == null or not event.is_action_pressed(ACTION):
		return
	if get_tree().paused:
		return  # a menu is open
	_open = not _open
	if _open and not _have_image and not _generating:
		_start_generation()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_root.visible = _open and not get_tree().paused
	if not _root.visible:
		return
	_overlay.queue_redraw()
	var p := _manager.player
	if p != null and is_instance_valid(p):
		var pos := p.global_position
		var biome := _manager.map.get_biome_at(pos.x, pos.z)
		_label.text = "Seed %d    Position %d, %d    Biome: %s" % [
			_manager.world_seed, roundi(pos.x), roundi(pos.z), biome.display_name if biome != null else "(outside)"]


## The world changed (new seed): forget the picture
func invalidate() -> void:
	_generation += 1
	_have_image = false
	_generating = false
	_picture.texture = null
	if _open:
		_start_generation()


# ---------------------------------------------------------------- building

func _view_size() -> Vector2:
	var b := _manager.map.get_bounds()
	var h := minf(MAP_VIEW_WIDTH * b.size.y / maxf(b.size.x, 1.0), MAP_VIEW_MAX_HEIGHT)
	return Vector2(MAP_VIEW_WIDTH, maxf(h, 120.0))


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -MAP_VIEW_WIDTH - 40.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_label = Label.new()
	vbox.add_child(_label)

	var holder := Control.new()
	holder.custom_minimum_size = _view_size()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(holder)

	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_picture)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_overlay = Overlay.new()
	_overlay.owner_map = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.text = "[M] Close    White outline = layout rectangle, dark ring = world edge, squares = towns, brown = roads, dots = POIs (bigger = dungeon)"
	vbox.add_child(_status)


# ---------------------------------------------------------------- picture

func _start_generation() -> void:
	_generating = true
	_status.text = "Generating map..."
	var gen := _generation
	var map := _manager.map
	var res := _manager.settings.debug_map_resolution
	_tasks[gen] = WorkerThreadPool.add_task(func() -> void:
		var image := _render(map, res)
		_finish_generation.call_deferred(image, gen), false, "debug map")


func _exit_tree() -> void:
	for gen in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[gen])
	_tasks.clear()


func _finish_generation(image: Image, gen: int) -> void:
	if _tasks.has(gen):
		WorkerThreadPool.wait_for_task_completion(_tasks[gen])  # it is just returning, this cleans it up
		_tasks.erase(gen)
	if gen != _generation:
		return  # the world changed while this was rendering
	_generating = false
	_have_image = true
	_picture.texture = ImageTexture.create_from_image(image)
	_status.text = "[M] Close    White outline = layout rectangle, dark ring = world edge, squares = towns, brown = roads, dots = POIs (bigger = dungeon)"


# Runs on a worker thread
static func _render(map: WorldMap, resolution: int) -> Image:
	var b := map.get_bounds()
	var aspect := b.size.y / maxf(b.size.x, 1.0)
	var w := resolution
	var h := maxi(int(round(resolution * aspect)), 8)
	if aspect > 1.0:
		h = resolution
		w = maxi(int(round(resolution / aspect)), 8)
	var s := WorldMap.Sample.new()
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	var colors := PackedColorArray()
	colors.resize(w * h)
	var lo := INF
	var hi := -INF
	for j in h:
		for i in w:
			var x := b.position.x + (float(i) + 0.5) / float(w) * b.size.x
			var z := b.position.y + (float(j) + 0.5) / float(h) * b.size.y
			map.sample(x, z, s)
			heights[j * w + i] = s.height
			colors[j * w + i] = s.map_color.lerp(Color(0.1, 0.1, 0.12), s.edge * 0.7)
			if s.edge < 0.01:
				lo = minf(lo, s.height)
				hi = maxf(hi, s.height)
	var image := Image.create(w, h, false, Image.FORMAT_RGB8)
	var span := maxf(hi - lo, 1.0)
	for j in h:
		for i in w:
			var t := clampf((heights[j * w + i] - lo) / span, 0.0, 1.0)
			var c := colors[j * w + i]
			image.set_pixel(i, j, Color(c.r, c.g, c.b).darkened(0.35 - 0.35 * t))
	return image


# Called by the Overlay control
func draw_overlay(canvas: Control) -> void:
	if _manager == null or _manager.map == null:
		return
	var b := _manager.map.get_bounds()
	var scale_to_view := canvas.size / b.size
	for i in _manager.map.placements.size():
		var r := _manager.map.get_placement_rect(i)
		var view_rect := Rect2((r.position - b.position) * scale_to_view, r.size * scale_to_view)
		canvas.draw_rect(view_rect, Color(1, 1, 1, 0.55), false, 1.0)
	var roads := _manager.map.roads
	if roads != null:
		for road in roads.get_roads():
			var line := PackedVector2Array()
			for p: Vector3 in road["points"]:
				line.append((Vector2(p.x, p.z) - b.position) * scale_to_view)
			canvas.draw_polyline(line, Color(0.25, 0.16, 0.08, 0.9), 2.0)
	var font := ThemeDB.fallback_font
	for t in _manager.towns:
		var at := (Vector2(t.position.x, t.position.z) - b.position) * scale_to_view
		var data := t.poi as TownData
		var half := 3.0 + float(data.kind) * 1.5
		canvas.draw_rect(Rect2(at - Vector2(half + 1.0, half + 1.0), Vector2(half + 1.0, half + 1.0) * 2.0), Color.BLACK)
		canvas.draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), data.map_color)
		if t.town != null:
			canvas.draw_string_outline(font, at + Vector2(half + 3.0, 4.0), t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			canvas.draw_string(font, at + Vector2(half + 3.0, 4.0), t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	for poi in _manager.pois:
		if poi.poi is TownData:
			continue
		var dot := (Vector2(poi.position.x, poi.position.z) - b.position) * scale_to_view
		var big := poi.poi is DungeonEntrancePOIData
		canvas.draw_circle(dot, 3.5 if big else 2.5, Color.BLACK)
		canvas.draw_circle(dot, 2.5 if big else 1.6, poi.poi.map_color)
	var p := _manager.player
	if p == null or not is_instance_valid(p):
		return
	var pos := p.global_position
	var at := (Vector2(pos.x, pos.z) - b.position) * scale_to_view
	var forward3 := -p.global_transform.basis.z
	var f := Vector2(forward3.x, forward3.z).normalized()
	var side := Vector2(-f.y, f.x)
	var tip := at + f * 9.0
	var tail_a := at - f * 5.0 + side * 5.0
	var tail_b := at - f * 5.0 - side * 5.0
	canvas.draw_colored_polygon(PackedVector2Array([tip, tail_a, tail_b]), Color(1.0, 0.85, 0.2))
	canvas.draw_polyline(PackedVector2Array([tip, tail_a, tail_b, tip]), Color.BLACK, 1.5)
