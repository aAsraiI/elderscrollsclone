extends SceneTree
## Headless tests for stage 12a (the named settlements of Caldreth and their lords' seats).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage12.gd

const W := "res://data/world/"

var passes := 0
var fails := 0
var realm_map: WorldMap


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
	var towns := t_plan()
	t_people(towns)
	t_buildings(towns)
	t_old_worlds()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- the list

func t_data() -> void:
	print("-- the named settlements")
	check("44 settlements", NamedSettlements.count() == 44, str(NamedSettlements.count()))
	check("in all 13 lands", NamedSettlements.LIST.size() == 13)
	var names := {}
	var ok := true
	var cities := 0
	for biome: String in NamedSettlements.LIST:
		var list: Array = NamedSettlements.LIST[biome]
		for i in list.size():
			var e: Dictionary = list[i]
			for key in ["name", "kind", "lord", "seat", "hall", "house"]:
				ok = ok and String(e.get(key, "")) != ""
			ok = ok and NamedSettlements.SEAT_WORDS.has(e["seat"]) and NamedSettlements.HOUSE_COLORS.has(e["house"])
			names[e["name"]] = true
			if e["kind"] == "city":
				cities += 1
				ok = ok and i == 0  # the biggest comes first, so it gets the most room
	check("every entry has a name, lord, seat and house", ok)
	check("no two share a name", names.size() == 44)
	check("9 cities and large towns", cities == 9, str(cities))
	var plains: Array = NamedSettlements.for_biome("plains")
	check("the Plains start with Kingsreach and the King", plains[0]["name"] == "Kingsreach" and plains[0]["hall"] == "Castle Dawnhold" and String(plains[0]["lord"]).begins_with("King"))
	check("a biome with no list has none", NamedSettlements.for_biome("nowhere").is_empty())
	var s := load(W + "realm_world.tres") as WorldSettings
	check("the realm uses them", s.named_settlements)
	check("random worlds do not", not (load(W + "grand_world.tres") as WorldSettings).named_settlements)


# ---------------------------------------------------------------- the planned realm

func t_plan() -> Array[PlacedPOI]:
	print("-- the realm, planned")
	var s := load(W + "realm_world.tres") as WorldSettings
	var map := WorldMap.new(s, 1337)
	var towns := SettlementPlanner.plan(map)
	map.set_pads(towns)
	SettlementPlanner.lay_out(map, towns)
	realm_map = map
	check("all 44 settlements are placed", towns.size() == 44, str(towns.size()))
	var by_name := {}
	for t in towns:
		by_name[t.town.display_name] = t
	var missing := []
	for biome: String in NamedSettlements.LIST:
		for e: Dictionary in NamedSettlements.LIST[biome]:
			if not by_name.has(e["name"]):
				missing.append(e["name"])
	check("every named settlement exists, by name", missing.is_empty(), str(missing))
	# each in its own land, with the right size
	var in_land := true
	var sized := true
	for t in towns:
		var biome := map.placements[t.region].biome.get_key()
		in_land = in_land and NamedSettlements.for_biome(biome).has(t.named)
		sized = sized and (t.poi as TownData).kind == NamedSettlements.town_kind(t.named)
	check("each stands in its own land", in_land)
	check("each is a city, town or village as listed", sized)
	# seats
	var seats_ok := true
	var bad := []
	for t in towns:
		var seat := t.town.get_seat()
		if seat == null or seat.owner_name != t.named["lord"] or seat.display_name != t.named["hall"] or seat.seat_type != t.named["seat"] or t.town.count_kind(BuildingPlot.Kind.SEAT) != 1:
			seats_ok = false
			bad.append(t.town.display_name)
	check("every settlement has exactly one seat, held by its lord", seats_ok, str(bad))
	var kings: PlacedPOI = by_name.get("Kingsreach")
	var castle := kings.town.get_seat() if kings != null else null
	check("the King lives in Castle Dawnhold, in Kingsreach", castle != null and castle.display_name == "Castle Dawnhold" and castle.seat_type == "castle" and castle.house == "aurelane")
	check("a castle is bigger than a keep, a keep than a reeve's house", castle != null and castle.size.x * castle.size.z > TownLayout.SEAT_SIZES["keep"].x * TownLayout.SEAT_SIZES["keep"].z and TownLayout.SEAT_SIZES["keep"].x > TownLayout.SEAT_SIZES["reeve"].x)
	var central := true
	for t in towns:
		var seat := t.town.get_seat()
		central = central and seat != null and seat.local_pos.length() < t.town.radius * 0.75
	check("seats stand toward the middle of town", central)
	check("seats are open by day, like other public buildings", castle != null and castle.is_public() and not castle.starts_locked and castle.lock_level >= 50)
	var briar: PlacedPOI = by_name.get("Briarwatch")
	check("Briarwatch is held from a knight's tower", briar != null and briar.town.get_seat().seat_type == "tower" and briar.town.get_seat().owner_name == "Sir Aldo Thorne")
	# the same world gives the same towns
	var map2 := WorldMap.new(s, 1337)
	var again := SettlementPlanner.plan(map2)
	map2.set_pads(again)
	SettlementPlanner.lay_out(map2, again)
	var same := again.size() == towns.size()
	for i in mini(again.size(), towns.size()):
		same = same and again[i].id == towns[i].id and again[i].town.display_name == towns[i].town.display_name and again[i].town.get_seat().id == towns[i].town.get_seat().id
	check("the same seed plans the same towns and seats", same)
	# another seed moves them but keeps the names
	var map3 := WorldMap.new(s, 99)
	var other := SettlementPlanner.plan(map3)
	map3.set_pads(other)
	SettlementPlanner.lay_out(map3, other)
	var other_names := {}
	for t in other:
		other_names[t.town.display_name] = true
	check("another world seed keeps every name", other.size() == 44 and other_names.size() == 44)
	return towns


# ---------------------------------------------------------------- lords

func t_people(towns: Array[PlacedPOI]) -> void:
	print("-- lords")
	var kings: PlacedPOI = null
	var village: PlacedPOI = null
	for t in towns:
		if t.town.display_name == "Kingsreach":
			kings = t
		if t.town.display_name == "Wheatley":
			village = t
	if kings == null or village == null:
		check("Kingsreach and Wheatley exist", false)
		return
	var people := Residents.generate(kings, null)
	var lords: Array[NpcData] = []
	for n in people:
		if n.role == NpcData.Role.LORD:
			lords.append(n)
	check("Kingsreach has one lord", lords.size() == 1, str(lords.size()))
	var king: NpcData = lords[0] if not lords.is_empty() else null
	var seat := kings.town.get_seat()
	check("the King lives and works in his castle", king != null and king.display_name == "King Aldren IV Aurelane" and king.home_id == seat.id and king.work_id == seat.id)
	check("he holds court by day", king != null and king.activity_at(12.0) == NpcData.Activity.WORK and king.activity_at(2.0) == NpcData.Activity.SLEEP)
	check("a lord is not a tradesman", not NpcData.is_tradesman(NpcData.Role.LORD) and NpcData.is_tradesman(NpcData.Role.HERBALIST))
	check("lords are called lords", NpcData.role_name(NpcData.Role.LORD) == "Lord" and NpcData.role_for(BuildingPlot.Kind.SEAT) == NpcData.Role.LORD)
	check("and say so", king != null and "\n".join(king.talk_lines).contains("I hold Kingsreach"))
	var reeves := 0
	for n in Residents.generate(village, null):
		if n.role == NpcData.Role.LORD and n.display_name == "Reeve Marta Coombe":
			reeves += 1
	check("Wheatley has its reeve", reeves == 1)


# ---------------------------------------------------------------- buildings

func t_buildings(towns: Array[PlacedPOI]) -> void:
	print("-- seat buildings")
	var types := {}
	for t in towns:
		var seat := t.town.get_seat()
		if not types.has(seat.seat_type):
			types[seat.seat_type] = t
	check("all four kinds of seat are built somewhere", types.size() == 4, str(types.keys()))
	for kind: String in ["castle", "keep", "tower", "reeve"]:
		var t: PlacedPOI = types.get(kind)
		if t == null:
			continue
		var seat := t.town.get_seat()
		var town_root := TownBuilder.build(t.poi as TownData, t, realm_map)
		var holder: Node3D = null
		for c in town_root.get_children():
			if c.has_meta("building_id") and c.get_meta("building_id") == seat.id:
				holder = c
		var door := holder.get_node_or_null("Door") as BuildingDoor if holder != null else null
		check("the %s of %s stands with a door" % [kind, t.town.display_name], holder != null and holder.name.ends_with("_Seat") and door != null and door.building_id == seat.id and door.building_name == seat.display_name)
		var inside := InteriorBuilder.build(seat, 4242, 10, 1)
		var iroot := inside["root"] as Node3D
		var chest_name := "Tithe Chest" if kind == "reeve" else "Treasury Chest"
		var found := false
		for c in iroot.get_children():
			var cc := c.get_node_or_null("ContainerComponent") as ContainerComponent
			if cc != null and cc.display_name == chest_name:
				found = true
		var spots: Dictionary = inside["spots"]
		check("inside the %s: a %s, a bed and a place to hold court" % [kind, chest_name], found and (spots["beds"] as Array).size() >= 1 and (spots["work"] as Vector3).z > 0.0)
		town_root.free()
		iroot.free()


func t_old_worlds() -> void:
	print("-- random worlds are unchanged")
	var s := load(W + "grand_world.tres") as WorldSettings
	var map := WorldMap.new(s, 1337)
	var towns := SettlementPlanner.plan(map)
	map.set_pads(towns)
	SettlementPlanner.lay_out(map, towns)
	var seats := 0
	var named := 0
	for t in towns:
		seats += t.town.count_kind(BuildingPlot.Kind.SEAT)
		named += 0 if t.named.is_empty() else 1
	check("no seats and no named towns in a random world", seats == 0 and named == 0 and towns.size() >= 25, "%d %d %d" % [seats, named, towns.size()])


# ---------------------------------------------------------------- in the game

func t_world() -> void:
	print("-- in the game")
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var player := get_first_node_in_group("player") as CharacterBody3D
	check("the game builds the realm", wm != null and player != null and wm.settings.named_settlements)
	if wm == null or player == null:
		return
	check("with all 44 named settlements", wm.towns.size() == 44, str(wm.towns.size()))
	var town := wm.get_town_at(player.global_position, 200.0)
	if town == null:
		town = wm.towns[0]
	var seat := town.town.get_seat()
	check("the start town has its seat", seat != null and wm.get_building(seat.id) == seat, town.town.display_name)
	var lord: TownLife.Resident = wm.life.get_owner_of(seat.id) if wm.life != null and seat != null else null
	check("and its lord lives there", lord != null and lord.data.role == NpcData.Role.LORD and lord.data.display_name == town.named["lord"])
