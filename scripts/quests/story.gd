class_name Story
extends Node
## The main questline, "The Ashen Eclipse". Begins for every character made on the Character
## Creation screen. Created by WorldManager. Places come from the generated world, so the story
## names roles and finds the nearest fitting places rather than fixed coordinates:
##
##   1  A courier's sealed letter: take it to the priest of the nearest city's temple.
##   2  The priest ("the sealed letter"): the Ash Cult hunts the Eclipse Codex in a dungeon
##      nearby. Clear that dungeon (kill what guards its deepest room).
##   3  With the Codex, ask the master of any Mages Guild hall ("the eclipse codex").
##   4  The ritual site: a far ruin where the Ash Hierophant and his cult gather. Kill him.
##   5  Back to the priest ("the eclipse"): a reward, and the sun is safe.
## State lives in WorldState "story". The journal files it under "The Ashen Eclipse"; its target
## shows on the map and compass like a guild job.

const ID := "story"
const NAME := "The Ashen Eclipse"
const TOPICS := {2: "the sealed letter", 3: "the eclipse codex", 5: "the eclipse"}

var world: WorldManager
var _timer := 3.0
var _spawned := false


func _ready() -> void:
	add_to_group("story")
	world = get_parent() as WorldManager


static func state() -> Dictionary:
	return WorldState.get_record(ID)


static func stage() -> int:
	return int(state().get("stage", 0))


static func _store(d: Dictionary) -> void:
	WorldState.set_record(ID, d)


## The marker for the map and compass ({} = none)
static func target() -> Dictionary:
	var s := state()
	if s.is_empty() or int(s.get("stage", 0)) <= 0 or int(s.get("stage", 0)) >= 6 or not s.has("pos"):
		return {}
	return {"pos": Vector2(float(s["pos"][0]), float(s["pos"][1])), "name": NAME, "id": ID}


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	# The story is over: its epilogue plays once, after the last conversation has closed
	if stage() >= 6 and not WorldState.has_record("epilogue/story"):
		WorldState.set_record("epilogue/story", {"seen": true})
		Epilogue.play(get_tree(), NAME)
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or world == null or world.map == null:
		return
	var s := state()
	if s.is_empty():
		if p.has_meta("character"):
			_begin(p)
		return
	match int(s.get("stage", 0)):
		2:
			if Discovery.is_cleared(String(s.get("dungeon", ""))):
				var codex := QuestItems.get_item("story_codex", "Eclipse Codex")
				(p.get_node("Inventory") as Inventory).add_item(codex, 1)
				_advance(3, "Among the cultists' things lay the Eclipse Codex, written in ash-grey ink. The priest said a scholar of the Mages Guild could read it.", Vector3.INF)
		4:
			_tick_ritual(p, s)


func _begin(p: Node3D) -> void:
	var temple := _nearest_city_temple(p.global_position)
	if temple.is_empty():
		return
	var letter := QuestItems.get_item("story_letter", "Sealed Letter")
	(p.get_node("Inventory") as Inventory).add_item(letter, 1)
	_store({"stage": 1, "temple": temple["building"], "town": temple["town"], "pos": temple["pos"]})
	_journal("A dying courier pressed a sealed letter into your hands: 'Take it to the priests of %s. Tell them the sun is in danger.' Then the courier was gone." % temple["town_name"])
	Locks.toast(get_tree(), "New quest: %s" % NAME)


func _nearest_city_temple(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for t in world.towns:
		if t.town == null or not (t.poi is TownData):
			continue
		for b in t.town.buildings:
			if b.kind == BuildingPlot.Kind.TEMPLE:
				var d := t.position.distance_to(pos) * (1.0 if (t.poi as TownData).kind == TownData.Kind.CITY else 1.6)
				if d < best_d:
					best_d = d
					best = {"building": b.id, "town": t.id, "town_name": t.town.display_name, "pos": [t.position.x, t.position.z]}
	return best


func _advance(to: int, text: String, at: Vector3) -> void:
	var s := state().duplicate()
	s["stage"] = to
	if at.is_finite():
		s["pos"] = [at.x, at.z]
	_store(s)
	_journal(text)


func _journal(text: String) -> void:
	var clock := world.clock if world != null else null
	DialogueState.add_journal({"text": text, "speaker": "", "topic": "", "day": clock.day if clock != null else 1,
		"time": clock.get_time_text() if clock != null else "", "quest_id": ID, "quest_name": NAME})


# ---------------------------------------------------------------- dialogue (QuestManager asks)

func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	var st := stage()
	if (st == 1 or st == 5) and _is_priest(s):
		out.append(TOPICS[2] if st == 1 else TOPICS[5])
	elif st == 3 and Factions.leader_of(s, world) == "mages":
		out.append(TOPICS[3])
	return out


func _is_priest(s: DialogueEngine.Speaker) -> bool:
	return s != null and s.data != null and s.data.work_id == String(state().get("temple", ""))


func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if not topics_for(s).has(topic):
		return {}
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var inv := p.get_node("Inventory") as Inventory
	match stage():
		1:
			inv.remove_item(QuestItems.get_item("story_letter", "Sealed Letter"), 1)
			var dungeon := _story_dungeon(p.global_position)
			if dungeon == null:
				return _say("This letter... Ash and a black sun. I must think on it. Come back to me.")
			var s2 := state().duplicate()
			s2["dungeon"] = dungeon.id
			s2["stage"] = 2
			s2["pos"] = [dungeon.position.x, dungeon.position.z]
			_store(s2)
			var where := DialogueEngine.poi_topic_name(world, dungeon)
			return _say("The Ash Cult. They believe a ritual written in the Eclipse Codex can put out the sun, and give the night to their masters. Their scouts were seen at %s, %s of here. Find the Codex before they do: clear that place to its deepest room." % [where, DialogueEngine.compass(Vector2(dungeon.position.x - s.position.x, dungeon.position.z - s.position.z))])
		3:
			inv.remove_item(QuestItems.get_item("story_codex", "Eclipse Codex"), 1)
			var site := _ritual_site(p.global_position)
			if site == null:
				return _say("Fascinating. Give me time with it.")
			var s3 := state().duplicate()
			s3["stage"] = 4
			s3["site"] = site.id
			s3["pos"] = [site.position.x, site.position.z]
			_store(s3)
			return _say("By the stars. This isn't a book of lore, it is a map. The ritual needs a place where old stones meet open sky: %s. If the Ash Hierophant completes it on the next dark moon, the sun goes out. Stop him." % DialogueEngine.poi_topic_name(world, site))
		5:
			var sword := load("res://data/weapons/silver_sword.tres") as ItemData
			if sword != null:
				var dawn := CraftedItems.gear(sword, 3, [{"id": &"fire_damage", "mag": 25, "dur": 0}], 2000.0, "Dawn's Edge")
				inv.add_item(dawn, 1)
			Currency.add_gold(inv, 1000)
			var skills := p.get_node_or_null("Skills") as Skills
			if skills != null:
				skills.add_deed_xp(SkillDatabase.deed_xp(skills.get_player_level(), 10.0))
			var s5 := state().duplicate()
			s5["stage"] = 6
			_store(s5)
			return _say("The Hierophant is dead and the sun still rises. Take this blade: Dawn's Edge, forged for the day the night would try to win. The temple will not forget you.")
	return {}


func _say(text: String) -> Dictionary:
	return {"text": text, "journal": true, "quest_id": ID, "quest_name": NAME, "learn": PackedStringArray()}


# The nearest dungeon with a boss, at least 400 m away
func _story_dungeon(from: Vector3) -> PlacedPOI:
	var best: PlacedPOI = null
	var best_d := INF
	for p in world.pois:
		var e := p.poi as DungeonEntrancePOIData
		if e == null or e.dungeon == null or e.dungeon.boss == null or Discovery.is_cleared(p.id):
			continue
		var d := p.position.distance_to(from)
		if d > 400.0 and d < best_d:
			best_d = d
			best = p
	return best


# A far ruin or standing stones (not a dungeon), 1.5 km or more away
func _ritual_site(from: Vector3) -> PlacedPOI:
	var best: PlacedPOI = null
	var best_d := INF
	for p in world.pois:
		if p.poi is TownData or p.poi is DungeonEntrancePOIData:
			continue
		var d := p.position.distance_to(from)
		if d > 1500.0 and d < best_d:
			best_d = d
			best = p
	return best


# ---------------------------------------------------------------- the ritual

func _tick_ritual(p: Node3D, s: Dictionary) -> void:
	var site := world.get_poi(String(s.get("site", "")))
	if site == null:
		return
	var d := Vector2(site.position.x - p.global_position.x, site.position.z - p.global_position.z).length()
	if not _spawned and d < 90.0:
		_spawned = true
		_spawn_cult(site)
		Locks.toast(get_tree(), "Chanting rises from the ruins...", true)
	if _spawned:
		var boss_alive := false
		for n in ActorRegistry.all():
			if n is Enemy and (n as Enemy).has_meta("hierophant") and not (n as Enemy).is_dead():
				boss_alive = true
		if not boss_alive and d < 200.0:
			var temple := world.get_building(String(s.get("temple", "")))
			var at := temple.world_pos if temple != null else Vector3.INF
			_advance(5, "The Ash Hierophant is dead and his circle broken. The priest who read the letter should hear of it.", at)
			_spawned = false


func _spawn_cult(site: PlacedPOI) -> void:
	var skills := get_tree().get_first_node_in_group("player").get_node_or_null("Skills") as Skills
	var level := (skills.get_player_level() if skills != null else 10) + 3
	var priest := load("res://data/enemies/ashen_priest.tres") as EnemyData
	var cultist := load("res://data/enemies/ash_cultist.tres") as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.seed = site.id.hash()
	for i in 6:
		var data := priest if i == 0 else cultist
		if data == null:
			continue
		var a := float(i) / 6.0 * TAU
		var x := site.position.x + cos(a) * (2.0 if i == 0 else 9.0)
		var z := site.position.z + sin(a) * (2.0 if i == 0 else 9.0)
		var pos := Vector3(x, world.get_height_at(x, z) + 0.5, z)
		var e := Enemy.create()
		data.apply(e, level + (4 if i == 0 else 0), rng)
		e.persist_mode = Enemy.PersistMode.NEVER
		if i == 0:
			e.display_name = "Ash Hierophant"
			e.max_health *= 3.0
			e.body_scale = 1.15
			e.set_meta("hierophant", true)
		e.position = pos
		get_tree().current_scene.add_child(e)
		e.global_position = pos
