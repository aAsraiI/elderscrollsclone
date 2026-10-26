class_name QuestRunner
extends Node
## Runs the handmade quests (QuestData, every .tres in data/quests/). Created by WorldManager.
## Each quest's live copy (the instance) is saved in WorldState "qi/<id>"; the QuestData itself
## is never changed. Only ids are saved (QuestTargets), never nodes.
##
## States, and the only changes allowed between them (anything else is refused and logged):
##   unavailable -> available -> active -> ready -> completed
##   active / ready -> failed, abandoned      available -> expired (an offer never taken)
##   failed / abandoned / expired -> available (when the quest allows a retry)
## Progress comes from QuestEvents (kills, talks, thefts...) and from a look at the world twice a
## second (what you carry, where you stand, how much someone likes you, time limits).
## In dialogue: the giver offers the quest under its hook; TALK and DELIVER objectives and choices
## are topics of their people; "report back" hands it in (with the turn-in person dead, the
## town's lord or a guild leader takes it, as the quest says).

const DIR := "res://data/quests"
const STATE := "qi/"
const REPORT := "report back"
const SPAWN_NEAR := 150.0
const RETRY_HOURS := 72.0
const TRANSITIONS := {
	"unavailable": ["available"],
	"available": ["active", "expired", "unavailable"],
	"active": ["ready", "completed", "failed", "abandoned"],
	"ready": ["completed", "failed", "abandoned", "active"],
	"completed": [],
	"failed": ["available"],
	"abandoned": ["available"],
	"expired": ["available"],
}
const ENDED := ["completed", "failed", "abandoned", "expired"]

static var _list: Array[QuestData] = []
static var _loaded := false

var world: WorldManager
var _timer := 0.0
var _spawned := {}  # spawn key -> Enemy


func _ready() -> void:
	add_to_group("quest_runner")
	world = get_parent() as WorldManager
	var sm := get_tree().get_first_node_in_group("save_manager") as SaveManager
	if sm != null:
		sm.loaded.connect(func(_slot: String) -> void: recompute())


static func of(tree: SceneTree) -> QuestRunner:
	return tree.get_first_node_in_group("quest_runner") as QuestRunner if tree != null else null


# ---------------------------------------------------------------- the quests

## Every QuestData in data/quests/ that is not a template
static func all() -> Array[QuestData]:
	if not _loaded:
		_loaded = true
		var names := PackedStringArray()
		for f in DirAccess.get_files_at(DIR):
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres") and not names.has(file):
				names.append(file)
		names.sort()
		for file in names:
			var d := load(DIR + "/" + file) as QuestData
			if d != null and not d.template and d.id != "":
				_list.append(d)
	return _list


## Adds a quest at runtime (tests, or quests made by code)
static func register(d: QuestData) -> void:
	all()
	if get_data(d.id) == null:
		_list.append(d)


static func get_data(id: String) -> QuestData:
	for d in all():
		if d.id == id:
			return d
	return null


static func record(id: String) -> Dictionary:
	return WorldState.get_record(STATE + id)


static func _store(id: String, rec: Dictionary) -> void:
	WorldState.set_record(STATE + id, rec)


## The quest's state (see the list at the top). Never started = available or unavailable.
func status(id: String) -> String:
	var rec := record(id)
	var st := String(rec.get("state", ""))
	if st == "" or st == "unavailable" or st == "available":
		var d := get_data(id)
		return "available" if d != null and _requirements_met(d) else "unavailable"
	return st


static func is_finished_anywhere(key: String) -> bool:
	if String(record(key).get("state", "")) == "completed":
		return true
	if QuestBook.is_done(key):
		return true
	if key == "story":
		return Story.stage() >= 6
	var job := QuestManager.get_quest(key)
	return not job.is_empty() and job["status"] == "done"


static func is_active_anywhere(key: String) -> bool:
	var st := String(record(key).get("state", ""))
	if st == "active" or st == "ready":
		return true
	if QuestBook.is_active(key):
		return true
	if key == "story":
		return Story.stage() > 0 and Story.stage() < 6
	var job := QuestManager.get_quest(key)
	return not job.is_empty() and job["status"] == "active"


func _requirements_met(d: QuestData) -> bool:
	for a in d.after:
		if not is_finished_anywhere(a):
			return false
	return QuestCondition.all_pass(d.requirements, get_tree())


## Can the giver offer it now?
func can_offer(d: QuestData) -> bool:
	var rec := record(d.id)
	var st := String(rec.get("state", ""))
	if st in ["active", "ready", "completed"]:
		return false
	if st in ["failed", "abandoned", "expired"]:
		if not d.retry or _hours() - float(rec.get("ended_at", 0.0)) < RETRY_HOURS:
			return false
	return _requirements_met(d)


# ---------------------------------------------------------------- changing state

## Moves a quest to a new state. Refused (and logged) when the change isn't allowed.
func set_state(id: String, to: String, why: String = "") -> bool:
	var rec := record(id).duplicate(true)
	var from := String(rec.get("state", "unavailable"))
	if from == "":
		from = "unavailable"
	if not (TRANSITIONS.get(from, []) as Array).has(to):
		push_warning("[Quest] %s: %s -> %s is not allowed" % [id, from, to])
		return false
	rec["state"] = to
	if to in ENDED:
		rec["ended_at"] = _hours()
		rec["ended_day"] = _day()
		if why != "":
			rec["why"] = why
	_store(id, rec)
	var d := get_data(id)
	QuestManager.log_quest({"id": id, "name": d.title if d != null else id}, "%s -> %s%s" % [from, to, (": " + why) if why != "" else ""])
	return true


func start(id: String) -> bool:
	var d := get_data(id)
	if d == null or not can_offer(d):
		return false
	var old := String(record(id).get("state", ""))
	if old in ["failed", "abandoned", "expired"]:
		set_state(id, "available", "offered again")
	_store(id, {"state": "available", "stage": 0, "done": {}, "flags": [], "t0": _hours(), "history": record(id).get("history", [])})
	if not set_state(id, "active"):
		return false
	_journal(d, d.intro if d.intro != "" else d.description)
	Notices.quest(get_tree(), "Quest started", d.title)
	_begin_stage(id, 0)
	return true


func _begin_stage(id: String, i: int) -> void:
	var d := get_data(id)
	if i < 0 or i >= d.stages.size():
		_stages_done(id)
		return
	var rec := record(id).duplicate(true)
	rec["stage"] = i
	_store(id, rec)
	_journal(d, d.stages[i].text)
	QuestManager.log_quest({"id": id, "name": d.title}, "stage %d of %d" % [i + 1, d.stages.size()])
	_check_stage(id)


func _stages_done(id: String) -> void:
	var d := get_data(id)
	if d.completion == QuestData.Completion.AUTO:
		complete(id)
		return
	if set_state(id, "ready"):
		var who := _turn_in_name(d)
		_journal(d, "Done. Now report back to %s." % who)
		Notices.quest(get_tree(), "Ready to turn in", "%s: report back to %s" % [d.title, who])


## Gives the rewards and ends the quest as completed. Returns the gold given.
func complete(id: String, pick: int = -1) -> int:
	var d := get_data(id)
	var st := String(record(id).get("state", ""))
	if d == null or not (st == "active" or st == "ready"):
		return 0
	if not d.reward_choice.is_empty() and pick < 0:
		return 0  # a reward still has to be picked ("take the ...")
	_hand_over(d)
	var p := _player()
	var inv := p.get_node("Inventory") as Inventory
	var lines := PackedStringArray()
	var gold := reward_gold(d)
	if gold > 0:
		Currency.add_gold(inv, gold)
		lines.append("%d gold" % gold)
	for it in d.reward_items:
		if it != null:
			inv.add_item(it, 1)  # never lost: an inventory takes anything (you may be slowed)
			lines.append(it.display_name)
	if pick >= 0 and pick < d.reward_choice.size() and d.reward_choice[pick] != null:
		inv.add_item(d.reward_choice[pick], 1)
		lines.append(d.reward_choice[pick].display_name)
	var bonus := _bonus_gold(id)
	if bonus > 0:
		Currency.add_gold(inv, bonus)
		lines.append("%d bonus gold" % bonus)
	var skills := p.get_node_or_null("Skills") as Skills
	if skills != null:
		if d.reward_skill != "" and d.reward_skill_xp > 0.0:
			skills.add_xp(StringName(d.reward_skill), d.reward_skill_xp)
			lines.append("%s experience" % d.reward_skill.capitalize())
		skills.add_deed_xp(SkillDatabase.deed_xp(skills.get_player_level(), 4.0 + d.stages.size()))
	if d.reward_rep_with != "" and d.reward_rep != 0:
		Reputation.add(d.reward_rep_with, d.reward_rep)
		lines.append("reputation with %s" % (Factions.display_name(d.reward_rep_with) if Factions.get_data(d.reward_rep_with) != null else d.reward_rep_with))
	var town := QuestTargets.person_town(world, d.giver)
	if town != null and town.town != null:
		Reputation.add_fame(town.town.display_name, 2)
	if d.reward_flag != "":
		DialogueState.set_flag(d.reward_flag)
	set_state(id, "completed")
	var rec := record(id).duplicate(true)
	rec["reward"] = lines
	_store(id, rec)
	_journal(d, "Quest complete: %s.%s" % [d.title, (" You got " + ", ".join(lines) + ".") if not lines.is_empty() else ""])
	Notices.quest(get_tree(), "Quest completed", d.title)
	if d.follow_up != "" and get_data(d.follow_up) != null:
		var next := get_data(d.follow_up)
		if next.giver == "" and can_offer(next):
			start(next.id)
	return gold


## The gold a quest pays, grown with the player's level
func reward_gold(d: QuestData) -> int:
	var skills := _player().get_node_or_null("Skills") as Skills if _player() != null else null
	var lvl := skills.get_player_level() if skills != null else 1
	return d.reward_gold + d.gold_per_level * maxi(lvl - d.level, 0)


## What you'd get, for the offer and the turn-in ("150 gold, Iron Sword, or one of: ...")
func reward_text(d: QuestData) -> String:
	var parts := PackedStringArray()
	if reward_gold(d) > 0:
		parts.append("%d gold" % reward_gold(d))
	for it in d.reward_items:
		if it != null:
			parts.append(it.display_name)
	if not d.reward_choice.is_empty():
		var names := PackedStringArray()
		for it in d.reward_choice:
			if it != null:
				names.append(it.display_name)
		parts.append("your pick of " + " or ".join(names))
	if d.reward_skill != "":
		parts.append("training in %s" % d.reward_skill.capitalize())
	return ", ".join(parts) if not parts.is_empty() else "thanks"


# Collected and delivered items go to whoever wanted them: exactly the right stack and count
func _hand_over(d: QuestData) -> PackedStringArray:
	var out := PackedStringArray()
	var inv := _player().get_node("Inventory") as Inventory
	for st in d.stages:
		for o in st.objectives:
			if o.type == QuestObjective.Type.COLLECT:
				var it := _item(o.target)
				if it != null and inv.get_count(it) > 0:
					var n := mini(o.count, inv.get_count(it))
					inv.remove_item(it, n)
					out.append("%d %s" % [n, it.display_name])
	return out


func _bonus_gold(id: String) -> int:
	var d := get_data(id)
	var done: Dictionary = record(id).get("done", {})
	var total := 0
	for si in d.stages.size():
		var st := d.stages[si]
		for oi in st.objectives.size():
			var o := st.objectives[oi]
			if o.bonus and int(done.get("%d:%d" % [si, oi], 0)) >= o.count:
				total += o.bonus_gold
	return total


func fail(id: String, why: String) -> void:
	var d := get_data(id)
	if d == null or not set_state(id, "failed", why):
		return
	_despawn(id)
	_journal(d, "Failed: %s. %s" % [d.title, why])
	Notices.quest(get_tree(), "Quest failed", "%s: %s" % [d.title, why], true)


## Gives up a quest: the giver's town (and guild) think less of you
func abandon(id: String) -> void:
	var d := get_data(id)
	if d == null or not set_state(id, "abandoned", "You gave it up."):
		return
	_despawn(id)
	var town := QuestTargets.person_town(world, d.giver)
	if town != null and town.town != null:
		Reputation.add_fame(town.town.display_name, -2)
	if d.reward_rep_with != "":
		Reputation.add(d.reward_rep_with, -maxi(d.reward_rep / 2, 1))
	_journal(d, "Abandoned: %s." % d.title)
	Notices.quest(get_tree(), "Quest abandoned", d.title, true)


# ---------------------------------------------------------------- progress

func on_event(kind: String, data: Dictionary) -> void:
	for d in all():
		var rec := record(d.id)
		if String(rec.get("state", "")) != "active":
			continue
		var si := int(rec.get("stage", 0))
		var st := d.stages[si] if si < d.stages.size() else null
		if st == null:
			continue
		var changed := false
		for oi in st.objectives.size():
			if not _is_current(d, si, oi):
				continue
			var o := st.objectives[oi]
			var key := "%d:%d" % [si, oi]
			var have := int(rec.get("done", {}).get(key, 0))
			if have >= o.count:
				continue
			var add := 0
			match kind:
				"kill":
					if o.type == QuestObjective.Type.KILL:
						var e := data.get("enemy") as Enemy
						var own := String(data.get("key", "")).begins_with(_spawn_prefix(d.id, si, oi))
						if own or (o.spawn == "" and QuestTargets.enemy_matches(e, o.target)):
							add = 1
				"steal":
					if o.type == QuestObjective.Type.STEAL and _item_matches(data.get("item") as ItemData, o.target):
						add = int(data.get("count", 1))
				"use":
					if o.type == QuestObjective.Type.USE_ITEM and _item_matches(data.get("item") as ItemData, o.target):
						add = 1
				"discover":
					if o.type == QuestObjective.Type.DISCOVER and (String(data["poi"]) == o.place or QuestTargets.place(world, o.place).get("poi", "") == data["poi"]):
						add = o.count
				"enter":
					if o.type == QuestObjective.Type.REACH and QuestTargets.place(world, o.place).get("poi", "-") == data["place"]:
						add = o.count
			if add > 0:
				_set_count(d, si, oi, mini(have + add, o.count))
				changed = true
		if changed:
			_check_stage(d.id)


func _set_count(d: QuestData, si: int, oi: int, n: int) -> void:
	var rec := record(d.id).duplicate(true)
	var done: Dictionary = rec.get("done", {})
	var key := "%d:%d" % [si, oi]
	if int(done.get(key, 0)) == n:
		return
	done[key] = n
	rec["done"] = done
	_store(d.id, rec)
	var o := d.stages[si].objectives[oi]
	if n >= o.count:
		Notices.quest(get_tree(), "Objective complete", _objective_text(d, o))
	elif o.count > 1:
		Notices.quest(get_tree(), "Objective updated", "%s (%d/%d)" % [_objective_text(d, o), n, o.count])


# Sequential stages: only the first unfinished objective counts
func _is_current(d: QuestData, si: int, oi: int) -> bool:
	var st := d.stages[si]
	if not st.sequential:
		return true
	var done: Dictionary = record(d.id).get("done", {})
	for k in oi:
		if not st.objectives[k].optional and int(done.get("%d:%d" % [si, k], 0)) < st.objectives[k].count:
			return false
	return true


func _check_stage(id: String) -> void:
	var d := get_data(id)
	var rec := record(id)
	if String(rec.get("state", "")) != "active":
		return
	var si := int(rec.get("stage", 0))
	if si >= d.stages.size():
		_stages_done(id)
		return
	var st := d.stages[si]
	var done: Dictionary = rec.get("done", {})
	for oi in st.objectives.size():
		var o := st.objectives[oi]
		if not o.optional and not o.bonus and int(done.get("%d:%d" % [si, oi], 0)) < o.count:
			return
	if not st.choices.is_empty():
		return  # a choice ends this stage (in dialogue)
	_despawn_stage(id, si)
	_begin_stage(id, st.next if st.next >= 0 else si + 1)


func _process(delta: float) -> void:
	if world == null or get_tree().paused:
		return
	_timer += delta
	if _timer < 0.5:
		return
	_timer = 0.0
	var p := _player()
	if p == null:
		return
	for d in all():
		var rec := record(d.id)
		var st := String(rec.get("state", ""))
		if st == "active" or st == "ready":
			if d.time_limit_hours > 0.0 and _hours() - float(rec.get("t0", 0.0)) > d.time_limit_hours:
				fail(d.id, "You ran out of time.")
				continue
		if st == "active":
			_tick_objectives(d, rec, p)
		elif st == "ready" and _needs_item_back(d):
			set_state(d.id, "active", "the items were no longer carried")
		elif (st == "" or st == "available") and d.offer_days > 0 and rec.has("offered_at") and _hours() - float(rec["offered_at"]) > d.offer_days * 24.0:
			set_state(d.id, "expired", "The offer ran out.")


func _tick_objectives(d: QuestData, rec: Dictionary, p: Node3D) -> void:
	var si := int(rec.get("stage", 0))
	if si >= d.stages.size():
		return
	var st := d.stages[si]
	var inv := p.get_node("Inventory") as Inventory
	for oi in st.objectives.size():
		if not _is_current(d, si, oi):
			continue
		var o := st.objectives[oi]
		match o.type:
			QuestObjective.Type.COLLECT:
				var it := _item(o.target)
				_set_count(d, si, oi, mini(inv.get_count(it), o.count) if it != null else 0)
			QuestObjective.Type.REACH:
				var pl := QuestTargets.place(world, o.place)
				if o.target.begins_with("room:"):
					# a room inside the place's dungeon ("room:boss", "room:war_room")
					var dm := world.dungeons
					if dm != null and dm.nav != null and (pl.is_empty() or String(pl.get("poi", dm.current_entrance_id)) == dm.current_entrance_id):
						var here := dm.nav.room_of(p)
						if here >= 0 and dm.nav.room_is(here, o.target.substr(5)):
							_set_count(d, si, oi, o.count)
				elif not pl.is_empty():
					var at: Vector3 = pl["pos"]
					if Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() <= o.radius:
						_set_count(d, si, oi, o.count)
			QuestObjective.Type.PERSUADE:
				var r := QuestTargets.resident(world, o.who)
				if r != null and DialogueState.get_disposition(r.data.id, r.data.base_disposition) >= o.count:
					_set_count(d, si, oi, 1)
				if QuestTargets.is_gone(world, o.who):
					fail(d.id, "%s is dead." % o.who.get_slice("@", 0))
					return
			QuestObjective.Type.DELIVER, QuestObjective.Type.TALK:
				if o.who != "" and QuestTargets.is_gone(world, o.who) and o.who != d.turn_in_who():
					fail(d.id, "%s is dead: no one is left to ask." % o.who.get_slice("@", 0))
					return
			QuestObjective.Type.KILL:
				if o.spawn != "":
					_tend_spawn(d, si, oi, o, p)
	_check_stage(d.id)


# A turn-in quest whose collected items were dropped goes back to collecting
func _needs_item_back(d: QuestData) -> bool:
	var inv := _player().get_node("Inventory") as Inventory
	for st in d.stages:
		for o in st.objectives:
			if o.type == QuestObjective.Type.COLLECT and not o.optional:
				var it := _item(o.target)
				if it != null and inv.get_count(it) < o.count:
					return true
	return false


## After loading a save: spawned foes, counts and states are worked out again from the records
func recompute() -> void:
	_spawned.clear()
	for d in all():
		var rec := record(d.id)
		if String(rec.get("state", "")) != "active":
			continue
		var si := int(rec.get("stage", 0))
		if si < d.stages.size():
			for oi in d.stages[si].objectives.size():
				var o := d.stages[si].objectives[oi]
				if o.type == QuestObjective.Type.KILL and o.spawn != "":
					var dead := 0
					for n in o.count:
						if WorldState.has_record("kill/" + _spawn_prefix(d.id, si, oi) + str(n)):
							dead += 1
					_set_count(d, si, oi, dead)
		_check_stage(d.id)


# ---------------------------------------------------------------- foes made for a quest

static func _spawn_prefix(id: String, si: int, oi: int) -> String:
	return "qi/%s/%d/%d/" % [id, si, oi]


func _tend_spawn(d: QuestData, si: int, oi: int, o: QuestObjective, p: Node3D) -> void:
	var pl := QuestTargets.place(world, o.place)
	if pl.is_empty():
		return
	var at: Vector3 = pl["pos"]
	if Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() > SPAWN_NEAR or (world.dungeons != null and world.dungeons.is_inside()):
		return
	var body := load(o.spawn) as EnemyData if ResourceLoader.exists(o.spawn) else null
	if body == null:
		return
	var zone := LevelCurve.zone_range(world.map, at) if world.map != null else Vector2i(1, 5)
	for n in o.count:
		var key := _spawn_prefix(d.id, si, oi) + str(n)
		if WorldState.has_record("kill/" + key) or (_spawned.has(key) and is_instance_valid(_spawned[key])):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = key.hash()
		var pos := at + Vector3(rng.randf_range(-6, 6), 0.0, rng.randf_range(-6, 6))
		pos.y = world.get_height_at(pos.x, pos.z) + 0.6
		var e := Population.spawn_enemy(body, maxi(zone.y, d.level), world, pos, rng, {"key": key, "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
		if o.target != "" and n == 0 and not o.target.begins_with("res://"):
			e.display_name = o.target
		e.set_meta("quest_id", d.id)
		e.set_meta("quest_critical", true)
		_spawned[key] = e


func _despawn_stage(id: String, si: int) -> void:
	for key in _spawned.keys():
		if String(key).begins_with("qi/%s/%d/" % [id, si]):
			var e: Enemy = _spawned[key]
			if is_instance_valid(e) and not e.is_dead():
				e.queue_free()
			_spawned.erase(key)


func _despawn(id: String) -> void:
	for key in _spawned.keys():
		if String(key).begins_with("qi/%s/" % id):
			var e: Enemy = _spawned[key]
			if is_instance_valid(e) and not e.is_dead():
				e.queue_free()
			_spawned.erase(key)


# ---------------------------------------------------------------- dialogue

## The topics this person has for quests now
func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	for d in all():
		var rec := record(d.id)
		var st := String(rec.get("state", ""))
		if st in ["", "available", "unavailable", "failed", "abandoned", "expired"]:
			if d.giver != "" and d.hook != "" and QuestTargets.is_person(s, d.giver, world) and can_offer(d):
				out.append(d.hook)
				if not rec.has("offered_at") or String(rec.get("state", "")) != "available":
					var r2 := rec.duplicate()
					r2["offered_at"] = _hours()
					r2["state"] = "available"  # offered: the offer can now run out (offer_days)
					_store(d.id, r2)
			continue
		if st == "ready" and _takes_in(s, d):
			if d.reward_choice.is_empty():
				out.append(REPORT)
			else:
				for it in d.reward_choice:
					if it != null:
						out.append("take the " + it.display_name.to_lower())
			continue
		if st != "active":
			continue
		var si := int(rec.get("stage", 0))
		if si >= d.stages.size():
			continue
		var stage := d.stages[si]
		for oi in stage.objectives.size():
			var o := stage.objectives[oi]
			if (o.type == QuestObjective.Type.TALK or o.type == QuestObjective.Type.DELIVER) and _is_current(d, si, oi) \
					and int(rec.get("done", {}).get("%d:%d" % [si, oi], 0)) < o.count and QuestTargets.is_person(s, o.who, world):
				out.append(o.topic)
		for c in stage.choices:
			if QuestTargets.is_person(s, c.who if c.who != "" else d.giver, world) and QuestCondition.all_pass(c.conditions, get_tree()):
				out.append(c.topic)
	return out


# Does this person take the quest in? (the turn-in person, or the fallback when they are gone)
func _takes_in(s: DialogueEngine.Speaker, d: QuestData) -> bool:
	var who := d.turn_in_who()
	if who == "" or QuestTargets.is_person(s, who, world):
		return who != "" or s != null
	if not QuestTargets.is_gone(world, who):
		return false
	match d.fallback:
		"lord":
			var town := QuestTargets.person_town(world, who)
			return s.role == NpcData.Role.LORD and town != null and s.town == town
		"":
			return false
	return Factions.leader_of(s, world) == d.fallback


func _turn_in_name(d: QuestData) -> String:
	var who := d.turn_in_who()
	if who == "":
		return "anyone who asked"
	if QuestTargets.is_gone(world, who):
		match d.fallback:
			"lord":
				var town := QuestTargets.person_town(world, who)
				return "the lord of %s (%s is dead)" % [town.town.display_name if town != null else "the town", who.get_slice("@", 0)]
			_:
				return "a leader of the %s" % Factions.display_name(d.fallback)
	var r := QuestTargets.resident(world, who)
	if r != null:
		return "%s in %s" % [r.data.display_name, r.town.town.display_name]
	for c in CustomNpcs.all():
		if c.save_id() == who:
			return c.display_name
	return who.get_slice("@", 0)


func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if not topics_for(s).has(topic):
		return {}
	for d in all():
		var rec := record(d.id)
		var st := String(rec.get("state", ""))
		if topic == d.hook and d.giver != "" and QuestTargets.is_person(s, d.giver, world) and can_offer(d):
			start(d.id)
			return _say("%s (Reward: %s.)" % [d.intro, reward_text(d)], d)
		if st == "ready" and _takes_in(s, d):
			var pick := -1
			for i in d.reward_choice.size():
				if d.reward_choice[i] != null and topic == "take the " + d.reward_choice[i].display_name.to_lower():
					pick = i
			if topic == REPORT or pick >= 0:
				var given := _handed_text(d)
				complete(d.id, pick)
				return _say("%s%s" % [d.turn_in_say, (" [You hand over %s.]" % given) if given != "" else ""], d)
		if st != "active":
			continue
		var si := int(rec.get("stage", 0))
		var stage := d.stages[si]
		for oi in stage.objectives.size():
			var o := stage.objectives[oi]
			if o.topic != topic or not QuestTargets.is_person(s, o.who, world) or not _is_current(d, si, oi):
				continue
			if o.type == QuestObjective.Type.DELIVER:
				var it := _item(o.target)
				var inv := _player().get_node("Inventory") as Inventory
				if it == null or inv.get_count(it) < o.count:
					return _say("You don't have it with you.", d)
				inv.remove_item(it, o.count)  # exactly this stack and count
			_set_count(d, si, oi, o.count)
			_check_stage(d.id)
			return _say(o.say if o.say != "" else "...", d)
		for c in stage.choices:
			if c.topic != topic:
				continue
			var r2 := record(d.id).duplicate(true)
			var flags: Array = r2.get("flags", [])
			flags.append(c.flag)
			r2["flags"] = flags
			_store(d.id, r2)
			if c.flag != "":
				QuestBook.set_flag("%s:%s" % [d.id, c.flag])
			if c.fails:
				fail(d.id, "The choice you made ended it.")
			else:
				_despawn_stage(d.id, si)
				_begin_stage(d.id, c.next if c.next >= 0 else d.stages.size())
			return _say(c.say, d)
	return {}


func _handed_text(d: QuestData) -> String:
	var parts := PackedStringArray()
	var inv := _player().get_node("Inventory") as Inventory
	for st in d.stages:
		for o in st.objectives:
			if o.type == QuestObjective.Type.COLLECT:
				var it := _item(o.target)
				if it != null and inv.get_count(it) > 0:
					parts.append("%d %s" % [mini(o.count, inv.get_count(it)), it.display_name])
	return ", ".join(parts)


func _say(text: String, d: QuestData) -> Dictionary:
	return {"text": text, "journal": true, "quest_id": d.id, "quest_name": d.title, "learn": PackedStringArray()}


# ---------------------------------------------------------------- the journal and the map

## The objectives of the current stage, for the journal and tracker:
## [{"text", "done": bool, "have", "need", "optional", "bonus"}] (hidden ones only once done)
func objectives_view(id: String) -> Array:
	var out: Array = []
	var d := get_data(id)
	var rec := record(id)
	if d == null:
		return out
	var si := int(rec.get("stage", 0))
	if si >= d.stages.size():
		return out
	var done: Dictionary = rec.get("done", {})
	for oi in d.stages[si].objectives.size():
		var o := d.stages[si].objectives[oi]
		var have := int(done.get("%d:%d" % [si, oi], 0))
		if o.hidden and have < o.count:
			continue
		out.append({"text": _objective_text(d, o), "done": have >= o.count, "have": have, "need": o.count, "optional": o.optional or o.bonus, "bonus": o.bonus})
	return out


func _objective_text(_d: QuestData, o: QuestObjective) -> String:
	if o.text != "":
		return o.text
	match o.type:
		QuestObjective.Type.KILL: return "Kill %s" % o.target
		QuestObjective.Type.COLLECT: return "Collect %s" % o.target.get_file().get_basename().capitalize()
		QuestObjective.Type.DELIVER: return "Bring it to %s" % o.who.get_slice("@", 0)
		QuestObjective.Type.TALK: return "Talk to %s about %s" % [o.who.get_slice("@", 0), o.topic]
		QuestObjective.Type.REACH: return "Go to %s" % o.place
		QuestObjective.Type.STEAL: return "Steal %s" % o.target.get_file().get_basename().capitalize()
		QuestObjective.Type.PERSUADE: return "Win over %s" % o.who.get_slice("@", 0)
		QuestObjective.Type.USE_ITEM: return "Use %s" % o.target.get_file().get_basename().capitalize()
		QuestObjective.Type.DISCOVER: return "Discover %s" % o.place
	return "?"


## The next thing to do, in a few words (journal and tracker)
func next_step(id: String) -> String:
	var d := get_data(id)
	var st := status(id)
	if st == "ready":
		return "Report back to %s." % _turn_in_name(d)
	for o: Dictionary in objectives_view(id):
		if not o["done"] and not o["optional"]:
			return String(o["text"]) + ("" if int(o["need"]) <= 1 else " (%d/%d)" % [o["have"], o["need"]])
	var si := int(record(id).get("stage", 0))
	if si < d.stages.size() and not d.stages[si].choices.is_empty():
		return "Make your choice."
	return ""


## Where active quests send you: [{"pos": Vector2, "name", "id"}]
func targets() -> Array:
	var out: Array = []
	for d in all():
		var st := String(record(d.id).get("state", ""))
		var at := Vector3.INF
		if st == "ready":
			at = QuestTargets.person_pos(world, d.turn_in_who())
		elif st == "active":
			var si := int(record(d.id).get("stage", 0))
			if si < d.stages.size():
				for oi in d.stages[si].objectives.size():
					var o := d.stages[si].objectives[oi]
					if not _is_current(d, si, oi) or int(record(d.id).get("done", {}).get("%d:%d" % [si, oi], 0)) >= o.count:
						continue
					if o.place != "":
						var pl := QuestTargets.place(world, o.place)
						at = pl.get("pos", Vector3.INF)
					elif o.who != "":
						at = QuestTargets.person_pos(world, o.who)
					if at.is_finite():
						break
		if at.is_finite():
			out.append({"pos": Vector2(at.x, at.z), "name": d.title, "id": d.id})
	return out


# ---------------------------------------------------------------- helpers

func _journal(d: QuestData, text: String) -> void:
	if text.strip_edges() == "":
		return
	var clock := world.clock if world != null else null
	DialogueState.add_journal({"text": text, "speaker": "", "topic": "", "day": clock.day if clock != null else 1,
		"time": clock.get_time_text() if clock != null else "", "quest_id": d.id, "quest_name": d.title})


static func _item(path: String) -> ItemData:
	if path.begins_with("res://"):
		return load(path) as ItemData if ResourceLoader.exists(path) else null
	for it in ItemCatalog.all_items():
		if String(it.id) == path or it.display_name == path:
			return it
	return null


static func _item_matches(item: ItemData, target: String) -> bool:
	return item != null and (item.resource_path == target or String(item.id) == target or item.display_name == target)


func _hours() -> float:
	var clock := world.clock if world != null else null
	return float(clock.day) * 24.0 + clock.hour if clock != null else 0.0


func _day() -> int:
	return world.clock.day if world != null and world.clock != null else 1


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
