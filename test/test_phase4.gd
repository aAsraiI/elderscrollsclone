extends SceneTree
## Headless tests for rebuild phase 4 (performance): StaticBatch merges a place's plain boxes into
## one mesh and one collision body, leaves named and scripted boxes alone, and still blocks movement.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_phase4.gd

var passes := 0
var fails := 0


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await frames(2)
	await t_batch()
	t_harvest_shares()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_batch() -> void:
	print("-- StaticBatch")
	var place := Node3D.new()
	var stone := Color(0.5, 0.5, 0.52)
	# A wall of solid boxes, a few decorations, one named gate, one glowing window, one scripted thing
	for i in 10:
		POIBuilder.add_box(place, Vector3(2, 3, 0.5), Vector3(i * 2.0, 1.5, 0), stone)
	for i in 4:
		POIBuilder.add_box(place, Vector3(0.3, 0.3, 0.3), Vector3(i, 0.15, 3), Color(0.4, 0.3, 0.2), 0.0, Vector3.ZERO, false)
	var gate := POIBuilder.add_box(place, Vector3(2, 3, 0.25), Vector3(-2, 1.5, 0), Color(0.25, 0.25, 0.28))
	gate.name = "Gate"
	POIBuilder.add_box(place, Vector3(0.6, 0.6, 0.1), Vector3(4, 2, -0.3), Color(1, 0.8, 0.4), 0.0, Vector3.ZERO, false, true)
	var scripted := DungeonFeature.new()
	place.add_child(scripted)
	POIBuilder.add_box(scripted, Vector3(0.5, 0.5, 0.5), Vector3.ZERO, stone)
	var merged := StaticBatch.merge(place)
	check("the 14 plain boxes are merged", merged == 14, str(merged))
	check("one mesh draws them", place.get_node_or_null("MergedBoxes") is MeshInstance3D)
	check("one body holds their collision", place.get_node_or_null("MergedCollision") is StaticBody3D \
		and (place.get_node("MergedCollision") as StaticBody3D).get_shape_owners().size() == 10)
	check("the named gate keeps its own mesh", gate.get_child_count() == 2 and gate.get_child(0) is MeshInstance3D)
	var glow_left := 0
	for c in place.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).material_override is StandardMaterial3D and ((c as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled:
			glow_left += 1
	check("the glowing window is left alone", glow_left == 1)
	check("the scripted node's box is left alone", scripted.find_children("*", "MeshInstance3D", true, false).size() == 1)
	var mesh := (place.get_node("MergedBoxes") as MeshInstance3D).mesh
	var has_stone := false  # vertex colors are stored as 8-bit, so compare closely, not exactly
	for c in (mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
		has_stone = has_stone or (absf(c.r - stone.r) < 0.01 and absf(c.g - stone.g) < 0.01 and absf(c.b - stone.b) < 0.01)
	check("the merged mesh keeps each box's color", has_stone)
	# The wall still blocks: a ray through it hits the merged body
	root.add_child(place)
	await frames(2)
	var q := PhysicsRayQueryParameters3D.create(Vector3(9, 1.5, -5), Vector3(9, 1.5, 5))
	var hit := place.get_world_3d().direct_space_state.intersect_ray(q)
	check("the wall still blocks movement", not hit.is_empty() and hit["collider"] == place.get_node("MergedCollision"), str(hit))
	place.queue_free()


func t_harvest_shares() -> void:
	print("-- herbs and ore share meshes")
	var holder := Node3D.new()
	root.add_child(holder)
	var a := HarvestNode.make_herb(holder, Vector3.ZERO, Vector3(10, 0, 10), "temperate", 0)
	var b := HarvestNode.make_herb(holder, Vector3(2, 0, 0), Vector3(12, 0, 10), "temperate", 0)
	var ma := a.find_children("*", "MeshInstance3D", true, false)
	var mb := b.find_children("*", "MeshInstance3D", true, false)
	check("a herb is one mesh", ma.size() == 1, str(ma.size()))
	check("two herbs of a kind share it", ma.size() == 1 and mb.size() == 1 and (ma[0] as MeshInstance3D).mesh == (mb[0] as MeshInstance3D).mesh)
	check("herbs stop drawing far away", ma.size() == 1 and (ma[0] as MeshInstance3D).visibility_range_end > 0.0)
	var ore := HarvestNode.make_ore(holder, Vector3(5, 0, 0), Vector3(15, 0, 10), 0)
	check("an ore node is a rock and its veins", ore.find_children("*", "MeshInstance3D", true, false).size() == 2)
	holder.queue_free()
