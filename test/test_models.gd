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
	# The built-in models first (this PC may have your own or Morrowind's in the models folder)
	ModelLibrary.only_builtin(true)
	t_library()
	t_items()
	t_props()
	t_nature()
	ModelLibrary.only_builtin(false)
	t_user_folder()
	t_morrowind()
	t_morrowind_world()
	t_turned_rooms()
	t_rooms()
	await t_prop_collision()
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
	# Whatever is already there (your own models, a Morrowind import) is put back afterwards
	var json_path := dir.path_join("models.json")
	var kept := FileAccess.get_file_as_string(json_path) if FileAccess.file_exists(json_path) else ""
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
	DirAccess.remove_absolute(json_path)
	if kept != "":
		FileAccess.open(json_path, FileAccess.WRITE).store_string(kept)
	ModelLibrary.reload()
	check("removing them puts things back", not ModelLibrary.has("prop/test_crate"))


func t_morrowind() -> void:
	print("-- Morrowind people")
	var keys := [[0.0, "Idle: Start"], [2.0, "Idle: Stop\r\n"], [3.0, "WeaponOneHand: Chop Start"],
		[3.5, "WeaponOneHand: Chop Hit"], [3.8, "WeaponOneHand: Chop Large Follow Stop"],
		[4.0, "WeaponOneHand: Chop Small Follow Stop"], [5.0, "Idle2: Start"], [5.5, "Idle2: Loop Start"],
		[6.0, "Idle2: Loop Stop"], [7.0, "Idle2: Stop"]]
	var r := MwCharacter.clip_ranges(keys)
	check("text keys become clips (%s)" % str(r.keys()), r.get("Idle") == [0.0, 2.0] and r.get("WeaponOneHand_Chop") == [3.0, 3.8] and r.get("Idle2") == [5.0, 7.0] and not r.has("Idle2_Loop"))
	var folder := MwData.find_install()
	if folder == "":
		print("SKIP  Morrowind is not installed here: the import itself is not tried")
		return
	var data := MwData.open(folder)
	check("your copy of Morrowind opens (%d races, %d items)" % [data.esm.races.size(), data.esm.wearables.size()], data.esm.races.size() >= 10 and data.esm.wearables.size() > 500)
	var b := MwCharacter.new(data)
	var t := Time.get_ticks_msec()
	var person := b.build(MwImport.CAST["people/knight"])
	check("a knight is built (%d ms, problems: %s)" % [Time.get_ticks_msec() - t, ", ".join(b.problems)], person != null and b.problems.is_empty())
	if person == null:
		return
	var stand := Node3D.new()
	root.add_child(stand)
	stand.add_child(person)
	var skel := person.get_node("Skeleton3D") as Skeleton3D
	check("on Morrowind's skeleton (%d bones)" % skel.get_bone_count(), skel.find_bone("Bip01 Head") >= 0 and skel.find_bone("Weapon Bone") >= 0)
	var meshes := person.find_children("*", "MeshInstance3D", true, false)
	var textured := meshes.filter(func(m): return ((m as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture != null)
	check("wearing its parts, textured (%d of %d)" % [textured.size(), meshes.size()], meshes.size() >= 10 and textured.size() == meshes.size())
	var player := person.get_node("AnimationPlayer") as AnimationPlayer
	var clips := player.get_animation_list()
	var missing := MwImport.CLIPS.values().filter(func(c): return not clips.has(c))
	check("every clip the game asks for is there", missing.is_empty(), ", ".join(missing))
	player.play("WalkForward")
	player.seek(0.3, true)
	var box := ModelLibrary.bounds(stand)
	check("it stands up (%.2f m tall, %.2f deep)" % [box.size.y, box.size.z], box.size.y > 1.6 and box.size.y < 2.4 and box.size.z < 1.0)
	var head := ModelLibrary.relative_transform(stand, skel) * skel.get_bone_global_pose(skel.find_bone("Bip01 Head")).origin
	check("head on top", head.y > box.position.y + box.size.y * 0.8)
	check("walks in place (forward motion taken out)", b.speeds.get("WalkForward", 0.0) > 20.0)
	stand.free()


func t_morrowind_world() -> void:
	print("-- Morrowind's things, creatures and skies")
	var folder := MwData.find_install()
	if folder == "":
		print("SKIP  Morrowind is not installed here")
		return
	var data := MwData.open(folder)
	var found := MwCatalog.statics(data)
	check("the catalogue finds hundreds of Morrowind models (%d)" % found.size(), found.size() > 200)
	check("for furniture, clutter, weapons and armour", found.has("prop/barrel") and found.has("clutter/plate") and found.has("item/steel_sword") and found.has("item/iron_helmet"))
	var b := MwCharacter.new(data)
	var barrel := b.build_static(String(found["prop/barrel"]["file"]))
	var box := ModelLibrary.bounds(_wrap(barrel))
	check("a Morrowind barrel at its real size (%.2f m tall)" % box.size.y, box.size.y > 0.6 and box.size.y < 1.4)
	barrel.get_parent().free()
	var candle := b.build_static("meshes/l/light_com_candle_06.nif")
	check("a candle reads (particles included) with its light and flame", candle != null and candle.find_children("*", "OmniLight3D", true, false).size() >= 1 and candle.find_child("Flame", true, false) != null)
	if candle != null:
		candle.free()
	var rat := b.build_creature(data.find(["meshes/r/rust rat.nif"]), data.find(["meshes/r/xrust rat.kf"]))
	var clips := (rat.get_node("AnimationPlayer") as AnimationPlayer).get_animation_list() if rat else PackedStringArray()
	check("a rat walks, runs, bites and dies (%d clips)" % clips.size(), clips.has("WalkForward") and clips.has("Attack1") and clips.has("Death1"))
	if rat != null:
		rat.free()
	var skel := b.build_creature(data.find(["meshes/r/skeleton.nif"]), data.find(["meshes/r/xskeleton.kf"]))
	var sclips := (skel.get_node("AnimationPlayer") as AnimationPlayer).get_animation_list() if skel else PackedStringArray()
	check("a skeleton borrows people's clips it lacks", sclips.has("Idle") and sclips.has("WalkForward") and sclips.has("WeaponOneHand_Chop"))
	if skel != null:
		skel.free()
	var tex := data.texture("tx_sky_clear.tga")
	check("Morrowind's sky and ground textures read", tex != null and data.texture("tx_ai_grass_01.tga") != null)


func _wrap(n: Node3D) -> Node3D:
	var w := Node3D.new()
	w.add_child(n)
	return w


func t_rooms() -> void:
	print("-- rooms")
	var room := Rect2(-3.0, -2.5, 6.0, 5.0)
	var layouts: Array = []
	var loot: Array = []
	for seed_value in [3, 6]:  # both variant 0 of LAYOUTS = 3
		var root := Node3D.new()
		RoomDecorator.decorate(root, room, "tavern", 4, seed_value, "", "test/room_%d" % seed_value)
		var pieces := root.get_children().filter(func(c): return String(c.name).begins_with("Decor_")).map(func(c): return "%s@%s" % [String(c.name).trim_suffix("2").trim_suffix("3"), (c as Node3D).position.snappedf(0.01)])
		pieces.sort()
		layouts.append(pieces)
		loot.append(root.find_children("*", "WorldItem", true, false).map(func(w): return String((w as WorldItem).item.id)))
		root.free()
	check("two taverns of a size share a layout (%d pieces)" % layouts[0].size(), layouts[0] == layouts[1] and layouts[0].size() >= 3)
	check("but their loot is their own", loot[0] != loot[1] or loot[0].is_empty())
	var tags := RoomDecorator.surface_tags("rack", PackedStringArray(["weapon", "armor", "camp", "tavern"]))
	check("racks hold weapons and armour (%s)" % ", ".join(tags), not tags.has("tavern") and tags.has("weapon"))
	var shelf := RoomDecorator.surface_tags("bookcase", PackedStringArray(["camp"]))
	check("a surface with nothing of its own takes the room's loot", shelf == PackedStringArray(["camp"]))


# A prop without a model gets collision the size of what you see (the old scenes' boxes were often far
# deeper than the prop)
func t_prop_collision() -> void:
	print("-- prop collision")
	ModelLibrary.only_builtin(true)
	var anvil := (load("res://scenes/interiors/props/anvil.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(anvil)
	await process_frame
	var seen := ModelLibrary.bounds(anvil)
	var solid := AABB()
	var first := true
	for cs in anvil.find_children("*", "CollisionShape3D", false, false):
		var a := ModelLibrary.relative_transform(anvil, cs) * (cs as CollisionShape3D).shape.get_debug_mesh().get_aabb()
		solid = a if first else solid.merge(a)
		first = false
	check("an anvil's collision fits it (%s vs %s)" % [solid.size.snappedf(0.01), seen.size.snappedf(0.01)], not first and solid.size.z <= seen.size.z * 1.1 + 0.02 and solid.size.x <= seen.size.x * 1.1 + 0.02)
	anvil.free()
	ModelLibrary.only_builtin(false)


# Dungeon rooms are placed turned, and their enemies with them: facing must be in world terms
func t_turned_rooms() -> void:
	print("-- enemies in turned rooms")
	for turn in [PI, PI * 0.5, -0.7]:
		var room := Node3D.new()
		room.rotation.y = turn
		root.add_child(room)
		var e := Enemy.create()
		room.add_child(e)
		var to := Vector3(1.0, 0.0, 0.3).normalized()
		for i in 60:
			e._face(to, 0.1)
		var fwd := -e.global_basis.z
		check("in a room turned %.1f it faces its target (off by %.0f deg)" % [turn, rad_to_deg(fwd.angle_to(to))], fwd.angle_to(to) < 0.05)
		check("and knows it does", e._facing_error(to) < 0.05)
		for i in 60:
			e._face(-to, 0.1)  # fleeing: facing the way it runs
		check("running away it faces away", (-e.global_basis.z).angle_to(-to) < 0.05)
		room.free()


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
	# The lantern slot: wearing a lantern lights the way
	var lantern_node := p.get_node_or_null("LanternLight") as LanternLight
	check("you carry a lantern light", lantern_node != null and not lantern_node.is_lit())
	var lantern := load("res://data/clutter/lantern.tres") as ItemData
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	inv.add_item(lantern)
	check("a lantern goes in the Lantern slot", lantern.equip_slot == ItemData.EquipSlot.LANTERN and eq.equip(lantern))
	check("and lights up around you", lantern_node != null and lantern_node.is_lit() and lantern_node.get_node("Light").visible)
	eq.unequip(ItemData.EquipSlot.LANTERN)
	check("taking it off puts it out", lantern_node != null and not lantern_node.is_lit())
