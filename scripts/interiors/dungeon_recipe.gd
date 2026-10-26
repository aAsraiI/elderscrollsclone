@tool
class_name DungeonRecipe
extends Resource
## What a stitched interior is made of (data/interiors/recipes/): which room themes, how many
## rooms, which kinds it must have, how it branches, how many floors. DungeonAssembler follows it.
## A fort recipe asks for a barracks, a war room and a kitchen; a mine for ore chambers; a crypt
## for burial halls and a tomb.

## Room themes to draw from (the first is the main one; others mix in: a fort over a crypt)
@export var themes: PackedStringArray = ["fort"]
## How much of the mix each extra theme gets (0..1)
@export_range(0.0, 1.0) var mix := 0.2
## Rooms on the way at level 1, and how many more every 10 levels
@export var rooms_base := 8
@export var rooms_per_10_levels := 3
@export var rooms_max := 28
## Kinds of room it must contain (from the modules' Kind: barracks, war_room, kitchen...)
@export var required: PackedStringArray = []
## How often the path splits into side branches (0..1)
@export_range(0.0, 1.0) var branching := 0.35
## How often a corridor is put between two rooms (0..1)
@export_range(0.0, 1.0) var corridors := 0.55
## Floors above and below the first, joined by stair rooms (0 = all on one floor)
@export var extra_floors := 0
## A boss room at the far end
@export var boss := true
## How cluttered the rooms are (scales every spawn point's chance)
@export_range(0.2, 2.0) var density := 1.0
## Light: 0 dark, 1 dim, 2 lit
@export_range(0, 2) var light := 1


## Rooms for a dungeon of this level
func rooms_for(level: int) -> int:
	return mini(rooms_base + rooms_per_10_levels * (level / 10), rooms_max)
