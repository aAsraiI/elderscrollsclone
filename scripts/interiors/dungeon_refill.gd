class_name DungeonRefill
extends RefCounted
## Cleared dungeons don't stay empty: REFILL_DAYS after its boss died, a stitched dungeon gets new
## occupants the next time you go in. Its dead are forgotten, someone else's creatures (another
## kind of dungeon's spawn table and boss: bandits in an old crypt, beasts in an empty fort) move
## in, it shows as not cleared again and folk talk about it. The rooms, and what you took from
## them, stay as they were. Saved as "occupants/<dungeon id>" {"gen", "data"}.

const REFILL_DAYS := 21
const DUNGEONS_DIR := "res://data/world/Dungeons/"


## Called as the dungeon is built: refills it if its time has come. Returns the DungeonData whose
## creatures live there now (the dungeon's own, or the newcomers') and the generation (0 = the first).
static func occupants(data: DungeonData, dungeon_id: String, today: int) -> Dictionary:
	var rec := WorldState.get_record("occupants/" + dungeon_id)
	var gen := int(rec.get("gen", 0))
	var found := WorldState.get_record("found/" + dungeon_id)
	var story := WorldState.has_record("handmade/" + dungeon_id)  # the story's own place stays as it is
	if not story and bool(found.get("cleared", false)) and today - int(found.get("cleared_day", today)) >= REFILL_DAYS:
		gen += 1
		var newcomers := _pick(data, dungeon_id, gen)
		rec = {"gen": gen, "data": newcomers}
		WorldState.set_record("occupants/" + dungeon_id, rec)
		_forget_the_dead(dungeon_id)
		found.erase("cleared")
		found.erase("cleared_day")
		WorldState.set_record("found/" + dungeon_id, found)
		var w := Rumors._world()
		var p := w.get_poi(dungeon_id) if w != null else null
		if p != null:
			Rumors.add("trouble", "Something has moved into the %s again. Folk keep away." % Discovery.place_name(w, p), p.position, today, dungeon_id)
	var who := data
	if String(rec.get("data", "")) != "" and ResourceLoader.exists(String(rec["data"])):
		var other := load(String(rec["data"])) as DungeonData
		who = data.duplicate() as DungeonData
		who.spawn_table = other.spawn_table
		who.boss = other.boss
	return {"data": who, "gen": gen}


# Another kind of dungeon's folk (seeded, so the same every time)
static func _pick(data: DungeonData, dungeon_id: String, gen: int) -> String:
	var options: Array[String] = []
	for f in DirAccess.get_files_at(DUNGEONS_DIR):
		f = f.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var d := load(DUNGEONS_DIR + f) as DungeonData
		if d != null and d.spawn_table != null and d.boss != null and d.spawn_table != data.spawn_table:
			options.append(DUNGEONS_DIR + f)
	if options.is_empty():
		return ""
	options.sort()
	return options[absi(("%s|%d" % [dungeon_id, gen]).hash()) % options.size()]


# Its dead are gone: the kills of its rooms and its boss are forgotten (chests and doors are not)
static func _forget_the_dead(dungeon_id: String) -> void:
	var keys: Array = []
	for k: String in WorldState.records:
		if k.begins_with("kill/%s/" % dungeon_id) or k == "kill/dungeon/%s/boss" % dungeon_id:
			keys.append(k)
	for k in keys:
		WorldState.erase_record(k)
