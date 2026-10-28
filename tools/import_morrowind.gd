extends SceneTree
## Builds the game's people from your own copy of Morrowind into your models folder (see MwImport).
##   godot --headless --path . -s res://tools/import_morrowind.gd -- ["<Data Files folder>"] [remove]
## "kit" builds the builder kit's pieces instead (MwKitCatalog); "kit list" only counts them by type.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "remove" in args:
		print("removed %d" % MwImport.remove())
		quit()
		return
	var folder := args[0] if args.size() > 0 and not args[0] in ["kit", "list"] else MwData.find_install()
	if folder == "":
		print("Morrowind not found: pass its Data Files folder")
		quit(1)
		return
	if "kit" in args and "list" in args:
		var counts := {}
		var keys: Array = MwKitCatalog.statics(MwData.open(folder)).keys()
		for k in keys:
			var set_name := String(k).get_slice("/", 1) + "/" + String(k).get_slice("/", 2)
			counts[set_name] = counts.get(set_name, 0) + 1
		for s in counts:
			print("%5d  %s" % [counts[s], s])
		print("%d pieces" % keys.size())
		quit()
		return
	var t := Time.get_ticks_msec()
	var step := func(i, n, key): print("%d/%d %s" % [i + 1, n, key])
	var r := MwImport.run_kit(folder, step) if "kit" in args else MwImport.run(folder, step)
	print("made %d in %.1f s into %s" % [r["made"].size(), (Time.get_ticks_msec() - t) / 1000.0, MwImport.models_dir()])
	for p in r["problems"]:
		print("  problem: ", p)
	quit()
