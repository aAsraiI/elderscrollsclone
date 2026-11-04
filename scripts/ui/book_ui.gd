class_name BookUI
extends CanvasLayer
## A page for reading a lorebook (LoreBooks): its title and text, closed with the button or Esc.
## Opened by ItemUse when you read a book from the inventory.


static func open(tree: SceneTree, title: String, text: String) -> BookUI:
	if tree == null:
		return null
	var old := tree.get_first_node_in_group("book_ui")
	if old != null:
		old.queue_free()
	var ui := BookUI.new()
	ui._build(title, text)
	tree.root.add_child(ui)
	return ui


func _build(title: String, text: String) -> void:
	add_to_group("book_ui")
	layer = 40
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 420)
	panel.position = Vector2(-280, -210)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	box.add_child(head)
	var body := RichTextLabel.new()
	_pages = pages_of(text)
	body.text = _pages[0]
	body.fit_content = false
	body.scroll_active = true
	_body = body
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(520, 300)
	box.add_child(body)
	# 1.24: a long book is pages you turn
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_prev = Button.new()
	_prev.text = "< Back"
	_prev.pressed.connect(func() -> void: turn(-1))
	row.add_child(_prev)
	_count = Label.new()
	row.add_child(_count)
	_next = Button.new()
	_next.text = "Next >"
	_next.pressed.connect(func() -> void: turn(1))
	row.add_child(_next)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	row.add_child(close)
	_show_page()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		turn(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		turn(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


# ---------------------------------------------------------------- pages (1.24)

const PAGE_CHARS := 900

var _pages := PackedStringArray([""])
var _page := 0
var _body: RichTextLabel
var _prev: Button
var _next: Button
var _count: Label


## The text cut into pages at paragraph ends (or sentence ends in a very long paragraph)
static func pages_of(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for para in text.split("\n"):
		var piece := para
		while piece.length() > PAGE_CHARS:
			var cut := piece.rfind(". ", PAGE_CHARS)
			cut = cut + 1 if cut > PAGE_CHARS / 3 else PAGE_CHARS
			if cur != "":
				out.append(cur)
				cur = ""
			out.append(piece.substr(0, cut).strip_edges())
			piece = piece.substr(cut).strip_edges()
		if cur.length() + piece.length() + 1 > PAGE_CHARS and cur != "":
			out.append(cur)
			cur = ""
		cur = piece if cur == "" else cur + "\n" + piece
	if cur != "" or out.is_empty():
		out.append(cur)
	return out


func turn(by: int) -> void:
	_page = clampi(_page + by, 0, _pages.size() - 1)
	_show_page()


func _show_page() -> void:
	if _body != null:
		_body.text = _pages[_page]
	if _prev != null:
		_prev.disabled = _page == 0
		_next.disabled = _page >= _pages.size() - 1
		_prev.visible = _pages.size() > 1
		_next.visible = _pages.size() > 1
		_count.text = "%d / %d" % [_page + 1, _pages.size()] if _pages.size() > 1 else ""
