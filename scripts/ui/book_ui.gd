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
	body.text = text
	body.fit_content = false
	body.scroll_active = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(520, 300)
	box.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	box.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
