class_name IslandData
extends Resource
## An island out in the sea (Regions layouts only), made exactly like the main island: a list of
## biome placements, whose boxes together give the island's rough size and place, cut into rounded
## regions and ringed by its own coastline. Add it to WorldSettings > Islands. Any size, any number
## of biomes; its boxes are in the same cells as the main island's, so place it out in the open sea
## (keep at least a couple of kilometers of water between it and other land).

@export var name := "Island"
## The biome regions of this island (same as WorldSettings > Placements)
@export var placements: Array[BiomePlacement] = []
## How round the island is: 0 = squarish, 0.5 = nearly a circle
@export_range(0.0, 0.5, 0.01) var roundness := 0.42
## How far noise pushes its coast in and out (m). -1 = from its size (smaller islands, gentler coast).
@export var coast_warp := -1.0
## How far noise bends its region borders (m). -1 = from its size.
@export var region_warp := -1.0
## A port town is built on its shore, with a ship to the other ports (SeaTravel)
@export var port := true


func get_valid_placements() -> Array[BiomePlacement]:
	var out: Array[BiomePlacement] = []
	for p in placements:
		if p != null and p.is_valid():
			out.append(p)
	return out
