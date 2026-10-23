class_name BiomePlacement
extends Resource
## One rectangle of the world map filled with a biome. WorldSettings holds a list of these.
## The rectangle is only the rough size and position: the border is bent by noise at runtime
## so biomes get natural, uneven edges.
##
## Cells are squares of WorldSettings.cell_size meters. Cell x grows to the east and
## cell y grows to the SOUTH (+Z in Godot), so smaller y = further north.

@export var biome: BiomeData
## Top-left (north-west) cell of the rectangle
@export var cell := Vector2i.ZERO
## Width and height in cells
@export var size_cells := Vector2i(4, 4)


## The rectangle in world meters (x = east, y = south / +Z)
func get_rect(cell_size: float) -> Rect2:
	return Rect2(Vector2(cell) * cell_size, Vector2(size_cells) * cell_size)


func is_valid() -> bool:
	return biome != null and size_cells.x > 0 and size_cells.y > 0


## Overrides the biome's level range for this rectangle only (0 = use the biome's own). The same
## biome can then be easy in one corner of the world and hard in another.
@export var level_min := 0
@export var level_max := 0


func get_level_range() -> Vector2i:
	var lo := level_min if level_min > 0 else biome.level_min
	var hi := level_max if level_max > 0 else biome.level_max
	return Vector2i(lo, maxi(hi, lo))
