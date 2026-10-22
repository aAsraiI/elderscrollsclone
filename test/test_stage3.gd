extends SceneTree
## Headless tests for stage 3: townspeople, their day, locks that follow them, guards. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage3.gd

const R := "res://scripts/Resources/"

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
	t_schedule()
	t_plan()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _settings() -> WorldSettings:
	var s := (load(R + "World/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	return s


# ---------------------------------------------------------------- pure logic

func t_schedule() -> void:
	print("-- a day")
	var n := NpcData.new()
	n.wake_hour = 6.0
	n.work_start = 8.0
	n.work_end = 18.0
	n.sleep_hour = 21.0
	check("asleep at 2:00", n.activity_at(2.0) == NpcData.Activity.SLEEP)
	check("asleep at 23:30 (across midnight)", n.activity_at(23.5) == NpcData.Activity.SLEEP)
	check("free time at 7:00 before work", n.activity_at(7.0) == NpcData.Activity.LEISURE)
	check("working at noon", n.activity_at(12.0) == NpcData.Activity.WORK)
	check("free time in the evening", n.activity_at(19.5) == NpcData.Activity.LEISURE)
	n.role = NpcData.Role.GUARD
	check("guards are always on their rounds", n.activity_at(2.0) == NpcData.Activity.PATROL and n.activity_at(12.0) == NpcData.Activity.PATROL)
	check("a shop makes a merchant, a farm a farmer", NpcData.role_for(BuildingPlot.Kind.SHOP) == NpcData.Role.MERCHANT and NpcData.role_for(BuildingPlot.Kind.FARM) == NpcData.Role.FARMER)


func t_plan() -> void:
	print("-- who lives in a town")
	var settings := _settings()
	var map := WorldMap.new(settings, 1337)
	var towns := SettlementPlanner.plan(map)
	map.set_pads(towns)
	SettlementPlanner.lay_out(map, towns)
	var village: PlacedPOI = null
	var city: PlacedPOI = null
	for t in towns:
		if (t.poi as TownData).kind == TownData.Kind.VILLAGE and village == null:
			village = t
		if (t.poi as TownData).kind == TownData.Kind.CITY and city == null:
			city = t
	var people := Residents.generate(city, map)
	var buildings := city.town.buildings
	var for_sale := 1 if Homes.for_sale_id(city.town, TownData.Kind.CITY) != "" else 0  # stage 11: one empty house is for sale
	check("one owner per building plus guards", people.size() == buildings.size() - for_sale + Residents.GUARDS[2], "%d people, %d buildings" % [people.size(), buildings.size()])
	var ids := {}
	var owners_ok := true
	var work_ok := true
	for b in buildings:
		var found: NpcData = null
		for n in people:
			if n.home_id == b.id:
				found = n
		if b.id == Homes.for_sale_id(city.town, TownData.Kind.CITY):
			continue
		if found == null or found.display_name != b.owner_name or found.role != NpcData.role_for_plot(b):  # a house can hold a tradesman
			owners_ok = false
		elif (found.work_id == b.id) != b.is_public():
			work_ok = false
	for n in people:
		ids[n.id] = true
	check("every building's owner lives there, with the name on the door and the right job", owners_ok)
	check("shopkeepers, smiths, priests and innkeepers work in their own building", work_ok)
	check("everyone has their own id", ids.size() == people.size())
	var guards := 0
	var lines_ok := true
	for n in people:
		if n.role == NpcData.Role.GUARD:
			guards += 1
			lines_ok = lines_ok and n.home_id == "" and n.level > 1
		lines_ok = lines_ok and n.talk_lines.size() >= 2 and n.body != null
	check("the city has its guards, with no home", guards == Residents.GUARDS[2] and lines_ok)
	var again := Residents.generate(city, map)
	var same := again.size() == people.size()
	for i in mini(again.size(), people.size()):
		same = same and again[i].id == people[i].id and again[i].sleep_hour == people[i].sleep_hour and again[i].talk_lines == people[i].talk_lines
	check("the same town always has the same people and days", same)
	var guild := false
	for n in people:
		guild = guild or (n.role == NpcData.Role.GUILD_MEMBER and ["fighters", "mages", "knights"].has(n.faction))
	check("guild hall owners belong to their guild", guild)

	# walking routes keep to the streets
	var layout := city.town
	var through := false
	var long_ok := true
	for k in 12:
		var a := layout.buildings[k % layout.buildings.size()]
		var b := layout.buildings[(k * 7 + 3) % layout.buildings.size()]
		var route := layout.find_route(a.get_door_local(), b.get_door_local())
		var length := 0.0
		for i in route.size() - 1:
			length += route[i].distance_to(route[i + 1])
			for s in 10:
				var p := route[i].lerp(route[i + 1], float(s) / 10.0)
				for bp in layout.buildings:
					var rect := Rect2(bp.get_local_rect().position + Vector2(0.4, 0.4), bp.get_local_rect().size - Vector2(0.8, 0.8))
					if rect.has_point(Vector2(p.x, p.z)):
						through = true
		if length > a.get_door_local().distance_to(b.get_door_local()) * 3.0 + 30.0:
			long_ok = false
	check("routes through town never cut through a building", not through)
	check("and are not silly detours", long_ok)
	var farm: BuildingPlot = null
	for b in village.town.buildings:
		if b.kind == BuildingPlot.Kind.FARM:
			farm = b
	if farm != null:
		var path := farm.get_field_path(3)
		var field_center := farm.local_pos + Basis(Vector3.UP, farm.local_yaw) * Vector3(0, 0, farm.size.z * 0.5 + 0.5 + farm.field_size.y * 0.5)
		check("a farmer's way to work ends in the field", path[path.size() - 1].distance_to(field_center) < maxf(farm.field_size.x, farm.field_size.y) * 0.6)


# ---------------------------------------------------------------- in a running world

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
	p.add_to_group("player")
	parent.add_child(p)
	return p


func _bodies_outside(life: TownLife, town_id: String) -> Array:
	var out: Array = []
	for r: TownLife.Resident in life.get_town_residents(town_id):
		if r.node != null and is_instance_valid(r.node) and not r.node_inside and not r.node.is_dead():
			out.append(r)
	return out


func t_world() -> void:
	print("-- the day in a running world")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var player := make_player(holder)
	var inv := player.get_node("Inventory") as Inventory
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = _settings()
	holder.add_child(wm)
	await frames(10)
	var life := wm.life
	check("the world has a TownLife", life != null)
	var total := 0
	for t in wm.towns:
		total += t.town.buildings.size() + Residents.GUARDS[int((t.poi as TownData).kind)]
		if Homes.for_sale_id(t.town, int((t.poi as TownData).kind)) != "":
			total -= 1
	check("everyone in every town exists (as data)", life.residents.size() == total, "%d vs %d" % [life.residents.size(), total])

	var town := wm.get_nearest_town(player.global_position)
	player.global_position = town.position + Vector3(0, wm.get_height_at(town.position.x, town.position.z) - town.position.y + 1.0, 0)
	wm.clock.set_time(12.0)
	await secs(1.5)
	check("the town is loaded", wm.get_poi_node(town.id) != null)

	# ---- midday
	var outside := _bodies_outside(life, town.id)
	var shopkeeper: TownLife.Resident = null
	var commoner_out := false
	var keeper_out := false
	var guard: TownLife.Resident = null
	for r: TownLife.Resident in life.get_town_residents(town.id):
		if r.data.work_id != "" and shopkeeper == null and r.data.work_id == r.data.home_id:
			shopkeeper = r
	for r: TownLife.Resident in outside:
		if r.data.role == NpcData.Role.COMMONER or r.data.role == NpcData.Role.FARMER:
			commoner_out = true
		if r.data.work_id != "":
			keeper_out = true
		if r.data.role == NpcData.Role.GUARD:
			guard = r
	check("at noon townsfolk and farmers are out", commoner_out, str(outside.size()))
	check("shopkeepers are inside their shops, not out", not keeper_out)
	check("a guard is on the streets", guard != null)
	check("the shopkeeper is indoors (as data)", shopkeeper != null and shopkeeper.inside == shopkeeper.data.work_id)
	var shop := wm.get_building(shopkeeper.data.work_id)
	check("an open shop is unlocked at noon", not Locks.is_locked(shop.id, false))
	if guard != null:
		check("the guard walks rounds", guard.node.state == Enemy.State.PATROL and guard.node.route.size() > 3)
		var before := guard.node.global_position
		await secs(3.0)
		check("and is actually moving", guard.node.global_position.distance_to(before) > 2.0)
		check("no lantern in daylight", not (guard.node.get_node("Lantern") as Light3D).visible)
	var named := false
	for r: TownLife.Resident in outside:
		named = named or (r.node.display_name == r.data.display_name and r.node.get_node_or_null("NpcTalk") != null)
	check("townsfolk have their own names and can be talked to", named)

	# into the shop: the keeper is at work
	player.global_position = shop.get_door_position() + Vector3.UP
	wm.dungeons.enter(shop.id, shop.get_door_position(), 0.0)
	await secs(0.8)
	var keeper_body := shopkeeper.node
	check("inside, the shopkeeper is there", keeper_body != null and is_instance_valid(keeper_body) and shopkeeper.node_inside)
	if keeper_body != null and is_instance_valid(keeper_body):
		var work_spot: Vector3 = wm.dungeons.get_interior_root().to_global(wm.dungeons.current_spots["work"])
		check("standing at their place of work", Vector2(keeper_body.global_position.x - work_spot.x, keeper_body.global_position.z - work_spot.z).length() < 1.5)
		check("and awake", not keeper_body.get_meta("asleep", false))
	await wm.dungeons.exit()
	await frames(5)
	check("leaving the shop removes the bodies inside", shopkeeper.node == null)

	# ---- a walk home: someone outside, a little before their bedtime
	var walker: TownLife.Resident = null
	for r: TownLife.Resident in life.get_town_residents(town.id):
		if r.data.role == NpcData.Role.COMMONER and walker == null:
			walker = r
	check("there is a townsperson to follow home", walker != null)
	wm.clock.set_time(walker.data.sleep_hour - 0.2)
	await secs(1.0)
	check("before bedtime they are outside", walker.inside == "" and walker.node != null and is_instance_valid(walker.node), walker.inside)
	var home := wm.get_building(walker.data.home_id)
	wm.clock.set_time(walker.data.sleep_hour - 0.01)
	await secs(1.5)
	check("at bedtime they set off home", walker.walking and walker.node != null and walker.node.state == Enemy.State.PATROL)
	var waited := 0
	while walker.inside == "" and waited < 240:
		await secs(1.0)
		waited += 1
	check("they walk home and go in", walker.inside == walker.data.home_id and walker.node == null, "%d s" % waited)
	check("and lock the door behind them", Locks.is_locked(home.id, false))

	# ---- night
	wm.clock.set_time(23.5)
	await secs(1.0)
	var awake_outside := 0
	var guards_out := 0
	for r: TownLife.Resident in _bodies_outside(life, town.id):
		if r.data.role == NpcData.Role.GUARD:
			guards_out += 1
		else:
			awake_outside += 1
	check("at night only the guards are out", awake_outside == 0 and guards_out == Residents.GUARDS[int((town.poi as TownData).kind)], "%d others, %d guards" % [awake_outside, guards_out])
	if guard != null and guard.node != null and is_instance_valid(guard.node):
		check("guards carry a lantern at night", (guard.node.get_node("Lantern") as Light3D).visible)
	var all_locked := true
	for r: TownLife.Resident in life.get_town_residents(town.id):
		if r.data.home_id != "" and not Locks.is_locked(r.data.home_id, false):
			all_locked = false
	check("every home is locked at night", all_locked)
	check("the shop is shut", Locks.is_locked(shop.id, false))

	# sneak into a house (as if the lock were picked): the owner is in bed
	Locks.set_locked(home.id, false)
	wm.dungeons.enter(home.id, home.get_door_position(), 0.0)
	await secs(0.8)
	var sleeper := walker.node
	check("the owner is home, asleep in bed", sleeper != null and is_instance_valid(sleeper) and sleeper.get_meta("asleep", false))
	if sleeper != null and is_instance_valid(sleeper):
		check("lying down", absf(sleeper.rotation.x) > 1.0)
		var talk := sleeper.get_node_or_null("NpcTalk") as NpcTalk
		check("and mumbles in their sleep", talk != null and talk.lines[0] == "Zzz...")
		var hit := DamageInfo.new(1.0, player, &"melee")
		hit.direction = Vector3(0, 0, 1)
		sleeper.combat.take_damage(hit)
		await frames(5)
		check("a hit wakes them up", not sleeper.get_meta("asleep", false) and absf(sleeper.rotation.x) < 0.1)
	await wm.dungeons.exit()
	await frames(5)

	# the picked lock stays open until the owner locks up again (here: the next night)
	wm.clock.set_time(23.7)
	await secs(1.0)
	check("a lock opened at night stays open while nothing changes", not Locks.is_locked(home.id, true))

	# ---- morning
	wm.clock.set_time(12.0)
	await secs(1.0)
	check("in the morning the shop opens again", not Locks.is_locked(shop.id, true))
	check("and the house is back to how it usually is", Locks.is_locked(home.id, false) == home.starts_locked)

	# ---- death is remembered
	var victim: TownLife.Resident = null
	for r: TownLife.Resident in _bodies_outside(life, town.id):
		if r.data.role != NpcData.Role.GUARD:
			victim = r
			break
	check("someone is out to test with", victim != null)
	if victim != null:
		var body := victim.node
		var kill := DamageInfo.new(99999.0, player, &"melee")
		kill.direction = Vector3(0, 0, 1)
		body.combat.take_damage(kill)
		await frames(3)
		check("a killed townsperson is remembered", WorldState.has_record("kill/" + victim.data.id) and victim.dead)
		wm.clock.set_time(16.0)
		await secs(1.0)
		var again := false
		for r in _bodies_outside(life, town.id):
			again = again or r == victim
		check("and does not come back", not again)
		check("their body stays", is_instance_valid(body) and body.is_dead())

	# ---- far away and back
	_teleport(wm, player, town.position + Vector3(900, 0, 0) if wm.map.get_inside_distance(town.position.x + 900, town.position.z) > 200 else town.position - Vector3(900, 0, 0))
	await secs(2.0)
	check("when the town unloads, its people go too", _bodies_outside(life, town.id).is_empty())
	_teleport(wm, player, town.position)
	await secs(1.5)
	check("and come back with it", _bodies_outside(life, town.id).size() >= 2)
	holder.queue_free()
	await frames(2)


func _teleport(wm: WorldManager, p: Node3D, pos: Vector3) -> void:
	wm.ensure_area_loaded(pos, 2)
	p.global_position = Vector3(pos.x, wm.get_height_at(pos.x, pos.z) + 1.0, pos.z)
