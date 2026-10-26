class_name DialogueProfile
extends Resource
## What one kind of person talks about and which buttons their conversation shows. One file per
## kind in data/dialogue/profiles/ (commoner.tres, guard.tres...). Roles stack: an innkeeper who
## is also the Thieves Guild's contact gets the innkeeper's AND the guild officer's topics and
## buttons (DialogueEngine.profile_for merges them).
##
## Topic kinds (Kinds):
##   home     their own town             towns    the nearest few other towns (Towns)
##   place    buildings of their town     person   people of their town
##   poi      places in the wild nearby   guilds   every guild   own_guild   only their own

## Which jobs use it: commoner, farmer, merchant, innkeeper, smith, priest, guild_member, guard,
## woodcutter, fisherman, hunter, miner, herbalist, lord, traveler, guild_officer
@export var roles: PackedStringArray = []
## General topics they have ("background", "latest rumors", "the law", "rooms"...)
@export var generic: PackedStringArray = []
@export var kinds: PackedStringArray = []
## How many other towns they know about (the nearest)
@export var towns := 2
## Most named topics listed (towns, places, people, sites)
@export var cap := 6
## Fewer at night, out of doors (0 = same as Cap)
@export var night_cap := 0
## Service buttons they may show (Services.LIST ids: trade, train, rent, duties, travel, repair, enchant)
@export var services: PackedStringArray = []
## Skills they can train (Train button)
@export var trains: PackedStringArray = []
## The highest level they train a skill to
@export var train_max := 40


## Two profiles as one (roles stack): everything either has, the larger numbers
func merged(other: DialogueProfile) -> DialogueProfile:
	var p := DialogueProfile.new()
	p.roles = roles.duplicate()
	p.roles.append_array(other.roles)
	for list in ["generic", "kinds", "services", "trains"]:
		var out: PackedStringArray = get(list).duplicate()
		for x in other.get(list):
			if not out.has(x):
				out.append(x)
		p.set(list, out)
	p.towns = maxi(towns, other.towns)
	p.cap = maxi(cap, other.cap)
	p.night_cap = maxi(night_cap, other.night_cap)
	p.train_max = maxi(train_max, other.train_max)
	return p
