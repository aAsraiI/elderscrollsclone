class_name NameGen
extends RefCounted
## Names for towns, people and inns, picked from word lists with a seeded random generator
## (so the same world always has the same names). Add words to the lists to get more variety.

const TOWN_START := ["Ash", "Bright", "Cold", "Dun", "Elm", "Fair", "Glen", "Hearth", "Iron", "Kings",
	"Lake", "Mill", "North", "Oak", "Raven", "Stone", "Thorn", "West", "Wolf", "Wynd", "Red", "Silver",
	"Black", "High", "Amber", "Frost", "Sand", "Gold", "Hollow", "Briar"]
const TOWN_END := ["ford", "holm", "brook", "stead", "wick", "dale", "haven", "fall", "moor", "gate",
	"crest", "watch", "bury", "ton", "reach", "field", "mere", "march", "well", "hold"]
const FIRST := ["Brenna", "Aldric", "Maren", "Tobin", "Isolde", "Garrick", "Wren", "Osric", "Lysa",
	"Bram", "Hilde", "Corwin", "Edda", "Fenn", "Greta", "Halvard", "Ingrid", "Jory", "Kestrel", "Lorn",
	"Mira", "Nils", "Orla", "Piers", "Rowan", "Sigrid", "Tamsin", "Ulric", "Vera", "Willem", "Yara",
	"Dagny", "Emeric", "Freya", "Gideon", "Hesper", "Ivo", "Juniper", "Kael", "Linnea"]
const LAST := ["Ashford", "Barrow", "Coldwater", "Dunmore", "Elwood", "Fenwick", "Greaves", "Hollis",
	"Ironside", "Kettle", "Larkin", "Merrow", "Northcott", "Oakes", "Penhale", "Quarry", "Redfern",
	"Stroud", "Thatcher", "Underhill", "Vance", "Whitlock", "Yew", "Brandt", "Carver", "Dale"]
const INN_ADJ := ["Gilded", "Prancing", "Sleeping", "Drunken", "Rusty", "Laughing", "Golden", "Silver",
	"Wandering", "Crooked", "Merry", "Salty", "Frozen", "Burning", "Lucky", "Weary"]
const INN_NOUN := ["Goose", "Stag", "Mare", "Flagon", "Lantern", "Boar", "Kettle", "Anchor", "Griffin",
	"Hearth", "Wolf", "Barrel", "Crown", "Bard", "Pony", "Tankard"]
const DIVINES := ["the Eight", "the Dawn", "the Hearth Mother", "the Silent Watcher", "the Sun", "the Tides"]
## Kinds of shop. Each key has a MerchantData of the same name in scripts/Resources/Merchants/.
const TRADES := {
	"general": "General Goods",
	"alchemy": "Alchemist",
	"jeweler": "Jewels",
	"pawnbroker": "Pawnshop",
	"provisioner": "Provisions",
}
const GUILD_HALLS := {
	"fighters": "Fighters Guild Hall",
	"mages": "Mages Guild Hall",
	"knights": "Knightly Order Chapterhouse",
	"thieves": "Thieves Den",
	"antiquarians": "Antiquarian Museum",
	"hunters": "Hunters' Lodge",
	"merchants": "Consortium Counting House",
}


static func town(rng: RandomNumberGenerator) -> String:
	var a: String = TOWN_START[rng.randi_range(0, TOWN_START.size() - 1)]
	var b: String = TOWN_END[rng.randi_range(0, TOWN_END.size() - 1)]
	if a.to_lower().ends_with(b.substr(0, 1)):
		b = b.substr(1)  # "Ashhaven" -> "Ashaven"
	return a + b


static func person(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [FIRST[rng.randi_range(0, FIRST.size() - 1)], LAST[rng.randi_range(0, LAST.size() - 1)]]


static func first_name(full: String) -> String:
	return full.get_slice(" ", 0)


static func last_name(full: String) -> String:
	return full.get_slice(" ", 1) if full.contains(" ") else full


static func inn(rng: RandomNumberGenerator) -> String:
	return "The %s %s" % [INN_ADJ[rng.randi_range(0, INN_ADJ.size() - 1)], INN_NOUN[rng.randi_range(0, INN_NOUN.size() - 1)]]


static func temple(rng: RandomNumberGenerator) -> String:
	return "Temple of %s" % DIVINES[rng.randi_range(0, DIVINES.size() - 1)]
