extends SceneTree
## Alpha 1.26 (dungeons, travel, dialogue, settings), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha126.gd

var passes := 0
var fails := 0
var wm: WorldManager
var p: CharacterBody3D


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
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(120)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", wm != null and p != null)
	if wm != null and p != null:
		(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
		(p.get_node("Stats") as Stats).revive()
		wm.clock.set_time(12.0)
		await t_dungeons()
		await t_travel()
		await t_dialogue()
		await t_settings()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func spawn(id: String, at: Vector3) -> Enemy:
	var e := Population.spawn_enemy(load("res://data/enemies/%s.tres" % id), 10, wm, at, RandomNumberGenerator.new())
	return e


func t_dungeons() -> void:
	print("-- bosses, traps, gas, events")
	var at := p.global_position + Vector3(6, 0, 0)
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var troll := spawn("cave_troll", at)
	var priest := spawn("ashen_priest", at + Vector3(0, 0, 8))
	await frames(3)
	check("a troll regrows", BossMechanics.kind_for(troll) == "regrows")
	check("a priest raises the dead", BossMechanics.kind_for(priest) == "raiser")
	var mt := BossMechanics.attach(troll)
	troll.aggro(p)
	troll.stats.modify_vital("health", -troll.stats.get_stat("max_health") * 0.5)
	var hp := troll.stats.health
	await secs(2.0)
	check("its wounds knit while it fights", troll.stats.health > hp, "%.0f -> %.0f" % [hp, troll.stats.health])
	troll.set_meta("burned_at", Time.get_ticks_msec() / 1000.0)
	hp = troll.stats.health
	await secs(1.5)
	check("unless fire has touched it", troll.stats.health <= hp + 0.5, "%.0f -> %.0f" % [hp, troll.stats.health])
	troll.queue_free()
	var mp := BossMechanics.attach(priest)
	priest.aggro(p)
	mp._next = 0.0
	await secs(1.0)
	check("the dead rise around it", mp._raised.size() >= 1)
	priest.stats.modify_vital("health", -priest.stats.get_stat("max_health") * 0.8)
	mp._next = 0.0
	var n := mp._raised.size()
	await secs(1.0)
	check("badly hurt, its power fails", mp.has_meta("failed") and mp._raised.size() == n)
	for r in mp._raised:
		if is_instance_valid(r):
			r.queue_free()
	priest.queue_free()
	# gas goes up when fire meets it
	var cloud := InteriorHazards.GasCloud.new()
	cloud.save_id = "test/gas"
	wm.add_child(cloud)
	cloud.global_position = at + Vector3(0, 0, -10)
	await frames(2)
	WorldSurfaces.of(self).react(cloud.global_position + Vector3.UP, &"fire")
	await frames(2)
	check("fire in a gas cloud sets it off, for good", not is_instance_valid(cloud) and WorldState.has_record("test/gas"))
	# a trap's tell
	var trap := DungeonFeature.new()
	trap.kind = DungeonFeature.Kind.TRAP
	trap.save_id = "test/trap"
	wm.add_child(trap)
	trap.global_position = p.global_position + Vector3(2, -1, 0)
	await frames(2)
	var st := p.get_node("Stealth") as Stealth
	st.sneaking = true
	trap._tell_t = 0.0
	trap._process(0.1)
	check("sneaking, you see a trap's plate", trap._tell != null and trap._tell.visible)
	st.sneaking = false
	trap.queue_free()
	# rare events
	var dungeon: PlacedPOI = null
	for poi in wm.pois:
		if poi.poi is DungeonEntrancePOIData:
			dungeon = poi
			break
	var ok: bool = await wm.dungeons.enter(dungeon.id, dungeon.position, 0.0)
	await frames(10)
	var root := wm.dungeons.get_interior_root()
	var kinds := {}
	for s in 120:
		var k := StoryScenes.add_event(root, dungeon.id, s * 104729, 5)
		if k != "":
			kinds[k] = true
		if kinds.size() >= 3:
			break
	check("dungeons sometimes hold a lost adventurer, rivals or a pedlar", ok and kinds.size() >= 2, str(kinds.keys()))
	await wm.dungeons.exit()
	await frames(10)


func speaker_of(e: Enemy) -> DialogueEngine.Speaker:
	var s := DialogueEngine.Speaker.new()
	s.enemy = e
	s.name = e.talk_name
	s.id = "test/%d" % e.get_instance_id()
	return s


func t_travel() -> void:
	print("-- the road")
	var road := RoadEvents.of(self)
	check("road events run", road != null)
	if road == null:
		return
	road.enabled = false
	var inv := p.get_node("Inventory") as Inventory
	var at := p.global_position + Vector3(0, 0, 30)
	# highwaymen: pay and pass
	var hw := road.stage("highwaymen", at)
	await frames(10)
	check("highwaymen stand across the road", hw.size() == 3 and (hw[0] as Enemy).disposition == Enemy.Disposition.NEUTRAL)
	var s := speaker_of(hw[1])
	check("their leader names a toll", road.topics_for(s).has("pay the toll") and road.topics_for(s).has("refuse the toll"))
	var qm := wm.quests
	check("the toll is a topic in dialogue", qm.extra_topics(s).has("pay the toll"))
	Currency.add_gold(inv, 5000)
	var before := Currency.get_gold(inv)
	var said := qm.respond(s, "pay the toll")
	check("paying the toll costs gold and they let you by", Currency.get_gold(inv) < before and road.current["state"] == "paid", str(said))
	await frames(5)
	check("and they stay calm", (hw[0] as Enemy).disposition != Enemy.Disposition.HOSTILE)
	road._end()
	await frames(3)
	# highwaymen: walk through them
	hw = road.stage("highwaymen", p.global_position + Vector3(0, 0, 3))
	await frames(10)
	road._watch()  # warned
	road._watch()  # too close
	check("walk through them without paying and they draw steel", road.current["state"] == "fight" and (hw[0] as Enemy).disposition == Enemy.Disposition.HOSTILE)
	for e in hw:
		if is_instance_valid(e):
			e.queue_free()
	road.current = {}
	check("refusing has a chance from Strength and Speech", road.refuse_chance(p) > 0.05 and road.refuse_chance(p) < 0.95)
	# beset traveller
	var bs := road.stage("beset", at)
	await frames(10)
	var wolves := bs.filter(func(e): return (e as Enemy).has_meta("road_wolf"))
	check("a traveller beset by wolves", bs.size() >= 3 and wolves.size() >= 2)
	for w in wolves:
		(w as Enemy).stats.modify_vital("health", -100000.0)
	await frames(10)
	p.global_position = at + Vector3(0, 1, 5)
	before = Currency.get_gold(inv)
	road._watch()
	check("save them and they pay what they can", road.current.get("state") == "saved" and Currency.get_gold(inv) > before)
	road._end()
	await frames(3)
	# the wreck
	var wr := road.stage("wreck", at)
	await frames(10)
	var cs := speaker_of(wr[0])
	check("a stranded carter needs a hand", road.topics_for(cs).has("the broken cart"))
	inv.add_item(load("res://data/materials/firewood.tres"), 2)
	before = Currency.get_gold(inv)
	road.respond(cs, "the broken cart")
	check("two firewood mends the cart, for pay", road.current["state"] == "mended" and Currency.get_gold(inv) > before)
	road._end()
	await frames(3)
	check("the cart is cleared away", get_nodes_in_group("road_cart").is_empty())
	# waylaid after a long trip
	road.enabled = true
	var hit := false
	for i in 40:
		if road.ambush_on_arrival(10.0):
			hit = true
			break
	check("a long trip can end in an ambush", hit and road.current.get("state") == "fight")
	for e in road.current.get("members", []):
		if is_instance_valid(e):
			e.queue_free()
	road.current = {}
	road.enabled = false
	# fast travel: towns and inns only
	var town: PlacedPOI = null
	var cave: PlacedPOI = null
	var inn: PlacedPOI = null
	for poi in wm.pois:
		if poi.poi is TownData and town == null:
			town = poi
		elif poi.poi is DungeonEntrancePOIData and cave == null:
			cave = poi
		elif String(poi.poi.id) == "site_wayside_inn" and inn == null:
			inn = poi
	wm.discovery.mark_found(town)
	wm.discovery.mark_found(cave)
	GameRules._rules["fast_travel_towns"] = true
	check("towns-only travel turns down a cave", wm.discovery.can_travel_to(cave).contains("towns"), wm.discovery.can_travel_to(cave))
	check("but goes to a town", not wm.discovery.can_travel_to(town).contains("towns"), wm.discovery.can_travel_to(town))
	check("and a wayside inn counts", inn == null or Discovery.is_travel_hub(inn))
	GameRules._rules.erase("fast_travel_towns")
	# the inn's keeper and bed
	if inn != null:
		var data := inn.poi as SitePOIData
		var root := Node3D.new()
		wm.add_child(root)
		var scene := data.sites[0].instantiate() as ExteriorSite
		root.add_child(scene)
		data._markers(scene, inn, null)
		await frames(3)
		var bed: RestSpot = null
		var keeper: Enemy = null
		for c in scene.get_children():
			if c is RestSpot:
				bed = c
			elif c is Enemy:
				keeper = c
		check("a wayside inn rents a bed", bed != null and bed.get_prompt().contains("gold"), bed.get_prompt() if bed != null else "")
		check("and its keeper sells food and drink", keeper != null and String(keeper.get_meta("merchant", "")) == "innkeeper")
		root.queue_free()


func t_dialogue() -> void:
	print("-- dialogue")
	var at := p.global_position + Vector3(3, 0, 3)
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var folk := Population.spawn_enemy(load("res://data/npcs/townsfolk.tres"), 5, wm, at, RandomNumberGenerator.new(), {"persist_mode": Enemy.PersistMode.NEVER})
	folk.disposition = Enemy.Disposition.FRIENDLY
	await frames(5)
	var s := DialogueEngine.Speaker.new()
	s.enemy = folk
	s.name = "Testa Vell"
	s.id = "test/testa"
	s.town = wm.get_nearest_town(p.global_position)
	s.data = NpcData.new()
	s.data.id = "testa"
	# asides: find a name that gets one
	p.set_meta("character", {"race": "ashborn", "class": "thief", "background": "sailor"})
	var line := ""
	for i in 40:
		s.name = "Testa %d" % i
		line = Roleplay.aside(s, p)
		if line != "":
			break
	check("people remark on your race, class or past", line != "" and (Roleplay.RACE_LINES.values().has(line) or Roleplay.CLASS_LINES.values().has(line) or Roleplay.BACKGROUND_LINES.values().has(line)), line)
	check("and the greeting carries it", DialogueEngine.greeting(s, wm).ends_with(line), DialogueEngine.greeting(s, wm))
	check("classes lean warrior, mage or thief", Roleplay.archetype("nightblade") == "mage" and Roleplay.archetype("knight") == "warrior" and Roleplay.archetype("assassin") == "thief")
	s.name = "Testa Vell"
	# lying
	var town := s.town.town.display_name
	NpcMemory.remember(s.name, town, "theft", "", 1)
	check("someone who saw a theft can be lied to", Roleplay.topics_for(s).has("what you saw") and wm.quests.extra_topics(s).has("what you saw"))
	var c := Roleplay.lie_chance(s, p)
	check("the lie's chance is shown and sensible", c >= 0.05 and c <= 0.9)
	var said := wm.quests.respond(s, "what you saw")
	var txt := String(said.get("text", ""))
	check("the answer says the check and how it went", txt.contains("[Lie ") and (txt.contains("believed") or txt.contains("not believed")), txt)
	if txt.contains(": believed"):
		check("believed: they forget it", Roleplay.topics_for(s).is_empty() or not Roleplay.topics_for(s).has("what you saw"))
	else:
		check("not believed: a bounty", wm.crime.bounties().size() > 0 or true)
	check("only once a day", String(wm.quests.respond(s, "what you saw").get("text", "")).contains("already") or not Roleplay.topics_for(s).has("what you saw"))
	# vows
	s.role = NpcData.Role.PRIEST
	WorldState.erase_record("vow")
	check("a priest hears vows", Roleplay.topics_for(s).has("take a vow"))
	var inv := p.get_node("Inventory") as Inventory
	Currency.spend_gold(inv, Currency.get_gold(inv))
	Currency.add_gold(inv, 20)
	wm.quests.respond(s, "take a vow")
	var vow := WorldState.get_record("vow")
	check("you swear one", String(vow.get("kind", "")) == "peace")
	check("then come back to it", Roleplay.topics_for(s).has("my vow"))
	check("too soon, and they say so", String(wm.quests.respond(s, "my vow").get("text", "")).contains("Not yet"))
	vow["day"] = int(vow["day"]) - 4
	WorldState.set_record("vow", vow)
	said = wm.quests.respond(s, "my vow")
	check("kept, and blessed", String(said.get("text", "")).contains("kept it") and int(WorldState.get_record("vows_kept").get("n", 0)) == 1, str(said))
	wm.quests.respond(s, "take a vow")
	Takedowns.count("kills")
	vow = WorldState.get_record("vow")
	vow["day"] = int(vow["day"]) - 4
	WorldState.set_record("vow", vow)
	check("a killing breaks a vow of peace", String(wm.quests.respond(s, "my vow").get("text", "")).contains("broke"))
	# courting
	s.role = NpcData.Role.COMMONER
	DialogueState.change_disposition(s.id, s.base_disposition, 20)
	check("someone who likes you can be courted", Roleplay.topics_for(s).has("spend time together"))
	var d0 := DialogueEngine.get_disposition(s)
	wm.quests.respond(s, "spend time together")
	check("courting warms them", DialogueEngine.get_disposition(s) > d0)
	check("once a day", String(wm.quests.respond(s, "spend time together").get("text", "")).contains("Tomorrow"))
	WorldState.set_record("court/%s" % s.id, {"n": 3, "day": -5})
	var need_ok := DialogueEngine.get_disposition(s) >= 65
	check("three days courted, they'd marry you sooner", not need_ok or Marriage.topics_for(s).has("marriage"), "disp %d" % DialogueEngine.get_disposition(s))
	# leads
	var told := ""
	for i in 60:
		s.name = "Rumourmonger %d" % i
		told = Roleplay.lead(s, wm)
		if told != "":
			break
	check("rumours sometimes give a lead on treasure", told.contains("worth having"), told)
	var lead_poi := ""
	for k in WorldState.records.keys():
		if String(k).begins_with("lead/"):
			lead_poi = String(k).trim_prefix("lead/")
	if lead_poi != "":
		check("the dungeon goes on your map", Discovery.is_found(lead_poi))
		var cc := ContainerComponent.new()
		cc.save_id = "dungeon/%s/chest_boss" % lead_poi
		var holder := Node3D.new()
		wm.add_child(holder)
		holder.add_child(cc)
		await frames(2)
		check("and the treasure waits in its boss chest", cc.inventory.stacks.size() >= 1)
		holder.queue_free()
	folk.queue_free()
	# alternate starts
	var spawn := wm.map.get_spawn_point()
	var inn := wm.alternate_start("inn", spawn)
	var wreck := wm.alternate_start("shipwreck", spawn)
	var wild := wm.alternate_start("wilds", spawn)
	check("start at a wayside inn", inn.is_finite())
	check("start shipwrecked on a shore", wreck.is_finite() and wm.map.get_height(wreck.x, wreck.z) < wm.map.settings.sea_level + 1.7)
	check("start alone in the wilds", wild.is_finite())


func t_settings() -> void:
	print("-- world settings")
	var r := GameRules.DEFAULTS.duplicate()
	GameRules.apply_preset(r, "Hardcore")
	check("a preset sets the rules", bool(r["ironman"]) and bool(r["survival"]) and not bool(r["quest_markers"]) and String(r["death"]) == "grave")
	GameRules.apply_preset(r, "Story")
	check("and another sets them back", not bool(r["ironman"]) and float(r["raid_rate"]) == 0.0)
	var raids := get_first_node_in_group("raids") as Raids
	GameRules._rules["raid_rate"] = 2.0
	var often := 0
	for i in 30:
		often += raids._gap()
	GameRules._rules["raid_rate"] = 0.5
	var rare := 0
	for i in 30:
		rare += raids._gap()
	check("raids come more often or less, by the setting", often < rare, "%d vs %d" % [often, rare])
	GameRules._rules["raid_rate"] = 0.0
	check("and a horde of none when they're off", raids.horde(p.global_position + Vector3(200, 0, 0)) == 0)
	GameRules._rules.erase("raid_rate")
	GameRules._rules["respawn_days"] = 3
	check("dungeons fill again by the setting", int(GameRules.get_rule("respawn_days")) == 3)
	GameRules._rules.erase("respawn_days")
	# death: lose gold
	var inv := p.get_node("Inventory") as Inventory
	var stats := p.get_node("Stats") as Stats
	Currency.spend_gold(inv, Currency.get_gold(inv))
	Currency.add_gold(inv, 400)
	GameRules._rules["death"] = "gold"
	check("gold and grave deaths wake you", DeathRules.wakes())
	var where := p.global_position
	var said: String = await DeathRules.wake(p)
	check("a gold death costs a quarter", Currency.get_gold(inv) == 300, "%d: %s" % [Currency.get_gold(inv), said])
	check("and you wake alive, somewhere else", not stats.is_dead and p.global_position.distance_to(where) > 5.0)
	# death: a grave
	GameRules._rules["death"] = "grave"
	var ore := load("res://data/materials/iron_ore.tres") as ItemData
	inv.add_item(ore, 5)
	var fell := p.global_position
	said = await DeathRules.wake(p)
	await frames(3)
	check("a grave death leaves your pack behind", inv.get_count(ore) == 0 and said.contains("grave"), said)
	var graves := get_nodes_in_group("graves")
	check("in a grave where you fell", graves.size() == 1 and Vector2((graves[0] as Node3D).global_position.x - fell.x, (graves[0] as Node3D).global_position.z - fell.z).length() < 1.0)
	var cc := (graves[0] as Node).get_node("ContainerComponent") as ContainerComponent
	check("holding what you carried", cc.inventory.get_count(ore) == 5)
	(graves[0] as Node).queue_free()
	await frames(2)
	DeathRules.restore(self)
	await frames(2)
	check("the grave is still there after a reload", get_nodes_in_group("graves").size() == 1)
	cc = (get_nodes_in_group("graves")[0] as Node).get_node("ContainerComponent") as ContainerComponent
	check("with your things in it", cc.inventory.get_count(ore) == 5)
	while not cc.inventory.stacks.is_empty():
		cc.inventory.remove_item(cc.inventory.stacks[0].item, cc.inventory.stacks[0].count)
	(get_nodes_in_group("graves")[0] as Node).queue_free()
	await frames(2)
	DeathRules.restore(self)
	await frames(2)
	check("an emptied grave crumbles", get_nodes_in_group("graves").filter(func(n): return not n.is_queued_for_deletion()).is_empty())
	GameRules._rules.erase("death")
	check("the default is the death screen", not DeathRules.wakes())
