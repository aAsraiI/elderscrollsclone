class_name DungeonData
extends Resource
## Describes one kind of dungeon. A DungeonEntrancePOIData points at one of these.
## The layout is generated when you walk in, from the world seed and the entrance's id,
## so the same entrance always leads to the same dungeon.

@export var id: StringName
@export var display_name := "Dark Cave"

@export_group("Layout")
@export_range(2, 40) var min_rooms := 5
@export_range(2, 40) var max_rooms := 9
## Width and depth of every room (m)
@export_range(6.0, 40.0, 0.5) var room_size := 14.0
@export_range(2.5, 12.0, 0.5) var ceiling_height := 4.5
## Chance that two neighboring rooms get a second connection, making loops
@export_range(0.0, 1.0, 0.01) var extra_loops := 0.15

@export_group("Loot")
@export var chests_min := 1
@export var chests_max := 3
## What the chests can hold (each entry rolled like any container)
@export var loot_table: Array[LootEntry] = []
## Also fill chests with gear that suits the dungeon's level (see ItemCatalog.curve_loot)
@export var curve_loot := true

@export_group("Enemies")
## What lives in the rooms (not the start room). Empty = an empty dungeon.
@export var spawn_table: SpawnTable
## Groups per room (a group is one roll of the table)
@export var enemies_per_room_min := 0
@export var enemies_per_room_max := 2
## Guards the farthest room, together with a better chest. Optional.
@export var boss: EnemyData
## Added to the biome's levels at the entrance (a dungeon is as hard as the land it is in, plus this)
@export var level_offset := 0

@export_group("Look")
@export var wall_color := Color(0.30, 0.28, 0.26)
@export var floor_color := Color(0.22, 0.20, 0.19)
@export var light_color := Color(1.0, 0.72, 0.42)
@export_range(0.0, 8.0, 0.05) var light_energy := 1.6
## How dark the dungeon is without lights
@export var ambient_color := Color(0.03, 0.03, 0.04)

@export_group("Size and features")
## How rooms are furnished (a RoomDecorator theme: cave, crypt, barrow, mine, fort, ruin, vault,
## ice, ashen, sewer, camp)
@export var theme := "cave"
## Floors: 0 = by level (one floor below level 22, then one more every 22 levels, at most 4)
@export_range(0, 6) var floors := 0
## Extra rooms per floor for every 10 levels of the dungeon, on top of min/max rooms
@export_range(0.0, 10.0, 0.1) var rooms_per_10_levels := 2.2
## From this level on: pressure-plate traps (Security disarms them). 0 = never.
@export var traps_from_level := 15
## Chance of a hidden room behind a loose stone on each floor
@export_range(0.0, 1.0, 0.01) var secret_chance := 0.6
## From this level on, a gate on each floor blocks the way to its last room until you find the lever
@export var gate_from_level := 10


## Floors this dungeon has at this level
func floors_for(level: int) -> int:
	if floors > 0:
		return floors
	return clampi(1 + level / 22, 1, 4)


func get_key() -> String:
	if id != &"":
		return String(id)
	if resource_path != "":
		return resource_path.get_file().get_basename()
	return display_name
