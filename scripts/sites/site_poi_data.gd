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
	data.spawn_table = occupants
	data.boss = site.boss
	var ctx := {"data": data, "dungeon_id": placed.id, "level_min": zone.x + garrison_level_offset, "level_max": zone.y + garrison_level_offset,
		"density": 1.0, "seed": placed.seed_value}
	RoomFiller.fill(site, ctx)
	if dungeon != null:
		for link in site.links():
			link.make_door(placed.id)
			break
	StaticBatch.merge_interior(root)
	return root
