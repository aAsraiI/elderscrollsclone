extends SceneTree
## Builds the game's people from your own copy of Morrowind into your models folder (see MwImport).
##   godot --headless --path . -s res://tools/import_morrowind.gd -- ["<Data Files folder>"] [remove]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "remove" in args:
		print("removed %d" % MwImport.remove())
		quit()
		return
	var folder := args[0] if args.size() > 0 else MwData.find_install()
	if folder == "":
		print("Morrowind not found: pass its Data Files folder")
		quit(1)
		return
	var t := Time.get_ticks_msec()
	var r := MwImport.run(folder, func(i, n, key): print("%d/%d %s" % [i + 1, n, key]))
	print("made %d in %.1f s into %s" % [r["made"].size(), (Time.get_ticks_msec() - t) / 1000.0, MwImport.models_dir()])
	for p in r["problems"]:
		print("  problem: ", p)
	quit()
