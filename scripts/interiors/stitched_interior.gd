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
## Old saves: a dungeon visited before Alpha 1.13 used to keep its old generated layout; since Alpha 1.20
## (rooms are hand-made templates, no furniture picked at run time) it is built from its recipe like any
## other. DungeonBuilder is left for a DungeonData without a recipe.


static func uses_modules(data: DungeonData, dungeon_id: String) -> bool:
	return (data != null and data.recipe != null) or handmade_for(data, dungeon_id) != ""


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
	root.set_meta("loot_level", int(ctx["level_max"]))  # builder-kit containers and shelves in its rooms (KitPlace)
	var totals := {"props": 0, "chests": 0, "enemies": 0, "boss": false}
	for room in root.get_children():
		if room is RoomModule:
			var got := RoomFiller.fill(room, ctx)
			# loot on the room's own furniture (its tables, shelves, altars), thinner than in a house, never restocked
			var rb := (room as RoomModule).bounds()
			var rid := String(room.get_meta("room_id", room.name))
			RoomDecorator.decorate(room, Rect2(rb.position.x, rb.position.z, rb.size.x, rb.size.z), KitPlace.room_theme(room), int(ctx["level_max"]),
				("%d|%s" % [dungeon_seed, rid]).hash(), "", rid, [], 0, 1, 3.0, 0.5)
			for k in ["props", "chests", "enemies"]:
				totals[k] += int(got[k])
			totals["boss"] = bool(totals["boss"]) or bool(got["boss"])
	var features := {}
	if not plan.links.is_empty():
		features = InteriorFeatures.apply(plan, root, data, dungeon_id, level_max, dungeon_seed)
	StoryScenes.add(root, dungeon_id, dungeon_seed)  # 1.24: what happened here, in bones and a note
	StoryScenes.add_event(root, dungeon_id, dungeon_seed, int(ctx["level_max"]))  # 1.26: someone else down here
	if int(occ["gen"]) > 0:
		_newcomers_note(root, dungeon_id, int(occ["gen"]))  # 1.24: why new folk moved into a place you cleared
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
		# The way out is a door with a lit lantern, facing into the room
		var spot := door.position - Vector3(0, 1.3, 0)
		var inward := first.bounds().get_center() - spot
		# square to the wall it is set in (the room's middle is seldom straight ahead of it)
		inward = Vector3(signf(inward.x), 0.0, 0.0) if absf(inward.x) > absf(inward.z) else Vector3(0.0, 0.0, signf(inward.z))
		# and against it: from the spot back to the room's edge, less the wall's half thickness
		var rb := first.bounds()
		var to_edge := (spot.x - rb.position.x if inward.x > 0.0 else rb.end.x - spot.x) if inward.x != 0.0 else (spot.z - rb.position.z if inward.z > 0.0 else rb.end.z - spot.z)
		if to_edge > 0.35 and to_edge < 1.6:
			spot -= inward * (to_edge - 0.3)
		DoorLook.dress(first, spot, atan2(inward.x, inward.z), "door/dungeon")
	root.set_meta("stone_walls", true)  # dungeon walls read as stone (StaticBatch, built shader)
	return {"root": root, "start": start, "start_yaw": start_yaw, "down_spot": null, "rooms": plan.placed.size(),
		"chests": totals["chests"], "enemies": totals["enemies"], "boss": totals["boss"], "floor": 0, "floors": 1,
		"props": totals["props"], "features": features, "signature": plan.summary(), "plan": plan, "handmade": scene,
		"theme": String(first.themes[0]) if first != null and not first.themes.is_empty() else "fort"}


const NEWCOMER_NOTES := [
	["A Scrawled Note", "Whoever cleared this place did us a favour. Dry, deep, and nobody comes looking. Tell the others: this is ours now."],
	["Orders to the New Crew", "Last lot got careless and got themselves killed. You won't. Lookouts at the door, no fires near the entrance, and nobody goes out alone."],
	["A Claim, Chalked on the Wall", "THIS HOLE IS SPOKEN FOR. (Underneath, in another hand: 'So was the last one.')"],
]


# By the way in: a note from the ones who moved in after you cleared it
static func _newcomers_note(root: Node3D, dungeon_id: String, gen: int) -> void:
	for c in root.get_children():
		if c is RoomModule:
			var n: Array = NEWCOMER_NOTES[absi(("%s|%d" % [dungeon_id, gen]).hash()) % NEWCOMER_NOTES.size()]
			var spot := RoomFiller.free_spot(RoomFiller.furniture_in(c), c, Vector3(1.2, 0, 1.2))
			if spot.is_finite():
				var r := Readable.make(c, spot, 0.4, String(n[0]), String(n[1]), "note")
				r.name = "NewcomersNote"
			return
