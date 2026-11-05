class_name Settlers
extends Node
## Alpha 1.25: people who come to live at your homestead (Homestead). Created by WorldManager.
##   who      someone you freed from a dungeon's cells, or a traveller on the road you asked
##            ("a place to live"), while you own a homestead with room for them
##   room     the hall sleeps one, a bedroom two more; the storeroom and garden one each
##   work     farmer (vegetables), hunter (meat, hides), woodcutter (firewood), guard (keeps the place
##            safe: fewer raids), smith (now and then an ingot). Their work goes to the steward:
##            ask him for "the settlers' goods".
##   needs    every day each eats one share of food: the farmers and hunters feed everyone; short of
##            food, a bed, or after a raid, their mood falls; content, it rises. Below 15 they leave.
## Saved in WorldState "settlers". Their bodies stand about the plot when you are near it.

const RECORD := "settlers"
const STORE := "settlers_store"
const JOBS := ["farmer", "hunter", "woodcutter", "guard", "smith"]
const LEAVE_AT := 15
const TOPIC := "a place to live"
const GOODS_TOPIC := "the settlers' goods"
const OUTPUT := {"farmer": [["res://data/materials/cabbage.tres", 2], ["res://data/materials/potato.tres", 2]],
	"hunter": [["res://data/materials/raw_meat.tres", 2], ["res://data/materials/animal_hide.tres", 1]],
	"woodcutter": [["res://data/materials/firewood.tres", 4]],
	"smith": [["res://data/materials/iron_ingot.tres", 1]], "guard": []}

var world: WorldManager
var _day_done := -1
var _bodies := {}  # settler id -> Enemy
var _t := 0.0


func _ready() -> void:
	add_to_group("settlers")
	world = get_parent() as WorldManager


static func of(tree: SceneTree) -> Settlers:
	return tree.get_first_node_in_group("settlers") as Settlers if tree != null else null


static func all() -> Array:
	return WorldState.get_record(RECORD).get("list", [])


static func _save(list: Array) -> void:
	WorldState.set_record(RECORD, {"list": list})


## How many can live there now
static func capacity() -> int:
	if not Homestead.owns():
		return 0
	var c := 0
	if Homestead.has_part("hall"):
		c += 1
	if Homestead.has_part("bedroom"):
		c += 2
	if Homestead.has_part("storeroom"):
		c += 1
	if Homestead.has_part("garden"):
		c += 1
	return c


static func has_room() -> bool:
	return all().size() < capacity()


## Someone comes to live at your homestead. Returns "" or why not.
static func invite(name: String, job: String = "") -> String:
	if not Homestead.owns():
		return "You have no homestead"
	if not has_room():
		return "There is no room for anyone else"
	var list := all().duplicate(true)
	if job == "":
		job = JOBS[absi(name.hash()) % JOBS.size()]
	list.append({"id": "%s|%d" % [name, list.size()], "name": name, "job": job, "mood": 60, "joined": Rumors._day()})
	_save(list)
	DialogueState.system_entry("Homestead", "%s has come to live at your homestead, as a %s." % [name, job], "")
	return ""


# ---------------------------------------------------------------- every day

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null or world.clock == null:
		return
	_t = 2.0
	if world.clock.day != _day_done:
		if _day_done >= 0:
			daily()
		_day_done = world.clock.day
	_place_bodies()


## A day at the homestead: work, food, beds, mood; some may leave
func daily() -> void:
	Homestead.farm_day()  # 1.30: beehives, orchard and pen, settlers or not
	var list := all().duplicate(true)
	if list.is_empty():
		return
	var food := 0
	for s in list:
		if String(s["job"]) == "farmer":
			food += 3
		elif String(s["job"]) == "hunter":
			food += 2
	food += 2 if Homestead.has_part("garden") else 0
	var fed := food >= list.size()
	var beds := capacity() >= list.size()
	var raided := Rumors._day() - int(WorldState.get_record("homestead_raid").get("day", -99)) <= 2
	var store := WorldState.get_record(STORE).duplicate()
	var keep: Array = []
	for s in list:
		var mood := int(s["mood"])
		mood += (5 if fed else -15) + (3 if beds else -10) + (-10 if raided else 0)
		s["mood"] = clampi(mood, 0, 100)
		if int(s["mood"]) < LEAVE_AT:
			DialogueState.system_entry("Homestead", "%s has packed up and left your homestead. (%s)" % [s["name"], "hungry" if not fed else ("no bed" if not beds else "afraid")], "")
			Locks.toast(get_tree(), "%s has left your homestead." % s["name"], true)
			continue
		keep.append(s)
		# the day's work, a little less when unhappy
		var share := 1.0 if int(s["mood"]) >= 40 else 0.5
		for o in OUTPUT.get(String(s["job"]), []):
			if String(s["job"]) == "smith" and randf() > 0.4:
				continue
			store[o[0]] = int(store.get(o[0], 0)) + maxi(int(float(o[1]) * share), 1)
	_save(keep)
	WorldState.set_record(STORE, store)


## How much safer the guards make the place (Raids reads it)
static func guards() -> int:
	return all().filter(func(s): return String(s["job"]) == "guard").size()


# ---------------------------------------------------------------- dialogue

func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s == null or s.enemy == null or not is_instance_valid(s.enemy):
		return out
	if s.enemy.has_meta("traveller") and has_room():
		out.append(TOPIC)
	if s.enemy.has_meta("homestead_steward") and not WorldState.get_record(STORE).is_empty():
		out.append(GOODS_TOPIC)
	return out


func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if topic == TOPIC and s != null and s.enemy != null and is_instance_valid(s.enemy) and s.enemy.has_meta("traveller"):
		var why := invite(s.enemy.display_name.get_slice(",", 0))
		if why != "":
			return _say("I'd like that. But you've no room for me.")
		var e := s.enemy
		e.remove_meta("traveller")
		e.create_tween().tween_callback(e.queue_free).set_delay(8.0)
		return _say("A roof, and work? On the road it's neither. I'll be there before dark.")
	if topic == GOODS_TOPIC:
		var p := get_tree().get_first_node_in_group("player")
		var inv := p.get_node("Inventory") as Inventory if p != null else null
		var store := WorldState.get_record(STORE)
		var got := PackedStringArray()
		for path in store:
			var it := load(String(path)) as ItemData if ResourceLoader.exists(String(path)) else null
			if it != null and inv != null and int(store[path]) > 0:
				inv.add_item(it, int(store[path]))
				got.append("%s x%d" % [it.display_name, int(store[path])])
		var sk2 := p.get_node_or_null("Skills") as Skills if p != null else null
		if sk2 != null and not got.is_empty():
			sk2.add_xp(&"farming", 2.0 * got.size())  # 1.30: tending the farm
		WorldState.erase_record(STORE)
		return _say("Here is what the settlers brought in: %s." % ", ".join(got) if not got.is_empty() else "Nothing yet.")
	return {}


static func _say(text: String) -> Dictionary:
	return {"text": text, "journal": false, "learn": PackedStringArray()}


# ---------------------------------------------------------------- bodies about the plot

func _place_bodies() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or not Homestead.owns():
		return
	var plot := Homestead.plot_position()
	var near := plot.is_finite() and Vector2(plot.x - p.global_position.x, plot.z - p.global_position.z).length() < Homestead.NEAR \
			and not (world.dungeons != null and world.dungeons.is_inside())
	var list := all()
	var ids := {}
	for s in list:
		ids[String(s["id"])] = s
	for id in _bodies.keys():
		if not near or not ids.has(id) or not is_instance_valid(_bodies[id]):
			if is_instance_valid(_bodies[id]):
				(_bodies[id] as Node).queue_free()
			_bodies.erase(id)
	if not near:
		return
	var data := load("res://data/npcs/townsfolk.tres") as EnemyData
	for i in list.size():
		var s: Dictionary = list[i]
		var id := String(s["id"])
		if _bodies.has(id) or data == null:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = id.hash()
		var a := float(i) / maxf(list.size(), 1) * TAU
		var at := plot + Vector3(cos(a) * 9.0, 0, sin(a) * 9.0)
		at.y = world.get_height_at(at.x, at.z) + 0.4
		var e := Population.spawn_enemy(data, 5, world, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
		e.display_name = String(s["name"])
		e.talk_name = e.display_name
		e.disposition = Enemy.Disposition.FRIENDLY
		e.wander_radius = 4.0
		e.set_meta("settler", id)
		e.talk_lines = PackedStringArray(["Good to have a roof.", "Work's steady here. Food could be better." if int(s["mood"]) < 50 else "I like it here.", "I'm the %s, if you need anything." % s["job"]])
		if String(s["job"]) == "guard":
			e.set_meta("guard", true)
		_bodies[id] = e
