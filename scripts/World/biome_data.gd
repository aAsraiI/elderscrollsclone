class_name BiomeData
extends Resource
## One biome: how its terrain is shaped, how it is colored, how softly it fades into its neighbors.
## Create in the editor: FileSystem > right-click > New Resource > BiomeData, then save it,
## e.g. res://scripts/Resources/World/desert.tres. Place it in the world by adding a
## BiomePlacement to WorldSettings. The same biome can be placed several times, at any size.
##
## Terrain height = base_height + hills + mountains + detail (all smooth noise, no blocks).

enum TreeStyle { BROADLEAF, PINE, DEAD, CACTUS }

## Used for save files and noise seeding. Optional: the file path is used when empty.
@export var id: StringName
@export var display_name := "Plains"
## Color of this biome on the debug map (press M in game)
@export var map_color := Color(0.40, 0.70, 0.30)

@export_group("Blending")
## Meters over which this biome fades into its neighbors (half inside its border, half outside).
## Bigger = softer transitions. Use a large value next to tall mountains.
@export_range(1.0, 2000.0, 1.0, "or_greater") var blend_distance := 160.0

@export_group("Terrain")
## Average ground height in meters
@export var base_height := 20.0
@export_subgroup("Hills")
## How far the ground rises and falls (meters)
@export var hills_amplitude := 8.0
## Width of one hill in meters
@export_range(10.0, 5000.0, 1.0, "or_greater") var hills_scale := 220.0
## More octaves = more small bumps layered on the hills
@export_range(1, 6) var hills_octaves := 3
@export_subgroup("Mountains")
## Extra height of ridged mountains (0 = none)
@export var mountain_amplitude := 0.0
## Width of the mountain ridges in meters
@export_range(10.0, 10000.0, 1.0, "or_greater") var mountain_scale := 700.0
## Roughly how much of the biome is covered by mountains (0 to 1)
@export_range(0.0, 1.0, 0.01) var mountain_coverage := 0.5
@export_subgroup("Detail")
## Small bumps so the ground doesn't look polished (meters)
@export var detail_amplitude := 0.4
@export_range(1.0, 200.0, 0.5, "or_greater") var detail_scale := 12.0

@export_group("Colors")
@export var ground_color := Color(0.30, 0.50, 0.20)
## Large patches of this color are mixed into the ground color
@export var ground_color_alt := Color(0.40, 0.54, 0.22)
@export_range(5.0, 500.0, 1.0, "or_greater") var patch_scale := 45.0
## Steep slopes (cliffs) fade to this color
@export var steep_color := Color(0.38, 0.35, 0.32)
## Slope angle (degrees) where the cliff color starts to appear
@export_range(0.0, 90.0, 0.5) var steep_slope_start := 28.0
## Slope angle (degrees) where it is fully the cliff color
@export_range(0.0, 90.0, 0.5) var steep_slope_full := 50.0
@export var peak_color := Color(0.95, 0.96, 1.0)
## Terrain above this height gets the peak color (snow caps). The default means "never".
@export var peak_height := 100000.0
## Meters over which the peak color fades in
@export_range(1.0, 500.0, 1.0, "or_greater") var peak_blend := 25.0

@export_group("Trees")
## The kind of tree that grows here
@export var tree_style: TreeStyle = TreeStyle.BROADLEAF
## Trees per hectare (100 x 100 m). 0 = none, 15 = scattered, 150 = forest.
@export_range(0.0, 400.0, 1.0) var tree_density := 0.0
@export var tree_color := Color(0.22, 0.42, 0.18)

@export_group("Points of interest")
## What gets placed in this biome (camps, ruins, cave entrances...) and how many.
## Add an element, choose New POIRule, then drop a POI resource into its Poi field.
@export var poi_rules: Array[POIRule] = []

@export_group("Population")
## How strong things are here. Dungeons and camps in this biome are made for these levels, and
## random encounters use the player's level held inside this range.
@export var level_min := 1
@export var level_max := 10
## Random events that can happen to the player in this biome (ambushes, wolf packs, wanderers...).
## Add an element, choose New EncounterData or load one from scripts/Resources/Encounters.
@export var encounters: Array[EncounterData] = []


func get_key() -> String:
	if id != &"":
		return String(id)
	if resource_path != "":
		return resource_path
	return display_name
