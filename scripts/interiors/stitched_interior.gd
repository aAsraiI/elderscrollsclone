class_name StitchedInterior
extends RefCounted
## A dungeon made of room modules, for DungeonManager: plans it from the DungeonData's recipe
## (DungeonAssembler), builds the rooms, fills them (RoomFiller) and puts the way out at the
## entrance room's "Exit" marker. Returns what DungeonBuilder.build returns, so the rest of the
## game doesn't care which kind of dungeon it is.
##
## Hand-made dungeons: a scene of room modules (DungeonPreview's Bake, finished by hand, or made
## from scratch with the entrance room first) is used instead of a plan when the dungeon names one:
## its own record "handmade/<id>" (the story sets these), InteriorOverrides, or the DungeonData's
## Handmade. Its rooms are filled the same way; doors, levers and secrets come from the joins a
## baked scene remembers.
##
## Old saves: a dungeon visited before Alpha 1.13 keeps its old layout (legacy), so its chests and
## bodies are still where they were; one already visited as a generated dungeon stays generated.


static func uses_modules(data: DungeonData, dungeon_id: String) -> bool:
	if is_legacy(dungeon_id):
		return false
	return (data != null and data.recipe != null) or handmade_for(data, dungeon_id) != ""


## Was this dungeon visited before Alpha 1.13 (it has saved chests or kills of the old layout)?
static func is_legacy(dungeon_id: String) -> bool:
	if WorldState.has_record("stitched/" + dungeon_id):
		return false
	var prefix := "dungeon/%s/" % dungeon_id
	for key: String in WorldState.records:
		if (key.begins_with(prefix) or key.begins_with("kill/" + prefix)) and not key.contains("/r"):
			return true
	return false


## The hand-made scene this dungeon uses ("" = generate it)
static func handmade_for(data: DungeonData, dungeon_id: String) -> String:
	var seen: Dictionary = WorldState.get_record("stitched/" + dungeon_id) if WorldState.has_record("stitched/" + dungeon_id) else {}
	if not seen.is_empty() and String(seen.get("scene", "")) == "":
		return ""  # first seen generated: it stays that way
	if not seen.is_empty():
		return String(seen["scene"])
	var path := ""
	if WorldState.has_record("handmade/" + dungeon_id):
		path = String(WorldState.get_record("handmade/" + dungeon_id).get("scene", ""))
	if path == "":
		path = InteriorOverrides.dungeon_scene(dungeon_id)
	if path == "" and data != null and data.handmade != null:
		path = data.handmade.resource_path
	return path if path != "" and ResourceLoader.exists(path) else ""


static func build(data: DungeonData, dungeon_seed: int, dungeon_id: String, level_min: int, level_max: int) -> Dictionary:
	var scene := handmade_for(data, dungeon_id)
	WorldState.set_record("stitched/" + dungeon_id, {"v": 1, "scene": scene})
	var plan: DungeonAssembler
	var root: Node3D
	if scene != "":
		root = (load(scene) as PackedScene).instantiate() as Node3D
		root.name = "Interior"
		plan = DungeonAssembler.from_scene(root)
		var n := 0
		for c in root.get_children():
			if c is RoomModule:
				c.set_meta("room_id", "%s/r%d" % [dungeon_id, n])
				n += 1
	else:
		plan = DungeonAssembler.plan(data.recipe, dungeon_seed, level_max)
		root = plan.build(dungeon_id)
	var density := data.recipe.density if data.recipe != null else 1.0
	var occ := DungeonRefill.occupants(data, dungeon_id, Rumors._day())  # new folk in a long-cleared place
	var ctx := {"data": occ["data"], "dungeon_id": dungeon_id, "level_min": level_min + data.level_offset, "level_max": level_max + data.level_offset,
		"density": density, "seed": dungeon_seed, "occupants": int(occ["gen"])}
	var totals := {"props": 0, "chests": 0, "enemies": 0, "boss": false}
	for room in root.get_children():
		if room is RoomModule:
			var got := RoomFiller.fill(room, ctx)
			for k in ["props", "chests", "enemies"]:
				totals[k] += int(got[k])
			totals["boss"] = bool(totals["boss"]) or bool(got["boss"])
	var features := {}
	if not plan.links.is_empty():
		features = InteriorFeatures.apply(plan, root, data, dungeon_id, level_max, dungeon_seed)
	var start := Vector3(0, 0.2, 0)
	var start_yaw := 0.0
	var first: RoomModule = null
	for c in root.get_children():
		if c is RoomModule:
			first = c
			break
	if first != null:
		var ps := first.get_node_or_null("PlayerStart") as Node3D
		if ps != null:
			start = first.transform * ps.position + Vector3(0, 0.2, 0)
			start_yaw = first.rotation.y + ps.rotation.y
		var exit_mark := first.get_node_or_null("Exit") as Node3D
		if exit_mark != null:
			exit_mark.name = "ExitSpot"  # the door takes the name "Exit"
		var door := DungeonDoor.new()
		door.name = "Exit"
		door.entrance_id = dungeon_id
		door.label = "Leave"
		door.is_exit = true
		door.target_floor = -1
		first.add_child(door)
		door.position = (exit_mark.position if exit_mark != null else Vector3(0, 0, -first.bounds().size.z * 0.5 + 0.6)) + Vector3(0, 1.3, 0)
	return {"root": root, "start": start, "start_yaw": start_yaw, "down_spot": null, "rooms": plan.placed.size(),
		"chests": totals["chests"], "enemies": totals["enemies"], "boss": totals["boss"], "floor": 0, "floors": 1,
		"props": totals["props"], "features": features, "signature": plan.summary(), "plan": plan, "handmade": scene,
		"theme": String(first.themes[0]) if first != null and not first.themes.is_empty() else "fort"}
