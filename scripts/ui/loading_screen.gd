class_name LoadingScreen
extends CanvasLayer
## Shown while a new game or a save loads: building the realm stops the game for several seconds,
## so the screen says what is happening and shows a few lines from one of the lore books.
## It sits on the root, so it survives the scene change; the new world closes it when it is ready.
##   LoadingScreen.open(get_tree())   ...   LoadingScreen.close(get_tree())

const NAME := "LoadingScreen"
## How much of the book is shown: its first sentences, up to about this many characters
const TIP_LENGTH := 260
## Closes itself after this long even if nothing closes it (counted after the world finished building)
const SAFETY_SECONDS := 20.0


static func open(tree: SceneTree) -> void:
	if tree.root.get_node_or_null(NAME) != null:
		return
	var s := LoadingScreen.new()
	s.name = NAME
	tree.root.add_child(s)


static func close(tree: SceneTree) -> void:
	var s := tree.root.get_node_or_null(NAME)
	if s != null:
		s.queue_free()


func _ready() -> void:
	layer = 100  # above every menu and HUD
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Safety: a scene without a world never says it is ready, so don't cover it forever
	get_tree().create_timer(SAFETY_SECONDS, true, false, true).timeout.connect(queue_free)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var title := Label.new()
	title.text = "Loading..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	v.add_child(title)
	var book := LoreBooks.LIST[randi() % LoreBooks.LIST.size()] as Array
	var heading := Label.new()
	heading.text = "%s  -  %s" % [book[1], book[2]]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	v.add_child(heading)
	var tip := Label.new()
	tip.text = _opening(String(book[5]))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color(0.7, 0.68, 0.64))
	v.add_child(tip)


# The book's first sentences, cut at a sentence end before TIP_LENGTH
static func _opening(text: String) -> String:
	if text.length() <= TIP_LENGTH:
		return text
	var cut := text.rfind(". ", TIP_LENGTH)
	return text.substr(0, cut + 1) if cut > 40 else text.substr(0, TIP_LENGTH) + "..."
