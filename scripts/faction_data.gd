class_name FactionData
extends Resource
## A guild the player can join: its ranks, who may join, what promotion needs, what members
## get, and what kind of work it hands out. One file per guild in scripts/Resources/Factions/.
## Membership itself is kept by Factions (saved in WorldState).

@export var id: StringName
@export var display_name := "Fighters Guild"
@export_multiline var description := ""
## The five ranks, lowest first
@export var ranks: PackedStringArray = ["Associate", "Swordsman", "Warden", "Champion", "Master"]

@export_group("Joining")
## "" = anyone, "no_bounty" = not wanted anywhere and never a murderer, "has_stolen" = has stolen
## something (or Sneak 15+), "has_murdered" = has killed an innocent
@export var join_requirement := ""
## No hall: found through a contact (the Thieves Guild, the Assassins Cult)
@export var hidden := false

@export_group("Promotion")
## Finished jobs needed to hold each rank (the first is joining)
@export var quests_for_rank: PackedInt32Array = [0, 2, 4, 7, 10]
## Skills that count for promotion (the best of them is used). Empty = player level instead.
@export var skills: PackedStringArray = []
@export var skill_for_rank: PackedInt32Array = [0, 10, 20, 35, 50]
@export var level_for_rank: PackedInt32Array = [1, 3, 6, 10, 15]

@export_group("Perks")
## A stat raised for each rank held, e.g. "max_health" +5 per rank
@export var perk_stat := ""
@export var perk_per_rank := 0.0
## Merchants (MerchantData ids) who give members better prices, and how much per rank
@export var discount_merchants: PackedStringArray = []
@export_range(0.0, 0.1, 0.005) var discount_per_rank := 0.03

@export_group("Work")
## Kinds of job it offers: "retrieve", "kill", "steal", "persuade", "deliver", "assassinate"
@export var quest_types: PackedStringArray = ["kill", "retrieve"]
## Gold for a job at the lowest rank (more at higher ranks)
@export var reward_base := 60


func rank_name(rank: int) -> String:
	return ranks[clampi(rank - 1, 0, ranks.size() - 1)] if rank > 0 else "Outsider"
