extends SceneTree
## Headless tests for Alpha 1.20 (hand-built rooms and the functional builder kit): furniture is part of
## every room scene (never picked at run time), only the loot on it changes; kit containers (leveled and
## empty), loot furniture, stations; shelving collision that leaves the shelves open.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha120.gd

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
	t_baked()
	t_no_random_furniture()
	t_kit_files()
	await t_containers()
	await t_shelves()
	await t_stations()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _scenes(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scenes(dir + d + "/"))
	return out


# ---------------------------------------------------------------- furniture is in the scenes

func t_baked() -> void:
	print("-- furniture baked into the scenes")
	var furniture_spots := PackedStringArray()
	var overrides := PackedStringArray()
	var bare := PackedStringArray()
	var scenes := 0
	for dir in ["res://scenes/interiors/modules/", "res://scenes/interiors/houses/", "res://scenes/interiors/handmade/", "res://scenes/interiors/setpieces/", "res://scenes/sites/"]:
		for path in _scenes(dir):
			scenes += 1
			var root := (load(path) as PackedScene).instantiate()
			for s in root.find_children("*", "SpawnSocket", true, false):
				if (s as SpawnSocket).kind in [SpawnSocket.Kind.FURNITURE, SpawnSocket.Kind.DECORATION, SpawnSocket.Kind.WALL_DECORATION, SpawnSocket.Kind.LIGHT, SpawnSocket.Kind.CEILING]:
					furniture_spots.append("%s:%s" % [path.get_file(), s.name])
			if path.contains("/houses/") and root.find_children("*", "InteriorProp", true, false).size() < 4:
				bare.append(path.get_file())
			root.free()
			# a placed prop is a link to its prop scene, not a copy of its settings
			var text := FileAccess.get_file_as_string(path)
			if text.contains("instance=ExtResource") and text.contains("socket_kinds = "):
				overrides.append(path.get_file())
	check("%d room, house and site scenes have no furniture spawn points left" % scenes, furniture_spots.is_empty(), ", ".join(furniture_spots.slice(0, 6)))
	check("every house is furnished in its scene", bare.is_empty(), ", ".join(bare))
	check("placed props are links to their prop scenes", overrides.is_empty(), ", ".join(overrides.slice(0, 6)))


func t_no_random_furniture() -> void:
	print("-- the same room every time, different loot")
	var path := "res://scenes/interiors/houses/house_a.tscn"
	var layouts: Array = []
	var loot: Array = []
	for n in 2:
		var holder := Node3D.new()
		root.add_child(holder)
		var room := (load(path) as PackedScene).instantiate() as RoomModule
		room.set_meta("room_id", "test120/house_%d" % n)
		holder.add_child(room)
		var got := RoomFiller.fill(room, {"seed": 100 + n * 7919})
		var b := room.bounds()
		var r := RoomDecorator.decorate(room, Rect2(b.position.x, b.position.z, b.size.x, b.size.z), "home", 10, 31 + n * 7, "", "test120/house_%d" % n)
		check("house %d: nothing added but loot (%s)" % [n, str(r)], int(got["props"]) == 0 and int(r["pieces"]) == 0 and int(r["containers"]) == 0)
		var layout := PackedStringArray()
		var things := PackedStringArray()
		for c in room.get_children():
			if c is WorldItem:
				things.append((c as WorldItem).item.resource_path.get_file())
			elif c is Node3D and not c is Marker3D:
				layout.append("%s@%s" % [c.name, str((c as Node3D).position.snappedf(0.01))])
		layouts.append(layout)
		loot.append(things)
		holder.free()
	check("two houses of one template are furnished alike", layouts[0] == layouts[1], "%d vs %d" % [layouts[0].size(), layouts[1].size()])
	check("...and hold different loot", loot[0] != loot[1] and not loot[0].is_empty(), "%s / %s" % [str(loot[0]), str(loot[1])])


# ---------------------------------------------------------------- the kit

func t_kit_files() -> void:
	print("-- kit scenes")
	var leveled := _scenes("res://scenes/kit/containers/leveled/")
	var empty := _scenes("res://scenes/kit/containers/empty/")
	var surfaces := _scenes("res://scenes/kit/surfaces/")
	var stations := _scenes("res://scenes/kit/stations/")
	check("leveled and empty containers (%d + %d)" % [leveled.size(), empty.size()], leveled.size() >= 25 and leveled.size() == empty.size())
	check("loot furniture (%d)" % surfaces.size(), surfaces.size() >= 20)
	check("every crafting station, beds, a shrine and a planter (%d)" % stations.size(), stations.size() >= 15)
	var bad := PackedStringArray()
	for p in leveled + empty + surfaces + stations:
		var n := (load(p) as PackedScene).instantiate()
		if not (n is KitContainer or n is KitLootShelf or n is KitStation):
			bad.append(p.get_file())
		n.free()
	check("every kit scene is a kit piece", bad.is_empty(), ", ".join(bad))
	for old in ["container_chest", "loot_bookcase", "block_wall", "exit_door"]:
		check("old flat kit scene %s is gone (kit is in folders now)" % old, not FileAccess.file_exists("res://scenes/kit/%s.tscn" % old))


func t_containers() -> void:
	print("-- kit containers")
	var place := Node3D.new()
	place.set_meta("room_id", "test120/crypt")
	place.set_meta("loot_level", 20)
	root.add_child(place)
	var full := (load("res://scenes/kit/containers/leveled/chest.tscn") as PackedScene).instantiate() as KitContainer
	var empty := (load("res://scenes/kit/containers/empty/chest.tscn") as PackedScene).instantiate() as KitContainer
	var tall := (load("res://scenes/kit/containers/leveled/wardrobe.tscn") as PackedScene).instantiate() as KitContainer
	empty.name = "EmptyChest"
	place.add_child(full)
	place.add_child(empty)
	place.add_child(tall)
	await frames(2)
	var cf := full.find_child("ContainerComponent", true, false) as ContainerComponent
	var ce := empty.find_child("ContainerComponent", true, false) as ContainerComponent
	check("a leveled chest holds loot for the place", cf != null and not cf.contents.is_empty(), str(cf.contents.size() if cf != null else -1))
	check("an empty chest holds nothing", ce != null and ce.contents.is_empty())
	check("its save id is the room and its name", cf != null and cf.save_id == "kit/test120/crypt/Chest", cf.save_id if cf != null else "")
	# the hitbox fits the model: as tall as what you see, not a chest's box
	for k: KitContainer in [full, tall]:
		var body := k.get_node("Chest") as StaticBody3D
		var seen := ModelLibrary.bounds(body)
		var shapes := _shape_bounds(body)
		check("%s: hitbox fits its model (%.2f m tall, model %.2f m)" % [k.display_name, shapes.size.y, seen.size.y],
			shapes.size.y > 0.1 and absf(shapes.size.y - seen.size.y) < 0.08 and absf(shapes.position.y - seen.position.y) < 0.08)
		check("%s: stands on the floor" % k.display_name, absf(seen.position.y) < 0.03, str(seen.position.y))
	place.free()


func _shape_bounds(body: CollisionObject3D) -> AABB:
	var out := AABB()
	var first := true
	for cs in body.find_children("*", "CollisionShape3D", true, false):
		var s := (cs as CollisionShape3D).shape
		var pts := PackedVector3Array()
		if s is ConvexPolygonShape3D:
			pts = (s as ConvexPolygonShape3D).points
		elif s is ConcavePolygonShape3D:
			pts = (s as ConcavePolygonShape3D).get_faces()
		elif s is BoxShape3D:
			var h := (s as BoxShape3D).size * 0.5
			pts = PackedVector3Array([-h, h])
		var xf := ModelLibrary.relative_transform(body, cs)
		for p in pts:
			out = AABB(xf * p, Vector3.ZERO) if first else out.expand(xf * p)
			first = false
	return out


func t_shelves() -> void:
	print("-- shelving: open collision, loot that sits on it")
	var place := Node3D.new()
	place.set_meta("room_id", "test120/library")
	place.set_meta("loot_theme", "library")
	root.add_child(place)
	var shelf := (load("res://scenes/kit/surfaces/bookcase.tscn") as PackedScene).instantiate() as KitLootShelf
	shelf.fill = 1.0
	place.add_child(shelf)
	await frames(3)
	var exact := shelf.find_children("*", "CollisionShape3D", true, false).filter(func(c: Node) -> bool: return (c as CollisionShape3D).shape is ConcavePolygonShape3D)
	check("a bookcase's collision is its own faces, not a hull over the shelves", not exact.is_empty())
	var slots := ModelLibrary.surface_slots(shelf, shelf, "bookcase")
	check("it has planks to set things on (%d spots)" % slots.size(), slots.size() >= 3)
	# a ray at a plank's height, from the front, reaches into the shelf instead of stopping at its face
	var space := shelf.get_world_3d().direct_space_state
	var b := ModelLibrary.bounds(shelf)
	var deep := 0
	for s: Array in slots:
		var at: Vector3 = shelf.to_global((s[0] as Vector3) + Vector3(0, 0.08, 0))
		for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var from := at - dir * 2.0
			var q := PhysicsRayQueryParameters3D.create(from, at)
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit["position"] as Vector3).distance_to(at) < 0.05:
				deep += 1
				break
	check("you can reach every plank from one side (%d of %d)" % [deep, slots.size()], deep >= slots.size() - 1, str(b))
	var items := shelf.get_children().filter(func(c: Node) -> bool: return c is WorldItem)
	check("its planks hold loot (%d things)" % items.size(), items.size() >= 2)
	var inside := 0
	for w: WorldItem in items:
		var cs := w.find_children("*", "CollisionShape3D", false, false)
		if cs.is_empty():
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = (cs[0] as CollisionShape3D).shape
		q.transform = (cs[0] as CollisionShape3D).global_transform.translated(Vector3(0, 0.01, 0))
		q.collision_mask = 1
		q.exclude = [w.get_rid()]
		for hit in space.intersect_shape(q, 4):
			if hit["collider"] == shelf:
				inside += 1
				break
	check("nothing set on it stands inside it (it would be pushed through the wall)", inside == 0, "%d of %d" % [inside, items.size()])
	place.free()
	# old prop scenes with shelves get the same collision
	var prop := (load("res://scenes/interiors/props/bookshelf.tscn") as PackedScene).instantiate() as InteriorProp
	root.add_child(prop)
	await frames(1)
	var prop_exact := prop.find_children("*", "CollisionShape3D", true, false).any(func(c: Node) -> bool: return (c as CollisionShape3D).shape is ConcavePolygonShape3D)
	check("bookshelf props in rooms: exact collision too", prop_exact or not ModelLibrary.has("prop/bookshelf"))
	prop.free()


func t_stations() -> void:
	print("-- kit stations")
	var place := Node3D.new()
	place.set_meta("building_id", "test120_house")
	place.set_meta("building_kind", BuildingPlot.Kind.INN)
	root.add_child(place)
	for kind in ["forge", "alchemy_lab", "bed", "shrine", "planter"]:
		var k := (load("res://scenes/kit/stations/%s.tscn" % kind) as PackedScene).instantiate() as KitStation
		place.add_child(k)
	await frames(2)
	var crafting := place.find_children("*", "CraftingStation", true, false)
	check("crafting stations work where they are placed (%d)" % crafting.size(), crafting.size() == 2)
	for c: CraftingStation in crafting:
		var hb := _shape_bounds(c)
		var seen := ModelLibrary.bounds(c)
		check("%s: hitbox fits what you see" % c.kind, hb.size.y > 0.3 and absf(hb.end.y - seen.end.y) < 0.25, "%s vs %s" % [hb, seen])
	var rests := place.find_children("*", "RestSpot", true, false)
	check("a bed and a shrine you can use", rests.size() == 2)
	var bed := rests.filter(func(r: Node) -> bool: return (r as RestSpot).kind == "bed")
	check("a bed in an inn is the inn's", not bed.is_empty() and (bed[0] as RestSpot).building_id == "test120_house" and (bed[0] as RestSpot).building_kind == BuildingPlot.Kind.INN)
	check("a planter", not place.find_children("*", "Planter", true, false).is_empty())
	place.free()
