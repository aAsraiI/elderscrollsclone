extends SceneTree
## Saves a contact sheet of Morrowind textures (for choosing them):
##   godot --headless --path . -s res://tools/mw_texture_sheet.gd -- "<Data Files>" out.png name,name,...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var data := MwData.open(args[0])
	var names := args[2].split(",")
	var cell := 128
	var cols := 6
	var sheet := Image.create(cols * cell, int(ceil(names.size() / float(cols))) * (cell + 14), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in names.size():
		var t := data.texture(names[i] + ".tga")
		if t == null:
			print("missing ", names[i])
			continue
		var img := t.get_image()
		img.clear_mipmaps()
		img.resize(cell, cell)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * (cell + 14)))
		print(i, " ", names[i])
	sheet.save_png(args[1])
	quit()
