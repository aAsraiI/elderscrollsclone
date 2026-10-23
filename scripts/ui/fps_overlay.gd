class_name FpsOverlay
extends CanvasLayer
## Small frames-per-second counter in the top-left corner (Settings > Interface > FPS counter).
## GameSettings adds it to the window's root so it survives scene changes.

const NODE_NAME := "FpsOverlay"

var _label: Label
var _t := 0.0


static func set_shown(tree: SceneTree, shown: bool) -> void:
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if shown and existing == null:
		var o := FpsOverlay.new()
		o.name = NODE_NAME
		tree.root.add_child.call_deferred(o)
	elif not shown and existing != null:
		existing.queue_free()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_label = Label.new()
	_label.position = Vector2(8, 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_label)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_label.text = "%d FPS" % Engine.get_frames_per_second()
