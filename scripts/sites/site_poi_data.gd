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
	var root := Node3D.new()
	var site := ps.instantiate() as ExteriorSite
	site.set_meta("room_id", placed.id)
	root.add_child(site)
	# spawn points on the ground follow the land (those placed up high, on a floor or a wall, stay)
	for s in site.sockets():
		if s.position.y < 0.05 and map != null:
			s.position.y = POIBuilder.ground_y(placed, map, s.position.x, s.position.z)
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
	RoomFiller.fill(site, ctx)
	if dungeon != null:
		for link in site.links():
			link.make_door(placed.id)
			break
	_markers(site, placed, map)
	StaticBatch.merge_interior(root)
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


# The keeper of a wayside inn: a friendly face by the fire
func _keeper(site: ExteriorSite, at: Vector3, placed: PlacedPOI) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = placed.seed_value
	var e := Enemy.create()
	(load("res://data/npcs/townsfolk.tres") as EnemyData).apply(e, 5, rng)
	var name := NameGen.person(rng)
	e.display_name = name
	e.talk_name = name
	e.talk_lines = PackedStringArray(["Sit by the fire a while. The road keeps.", "Bandits on the north road, I hear. Mind yourself.", "Bed's free if you can sleep on straw."])
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.spawn_key = "%s/keeper" % placed.id
	e.wander_radius = 3.0
	e.set_meta("greeting", "Welcome, traveller. Warm yourself.")
	site.add_child(e)
	e.position = at + Vector3(0, 0.3, 0)
