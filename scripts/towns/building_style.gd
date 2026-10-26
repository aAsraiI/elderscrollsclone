@tool
class_name BuildingStyle
extends Resource
## How the buildings of one kind of land are built (Alpha 1.14): northern timber, highland stone,
## desert flat roofs, swamp stilts... (data/buildings/styles/<name>.tres, chosen by the town's biome;
## edit them in the Inspector). TownBuilder puts every building together from these and the part
## scenes in scenes/buildings/parts/.

const DIR := "res://data/buildings/styles/"
## biome key -> style name
const BY_BIOME := {
	"tundra": "northern", "snow_mountains": "northern", "frozen_crown": "northern", "forest": "timber",
	"highlands": "highland", "badlands": "highland", "desert": "desert", "ashlands": "highland",
	"swamp": "swamp", "deadlands": "swamp", "coast": "coastal", "lakeland": "timber", "plains": "timber",
}

## The walls: "plaster", "timber" (plaster with dark beams), "stone", "adobe", "planks"
@export_enum("plaster", "timber", "stone", "adobe", "planks") var walls := "timber"
## Tint over the town's wall colour (white = as it is)
@export var wall_tint := Color.WHITE
## What it stands on: "none", "stone" (a plinth), "stilts" (lifted on posts, steps up to the door)
@export_enum("none", "stone", "stilts") var base := "stone"
## The roof: "gable", "steep" (snow sheds off), "flat" (with a low parapet)
@export_enum("gable", "steep", "flat") var roof := "gable"
@export var roof_tint := Color.WHITE
@export var beam_color := Color(0.22, 0.15, 0.09)
@export var chimneys := true
## Chances (0..1) of a porch over the door, a balcony on a second floor, shutters by the windows
@export_range(0.0, 1.0) var porch := 0.3
@export_range(0.0, 1.0) var balcony := 0.3
@export_range(0.0, 1.0) var shutters := 0.5

static var _cache := {}


## The style for a town in this land (the default "timber" if the land has none)
static func for_biome(biome_key: String) -> BuildingStyle:
	var name: String = BY_BIOME.get(biome_key, "timber")
	if not _cache.has(name):
		var path := DIR + name + ".tres"
		_cache[name] = load(path) as BuildingStyle if ResourceLoader.exists(path) else BuildingStyle.new()
	return _cache[name]
