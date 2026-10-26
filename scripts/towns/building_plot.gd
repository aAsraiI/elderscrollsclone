class_name BuildingPlot
extends RefCounted
## One building of a town, as planned data (no nodes). TownLayout makes these from the seed, so
## the same world always has the same buildings, owners and locks. NPCs (homes and work places),
## shops and quests look buildings up by id: WorldManager.get_building(id).
##
## Local space of a building: its middle on the ground, the front (with the door) faces -Z.

## SEAT = the government building of a named town, where its lord sits (see NamedSettlements)
enum Kind { HOUSE, FARM, SHOP, INN, SMITHY, TEMPLE, GUILD_HALL, SEAT }

## "<town id>/b<n>", stable across runs and saves
var id := ""
var index := 0
var kind: Kind = Kind.HOUSE
## Shown on signs and the door prompt: "Brenna's House", "The Gilded Goose"
var display_name := ""
## Who lives or works here (the NPCs come with stage 3)
var owner_name := ""
## Shops: what they sell ("general", "alchemy", "clothier", "books", "fletcher")
var trade := ""
## Guild halls: "fighters", "mages" or "knights"
var guild := ""
## Seats: "castle", "keep", "tower" or "reeve", and the house whose banners hang on it
var seat_type := ""
var house := ""
## Width (x), wall height (y), depth (z) in meters
var size := Vector3(7.0, 3.4, 6.0)
## Farms: the field behind the house (width along the street, depth behind the house)
var field_size := Vector2.ZERO
## Houses in 1.14 towns: the space behind is a fenced yard with a garden, not a field
var yard := false
## Which part of a city it stands in: market, crafts, residential, noble, docks, slums ("" outside cities)
var district := ""
## Lock level 1..100 (100 = key only), 0 = the door has no lock
var lock_level := 0
## Whether the door is locked until someone (the player, or later its owner) changes that
var starts_locked := false
## Placement inside the town (town local space)
var local_pos := Vector3.ZERO
var local_yaw := 0.0
## Placement in the world, filled in by the planner
var world_pos := Vector3.ZERO
var world_yaw := 0.0
## The town this belongs to
var town_id := ""
var town_name := ""


static func kind_name(k: Kind) -> String:
	return ["House", "Farm", "Shop", "Inn", "Smithy", "Temple", "Guild Hall", "Seat"][int(k)]


## Is this a place people may walk into by day (shops, the inn, temple, guild halls)?
func is_public() -> bool:
	return kind != Kind.HOUSE and kind != Kind.FARM


## Where the door is, in the world (on the ground in front of the building)
func get_door_position() -> Vector3:
	return world_pos + Basis(Vector3.UP, world_yaw) * Vector3(0.0, 0.0, -size.z * 0.5 - 0.6)


## The same, in town local space
func get_door_local() -> Vector3:
	return local_pos + Basis(Vector3.UP, local_yaw) * Vector3(0.0, 0.0, -size.z * 0.5 - 0.6)


## Farms: town-local waypoints from the door, round the side of the house, into the field
## (`pick` chooses the side and the spot in the field)
func get_field_path(pick: int) -> PackedVector3Array:
	var basis := Basis(Vector3.UP, local_yaw)
	var side := 1.0 if pick % 2 == 0 else -1.0
	var x := side * (size.x * 0.5 + 1.2)
	var fx := (float((pick / 2) % 9) / 8.0 - 0.5) * field_size.x * 0.7
	var fz := size.z * 0.5 + 1.0 + field_size.y * (0.3 + 0.4 * float((pick / 18) % 5) / 4.0)
	var out := PackedVector3Array()
	for p in [Vector3(x, 0.0, -size.z * 0.5 - 0.8), Vector3(x, 0.0, size.z * 0.5 + 1.0), Vector3(fx, 0.0, fz)]:
		out.append(local_pos + basis * p)
	return out


## The floor rectangle of the building (plus its field) in town local space
func get_local_rect() -> Rect2:
	var front := Basis(Vector3.UP, local_yaw) * Vector3(0.0, 0.0, -1.0)
	var w := maxf(size.x, field_size.x)
	var d := size.z + field_size.y
	var center := local_pos - front * field_size.y * 0.5
	if absf(front.x) > 0.5:  # facing along X: the rectangle is turned
		return Rect2(center.x - d * 0.5, center.z - w * 0.5, d, w)
	return Rect2(center.x - w * 0.5, center.z - d * 0.5, w, d)
