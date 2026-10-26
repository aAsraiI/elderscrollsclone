@tool
class_name ExteriorSite
extends RoomModule
## An outdoor place as a scene you can open and edit (Alpha 1.14): a camp, a tower, a ruin, a fort,
## a farmstead, a shrine... It is a room module laid on the land: Cells is its footprint (4 m
## squares) and its height, spawn points (SpawnSocket) fill it the same way as a dungeon room
## (props, lights, chests, the occupants and their boss), and on the ground they are set onto the
## terrain where it is built. A SiteLink (door, cave mouth, hatch, trapdoor) leads down into a
## stitched dungeon. SitePOIData lists the versions of one kind of site and places them.
##
## The editor draws the footprint; problems() also checks the links (the test runner's site
## checker).

enum Size { SMALL, MEDIUM, LARGE, HUGE }

@export_group("Site")
## What kind of place: "bandit_camp", "watchtower", "ruined_keep", "farmstead"... (quests, rumors
## and the map use it)
@export var site_kind := "camp"
## The lands it suits (biome keys); empty = any
@export var biomes: PackedStringArray = []
@export var size_class: Size = Size.MEDIUM
## Other places of the same kind stay at least this far away (m)
@export var min_distance := 400.0
## The map's symbol for it: camp, tower, ruin, fort, farm, mill, mine, shrine, stones, grave,
## battle, wreck, dock, bridge, lighthouse
@export var map_icon := "camp"
## The one who rules the place (a BOSS spawn point); empty = the occupants' own boss
@export var boss: EnemyData


func _init() -> void:
	if themes.is_empty():
		themes = PackedStringArray(["camp"])


## The ways down into its dungeon
func links() -> Array[SiteLink]:
	var out: Array[SiteLink] = []
	for c in find_children("*", "SiteLink", true, false):
		out.append(c)
	return out


## The module checker's findings, plus the site's own: a link outside the footprint, or more than one
func problems() -> PackedStringArray:
	var out := super.problems()
	var b := bounds()
	var ls := links()
	if ls.size() > 1:
		out.append("%s: more than one way down (%d SiteLinks)" % [name, ls.size()])
	for l in ls:
		if not b.grow(0.5).has_point(l.position):
			out.append("%s: link %s is outside the site" % [name, l.name])
	if site_kind == "":
		out.append("%s: no site kind" % name)
	return out
