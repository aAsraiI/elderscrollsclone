extends SceneTree
## Saves a screenshot of a Settings tab:  godot --path . -s res://tools/capture_settings.gd -- out.png <tab index>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var s := SettingsMenu.new()
	root.add_child(s)
	await process_frame
	s.open()
	s._tabs.current_tab = int(args[1])
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	print("saved")
	quit()
