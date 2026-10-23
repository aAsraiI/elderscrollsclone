extends SceneTree
## Headless tests for stage 6b: more guards, the five guilds, ranks and perks, and guild jobs. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage6b.gd

const R := "res://data/"

var passes := 0
var fails := 0


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func secs(s: float) -> void:
	await frames(int(round(s * 60.0)))


func _run() -> void:
	await process_frame
	t_factions()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func make_player(parent: Node) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.collision_layer = 1
	p.collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	p.add_child(head)
	head.add_child(Camera3D.new())
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	stats.base_stats["max_health"] = 50000.0
	p.add_child(stats)
	var inv := Inventory.new()
	inv.name = "Inventory"
	inv.stats = stats
	p.add_child(inv)
	var eq := Equipment.new()
	eq.name = "Equipment"
	eq.inventory = inv
	eq.stats = stats
	p.add_child(eq)
	var sk := Skills.new()
	sk.name = "Skills"
	p.add_child(sk)
	var mc := MeleeCombat.new()
	mc.name = "MeleeCombat"
	p.add_child(mc)
	var st := Stealth.new()
	st.name = "Stealth"
	p.add_child(st)
	for ui in [ContainerUI.new(), DialogueUI.new(), BarterUI.new(), JournalUI.new()]:
		ui.name = ui.get_script().get_global_name()
		p.add_child(ui)
	p.add_to_group("player")
	parent.add_child(p)
	return p


# ---------------------------------------------------------------- guilds on paper

func t_factions() -> void:
	print("-- the guilds")
	WorldState.clear()
	var ok := true
	for id in Factions.IDS:
		var d := Factions.get_data(id)
		ok = ok and d != null and d.ranks.size() == 5 and d.quests_for_rank.size() == 5 and not d.quest_types.is_empty()
	check("five guilds, five ranks each", ok)
	check("the assassins are the Assassins Cult", Factions.display_name("assassins") == "Assassins Cult" and Factions.get_data("assassins").quest_types.has("assassinate"))

	var holder := Node3D.new()
	root.add_child(holder)
	var p := make_player(holder)
	var skills := p.get_node("Skills") as Skills
	var stats := p.get_node("Stats") as Stats
	check("anyone can join the Fighters Guild", Factions.join_problem("fighters", p) == "" and Factions.join("fighters", p) and Factions.rank("fighters") == 1)
	check("joining twice doesn't work", not Factions.join("fighters", p))
	CrimeManager.set_bounty_raw("some_town", 50)
	check("the Knightly Order won't take someone with a bounty", Factions.join_problem("knights", p) != "")
	CrimeManager.set_bounty_raw("some_town", 0)
	check("but will once it's cleared", Factions.join_problem("knights", p) == "")
	check("the Thieves Guild wants proof you can steal", Factions.join_problem("thieves", p) != "")
	Factions.note_crime("thefts")
	check("a theft is proof enough", Factions.join_problem("thieves", p) == "")
	check("the Assassins Cult wants blood", Factions.join_problem("assassins", p) != "")
	Factions.note_crime("murders")
	check("a murder opens that door", Factions.join_problem("assassins", p) == "")
	check("and closes the Knightly Order's", Factions.join_problem("knights", p) != "")

	# promotion and perks
	var n := Factions.next_rank("fighters", p)
	check("promotion needs jobs and skill", not n["ok"] and String(n["why"]).contains("2 more jobs") and String(n["why"]).contains("10"), String(n["why"]))
	Factions.add_quest_done("fighters")
	Factions.add_quest_done("fighters")
	check("jobs alone aren't enough", Factions.promote("fighters", p) == "")
	skills.levels[&"one_handed"] = 12
	check("with the skill too, a promotion", Factions.promote("fighters", p) == "Swordsman" and Factions.rank("fighters") == 2)
	check("rank perk: +5 health per rank", is_equal_approx(stats.get_stat("max_health"), 50010.0), str(stats.get_stat("max_health")))
	check("members get better prices from smiths", is_equal_approx(Factions.discount_for(load(R + "merchants/smith.tres")), 0.06))
	check("but not from an alchemist", Factions.discount_for(load(R + "merchants/alchemy.tres")) == 0.0)
	Factions.join("mages", p)
	check("the Mages Guild goes by player level until there are spells", String(Factions.next_rank("mages", p)["skill"]) == "player level")
	var item := QuestItems.get_item("q7", "Lost Journal")
	check("quest items save and load as themselves", SaveUtil.path_to_item(SaveUtil.item_to_path(item)) == item)
	check("merchants won't buy quest items", not (load(R + "merchants/general.tres") as MerchantData).will_buy(item))
	holder.queue_free()
	WorldState.clear()


# ---------------------------------------------------------------- in a running world

func t_world() -> void:
	print("-- guards, leaders and jobs in a running world")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var p := make_player(holder)
	var skills := p.get_node("Skills") as Skills
	var st := p.get_node("Stealth") as Stealth
	var ui := p.get_node("DialogueUI") as DialogueUI
	var s := (load(R + "world/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = s
	holder.add_child(wm)
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)
	var qm := wm.quests
	check("the world has a QuestManager", qm != null)

	# ---- guards
	var town := wm.get_nearest_town(p.global_position)
	p.global_position = town.position + Vector3(0, 1, 0)  # stand in town so it is loaded
	wm.ensure_area_loaded(town.position, 2)
	await secs(1.5)
	var guards := 0
	var posted := 0
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.GUARD:
			guards += 1
			if r.data.post >= 0:
				posted += 1
				var gate := town.town.get_gates_world()[r.data.post]
				var body_ok := r.node != null and is_instance_valid(r.node) and Vector2(r.node.global_position.x - gate.x, r.node.global_position.z - gate.z).length() < 15.0
				check("a gate guard stands by gate %d" % r.data.post, body_ok, "%s vs gate %s" % [str(r.node.global_position) if r.node != null and is_instance_valid(r.node) else "no body", gate])
	check("more guards: %d in a %s" % [guards, (town.poi as TownData).display_name.to_lower()], guards == Residents.GUARDS[int((town.poi as TownData).kind)] and guards >= 3)
	check("two of them stand watch at the gates", posted == 2)

	# ---- who leads what
	var city: PlacedPOI = null
	for t in wm.towns:
		if (t.poi as TownData).kind == TownData.Kind.CITY and city == null:
			city = t
	var every_city_fence := true
	for t in wm.towns:
		if (t.poi as TownData).kind == TownData.Kind.CITY:
			var has := false
			for b in t.town.buildings:
				has = has or (b.kind == BuildingPlot.Kind.SHOP and b.trade == "pawnbroker")
			every_city_fence = every_city_fence and has
	check("every city has a pawnbroker (the Thieves Guild's contact)", every_city_fence)
	var leaders := {}
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		var res_sp := DialogueEngine.Speaker.new()
		res_sp.data = r.data
		res_sp.id = r.data.id
		res_sp.role = r.data.role
		res_sp.town = r.town
		res_sp.home = wm.get_building(r.data.home_id)
		var lead := Factions.leader_of(res_sp, wm)
		if lead != "":
			leaders[lead] = r
	check("a city has leaders for the Fighters, Mages, Knights and Thieves", leaders.has("fighters") and leaders.has("mages") and leaders.has("knights") and leaders.has("thieves"), str(leaders.keys()))

	# ---- join the Fighters Guild through dialogue and take a job
	p.global_position = city.position + Vector3(0, 1, 0)
	wm.ensure_area_loaded(city.position, 2)
	await secs(1.0)
	var fighter: TownLife.Resident = leaders["fighters"]
	var hall := wm.get_building(fighter.data.work_id)
	await wm.dungeons.enter(hall.id, hall.get_door_position(), 0.0)
	await frames(10)
	check("the Fighters Guild's leader is in the hall", fighter.node != null and is_instance_valid(fighter.node) and ui.open_with(fighter.node))
	check("they talk about membership", DialogueEngine.topics_for(ui.speaker, wm).has("membership"))
	var r1 := ui.ask("membership")
	check("asking about membership joins you", Factions.is_member("fighters") and String(r1["text"]).contains("Welcome"), String(r1["text"]))
	check("advancement is now a topic", DialogueEngine.topics_for(ui.speaker, wm).has("advancement"))
	var r2 := ui.ask("duties")
	var job := QuestManager.active_for("fighters")
	check("asking about duties gives a job", not job.is_empty() and ["kill", "retrieve"].has(job["type"]), String(r2["text"]))
	check("the job is written in the journal under its name", not JournalUI.filter(DialogueState.journal(), "", "quest", job["id"]).is_empty())
	check("its target shows on the map", QuestManager.active_targets().size() == 1)
	var r3 := ui.ask("duties")
	check("asking again reminds you of it", String(r3["text"]).begins_with("You already have a job"))
	ui.close()
	await wm.dungeons.exit()
	await frames(5)

	# the same game makes the same jobs
	var saved := WorldState.to_dict()
	var _sp_f := DialogueEngine.speaker_for(fighter.node, wm) if fighter.node != null and is_instance_valid(fighter.node) else null
	WorldState.from_dict(saved)
	var list_before: Array = QuestManager.all_quests().duplicate(true)
	WorldState.set_record(QuestManager.STATE, {"list": [], "counter": 0})
	var sp := DialogueEngine.Speaker.new()
	sp.data = fighter.data
	sp.id = fighter.data.id
	sp.name = fighter.data.display_name
	sp.role = fighter.data.role
	sp.town = fighter.town
	sp.home = hall
	var again := qm.offer("fighters", sp)
	check("the same game always offers the same job (save-safe)", again.get("target") == list_before[0]["target"] and again.get("type") == list_before[0]["type"])
	WorldState.from_dict(saved)

	# ---- each kind of job
	await _kill_job(wm, qm, p, sp)
	_retrieve_job(wm, qm, p, sp)
	await _steal_job(wm, qm, p, leaders["thieves"], hall)
	_deliver_and_persuade(wm, qm, p, sp)
	await _assassins(wm, qm, p, ui, st)

	# ---- promotion through dialogue
	skills.levels[&"one_handed"] = 15
	var lead_sp := sp
	var promo := qm.respond(lead_sp, "advancement")
	check("after two jobs, a promotion", Factions.rank("fighters") == 2 and String(promo["text"]).contains("Swordsman"), String(promo["text"]))
	holder.queue_free()
	await frames(3)


func _kill_job(wm: WorldManager, qm: QuestManager, p: Node3D, giver: DialogueEngine.Speaker) -> void:
	_clear_active("fighters")
	var q := qm.offer("fighters", giver, "kill")
	check("a kill job names a bandit chief at a camp", not q.is_empty() and String(q["chief"]).contains(" the "))
	if q.is_empty():
		return
	var camp := wm.get_poi(String(q["target"]))
	p.global_position = camp.position + Vector3(0, 30, 25)
	wm.ensure_area_loaded(camp.position, 2)
	await secs(1.5)
	var chief: Enemy = null
	for e in wm.get_garrison(camp.id):
		if is_instance_valid(e) and e.display_name == String(q["chief"]):
			chief = e
	check("the chief is at the camp", chief != null)
	check("not done yet", not qm.is_ready(q))
	if chief != null:
		var kill := DamageInfo.new(999999.0, p, &"melee")
		kill.direction = Vector3(0, 0, 1)
		chief.combat.take_damage(kill)
		await frames(3)
	check("killing the chief finishes the task", qm.is_ready(q))
	var gold := Currency.get_gold(p.get_node("Inventory") as Inventory)
	var res := qm.respond(giver, "duties")
	check("reporting back pays", Currency.get_gold(p.get_node("Inventory") as Inventory) > gold and String(res["text"]).begins_with("Well done"))
	check("and counts toward promotion", Factions.quests_done("fighters") == 1 and QuestManager.get_quest(String(q["id"]))["status"] == "done")


func _retrieve_job(wm: WorldManager, qm: QuestManager, p: Node3D, giver: DialogueEngine.Speaker) -> void:
	var q := qm.offer("fighters", giver, "retrieve")
	check("a retrieve job points at a dungeon's boss chest", not q.is_empty() and String(q["container"]).ends_with("/chest_boss"))
	if q.is_empty():
		return
	# the chest is made when the dungeon is built: its item goes in once
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var cc := ContainerComponent.new()
	cc.save_id = String(q["container"])
	body.add_child(cc)
	wm.add_child(body)
	var item := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
	check("the item is in that chest", cc.inventory.has_item(item))
	body.queue_free()
	var body2 := StaticBody3D.new()
	var cc2 := ContainerComponent.new()
	cc2.save_id = "something/else"
	body2.add_child(cc2)
	wm.add_child(body2)
	check("and in no other", not cc2.inventory.has_item(item))
	body2.queue_free()
	var inv := p.get_node("Inventory") as Inventory
	inv.add_item(item)
	check("carrying it, the job is done", qm.is_ready(q))
	qm.respond(giver, "duties")
	check("handing it in takes the item", not inv.has_item(item) and Factions.quests_done("fighters") == 2)


func _steal_job(wm: WorldManager, qm: QuestManager, p: Node3D, contact: TownLife.Resident, _hall: BuildingPlot) -> void:
	var sp := DialogueEngine.Speaker.new()
	sp.data = contact.data
	sp.id = contact.data.id
	sp.name = contact.data.display_name
	sp.role = contact.data.role
	sp.town = contact.town
	sp.home = wm.get_building(contact.data.home_id)
	var no := qm.respond(sp, "duties")
	check("the Thieves Guild has no work for outsiders", String(no["text"]).contains("members"))
	Factions.note_crime("thefts")  # (the steal below comes after joining)
	var join := qm.respond(sp, "membership")
	check("with a theft behind you, the pawnbroker lets you in", Factions.is_member("thieves"), String(join["text"]))
	var q := qm.offer("thieves", sp)
	check("the Thieves Guild hands out steal jobs", not q.is_empty() and q["type"] == "steal" and String(q["container"]).begins_with("building/"))
	if q.is_empty():
		return
	var house := wm.get_building(String(q["target"]))
	check("from a private house", house != null and not house.is_public())
	Locks.set_locked(house.id, false)
	wm.ensure_area_loaded(house.world_pos, 2)
	await wm.dungeons.enter(house.id, house.get_door_position(), 0.0)
	await frames(10)
	var item := QuestItems.get_item(String(q["id"]), String(q["item_name"]))
	var chest: ContainerComponent = null
	for c in wm.dungeons.get_interior_root().find_children("*", "ContainerComponent", true, false):
		if (c as ContainerComponent).save_id == q["container"]:
			chest = c
	check("the thing to steal is in the owner's chest", chest != null and chest.inventory.has_item(item))
	if chest != null:
		var cui := p.get_node("ContainerUI") as ContainerUI
		(p.get_node("Stealth") as Stealth).awareness.clear()
		cui.open(chest)
		cui._take_all()
		cui._close()
	await wm.dungeons.exit()
	await frames(5)
	check("with it in your pack the job is done", qm.is_ready(q))
	var res := qm.respond(sp, "duties")
	check("the contact pays for it", String(res["text"]).begins_with("Well done") and Factions.quests_done("thieves") == 1)
	# fence and bounty clearing
	var bui := p.get_node("BarterUI") as BarterUI
	var real_sp := DialogueEngine.Speaker.new()
	real_sp.data = contact.data
	real_sp.id = contact.data.id
	real_sp.name = contact.data.display_name
	real_sp.role = contact.data.role
	real_sp.town = contact.town
	real_sp.home = sp.home
	wm.clock.set_time(contact.data.work_start + 1.0)
	await secs(1.0)
	if bui.open_for(real_sp):
		check("for members the contact is a fence", bui.shop.data.buys_stolen and bui.deal.guild > 0.0)
		bui.close()
	else:
		check("the contact trades during the day", false)
	wm.clock.set_time(12.0)
	await secs(1.0)
	wm.crime.set_bounty(contact.town.id, 200)
	Currency.add_gold(p.get_node("Inventory") as Inventory, 1000)
	var gold := Currency.get_gold(p.get_node("Inventory") as Inventory)
	check("members can have their bounty cleared", qm.extra_topics(sp).has("clear bounty"))
	qm.respond(sp, "clear bounty")
	check("for a part of it", CrimeManager.bounties().is_empty() and gold - Currency.get_gold(p.get_node("Inventory") as Inventory) == 90, str(gold - Currency.get_gold(p.get_node("Inventory") as Inventory)))


func _deliver_and_persuade(wm: WorldManager, qm: QuestManager, p: Node3D, _giver: DialogueEngine.Speaker) -> void:
	var mages_leader: DialogueEngine.Speaker = null
	for t in wm.towns:
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			if r.data.role == NpcData.Role.GUILD_MEMBER and r.data.faction == "mages" and mages_leader == null:
				mages_leader = DialogueEngine.Speaker.new()
				mages_leader.data = r.data
				mages_leader.id = r.data.id
				mages_leader.name = r.data.display_name
				mages_leader.role = r.data.role
				mages_leader.town = r.town
				mages_leader.home = wm.get_building(r.data.home_id)
	Factions.join("mages", p)
	var inv := p.get_node("Inventory") as Inventory
	var q := qm.offer("mages", mages_leader, "deliver")
	check("a delivery job hands you a sealed package", not q.is_empty() and inv.has_item(QuestItems.get_item(String(q["id"]), String(q["item_name"]))))
	if not q.is_empty():
		var r := wm.life.get_resident(String(q["target"]))
		check("for someone in another town", r != null and r.town != mages_leader.town)
		var to := DialogueEngine.Speaker.new()
		to.data = r.data
		to.id = r.data.id
		to.name = r.data.display_name
		to.role = r.data.role
		to.town = r.town
		check("they have \"a delivery\" to talk about", qm.extra_topics(to).has("a delivery"))
		var gold := Currency.get_gold(inv)
		var res := qm.respond(to, "a delivery")
		check("handing it over finishes the job and pays", Currency.get_gold(inv) > gold and not inv.has_item(QuestItems.get_item(String(q["id"]), String(q["item_name"]))) and QuestManager.get_quest(String(q["id"]))["status"] == "done", String(res.get("text", "")))
	var pq := qm.offer("mages", mages_leader, "persuade")
	check("a persuade job names someone to win over", not pq.is_empty())
	if not pq.is_empty():
		var who := wm.life.get_resident(String(pq["target"]))
		check("not done while they don't like you enough", not qm.is_ready(pq))
		DialogueState.change_disposition(who.data.id, who.data.base_disposition, 100)
		check("done once they do", qm.is_ready(pq))
		qm.respond(mages_leader, "duties")
		check("and reported", QuestManager.get_quest(String(pq["id"]))["status"] == "done" and Factions.quests_done("mages") == 2)


func _assassins(wm: WorldManager, qm: QuestManager, p: Node3D, ui: DialogueUI, _st: Stealth) -> void:
	# a murder, then a night outside: the stranger comes
	WorldState.erase_record(Factions.HISTORY)
	Factions.note_crime("murders")
	var town := wm.get_nearest_town(p.global_position)
	p.global_position = town.position + Vector3(0, 1, 0)
	wm.ensure_area_loaded(town.position, 2)
	wm.clock.set_time(23.0)
	await secs(1.5)
	var stranger := qm._stranger
	check("after a murder, a hooded stranger comes one night", stranger != null and is_instance_valid(stranger) and stranger.display_name == "Hooded Stranger")
	var waited := 0
	while not ui.is_open() and waited < 30:
		await secs(1.0)
		waited += 1
	check("and walks up to talk to you", ui.is_open() and ui.speaker.name == "Hooded Stranger", "%d s" % waited)
	if not ui.is_open():
		return
	check("they invite you to the Assassins Cult", DialogueState.knows("membership") and DialogueEngine.topics_for(ui.speaker, wm).has("membership"))
	ui.ask("membership")
	check("you can join", Factions.is_member("assassins") and Factions.rank("assassins") == 1)
	var r := ui.ask("duties")
	var q := QuestManager.active_for("assassins")
	check("the Assassins Cult gives contracts", not q.is_empty() and q["type"] == "assassinate" and String(q["name"]).begins_with("Contract:"), String(r["text"]))
	ui.close()
	if q.is_empty():
		return
	var target := wm.life.get_resident(String(q["target"]))
	check("the target is a townsperson, not a guard", target != null and target.data.role != NpcData.Role.GUARD)
	check("not done while they live", not qm.is_ready(q))
	WorldState.set_record("kill/" + target.data.id, {"dead": true})
	var fake := Enemy.new()
	fake.set_meta("npc_id", target.data.id)
	qm.on_murder(fake, false)
	fake.free()
	check("done once they're dead", qm.is_ready(q))
	var contact := QuestManager._make_contact(wm, p.global_position + Vector3(2, 0.5, 0), "Hooded Figure")
	await frames(2)
	var csp := DialogueEngine.speaker_for(contact, wm)
	var inv := p.get_node("Inventory") as Inventory
	var gold := Currency.get_gold(inv)
	var res := qm.respond(csp, "duties")
	check("an unseen kill pays half again as much", Currency.get_gold(inv) - gold == roundi(int(q["reward"]) * 1.5) and String(res["text"]).contains("No one saw"), "%d vs %d" % [Currency.get_gold(inv) - gold, int(q["reward"])])
	contact.queue_free()
	if qm._stranger != null and is_instance_valid(qm._stranger):
		qm._stranger.queue_free()

	# a city inn at night has a hooded figure
	var inn: BuildingPlot = null
	for t in wm.towns:
		if (t.poi as TownData).kind == TownData.Kind.CITY:
			for b in t.town.buildings:
				if b.kind == BuildingPlot.Kind.INN and inn == null:
					inn = b
	wm.clock.set_time(22.0)
	await secs(1.0)
	Locks.set_locked(inn.id, false)
	wm.ensure_area_loaded(inn.world_pos, 2)
	await wm.dungeons.enter(inn.id, inn.get_door_position(), 0.0)
	await frames(10)
	var figure := false
	for e in wm.dungeons.get_interior_root().find_children("*", "Enemy", true, false):
		figure = figure or (e as Enemy).get_meta("leader_of", "") == "assassins"
	check("a city inn at night has a hooded figure in the corner", figure)
	await wm.dungeons.exit()
	await frames(5)
	wm.clock.set_time(12.0)
	await secs(1.0)


func _clear_active(faction: String) -> void:
	var list := QuestManager.all_quests().duplicate(true)
	for q: Dictionary in list:
		if q["faction"] == faction and q["status"] == "active":
			q["status"] = "abandoned"
	WorldState.set_record(QuestManager.STATE, {"list": list, "counter": int(WorldState.get_record(QuestManager.STATE).get("counter", 0))})
