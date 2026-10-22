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
