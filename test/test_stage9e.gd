extends SceneTree
## Headless tests for stage 9e (Antiquarian Society, Hunters' Lodge, Merchant Consortium).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage9e.gd

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


func _run() -> void:
	t_data()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_data() -> void:
	print("-- the guilds")
	for id in ["antiquarians", "hunters", "merchants"]:
		var d := Factions.get_data(id)
		check("%s loads with 5 ranks and its own jobs" % id, d != null and d.ranks.size() == 5 and d.quest_types.size() >= 2 and Factions.IDS.has(id))
	check("the Society digs and surveys", Factions.get_data("antiquarians").quest_types.has("excavate") and Factions.get_data("antiquarians").quest_types.has("survey"))
	check("the Lodge hunts", Factions.get_data("hunters").quest_types.has("hunt"))


func _speaker(r: TownLife.Resident, wm: WorldManager) -> DialogueEngine.Speaker:
	var sp := DialogueEngine.Speaker.new()
	sp.data = r.data
	sp.id = r.data.id
	sp.name = r.data.display_name
	sp.role = r.data.role
	sp.town = r.town
	sp.home = wm.get_building(r.data.home_id)
	sp.faction = r.data.faction
	return sp


func t_in_game() -> void:
	print("-- in the game")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var city: PlacedPOI = null
	for t in wm.towns:
		if (t.poi as TownData).kind == TownData.Kind.CITY:
			var halls := []
			for b in t.town.buildings:
				if b.kind == BuildingPlot.Kind.GUILD_HALL:
					halls.append(b.guild)
			if halls.has("antiquarians") and halls.has("merchants"):
				city = t
				break
	check("cities have an Antiquarian Museum and a Counting House", city != null)
	var lodge := false
	for t in wm.towns:
		for b in t.town.buildings:
			lodge = lodge or (b.kind == BuildingPlot.Kind.GUILD_HALL and b.guild == "hunters")
	check("some towns have a Hunters' Lodge", lodge)
	if city == null:
		return
	var leaders := {}
	for r: TownLife.Resident in wm.life.get_town_residents(city.id):
		var lead := Factions.leader_of(_speaker(r, wm), wm)
		if lead != "":
			leaders[lead] = r
	check("the Society and the Consortium have leaders to talk to", leaders.has("antiquarians") and leaders.has("merchants"), str(leaders.keys()))
	if not leaders.has("antiquarians"):
		return
	var qm := wm.quests
	var giver := _speaker(leaders["antiquarians"], wm)
	p.global_position = city.position + Vector3(0, 2, 0)
	wm.ensure_area_loaded(city.position, 2)
	await frames(5)
	var dig := qm.offer("antiquarians", giver, "excavate")
	check("the Society offers an excavation", not dig.is_empty() and dig["type"] == "excavate" and String(dig["objective"]).contains("pickaxe"), str(dig))
	var survey := qm.offer("antiquarians", giver, "survey")
	check("...and a survey of a dungeon", not survey.is_empty() and survey["type"] == "survey")
	if not survey.is_empty():
		check("a survey is done when the dungeon's master is dead", not qm.is_ready(survey))
		Discovery.mark_cleared(String(survey["target"]))
		check("...like this", qm.is_ready(survey))
	if not dig.is_empty():
		var placed := wm.get_poi(String(dig["target"]))
		p.global_position = placed.position + Vector3(0, 3, 0)
		wm.ensure_area_loaded(placed.position, 2)
		await frames(30)
		var node := wm.get_poi_node(placed.id)
		var spot := node.get_node_or_null("Dig_" + String(dig["id"])) as DigSpot if node != null else null
		check("a dig spot appears at the place", spot != null)
		if spot != null:
			var dig_inv := p.get_node("Inventory") as Inventory
			spot.interact(dig_inv)
			await frames(2)
			check("no digging without a tool", not qm.is_ready(dig))
			dig_inv.add_item(load("res://data/clutter/shovel.tres"))
			spot.interact(dig_inv)
			await frames(2)
			check("with a shovel the artifact comes up", qm.is_ready(dig))
	var hunter_giver: DialogueEngine.Speaker = null
	for t in wm.towns:
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			if hunter_giver == null and Factions.leader_of(_speaker(r, wm), wm) == "hunters":
				hunter_giver = _speaker(r, wm)
	check("a Lodge has a leader", hunter_giver != null)
	if hunter_giver != null:
		var hunt := qm.offer("hunters", hunter_giver, "hunt")
		check("the Lodge offers a hunt for a named beast", not hunt.is_empty() and hunt["type"] == "hunt" and String(hunt["name"]).begins_with("The Hunt for"))
	# the museum
	var inv := p.get_node("Inventory") as Inventory
	var idol: ItemData = load("res://data/artifacts/sunfire_idol.tres")
	inv.add_item(idol)
	var gold := Currency.get_gold(inv)
	var st := p.get_node("Stats") as Stats
	var hp := st.get_stat("max_health")
	var paid := MuseumCase.donate(inv, p)
	check("donating pays the artifact's full value", paid == idol.value and Currency.get_gold(inv) == gold + idol.value)
	check("it joins the collection and leaves your pack", MuseumCase.donated().has("sunfire_idol") and not inv.has_item(idol))
	check("the collection makes you a little tougher", st.get_stat("max_health") > hp)
	inv.add_item(idol)
	check("the same relic can't be donated twice", MuseumCase.donate(inv, p) == 0)
