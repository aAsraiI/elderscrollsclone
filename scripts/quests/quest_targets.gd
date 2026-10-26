class_name QuestTargets
extends RefCounted
## Finds what quests point at by stable ids, never by node: people, places and containers are
## looked up again whenever they are needed, so world streaming, interiors and save/load never
## break a quest. Saved quest data only ever holds these ids.
##   people   "npc/<building id>" (townspeople), "custom/<id>" (CustomNpcData), "Name@Town"
##   places   a town's name, a POI id, "dungeon near <Town>", "camp near <Town>", "x,z"


## The resident for a person id (null for custom people and strangers)
static func resident(world: WorldManager, who: String) -> TownLife.Resident:
	if world == null or world.life == null or who == "":
		return null
	if who.begins_with("npc/"):
		return world.life.get_resident(who)
	var at := who.find("@")
	if at > 0:
		var name := who.substr(0, at)
		var town := who.substr(at + 1)
		for t in world.towns:
			if t.town != null and t.town.display_name == town:
				for r: TownLife.Resident in world.life.get_town_residents(t.id):
					if r.data.display_name == name:
						return r
	return null


## Is this speaker the person `who` names?
static func is_person(s: DialogueEngine.Speaker, who: String, world: WorldManager) -> bool:
	if s == null or who == "":
		return false
	if s.id == who:
		return true
	var r := resident(world, who)
	return r != null and r.data.id == s.id


## Is the person dead (or gone from the world)?
static func is_gone(world: WorldManager, who: String) -> bool:
	if who.begins_with("custom/"):
		return WorldState.has_record("kill/" + who) or not CustomNpcs.all().any(func(d: CustomNpcData) -> bool: return d.save_id() == who)
	var r := resident(world, who)
	return r == null or r.dead


## Where a person is found (their home or work), Vector3.INF if unknown
static func person_pos(world: WorldManager, who: String) -> Vector3:
	if who.begins_with("custom/"):
		var cn := world.get_node_or_null("CustomNpcs") as CustomNpcs
		for d in CustomNpcs.all():
			if d.save_id() == who and cn != null:
				return cn.spot_of(d)
		return Vector3.INF
	var r := resident(world, who)
	if r == null:
		return Vector3.INF
	var b := world.get_building(r.data.work_id if r.data.work_id != "" else r.data.home_id)
	return b.world_pos if b != null else r.town.position


## A person's town (for fallbacks: its lord, its board)
static func person_town(world: WorldManager, who: String) -> PlacedPOI:
	var r := resident(world, who)
	if r != null:
		return r.town
	var at := person_pos(world, who)
	return world.get_nearest_town(at) if at.is_finite() else null


## A place: {"pos": Vector3, "poi": id or ""} ({} if it doesn't exist)
static func place(world: WorldManager, where: String) -> Dictionary:
	if world == null or where == "":
		return {}
	var ix := index(world)
	if ix.has(where):
		var hit: Variant = ix[where]
		if hit is BuildingPlot:
			return {"pos": (hit as BuildingPlot).world_pos, "poi": (hit as BuildingPlot).id}  # a building: its interior counts too (the "enter" event)
		return {"pos": (hit as PlacedPOI).position, "poi": (hit as PlacedPOI).id}
	if where.contains(",") and where.get_slice(",", 0).is_valid_float():
		var x := float(where.get_slice(",", 0))
		var z := float(where.get_slice(",", 1))
		return {"pos": Vector3(x, world.get_height_at(x, z), z), "poi": ""}
	for t in world.towns:
		if t.town != null and t.town.display_name == where:
			return {"pos": t.position, "poi": t.id}
	var p := world.get_poi(where)
	if p != null:
		return {"pos": p.position, "poi": p.id}
	for kind in ["dungeon near ", "camp near "]:
		if where.begins_with(kind):
			var near := place(world, where.trim_prefix(kind))
			if near.is_empty():
				return {}
			var best: PlacedPOI = nearest_poi(world, near["pos"], kind == "dungeon near ")
			return {"pos": best.position, "poi": best.id} if best != null else {}
	return {}


## The nearest dungeon with a master (dungeon) or camp with a garrison
static func nearest_poi(world: WorldManager, from: Vector3, dungeon: bool) -> PlacedPOI:
	var best: PlacedPOI = null
	var best_d := INF
	for p in world.pois:
		if p.town != null:
			continue
		var ok := false
		if dungeon:
			var e := p.poi as DungeonEntrancePOIData
			ok = e != null and e.dungeon != null and e.dungeon.boss != null
		else:
			ok = p.poi is SimplePOIData and p.poi.garrison != null and p.poi.id != &"dragon_lair"
		var d := p.position.distance_squared_to(from)
		if ok and d < best_d:
			best_d = d
			best = p
	return best


## The nearest container (chest) whose save id contains `kind` ("chest_boss", "building/")
static func nearest_container(tree: SceneTree, from: Vector3, kind: String) -> ContainerComponent:
	var best: ContainerComponent = null
	var best_d := INF
	for c in tree.root.find_children("*", "ContainerComponent", true, false):
		var cc := c as ContainerComponent
		var host := cc.get_parent() as Node3D
		if cc.save_id.contains(kind) and host != null:
			var d := host.global_position.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = cc
	return best


## Does this enemy count for a KILL target (its id, its name, or its spawn key)?
static func enemy_matches(e: Enemy, target: String) -> bool:
	if e == null or target == "":
		return false
	return String(e.enemy_id) == target or e.display_name == target or e.spawn_key == target \
		or e.display_name.to_lower().contains(target.to_lower())


## Quest-critical creatures and people: road traffic and unloading leave them alone
static func is_critical(n: Node) -> bool:
	return n != null and n.has_meta("quest_critical")


## A townsperson as someone to talk to (for checks made without their body at hand)
static func speaker_of(world: WorldManager, r: TownLife.Resident) -> DialogueEngine.Speaker:
	var s := DialogueEngine.Speaker.new()
	s.data = r.data
	s.id = r.data.id
	s.name = r.data.display_name
	s.role = r.data.role
	s.personality = r.data.personality
	s.faction = r.data.faction
	s.base_disposition = r.data.base_disposition
	s.town = r.town
	s.home = world.get_building(r.data.home_id)
	s.position = s.home.world_pos if s.home != null else r.town.position
	return s


static var _index := {}
static var _index_key := -1


## Every town (by name and id), place (by id) and building (by id) of the world, worked out once
## when the world is made: what quest targets are looked up in
static func index(world: WorldManager) -> Dictionary:
	if world == null:
		return {}
	if _index_key == world.get_instance_id() and not _index.is_empty():
		return _index
	_index.clear()
	_index_key = world.get_instance_id()
	for p in world.pois:
		_index[p.id] = p
	for t in world.towns:
		if t.town != null:
			_index[t.town.display_name] = t
			for b in t.town.buildings:
				_index[b.id] = b
	return _index
