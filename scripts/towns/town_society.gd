class_name TownSociety
extends Node
## Alpha 1.24: townsfolk living with each other, beside TownLife's day plan. Created by WorldManager.
##   relationships   everyone has a family (the household), friends, maybe a rival and a sweetheart;
##                   worked out the same every game for each town, changes kept in WorldState
##                   ("npc_rel/<id>"). Ask anyone about "people you know".
##   greetings       friends passing say hello, rivals glare, sweethearts are glad to see each other,
##                   guards changing watch have a word
##   news            what people mention in passing comes from what is going on (rumours, a dragon,
##                   your bounty, a death in town)
##   crowds          something hostile inside a town sends everyone outside running for their doors
##   grief           when someone dies their family and friends mourn for a week (dark clothes, the
##                   temple); if you killed them, the family may pay thugs to come after you
##   brawls          two rivals drinking at the inn of an evening come to blows (no one dies of it);
##                   afterwards they are rivals for good
##   errands         someone back from the shops carries a sack home
## Everything runs on a 1-second tick over the people near you only.

const TICK := 1.0
const GREET_RANGE := 4.5
const GREET_QUIET := 150.0  # seconds before the same two greet again
const MOURN_DAYS := 7
const REVENGE_CHANCE := 0.6
const CROWD_RADIUS := 95.0
const BRAWL_EVERY := 45.0
const BRAWL_CHANCE := 0.2
const TOPIC := "people you know"

var world: WorldManager
var _timer := 2.0
var _brawl_t := 20.0
var _webs := {}  # town id -> {npc id -> {other id -> kind}}
var _greeted := {}  # "a|b" -> seconds
var _dead_seen := {}  # npc id -> true (grief already handled)
var _brawl: Dictionary = {}  # {"a": Enemy, "b": Enemy, "until": float}
var _panic := {}  # town id -> seconds left
var _clock := 0.0
var _day_done := -1
var _boards := {}  # town id -> Readable
var _horned := {}  # town id -> seconds


func _ready() -> void:
	add_to_group("town_society")
	world = get_parent() as WorldManager
	if world != null:
		world.poi_spawned.connect(_on_poi_spawned)
		_catch_up.call_deferred()


static func of(tree: SceneTree) -> TownSociety:
	return tree.get_first_node_in_group("town_society") as TownSociety if tree != null else null


func _process(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer > 0.0 or world == null or world.life == null or get_tree().paused:
		return
	_timer = TICK
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	_daily()
	_gossip()
	_bodies_found()
	_grief()
	_revenge(p)
	_tick_brawl(p)
	if world.dungeons != null and world.dungeons.is_inside():
		return
	_crowds()
	_greetings(p)


# ---------------------------------------------------------------- the relationship web

## How a knows b: "family", "sweetheart", "friend", "rival" or "" (strangers)
func relation(a_id: String, b_id: String) -> String:
	var r := world.life.get_resident(a_id) if world != null and world.life != null else null
	if r == null:
		return ""
	return String(_web(r.town.id).get(a_id, {}).get(b_id, ""))


## Everyone a person knows: {other id: kind}
func known_by(npc_id: String) -> Dictionary:
	var r := world.life.get_resident(npc_id) if world != null and world.life != null else null
	return _web(r.town.id).get(npc_id, {}) if r != null else {}


## Changes how two people get on, both ways, from now on (a brawl, a rescue). Kept in the save.
func set_relation(a_id: String, b_id: String, kind: String) -> void:
	for pair in [[a_id, b_id], [b_id, a_id]]:
		var rec := WorldState.get_record("npc_rel/" + pair[0]).duplicate()
		rec[pair[1]] = kind
		WorldState.set_record("npc_rel/" + pair[0], rec)
	var r := world.life.get_resident(a_id)
	if r != null:
		_webs.erase(r.town.id)


func _web(town_id: String) -> Dictionary:
	if _webs.has(town_id):
		return _webs[town_id]
	var web := {}
	var folk: Array = world.life.get_town_residents(town_id)
	var by_home := {}
	for r: TownLife.Resident in folk:
		web[r.data.id] = {}
		if r.data.home_id != "":
			if not by_home.has(r.data.home_id):
				by_home[r.data.home_id] = []
			by_home[r.data.home_id].append(r)
	# a household is a family
	for home in by_home:
		var h: Array = by_home[home]
		for a: TownLife.Resident in h:
			for b: TownLife.Resident in h:
				if a != b:
					web[a.data.id][b.data.id] = "family"
	# friends, a rival, maybe a sweetheart: the same in every game for this town
	var n := folk.size()
	for i in n:
		var a: TownLife.Resident = folk[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s|web" % a.data.id).hash()
		if rng.randf() < 0.35:  # a relative elsewhere in town (one person lives in each house)
			var kin: TownLife.Resident = folk[(i + rng.randi_range(1, maxi(n - 1, 1))) % n]
			if kin != a:
				web[a.data.id][kin.data.id] = "family"
				web[kin.data.id][a.data.id] = "family"
		for k in rng.randi_range(1, 3):
			var b: TownLife.Resident = folk[(i + rng.randi_range(1, maxi(n - 1, 1))) % n]
			if b != a and not web[a.data.id].has(b.data.id):
				web[a.data.id][b.data.id] = "friend"
				if not web[b.data.id].has(a.data.id):
					web[b.data.id][a.data.id] = "friend"
		if rng.randf() < 0.4:
			var c: TownLife.Resident = folk[(i + rng.randi_range(1, maxi(n - 1, 1))) % n]
			if c != a and not web[a.data.id].has(c.data.id):
				web[a.data.id][c.data.id] = "rival"
				web[c.data.id][a.data.id] = "rival"
		if rng.randf() < 0.15 and a.data.role != NpcData.Role.GUARD:
			var s: TownLife.Resident = folk[(i + rng.randi_range(1, maxi(n - 1, 1))) % n]
			if s != a and s.data.home_id != a.data.home_id and not web[a.data.id].has(s.data.id) and not web[s.data.id].has(a.data.id):
				web[a.data.id][s.data.id] = "sweetheart"
				web[s.data.id][a.data.id] = "sweetheart"
	# what changed in this game
	for id in web:
		var rec := WorldState.get_record("npc_rel/" + String(id))
		for other in rec:
			if String(rec[other]) == "":
				web[id].erase(other)
			else:
				web[id][other] = String(rec[other])
	_webs[town_id] = web
	return web


func _name(npc_id: String) -> String:
	var r := world.life.get_resident(npc_id)
	return r.data.display_name if r != null else "someone"


func _first(npc_id: String) -> String:
	return _name(npc_id).get_slice(" ", 0)


# ---------------------------------------------------------------- dialogue: "people you know"

func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	if s == null or s.data == null or s.asleep or world == null or world.life == null or world.life.get_resident(s.data.id) == null:
		return PackedStringArray()
	return PackedStringArray([TOPIC]) if not known_by(s.data.id).is_empty() else PackedStringArray()


func respond(s: DialogueEngine.Speaker, topic: String) -> Dictionary:
	if topic != TOPIC or s == null or s.data == null:
		return {}
	var known := known_by(s.data.id)
	var by_kind := {"family": [], "sweetheart": [], "friend": [], "rival": []}
	for other in known:
		var r := world.life.get_resident(String(other))
		if r == null:
			continue
		var who := r.data.display_name + (" (gone now)" if r.dead else "")
		if by_kind.has(known[other]):
			by_kind[known[other]].append(who)
	var lines := PackedStringArray()
	if not by_kind["family"].is_empty():
		lines.append("My family: %s." % _and(by_kind["family"]))
	if not by_kind["friend"].is_empty():
		lines.append("%s %s good to me." % [_and(by_kind["friend"]), "is" if by_kind["friend"].size() == 1 else "are"])
	if not by_kind["sweetheart"].is_empty():
		lines.append("And %s... well. Don't go telling people." % _and(by_kind["sweetheart"]))
	if not by_kind["rival"].is_empty():
		lines.append("%s? We don't speak, and that suits me." % _and(by_kind["rival"]))
	var mourning := WorldState.get_record("mourning/" + s.data.id)
	if not mourning.is_empty():
		lines.append("We buried %s not long ago. Forgive me if I'm not myself." % String(mourning.get("for", "a friend")))
	if lines.is_empty():
		lines.append("I keep to myself, mostly.")
	return {"text": " ".join(lines), "journal": false, "learn": PackedStringArray()}


static func _and(names: Array) -> String:
	if names.size() == 1:
		return String(names[0])
	return ", ".join(PackedStringArray(names.slice(0, names.size() - 1))) + " and " + String(names[names.size() - 1])


# ---------------------------------------------------------------- greetings

func _greetings(p: Node3D) -> void:
	for e in ActorRegistry.near(p.global_position, 40.0):
		if e.is_dead() or not e.has_meta("npc_id") or e.state == Enemy.State.CHASE or e.state == Enemy.State.FLEE:
			continue
		var a_id := String(e.get_meta("npc_id"))
		for o in ActorRegistry.near(e.global_position, GREET_RANGE):
			if o == e or o.is_dead() or not o.has_meta("npc_id"):
				continue
			var b_id := String(o.get_meta("npc_id"))
			var key := a_id + "|" + b_id if a_id < b_id else b_id + "|" + a_id
			if _clock - float(_greeted.get(key, -999.0)) < GREET_QUIET:
				continue
			var line := _greeting(e, o, a_id, b_id)
			if line == "":
				continue
			_greeted[key] = _clock
			_say(e, line)
			var to := o.global_position - e.global_position
			e.rotation.y = atan2(-to.x, -to.z)
			return  # one at a time


func _greeting(e: Enemy, o: Enemy, a_id: String, b_id: String) -> String:
	var kind := relation(a_id, b_id)
	var night := world.clock != null and world.clock.is_night()
	var hour := world.clock.hour if world.clock != null else 12.0
	var when := "Morning" if hour < 12.0 else ("Afternoon" if hour < 18.0 else "Evening")
	var them := _first(b_id)
	var k := absi((a_id + b_id + str(int(_clock / 60.0))).hash())
	if WorldState.has_record("mourning/" + a_id) and kind != "rival":
		return ["...%s." % them, "Thank you for coming by, %s." % them][k % 2]
	match kind:
		"friend":
			return ["%s, %s!" % [when, them], "%s! Good to see you." % them, "There's %s. How's the family?" % them][k % 3]
		"rival":
			return ["Hmph.", "%s." % them, "Watch where you're walking."][k % 3]
		"sweetheart":
			return ["There you are.", "%s... later?" % them, "I was hoping I'd see you."][k % 3]
		"family":
			return ["Home for supper, mind." if not night else "Don't stay out late.", "Bring some water up, would you?"][k % 2]
	var ra: NpcData.Role = (world.life.get_resident(a_id).data.role if world.life.get_resident(a_id) != null else NpcData.Role.COMMONER)
	var rb: NpcData.Role = (world.life.get_resident(b_id).data.role if world.life.get_resident(b_id) != null else NpcData.Role.COMMONER)
	if ra == NpcData.Role.GUARD and rb == NpcData.Role.GUARD:
		return ["Your watch. Quiet so far.", "Anything I should know?", "All yours. I'm for my bed."][k % 3]
	return ""


func _say(e: Enemy, line: String) -> void:
	var talk := e.get_node_or_null("NpcTalk") as NpcTalk
	if talk != null:
		talk.say(line)
		Barks.voice(get_tree(), e.display_name, line)


# ---------------------------------------------------------------- news in passing

## Something going on that a townsperson might mention ("" = nothing much)
func news_for(s: DialogueEngine.Speaker) -> String:
	if s == null:
		return ""
	var k := absi(("%s|news|%d" % [s.id, Time.get_ticks_msec() / 90000]).hash())
	var lines := PackedStringArray()
	var dragons := int(WorldState.get_record("dragons_slain").get("n", 0))
	if dragons > 0:
		lines.append("They say a dragon fell. I'll believe it when I see the bones.")
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	if town != "" and s.town != null and CrimeManager.bounties().has(s.town.id):
		lines.append("The guards are looking for someone. Big reward, too.")
	for r: Dictionary in Rumors.all().slice(-6):
		var text := String(r.get("text", ""))
		if text != "":
			lines.append("Have you heard? " + text.get_slice(".", 0) + ".")
	if s.data != null and WorldState.has_record("mourning/" + s.data.id):
		lines.append("I can't stop thinking about %s." % String(WorldState.get_record("mourning/" + s.data.id).get("for", "them")))
	for id in _dead_seen:
		var r := world.life.get_resident(String(id))
		if r != null and s.town != null and r.town.id == s.town.id and s.data != null and String(id) != s.data.id:
			lines.append("Poor %s. The whole town's talking about it." % r.data.display_name.get_slice(" ", 0))
			break
	if lines.is_empty():
		return ""
	return lines[k % lines.size()]


# ---------------------------------------------------------------- crowds

# Something hostile walking into a town: everyone out on the streets runs for their own door
func _crowds() -> void:
	for t in world.towns:
		if t.town == null or not (t.poi is TownData):
			continue
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p == null or Vector2(t.position.x - p.global_position.x, t.position.z - p.global_position.z).length() > 250.0:
			continue
		var threat := false
		for e in ActorRegistry.near(t.position, CROWD_RADIUS):
			if e.is_dead() or ActorLOD.is_frozen(e) or e.disposition != Enemy.Disposition.HOSTILE or e.has_meta("npc_id"):
				continue
			if CreatureFactions.relation(CreatureFactions.of(e), "town") == CreatureFactions.Rel.HOSTILE or e.enemy_id == "dragon":
				threat = true
				break
		if not threat:
			continue
		if _clock - float(_horned.get(t.id, -999.0)) > 90.0:
			_horned[t.id] = _clock
			SoundFX.at(get_tree(), t.position + Vector3.UP * 12.0, "horn", 450.0)  # the town sounds the alarm
		for r: TownLife.Resident in world.life.get_town_residents(t.id):
			if r.dead or r.node_inside or not is_instance_valid(r.node) or r.node.is_dead() or r.data.role == NpcData.Role.GUARD:
				continue
			if r.node.has_meta("panic") or r.data.home_id == "":
				continue
			var home := world.get_building(r.data.home_id)
			if home == null:
				continue
			r.node.set_meta("panic", true)
			_say(r.node, ["Get inside!", "Run!", "Gods, it's here!", "Bar the doors!"][absi(r.data.id.hash()) % 4])
			r.goal = {"inside": home.id, "pose": &"sit"}
			r.walking = true
			var layout := r.town.town
			var pts := layout.find_route(layout.to_local(r.node.global_position), home.get_door_local())
			r.node.follow_route(world.life._to_world(layout, pts), false, 1.0)  # running, not walking


# ---------------------------------------------------------------- grief and revenge

func _grief() -> void:
	var day := world.clock.day if world.clock != null else 1
	for r: TownLife.Resident in world.life.residents:
		if not r.dead or _dead_seen.has(r.data.id):
			continue
		_dead_seen[r.data.id] = true
		if WorldState.has_record("grieved/" + r.data.id):
			continue  # an old death (loaded game)
		WorldState.set_record("grieved/" + r.data.id, {"day": day})
		var killed := bool(WorldState.get_record("npc_killer/" + r.data.id).get("player", false))
		TownBoards.add_grave(world, r, "slain" if killed or WorldState.has_record("kill/" + r.data.id) else "taken before their time", day)
		var known := known_by(r.data.id)
		var family := ""
		_pass_on_jobs(r, known)  # 1.24: a job they gave you goes to their family
		for other in known:
			var kind := String(known[other])
			if kind in ["family", "sweetheart", "friend"]:
				WorldState.set_record("mourning/" + String(other), {"day": day, "for": r.data.display_name.get_slice(" ", 0)})
			if kind == "family" and family == "":
				family = _name(String(other))
		# killed by you: the family may want you dead
		if family != "" and bool(WorldState.get_record("npc_killer/" + r.data.id).get("player", false)) and randf() < REVENGE_CHANCE:
			WorldState.set_record("revenge/" + r.data.id, {"due": day + randi_range(1, 3), "by": family, "for": r.data.display_name})
	# mourning ends after a week
	for key in WorldState.records.keys():
		var k := String(key)
		if k.begins_with("mourning/") and day - int(WorldState.get_record(k).get("day", day)) > MOURN_DAYS:
			WorldState.erase_record(k)
	# mourners wear dark clothes
	for e in ActorRegistry.near((get_tree().get_first_node_in_group("player") as Node3D).global_position, 60.0):
		if e.has_meta("npc_id") and not e.has_meta("mourning_dress") and WorldState.has_record("mourning/" + String(e.get_meta("npc_id"))) and e.body != null:
			e.set_meta("mourning_dress", true)
			ModelLibrary.tint(e.body, Color(0.35, 0.33, 0.36))


## Who is mourning (TownLife sends them to the temple more often)
static func is_mourning(npc_id: String) -> bool:
	return WorldState.has_record("mourning/" + npc_id)


# Thugs paid by a grieving family find you on the road, a day or three later
func _revenge(p: Node3D) -> void:
	if world.dungeons != null and world.dungeons.is_inside():
		return
	var day := world.clock.day if world.clock != null else 1
	for key in WorldState.records.keys():
		var k := String(key)
		if not k.begins_with("revenge/"):
			continue
		var rec := WorldState.get_record(k)
		if bool(rec.get("done", false)) or day < int(rec.get("due", day)):
			continue
		for t in world.towns:
			if Vector2(t.position.x - p.global_position.x, t.position.z - p.global_position.z).length() < 200.0:
				return  # not in town: out on the road
		var done := rec.duplicate()
		done["done"] = true
		WorldState.set_record(k, done)
		_send_thugs(p, String(rec.get("by", "someone")), String(rec.get("for", "them")))
		return


func _send_thugs(p: Node3D, by: String, victim: String) -> void:
	var data := load("res://data/enemies/bandit_thug.tres") as EnemyData
	if data == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var skills := p.get_node_or_null("Skills") as Skills
	var level := skills.get_player_level() if skills != null else 5
	var back := p.global_transform.basis.z
	back.y = 0.0
	var at := p.global_position + back.normalized() * 28.0
	var note := QuestItems.get_item("revenge_note_" + victim.to_lower().replace(" ", "_"), "A Crumpled Note")
	note.description = "\"The one who killed %s travels the roads. Make it slow. Half now, half when it's done.\" - %s" % [victim, by]
	for i in 2:
		var pos := at + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		pos.y = world.get_height_at(pos.x, pos.z) + 0.6
		var e := Population.spawn_enemy(data, level, world, pos, rng, {"persist_mode": Enemy.PersistMode.NEVER})
		e.display_name = "Hired Thug"
		e.faction = "bandits"
		e.set_meta("hired_by", by)
		e.set_meta("lod_keep", true)
		if i == 0 and e.inventory != null:
			e.inventory.add_item(note, 1)
		e.aggro(p)
	Locks.toast(get_tree(), "Footsteps behind you. Someone has paid for your death.", true)


# ---------------------------------------------------------------- brawls at the inn

func _tick_brawl(p: Node3D) -> void:
	if not _brawl.is_empty():
		var a: Enemy = _brawl["a"]
		var b: Enemy = _brawl["b"]
		var over := not is_instance_valid(a) or not is_instance_valid(b) or a.is_dead() or b.is_dead() or _clock > float(_brawl["until"])
		if not over:
			over = a.stats.health < float(_brawl["ha"]) * 0.55 or b.stats.health < float(_brawl["hb"]) * 0.55
		if over:
			_end_brawl()
		return
	_brawl_t -= TICK
	if _brawl_t > 0.0:
		return
	_brawl_t = BRAWL_EVERY
	var dm := world.dungeons
	if dm == null or not dm.is_in_building():
		return
	var b0 := world.get_building(dm.current_entrance_id)
	var hour := world.clock.hour if world.clock != null else 12.0
	if b0 == null or b0.kind != BuildingPlot.Kind.INN or not (hour >= 19.0 or hour < 2.0) or randf() > BRAWL_CHANCE:
		return
	var here: Array = []
	for r: TownLife.Resident in world.life.residents:
		if r.node_inside and is_instance_valid(r.node) and not r.node.is_dead() and r.inside == b0.id \
				and r.data.role != NpcData.Role.INNKEEPER and r.data.role != NpcData.Role.GUARD:
			here.append(r)
	if here.size() < 2:
		return
	# rivals first, else any two who've had too much
	var pick: Array = []
	for x: TownLife.Resident in here:
		for y: TownLife.Resident in here:
			if x != y and relation(x.data.id, y.data.id) == "rival":
				pick = [x, y]
	if pick.is_empty():
		here.shuffle()
		pick = [here[0], here[1]]
	start_brawl(pick[0], pick[1])


## Two people come to blows (fists only, nobody dies of it)
func start_brawl(x: TownLife.Resident, y: TownLife.Resident) -> void:
	var a := x.node
	var b := y.node
	for e in [a, b]:
		e.stats.add_modifiers("brawl", {"max_health": 400.0})
		e.stats.modify_vital("health", 400.0)
		e.set_meta("brawl", true)
	_brawl = {"a": a, "b": b, "ida": x.data.id, "idb": y.data.id, "until": _clock + 25.0, "ha": a.stats.health, "hb": b.stats.health}
	_say(a, ["You looking at me?", "Say that again. Go on.", "That's my seat."][absi(x.data.id.hash()) % 3])
	a.fight(b)
	b.fight(a)


func _end_brawl() -> void:
	var a: Enemy = _brawl.get("a")
	var b: Enemy = _brawl.get("b")
	for e in [a, b]:
		if is_instance_valid(e) and not e.is_dead():
			e.stop_fighting()
			e.stats.remove_modifiers("brawl")
			e.stats.modify_vital("health", maxf(1.0 - e.stats.health, 0.0))  # nobody dies of a brawl
			e.remove_meta("brawl")
	if is_instance_valid(a) and not a.is_dead():
		_say(a, ["All right! All right, you win.", "Enough... enough.", "Next round's yours, then."][randi() % 3])
	set_relation(String(_brawl["ida"]), String(_brawl["idb"]), "rival")
	_brawl = {}


func is_brawling(e: Node) -> bool:
	return e != null and e.has_meta("brawl")


# ---------------------------------------------------------------- errands

## Someone leaving a shop carries what they bought home
static func carry_sack(e: Enemy) -> void:
	if e == null or e.body == null or e.has_meta("sack"):
		return
	var holder: Node3D = e.body.off_grip if e.body.off_grip != null else e.body
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.34
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.3)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, -0.18, 0)
	mi.name = "Sack"
	holder.add_child(mi)
	e.set_meta("sack", true)


## Has family in town (TownLife: home for supper in the evening)
func has_family(npc_id: String) -> bool:
	for k in known_by(npc_id).values():
		if k == "family":
			return true
	return false


# ---------------------------------------------------------------- the day's round (1.24.4)

## Once a day: how each town is doing (TownNeeds), and sweethearts who have waited long enough marry
func _daily() -> void:
	var day := world.clock.day if world.clock != null else 1
	if day == _day_done:
		return
	_day_done = day
	for t in world.towns:
		if t.town != null and t.poi is TownData:
			var needs := TownNeeds.get_needs(t.id)
			if needs.is_empty() or int(needs.get("day", -1)) != day:
				TownNeeds.update(world, t, day)
	_weddings(day)


func _weddings(day: int) -> void:
	if day < 15:
		return  # give it a couple of weeks
	for t in world.towns:
		if t.town == null or not (t.poi is TownData):
			continue
		var web := _web(t.id)
		for a in web:
			for b in web[a]:
				if String(web[a][b]) != "sweetheart" or String(a) > String(b):
					continue
				var key := "married/%s|%s" % [a, b]
				if WorldState.has_record(key):
					continue
				if absi(("%s|%d" % [key, day]).hash()) % 100 >= 4:
					continue  # about one in twenty-five days
				var ra := world.life.get_resident(String(a))
				var rb := world.life.get_resident(String(b))
				if ra == null or rb == null or ra.dead or rb.dead:
					continue
				WorldState.set_record(key, {"day": day})
				set_relation(String(a), String(b), "family")
				Rumors.add("wedding", "%s and %s were married at the temple in %s. The whole town came." % [ra.data.display_name, rb.data.display_name, t.town.display_name], t.position, day)


# ---------------------------------------------------------------- gossip about your crimes

## Witnesses of a crime tell their friends and family within the hour (CrimeManager calls this)
func spread_gossip(witness_ids: Array, kind: String, town_name: String) -> void:
	if witness_ids.is_empty() or world.clock == null:
		return
	var list: Array = WorldState.get_record("gossip").get("list", []).duplicate()
	list.append({"ids": witness_ids, "kind": kind, "town": town_name, "at": float(world.clock.day) * 24.0 + world.clock.hour})
	WorldState.set_record("gossip", {"list": list})


func _gossip() -> void:
	var rec := WorldState.get_record("gossip")
	if rec.is_empty() or world.clock == null:
		return
	var now := float(world.clock.day) * 24.0 + world.clock.hour
	var left: Array = []
	for g: Dictionary in rec.get("list", []):
		if now - float(g["at"]) < 1.0:
			left.append(g)
			continue
		for id in g["ids"]:
			var known := known_by(String(id))
			for other in known:
				if not (String(known[other]) in ["friend", "family", "sweetheart"]):
					continue
				var r := world.life.get_resident(String(other))
				if r == null or r.dead:
					continue
				NpcMemory.remember(r.data.display_name, String(g["town"]), String(g["kind"]), "heard it from %s" % _first(String(id)), world.clock.day)
				DialogueState.change_disposition(r.data.id, r.data.base_disposition, -5)
	if left.size() != (rec.get("list", []) as Array).size():
		WorldState.set_record("gossip", {"list": left})


# ---------------------------------------------------------------- boards, graves, bodies (1.24.5)

func _on_poi_spawned(placed: PlacedPOI, node: Node3D) -> void:
	if not (placed.poi is TownData) or placed.town == null or node == null:
		return
	_boards[placed.id] = true  # (the town's own notice board shows its posters: NoticeBoard)
	TownBoards.build_graves(world, placed, node)


# A body lying in town is found by the first passer-by: a scream, the news, people keep away
func _bodies_found() -> void:
	for r: TownLife.Resident in world.life.residents:
		if not r.dead or WorldState.has_record("body_found/" + r.data.id):
			continue
		var body := r.node
		if body == null or not is_instance_valid(body) or not body.is_inside_tree() or r.node_inside:
			continue
		# 1.24: a body in the water is never found; at night only someone right beside it notices
		if world.map != null and body.global_position.y < world.map.get_water_level(body.global_position.x, body.global_position.z) - 0.4:
			continue
		var notice := 3.0 if world.clock != null and world.clock.is_night() else 7.0
		for o in ActorRegistry.near(body.global_position, notice):
			if o == body or o.is_dead() or not o.has_meta("npc_id") or Takedowns.is_out(o):
				continue
			WorldState.set_record("body_found/" + r.data.id, {"by": o.display_name})
			_say(o, ["Gods! Someone help!", "Guards! Guards, there's a body!", "No... no, no."][absi(r.data.id.hash()) % 3])
			SoundFX.at(get_tree(), o.global_position + Vector3.UP * 1.5, "scream", 90.0)
			Rumors.add("body", "%s was found dead in %s. Nobody knows who did it." % [r.data.display_name, r.town.town.display_name], body.global_position, Rumors._day())
			for n in ActorRegistry.near(body.global_position, 15.0):
				if n.has_meta("npc_id") and n.disposition == Enemy.Disposition.FRIENDLY and not n.is_dead():
					n.flee_from(body, 6.0)
			break


# Towns that loaded before this node existed get their boards and graves too
func _catch_up() -> void:
	for t in world.towns:
		var node := world.get_poi_node(t.id)
		if node != null and not _boards.has(t.id):
			_on_poi_spawned(t, node)


# ---------------------------------------------------------------- quests that outlive their giver (1.24.9)

## Someone who gave you a job has died: a relative (else a friend) will see it through and pay you
func _pass_on_jobs(r: TownLife.Resident, known: Dictionary) -> void:
	var heir := ""
	for kind in ["family", "sweetheart", "friend"]:
		for other in known:
			var o := world.life.get_resident(String(other))
			if String(known[other]) == kind and o != null and not o.dead:
				heir = String(other)
				break
		if heir != "":
			break
	for q: Dictionary in QuestManager.all_quests():
		if String(q.get("status", "")) != "active" or String(q.get("giver", "")) != r.data.id:
			continue
		var q2 := q.duplicate(true)
		var text := ""
		if heir != "":
			var h := world.life.get_resident(heir)
			q2["giver"] = heir
			q2["objective"] = String(q2.get("objective", "")).replace(r.data.display_name, h.data.display_name)
			text = "%s is dead. %s says they will see the job through, and pay what is owed." % [r.data.display_name, h.data.display_name]
		else:
			text = "%s is dead, and nobody else knows of the job. Whatever it was worth, it is worth nothing now." % r.data.display_name
			q2["status"] = "failed"
		QuestManager._update_quest(q2)
		DialogueState.add_journal({"text": text, "speaker": "", "topic": "", "day": world.clock.day if world.clock != null else 1,
			"time": world.clock.get_time_text() if world.clock != null else "", "quest_id": String(q["id"]), "quest_name": String(q.get("name", ""))})
