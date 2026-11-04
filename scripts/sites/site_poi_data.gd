class_name SitePOIData
extends DungeonEntrancePOIData
## A kind of outdoor place made of ExteriorSite scenes (Alpha 1.14): list its versions in Sites and
## each place picks one by its seed. The scene's spawn points are set on the ground and filled
## (props, lights, chests, Occupants and the site's boss, at the land's level); a SiteLink in it
## leads into Dungeon (inherited: a DungeonData with a recipe or a hand-made scene). Its ground
## is levelled by Flatten Radius like any place.

## The versions (ExteriorSite scenes)
@export var sites: Array[PackedScene] = []
## Who lives there (rolled at the site's ENEMY spawn points); empty = nobody
@export var occupants: SpawnTable
## The map's symbol (the site scene's own Map Icon when empty)
@export var map_icon := ""


## The version this place uses
func pick(placed: PlacedPOI) -> PackedScene:
	if sites.is_empty():
		return null
	return sites[absi(placed.seed_value) % sites.size()]


func build(placed: PlacedPOI, map: WorldMap) -> Node3D:
	var ps := pick(placed)
	if ps == null:
		return super.build(placed, map)
	var t0 := Time.get_ticks_usec()
	var root := Node3D.new()
	var site := ps.instantiate() as ExteriorSite
	var t1 := Time.get_ticks_usec()
	site.set_meta("room_id", placed.id)
	root.add_child(site)
	# spawn points on the ground follow the land (those placed up high, on a floor or a wall, stay)
	for s in site.sockets():
		if s.position.y < 0.05 and map != null:
			s.position.y = POIBuilder.ground_y(placed, map, s.position.x, s.position.z)
	# and so do props and builder-kit pieces standing on the ground (furniture is the scene's own since 1.20)
	for c in site.get_children():
		if (c is InteriorProp or c is KitContainer or c is KitLootShelf or c is KitStation or c is KitModel) and (c as Node3D).position.y < 0.05 and map != null:
			(c as Node3D).position.y = POIBuilder.ground_y(placed, map, (c as Node3D).position.x, (c as Node3D).position.z)
	var zone := LevelCurve.zone_range(map, placed.position) if map != null else Vector2i(1, 5)
	var data := DungeonData.new()
	var who := SiteChanges.occupants(self, placed, site.boss)  # places change hands over time
	data.spawn_table = who[0]
	data.boss = who[1]
	# the outdoor boss and its chest: the place's own when nothing lies below, else "<id>/site" (the
	# dungeon below has the place's id: its boss clears the place, and quests fill its boss chest)
	var own_id := placed.id if dungeon == null else placed.id + "/site"
	var ctx := {"data": data, "dungeon_id": own_id, "level_min": zone.x + garrison_level_offset, "level_max": zone.y + garrison_level_offset,
		"density": 1.0, "seed": placed.seed_value}
	site.set_meta("loot_level", int(ctx["level_max"]))
	var t2 := Time.get_ticks_usec()
	RoomFiller.fill(site, ctx)
	var t3 := Time.get_ticks_usec()
	if dungeon != null:
		for link in site.links():
			link.make_door(placed.id)
			break
	_markers(site, placed, map)
	SiteLife.attach(site)
	# the animals the place keeps (near its middle, not when bandits have taken it)
	var herd: Array = SiteLife.ANIMALS.get(String(site.site_kind), [])
	if not WorldState.has_record("site_owners/" + placed.id):
		for i in herd.size():
			var a := Vector3(cos(i * 2.1) * 6.0, 0, sin(i * 2.1) * 6.0 - 4.0)
			if map != null:
				a.y = POIBuilder.ground_y(placed, map, a.x, a.z)
			SiteLife.animal(site, herd[i], a, "%s/animal%d" % [placed.id, i])
	var t4 := Time.get_ticks_usec()
	ModelLibrary.dress_structures(root)  # its walls and towers as Morrowind's (1.16)
	var t5 := Time.get_ticks_usec()
	ModelLibrary.batch_dressed(root)
	var t6 := Time.get_ticks_usec()
	StaticBatch.merge_interior(root)
	if WorldManager.profile_hitches and Time.get_ticks_usec() - t0 > 20000:
		print("HITCH     site %s: instantiate %.1f, ground %.1f, fill %.1f, markers+life %.1f, dress %.1f, batch %.1f, merge %.1f ms" % [placed.id, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, (t5 - t4) / 1000.0, (t6 - t5) / 1000.0, (Time.get_ticks_usec() - t6) / 1000.0])
	return root


## What a monument's inscription says
const INSCRIPTIONS := [
	"HERE THE HOST OF CALDRETH HELD THE LINE\nAGAINST THE ASH, AND HERE THEY LIE.\nREMEMBER THEM WHEN THE SUN IS DARK.",
	"RAISED BY THE CROWN IN THE 300TH YEAR\nTO MARK THE BORDER OF THE OLD REALM.\nWHAT LIES BEYOND IS NOBODY'S.",
	"TO THE BUILDERS OF THE ROAD,\nWHO CUT THE HILLS AND BRIDGED THE WATER,\nAND ASKED NO TOLL.",
]


# The markers a site's scene uses for the things that are more than props: a note to read, a shrine's
# blessing, herbs and ore to gather, a monument's inscription, the keeper of a wayside inn
func _markers(site: ExteriorSite, placed: PlacedPOI, map: WorldMap) -> void:
	var i := 0
	for m in site.find_children("*", "Marker3D", true, false):
		if m is SpawnSocket or m is SiteLink:
			continue
		var n := String(m.name)
		var at := (m as Node3D).position
		if map != null and at.y < 0.05:
			at.y = POIBuilder.ground_y(placed, map, at.x, at.z)
		var world := placed.position + Basis(Vector3.UP, placed.yaw) * at
		i += 1
		if n.begins_with("Note"):
			var note: Array = Readable.NOTES[absi(placed.seed_value + i) % Readable.NOTES.size()]
			Readable.make(site, at, (m as Node3D).rotation.y, note[0], note[1])
		elif n == "Inscription":
			Readable.make(site, at, (m as Node3D).rotation.y, "the inscription", INSCRIPTIONS[absi(placed.seed_value) % INSCRIPTIONS.size()], "none")
		elif n == "Blessing":
			RestSpot.make_shrine(site, at)
		elif n.begins_with("Herb"):
			HarvestNode.make_herb(site, at, world, "temperate", absi(placed.seed_value) + i)
		elif n.begins_with("Ore"):
			HarvestNode.make_ore(site, at, world, absi(placed.seed_value) + i)
		elif n == "Keeper":
			_keeper(site, at, placed)
		elif n == "Bed":
			_inn_bed(site, at, (m as Node3D).rotation.y, placed)


# 1.26: a straw bed at a wayside inn, ten gold a night
func _inn_bed(site: ExteriorSite, at: Vector3, yaw: float, placed: PlacedPOI) -> void:
	var s := RestSpot.new()
	s.kind = "bed"
	s.building_id = "%s/inn" % placed.id
	s.building_kind = BuildingPlot.Kind.INN
	site.add_child(s)
	s.position = at
	s.rotation.y = yaw
	var mat := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.3, 2.0)
	mat.mesh = box
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.62, 0.52, 0.3)
	mat.material_override = straw
	mat.position = Vector3(0, 0.15, 0)
	s.add_child(mat)


# The keeper of a wayside inn: a friendly face by the fire
func _keeper(site: ExteriorSite, at: Vector3, placed: PlacedPOI) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = placed.seed_value
	var e := Enemy.create()
	(load("res://data/npcs/townsfolk.tres") as EnemyData).apply(e, 5, rng)
	var name := NameGen.person(rng)
	e.display_name = name
	e.talk_name = name
	e.talk_lines = PackedStringArray(["Sit by the fire a while. The road keeps.", "Bandits on the north road, I hear. Mind yourself.", "Ten gold for the straw bed, and a hot bowl to go with it if you're buying."])
	e.set_meta("merchant", "innkeeper")  # 1.26: food and drink for the road
	e.set_meta("shop_id", "%s/keeper" % placed.id)
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.spawn_key = "%s/keeper" % placed.id
	e.wander_radius = 3.0
	e.set_meta("greeting", "Welcome, traveller. Warm yourself.")
	site.add_child(e)
	e.position = at + Vector3(0, 0.3, 0)


## Who lives here makes it a place for quests to send you (Alpha 1.14): any site with occupants
func is_camp() -> bool:
	return occupants != null and discoverable
