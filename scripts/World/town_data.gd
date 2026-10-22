class_name TownData
extends POIData
## A settlement template: a village, a town or a city. The world plan places them (see
## SettlementPlanner, settings in WorldSettings > Towns and roads), lays out streets and
## buildings from the seed (TownLayout), joins them with roads (RoadPlanner), and builds
## placeholder boxes for every building (TownBuilder). Every building has an inside you can
## enter, like a dungeon, and a door that can be locked.
##
## Make a new kind of settlement: duplicate one of the files in scripts/Resources/World/Towns/
## and change the numbers. Every TownData in that folder is used automatically.

enum Kind { VILLAGE, TOWN, CITY }
## CLUSTER = houses around a green (villages). STREET = a main street with side streets.
## GRID = a walled city with a grid of streets.
enum LayoutStyle { CLUSTER, STREET, GRID }

@export var kind: Kind = Kind.VILLAGE
@export var layout_style: LayoutStyle = LayoutStyle.CLUSTER
## How often this template is picked compared to the others of its kind
@export_range(0.0, 10.0, 0.1) var weight := 1.0
## Biome ids this may be built in, e.g. "plains" or "desert". Empty = every biome.
@export var allowed_biomes: PackedStringArray = []

@export_group("Buildings")
@export var houses_min := 4
@export var houses_max := 6
## A farmhouse with a field behind it
@export var farms_min := 0
@export var farms_max := 0
@export var shops_min := 0
@export var shops_max := 1
@export var inns_min := 1
@export var inns_max := 1
@export var smithies_min := 0
@export var smithies_max := 1
@export var temples_min := 0
@export var temples_max := 0
@export var guild_halls_min := 0
@export var guild_halls_max := 0
## Which guilds get a hall, in this order (fighters, mages, knights)
@export var guilds: PackedStringArray = ["fighters", "mages", "knights"]
## A stone wall with gates around the town (GRID style towns always have one)
@export var walls := false

@export_group("Look")
@export var wall_color := Color(0.62, 0.55, 0.45)
@export var roof_color := Color(0.42, 0.24, 0.16)
@export var street_color := Color(0.45, 0.39, 0.30)
## Color of the city wall
@export var stone_color := Color(0.55, 0.54, 0.52)

@export_group("Locks")
## Chance that a house or farmhouse door starts locked (shops, inns and halls start open)
@export_range(0.0, 1.0, 0.05) var house_locked_chance := 0.75
## Lock levels (1 = Novice .. 99 = Master, 100 = only a key opens it)
@export_range(1, 100) var house_lock_min := 1
@export_range(1, 100) var house_lock_max := 20


func build(placed: PlacedPOI, map: WorldMap) -> Node3D:
	return TownBuilder.build(self, placed, map)


## How many of one kind of building this template asks for (rolled from the seed)
func roll_count(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	return rng.randi_range(mini(lo, hi), maxi(lo, hi))


func allows_biome(biome: BiomeData) -> bool:
	if allowed_biomes.is_empty():
		return true
	return biome != null and allowed_biomes.has(biome.get_key())
