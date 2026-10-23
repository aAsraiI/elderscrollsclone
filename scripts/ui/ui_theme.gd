class_name UITheme
extends RefCounted
## The look of every menu: thin gold lines on dark glass, small text, slim buttons and lists.
## Built in code so it is easy to tweak, then saved to res://ui/ui_theme.tres, which
## Project Settings > GUI > Theme > Custom points at (so every Control in the game uses it).
##
## After changing a color or size here, rebuild the file:
##   godot --headless --path . -s res://tools/build_ui_theme.gd
## (or open ui/ui_theme.tres in the editor and change it there, by hand).

const THEME_PATH := "res://ui/ui_theme.tres"

const FONT_SIZE := 14
const GOLD := Color(0.93, 0.80, 0.48)
const GOLD_DIM := Color(0.93, 0.80, 0.48, 0.35)
const TEXT := Color(0.90, 0.88, 0.82)
const TEXT_DIM := Color(0.90, 0.88, 0.82, 0.45)
const PANEL_BG := Color(0.045, 0.045, 0.055, 0.93)
const FIELD_BG := Color(0.0, 0.0, 0.0, 0.35)
const HOVER_BG := Color(1.0, 1.0, 1.0, 0.06)
const SELECT_BG := Color(0.93, 0.80, 0.48, 0.16)

## Height of the tab bar along the top of the Tab menu (see MenuHub): screens leave room for it
const HUB_BAR_HEIGHT := 40


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	# Panels: dark glass with one thin gold line
	var panel := _box(PANEL_BG, GOLD_DIM, 1, 3, 12)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	t.set_stylebox("panel", "TooltipPanel", _box(PANEL_BG, GOLD_DIM, 1, 2, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", 2)

	# Buttons: almost flat, a hairline border, gold when hovered
	var b_normal := _box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.10), 1, 2, 0)
	_pad(b_normal, 10, 4)
	var b_hover := _box(Color(0.93, 0.80, 0.48, 0.10), GOLD_DIM, 1, 2, 0)
	_pad(b_hover, 10, 4)
	var b_pressed := _box(Color(0.93, 0.80, 0.48, 0.22), GOLD, 1, 2, 0)
	_pad(b_pressed, 10, 4)
	var b_disabled := _box(Color(1, 1, 1, 0.015), Color(1, 1, 1, 0.05), 1, 2, 0)
	_pad(b_disabled, 10, 4)
	var b_focus := _box(Color(0, 0, 0, 0), GOLD, 1, 2, 0)
	b_focus.draw_center = false
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, b_normal)
		t.set_stylebox("hover", type, b_hover)
		t.set_stylebox("pressed", type, b_pressed)
		t.set_stylebox("hover_pressed", type, b_pressed)
		t.set_stylebox("disabled", type, b_disabled)
		t.set_stylebox("focus", type, b_focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_hover_pressed_color", type, GOLD)
		t.set_color("font_focus_color", type, GOLD)
		t.set_color("font_disabled_color", type, TEXT_DIM)
	for type in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		_pad(empty, 4, 2)
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(s, type, empty)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, GOLD)

	# Text fields
	var field := _box(FIELD_BG, Color(1, 1, 1, 0.10), 1, 2, 0)
	_pad(field, 8, 4)
	var field_focus := _box(FIELD_BG, GOLD_DIM, 1, 2, 0)
	_pad(field_focus, 8, 4)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", SELECT_BG)

	# Lists: no box around them, a soft gold bar on the selected row
	var list_bg := _box(FIELD_BG, Color(1, 1, 1, 0.06), 1, 2, 4)
	var selected := _box(SELECT_BG, Color(0, 0, 0, 0), 0, 1, 0)
	selected.border_width_left = 2
	selected.border_color = GOLD
	var hovered := _box(HOVER_BG, Color(0, 0, 0, 0), 0, 1, 0)
	var title := _box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 0, 0)
	title.border_width_bottom = 1
	title.border_color = GOLD_DIM
	_pad(title, 6, 3)
	for type in ["Tree", "ItemList"]:
		t.set_stylebox("panel", type, list_bg)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("selected", type, selected)
		t.set_stylebox("selected_focus", type, selected)
		t.set_stylebox("hovered", type, hovered)
		t.set_stylebox("cursor", type, StyleBoxEmpty.new())
		t.set_stylebox("cursor_unfocused", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_selected_color", type, GOLD)
		t.set_color("font_hovered_color", type, Color.WHITE)
	t.set_stylebox("title_button_normal", "Tree", title)
	t.set_stylebox("title_button_hover", "Tree", title)
	t.set_stylebox("title_button_pressed", "Tree", title)
	t.set_color("title_button_color", "Tree", TEXT_DIM)
	t.set_font_size("title_button_font_size", "Tree", 12)
	t.set_constant("v_separation", "Tree", 3)
	t.set_constant("item_margin", "Tree", 8)
	t.set_constant("inner_item_margin_left", "Tree", 4)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_constant("v_separation", "ItemList", 3)

	# Tabs: plain words, the current one underlined in gold
	var tab_sel := _box(Color(0, 0, 0, 0), GOLD, 0, 0, 0)
	tab_sel.border_width_bottom = 2
	_pad(tab_sel, 12, 5)
	var tab_off := StyleBoxEmpty.new()
	_pad(tab_off, 12, 5)
	var tab_hover := _box(HOVER_BG, Color(0, 0, 0, 0), 0, 2, 0)
	_pad(tab_hover, 12, 5)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_off)
	t.set_stylebox("tab_hovered", "TabBar", tab_hover)
	t.set_stylebox("tab_disabled", "TabBar", tab_off)
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", GOLD)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)

	# Bars, sliders, scrollbars: thin
	var bar_bg := _box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.08), 1, 1, 0)
	var bar_fill := _box(GOLD, Color(0, 0, 0, 0), 0, 1, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	var slider := _box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 1, 0)
	slider.content_margin_top = 2
	slider.content_margin_bottom = 2
	var slider_fill := _box(GOLD_DIM, Color(0, 0, 0, 0), 0, 1, 0)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	for type in ["VScrollBar", "HScrollBar"]:
		var track := _box(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 3, 0)
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		var grab := _box(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 0, 3, 0)
		var grab_hi := _box(GOLD_DIM, Color(0, 0, 0, 0), 0, 3, 0)
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)

	var line := StyleBoxLine.new()
	line.color = Color(0.93, 0.80, 0.48, 0.18)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 6)
	var vline := StyleBoxLine.new()
	vline.color = line.color
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)

	var popup := _box(PANEL_BG, GOLD_DIM, 1, 2, 4)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(SELECT_BG, Color(0, 0, 0, 0), 0, 1, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	return t


## Writes the theme file. tools/build_ui_theme.gd calls this.
static func save() -> Error:
	return ResourceSaver.save(build(), THEME_PATH)


## A heading in the menus' style: small capitals, gold
static func heading(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	return l


## Small grey text for key hints at the bottom of a screen
static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", TEXT_DIM)
	return l


static func _box(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	s.anti_aliasing = radius > 0
	return s


static func _pad(s: StyleBox, h: int, v: int) -> void:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
