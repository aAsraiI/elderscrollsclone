class_name PlacedPOI
extends RefCounted
## One point of interest the world plan has decided to put somewhere. Not a node: the planner
## makes a list of these at world creation (cheap), and the real structure is only built while
## its chunk is loaded.

## Stable across runs and saves: region + POI type + number. Saved changes are keyed by it.
var id := ""
var poi: POIData
## Ground point at the middle of the POI (the ground is leveled to this height if the POI flattens)
var position := Vector3.ZERO
## Turn around the Y axis. The front of every structure faces -Z, like Godot's "forward".
var yaw := 0.0
## For anything random inside the structure (stone positions, loot, dungeon layout)
var seed_value := 0
## Index into WorldMap.placements
var region := -1
## Towns only: the planned streets and buildings
var town: TownLayout
## Named towns only: the NamedSettlements entry (name, lord, seat...); empty for random towns
var named: Dictionary = {}


func get_anchor_chunk(chunk_size: float) -> Vector2i:
	return Vector2i(floori(position.x / chunk_size), floori(position.z / chunk_size))
