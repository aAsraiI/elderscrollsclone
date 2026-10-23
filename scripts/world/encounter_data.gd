class_name EncounterData
extends Resource
## One kind of random event that can happen to the player out in a biome: bandits ambushing, a wolf
## pack, a wandering merchant, a hunter. List these in a biome's "Encounters". The EncounterManager
## picks one now and then (by weight), finds a spot around the player, and spawns the SpawnTable's
## creatures there at a level that suits the player and the biome.
## Create in the editor: FileSystem > right-click > New Resource > EncounterData.

@export var id: StringName
@export var display_name := "Encounter"
## What shows up. Hostile creatures, NPCs, or both.
@export var table: SpawnTable
## Chance relative to the biome's other encounters
@export var weight := 1.0
## Hostile creatures come straight for the player instead of waiting to notice them
@export var aggro := false
## Don't spawn where the player is looking (they appear behind or beside you)
@export var avoid_view := true
## How far from the player the group appears (m)
@export var distance_min := 40.0
@export var distance_max := 75.0
## How far apart the members of the group are placed (m)
@export var group_spread := 3.0
## Only happens to players of this level (0 = no limit)
@export var min_player_level := 0
@export var max_player_level := 0
## Seconds before this same encounter can happen again
@export var cooldown := 120.0
## Only after dark (werewolves, vampires)
@export var night_only := false
## Short message shown when it starts ("" = none)
@export var message := ""


func get_key() -> String:
	if id != &"":
		return String(id)
	if resource_path != "":
		return resource_path.get_file().get_basename()
	return display_name
