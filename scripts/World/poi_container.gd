class_name POIContainer
extends Resource
## A chest (or similar) that a structure contains. List these in a SimplePOIData.

@export var display_name := "Chest"
## Position relative to the middle of the structure (x right, y up, -z toward the front)
@export var offset := Vector3(0.0, 0.0, 2.0)
## Chance this particular chest exists in a given structure (decided once from the world seed)
@export_range(0.0, 1.0, 0.01) var chance := 1.0
@export var loot: Array[LootEntry] = []
## Also hold gear that suits the level of the land this is in (see ItemCatalog.curve_loot)
@export var curve_loot := true
