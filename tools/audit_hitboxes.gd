extends SceneTree
## Lists props whose collision is much bigger than what you can see (or missing).
##   godot --headless --path . -s res://tools/audit_hitboxes.gd [-- builtin]

func _init() -> void:
	if "builtin" in OS.get_cmdline_user_args():
		ModelLibrary.only_builtin(true)
	var dir := "res://scenes/interiors/props/"
	var bad := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tscn"):
			continue
		var p := (load(dir + f) as PackedScene).instantiate() as Node3D
		root.add_child(p)
		var seen := ModelLibrary.bounds(p)
		var solid := AABB()
		var first := true
		for cs in p.find_children("*", "CollisionShape3D", true, false):
			var s := (cs as CollisionShape3D).shape
			if s == null:
				continue
			var local := ModelLibrary.relative_transform(p, cs) * s.get_debug_mesh().get_aabb()
			solid = local if first else solid.merge(local)
			first = false
		var note := ""
		if first:
			note = "no collision"
		else:
			var grow := Vector3(solid.size.x / maxf(seen.size.x, 0.01), solid.size.y / maxf(seen.size.y, 0.01), solid.size.z / maxf(seen.size.z, 0.01))
			if grow.x > 1.25 or grow.y > 1.25 or grow.z > 1.25:
				note = "collision %.2fx %.2fx %.2fx the model" % [grow.x, grow.y, grow.z]
		var model := "model" if p.get_node_or_null("Model") != null else "boxes"
		print("%-22s %-6s seen %s  solid %s  %s" % [f.get_basename(), model, seen.size.snappedf(0.01), solid.size.snappedf(0.01), note])
		if note != "":
			bad += 1
		p.free()
	print("%d props with a problem" % bad)
	quit()
