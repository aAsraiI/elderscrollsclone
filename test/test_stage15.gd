extends SceneTree
## Headless tests for stage 15, the new content: mounted combat, the new creature families, bounty
## boards, the dragon and its lair, the arena, marriage and the spouse's shop, boats, and the
## homestead you build yourself.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage15.gd

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
		await process_frame


func secs(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await frames(2)
	t_data()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_data() -> void:
	print("-- the new creatures")
	var ids := ["giant_spider", "bog_lurker", "marsh_hag", "drowned_sailor", "sea_raider", "sand_scorpion", "ash_hound", "harpy", "forest_troll", "grave_ghoul", "dragon"]
	var ok := 0
	for id in ids:
		var e := load("res://data/enemies/%s.tres" % id) as EnemyData
		ok += 1 if e != null and e.get_key() == id else 0
	check("all eleven new creatures load", ok == ids.size(), str(ok))
	check("spiders and scorpions crawl", CreatureBody.kind_for("giant_spider") == CreatureBody.Kind.CRAWLER and CreatureBody.kind_for("sand_scorpion") == CreatureBody.Kind.CRAWLER)
	check("hounds and the dragon go on four legs", CreatureBody.kind_for("ash_hound") == CreatureBody.Kind.BEAST and CreatureBody.kind_for("dragon") == CreatureBody.Kind.BEAST)
	var lands := 0
	for biome in ["forest", "swamp", "coast", "desert", "ashlands", "highlands", "deadlands"]:
		var b := load("res://data/world/%s.tres" % biome) as BiomeData
		for enc in b.encounters:
			if enc != null and String(enc.get_key()) in ["forest_spiders", "swamp_lurkers", "coast_raiders", "desert_scorpions", "ash_hounds", "highland_harpies", "dead_ghouls"]:
				lands += 1
				break
	check("each land has its own creatures on the road", lands == 7, str(lands))
	var lairs := 0
	for biome in ["highlands", "snow_mountains", "ashlands"]:
		for r in (load("res://data/world/%s.tres" % biome) as BiomeData).poi_rules:
			lairs += 1 if r.poi != null and r.poi.id == &"dragon_lair" else 0
	check("dragon lairs can appear in the high and burnt lands", lairs == 3, str(lairs))
	var cave := load("res://data/spawns/dungeon_cave.tres") as SpawnTable
	var spiders := false
	for en in cave.entries:
		for m in en.members:
			spiders = spiders or m.get_key() == "giant_spider"
	check("spiders in the caves", spiders)


func t_in_game() -> void:
	print("-- in the game")
	WorldState.clear()
	SaveSession.begin_new_game(0, true)
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(30)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	var inv := player.get_node("Inventory") as Inventory
	var console := player.get_node("DebugConsole") as DebugConsole
	console.run("tp kingsreach")
	await secs(2.0)
	var town := wm.get_town_at(player.global_position, 80.0)
	check("in a town", town != null)
	if town == null:
		return
	await t_mounted(player)
	t_bounty(wm, player, inv, town)
	await t_arena(wm, player, inv, town)
	await t_dragon(wm, player)
	t_marriage(wm, player, inv)
	await t_boat(wm, player)
	await t_homestead(wm, player, inv, town)


func t_mounted(player: CharacterBody3D) -> void:
	print("-- mounted combat")
	var combat := player.get_node("MeleeCombat") as MeleeCombat
	var act := {"kind": MeleeCombat.Kind.LIGHT, "weapon": null, "heavy": false}
	var afoot := combat._act_reach(act)
	player.set_meta("riding", true)
	var mounted := combat._act_reach(act)
	player.remove_meta("riding")
	check("you reach further from the saddle", mounted > afoot + 0.5, "%f vs %f" % [mounted, afoot])


func t_bounty(wm: WorldManager, _player: Node3D, inv: Inventory, town: PlacedPOI) -> void:
	print("-- bounty boards")
	var seat: BuildingPlot = null
	for b in town.town.buildings:
		if b.kind == BuildingPlot.Kind.SEAT:
			seat = b
	check("the town has a lord's hall", seat != null)
	if seat != null:
		var built := InteriorBuilder.build(seat, 7, 5)
		var root: Node3D = built["root"]
		check("the hall has a bounty board", root.find_children("*", "BountyBoard", true, false).size() == 1)
		root.free()
	var qm := wm.quests
	var q := qm.offer_bounty(town, "board:" + town.id)
	check("the board offers a bounty", not q.is_empty() and String(q["type"]) in ["kill", "hunt"], str(q.get("type", "")))
	if q.is_empty():
		return
	check("it is a job you can see in the journal", qm.bounty_of("board:" + town.id).get("id", "") == q["id"] and q["faction"] == "bounty")
	check("not ready until the mark is dead", not qm.is_ready(q))
	WorldState.set_record("kill/quest/%s/chief" % q["id"], {"dead": true})
	check("ready once it is", qm.is_ready(q))
	var gold := Currency.get_gold(inv)
	var paid := qm.complete(q)
	check("the board pays", Currency.get_gold(inv) == gold + paid and paid >= 120, str(paid))
	check("and a new bounty can be taken", qm.bounty_of("board:" + town.id).is_empty())


func t_arena(wm: WorldManager, player: CharacterBody3D, inv: Inventory, town: PlacedPOI) -> void:
	print("-- the arena")
	var hall: BuildingPlot = null
	for t in wm.towns:
		for b in t.town.buildings:
			if b.kind == BuildingPlot.Kind.GUILD_HALL and b.guild == "fighters":
				hall = b
		if hall != null:
			break
	check("a Fighters' Guild hall somewhere", hall != null)
	if hall == null:
		return
	var built := InteriorBuilder.build(hall, 11, 5)
	var root: Node3D = built["root"]
	var arenas := root.find_children("*", "Arena", true, false)
	check("its hall has an arena gong", arenas.size() == 1)
	if arenas.is_empty():
		root.free()
		return
	root.position = player.global_position + Vector3(0, 40, 0)  # a room in the sky, like the game's interiors
	current_scene.add_child(root)
	var arena := arenas[0] as Arena
	check("you start unranked", Arena.rank() == 0 and Arena.rank_name() == "Unranked")
	var foes := arena.start_bout()
	check("the first bout brings out one fighter", foes.size() == 1)
	check("a bout cannot be started twice", arena.is_fighting() and arena.get_prompt().contains("on"))
	var gold := Currency.get_gold(inv)
	await frames(2)
	for e in foes.duplicate():
		(e.get_node("Stats") as Stats).modify_vital("health", -99999.0)
	await frames(3)
	check("winning ranks you up", Arena.rank() == 1 and Arena.rank_name() == "Brawler", str(Arena.rank()))
	check("and pays the purse", Currency.get_gold(inv) == gold + 60)
	WorldState.set_record("arena", {"rank": Arena.BOUTS.size() - 1})
	foes = arena.start_bout()
	check("the last bout has a named champion", foes.size() == 3 and foes[0].display_name.ends_with("the Unbroken"))
	for e in foes.duplicate():
		(e.get_node("Stats") as Stats).modify_vital("health", -99999.0)
	await frames(3)
	check("beating them makes you Grand Champion", Arena.is_champion())
	check("then you defend your title", arena.get_prompt().contains("defend"))
	root.queue_free()
	await frames(2)


func t_dragon(wm: WorldManager, player: CharacterBody3D) -> void:
	print("-- the dragon")
	var data := load("res://data/enemies/dragon.tres") as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var d := Population.spawn_enemy(data, 30, wm, player.global_position + Vector3(0, 1, 40), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	await frames(3)
	check("the dragon is huge", d.body_scale >= 2.5)
	check("it has wings", d.body != null and d.body.bones.has("wing_l") and d.body.bones.has("wing_r"))
	check("fire does not hurt it", float((d.get_meta("resists", {}) as Dictionary).get("resist_fire", 0.0)) >= 1.0)
	check("it breathes fire", not d.spells.is_empty())
	check("its bite reaches far", d.combat.get_main_reach() > 2.5, str(d.combat.get_main_reach()))
	check("it is much tougher than a bandit", d.max_health > 500.0, str(d.max_health))
	(d.get_node("Stats") as Stats).modify_vital("health", -999999.0)
	await frames(3)
	check("slaying it is remembered", int(WorldState.get_record("dragons_slain").get("n", 0)) == 1)
	# The lair itself
	var lair := load("res://data/world/POIs/dragon_lair.tres") as SimplePOIData
	var placed := PlacedPOI.new()
	placed.id = "test_lair"
	placed.poi = lair
	placed.position = player.global_position + Vector3(0, 0, 60)
	placed.seed_value = 99
	var node := lair.build(placed, wm.map)
	check("the lair is built: crags, bones and a hoard", node.get_child_count() > 20, str(node.get_child_count()))
	var hoard := false
	for c in node.find_children("*", "ContainerComponent", true, false):
		hoard = hoard or (c as ContainerComponent).display_name == "Dragon's Hoard"
	check("with the hoard chest", hoard)
	node.free()
	var n := 0
	for p in wm.pois:
		n += 1 if p.poi != null and p.poi.id == &"dragon_lair" else 0
	print("      (this world has %d dragon lairs)" % n)


func t_marriage(wm: WorldManager, player: CharacterBody3D, inv: Inventory) -> void:
	print("-- marriage")
	var r: TownLife.Resident = null
	for x in wm.life.residents:
		if x.data.role in [NpcData.Role.MERCHANT, NpcData.Role.COMMONER, NpcData.Role.FARMER]:
			r = x
			break
	check("someone to marry", r != null)
	if r == null:
		return
	var s := DialogueEngine.Speaker.new()
	s.data = r.data
	s.id = r.data.id
	s.name = r.data.display_name
	s.role = r.data.role
	s.town = r.town
	s.base_disposition = r.data.base_disposition
	check("strangers don't talk of marriage", not Marriage.topics_for(s).has("marriage"))
	DialogueState.change_disposition(s.id, s.base_disposition, 100)
	check("but a close friend will", Marriage.topics_for(s).has("marriage"))
	var day := wm.clock.day
	var no := Marriage.respond(s, "marriage", player, day)
	check("not without a ring", not Marriage.is_married() and String(no["text"]).contains("ring"))
	inv.add_item(load("res://data/jewelry/copper_ring_mule.tres") as ItemData)
	Marriage.respond(s, "marriage", player, day)
	check("with a ring they say yes", Marriage.is_married() and Marriage.spouse_name() == s.name)
	check("the ring is given", not inv.has_item(load("res://data/jewelry/copper_ring_mule.tres") as ItemData))
	check("your spouse keeps a shop you can always use", Barter.trade_status(s, wm)["open"] and Barter.trade_status(s, wm)["merchant"] != null)
	check("and talks about it", Marriage.topics_for(s).has("our shop"))
	var gold := Currency.get_gold(inv)
	Marriage.respond(s, "our shop", player, day + 3)
	check("three days' takings", Currency.get_gold(inv) == gold + 3 * Marriage.SHOP_TAKINGS)
	Marriage.respond(s, "our shop", player, day + 3)
	check("nothing more the same day", Currency.get_gold(inv) == gold + 3 * Marriage.SHOP_TAKINGS)


func t_boat(wm: WorldManager, player: CharacterBody3D) -> void:
	print("-- boats")
	# Find open water near the middle of the world
	var sea := wm.settings.sea_level
	var spot := Vector3.INF
	var bounds := wm.map.get_bounds()
	for i in 6000:
		var x := bounds.position.x + fposmod(float(i) * 97.3, bounds.size.x)
		var z := bounds.position.y + fposmod(float(i) * 163.7, bounds.size.y)
		var ok := true
		for o in [Vector2(0, 0), Vector2(0, -8), Vector2(0, 8), Vector2(8, 0), Vector2(-8, 0)]:
			ok = ok and wm.map.get_height(x + o.x, z + o.y) < sea - 2.0
		if ok:
			spot = Vector3(x, sea, z)
			break
	check("there is open water", spot != Vector3.INF)
	if spot == Vector3.INF:
		return
	player.global_position = spot + Vector3(0, 1, 0)
	await secs(1.0)
	var boat := Boat.make(current_scene, spot, 0.0, "")
	await frames(2)
	boat.board(player)
	check("you board the boat", boat.is_boarded() and player.has_meta("boat"))
	check("and do not swim", not (player.get_node("Swimming") as Swimming).is_swimming())
	var start := boat.global_position
	for i in 120:
		boat.steer(1.0 / 60.0, Vector2(0, -1), false)
	var moved := Vector2(boat.global_position.x - start.x, boat.global_position.z - start.z).length()
	var aground := boat.speed == 0.0
	check("rowing moves it (or it runs aground)", moved > 1.0 or aground, str(moved))
	check("it floats at the water line", absf(boat.global_position.y - sea) < 0.2)
	check("you ride in it", player.global_position.distance_to(boat.global_position) < 1.5)
	var row_speed := boat.speed
	for i in 240:
		boat.steer(1.0 / 60.0, Vector2(0, -1), true)
	check("the sail is faster", boat.speed > row_speed or boat.speed == 0.0, "%f vs %f" % [boat.speed, row_speed])
	boat.leave()
	check("E steps off", not boat.is_boarded() and not player.has_meta("boat"))
	check("the boat is remembered", WorldState.has_record("boat"))
	boat.queue_free()
	await frames(2)


func t_homestead(wm: WorldManager, player: CharacterBody3D, inv: Inventory, town: PlacedPOI) -> void:
	print("-- the homestead")
	var lord := DialogueEngine.Speaker.new()
	lord.role = NpcData.Role.LORD
	lord.town = town
	lord.name = "The Lord"
	check("a lord sells land", Homestead.topics_for(lord).has("land for sale"))
	Currency.add_gold(inv, 20000)
	var day := wm.clock.day
	var r := Homestead.respond(lord, "land for sale", player, wm, day)
	check("you buy a plot", Homestead.owns(), String(r.get("text", "")))
	if not Homestead.owns():
		return
	check("and no more land is offered", not Homestead.topics_for(lord).has("land for sale"))
	check("it is outside the town", wm.get_town_at(Homestead.plot_position(), 10.0) == null)
	player.global_position = Homestead.plot_position() + Vector3(0, 2, -12)
	await secs(2.0)
	var hs := player.get_node("Homestead") as Homestead
	check("the plot appears when you come near", hs._house != null)
	var tables := 0
	if hs._house != null:
		for c in hs._house.get_children():
			tables += 1 if c is Homestead.DraftingTable else 0
	check("with a drafting table", tables == 1)
	for i in Homestead.PARTS.size():
		hs.build_next(inv)
	check("everything gets built", Homestead.next_part().is_empty(), str(Homestead.built()))
	var beds := hs._house.find_children("*", "RestSpot", true, false)
	check("your own bed, free to sleep in", beds.size() == 1 and (beds[0] as RestSpot).is_own_home())
	check("a workshop", hs._house.find_children("*", "CraftingStation", true, false).size() >= 4)
	check("a garden", hs._house.find_children("*", "Planter", true, false).size() == 4)
	var steward := false
	for e in hs._house.find_children("*", "Enemy", true, false):
		steward = steward or (e as Enemy).display_name == "Your Steward"
	check("and a steward", steward)
	var rec := WorldState.get_record("homestead")
	rec["paid"] = wm.clock.day - 4
	WorldState.set_record("homestead", rec)
	var gold := Currency.get_gold(inv)
	hs._collect_rent()
	check("who pays the rents for the days you were away", Currency.get_gold(inv) == gold + 4 * Homestead.STEWARD_RENT)
	check("there is a marker on the map", MapMarkers.all().size() >= 1)
