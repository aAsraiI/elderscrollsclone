class_name POIRule
extends Resource
## One line in a biome's "Poi Rules": how many of one kind of POI the biome gets, and how
## picky the placement is. Edit counts here to make the world busier or emptier.

enum CountMode {
	PER_REGION,    ## the numbers are for each placed rectangle of this biome
	PER_SQUARE_KM, ## the numbers are per square kilometer, so bigger regions get more
}

@export var poi: POIData
@export var count_mode: CountMode = CountMode.PER_SQUARE_KM
## A number between these is picked per region from the world seed (fractions are rounded randomly)
@export var count_min := 1.0
@export var count_max := 2.0
## Empty ground (m) to keep around it, on top of both footprints
@export_range(0.0, 500.0, 1.0, "or_greater") var extra_spacing := 30.0
## Stay this far inside the biome's border (m) so it doesn't straddle two biomes
@export_range(0.0, 500.0, 1.0, "or_greater") var border_margin := 60.0
