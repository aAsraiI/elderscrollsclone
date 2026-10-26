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
## Once the task is done the job is "ready": a notice says so, the map and compass point back to
## whoever gave it, and their guild's leaders get a "report back" topic that hands it in.
## Every change of a job's state is printed as a [Quest] line (see QuestDebug for the console).
##
## The Assassins Cult: after your first murder, a hooded stranger finds you one night. Hooded
## figures also sit in city inns at night. They are the cult's contacts.
## Saved in WorldState: "quests" (every job, and the counter) and "assassins/invited".

const STATE := "quests"
const TOPICS: Array[String] = ["membership", "duties", "report back", "advancement", "leave the guild", "supplies", "clear bounty", "a delivery", "the territory war", "marriage", "our shop", "land for sale"]
const REPORT := "report back"
## The skill a kind of job trains when it is handed in
const SKILL_OF := {"retrieve": "athletics", "kill": "one_handed", "hunt": "archery", "steal": "security", "persuade": "speech",
	"deliver": "athletics", "assassinate": "sneak", "excavate": "athletics", "survey": "block"}
## Hours a guild waits after a finished job before it has another
const COOLDOWN_HOURS := 3.0
const COOLDOWN := "job_cooldown"
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
var _extra_cache := {}
var _extra_frame := -1
var _radiant_spawned := {}
var _leaving := {}  # guilds you asked to leave once (ask again to go)


func _ready() -> void:
	add_to_group("quests")
	world = get_parent() as WorldManager
	if world != null and world.dungeons != null:
		world.dungeons.entered.connect(_on_entered)
	_apply_perks.call_deferred()
	_listen_crime.call_deferred()
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
## Where active quests send you: [{"pos": Vector2, "name", "id"}] (guild jobs, the story, the book)
static func active_targets() -> Array:
	var out: Array = []
	if not bool(GameRules.get_rule("quest_markers")):
		return out
	for q: Dictionary in all_quests():
		if q["status"] == "active":
			# done: back to whoever gave it
			var at: Array = q["giver_pos"] if bool(q.get("ready", false)) and q.has("giver_pos") else q["pos"]
			out.append({"pos": Vector2(float(at[0]), float(at[1])), "name": String(q["name"]), "id": String(q["id"])})
	var raid := TerritoryWar.target()
	if not raid.is_empty():
		out.append(raid)
	var st := Story.target()
	if not st.is_empty():
		out.append(st)
	out.append_array(QuestBook.targets())
	var runner := QuestRunner.of(Engine.get_main_loop() as SceneTree)
	if runner != null:
		out.append_array(runner.targets())
	return out


# ---------------------------------------------------------------- the tracked quest

const TRACKED := "tracked_quest"


## The quest pinned from the journal ("" = none): the compass then shows only its target
static func tracked_id() -> String:
	var list := QuestTracker.tracked()
	return String(list[0]) if not list.is_empty() else ""


## Pins a quest to the compass, or unpins it if it is already the pinned one
static func toggle_tracked(id: String) -> void:
	QuestTracker.toggle(id)


## What the compass shows: the tracked quest's targets if it has any right now, else all of them
static func compass_targets() -> Array:
	var all := active_targets()
	var ids := QuestTracker.tracked()
	if ids.is_empty():
		return all
	var mine := all.filter(func(t: Dictionary) -> bool: return ids.has(String(t.get("id", ""))))
	return mine if not mine.is_empty() else all


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
			q["type"] = String(t)
			if Radiant.validate(self, q) == "":
				break  # every target checked: no impossible jobs
			q = {}
	if q.is_empty():
		return {}
	q["id"] = qid
	q["faction"] = faction
	q["giver"] = s.id
	q["giver_name"] = s.name
	q["giver_town"] = town.town.display_name if town != null else ""
	var back := s.home.world_pos if s.home != null else (s.position if s.position != Vector3.ZERO else (town.position if town != null else Vector3.ZERO))
	q["giver_pos"] = [back.x, back.z]
	q["status"] = "active"
	q["reward"] = d.reward_base + 40 * Factions.rank(faction) + 6 * _player_level() + rng.randi_range(0, 30)  # grows with rank and level
	q["offered_day"] = world.clock.day if world.clock != null else 1
	q["deadline_day"] = int(q["offered_day"]) + (5 if q["type"] == "deliver" else 14)
	q["skill"] = String(SKILL_OF.get(q["type"], ""))
	_finish_offer(q, s.name, rng)
	var list := all_quests().duplicate(true)
	list.append(q)
	_save_list(list, counter + 1)
	log_quest(q, "offered by %s (%s) and taken: %s" % [s.name, faction, q["objective"]])
	Notices.quest(get_tree(), "Quest started", String(q["name"]))
	if q["type"] == "deliver":
		var inv := _player().get_node("Inventory") as Inventory
		inv.add_item(QuestItems.get_item(qid, String(q["item_name"])))
	if q["type"] in ["kill", "hunt", "excavate"] and world.get_poi_node(String(q["target"])) != null:
		var placed := world.get_poi(String(q["target"]))
		for e in on_garrison(placed, world.get_poi_node(placed.id)):
			world.add_to_garrison(placed.id, e)
	return q


## A bounty from a town hall's board (BountyBoard): a bandit chief or a beast near the town.
## Returns the job (already saved), or {} if there is nothing to hunt nearby.
func offer_bounty(town: PlacedPOI, board_id: String) -> Dictionary:
	if world == null or town == null:
		return {}
	var counter := _counter()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|bounty|%s|%d" % [world.world_seed, town.id, counter]).hash()
	var board := DialogueEngine.Speaker.new()
	board.id = board_id
	board.name = "the bounty board in %s" % town.town.display_name
	board.town = town
	var qid := "q%d" % counter
	var q := {}
	for t in (["kill", "hunt"] if rng.randf() < 0.6 else ["hunt", "kill"]):
		q = _make(t, qid, town, board, rng)
		if not q.is_empty():
			break
	if q.is_empty():
		return {}
	var skills := _player().get_node_or_null("Skills") as Skills
	q["id"] = qid
	q["faction"] = "bounty"
	q["giver"] = board_id
	q["giver_name"] = board.name
	q["giver_town"] = town.town.display_name
	var seat := town.town.get_seat() if town.town != null else null
	var back := seat.world_pos if seat != null else town.position
	q["giver_pos"] = [back.x, back.z]
	q["status"] = "active"
	q["reward"] = 120 + 20 * (skills.get_player_level() if skills != null else 1) + rng.randi_range(0, 40)
	var list := all_quests().duplicate(true)
	list.append(q)
	_save_list(list, counter + 1)
	log_quest(q, "posted on %s and taken: %s" % [board.name, q["objective"]])
	if world.get_poi_node(String(q["target"])) != null:
		var placed := world.get_poi(String(q["target"]))
		for e in on_garrison(placed, world.get_poi_node(placed.id)):
			world.add_to_garrison(placed.id, e)
	return q


## The board's bounty that is still open (active), or {}
func bounty_of(board_id: String) -> Dictionary:
	for q: Dictionary in all_quests():
		if q["status"] == "active" and String(q.get("giver", "")) == board_id:
			return q
	return {}


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
				if p.poi is SimplePOIData and p.poi.garrison != null and p.poi.id != &"dragon_lair":
					options.append(p)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 4) - 1)]
			if s.id.begins_with("board:") and world.clock != null:  # the camp everyone talks about (Rumors)
				var trouble := Rumors.trouble_near(from, world.clock.day)
				for o in options:
					if o.id == trouble:
						p = o
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
				if p.poi is SimplePOIData and p.poi.garrison != null and p.poi.id != &"dragon_lair":
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
				if p.poi is SimplePOIData and p.poi.garrison != null and p.poi.id != &"dragon_lair":
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
	if Radiant.NEW_TYPES.has(type):
		return Radiant.make(self, type, town, s, rng)
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
	var radiant: Variant = Radiant.is_ready(self, q)
	if radiant != null:
		return bool(radiant)
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
	if q["type"] == "steal" and not bool(q.get("witnessed", false)):
		gold += roundi(gold * 0.25)  # bonus: nobody saw a thing
	if q["type"] == "retrieve" and Discovery.is_cleared(String(q.get("target", ""))):
		gold += roundi(gold * 0.25)  # bonus: the place was cleared too
	gold += Radiant.hand_over(self, q, gold)
	Currency.add_gold(inv, gold)
	var loot := _loot_reward(q)
	if loot != null:
		inv.add_item(loot, 1)
		q["loot"] = loot.display_name
	Factions.add_quest_done(String(q["faction"]))
	var skills := p.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_deed_xp(SkillDatabase.deed_xp(skills.get_player_level(), 5.0))  # a deed: helps past level 80
		if String(q.get("skill", "")) != "":
			skills.add_xp(StringName(q["skill"]), 25.0 + 5.0 * Factions.rank(String(q["faction"])))
	if Factions.get_data(String(q["faction"])) != null:
		Reputation.add(String(q["faction"]), 3)
	Reputation.add_fame(String(q.get("giver_town", "")), 1)
	q["done_day"] = world.clock.day if world != null and world.clock != null else 1
	var cool := WorldState.get_record(COOLDOWN).duplicate()
	cool[String(q["faction"])] = _hours() + COOLDOWN_HOURS
	WorldState.set_record(COOLDOWN, cool)
	q["status"] = "done"
	_update_quest(q)
	log_quest(q, "handed in: %d gold" % gold)
	Rumors.on_job_done(q)
	Notices.quest(get_tree(), "Quest completed", "%s: %d gold" % [q["name"], gold])
	return gold


## Ends a job without its reward (the debug console, or a job that can no longer be done)
func fail(q: Dictionary, why: String) -> void:
	if q.is_empty() or q["status"] != "active":
		return
	q["status"] = "failed"
	q["fail_reason"] = why
	_update_quest(q)
	log_quest(q, "failed: " + why)
	_journal(q, "Failed: %s. %s" % [q["name"], why])
	Notices.quest(get_tree(), "Quest failed", "%s: %s" % [q["name"], why], true)


## Why an active job can no longer be done ("" = it still can): out of time, the person dead, the
## package lost, seen while stealing
func failure(q: Dictionary) -> String:
	var new_kind := Radiant.failure(q)
	if new_kind != "":
		return new_kind
	var day := world.clock.day if world != null and world.clock != null else 1
	if q.has("deadline_day") and day > int(q["deadline_day"]) and q["faction"] != "bounty":
		return "You ran out of time."
	var t := String(q.get("type", ""))
	if t in ["persuade", "deliver"] and world != null and world.life != null:
		var r: TownLife.Resident = world.life.get_resident(String(q["target"]))
		if r == null or r.dead:
			return "%s is dead." % q.get("target_name", "They")
	if t == "deliver":
		var inv := _player().get_node("Inventory") as Inventory
		if not inv.has_item(QuestItems.get_item(String(q["id"]), String(q["item_name"]))):
			return "The package is lost."
	if t == "steal" and bool(q.get("caught", false)):
		return "You were seen. The guild wants nothing traced back to it."
	return ""


## Gives up a job: the guild thinks less of you
func abandon(q: Dictionary) -> void:
	if q.is_empty() or q["status"] != "active":
		return
	q["status"] = "abandoned"
	_update_quest(q)
	if Factions.get_data(String(q["faction"])) != null:
		Reputation.add(String(q["faction"]), -5)
	log_quest(q, "abandoned")
	_journal(q, "Abandoned: %s." % q["name"])
	Notices.quest(get_tree(), "Quest abandoned", String(q["name"]), true)


# CrimeManager: a theft was seen. Inside a steal job's house, the job is blown.
func _on_crime(kind: String, town_id: String, bounty: int, witnessed: bool) -> void:
	if witnessed and world != null and world.get_poi(town_id) != null and world.get_poi(town_id).town != null:
		Reputation.add_infamy(world.get_poi(town_id).town.display_name, maxi(bounty / 20, 1))  # the town remembers
	if kind != "theft" or not witnessed or world == null or world.dungeons == null:
		return
	var root := world.dungeons.get_interior_root()
	var inside := String(root.get_meta("building_id", "")) if root != null else ""
	for q: Dictionary in all_quests():
		if q["status"] == "active" and q["type"] == "steal" and String(q["target"]) == inside:
			q["caught"] = true
			q["witnessed"] = true
			_update_quest(q)


## Hours until this guild has another job (0 = now)
static func cooldown_left(faction: String, now_hours: float) -> float:
	return maxf(float(WorldState.get_record(COOLDOWN).get(faction, 0.0)) - now_hours, 0.0)


func _hours() -> float:
	var clock := world.clock if world != null else null
	return float(clock.day) * 24.0 + clock.hour if clock != null else 0.0


func _player_level() -> int:
	var sk := _player().get_node_or_null("Skills") as Skills if _player() != null else null
	return sk.get_player_level() if sk != null else 1


## Prints a job's change of state as a [Quest] line in the output
static func log_quest(q: Dictionary, what: String) -> void:
	print("[Quest] %s \"%s\": %s" % [q.get("id", "?"), q.get("name", ""), what])


# Once per job: its task is done, so say where to hand it in
func _check_ready() -> void:
	if _player() == null:
		return
	for q: Dictionary in all_quests():
		if q["status"] != "active":
			continue
		var why := failure(q)
		if why != "":
			fail(q, why)
			continue
		var now := is_ready(q)
		if now == bool(q.get("ready", false)):
			continue
		var q2 := q.duplicate(true)
		if not now:  # the item was dropped or sold: back to the task
			q2["ready"] = false
			_update_quest(q2)
			log_quest(q2, "no longer ready")
			continue
		q2["ready"] = true
		_update_quest(q2)
		var who := String(q2.get("giver_name", "whoever gave it"))
		var town := String(q2.get("giver_town", ""))
		var where := "%s in %s" % [who, town] if town != "" and not who.contains(town) else who
		var how := "Use the board again." if q2["faction"] == "bounty" else "Ask about \"%s\"." % REPORT
		log_quest(q2, "ready to hand in to %s" % where)
		_journal(q2, "Done. Now report back to %s. %s" % [where, how])
		Notices.quest(get_tree(), "Ready to turn in", "%s: report back to %s" % [q2["name"], where])


func _journal(q: Dictionary, text: String) -> void:
	var clock := world.clock if world != null else null
	DialogueState.add_journal({"text": text, "speaker": "", "topic": "", "day": clock.day if clock != null else 1,
		"time": clock.get_time_text() if clock != null else "", "quest_id": String(q.get("id", "")), "quest_name": String(q.get("name", ""))})


## CrimeManager tells us about a killing (for the assassination bonus)
func on_murder(victim: Enemy, witnessed: bool) -> void:
	var npc_id := String(victim.get_meta("npc_id", ""))
	# killing one of your own guild, seen: you are thrown out
	var r: TownLife.Resident = world.life.get_resident(npc_id) if world != null and world.life != null and npc_id != "" else null
	if r != null and witnessed and Factions.get_data(r.data.faction) != null and Factions.is_member(r.data.faction):
		Factions.expel_for_crime(r.data.faction, "you murdered %s." % r.data.display_name)
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
			if bool(q.get("twist", false)):
				q["placed"] = true  # someone got here first: the chest is empty
				_update_quest(q)
				_journal(q, "The chest has been emptied. Fresh tracks lead back out of the %s: whoever took the %s is still near." % [q.get("target_name", "place"), q["item_name"]])
				continue
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
		var kind := _biome_body(q, placed, body if q["type"] == "kill" else load(BEAST_BODY) as EnemyData)
		# harder with the player: chief level follows the zone and the player's level
		var lvl := maxi(zone.y + 2, _player_level() + int(q.get("tier", 0)))
		var e := Population.spawn_enemy(kind, lvl, parent, at, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
		e.display_name = String(q["chief"])
		e.set_meta("quest_id", q["id"])
		e.set_meta("quest_critical", true)
		if q.has("proof") and e.inventory != null:
			e.inventory.add_item(QuestItems.get_item(String(q["id"]) + "_proof", String(q["proof"])))  # proof of the kill
		out.append(e)
		if q["type"] == "kill":
			for n in 2:  # the chief's escort
				var ekey := "quest/%s/escort%d" % [q["id"], n]
				if WorldState.has_record("kill/" + ekey):
					continue
				var epos := at + Vector3(2.5 * (n * 2 - 1), 0.0, -2.0)
				epos.y = world.get_height_at(epos.x, epos.z) + 0.6
				var guard := Population.spawn_enemy(load("res://data/enemies/bandit_thug.tres") as EnemyData, lvl - 2, parent, epos, rng, {"key": ekey, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
				guard.set_meta("quest_id", q["id"])
				out.append(guard)
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
	# the dialogue asks once per known topic: work it out once a frame per person (until something changes)
	var frame := Engine.get_process_frames() * 100000 + WorldState.version
	if frame != _extra_frame:
		_extra_frame = frame
		_extra_cache.clear()
	var key := "%s|%s|%d|%d" % [s.id, s.name, int(s.role), s.enemy.get_instance_id() if s.enemy != null and is_instance_valid(s.enemy) else 0]
	if not _extra_cache.has(key):
		_extra_cache[key] = _extra_topics(s)
	return _extra_cache[key]


func _extra_topics(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	var leader := Factions.leader_of(s, world)
	if leader != "":
		out.append("membership")
		out.append("duties")
		if Factions.is_member(leader):
			out.append("advancement")
			out.append("leave the guild")
			var job := active_for(leader)
			if not job.is_empty() and is_ready(job):
				out.append(REPORT)
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
	if world != null and world.runner != null:
		out.append_array(world.runner.topics_for(s))
	out.append_array(Radiant.topics_for(self, s))
	if s.data != null and s.role == NpcData.Role.MERCHANT and leader == "":
		var own := _job_given_by(s)
		if own.is_empty():
			out.append("supplies")  # shopkeepers have errands too
		elif is_ready(own):
			out.append(REPORT)
	out.append_array(Marriage.topics_for(s))
	out.append_array(Homestead.topics_for(s))
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
	_extra_cache.clear()  # what is said may change who has which topics
	var story := get_tree().get_first_node_in_group("story") as Story
	if story != null:
		var told := story.respond(s, topic)
		if not told.is_empty():
			return told
	if world != null and world.book != null:
		var written := world.book.respond(s, topic)
		if not written.is_empty():
			return written
	if world != null and world.runner != null:
		var handmade := world.runner.respond(s, topic)
		if not handmade.is_empty():
			return handmade
	var wed := Marriage.respond(s, topic, _player(), world.clock.day if world != null and world.clock != null else 1)
	if not wed.is_empty():
		return wed
	var land := Homestead.respond(s, topic, _player(), world, world.clock.day if world != null and world.clock != null else 1)
	if not land.is_empty():
		return land
	var other_way := Radiant.respond(self, s, topic)
	if not other_way.is_empty():
		return other_way
	if topic == "supplies" and s.role == NpcData.Role.MERCHANT and _job_given_by(s).is_empty():
		var sq := offer("merchants", s, "gather")
		if sq.is_empty():
			return _say("Nothing I need just now.")
		return _say("I'm running short. %s I'll pay %d gold." % [sq["objective"], sq["reward"]], sq)
	if topic == REPORT and Factions.leader_of(s, world) == "":
		var mine := _job_given_by(s)
		if not mine.is_empty() and is_ready(mine):
			var paid := complete(mine)
			return _say("Just what I needed. Here: %d gold.%s" % [paid, (" And take this %s." % mine["loot"]) if mine.has("loot") else ""], mine)
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
		"leave the guild":
			if not Factions.is_member(leader):
				return {}
			if not _leaving.has(leader):
				_leaving[leader] = true
				return _say("Leave the %s? Ask me again if you mean it. You would come back a rank lower." % guild)
			_leaving.erase(leader)
			Factions.leave(leader)
			return _say("So be it. Your name is struck from our rolls.")
		"duties", REPORT:
			if not Factions.is_member(leader):
				return _say("We only give work to members. Ask me about membership.")
			if Reputation.get_rep(leader) <= -10:
				return _say("After what you've done? Earn back our trust first.")
			var q := active_for(leader)
			if topic == REPORT and (q.is_empty() or not is_ready(q)):
				return _say("You've nothing to report yet." if q.is_empty() else "Not done yet. %s" % q["objective"], q)
			if not q.is_empty():
				if is_ready(q):
					var gold := complete(q)
					var extra := ""
					if q["type"] == "assassinate" and not bool(q.get("witnessed", false)):
						extra = " Clean work. No one saw a thing: there's extra in it for you."
					var promo := Factions.next_rank(leader, p)
					if bool(promo.get("ok", false)):
						extra += " Ask me about advancement."
					if q.has("item_name") and q["type"] != "deliver":
						extra = " [You hand over the %s.]" % q["item_name"] + extra
					return _say("Well done. Here is your pay: %d gold.%s" % [gold, extra], q)
				return _say("You already have a job: %s" % q["objective"], q)
			var wait := cooldown_left(leader, _hours())
			if wait > 0.0:
				return _say("Nothing yet. Come back in %d hour%s." % [ceili(wait), "" if ceili(wait) == 1 else "s"])
			var day := world.clock.day if world.clock != null else 1
			var home := s.town.id if s.town != null else ""
			if Radiant.town_count(home, day) >= Radiant.TOWN_LIMIT:
				return _say("That's all the work this town has today. Come back tomorrow.")
			var nq := offer(leader, s)
			if nq.is_empty():
				return _say("Nothing for you right now. Come back later.")
			Radiant.count_town(home, day)
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
	_check_ready()
	_tend_chiefs()
	Radiant.tend(self, _radiant_spawned)
	if world.clock != null:
		Rumors.daily(world, world.clock.day)
	_tend_thieves()


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
	var e := Enemy.create()
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


func _listen_crime() -> void:
	if world != null and world.crime != null and not world.crime.crime_reported.is_connected(_on_crime):
		world.crime.crime_reported.connect(_on_crime)


# A kill or hunt job's chief belongs at its camp whenever the camp is loaded. After loading a save
# the camp may have been built before the jobs came back: put the chief there now.
func _tend_chiefs() -> void:
	if world == null:
		return
	for q: Dictionary in all_quests():
		if q["status"] != "active" or not (q["type"] in ["kill", "hunt"]):
			continue
		var id := String(q["target"])
		if not world._garrisons.has(id) or WorldState.has_record("kill/quest/%s/chief" % q["id"]):
			continue
		var there := false
		for e in world.get_garrison(id):
			there = there or (is_instance_valid(e) and String(e.spawn_key) == "quest/%s/chief" % q["id"])
		if not there:
			for e in on_garrison(world.get_poi(id), world._garrison_root if world._garrison_root != null else world):
				world.add_to_garrison(id, e)


# The finishing touches of a new job: its wording from its RadiantTemplate, a reward on the
# template's curve, the template's deadline, the "already taken" twist, a chief's signet
func _finish_offer(q: Dictionary, giver_name: String, rng: RandomNumberGenerator) -> void:
	if q.has("town_name") == false and q.has("target_town"):
		q["town_name"] = q["target_town"]
	if q["type"] == "steal" and world.get_building(String(q["target"])) != null:
		q["town_name"] = world.get_building(String(q["target"])).town_name
		q["target_house"] = world.get_building(String(q["target"])).display_name
	if q["type"] in ["kill"]:
		q["proof"] = "%s's Signet" % String(q["chief"]).get_slice(" the ", 0)
	if q["type"] == "persuade":
		q["count"] = PERSUADE_GOAL
	if q["type"] in ["persuade", "deliver", "assassinate"] and world.life != null:
		var r: TownLife.Resident = world.life.get_resident(String(q["target"]))
		if r != null:
			q["town_name"] = r.town.town.display_name
	if q["type"] == "retrieve" and rng.randf() < Radiant.TWIST_CHANCE:
		q["twist"] = true  # someone got there first: a thief near the entrance has it
		var p := world.get_poi(String(q["target"]))
		if p != null:
			q["at"] = [p.position.x + 8.0, p.position.y, p.position.z + 8.0]
	Radiant.word(q, giver_name, _player_level(), rng)
	var t := Radiant.template(String(q["type"]))
	if t != null:
		q["reward"] = maxi(int(q.get("reward", 0)), int(q.get("template_reward", 0)) + rng.randi_range(0, 30))
	if Factions.get_data(String(q.get("faction", ""))) != null and Reputation.get_rep(String(q["faction"])) >= 30:
		q["reward"] = roundi(int(q["reward"]) * 1.1)  # a respected member gets the better-paid work
		if t.days > 0:
			q["deadline_day"] = int(q.get("offered_day", 1)) + t.days


# The kind of creature a kill or hunt job sends you after, by the land it is in (RadiantTemplate)
func _biome_body(q: Dictionary, placed: PlacedPOI, fallback: EnemyData) -> EnemyData:
	var t := Radiant.template(String(q["type"]))
	var biome := world.get_biome_at(placed.position.x, placed.position.z) if world != null else null
	if t == null or biome == null:
		return fallback
	var path := "res://data/enemies/%s.tres" % t.enemy_for(biome.get_key())
	return load(path) as EnemyData if ResourceLoader.exists(path) else fallback


# A retrieve job's "already taken" twist: the thief waits near the entrance with the item
func _tend_thieves() -> void:
	var p := _player()
	if p == null or world == null or (world.dungeons != null and world.dungeons.is_inside()):
		return
	for q: Dictionary in all_quests():
		if q["status"] != "active" or not bool(q.get("twist", false)) or not q.has("at") or is_ready(q):
			continue
		var at := Vector3(float(q["at"][0]), float(q["at"][1]), float(q["at"][2]))
		if Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() > Radiant.SPAWN_NEAR:
			continue
		Radiant._want(self, _radiant_spawned, q, "thief", 1, "bandit_thug", at, true)
		var e: Enemy = _radiant_spawned.get("quest/%s/thief0" % q["id"])
		var item := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
		if e != null and is_instance_valid(e) and e.inventory != null and not e.inventory.has_item(item) and not e.is_dead():
			e.display_name = "Thief"
			e.inventory.add_item(item)


## Takes a notice board offer (Radiant.board_offers): it becomes a job given by the board
func take_offer(offer: Dictionary, board_id: String, town: PlacedPOI) -> Dictionary:
	if world == null or offer.is_empty():
		return {}
	var day := world.clock.day if world.clock != null else 1
	if day >= int(offer.get("expires_day", day + 1)):
		return {}  # the notice came down
	var counter := _counter()
	var q := offer.duplicate(true)
	q["id"] = "q%d" % counter
	q["faction"] = "board"
	q["giver"] = board_id
	q["giver_name"] = "the notice board in %s" % town.town.display_name
	q["giver_town"] = town.town.display_name
	q["giver_pos"] = [town.position.x, town.position.z]
	q["status"] = "active"
	q["reward"] = int(offer.get("template_reward", 100))
	q["offered_day"] = day
	q["deadline_day"] = day + maxi(Radiant.template(String(q["type"])).days if Radiant.template(String(q["type"])) != null else 7, 3)
	q["skill"] = String(SKILL_OF.get(q["type"], ""))
	var list := all_quests().duplicate(true)
	list.append(q)
	_save_list(list, counter + 1)
	Radiant.count_town(town.id, day)
	log_quest(q, "taken from %s: %s" % [q["giver_name"], q["objective"]])
	Notices.quest(get_tree(), "Quest started", String(q["name"]))
	if q["type"] == "deliver":
		(_player().get_node("Inventory") as Inventory).add_item(QuestItems.get_item(String(q["id"]), String(q["item_name"])))
	return q


## The active job this person gave (a shopkeeper's errand), or {}
func _job_given_by(s: DialogueEngine.Speaker) -> Dictionary:
	for q: Dictionary in all_quests():
		if q["status"] == "active" and String(q.get("giver", "")) == s.id and s.id != "":
			return q
	return {}


# A job's pay sometimes includes something from the loot tables, around your level
func _loot_reward(q: Dictionary) -> ItemData:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|loot" % q["id"]).hash()
	if rng.randf() > 0.35:
		return null
	var lvl := _player_level()
	var table := ItemCatalog.curve_loot(lvl, lvl + 3, 1.0)
	if table.is_empty():
		return null
	var e: LootEntry = table[rng.randi_range(0, table.size() - 1)]
	return e.item if e != null else null
