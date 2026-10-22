extends SceneTree
## Loads every script in the project and reports the ones that fail to compile. Run with:
##   godot --headless --path . -s res://tools/check_scripts.gd


func _initialize() -> void:
	var bad := 0
	for path in _scripts("res://scripts") + _scripts("res://tools") + _scripts("res://test"):
		var s := load(path) as Script
		if s == null or not s.can_instantiate() and not (s as GDScript).is_abstract():
			print("FAILED: ", path)
			bad += 1
	print("checked, %d failed" % bad)
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scripts(dir + "/" + sub))
	return out
