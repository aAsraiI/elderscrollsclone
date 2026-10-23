class_name QuestBook
extends Node
## Every written quest of the design bible: settlement quests, noble houses, vampire clans, the
## werewolf pack, guild questlines and realm quests. Created by WorldManager. The quests are data
## (see QD and the QuestDefs* files); this runs them.
##
## A quest is offered by its giver as a dialogue topic (its "hook"). Asking starts it; then it
## moves through its steps one by one:
##   talk / choice   ask someone about a topic (a choice offers several, the pick is remembered)
##   clear           defeat the master of a dungeon (Discovery.is_cleared)
##   fetch           a quest item waits in a dungeon's deepest chest
##   fight           foes appear at a place when you come near; kill them all
##   visit           reach a place
##   collect         carry some of a real item (given up at the next talk)
##   wait            let time pass
##   realm           enter an instanced realm and defeat what rules its heart (RealmManager)
## Places are worked out from the world when a step begins (the nearest dungeon to a town, a
## spot in the wild...), and every step's target shows on the map and compass.
##
## Faction questlines: a quest with a faction needs that rank; the faction's gate quests must be
## done before ranks 3 and 5 (Factions.next_rank); completing a faction quest counts as a job and
## promotes when earned. A clan or pack quest needs the affliction, and a cure expels.
##
## Saved in WorldState: "qb/<id>" per quest started, "qb_flags", "qb_perks", "qb_titles".

const STATE := "qb/"
const FLAGS := "qb_flags"
const PERKS := "qb_perks"
const TITLES := "qb_titles"
const ENEMY_DIR := "res://data/enemies/"
const SPAWN_NEAR := 150.0
const SPAWN_FAR := 260.0
const TALKER_NEAR := 110.0
const WEAPON_CHARGE := 2000.0

static var _defs := {}
static var _order: Array[String] = []
static var _cast_cache := {}

var world: WorldManager
var _timer := 0.0
var _spawned := {}   # key -> Enemy
var _topic_cache := {}
var _topic_frame := -1


func _ready() -> void:
	add_to_group("quest_book")
	world = get_parent() as WorldManager
	_apply_perks.call_deferred()
	var sm := get_tree().get_first_node_in_group("save_manager") as SaveManager
	if sm != null:
		sm.loaded.connect(func(_slot: String) -> void: _apply_perks())


static func of(tree: SceneTree) -> QuestBook:
	return tree.get_first_node_in_group("quest_book") as QuestBook if tree != null else null


# ---------------------------------------------------------------- the quest list

static func defs() -> Dictionary:
	if _defs.is_empty():
		var lists: Array = []
		lists.append_array(QuestDefsSettlements.list())
		lists.append_array(QuestDefsWilds.list())
		lists.append_array(QuestDefsHouses.list())
		lists.append_array(QuestDefsNight.list())
		lists.append_array(QuestDefsGuilds.list())
		lists.append_array(QuestDefsRealms.list())
		for d: Dictionary in lists:
			_defs[d["id"]] = d
			_order.append(d["id"])
	return _defs


static func get_def(id: String) -> Dictionary:
	return defs().get(id, {})


static func ids() -> Array[String]:
	defs()
	return _order


static func state(id: String) -> Dictionary:
	return WorldState.get_record(STATE + id)


static func _store(id: String, st: Dictionary) -> void:
	WorldState.set_record(STATE + id, st)


static func status(id: String) -> String:
	return String(state(id).get("status", ""))


static func is_done(id: String) -> bool:
	return status(id) == "done"


static func is_active(id: String) -> bool:
	return status(id) == "active"


static func flag(flag_id: String) -> bool:
	return WorldState.get_record(FLAGS).has(flag_id)


static func set_flag(flag_id: String) -> void:
	var f := WorldState.get_record(FLAGS).duplicate()
	f[flag_id] = true
	WorldState.set_record(FLAGS, f)


static func titles() -> Array:
	return WorldState.get_record(TITLES).get("list", [])


## Everyone a named town needs for its quests: [{"name", "at"}], sorted (TownLayout gives each a
## home in that town)
static func cast_for(town_name: String) -> Array:
	if _cast_cache.is_empty():
		var by_town := {}
		for id in ids():
			var d: Dictionary = _defs[id]
			var refs: Array = [d["giver"]]
			for st: Dictionary in d["steps"]:
				if st.has("who"):
					refs.append(st["who"])
			for r: Dictionary in refs:
				if r.has("cast"):
					var t := String(r["town"])
					if not by_town.has(t):
						by_town[t] = {}
					if not by_town[t].has(r["cast"]):
						by_town[t][r["cast"]] = String(r.get("at", "house"))
		for t in by_town:
			var list: Array = []
			var names: Array = by_town[t].keys()
			names.sort()
			for n in names:
				list.append({"name": n, "at": by_town[t][n]})
			_cast_cache[t] = list
		_cast_cache["__built"] = []
	return _cast_cache.get(town_name, [])


# ---------------------------------------------------------------- can it start?

func can_start(d: Dictionary) -> bool:
	if status(d["id"]) != "":
		return false
	for a in d["after"]:
		if not is_done(String(a)):
			return false
	var aff := String(d.get("affliction", ""))
	if aff != "" and not _afflicted(aff):
		return false
	var f := String(d.get("faction", ""))
	if bool(d.get("penance", false)):  # coming back after a cure: only the expelled
		return f != "" and not Factions.is_member(f) and WorldState.has_record("fexpel/" + f)
	if f != "":
		var r := int(d.get("rank", 1))
		if r <= 0:  # the trial: anyone who could join
			if Factions.is_member(f) or Factions.join_problem(f, _player(), true) != "":
				return false
		elif Factions.rank(f) < r:
			return false
	return true


func _afflicted(kind: String) -> bool:
	var a := Afflictions.of(get_tree())
	if a == null:
		return false
	return a.vampire if kind == "vampire" else a.werewolf if kind == "werewolf" else true


# ---------------------------------------------------------------- talking

## Topics this speaker has for quests (cached for the frame: the dialogue asks often)
func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	if s == null:
		return PackedStringArray()
	var frame := Engine.get_process_frames()
	if frame != _topic_frame:
		_topic_frame = frame
		_topic_cache.clear()
	var key := "%s|%s" % [s.id, s.name]
	if _topic_cache.has(key):
		return _topic_cache[key]
	var out := PackedStringArray()
	for id in ids():
		var d: Dictionary = _defs[id]
		var st := status(id)
		if st == "":
			if _matches(s, d["giver"], d) and can_start(d):
				out.append(String(d["hook"]))
		elif st == "active":
			var step := _step(d)
			if step.is_empty() or not _matches(s, step.get("who", {}), d):
				continue
			if step["do"] == "talk":
				out.append(String(step["topic"]))
			elif step["do"] == "choice":
				for o: Dictionary in step["options"]:
					out.append(String(o["topic"]))
	_topic_cache[key] = out
	return out


func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if not topics_for(s).has(topic):
		return {}
	for id in ids():
		var d: Dictionary = _defs[id]
		var st := status(id)
		if st == "" and String(d["hook"]) == topic and _matches(s, d["giver"], d) and can_start(d):
			start(id)
			return _say(String(d["intro"]), d)
		if st != "active":
			continue
		var step := _step(d)
		if step.is_empty() or not _matches(s, step.get("who", {}), d):
			continue
		if step["do"] == "talk" and String(step["topic"]) == topic:
			var why := _talk_blocked(d, step)
			if why != "":
				return _say(why, d)
			var text := String(step["say"])
			_consume_collected(d)
			advance(id)
			return _say(text, d)
		if step["do"] == "choice":
			for o: Dictionary in step["options"]:
				if String(o["topic"]) == topic:
					var stt := state(id).duplicate(true)
					var fl: Array = stt.get("flags", [])
					fl.append(o["flag"])
					stt["flags"] = fl
					_store(id, stt)
					set_flag("%s:%s" % [id, o["flag"]])
					advance(id)
					return _say(String(o["say"]), d)
	return {}


# A talk step that hands something in waits until you carry it
func _talk_blocked(d: Dictionary, step: Dictionary) -> String:
	if step.has("carry"):
		var item := QuestItems.get_item(_item_key(d["id"], "carry"), String(step["carry"]))
		if not _inv().has_item(item):
			return "You don't have the %s." % step["carry"]
	return ""


func _say(text: String, d: Dictionary) -> Dictionary:
	return {"text": text, "journal": true, "quest_id": String(d["id"]), "quest_name": String(d["name"]), "learn": PackedStringArray()}


## Does this speaker stand for this person of a quest?
func _matches(s: DialogueEngine.Speaker, who: Dictionary, d: Dictionary) -> bool:
	if who.is_empty():
		return false
	if who.has("giver"):
		who = d["giver"]
	var town_name := s.town.town.display_name if s.town != null and s.town.town != null else ""
	if who.has("lord"):
		return s.role == NpcData.Role.LORD and town_name == String(who["lord"])
	if who.has("cast"):
		return s.name == String(who["cast"]) and (town_name == "" or town_name == String(who["town"]))
	if who.has("guild"):
		return Factions.leader_of(s, world) == String(who["guild"])
	if who.has("leader"):
		return Factions.leader_of(s, world) == String(who["leader"])
	if who.has("spawn"):
		return s.enemy != null and is_instance_valid(s.enemy) and String(s.enemy.get_meta("qb_npc", "")) == _talker_key(d["id"], who)
	if who.has("realm_npc"):
		return s.enemy != null and is_instance_valid(s.enemy) and String(s.enemy.get_meta("realm_npc", "")) == String(who["realm_npc"])
	return false


# The realms a step sends you to (its own realm, or the realm of the person to see)
static func _realms_of(step: Dictionary) -> Array:
	var out := []
	if step.has("realm"):
		out.append(String(step["realm"]))
	if step.get("who", {}).has("realm"):
		out.append(String(step["who"]["realm"]))
	return out


# ---------------------------------------------------------------- running a quest

func start(id: String) -> void:
	var d := get_def(id)
	if d.is_empty() or status(id) != "":
		return
	_store(id, {"status": "active", "step": 0, "flags": [], "places": {}})
	_journal(d, String(d["intro"]))
	Locks.toast(get_tree(), "New quest: %s" % d["name"])
	_begin_step(id, 0)


func _step(d: Dictionary) -> Dictionary:
	var i := int(state(d["id"]).get("step", 0))
	var steps: Array = d["steps"]
	return steps[i] if i >= 0 and i < steps.size() else {}


func _begin_step(id: String, i: int) -> void:
	var d := get_def(id)
	var steps: Array = d["steps"]
	if i >= steps.size():
		finish(id)
		return
	var step: Dictionary = steps[i]
	var st := state(id).duplicate(true)
	st["step"] = i
	st["t0"] = _hours()
	var pos := Vector3.INF
	if step.has("at"):
		var place := _resolve(step["at"], id)
		var places: Dictionary = st.get("places", {})
		places[str(i)] = place
		st["places"] = places
		pos = _vec(place.get("pos", []))
	elif step.has("who"):
		pos = _person_pos(step["who"], d)
	elif step["do"] == "realm" or step["do"] == "site":
		pos = RealmManager.gate_position(world, String(step["realm"]))
	# a quest that sends you to a realm opens its gate
	for r in _realms_of(step):
		RealmManager.open_gate(r)
	if pos.is_finite():
		st["pos"] = [pos.x, pos.z]
	else:
		st.erase("pos")
	_store(id, st)
	if step.has("carry"):
		_inv().add_item(QuestItems.get_item(_item_key(id, "carry"), String(step["carry"])))
	_journal(d, String(step.get("text", "")))
	_check_step(id)  # a place already cleared, an item already carried...


## Moves a quest on to its next step (finishing it after the last)
func advance(id: String) -> void:
	var d := get_def(id)
	var st := state(id)
	if d.is_empty() or String(st.get("status", "")) != "active":
		return
	_despawn_step(id, int(st.get("step", 0)))
	var step := _step(d)
	if step.has("carry"):
		var item := QuestItems.get_item(_item_key(id, "carry"), String(step["carry"]))
		if _inv().has_item(item):
			_inv().remove_item(item, _inv().get_count(item))
	_begin_step(id, int(st.get("step", 0)) + 1)


func finish(id: String) -> void:
	var d := get_def(id)
	var st := state(id).duplicate(true)
	st["status"] = "done"
	st.erase("pos")
	_store(id, st)
	# quest items go back to whoever wanted them
	var inv := _inv()
	for i in (d["steps"] as Array).size():
		var item := QuestItems.get_item(_item_key(id, str(i)), "")
		if inv.has_item(item):
			inv.remove_item(item, inv.get_count(item))
	var lines := _give_reward(d)
	var f := String(d.get("faction", ""))
	if ClanTerritory.CLANS.has(f) and world != null and world.map != null:
		# a clan's work wins it ground in the land where it was done
		var last := Vector3.INF
		for pl: Dictionary in st.get("places", {}).values():
			if _vec(pl.get("pos", [])).is_finite():
				last = _vec(pl["pos"])
		if not last.is_finite():
			last = _player().global_position
		var biome := world.map.get_biome_at(last.x, last.z)
		if biome != null:
			ClanTerritory.gain(biome.get_key(), f)
	if f != "" and Factions.is_member(f):
		Factions.add_quest_done(f)
		var title := Factions.promote(f, _player())
		if title != "":
			lines.append("You are now a %s of the %s." % [title, Factions.display_name(f)])
	_journal(d, "Quest complete: %s.%s" % [d["name"], (" " + " ".join(lines)) if not lines.is_empty() else ""])
	Locks.toast(get_tree(), "Quest complete: %s" % d["name"])
	if bool(d.get("penance", false)):
		WorldState.erase_record(STATE + id)  # a penance can be needed again after another cure


func _give_reward(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var r: Dictionary = d.get("reward", {})
	var p := _player()
	var inv := _inv()
	var gold := int(r.get("gold", 0))
	if gold > 0:
		Currency.add_gold(inv, gold)
		out.append("%d gold." % gold)
	for path in r.get("items", []):
		var it := load(String(path)) as ItemData if ResourceLoader.exists(String(path)) else null
		if it != null:
			inv.add_item(it, 1)
			out.append("%s." % it.display_name)
	for n: Dictionary in r.get("named", []):
		var base := load(String(n["base"])) as ItemData if ResourceLoader.exists(String(n["base"])) else null
		if base == null:
			continue
		var fx: Array = []
		var weapon := base.item_type == ItemData.ItemType.WEAPON
		for e: Array in n.get("fx", []):
			fx.append({"id": String(e[0]), "mag": float(e[1]), "dur": float(e[2]) if e.size() > 2 else 0.0})
		var item := CraftedItems.gear(base, int(n.get("q", 3)), fx, WEAPON_CHARGE if weapon and not fx.is_empty() else 0.0, String(n["name"]))
		if item != null:
			inv.add_item(item, 1)
			out.append("%s." % n["name"])
	if r.has("perk"):
		var perks := WorldState.get_record(PERKS).duplicate()
		perks[d["id"]] = r["perk"]
		WorldState.set_record(PERKS, perks)
		_apply_perks()
	if r.has("title"):
		var t := titles().duplicate()
		if not t.has(r["title"]):
			t.append(r["title"])
		WorldState.set_record(TITLES, {"list": t})
		out.append("Title: %s." % r["title"])
	if r.has("home"):
		var home := _home_in(String(r["home"]))
		if home != null and not Homes.owns(home.id):
			WorldState.set_record("home/" + home.id, {"town": home.town_name})
			Locks.set_locked(home.id, false)
			inv.add_item(KeyRing.get_key(home.id, home.display_name), 1)
			out.append("A home in %s." % home.town_name)
	if r.has("spell"):
		var book := p.get_node_or_null("Spellbook") as Spellbook if p != null else null
		var sp := SpellCatalog.get_spell(String(r["spell"]))
		if book != null and sp != null:
			book.learn(sp, true)
			out.append("Spell: %s." % sp.display_name)
	if r.has("join"):
		var f := String(r["join"])
		if not Factions.is_member(f) and Factions.join(f, p):
			out.append("You are sworn to the %s." % Factions.display_name(f))
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	if skills != null:
		var size := 8.0 if (d["steps"] as Array).size() >= 5 else 5.0
		skills.add_deed_xp(SkillDatabase.deed_xp(skills.get_player_level(), float(r.get("xp", size))))
	return out


func _apply_perks() -> void:
	var p := _player()
	var stats := p.get_node_or_null("Stats") as Stats if p != null else null
	if stats == null:
		return
	var perks := WorldState.get_record(PERKS)
	for id in perks:
		stats.add_modifiers("quest_" + String(id), perks[id])


# The house for sale in a town (falls back to any empty-looking house)
func _home_in(town_name: String) -> BuildingPlot:
	for t in world.towns:
		if t.town != null and t.town.display_name == town_name:
			var sale := Homes.for_sale_id(t.town, 2)
			if sale != "":
				return world.get_building(sale)
			for b in t.town.buildings:
				if b.kind == BuildingPlot.Kind.HOUSE:
					return b
	return null


# ---------------------------------------------------------------- per tick

func _process(delta: float) -> void:
	if world == null or get_tree().paused or _player() == null:
		return
	_timer += delta
	if _timer < 0.5:
		return
	_timer = 0.0
	for id in ids():
		if is_active(id):
			_check_step(id)
	_tend_spawns()
	_check_expulsions()


## Is the current step's task done? (talk and choice steps finish in dialogue)
func _check_step(id: String) -> void:
	var d := get_def(id)
	var st := state(id)
	var step := _step(d)
	if step.is_empty():
		return
	var i := int(st.get("step", 0))
	var place: Dictionary = st.get("places", {}).get(str(i), {})
	var done := false
	match String(step["do"]):
		"clear":
			done = place.has("poi") and Discovery.is_cleared(String(place["poi"]))
		"fetch":
			done = _inv().has_item(QuestItems.get_item(_item_key(id, str(i)), String(step["item"])))
		"fight":
			done = _foes_dead(id, i, step)
		"visit":
			var p := _player().global_position
			var at := _vec(place.get("pos", []))
			done = at.is_finite() and Vector2(p.x - at.x, p.z - at.z).length() <= float(step.get("radius", 40.0))
		"collect":
			var it := load(String(step["item"])) as ItemData if ResourceLoader.exists(String(step["item"])) else null
			done = it != null and _inv().get_count(it) >= int(step["count"])
		"wait":
			done = _hours() - float(st.get("t0", 0.0)) >= float(step["hours"])
		"realm":
			done = RealmManager.is_conquered(String(step["realm"]))
		"site":
			done = RealmManager.is_site_cleared(String(step["realm"]), int(step["site"]))
	if done:
		advance(id)


# The items of a collect step are handed over at the next talk
func _consume_collected(d: Dictionary) -> void:
	var i := int(state(d["id"]).get("step", 0))
	if i <= 0:
		return
	var prev: Dictionary = d["steps"][i - 1]
	if prev["do"] != "collect":
		return
	var it := load(String(prev["item"])) as ItemData if ResourceLoader.exists(String(prev["item"])) else null
	if it != null:
		_inv().remove_item(it, mini(int(prev["count"]), _inv().get_count(it)))


func _foes_dead(id: String, i: int, step: Dictionary) -> bool:
	var n := 0
	for f: Array in step["foes"]:
		for k in int(f[1]):
			if not WorldState.has_record("kill/" + _foe_key(id, i, n)):
				return false
			n += 1
	return n > 0


# ---------------------------------------------------------------- people and foes in the world

func _tend_spawns() -> void:
	var p := _player().global_position
	if world.dungeons != null and world.dungeons.is_inside():
		return  # nothing appears outside while you are in a building or dungeon
	var wanted := {}
	for id in ids():
		var d: Dictionary = _defs[id]
		var st := status(id)
		if st == "" and d["giver"].has("spawn") and can_start(d):
			_want_talker(wanted, id, d["giver"], d, p)
		elif st == "active":
			if d["giver"].has("spawn"):
				_want_talker(wanted, id, d["giver"], d, p)
			var step := _step(d)
			if step.get("who", {}).has("spawn"):
				_want_talker(wanted, id, step["who"], d, p)
			if step.get("do", "") == "fight":
				_want_foes(wanted, id, step, p)
	for key in _spawned.keys():
		var e: Enemy = _spawned[key]
		if not is_instance_valid(e):
			_spawned.erase(key)
		elif not wanted.has(key) and (e.is_dead() or e.global_position.distance_to(p) > SPAWN_FAR or String(e.get_meta("qb_npc", "")) != ""):
			if not e.is_dead():
				e.queue_free()
			_spawned.erase(key)


func _want_talker(wanted: Dictionary, id: String, who: Dictionary, _d: Dictionary, p: Vector3) -> void:
	var key := _talker_key(id, who)
	var at := _spawn_place_pos(id, who)
	if not at.is_finite() or Vector2(at.x - p.x, at.z - p.z).length() > TALKER_NEAR:
		return
	wanted[key] = true
	if _spawned.has(key) and is_instance_valid(_spawned[key]):
		return
	var e := Enemy.create()
	e.display_name = String(who["name"])
	e.talk_name = String(who["name"])
	e.talk_lines = PackedStringArray(["..."])
	e.disposition = Enemy.Disposition.NEUTRAL
	e.placeholder_color = Color(0.45, 0.38, 0.30)
	e.max_health = 200.0
	e.persist_mode = Enemy.PersistMode.NEVER
	e.set_meta("qb_npc", key)
	at.y = world.get_height_at(at.x, at.z) + 0.6
	e.position = at
	world.add_child(e)
	_spawned[key] = e


func _want_foes(wanted: Dictionary, id: String, step: Dictionary, p: Vector3) -> void:
	var i := int(state(id).get("step", 0))
	var place: Dictionary = state(id).get("places", {}).get(str(i), {})
	var at := _vec(place.get("pos", []))
	if not at.is_finite() or Vector2(at.x - p.x, at.z - p.z).length() > SPAWN_NEAR:
		return
	var zone := LevelCurve.zone_range(world.map, at) if world.map != null else Vector2i(1, 5)
	var n := 0
	for f: Array in step["foes"]:
		var body := load(ENEMY_DIR + String(f[0]) + ".tres") as EnemyData if ResourceLoader.exists(ENEMY_DIR + String(f[0]) + ".tres") else null
		for k in int(f[1]):
			var key := _foe_key(id, i, n)
			n += 1
			if body == null or WorldState.has_record("kill/" + key):
				continue
			wanted[key] = true
			if _spawned.has(key) and is_instance_valid(_spawned[key]):
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = key.hash()
			var ang := rng.randf() * TAU
			var pos := at + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(2.0, 9.0)
			pos.y = world.get_height_at(pos.x, pos.z) + 0.6
			var named := String(f[2]) != ""
			var e := Population.spawn_enemy(body, zone.y + (3 if named else 1), world, pos, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
			if named:
				e.display_name = String(f[2])
			e.set_meta("quest_id", id)
			_spawned[key] = e


func _despawn_step(id: String, i: int) -> void:
	for key in _spawned.keys():
		if String(key).begins_with("qb/%s/%d/" % [id, i]):
			var e: Enemy = _spawned[key]
			if is_instance_valid(e) and not e.is_dead():
				e.queue_free()
			_spawned.erase(key)


static func _foe_key(id: String, step: int, n: int) -> String:
	return "qb/%s/%d/%d" % [id, step, n]


static func _talker_key(id: String, who: Dictionary) -> String:
	return "qbnpc/%s/%s" % [id, who.get("name", "")]


static func _item_key(id: String, which: String) -> String:
	return "qb_%s_%s" % [id, which]


func _spawn_place_pos(id: String, who: Dictionary) -> Vector3:
	var key := "talker/" + String(who["name"])
	var st := state(id)
	if st.get("places", {}).has(key):
		return _vec(st["places"][key].get("pos", []))
	var cached: Array = WorldState.get_record("qb_talkers").get(id + "|" + key, [])
	if not cached.is_empty():
		return _vec(cached)
	var place := _resolve(who["spawn"], id)
	var pos := _vec(place.get("pos", []))
	if pos.is_finite():
		var rec := WorldState.get_record("qb_talkers").duplicate()
		rec[id + "|" + key] = [pos.x, pos.y, pos.z]
		WorldState.set_record("qb_talkers", rec)
	return pos


## ContainerComponent asks: should this chest hold a quest item? (once each)
func fill_container(c: ContainerComponent) -> void:
	if c.save_id == "" or not c.save_id.ends_with("/chest_boss"):
		return
	for id in ids():
		if not is_active(id):
			continue
		var d: Dictionary = _defs[id]
		var step := _step(d)
		if step.get("do", "") != "fetch":
			continue
		var st := state(id)
		var i := int(st.get("step", 0))
		var place: Dictionary = st.get("places", {}).get(str(i), {})
		if place.has("poi") and c.save_id == "dungeon/%s/chest_boss" % place["poi"] and not bool(place.get("placed", false)):
			c.inventory.add_item(QuestItems.get_item(_item_key(id, str(i)), String(step["item"])))
			var st2 := st.duplicate(true)
			st2["places"][str(i)]["placed"] = true
			_store(id, st2)


# ---------------------------------------------------------------- places

func _resolve(place: Dictionary, qid: String) -> Dictionary:
	if world == null:
		return {}
	if place.has("town"):
		var t := _town(String(place["town"]))
		if t == null:
			return {}
		var seat := t.town.get_seat() if t.town != null else null
		var p := seat.get_door_position() if seat != null else t.position
		return {"pos": [p.x, p.y, p.z], "town": t.id}
	if place.has("dungeon") or place.has("camp"):
		var near := _near_pos(String(place.get("dungeon", place.get("camp", ""))))
		var dungeon := place.has("dungeon")
		var used := _used_pois()
		var fresh: Array[PlacedPOI] = []
		var any: Array[PlacedPOI] = []
		for p in world.pois:
			if p.town != null:
				continue
			if dungeon:
				var e := p.poi as DungeonEntrancePOIData
				if e == null or e.dungeon == null or e.dungeon.boss == null:
					continue
			elif not (p.poi is SimplePOIData and p.poi.garrison != null):
				continue
			any.append(p)
			if not used.has(p.id) and not Discovery.is_cleared(p.id):
				fresh.append(p)
		var list := fresh if not fresh.is_empty() else any
		if list.is_empty():
			return {}
		list.sort_custom(func(a: PlacedPOI, b: PlacedPOI) -> bool:
			return a.position.distance_squared_to(near) < b.position.distance_squared_to(near))
		var pick := list[clampi(int(place.get("k", 0)), 0, list.size() - 1)]
		return {"pos": [pick.position.x, pick.position.y, pick.position.z], "poi": pick.id}
	if place.has("wild"):
		var c := _near_pos(String(place["wild"]))
		var a := deg_to_rad(float(place.get("ang", 0.0)) + float(absi(qid.hash()) % 60) - 30.0)
		var p := c + Vector3(cos(a), 0.0, sin(a)) * float(place.get("dist", 350.0))
		p.y = world.get_height_at(p.x, p.z)
		if world.map != null and world.map.is_under_water(p.y):
			p = c.lerp(p, 0.5)  # don't send anyone into a lake
			p.y = world.get_height_at(p.x, p.z)
		return {"pos": [p.x, p.y, p.z]}
	return {}


# Dungeons and camps other active quests are using (so two quests don't share one)
func _used_pois() -> Dictionary:
	var out := {}
	for id in ids():
		if not is_active(id):
			continue
		for pl: Dictionary in state(id).get("places", {}).values():
			if pl.has("poi"):
				out[pl["poi"]] = true
	return out


func _town(town_name: String) -> PlacedPOI:
	for t in world.towns:
		if t.town != null and t.town.display_name == town_name:
			return t
	return null


# A town's middle, or the middle of a biome's biggest region
func _near_pos(place: String) -> Vector3:
	var t := _town(place)
	if t != null:
		return t.position
	if world.map != null:
		var best := -1
		var area := 0.0
		for i in world.map.placements.size():
			if world.map.placements[i].biome.get_key() == place:
				var a := world.map.get_placement_rect(i).get_area()
				if a > area:
					area = a
					best = i
		if best >= 0:
			var c := world.map.get_placement_rect(best).get_center()
			return Vector3(c.x, world.get_height_at(c.x, c.y), c.y)
	return _player().global_position


func _person_pos(who: Dictionary, d: Dictionary) -> Vector3:
	if who.has("giver"):
		who = d["giver"]
	if who.has("lord"):
		var t := _town(String(who["lord"]))
		var seat := t.town.get_seat() if t != null and t.town != null else null
		return seat.world_pos if seat != null else (t.position if t != null else Vector3.INF)
	if who.has("cast"):
		var t := _town(String(who["town"]))
		if t != null and t.town != null:
			for b in t.town.buildings:
				if b.owner_name == String(who["cast"]):
					return b.world_pos
			return t.position
		return Vector3.INF
	if who.has("leader"):
		var fd := Factions.get_data(String(who["leader"]))
		if fd != null and fd.leader_name != "":
			return _person_pos({"cast": fd.leader_name, "town": fd.leader_town}, d)
	if who.has("guild"):
		var best := Vector3.INF
		var p := _player().global_position
		for t in world.towns:
			for b in t.town.buildings:
				if b.kind == BuildingPlot.Kind.GUILD_HALL and b.guild == String(who["guild"]) and (not best.is_finite() or b.world_pos.distance_to(p) < best.distance_to(p)):
					best = b.world_pos
		return best
	if who.has("spawn"):
		return _spawn_place_pos(String(d["id"]), who)
	if who.has("realm_npc"):
		return RealmManager.gate_position(world, String(who["realm"]))
	return Vector3.INF


# ---------------------------------------------------------------- the map

## Active quests' targets: [{"pos": Vector2, "name"}]
static func targets() -> Array:
	var out: Array = []
	for id in ids():
		var st := state(id)
		if String(st.get("status", "")) == "active" and st.has("pos"):
			out.append({"pos": Vector2(float(st["pos"][0]), float(st["pos"][1])), "name": String(_defs[id]["name"]), "id": id})
	return out


# ---------------------------------------------------------------- clans and the pack

# A cure ends membership of anything that needs the affliction
func _check_expulsions() -> void:
	for f in Factions.IDS:
		var fd := Factions.get_data(f)
		if fd == null or fd.requires_affliction == "" or not Factions.is_member(f):
			continue
		if not _afflicted(fd.requires_affliction):
			Factions.expel(f)
			Locks.toast(get_tree(), "Cured, you are no longer one of the %s." % fd.display_name, true)


# ---------------------------------------------------------------- helpers

func _journal(d: Dictionary, text: String) -> void:
	if text.strip_edges() == "":
		return
	var clock := world.clock if world != null else null
	DialogueState.add_journal({"text": text, "speaker": "", "topic": "", "day": clock.day if clock != null else 1,
		"time": clock.get_time_text() if clock != null else "", "quest_id": String(d["id"]), "quest_name": String(d["name"])})


func _hours() -> float:
	var clock := world.clock if world != null else null
	return float(clock.day) * 24.0 + clock.hour if clock != null else 0.0


static func _vec(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _inv() -> Inventory:
	return _player().get_node("Inventory") as Inventory


# ---------------------------------------------------------------- for tests and debugging

## Finishes a quest at once (rewards and all), starting it first if needed
func debug_complete(id: String) -> void:
	if status(id) == "":
		start(id)
	finish(id)
