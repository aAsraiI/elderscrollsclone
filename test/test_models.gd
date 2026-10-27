extends SceneTree
## Headless tests for 1.15.3 (real models): the model list, items, props, trees and rocks, people and
## creatures with their own animations, hitboxes fitted to models, corpses, your own models folder.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_models.gd

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
		await physics_frame


func _run() -> void:
	await process_frame
	t_library()
	t_items()
	t_props()
	t_nature()
	t_user_folder()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_library() -> void:
	print("-- the model list")
	var keys := ModelLibrary.keys()
	check("models.json lists 100+ looks (%d)" % keys.size(), keys.size() >= 100)
	var bad := PackedStringArray()
	for k in keys:
		var m := ModelLibrary.instance(k)
		if m == null or ModelLibrary.bounds(m).size.length() < 0.001:
			bad.append(k)
		if m != null:
			m.free()
	check("every listed model loads and has a size", bad.is_empty(), ", ".join(bad))
	var fit := ModelLibrary.fitted("prop/barrel", AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.9, 0.6)))
	var b := ModelLibrary.bounds(fit)
	check("a fitted model fills the old space (%.2f tall, floor %.2f)" % [b.size.y, b.position.y], absf(b.size.y - 0.9) < 0.05 and absf(b.position.y) < 0.02)
	fit.free()
	check("a missing key gives no model (the boxes stay)", ModelLibrary.instance("prop/no_such_thing") == null)


func t_items() -> void:
	print("-- items")
	var sword := load("res://data/weapons/iron_sword.tres") as ItemData
	if sword == null:
		for f in DirAccess.get_files_at("res://data/weapons"):
			var it := load("res://data/weapons/" + f) as ItemData
			if it != null and it.item_type == ItemData.ItemType.WEAPON and String(it.animation_set) == "":
				sword = it
				break
	check("found a sword to try", sword != null)
	if sword == null:
		return
	var view := ItemModels.build_view(sword)
	var has_model := not view.find_children("*", "", true, false).filter(func(n): return n.has_meta("model_key")).is_empty()
	check("a sword in your hand is a real model", has_model)
	var b := ModelLibrary.bounds(view)
	check("held blade runs up from the grip (%.2f to %.2f)" % [b.position.y, b.end.y], b.size.y > 0.5 and b.position.y < 0.05 and b.end.y > 0.5)
	view.free()
	var potion: ItemData = null
	for f in DirAccess.get_files_at("res://data/consumables"):
		var it := load("res://data/consumables/" + f) as ItemData
		if it != null and it.effect_group == "potion":
			potion = it
			break
	if potion != null:
		var w := WorldItem.spawn(potion, 1, root, Vector3(0, 50, 0))
		var model := w.get_node_or_null("Model")
		var keyed := model != null and not model.find_children("*", "", true, false).filter(func(n): return n.has_meta("model_key")).is_empty()
		check("a potion on the ground is a real model", keyed)
		var shape := w.find_children("*", "CollisionShape3D", false, false)
		var box := (shape[0] as CollisionShape3D).shape as BoxShape3D if not shape.is_empty() else null
		var vb := ModelLibrary.bounds(model)
		check("its collision box fits the model", box != null and box.size.distance_to(vb.size.max(Vector3(0.06, 0.06, 0.06))) < 0.02, "%s vs %s" % [box.size if box else Vector3.ZERO, vb.size])
		w.free()
	var keys := ItemModels.model_keys(sword)
	check("items look up their own id first", keys[0] == "item/" + String(sword.id))


func t_props() -> void:
	print("-- props")
	var barrel := (load("res://scenes/interiors/props/barrel.tscn") as PackedScene).instantiate() as InteriorProp
	root.add_child(barrel)
	var boxes := barrel.find_children("Part*", "MeshInstance3D", false, false)
	check("the barrel's boxes are gone", boxes.is_empty())
	check("a barrel model is there", barrel.get_node_or_null("Model") != null)
	var shapes := barrel.find_children("*", "CollisionShape3D", false, false)
	var hulls := shapes.filter(func(s): return (s as CollisionShape3D).shape is ConvexPolygonShape3D)
	check("its collision follows the model (%d hulls, no box)" % hulls.size(), not hulls.is_empty() and hulls.size() == shapes.size())
	var mb := ModelLibrary.bounds(barrel)
	check("it stands where the old barrel stood (%.2f tall)" % mb.size.y, absf(mb.size.y - 0.9) < 0.1 and absf(mb.position.y) < 0.05)
	barrel.free()
	# A prop with a flame keeps the flame
	var fire := (load("res://scenes/interiors/props/campfire.tscn") as PackedScene).instantiate() as InteriorProp
	var glow_before := fire.find_children("*", "MeshInstance3D", true, false).filter(func(m): return ModelLibrary._glows(m)).size()
	root.add_child(fire)
	var glow_after := fire.find_children("*", "MeshInstance3D", true, false).filter(func(m): return ModelLibrary._glows(m) and not ModelLibrary._is_kept(m)).size()
	check("a campfire keeps its flames (%d of %d)" % [glow_after, glow_before], glow_after == glow_before)
	check("and its stones are a model", fire.get_node_or_null("Model") != null)
	fire.free()
	# Decorations built in code
	var room := Node3D.new()
	root.add_child(room)
	var slots: Array = []
	RoomDecorator._build_piece(room, "table", Vector3.ZERO, 0.0, slots, 3.0)
	var piece := room.get_child(0) as Node3D
	check("a decorated room's table is a model", piece.get_node_or_null("Model") != null)
	var tb := ModelLibrary.bounds(piece)
	check("things set on it still sit on top (%.2f tall, slot at %.2f)" % [tb.end.y, (slots[0][0] as Vector3).y], absf(tb.end.y - (slots[0][0] as Vector3).y) < 0.15)
	room.free()


func t_nature() -> void:
	print("-- trees and rocks")
	var rock := NatureMeshes.rock_mesh(0)
	check("rocks are models", rock is ArrayMesh and rock.get_surface_count() >= 1 and rock.get_aabb().size.y > 0.5)
	var tree := TerrainChunk._tree_model(BiomeData.TreeStyle.BROADLEAF)
	check("leafy trees are models (%.1f m)" % (tree.get_aabb().size.y if tree else 0.0), tree != null and absf(tree.get_aabb().size.y - 5.8) < 0.3)
	check("styles without a model keep the old trees", TerrainChunk._tree_model(BiomeData.TreeStyle.CACTUS) == null)


func t_user_folder() -> void:
	print("-- your own models")
	var dir := ProjectSettings.globalize_path("user://models")
	DirAccess.make_dir_recursive_absolute(dir)
	# A glb of our own, made from a built-in model, saved under a key's name
	var src := ModelLibrary.instance("prop/bucket")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(src, state)
	var path := dir.path_join("prop__test_crate.glb")
	doc.write_to_filesystem(state, path)
	src.free()
	FileAccess.open(dir.path_join("models.json"), FileAccess.WRITE).store_string('{"prop/test_crate_turned": {"path": "prop__test_crate.glb", "rot": [0, 90, 0]}}')
	ModelLibrary.reload()
	check("a file named prop__test_crate.glb becomes prop/test_crate", ModelLibrary.has("prop/test_crate"))
	var m := ModelLibrary.instance("prop/test_crate")
	check("and loads at runtime", m != null and ModelLibrary.bounds(m).size.y > 0.1)
	if m != null:
		m.free()
	var rot: Array = ModelLibrary.entry("prop/test_crate_turned").get("rot", [0, 0, 0])
	check("a models.json there adds keys too", rot.size() == 3 and is_equal_approx(float(rot[1]), 90.0))
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir.path_join("models.json"))
	ModelLibrary.reload()
	check("removing them puts things back", not ModelLibrary.has("prop/test_crate"))


func t_in_game() -> void:
	print("-- people and creatures")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(90)
	var p := get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", p != null)
	if p == null:
		return
	var rng := RandomNumberGenerator.new()
	var at := p.global_position + Vector3(0, 0, -8)
	var bandit := Population.spawn_enemy(load("res://data/enemies/bandit.tres"), 3, current_scene, at, rng)
	var wolf := Population.spawn_enemy(load("res://data/enemies/wolf.tres"), 3, current_scene, at + Vector3(4, 0, 0), rng)
	await frames(10)
	check("a bandit has a real model", bandit.body != null and bandit.body.model_body != null)
	check("a wolf has a real model", wolf.body != null and wolf.body.model_body != null)
	if bandit.body == null or bandit.body.model_body == null or wolf.body.model_body == null:
		return
	var mb := bandit.body.model_body
	check("it plays its own animation (%s)" % mb.player.current_animation if mb.player else "", mb.player != null and mb.player.is_playing())
	check("the boxes are hidden", not bandit.body.bones["hips"].visible)
	var weapon_shown := bandit.body.grip != null and bandit.body.grip.is_visible_in_tree() and bandit.body.grip.get_child_count() > 0
	check("its weapon hangs from the model's hand", weapon_shown and mb.model.is_ancestor_of(bandit.body.grip))
	var cap := (bandit.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D)
	var box := ModelLibrary.relative_transform(bandit, mb) * ModelLibrary.bounds(mb)
	check("its hitbox is as tall as its model (%.2f vs %.2f)" % [(cap.shape as CapsuleShape3D).height, box.size.y], absf((cap.shape as CapsuleShape3D).height - box.size.y) < 0.05)
	var wcap := (wolf.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D)
	check("a wolf's hitbox lies along its body", absf(wcap.rotation.x - PI * 0.5) < 0.01 and (wcap.shape as CapsuleShape3D).radius < 0.6)
	check("the wolf's eyes are low (%.2f m)" % wolf.head.position.y, wolf.head.position.y < 1.2)
	# Walking plays the walk clip
	wolf.velocity = Vector3(2.0, 0, 0)
	wolf.body._speed = 2.0
	wolf.body.model_body.animate(0.1, 2.0)
	check("a moving wolf walks (%s)" % wolf.body.model_body.player.current_animation, wolf.body.model_body._role == "walk")
	# Death: the death clip, lying as one searchable piece
	bandit.stats.modify_vital("health", -99999.0)
	await frames(20)
	var rag := bandit.get_node_or_null("Ragdoll") as Ragdoll
	check("the bandit died", bandit.state == Enemy.State.DEAD)
	check("its corpse is one piece", rag != null and rag.parts.has("remains"))
	check("playing its death clip", mb._dead and mb.player.current_animation.to_lower().contains("death"))
	check("and still drawn", mb.model.is_visible_in_tree())
	var searchable := rag != null and rag.parts.has("remains") and (rag.parts["remains"] as Node).has_meta("interactable")
	check("and can be searched", searchable)
