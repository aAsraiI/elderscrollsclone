@tool
class_name InteriorOverrides
extends Resource
## Hand-made interiors that replace generated ones (data/interiors/overrides.tres; edit it in the
## Inspector):
##   buildings  "<town>/<building name>" (or a building id) -> a RoomModule scene with the
##              building markers (see tools/build_houses.gd), used instead of a picked one
##   dungeons   a dungeon's id -> a scene of room modules (StitchedInterior)
## Castle Dawnhold has its own scene and needs no entry.

const PATH := "res://data/interiors/overrides.tres"

@export var buildings: Dictionary[String, PackedScene] = {}
@export var dungeons: Dictionary[String, PackedScene] = {}
## "<town>/<building name>" (or a building id) -> a scene that stands in for the building outside
## (origin at the middle of its floor, front door on the -Z side; the door is added for you)
@export var exteriors: Dictionary[String, PackedScene] = {}

static var _cached: InteriorOverrides


static func get_all() -> InteriorOverrides:
	if _cached == null:
		_cached = load(PATH) as InteriorOverrides if ResourceLoader.exists(PATH) else InteriorOverrides.new()
	return _cached


## The hand-made scene for a town building ("" = none)
static func building_scene(b: BuildingPlot) -> String:
	var all := get_all()
	for key in ["%s/%s" % [b.town_name, b.display_name], b.id]:
		var ps: PackedScene = all.buildings.get(key)
		if ps != null:
			return ps.resource_path
	return ""


## The hand-made scene for a dungeon ("" = none)
static func dungeon_scene(dungeon_id: String) -> String:
	var ps: PackedScene = get_all().dungeons.get(dungeon_id)
	return ps.resource_path if ps != null else ""


## The hand-made outside of a town building ("" = generated)
static func exterior_scene(b: BuildingPlot) -> String:
	var all := get_all()
	for key in ["%s/%s" % [b.town_name, b.display_name], b.id]:
		var ps: PackedScene = all.exteriors.get(key)
		if ps != null:
			return ps.resource_path
	return ""
