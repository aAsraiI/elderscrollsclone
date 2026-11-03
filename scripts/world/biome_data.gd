class_name BiomeData
extends Resource
## One biome: how its terrain is shaped, how it is colored, how softly it fades into its neighbors.
## Create in the editor: FileSystem > right-click > New Resource > BiomeData, then save it,
## e.g. res://data/world/desert.tres. Place it in the world by adding a
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
## How pointed the mountain ridges are: 1 = rounded, 2 = the old look, 3+ = knife-edged
@export_range(0.5, 6.0, 0.05) var ridge_sharpness := 2.0
@export_subgroup("Swirl")
## Meters the hills and mountains are pushed around by noise (domain warping): long winding ridges
## and swirling valleys instead of round lumps. 0 = off.
@export var swirl := 0.0
@export_range(20.0, 5000.0, 1.0, "or_greater") var swirl_scale := 500.0
@export_subgroup("Valleys")
## Depth (m) of winding valleys cut into the land, branching like water-worn ground. 0 = none.
@export var valley_depth := 0.0
@export_range(50.0, 5000.0, 1.0, "or_greater") var valley_scale := 700.0
## How wide the valleys are (0.05 = narrow gullies, 0.4 = broad vales)
@export_range(0.02, 0.8, 0.01) var valley_width := 0.16
@export_subgroup("Terraces")
## Height (m) of each step of terraced land (mesas, strata, rice-terrace hills). 0 = none.
@export var terrace_height := 0.0
## 0 = soft steps, 1 = flat treads with sheer risers
@export_range(0.0, 0.95, 0.01) var terrace_sharpness := 0.6
@export_subgroup("Dunes")
## Height (m) of wind-made dune ridges. 0 = none.
@export var dune_amplitude := 0.0
## Meters between dune crests
@export_range(10.0, 1000.0, 1.0, "or_greater") var dune_scale := 80.0
## Direction the crests run (degrees)
@export_range(0.0, 180.0, 1.0) var dune_angle := 35.0
@export_subgroup("Pools")
## Depth (m) of hollows that fill with water where the land is low (marsh pools, meres). 0 = none.
@export var pool_depth := 0.0
@export_range(10.0, 2000.0, 1.0, "or_greater") var pool_scale := 90.0
## How much of the land is pools (0..1)
@export_range(0.0, 1.0, 0.01) var pool_coverage := 0.3
@export_subgroup("Crags")
## Height (m) of rock outcrops, tors and spires standing up out of the land. 0 = none.
@export var crag_amplitude := 0.0
## Meters between outcrops
@export_range(20.0, 3000.0, 1.0, "or_greater") var crag_scale := 140.0
## How fat each outcrop is (share of the space between them)
@export_range(0.05, 0.9, 0.01) var crag_size := 0.3
@export_subgroup("Cones")
## Height (m) of volcanic cones (or any steep hills with a hollow top). 0 = none.
@export var cone_amplitude := 0.0
## Meters between cones
@export_range(100.0, 10000.0, 1.0, "or_greater") var cone_scale := 1100.0
## How deep the crater at the top is (share of the cone's height)
@export_range(0.0, 1.0, 0.01) var crater_depth := 0.3
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
## Higher ground (heather on hilltops, bare stone on high plateaus) fades to this color, from
## high_start to high_full meters above the biome's base height. high_full 0 = off.
@export var high_color := Color(0.45, 0.42, 0.36)
@export var high_start := 0.0
@export var high_full := 0.0
## The ground along the water: beaches, mud banks, shingle
@export var shore_color := Color(0.6, 0.55, 0.42)

@export_group("Trees")
## The kind of tree that grows here
@export var tree_style: TreeStyle = TreeStyle.BROADLEAF
## Trees per hectare (100 x 100 m). 0 = none, 15 = scattered, 150 = forest.
@export_range(0.0, 400.0, 1.0) var tree_density := 0.0
@export var tree_color := Color(0.22, 0.42, 0.18)

@export_group("Flora")
## The trees, shrubs, plants, logs and rocks that grow here, each its own layer with its own
## density, clumping and liking for slopes, heights and water (FloraLayer). When this list has
## anything in it, it replaces Tree Style / Tree Density above.
@export var flora: Array[FloraLayer] = []
## Herbs you can pick here: "ingredient_id" or "ingredient_id:weight". Empty = by the climate.
@export var herbs := PackedStringArray()
## Pickable herbs compared to the usual amount (1 = about four on a 64 m square of open ground)
@export_range(0.0, 5.0, 0.05) var herb_density := 1.0

@export_group("Ground cover and weather")
## temperate, cold, arid or wet. Decides the weather, the season's look and which herbs grow.
## Empty = guessed from the name (snow, desert, swamp...).
@export_enum("auto:", "temperate", "cold", "arid", "wet") var climate: String = ""
## Grass per square meter compared to a meadow (1.0). -1 = from the climate.
@export_range(-1.0, 2.0, 0.05) var grass_density := -1.0
## Rocks and boulders, 0..2. -1 = from the climate.
@export_range(-1.0, 2.0, 0.05) var rock_density := -1.0

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


## The climate, guessed from the name when not set
func get_climate() -> String:
	if climate != "":
		return climate
	var n := (String(id) + " " + display_name).to_lower()
	for w in ["snow", "frost", "tundra", "glacier", "ice", "winter", "frozen"]:
		if n.contains(w):
			return "cold"
	for w in ["desert", "dune", "sand", "waste", "ash", "badland", "barren", "dead"]:
		if n.contains(w):
			return "arid"
	for w in ["swamp", "marsh", "bog", "jungle", "fen", "wetland"]:
		if n.contains(w):
			return "wet"
	return "temperate"


func get_grass_density() -> float:
	if grass_density >= 0.0:
		return grass_density
	return {"temperate": 1.0, "wet": 1.0, "cold": 0.15, "arid": 0.06}.get(get_climate(), 1.0)


func get_rock_density() -> float:
	if rock_density >= 0.0:
		return rock_density
	return {"temperate": 0.35, "wet": 0.2, "cold": 0.7, "arid": 0.6}.get(get_climate(), 0.4)


func get_key() -> String:
	if id != &"":
		return String(id)
	if resource_path != "":
		return resource_path
	return display_name
