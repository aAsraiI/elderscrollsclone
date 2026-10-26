class_name QuestCheck
extends RefCounted
## Looks for quests that could never be finished: a person who isn't in the world, a town that
## doesn't exist, a foe, item or realm that isn't there. WorldManager runs it once the world is
## ready and prints each problem as a [Quest] warning; the debug console's quest.check runs it again.
##
## Covers the written quests (QuestBook) and the guild jobs in progress (QuestManager).

const ENEMY_DIR := "res://data/enemies/"


## Every problem found, one line each ("" problems = all good)
static func problems(world: WorldManager) -> PackedStringArray:
	var out := PackedStringArray()
	if world == null:
		return out
	var towns := {}
	for t in world.towns:
		if t.town != null:
			towns[t.town.display_name] = t
	for id in QuestBook.ids():
		var d := QuestBook.get_def(id)
		_check_who(world, towns, id, "giver", d["giver"], d, out)
		var steps: Array = d["steps"]
		for i in steps.size():
			var st: Dictionary = steps[i]
			var where := "step %d" % (i + 1)
			if st.has("who"):
				_check_who(world, towns, id, where, st["who"], d, out)
			if st.has("at"):
				_check_place(towns, id, where, st["at"], out)
			match String(st["do"]):
				"fight":
					for f: Array in st["foes"]:
						if not ResourceLoader.exists(ENEMY_DIR + String(f[0]) + ".tres"):
							out.append("%s %s: no enemy '%s'" % [id, where, f[0]])
				"collect":
					if not ResourceLoader.exists(String(st["item"])):
						out.append("%s %s: no item %s" % [id, where, st["item"]])
				"realm", "site":
					if RealmManager.get_data(String(st["realm"])).is_empty():
						out.append("%s %s: no realm %s" % [id, where, st["realm"]])
		var r: Dictionary = d.get("reward", {})
		for path in r.get("items", []):
			if not ResourceLoader.exists(String(path)):
				out.append("%s reward: no item %s" % [id, path])
		for n: Dictionary in r.get("named", []):
			if not ResourceLoader.exists(String(n["base"])):
				out.append("%s reward: no base item %s" % [id, n["base"]])
	for c in CustomNpcs.all():
		if c.town != "" and not towns.has(c.town):
			out.append("custom NPC %s: no town %s" % [c.display_name, c.town])
		if c.dialogue == null:
			out.append("custom NPC %s: no DialogueData" % c.display_name)
	for q: Dictionary in QuestManager.all_quests():
		if String(q.get("status", "")) == "active":
			var why := job_problem(world, q)
			if why != "":
				out.append("%s (%s): %s" % [q["id"], q.get("name", ""), why])
	return out


## Why a guild job in progress can't be finished, or ""
static func job_problem(world: WorldManager, q: Dictionary) -> String:
	var target := String(q.get("target", ""))
	match String(q.get("type", "")):
		"retrieve", "kill", "hunt", "excavate", "survey":
			if world.get_poi(target) == null:
				return "its place %s is gone" % target
		"steal":
			if world.get_building(target) == null:
				return "its house %s is gone" % target
		"persuade", "deliver", "assassinate":
			if world.life == null or world.life.get_resident(target) == null:
				return "%s is not in the world" % q.get("target_name", target)
			if q["type"] != "assassinate" and world.life.get_resident(target).dead:
				return "%s is dead" % q.get("target_name", target)
	return ""


static func _resident_named(world: WorldManager, town: PlacedPOI, name: String) -> TownLife.Resident:
	if world.life == null or town == null:
		return null
	for r: TownLife.Resident in world.life.get_town_residents(town.id):
		if r.data.display_name == name:
			return r
	return null


static func _check_who(world: WorldManager, towns: Dictionary, id: String, where: String, who: Dictionary, d: Dictionary, out: PackedStringArray) -> void:
	if who.has("giver"):
		who = d["giver"]
	if who.has("lord"):
		var t: PlacedPOI = towns.get(String(who["lord"]))
		if t == null:
			out.append("%s %s: no town %s" % [id, where, who["lord"]])
		elif t.town.get_seat() == null:
			out.append("%s %s: %s has no lord's seat" % [id, where, who["lord"]])
	elif who.has("cast"):
		var t: PlacedPOI = towns.get(String(who["town"]))
		if t == null:
			out.append("%s %s: no town %s" % [id, where, who["town"]])
		elif _resident_named(world, t, String(who["cast"])) == null:
			out.append("%s %s: nobody called %s lives in %s" % [id, where, who["cast"], who["town"]])
	elif who.has("leader"):
		var fd := Factions.get_data(String(who["leader"]))
		if fd == null or fd.leader_name == "":
			out.append("%s %s: %s has no leader" % [id, where, who["leader"]])
		elif not towns.has(fd.leader_town) or _resident_named(world, towns[fd.leader_town], fd.leader_name) == null:
			out.append("%s %s: %s (leader of %s) is not in %s" % [id, where, fd.leader_name, who["leader"], fd.leader_town])
	elif who.has("guild"):
		if QuestBook.guild_places(world, String(who["guild"])).is_empty():
			out.append("%s %s: nowhere to find the %s" % [id, where, who["guild"]])
	elif who.has("spawn"):
		_check_place(towns, id, where, who["spawn"], out)
	elif who.has("realm_npc"):
		if RealmManager.get_data(String(who["realm"])).is_empty():
			out.append("%s %s: no realm %s" % [id, where, who["realm"]])


static func _check_place(towns: Dictionary, id: String, where: String, place: Dictionary, out: PackedStringArray) -> void:
	if place.has("town") and not towns.has(String(place["town"])):
		out.append("%s %s: no town %s" % [id, where, place["town"]])
	for k in ["dungeon", "camp", "wild"]:
		if place.has(k):
			var near := String(place[k])
			if not towns.has(near) and not BiomeKeys.has(near):
				out.append("%s %s: nowhere called %s" % [id, where, near])


## Biome keys a quest place can name instead of a town
class BiomeKeys:
	static var _keys := {}

	static func has(key: String) -> bool:
		if _keys.is_empty():
			for biome: String in NamedSettlements.LIST:
				_keys[biome] = true
		return _keys.has(key)
