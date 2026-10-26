class_name Radiant
extends RefCounted
## The radiant job generator, version 2. QuestManager makes the classic jobs (retrieve, kill,
## steal, persuade, deliver, assassinate, hunt, excavate, survey); this adds the rest, words them
## all from RadiantTemplate files (data/radiant/), and runs what they need in the world:
##   gather       carry N of a real item (herbs, ore, hides) to the giver
##   rescue       a captive held at a camp: kill the guards, reach the captive
##   escort       someone walks with you from the giver's town to another town
##   investigate  go and look at a place; what you find is written down
##   protect      raiders strike a farm: be there and kill them all
##   road         highwaymen wait on the road between two towns
## Also: the "already taken" twist on retrieve jobs (a thief has it), escorts and a signet for
## bandit chiefs, other ways through persuade and steal jobs (a favour, what you know, buying it,
## asking for it), checks that every target exists before a job is offered, limits per town, and
## the notice boards' rotating offers (NoticeBoard).

const DIR := "res://data/radiant/"
const NEW_TYPES := ["gather", "rescue", "escort", "investigate", "protect", "road"]
const BOARD_TYPES := ["gather", "rescue", "escort", "investigate", "protect", "road", "deliver"]
const SPAWN_NEAR := 120.0
const SPAWN_FAR := 220.0
## A notice board's offers change every BOARD_DAYS days; it shows BOARD_OFFERS at a time
const BOARD_DAYS := 3
const BOARD_OFFERS := 3
## Jobs a town's board and people hand out per day at most
const TOWN_LIMIT := 3
## The chance a retrieve job's item was already taken by someone else
const TWIST_CHANCE := 0.25
## Speech needed for the "talk them round" option on persuade jobs
const SPEECH_CHECK := 50

static var _templates := {}


static func template(type: String) -> RadiantTemplate:
	if not _templates.has(type):
		var path := DIR + type + ".tres"
		_templates[type] = load(path) as RadiantTemplate if ResourceLoader.exists(path) else null
	return _templates[type]


## Words a job from its template: a name and objective picked by the job's own seed, the reward
## grown with the player's level (difficulty tiers), the deadline in days
static func word(q: Dictionary, giver_name: String, player_level: int, rng: RandomNumberGenerator) -> void:
	var t := template(String(q["type"]))
	if t == null:
		return
	var fill := {"{thing}": q.get("item_name", q.get("thing", "")), "{place}": q.get("target_name", ""), "{target}": q.get("target_name", ""),
		"{chief}": q.get("chief", ""), "{giver}": giver_name, "{town}": q.get("town_name", q.get("target_town", "")),
		"{count}": str(q.get("count", "")), "{destination}": q.get("destination_name", "")}
	if q.has("target_house"):
		fill["{target}"] = q["target_house"]
	if t.names.size() > 0:
		q["name"] = _fill(t.names[rng.randi_range(0, t.names.size() - 1)], fill)
	if t.objectives.size() > 0:
		q["objective"] = _fill(t.objectives[rng.randi_range(0, t.objectives.size() - 1)], fill)
	q["tier"] = clampi(player_level / 10, 0, 9)
	q["template_reward"] = t.reward_base + t.reward_per_level * player_level


static func _fill(text: String, fill: Dictionary) -> String:
	for k in fill:
		text = text.replace(k, String(fill[k]))
	return text


# ---------------------------------------------------------------- making the new kinds

static func make(qm: QuestManager, type: String, town: PlacedPOI, s: DialogueEngine.Speaker, rng: RandomNumberGenerator) -> Dictionary:
	var world := qm.world
	var t := template(type)
	if t == null or town == null:
		return {}
	var biome := world.get_biome_at(town.position.x, town.position.z)
	var bkey := biome.get_key() if biome != null else ""
	var count := rng.randi_range(t.count_min, maxi(t.count_min, t.count_max))
	match type:
		"gather":
			var path := t.things[rng.randi_range(0, t.things.size() - 1)]
			var it := load(path) as ItemData if ResourceLoader.exists(path) else null
			if it == null:
				return {}
			return {"type": type, "name": "", "target": path, "item_path": path, "thing": it.display_name, "count": count,
				"pos": [town.position.x, town.position.z], "target_name": town.town.display_name, "town_name": town.town.display_name}
		"rescue":
			var camp := _camp_near(qm, town.position, rng)
			if camp == null:
				return {}
			var who := "%s %s" % [t.things[rng.randi_range(0, t.things.size() - 1)], NameGen.FIRST[rng.randi_range(0, NameGen.FIRST.size() - 1)]]
			return {"type": type, "target": camp.id, "target_name": who, "place_name": qm._place_name(camp), "count": count,
				"enemy": t.enemy_for(bkey), "at": [camp.position.x, camp.position.y, camp.position.z], "pos": [camp.position.x, camp.position.z],
				"town_name": town.town.display_name}
		"escort":
			var dest := _other_town(qm, town, rng)
			if dest == null:
				return {}
			var who := t.things[rng.randi_range(0, t.things.size() - 1)]
			return {"type": type, "target": dest.id, "target_name": who.capitalize(), "destination_name": dest.town.display_name,
				"at": [town.position.x + 6.0, town.position.y, town.position.z + 6.0], "pos": [dest.position.x, dest.position.z],
				"town_name": town.town.display_name}
		"investigate":
			var options: Array[PlacedPOI] = qm._pois_near(town.position, 2400.0)
			if options.is_empty():
				return {}
			var p := options[rng.randi_range(0, mini(options.size(), 6) - 1)]
			return {"type": type, "target": p.id, "target_name": qm._place_name(p), "clue": t.things[rng.randi_range(0, t.things.size() - 1)],
				"at": [p.position.x, p.position.y, p.position.z], "pos": [p.position.x, p.position.z], "town_name": town.town.display_name}
		"protect":
			var farm: BuildingPlot = null
			for tt in qm._towns_for(town):
				for b in tt.town.buildings:
					if b.kind == BuildingPlot.Kind.FARM and farm == null:
						farm = b
			if farm == null:
				return {}
			return {"type": type, "target": farm.id, "target_name": farm.display_name, "target_house": farm.display_name, "count": count,
				"enemy": t.enemy_for(bkey), "at": [farm.world_pos.x, farm.world_pos.y, farm.world_pos.z], "pos": [farm.world_pos.x, farm.world_pos.z],
				"town_name": farm.town_name}
		"road":
			var dest := _other_town(qm, town, rng)
			if dest == null:
				return {}
			var mid := town.position.lerp(dest.position, rng.randf_range(0.35, 0.65))
			mid.y = world.get_height_at(mid.x, mid.z)
			return {"type": type, "target": dest.id, "target_name": "the %s road" % dest.town.display_name, "destination_name": dest.town.display_name,
				"count": count, "enemy": t.enemy_for(bkey), "at": [mid.x, mid.y, mid.z], "pos": [mid.x, mid.z], "town_name": town.town.display_name}
	return {}


static func _camp_near(qm: QuestManager, from: Vector3, rng: RandomNumberGenerator) -> PlacedPOI:
	var options: Array[PlacedPOI] = []
	for p in qm._pois_near(from, 2200.0):
		if p.poi.is_camp():
			options.append(p)
	return options[rng.randi_range(0, mini(options.size(), 4) - 1)] if not options.is_empty() else null


static func _other_town(qm: QuestManager, town: PlacedPOI, rng: RandomNumberGenerator) -> PlacedPOI:
	var others := qm._towns_for(town).filter(func(t: PlacedPOI) -> bool: return t != town)
	return others[rng.randi_range(0, others.size() - 1)] if not others.is_empty() else null


## Is a job of one of the new kinds done? (null: not one of them)
static func is_ready(qm: QuestManager, q: Dictionary) -> Variant:
	var id := String(q["id"])
	match String(q["type"]):
		"gather":
			var it := load(String(q["item_path"])) as ItemData
			return it != null and (qm._player().get_node("Inventory") as Inventory).get_count(it) >= int(q["count"])
		"rescue":
			return _all_dead(id, "guard", int(q["count"])) and WorldState.has_record("quest/%s/freed" % id)
		"escort":
			return WorldState.has_record("quest/%s/arrived" % id)
		"investigate":
			return WorldState.has_record("quest/%s/seen" % id)
		"protect", "road":
			return _all_dead(id, "raider", int(q["count"]))
	return null


static func _all_dead(id: String, role: String, n: int) -> bool:
	for i in n:
		if not WorldState.has_record("kill/quest/%s/%s%d" % [id, role, i]):
			return false
	return true


## Why one of the new kinds can no longer be done ("" = it can)
static func failure(q: Dictionary) -> String:
	if String(q["type"]) == "escort" and WorldState.has_record("kill/quest/%s/escort" % q["id"]):
		return "%s was killed on the road." % q.get("target_name", "They")
	if String(q["type"]) == "rescue" and WorldState.has_record("kill/quest/%s/captive" % q["id"]):
		return "%s died." % q.get("target_name", "The captive")
	return ""


## Hands in what a job needs (gathered items, the chief's signet for a bonus). Returns extra gold.
static func hand_over(qm: QuestManager, q: Dictionary, gold: int) -> int:
	var inv := qm._player().get_node("Inventory") as Inventory
	if String(q["type"]) == "gather":
		var it := load(String(q["item_path"])) as ItemData
		if it != null:
			inv.remove_item(it, mini(int(q["count"]), inv.get_count(it)))
	if q.has("proof"):
		var token := QuestItems.get_item(String(q["id"]) + "_proof", String(q["proof"]))
		if inv.has_item(token):
			inv.remove_item(token, inv.get_count(token))
			return roundi(gold * 0.2)  # the signet proves it: a little extra
	return 0


# ---------------------------------------------------------------- the world: spawns and arrivals

## Once a second: spawns what jobs need near you, moves escorts along, notices arrivals
static func tend(qm: QuestManager, spawned: Dictionary) -> void:
	var world := qm.world
	var p := qm._player()
	if p == null or world == null:
		return
	var inside := world.dungeons != null and world.dungeons.is_inside()
	for q: Dictionary in QuestManager.all_quests():
		if q["status"] != "active" or not q.has("at"):
			continue
		var id := String(q["id"])
		var at := Vector3(float(q["at"][0]), float(q["at"][1]), float(q["at"][2]))
		var near := not inside and Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() < SPAWN_NEAR
		match String(q["type"]):
			"investigate":
				if near and Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() < 30.0 and not WorldState.has_record("quest/%s/seen" % id):
					WorldState.set_record("quest/%s/seen" % id, {"done": true})
					qm._journal(q, "At the %s: %s. %s should hear of it." % [q["target_name"], q["clue"], q.get("giver_name", "The one who sent you")])
					Notices.quest(qm.get_tree(), "Clue found", String(q["clue"]).capitalize())
			"rescue":
				if near:
					_want(qm, spawned, q, "guard", int(q["count"]), String(q["enemy"]), at, true)
					_want_person(qm, spawned, q, "captive", String(q["target_name"]), at + Vector3(3, 0, 3))
				var cap: Enemy = spawned.get("quest/%s/captive" % id)
				if cap != null and is_instance_valid(cap) and _all_dead(id, "guard", int(q["count"])) and cap.global_position.distance_to(p.global_position) < 6.0 \
						and not WorldState.has_record("quest/%s/freed" % id):
					WorldState.set_record("quest/%s/freed" % id, {"done": true})
					cap.set_meta("greeting", "Thank you! I'll find my own way home now. Tell them I'm safe.")
					Notices.quest(qm.get_tree(), "Objective complete", "%s is free" % q["target_name"])
			"escort":
				_tend_escort(qm, spawned, q, at, p)
			"protect", "road":
				if near:
					_want(qm, spawned, q, "raider", int(q["count"]), String(q["enemy"]), at, true)
	for key in spawned.keys():
		var e: Enemy = spawned[key]
		if not is_instance_valid(e):
			spawned.erase(key)
		elif not e.is_dead() and e.global_position.distance_to(p.global_position) > SPAWN_FAR and not String(key).ends_with("/escort"):
			e.queue_free()
			spawned.erase(key)


static func _want(qm: QuestManager, spawned: Dictionary, q: Dictionary, role: String, n: int, enemy: String, at: Vector3, hostile: bool) -> void:
	var path := "res://data/enemies/%s.tres" % enemy
	var body := load(path) as EnemyData if ResourceLoader.exists(path) else load("res://data/enemies/bandit.tres") as EnemyData
	var world := qm.world
	var zone := LevelCurve.zone_range(world.map, at) if world.map != null else Vector2i(1, 5)
	for i in n:
		var key := "quest/%s/%s%d" % [q["id"], role, i]
		if WorldState.has_record("kill/" + key) or (spawned.has(key) and is_instance_valid(spawned[key])):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = key.hash()
		var pos := at + Vector3(rng.randf_range(-7, 7), 0.0, rng.randf_range(-7, 7))
		pos.y = world.get_height_at(pos.x, pos.z) + 0.6
		var e := Population.spawn_enemy(body, maxi(zone.y, qm._player_level()), world, pos, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
		e.set_meta("quest_id", q["id"])
		e.set_meta("quest_critical", true)
		if not hostile:
			e.disposition = Enemy.Disposition.NEUTRAL
		spawned[key] = e


static func _want_person(qm: QuestManager, spawned: Dictionary, q: Dictionary, role: String, name: String, at: Vector3) -> Enemy:
	var key := "quest/%s/%s" % [q["id"], role]
	if WorldState.has_record("kill/" + key):
		return null
	if spawned.has(key) and is_instance_valid(spawned[key]):
		return spawned[key]
	var world := qm.world
	var e := Enemy.create()
	(load("res://data/npcs/townsfolk.tres") as EnemyData).apply(e, maxi(qm._player_level() - 2, 1), RandomNumberGenerator.new())
	e.display_name = name
	e.talk_name = name
	e.talk_lines = PackedStringArray(["Please, get me out of here!"])
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.spawn_key = key
	e.wander_radius = 0.0
	e.set_meta("greeting", "Please, get me out of here!" if role == "captive" else "Ready when you are. Lead the way.")
	e.set_meta("quest_critical", true)
	at.y = world.get_height_at(at.x, at.z) + 0.6
	e.position = at
	world.add_child(e)
	spawned[key] = e
	return e


# The escort walks behind you; reaching the other town ends the job
static func _tend_escort(qm: QuestManager, spawned: Dictionary, q: Dictionary, start: Vector3, p: Node3D) -> void:
	var id := String(q["id"])
	if WorldState.has_record("quest/%s/arrived" % id):
		return
	var key := "quest/%s/escort" % id
	var e: Enemy = spawned.get(key)
	if e == null or not is_instance_valid(e):
		var from := start
		if q.has("escort_at"):
			from = Vector3(float(q["escort_at"][0]), float(q["escort_at"][1]), float(q["escort_at"][2]))
		if Vector2(from.x - p.global_position.x, from.z - p.global_position.z).length() > SPAWN_NEAR:
			return
		e = _want_person(qm, spawned, q, "escort", String(q["target_name"]), from)
		if e == null:
			return
	if e.is_dead():
		return
	var d := e.global_position.distance_to(p.global_position)
	if d > 3.5 and d < 60.0:
		e.follow_route(PackedVector3Array([p.global_position]), false, 0.75 if d < 12.0 else 1.0)
	elif d <= 3.5:
		e.stop_route()
	var dest := qm.world.get_poi(String(q["target"]))
	if dest != null and Vector2(dest.position.x - e.global_position.x, dest.position.z - e.global_position.z).length() < 45.0:
		WorldState.set_record("quest/%s/arrived" % id, {"done": true})
		e.set_meta("greeting", "We made it! Thank you, friend.")
		e.stop_route()
		Notices.quest(qm.get_tree(), "Objective complete", "%s reached %s" % [q["target_name"], q["destination_name"]])
	elif d < 60.0:
		var q2 := q.duplicate()
		q2["escort_at"] = [e.global_position.x, e.global_position.y, e.global_position.z]
		QuestManager._update_quest(q2)  # where they are, if the game is saved on the way


# ---------------------------------------------------------------- other ways through

## Topics a job's target person has: a persuade job's "a favour" and "what I know"; a steal job's
## owner sells or gives the thing ("buy the ...", "ask for the ...")
static func topics_for(qm: QuestManager, s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s == null or s.id == "":
		return out
	for q: Dictionary in QuestManager.all_quests():
		if q["status"] != "active":
			continue
		if q["type"] == "persuade" and q["target"] == s.id and not qm.is_ready(q):
			out.append("a favour")
			if DialogueState.knows(s.name):  # you have heard about them: leverage
				out.append("what I know")
			if _speech(qm) >= SPEECH_CHECK:  # a skilled tongue: a Speech option
				out.append("talk them round")
		if q["type"] == "steal" and "npc/" + String(q["target"]) == s.id and not qm.is_ready(q):
			out.append("buy the " + String(q["item_name"]).to_lower())
			if DialogueEngine.get_disposition(s) >= 80:
				out.append("ask for the " + String(q["item_name"]).to_lower())
	return out


static func respond(qm: QuestManager, s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if not topics_for(qm, s).has(topic):
		return {}
	var inv := qm._player().get_node("Inventory") as Inventory
	for q: Dictionary in QuestManager.all_quests():
		if q["status"] != "active":
			continue
		if q["type"] == "persuade" and q["target"] == s.id:
			if topic == "talk them round":
				DialogueState.change_disposition(s.id, s.base_disposition, QuestManager.PERSUADE_GOAL - DialogueEngine.get_disposition(s))
				_creative(qm, &"speech")
				return qm._say("[Speech %d] ...You know, you're right. I've been unfair. Consider me a friend." % _speech(qm), q)
			if topic == "what I know":
				DialogueState.change_disposition(s.id, s.base_disposition, QuestManager.PERSUADE_GOAL - DialogueEngine.get_disposition(s))
				NpcMemory.remember(s.name, s.town.town.display_name if s.town != null and s.town.town != null else "", "threat", "leverage", 1)
				_creative(qm, &"speech")
				return qm._say("...How do you know that? Fine. Fine! Whatever you want. Just keep it quiet.", q)
			if topic == "a favour":
				var bread := load("res://data/consumables/bread.tres") as ItemData if ResourceLoader.exists("res://data/consumables/bread.tres") else null
				var want: ItemData = bread
				if want == null:
					for st in inv.stacks:
						if st.item.item_type == ItemData.ItemType.CONSUMABLE:
							want = st.item
				if want != null and inv.has_item(want):
					inv.remove_item(want, 1)
					DialogueState.change_disposition(s.id, s.base_disposition, QuestManager.PERSUADE_GOAL - DialogueEngine.get_disposition(s))
					_creative(qm, &"speech")
					return qm._say("You brought %s? You remembered! You're a good sort, you know that." % want.display_name, q)
				return qm._say("A favour? I could do with %s, if you have one. Bring it and we'll talk." % (want.display_name if want != null else "something to eat"), q)
		if q["type"] == "steal" and "npc/" + String(q["target"]) == s.id:
			var thing := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
			if topic.begins_with("buy the "):
				var price := 120 + 25 * Factions.rank("thieves")
				if not Currency.spend_gold(inv, price):
					return qm._say("My %s? I'd part with it for %d gold. Not a coin less." % [String(q["item_name"]).get_slice("'s ", 1), price], q)
				inv.add_item(thing, 1)
				q["placed"] = true
				q["bought"] = true
				QuestManager._update_quest(q)
				_creative(qm, &"speech")
				return qm._say("Done. It's yours. Odd thing to want, but your gold is good.", q)
			if topic.begins_with("ask for the "):
				inv.add_item(thing, 1)
				q["placed"] = true
				q["bought"] = true
				QuestManager._update_quest(q)
				return qm._say("For you? Take it. I never cared for it anyway.", q)
	return {}


# ---------------------------------------------------------------- checks and limits

## Why a freshly made job can't be offered ("" = it can): every target must exist
static func validate(qm: QuestManager, q: Dictionary) -> String:
	var gone := QuestCheck.job_problem(qm.world, q)
	if gone != "":
		return gone
	match String(q["type"]):
		"steal":
			var b := qm.world.get_building(String(q["target"]))
			if b == null or b.is_public():
				return "no private house"
		"retrieve":
			var p := qm.world.get_poi(String(q["target"]))
			if p == null or not (p.poi is DungeonEntrancePOIData) or (p.poi as DungeonEntrancePOIData).dungeon.boss == null:
				return "no dungeon with a master"
		"gather":
			if not ResourceLoader.exists(String(q["item_path"])):
				return "no such item"
		"escort", "road":
			if qm.world.get_poi(String(q["target"])) == null:
				return "no such town"
	return ""


## Jobs given out in a town today (TOWN_LIMIT a day)
static func town_count(town_id: String, day: int) -> int:
	return int(WorldState.get_record("radiant_day/%s" % town_id).get(str(day), 0))


static func count_town(town_id: String, day: int) -> void:
	WorldState.set_record("radiant_day/%s" % town_id, {str(day): town_count(town_id, day) + 1})


## A notice board's offers for this period: [{"type", "name", "objective", "reward", "seed"}]
static func board_offers(qm: QuestManager, town: PlacedPOI, day: int) -> Array:
	var out: Array = []
	var period := day / BOARD_DAYS
	for i in BOARD_OFFERS:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|board|%s|%d|%d" % [qm.world.world_seed, town.id, period, i]).hash()
		var type: String = BOARD_TYPES[rng.randi_range(0, BOARD_TYPES.size() - 1)]
		var giver := DialogueEngine.Speaker.new()
		giver.id = "notice:%s" % town.id
		giver.name = "the notice board in %s" % town.town.display_name
		giver.town = town
		var q := qm._make(type, "offer", town, giver, rng) if not NEW_TYPES.has(type) else make(qm, type, town, giver, rng)
		if q.is_empty():
			continue
		q["type"] = type
		word(q, giver.name, qm._player_level(), rng)
		if validate(qm, q) != "":
			continue
		q["offer_key"] = "%s|%d|%d" % [town.id, period, i]
		q["expires_day"] = (period + 1) * BOARD_DAYS
		out.append(q)
	return out


static func _speech(qm: QuestManager) -> int:
	var sk := qm._player().get_node_or_null("Skills") as Skills
	return sk.get_level(&"speech") if sk != null else 0


# Another way through than the obvious one trains a skill
static func _creative(qm: QuestManager, skill: StringName) -> void:
	var sk := qm._player().get_node_or_null("Skills") as Skills
	if sk != null:
		sk.add_xp(skill, 20.0)
