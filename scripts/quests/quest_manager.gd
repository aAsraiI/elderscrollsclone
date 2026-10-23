class_name QuestManager
extends Node
## Guild jobs. Created by WorldManager, nothing to add by hand.
##
## Ask a guild's leader about "duties" and they hand out a job made from the world seed and a
## counter (so the same game always gets the same jobs, and saves are safe). One job per guild at
## a time. Kinds of job:
##   retrieve     an item hidden in the boss chest of a dungeon nearby       bring it back
##   kill         a bandit chief added to a camp nearby                       kill them, come back
##   steal        an item from someone's house chest in a town nearby        bring it back
##   persuade     someone in another town must like you (disposition 70)     come back
##   deliver      a sealed package to someone in another town                 talk to them: done
##   assassinate  a townsperson in another town (Assassins Cult)              kill them, come back
## Finished jobs count toward promotion (ask about "advancement"). Everything said about a job is
## written in the journal under the job's name, and active targets show on the map (M).
##
## The Assassins Cult: after your first murder, a hooded stranger finds you one night. Hooded
## figures also sit in city inns at night. They are the cult's contacts.
## Saved in WorldState: "quests" (every job, and the counter) and "assassins/invited".

const STATE := "quests"
const TOPICS: Array[String] = ["membership", "advancement", "clear bounty", "a delivery", "the territory war"]
const PERSUADE_GOAL := 70
const CHIEF_BODY := "res://data/enemies/bandit_brute.tres"
const BEAST_BODY := "res://data/enemies/frost_bear.tres"
## What Antiquarian Society jobs send you after, and the beasts the Hunters' Lodge wants dead
const ARTIFACT_FINDS := ["Bronze Funerary Mask", "Engraved Clay Seal", "Gilded Votive Figure", "Runed Bone Tablet", "Shard of an Old Crown", "Sunstone Amulet"]
const BEASTS := ["the White Stag", "Old Gnasher", "the Ashen Wolf", "Greyback", "the Marsh Hag", "Ironhide"]
const CONTACT_LINES := ["...", "Not here. Not now."]

var world: WorldManager
var _timer := 0.0
var _stranger: Enemy
var _stranger_time := 0.0


func _ready() -> void:
	add_to_group("quests")
	world = get_parent() as WorldManager
	if world != null and world.dungeons != null:
		world.dungeons.entered.connect(_on_entered)
	_apply_perks.call_deferred()
	var sm := get_tree().get_first_node_in_group("save_manager") as SaveManager
	if sm != null:
		sm.loaded.connect(func(_slot: String) -> void: _apply_perks())


func _apply_perks() -> void:
	Factions.apply_perks(_player())
	MuseumCase.apply_bonus(_player())  # the Antiquarian Society's collection


# ---------------------------------------------------------------- the list of jobs

static func all_quests() -> Array:
	return WorldState.get_record(STATE).get("list", [])


static func _save_list(list: Array, counter: int) -> void:
	WorldState.set_record(STATE, {"list": list, "counter": counter})


static func _counter() -> int:
	return int(WorldState.get_record(STATE).get("counter", 0))


static func get_quest(qid: String) -> Dictionary:
	for q: Dictionary in all_quests():
		if q["id"] == qid:
			return q
	return {}


static func _update_quest(q: Dictionary) -> void:
	var list := all_quests().duplicate(true)
	for i in list.size():
		if list[i]["id"] == q["id"]:
			list[i] = q
	_save_list(list, _counter())


## The guild's job in progress, or {}
static func active_for(faction: String) -> Dictionary:
	for q: Dictionary in all_quests():
		if q["faction"] == faction and q["status"] == "active":
			return q
	return {}


## Active jobs' targets for the map: [{"pos": Vector2 (x, z), "name"}]
static func active_targets() -> Array:
	var out: Array = []
	if not bool(GameRules.get_rule("quest_markers")):
		return out
	for q: Dictionary in all_quests():
		if q["status"] == "active":
			out.append({"pos": Vector2(float(q["pos"][0]), float(q["pos"][1])), "name": String(q["name"])})
	var st := Story.target()
	if not st.is_empty():
		out.append(st)
	out.append_array(QuestBook.targets())
	return out


# ---------------------------------------------------------------- making a job

## Makes the next job for a guild, given by `s`. Returns it (already saved), or {} if none fits.
## only_type: make this kind of job (tests use it), instead of one the guild picks.
func offer(faction: String, s: DialogueEngine.Speaker, only_type: String = "") -> Dictionary:
	var d := Factions.get_data(faction)
	if d == null or world == null:
		return {}
	var counter := _counter()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|quest|%s|%d" % [world.world_seed, faction, counter]).hash()
	var types := Array(d.quest_types)
	for i in range(types.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = types[i]
		types[i] = types[j]
		types[j] = tmp
	if only_type != "":
		types = [only_type]
	var town: PlacedPOI = s.town if s.town != null else world.get_nearest_town(_player().global_position)
	var qid := "q%d" % counter
	var q := {}
	for t in types:
		q = _make(String(t), qid, town, s, rng)
		if not q.is_empty():
			break
	if q.is_empty():
		return {}
	q["id"] = qid
	q["faction"] = faction
	q["giver"] = s.id
	q["giver_name"] = s.name
	q["giver_town"] = town.town.display_name if town != null else ""
	q["status"] = "active"
	q["reward"] = d.reward_base + 40 * Factions.rank(faction) + rng.randi_range(0, 30)
	var list := all_quests().duplicate(true)
	list.append(q)
	_save_list(list, counter + 1)
	if q["type"] == "deliver":
		var inv := _player().get_node("Inventory") as Inventory
		inv.add_item(QuestItems.get_item(qid, String(q["item_name"])))
	if q["type"] in ["kill", "hunt", "excavate"] and world.get_poi_node(String(q["target"])) != null:
		var placed := world.get_poi(String(q["target"]))
		for e in on_garrison(placed, world.get_poi_node(placed.id)):
			world.add_to_garrison(placed.id, e)
	return q


func _make(type: String, _qid: String, town: PlacedPOI, s: DialogueEngine.Speaker, rng: RandomNumberGenerator) -> Dictionary:
	var from := town.position if town != null else _player().global_position
	match type:
		"retrieve":
			var options: Array[PlacedPOI] = []
			for p in _pois_near(from, 2600.0):
				var e := p.poi as DungeonEntrancePOIData
				if e != null and e.dungeon != null and e.dungeon.boss != null:
					options.append(p)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 4) - 1)]
			var things := ["Silver Locket", "Old Family Sword", "Lost Journal", "Carved Amulet", "Map of the Old Roads"]
			if s.faction == "mages":
				things = ["Ancient Tome", "Star Chart", "Crystal Focus", "Sealed Grimoire"]
			elif s.faction == "antiquarians":
				things = ARTIFACT_FINDS
			var thing: String = things[rng.randi_range(0, things.size() - 1)]
			var where := _place_name(p)
			return {"type": type, "name": "The %s" % thing, "target": p.id, "container": "dungeon/%s/chest_boss" % p.id,
				"item_name": thing, "pos": [p.position.x, p.position.z], "target_name": where,
				"objective": "Find the %s in the deepest chest of the %s and bring it to %s." % [thing, where, s.name]}
		"kill":
			var options: Array[PlacedPOI] = []
			for p in _pois_near(from, 2200.0):
				if p.poi is SimplePOIData and p.poi.garrison != null:
					options.append(p)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 4) - 1)]
			var chief := "%s the %s" % [NameGen.FIRST[rng.randi_range(0, NameGen.FIRST.size() - 1)], ["Red", "Butcher", "Grim", "Knife", "Wolf", "Black", "Cruel"][rng.randi_range(0, 6)]]
			var where := _place_name(p)
			return {"type": type, "name": "Bounty: %s" % chief, "target": p.id, "chief": chief,
				"pos": [p.position.x, p.position.z], "target_name": where,
				"objective": "Kill %s, who leads the bandits at the %s, then report to %s." % [chief, where, s.name]}
		"steal":
			var house := _pick_building(town, rng, true)
			if house == null:
				return {}
			var thing := "%s's %s" % [NameGen.first_name(house.owner_name), ["Ledger", "Silver Candlestick", "Jeweled Box", "Signet Ring", "Letters"][rng.randi_range(0, 4)]]
			return {"type": type, "name": "A Quiet Job in %s" % house.town_name, "target": house.id, "container": "building/%s/chest_0" % house.id,
				"item_name": thing, "pos": [house.world_pos.x, house.world_pos.z], "target_name": house.display_name,
				"objective": "Steal %s from the chest in %s, in %s. Don't get caught. Bring it to %s." % [thing, house.display_name, house.town_name, s.name]}
		"excavate":
			# a ruin or other old place nearby; the artifact is buried there (a DigSpot appears)
			var options: Array[PlacedPOI] = []
			for p in _pois_near(from, 2800.0):
				if p.poi is SimplePOIData and p.poi.garrison != null:
					options.append(p)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 5) - 1)]
			var thing: String = ARTIFACT_FINDS[rng.randi_range(0, ARTIFACT_FINDS.size() - 1)]
			var where := _place_name(p)
			return {"type": type, "name": "Excavation: %s" % where, "target": p.id, "item_name": thing,
				"pos": [p.position.x, p.position.z], "target_name": where,
				"objective": "Dig up the %s at the %s (bring a pickaxe or shovel) and bring it to %s." % [thing, where, s.name]}
		"survey":
			# reach the bottom of a dungeon and defeat what lives there: the Society can then map it
			var options: Array[PlacedPOI] = []
			for p in _pois_near(from, 3000.0):
				var e := p.poi as DungeonEntrancePOIData
				if e != null and e.dungeon != null and e.dungeon.boss != null and not Discovery.is_cleared(p.id):
					options.append(p)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 4) - 1)]
			var where := _place_name(p)
			return {"type": type, "name": "Survey of the %s" % where, "target": p.id, "pos": [p.position.x, p.position.z], "target_name": where,
				"objective": "Reach the deepest hall of the %s and defeat its master, so the Society can map it. Then report to %s." % [where, s.name]}
		"hunt":
			# a named beast, met at a place out in the wild
			var options: Array[PlacedPOI] = []
			for p in _pois_near(from, 2400.0):
				if p.poi is SimplePOIData and p.poi.garrison != null:
					options.append(p)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 4) - 1)]
			var beast: String = BEASTS[rng.randi_range(0, BEASTS.size() - 1)]
			var where := _place_name(p)
			return {"type": type, "name": "The Hunt for %s" % beast, "target": p.id, "chief": beast,
				"pos": [p.position.x, p.position.z], "target_name": where,
				"objective": "Track down %s, seen near the %s, and kill it. Then report to %s." % [beast, where, s.name]}
		"persuade", "deliver", "assassinate":
			var r := _pick_person(town, rng, type == "persuade")
			if r == null:
				return {}
			var where := r.town.town.display_name
			var home := world.get_building(r.data.home_id)
			var pos := home.world_pos if home != null else r.town.position
			var q := {"type": type, "target": r.data.id, "target_name": r.data.display_name, "pos": [pos.x, pos.z]}
			match type:
				"persuade":
					q["name"] = "Winning Over %s" % r.data.display_name
					q["objective"] = "Make %s in %s like you (disposition %d): talk, admire, joke, or bribe. Then return to %s." % [r.data.display_name, where, PERSUADE_GOAL, s.name]
				"deliver":
					q["name"] = "Delivery to %s" % where
					q["item_name"] = "Sealed Package for %s" % r.data.display_name
					q["objective"] = "Deliver the sealed package to %s in %s. Ask them about a delivery." % [r.data.display_name, where]
				"assassinate":
					q["name"] = "Contract: %s" % r.data.display_name
					q["objective"] = "Kill %s in %s. A bonus if no one sees it. Then return to %s." % [r.data.display_name, where, s.name]
			return q
	return {}


func _pois_near(pos: Vector3, radius: float) -> Array[PlacedPOI]:
	var out: Array[PlacedPOI] = []
	for p in world.get_pois_near(pos, radius):
		if not p.poi is TownData:
			out.append(p)
	return out


func _place_name(p: PlacedPOI) -> String:
	var n := DialogueEngine.poi_topic_name(world, p)
	return n if n != "" else p.poi.display_name


# Other towns first (nearest few), then the giver's own
func _towns_for(town: PlacedPOI) -> Array[PlacedPOI]:
	var others: Array[PlacedPOI] = []
	for t in world.towns:
		if t != town:
			others.append(t)
	others.sort_custom(func(a: PlacedPOI, b: PlacedPOI) -> bool:
		return a.position.distance_squared_to(town.position) < b.position.distance_squared_to(town.position))
	others = others.slice(0, 3)
	if town != null:
		others.append(town)
	return others


func _pick_building(town: PlacedPOI, rng: RandomNumberGenerator, private_only: bool) -> BuildingPlot:
	for t in _towns_for(town):
		var options: Array[BuildingPlot] = []
		for b in t.town.buildings:
			if private_only and b.is_public():
				continue
			var resident: TownLife.Resident = world.life.get_owner_of(b.id) if world.life != null else null
			if resident != null and not resident.dead:
				options.append(b)
		if not options.is_empty():
			return options[rng.randi_range(0, options.size() - 1)]
	return null


func _pick_person(town: PlacedPOI, rng: RandomNumberGenerator, friendly_check: bool) -> TownLife.Resident:
	if world.life == null:
		return null
	for t in _towns_for(town):
		var options: Array = []
		for r: TownLife.Resident in world.life.get_town_residents(t.id):
			if r.dead or r.data.role == NpcData.Role.GUARD or r.data.role == NpcData.Role.GUILD_MEMBER:
				continue
			if friendly_check and DialogueState.get_disposition(r.data.id, r.data.base_disposition) >= PERSUADE_GOAL:
				continue
			options.append(r)
		if not options.is_empty():
			return options[rng.randi_range(0, options.size() - 1)]
	return null


# ---------------------------------------------------------------- progress

## Has the job's task been done (ready to report)?
func is_ready(q: Dictionary) -> bool:
	var inv := _player().get_node("Inventory") as Inventory
	match String(q["type"]):
		"retrieve", "steal", "excavate":
			return inv.has_item(QuestItems.get_item(String(q["id"]), String(q.get("item_name", ""))))
		"kill", "hunt":
			return WorldState.has_record("kill/quest/%s/chief" % q["id"])
		"survey":
			return Discovery.is_cleared(String(q["target"]))
		"persuade":
			var r: TownLife.Resident = world.life.get_resident(String(q["target"])) if world.life != null else null
			return r != null and DialogueState.get_disposition(r.data.id, r.data.base_disposition) >= PERSUADE_GOAL
		"assassinate":
			return WorldState.has_record("kill/" + String(q["target"]))
	return false


## Hands in a finished job: the reward, the item, the count toward promotion. Returns the gold.
func complete(q: Dictionary) -> int:
	var p := _player()
	var inv := p.get_node("Inventory") as Inventory
	if q.has("item_name"):
		var item := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
		if inv.has_item(item):
			inv.remove_item(item, inv.get_count(item))
	var gold := int(q["reward"])
	if q["type"] == "assassinate" and not bool(q.get("witnessed", false)):
		gold = roundi(gold * 1.5)
	Currency.add_gold(inv, gold)
	Factions.add_quest_done(String(q["faction"]))
	var skills := p.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_deed_xp(SkillDatabase.deed_xp(skills.get_player_level(), 5.0))  # a deed: helps past level 80
	q["status"] = "done"
	_update_quest(q)
	return gold


## CrimeManager tells us about a killing (for the assassination bonus)
func on_murder(victim: Enemy, witnessed: bool) -> void:
	var npc_id := String(victim.get_meta("npc_id", ""))
	for q: Dictionary in all_quests():
		if q["status"] == "active" and q["type"] == "assassinate" and q["target"] == npc_id:
			q["witnessed"] = witnessed
			_update_quest(q)


## ContainerComponent asks: should this chest hold a job's item? (Each item is placed once.)
func fill_container(c: ContainerComponent) -> void:
	if c.save_id == "":
		return
	if world != null and world.book != null:
		world.book.fill_container(c)
	for q: Dictionary in all_quests():
		if q["status"] == "active" and String(q.get("container", "")) == c.save_id and not bool(q.get("placed", false)):
			c.inventory.add_item(QuestItems.get_item(String(q["id"]), String(q["item_name"])))
			q["placed"] = true
			_update_quest(q)


## WorldManager asks when a camp's garrison is made: the bandit chiefs of kill jobs there
func on_garrison(placed: PlacedPOI, parent: Node3D) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var body := load(CHIEF_BODY) as EnemyData
	if body == null or placed == null:
		return out
	for q: Dictionary in all_quests():
		if q["status"] != "active" or q["target"] != placed.id:
			continue
		var zone := LevelCurve.zone_range(world.map, placed.position)
		if q["type"] == "excavate":
			_place_dig_spot(q, placed, zone.y)
			continue
		if q["type"] != "kill" and q["type"] != "hunt":
			continue
		var key := "quest/%s/chief" % q["id"]
		if WorldState.has_record("kill/" + key):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = key.hash()
		var at := placed.position + Vector3(2.0, 0.6, 2.0)
		at.y = world.get_height_at(at.x, at.z) + 0.6
		var kind := body if q["type"] == "kill" else load(BEAST_BODY) as EnemyData
		var e := Population.spawn_enemy(kind, zone.y + 2, parent, at, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
		e.display_name = String(q["chief"])
		e.set_meta("quest_id", q["id"])
		out.append(e)
	return out


# An excavation job's dig spot, on the place itself (it goes away with the place's chunk)
func _place_dig_spot(q: Dictionary, placed: PlacedPOI, level: int) -> void:
	if WorldState.has_record("dig/" + String(q["id"])):
		return
	var host := world.get_poi_node(placed.id)
	if host == null or host.get_node_or_null("Dig_" + String(q["id"])) != null:
		return
	var spot := DigSpot.new()
	spot.name = "Dig_" + String(q["id"])
	spot.quest_id = q["id"]
	spot.item_name = q["item_name"]
	spot.level = level
	var at := placed.position + Vector3(-5.0, 0.0, 4.0)
	at.y = world.get_height_at(at.x, at.z) + 0.1
	host.add_child(spot)
	spot.global_position = at


# ---------------------------------------------------------------- talking

## Extra topics this speaker has (a guild leader's membership, a delivery for the recipient...)
func extra_topics(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	var leader := Factions.leader_of(s, world)
	if leader != "":
		out.append("membership")
		out.append("duties")
		if Factions.is_member(leader):
			out.append("advancement")
		if leader == "thieves" and Factions.is_member("thieves") and not CrimeManager.bounties().is_empty():
			out.append("clear bounty")
	if not _delivery_for(s).is_empty():
		out.append("a delivery")
	if ClanTerritory.CLANS.has(leader):
		out.append("the territory war")
	var story := get_tree().get_first_node_in_group("story") as Story
	if story != null:
		out.append_array(story.topics_for(s))
	if world != null and world.book != null:
		out.append_array(world.book.topics_for(s))
	return out


func _delivery_for(s: DialogueEngine.Speaker) -> Dictionary:
	if s == null or s.id == "":
		return {}
	var inv := _player().get_node("Inventory") as Inventory
	for q: Dictionary in all_quests():
		if q["status"] == "active" and q["type"] == "deliver" and q["target"] == s.id:
			if inv.has_item(QuestItems.get_item(String(q["id"]), String(q["item_name"]))):
				return q
	return {}


## The answer for a job topic, or {} when it isn't one (DialogueEngine asks first)
func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	var story := get_tree().get_first_node_in_group("story") as Story
	if story != null:
		var told := story.respond(s, topic)
		if not told.is_empty():
			return told
	if world != null and world.book != null:
		var written := world.book.respond(s, topic)
		if not written.is_empty():
			return written
	var leader := Factions.leader_of(s, world)
	var p := _player()
	if topic == "a delivery":
		var q := _delivery_for(s)
		if q.is_empty():
			return {}
		var gold := complete(q)
		return _say("Ah, at last! Thank you. Here, for your trouble: %d gold." % gold, q)
	if leader == "":
		return {}
	if topic == "the territory war" and ClanTerritory.CLANS.has(leader):
		return _say("The clans war over the night of every land. %s Work for us where you would see us rule." % ClanTerritory.summary())
	var d := Factions.get_data(leader)
	var guild := d.display_name
	match topic:
		"membership":
			if Factions.is_member(leader):
				var n := Factions.next_rank(leader, p)
				var text := "You are a %s of the %s." % [d.rank_name(Factions.rank(leader)), guild]
				if n.has("name"):
					text += " To become a %s you need %d finished job%s and %s %d." % [n["name"], n["quests_needed"], "" if int(n["quests_needed"]) == 1 else "s", n["skill"], n["skill_needed"]]
				return _say(text)
			var why := Factions.join_problem(leader, p)
			if why != "":
				return _say(why)
			Factions.join(leader, p)
			if leader == "assassins":
				WorldState.set_record("assassins/invited", {"done": true})
			return _say("Then it's done. Welcome to the %s, %s. Ask me about duties when you want work, and about advancement when you've proven yourself." % [guild, d.rank_name(1)])
		"advancement":
			if not Factions.is_member(leader):
				return _say("You're not one of us.")
			var title := Factions.promote(leader, p)
			if title != "":
				return _say("You've earned it. From today you are a %s of the %s." % [title, guild])
			var n := Factions.next_rank(leader, p)
			return _say("Not yet. You still need %s." % n["why"] if String(n.get("why", "")) != "" and n.has("name") else String(n.get("why", "Not yet.")))
		"duties":
			if not Factions.is_member(leader):
				return _say("We only give work to members. Ask me about membership.")
			var q := active_for(leader)
			if not q.is_empty():
				if is_ready(q):
					var gold := complete(q)
					var extra := ""
					if q["type"] == "assassinate" and not bool(q.get("witnessed", false)):
						extra = " Clean work. No one saw a thing: there's extra in it for you."
					var promo := Factions.next_rank(leader, p)
					if bool(promo.get("ok", false)):
						extra += " Ask me about advancement."
					return _say("Well done. Here is your pay: %d gold.%s" % [gold, extra], q)
				return _say("You already have a job: %s" % q["objective"], q)
			var nq := offer(leader, s)
			if nq.is_empty():
				return _say("Nothing for you right now. Come back later.")
			return _say("I have a job for you. %s Pay is %d gold." % [nq["objective"], nq["reward"]], nq)
		"clear bounty":
			if leader != "thieves" or not Factions.is_member("thieves"):
				return {}
			var total := 0
			for v in CrimeManager.bounties().values():
				total += int(v)
			var cost := ceili(total * maxf(0.5 - 0.05 * Factions.rank("thieves"), 0.25))
			if total <= 0:
				return _say("You're not wanted anywhere. Keep it that way.")
			var inv := p.get_node("Inventory") as Inventory
			if Currency.get_gold(inv) < cost:
				return _say("Making %d gold of bounty go away costs %d. Come back when you have it." % [total, cost])
			Currency.spend_gold(inv, cost)
			for town_id in CrimeManager.bounties().keys():
				if world.crime != null:
					world.crime.set_bounty(town_id, 0)
				else:
					CrimeManager.set_bounty_raw(town_id, 0)
			return _say("Done. A few papers lost, a few guards paid. %d gold, and the guards forget your face." % cost)
	return {}


func _say(text: String, q: Dictionary = {}) -> Dictionary:
	return {"text": text, "journal": true, "quest_id": String(q.get("id", "")), "quest_name": String(q.get("name", "")), "learn": PackedStringArray()}


# ---------------------------------------------------------------- the Assassins Cult's contacts

func _process(delta: float) -> void:
	if world == null or get_tree().paused:
		return
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	_tick_stranger()


# After a first murder, a hooded stranger walks up to you one night
func _tick_stranger() -> void:
	var p := _player()
	if p == null:
		return
	if _stranger != null and is_instance_valid(_stranger):
		_stranger_time += 1.0
		var d := _stranger.global_position.distance_to(p.global_position)
		if _stranger_time > 120.0 or d > 80.0 or _stranger.is_dead():
			if not _stranger.is_dead():
				_stranger.queue_free()
			_stranger = null
			return
		if d > 3.0:
			_stranger.follow_route(PackedVector3Array([p.global_position]), false, 0.6)
		else:
			_stranger.stop_route()
			if not WorldState.has_record("assassins/invited"):
				var ui := get_tree().get_first_node_in_group("dialogue_ui") as DialogueUI
				if ui != null and ui.open_with(_stranger):
					WorldState.set_record("assassins/invited", {"done": true})
		return
	if Factions.is_member("assassins") or WorldState.has_record("assassins/invited"):
		return
	if int(WorldState.get_record(Factions.HISTORY).get("murders", 0)) <= 0:
		return
	if world.clock == null or not world.clock.is_night() or (world.dungeons != null and world.dungeons.is_inside()):
		return
	var behind := p.global_transform.basis.z
	behind.y = 0.0
	var at := p.global_position + behind.normalized() * 12.0
	at.y = world.get_height_at(at.x, at.z) + 0.5
	_stranger = _make_contact(world, at, "Hooded Stranger")
	_stranger.set_meta("greeting", "You've killed. Quietly or not, the Assassins Cult has noticed. If you have the stomach for more, ask me about membership.")
	_stranger_time = 0.0


# City inns at night: a hooded figure in the corner
func _on_entered(id: String) -> void:
	var b := world.get_building(id)
	if b == null or b.kind != BuildingPlot.Kind.INN or world.clock == null:
		return
	var town := world.get_poi(b.town_id)
	if town == null or (town.poi as TownData).kind != TownData.Kind.CITY:
		return
	if not WorldClock.hour_in_range(world.clock.hour, 21.0, 4.0):
		return
	var root := world.dungeons.get_interior_root()
	var seats: Array = world.dungeons.current_spots.get("seats", [])
	var spot: Vector3 = seats[seats.size() - 1] if not seats.is_empty() else Vector3(2, 0, 2)
	var e := _make_contact(root, root.to_global(spot + Vector3.UP * 0.2), "Hooded Figure")
	e.set_meta("greeting", "Sit. Speak softly. If you're here about the Assassins Cult, ask me about membership. If not, you never saw me.")


static func _make_contact(parent: Node, at: Vector3, name_shown: String) -> Enemy:
	var e := Enemy.new()
	e.display_name = name_shown
	e.talk_name = name_shown
	e.talk_lines = PackedStringArray(CONTACT_LINES)
	e.disposition = Enemy.Disposition.NEUTRAL
	e.placeholder_color = Color(0.12, 0.10, 0.12)
	e.max_health = 300.0
	e.persist_mode = Enemy.PersistMode.NEVER
	e.set_meta("leader_of", "assassins")
	var host := parent as Node3D
	e.position = host.to_local(at) if host != null and host.is_inside_tree() else at
	parent.add_child(e)
	return e


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
