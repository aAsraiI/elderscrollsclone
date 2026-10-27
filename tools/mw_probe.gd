extends SceneTree
## Development probe for the Morrowind importer.
##   godot --headless --path . -s res://tools/mw_probe.gd -- "<Data Files>" list <pattern>
##   godot --headless --path . -s res://tools/mw_probe.gd -- "<Data Files>" nif <file> [dump]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var bsa := MwBsa.open(args[0].path_join("Morrowind.bsa"))
	match args[1]:
		"list":
			var n := 0
			var list := bsa.names()
			list.sort()
			for name in list:
				if String(name).match(args[2]):
					print(name)
					n += 1
			print("%d of %d" % [n, list.size()])
		"keys":
			var kf := MwNif.parse(bsa.read(args[2]))
			for r in kf.records:
				if r["type"] == "NiTextKeyExtraData":
					for k in r["keys"]:
						print("%.3f  %s" % [k[0], String(k[1]).replace("
", " | ")])
		"nif":
			for file in args[2].split(","):
				var nif := MwNif.parse(bsa.read(file))
				var types := {}
				for r in nif.records:
					types[r["type"]] = types.get(r["type"], 0) + 1
				print("%s: %d records, roots %s, error '%s'\n  %s" % [file, nif.records.size(), nif.roots, nif.error, types])
				if args.size() > 3:
					for i in nif.records.size():
						var r: Dictionary = nif.records[i]
						var line := "  [%d] %s %s" % [i, r["type"], r.get("name", "")]
						if r.has("origin"):
							line += " at %s scale %.2f" % [r["origin"], r["scale"]]
						if r.has("children"):
							line += " children %s" % r["children"]
						if r.has("file"):
							line += " file %s" % r["file"]
						if r.has("text"):
							line += " text '%s'" % r["text"]
						if r.has("vertices") and r["type"] == "NiTriShapeData":
							line += " verts %d tris %d uvs %d" % [r["vertices"].size(), r["triangles"].size() / 3, r["uvs"].size()]
						if r.has("bones") and r["type"] == "NiSkinInstance":
							line += " bones %s" % r["bones"]
						if r.has("skin"):
							line += " data %d skin %d props %s" % [r["data"], r["skin"], r["properties"]]
						print(line)
	quit()
