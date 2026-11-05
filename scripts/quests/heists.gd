class_name Heists
extends RefCounted
## Alpha 1.29.4: heists for the Thieves Guild. A member asks the guild's fence (a city pawnbroker)
## about "a heist": the fence names a rich house in town (a noble seat, or the best house) and what
## is in its strongbox. Go in (best at night: pick the lock, or find another way), take the Heist
## Prize from the strongbox past the night watchmen who walk their rounds, and get out. Back at
## the fence, "the heist" pays out: the full purse if no one saw you inside, half if you were seen.
## One heist at a time; a new one the next day. Kept in WorldState "heist".
##   {"state": "active", "building", "town", "owner", "day", "seen", "spawned"}

const PRIZE := "res://data/misc/heist_prize.tres"
const PAY := 600
const PAY_PER_LEVEL := 12
const WATCHMEN := 2


static func record() -> Dictionary:
	return WorldState.get_record("heist")


static func active() -> bool:
	return String(record().get("state", "")) == "active"


static func is_fence(s: DialogueEngine.Speaker, world: WorldManager) -> bool:
	return s != null and Factions.is_member("thieves") and Factions.leader_of(s, world) == "thieves"


static func topics_for(s: DialogueEngine.Speaker, world: WorldManager) -> PackedStringArray:
	var out := PackedStringArray()
	if is_fence(s, world) and not s.asleep:
		out.append("the heist" if active() else "a heist")
	return out


## The richest house in a town: a noble seat first, then the house with the hardest lock
static func target_in(town: PlacedPOI) -> BuildingPlot:
	if town == null or town.town == null:
		return null
	var best: BuildingPlot = null
	for b: BuildingPlot in town.town.buildings:
		if b.kind != BuildingPlot.Kind.SEAT and b.kind != BuildingPlot.Kind.HOUSE:
			continue
		if Homes.owns(b.id):
			continue
		if best == null or (b.kind == BuildingPlot.Kind.SEAT and best.kind != BuildingPlot.Kind.SEAT) \
				or (b.kind == best.kind and b.lock_level > best.lock_level):
			best = b
	return best


static func pay_for(player: Node) -> int:
	var sk := player.get_node_or_null("Skills") as Skills
	return PAY + PAY_PER_LEVEL * (sk.get_player_level() if sk != null else 1)


static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, world: WorldManager) -> Dictionary:
	if not topics_for(s, world).has(topic):
		return {}
	var today := world.clock.day if world != null and world.clock != null else 1
	if topic == "a heist":
		if int(WorldState.get_record("heist_last").get("day", -9)) == today:
			return Roleplay._say("Not today. Let the last one cool off. Come back tomorrow.")
		var b := target_in(s.town)
		if b == null:
			return Roleplay._say("Nothing in this town worth the risk. Try another city.")
		var who := b.owner_name if b.owner_name != "" else b.display_name
		var town_name := s.town.town.display_name
		WorldState.set_record("heist", {"state": "active", "building": b.id, "town": town_name, "owner": who, "day": today, "seen": false, "spawned": false})
		var pay := pay_for(player)
		DialogueState.system_entry("Quest", "The fence has a job: the strongbox in %s in %s. Take the prize past the night watchmen and get out. %d gold if no one sees me inside, half if they do." % [b.display_name, town_name, pay], "")
		Notices.quest(player.get_tree(), "Heist", "%s, %s" % [b.display_name, town_name])
		return Roleplay._say("%s keeps a strongbox in %s. Two watchmen walk the rooms at night. Bring me what's in it, and don't let them see your face: %d gold, half if they do." % [who, b.display_name, pay])
	# "the heist"
	var inv := player.get_node("Inventory") as Inventory
	var prize := load(PRIZE) as ItemData
	if prize == null or not inv.has_item(prize):
		return Roleplay._say("The strongbox in %s, in %s. I'll be here when you have it." % [String(record().get("owner", "")), String(record().get("town", ""))])
	inv.remove_item(prize, 1)
	var seen := bool(record().get("seen", false))
	var pay := pay_for(player) / (2 if seen else 1)
	Currency.add_gold(inv, pay)
	WorldState.set_record("heist", {"state": "done"})
	WorldState.set_record("heist_last", {"day": today})
	Factions.add_quest_done("thieves")
	Achievements.note("heist")
	if not seen:
		Achievements.note("clean_heist")
	DialogueState.system_entry("Quest", "The heist is done: %d gold from the fence%s." % [pay, " (half: I was seen)" if seen else ", and no one saw a thing"], "")
	return Roleplay._say(("Clean as a whistle. %d gold, as promised." if not seen else "Half, as we said: they saw you. %d gold.") % pay)


## The player went into a building (DungeonManager.entered): set out the strongbox and the watch
static func on_entered(tree: SceneTree, entrance_id: String) -> void:
	var rec := record()
	if String(rec.get("state", "")) != "active" or String(rec.get("building", "")) != entrance_id:
		return
	var dm := tree.get_first_node_in_group("dungeon_manager") as DungeonManager
	var root := dm.get_interior_root() if dm != null else null
	var player := tree.get_first_node_in_group("player") as Node3D
	if root == null or player == null:
		return
	var prize := load(PRIZE) as ItemData
	var inv := player.get_node("Inventory") as Inventory
	if prize != null and inv.has_item(prize):
		return
	# the strongbox goes by the bed furthest from the door (or simply across the room)
	var far := player.global_position - player.global_transform.basis.z * 5.0
	var best := -1.0
	for n in root.find_children("*", "RestSpot", true, false):
		var d := (n as Node3D).global_position.distance_to(player.global_position)
		if d > best:
			best = d
			far = (n as Node3D).global_position + Vector3(0.9, 0.0, 0.0)
	var loot: Array[LootEntry] = []
	var box := POIBuilder.make_chest("Strongbox", loot, "", 1)
	root.add_child(box)
	box.global_position = far
	(box.get_node("ContainerComponent") as ContainerComponent).inventory.add_item(prize, 1)
	box.set_meta("heist_box", true)
	# the night watch walks between the door and the box
	var data := load("res://data/enemies/caravan_guard.tres") as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sk := player.get_node_or_null("Skills") as Skills
	for i in WATCHMEN:
		var at := player.global_position.lerp(far, 0.35 + 0.3 * i) + Vector3(rng.randf_range(-1.0, 1.0), 0.3, rng.randf_range(-1.0, 1.0))
		var e := Enemy.create()
		data.apply(e, maxi((sk.get_player_level() if sk != null else 5), 5), rng)
		e.display_name = "Night Watchman"
		e.disposition = Enemy.Disposition.HOSTILE
		e.persist_mode = Enemy.PersistMode.NEVER
		e.set_meta("watchman", true)
		root.add_child(e)
		e.global_position = at
		e.follow_route.call_deferred(PackedVector3Array([player.global_position, far]), true, 0.35)
	Locks.toast(tree, "Somewhere in here is the strongbox. Mind the watch.")


## Seen inside? (Tutorial checks while you are in the target building)
static func watch(tree: SceneTree, player: Node3D) -> void:
	var rec := record()
	if String(rec.get("state", "")) != "active" or bool(rec.get("seen", false)):
		return
	var dm := tree.get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm == null or not dm.is_in_building() or dm.current_entrance_id != String(rec.get("building", "")):
		return
	var st: Variant = player.get_meta("stealth", null)
	if st == null or not is_instance_valid(st):
		return
	for e in tree.get_nodes_in_group("enemies"):
		if e.has_meta("watchman") and float(st.awareness_of(e)) >= Stealth.SEEN:
			rec = rec.duplicate()
			rec["seen"] = true
			WorldState.set_record("heist", rec)
			Locks.toast(tree, "A watchman saw you! The fence will pay half.", true)
			return
