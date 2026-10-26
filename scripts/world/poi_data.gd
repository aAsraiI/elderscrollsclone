class_name POIData
extends Resource
## Base of everything that can be placed in the world: a ruin, a camp, a cave entrance...
## You normally make one of the subclasses (SimplePOIData, DungeonEntrancePOIData): FileSystem >
## right-click > New Resource > pick the subclass. Then list it in a biome's "Poi Rules".

## Used for saves and seeding. Optional: the file path is used when empty. Don't change it later.
@export var id: StringName
@export var display_name := "Point of Interest"
## Dot color on the debug map (press M)
@export var map_color := Color(1.0, 1.0, 1.0)

@export_group("Space")
## Radius (m) of the ground this POI reserves. No other POI is placed inside it.
@export_range(2.0, 300.0, 0.5, "or_greater") var footprint_radius := 20.0
## Ground inside this radius is leveled flat; from here out to the footprint it blends back into
## the terrain. 0 = leave the terrain alone (standing stones). Never bigger than the footprint.
@export_range(0.0, 300.0, 0.5, "or_greater") var flatten_radius := 0.0
## Sites steeper than this (degrees, measured across the footprint) are rejected
@export_range(0.0, 60.0, 0.5) var max_slope_deg := 14.0
## Where it likes to stand (Alpha 1.14): "high" (hilltops: forts, towers), "water" (by a lake,
## river or the sea: docks, mills, wrecks), "road" (by a road: shrines, farms), "low" (hollows:
## graveyards) or "any" (anywhere it fits)
@export_enum("any", "high", "low", "water", "road") var prefer := "any"
## Places of this same kind stay at least this far apart (m); 0 = only the usual spacing
@export var min_same_distance := 0.0
## A dirt path is laid to the nearest road within this many meters (0 = none)
@export var path_to_road := 0.0
## A place you discover (a banner, the map, fast travel). Off for small things: a campfire, a
## signpost, a lost pack
@export var discoverable := true
## Turn each one a random way. Off = always facing the same direction.
@export var random_rotation := true

@export_group("Garrison")
## Creatures that live here. Leave empty for an empty site. A garrison is the same every time (it
## comes from the world seed) and the ones you kill stay dead.
@export var garrison: SpawnTable
## How many times the table is rolled (each roll can be a whole group)
@export var garrison_groups_min := 1
@export var garrison_groups_max := 2
## How far from the middle they stand (m). 0 = 60% of the footprint radius.
@export var garrison_radius := 0.0
## Added to the biome's levels. +3 makes this place tougher than its surroundings.
@export var garrison_level_offset := 0


func get_key() -> String:
	if id != &"":
		return String(id)
	if resource_path != "":
		return resource_path.get_file().get_basename()
	return display_name


## Makes the structure. Subclasses override this. The returned node's origin is the ground point
## at the middle of the POI (the caller moves and turns it), its front faces -Z. Use `map` to put
## pieces on the ground: map.get_height(x, z) - placed.position.y is the local height of a spot.
func build(_placed: PlacedPOI, _map: WorldMap) -> Node3D:
	return null
