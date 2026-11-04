class_name TownBoards
extends RefCounted
## Alpha 1.24: what a town puts up for all to see.
##   notice board  (the town's own NoticeBoard, at the top of its menu): a wanted poster when you have a bounty here, rewards for the
##                 dangerous places nearby, this month's festival and how the town is doing
##   graves        everyone named who dies in town gets a stone by the temple (or the square): their
##                 name, the day and how they died (kept in WorldState "graves/<town id>")
## TownSociety builds them when a town loads and keeps the board's text up to date.

const GRAVE_RECORD := "graves/"


## What the board says today
static func board_text(world: WorldManager, t: PlacedPOI) -> String:
	var parts := PackedStringArray()
	var bounty := CrimeManager.get_bounty(t.id)
	if bounty > 0:
		parts.append("WANTED\nFor crimes against the people of %s. A stranger, armed, answering to your description.\nReward: %d gold. By order of the guard." % [t.town.display_name, bounty])
	var rewards := PackedStringArray()
	for p in world.pois:
		if p.poi is TownData or p.poi.garrison == null or Discovery.is_cleared(p.id):
			continue
		var d := Vector2(p.position.x - t.position.x, p.position.z - t.position.z).length()
		if d < 900.0:
			rewards.append("- %s, %s of town. The council pays for news that it has been cleared." % [DialogueEngine.poi_topic_name(world, p).capitalize(), DialogueEngine.compass(Vector2(p.position.x - t.position.x, p.position.z - t.position.z))])
		if rewards.size() >= 3:
			break
	if not rewards.is_empty():
		parts.append("DANGER NEAR THE TOWN\n" + "\n".join(rewards))
	if world.clock != null:
		var month: Array = Festivals.LIST[world.clock.get_month()]
		parts.append("THIS MONTH\n%s, from the %dth: %s" % [month[0], Festivals.FIRST_DAY, month[2]])
	var needs := TownNeeds.get_needs(t.id)
	if not needs.is_empty():
		if TownNeeds.is_hungry(t.id):
			parts.append("BY ORDER OF THE COUNCIL\nBread is rationed. No grain to leave the town.")
		elif int(needs.get("safety", 60)) < TownNeeds.UNSAFE:
			parts.append("BY ORDER OF THE COUNCIL\nTravel in company. The gates close at dusk.")
	var graves := WorldState.get_record(GRAVE_RECORD + t.id).get("list", []) as Array
	if not graves.is_empty():
		var g: Dictionary = graves[graves.size() - 1]
		parts.append("IN MEMORY\n%s, laid to rest on day %d." % [String(g["name"]), int(g["day"])])
	if parts.is_empty():
		return "Old notices, curling at the edges. Nothing new."
	return "\n\n".join(parts)


## Someone named died in town: their grave (built now if the town is loaded)
static func add_grave(world: WorldManager, r: TownLife.Resident, cause: String, day: int) -> void:
	var rec := WorldState.get_record(GRAVE_RECORD + r.town.id).duplicate()
	var list: Array = (rec.get("list", []) as Array).duplicate()
	for g: Dictionary in list:
		if String(g["id"]) == r.data.id:
			return
	list.append({"id": r.data.id, "name": r.data.display_name, "day": day, "cause": cause})
	rec["list"] = list
	WorldState.set_record(GRAVE_RECORD + r.town.id, rec)
	var node := world.get_poi_node(r.town.id) if world.has_method("get_poi_node") else null
	if node != null:
		_build_grave(world, r.town, node, list.size() - 1, list[list.size() - 1])


## Every grave of a town that has just loaded
static func build_graves(world: WorldManager, t: PlacedPOI, node: Node3D) -> void:
	var list: Array = WorldState.get_record(GRAVE_RECORD + t.id).get("list", [])
	for i in list.size():
		_build_grave(world, t, node, i, list[i])


# A row of stones beside the temple (or the square), the newest at the end
static func _build_grave(world: WorldManager, t: PlacedPOI, node: Node3D, i: int, g: Dictionary) -> void:
	var layout := t.town
	var base := Vector3.ZERO
	var along := Vector3(1, 0, 0)
	for b in layout.buildings:
		if b.kind == BuildingPlot.Kind.TEMPLE:
			var door := b.get_door_local()
			var out := (door - b.local_pos).normalized()
			base = door + out * 4.0 + out.cross(Vector3.UP) * 3.0
			along = out.cross(Vector3.UP)
			break
	if base == Vector3.ZERO:
		base = layout.get_plaza_spot(7) + Vector3(6, 0, 6)
	var local := base + along * float(i % 8) * 1.3 + along.cross(Vector3.UP) * float(i / 8) * 1.8
	var at := layout.to_world(local)
	at.y = world.get_height_at(at.x, at.z)
	var text := "Here lies %s.\nDied on the %s day, %s.\nRemembered." % [String(g["name"]), _ordinal(int(g["day"])), String(g["cause"])]
	var stone := Readable.make(node, Vector3.ZERO, 0.0, "A Grave", text, "none")
	stone.name = "Grave_%s" % String(g["id"]).replace("/", "_")
	stone.global_position = at
	var grey := Color(0.5, 0.5, 0.48)
	POIBuilder.add_box(stone, Vector3(0.6, 0.85, 0.14), Vector3(0, 0.42, 0), grey)
	POIBuilder.add_box(stone, Vector3(0.8, 0.15, 1.7), Vector3(0, 0.07, 0.9), Color(0.33, 0.27, 0.2))


static func _ordinal(n: int) -> String:
	var s := "th"
	if n % 100 < 11 or n % 100 > 13:
		s = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, s]
