class_name NamedSettlements
extends RefCounted
## The 44 named settlements of the Kingdom of Caldreth (see the "World Lore & Quest Design Bible"
## doc): for every biome, the settlements in it in order (the biggest first), each with its lord
## and the government building the lord sits in. A world with WorldSettings.named_settlements on
## builds exactly these instead of random towns (SettlementPlanner), and every one of them gets
## its seat building (TownLayout) with its lord living and working in it (Residents).
##
## Entry keys:
##   name   the settlement's name
##   kind   "city", "town" or "village" (which TownData template it uses)
##   lord   the lord's full name and title, the owner of the seat
##   seat   "castle" (a great lord), "keep" (a baron), "tower" (a landed knight) or "reeve"
##   hall   the seat building's name
##   house  the fief's house, for banner colours (see HOUSE_COLORS)

const LIST := {
	"plains": [
		{"name": "Kingsreach", "kind": "city", "lord": "King Aldren IV Aurelane", "seat": "castle", "hall": "Castle Dawnhold", "house": "aurelane"},
		{"name": "Harrowford", "kind": "town", "lord": "Baron Osric Fenn", "seat": "keep", "hall": "Harrowford Manor", "house": "aurelane"},
		{"name": "Wheatley", "kind": "village", "lord": "Reeve Marta Coombe", "seat": "reeve", "hall": "Reeve's House", "house": "aurelane"},
		{"name": "Oakrest", "kind": "village", "lord": "Reeve Tam Hollis", "seat": "reeve", "hall": "Reeve's House", "house": "aurelane"},
		{"name": "Brindle Cross", "kind": "village", "lord": "Reeve Jory Underhill", "seat": "reeve", "hall": "Reeve's House", "house": "aurelane"},
	],
	"lakeland": [
		{"name": "Merewater", "kind": "city", "lord": "Duke Lucan Valcourt", "seat": "castle", "hall": "Castle Stillmere", "house": "valcourt"},
		{"name": "Reedholm", "kind": "town", "lord": "Baroness Ilse Marrow", "seat": "keep", "hall": "Reedholm Keep", "house": "valcourt"},
		{"name": "Stillwater", "kind": "village", "lord": "Reeve Anselm Wade", "seat": "reeve", "hall": "Reeve's House", "house": "valcourt"},
		{"name": "Heron's Wick", "kind": "village", "lord": "Reeve Bryn Talley", "seat": "reeve", "hall": "Reeve's House", "house": "valcourt"},
	],
	"coast": [
		{"name": "Saltmere", "kind": "city", "lord": "Duchess Isra Tidewell", "seat": "castle", "hall": "Tidewell Keep", "house": "tidewell"},
		{"name": "Gullhaven", "kind": "town", "lord": "Baron Corran Pike", "seat": "keep", "hall": "Gullhaven Tower", "house": "tidewell"},
		{"name": "Driftwood", "kind": "village", "lord": "Reeve Nessa Gale", "seat": "reeve", "hall": "Reeve's House", "house": "tidewell"},
		{"name": "Kelpstead", "kind": "village", "lord": "Reeve Old Harl", "seat": "reeve", "hall": "Reeve's House", "house": "tidewell"},
	],
	"forest": [
		{"name": "Thornhaven", "kind": "city", "lord": "Earl Rowan Ashgrove", "seat": "castle", "hall": "Greenspire Keep", "house": "ashgrove"},
		{"name": "Elmwick", "kind": "town", "lord": "Baron Piers Larkin", "seat": "keep", "hall": "Elmwick Lodge", "house": "ashgrove"},
		{"name": "Fernhollow", "kind": "village", "lord": "Reeve Hesper Yew", "seat": "reeve", "hall": "Reeve's House", "house": "ashgrove"},
		{"name": "Briarwatch", "kind": "village", "lord": "Sir Aldo Thorne", "seat": "tower", "hall": "Briarwatch Tower", "house": "ashgrove"},
		{"name": "Mossgate", "kind": "village", "lord": "Reeve Linnea Moss", "seat": "reeve", "hall": "Reeve's House", "house": "ashgrove"},
	],
	"swamp": [
		{"name": "Blackfen", "kind": "city", "lord": "Margrave Corvin Morvaine", "seat": "castle", "hall": "Mirehold Castle", "house": "morvaine"},
		{"name": "Sallow's End", "kind": "village", "lord": "Reeve Grub Meeks", "seat": "reeve", "hall": "Reeve's House", "house": "morvaine"},
		{"name": "Murkwater", "kind": "village", "lord": "Reeve Sith-Tal", "seat": "reeve", "hall": "Reeve's House", "house": "morvaine"},
	],
	"deadlands": [
		{"name": "Gravenhold", "kind": "town", "lord": "Knight-Commander Sir Halvard Greaves", "seat": "keep", "hall": "Gravenhold Citadel", "house": "order"},
		{"name": "Lastlight", "kind": "village", "lord": "Reeve Sister Dorrit", "seat": "reeve", "hall": "Reeve's House", "house": "order"},
	],
	"desert": [
		{"name": "Sunhold", "kind": "city", "lord": "Emir Kasim al-Sahrim", "seat": "castle", "hall": "The Palace of Mirrors", "house": "sahrim"},
		{"name": "Dune's Rest", "kind": "town", "lord": "Baroness Zahra Qadir", "seat": "keep", "hall": "Dune's Rest Citadel", "house": "sahrim"},
		{"name": "Tamar's Well", "kind": "village", "lord": "Reeve Ibbet Sand-Eye", "seat": "reeve", "hall": "Reeve's House", "house": "sahrim"},
		{"name": "Redsand", "kind": "village", "lord": "Reeve Omar Dask", "seat": "reeve", "hall": "Reeve's House", "house": "sahrim"},
	],
	"highlands": [
		{"name": "Cragmoor", "kind": "city", "lord": "Duke Fergus Brannoch", "seat": "castle", "hall": "Brannoch Keep", "house": "brannoch"},
		{"name": "Heathwick", "kind": "town", "lord": "Baron Dougal Reay", "seat": "keep", "hall": "Heathwick Hall", "house": "brannoch"},
		{"name": "Stonebrook", "kind": "village", "lord": "Reeve Morag Aird", "seat": "reeve", "hall": "Reeve's House", "house": "brannoch"},
		{"name": "Pinewatch", "kind": "village", "lord": "Dame Ailsa Brannoch", "seat": "tower", "hall": "Pinewatch Tower", "house": "brannoch"},
	],
	"badlands": [
		{"name": "Dustgate", "kind": "town", "lord": "Baron Grakk Ironjaw", "seat": "keep", "hall": "Dustgate Fort", "house": "brannoch"},
		{"name": "Scorch Hollow", "kind": "village", "lord": "Reeve Vell Cinders", "seat": "reeve", "hall": "Reeve's House", "house": "brannoch"},
		{"name": "Rustfield", "kind": "village", "lord": "Reeve Orsa Ironjaw", "seat": "reeve", "hall": "Reeve's House", "house": "brannoch"},
	],
	"snow_mountains": [
		{"name": "Frosthelm", "kind": "town", "lord": "Baron Ulfric Stormvold", "seat": "keep", "hall": "Frosthelm Keep", "house": "kjellvar"},
		{"name": "Highpass", "kind": "village", "lord": "Reeve Kari Ostby", "seat": "reeve", "hall": "Reeve's House", "house": "kjellvar"},
	],
	"frozen_crown": [
		{"name": "Wintergate", "kind": "city", "lord": "High Jarl Sigrun Kjellvar", "seat": "castle", "hall": "The White Hall", "house": "kjellvar"},
		{"name": "Icewater", "kind": "village", "lord": "Reeve Bjorn Haldsen", "seat": "reeve", "hall": "Reeve's House", "house": "kjellvar"},
	],
	"tundra": [
		{"name": "Northwatch", "kind": "town", "lord": "Baron Eirik Kjellvar", "seat": "keep", "hall": "Northwatch Longhall", "house": "kjellvar"},
		{"name": "Ulfstead", "kind": "village", "lord": "Reeve Signe Ulfsdottir", "seat": "reeve", "hall": "Reeve's House", "house": "kjellvar"},
		{"name": "Skyfall", "kind": "village", "lord": "Reeve Aurek", "seat": "reeve", "hall": "Reeve's House", "house": "kjellvar"},
	],
	"ashlands": [
		{"name": "Cinderhold", "kind": "city", "lord": "Archon Seraphine Vyrel", "seat": "castle", "hall": "The Obsidian Spire", "house": "vyrel"},
		{"name": "Emberwick", "kind": "town", "lord": "Baron Talvys Drem", "seat": "keep", "hall": "Emberwick Bastion", "house": "vyrel"},
		{"name": "Smokefall", "kind": "village", "lord": "Reeve Nera Ashwalker", "seat": "reeve", "hall": "Reeve's House", "house": "vyrel"},
	],
}

## Banner colours of the houses (and the Knightly Order, who hold Gravenhold)
const HOUSE_COLORS := {
	"aurelane": Color(0.85, 0.68, 0.20),
	"valcourt": Color(0.20, 0.32, 0.65),
	"tidewell": Color(0.15, 0.45, 0.32),
	"ashgrove": Color(0.12, 0.14, 0.12),
	"morvaine": Color(0.30, 0.30, 0.34),
	"brannoch": Color(0.62, 0.12, 0.10),
	"sahrim": Color(0.75, 0.20, 0.12),
	"kjellvar": Color(0.92, 0.92, 0.95),
	"vyrel": Color(0.85, 0.40, 0.08),
	"order": Color(0.80, 0.78, 0.70),
}

## What each kind of seat is called in speech ("the castle", "the reeve's house")
const SEAT_WORDS := {"castle": "castle", "keep": "keep", "tower": "tower", "reeve": "reeve's house"}


## The settlements of a biome, biggest first (empty for a biome with none)
static func for_biome(biome_key: String) -> Array:
	return LIST.get(biome_key, [])


static func count() -> int:
	var n := 0
	for k in LIST:
		n += (LIST[k] as Array).size()
	return n


## The TownData kind an entry needs
static func town_kind(entry: Dictionary) -> TownData.Kind:
	match String(entry.get("kind", "village")):
		"city":
			return TownData.Kind.CITY
		"town":
			return TownData.Kind.TOWN
	return TownData.Kind.VILLAGE


static func house_color(house: String) -> Color:
	return HOUSE_COLORS.get(house, Color(0.5, 0.4, 0.3))
