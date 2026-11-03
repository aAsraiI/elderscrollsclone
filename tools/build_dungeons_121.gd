extends SceneTree
## Alpha 1.21: more kinds of dungeon, and very large ones in the late lands. Each kind is a
## DungeonRecipe (which room modules, how many rooms, how many floors), a spawn table from the
## existing creatures, a DungeonData, its entrance (a POI) and the lands it is found in. Also thins
## out the plain cave entrances that were everywhere. Run with:
##   godot --headless --path . -s res://tools/build_dungeons_121.gd
## Running it again overwrites the files it owns and never adds a land's rule twice.

const R := "res://data/"
const RECIPES := "res://data/interiors/recipes/"

## recipe -> settings (DungeonRecipe fields). Themes are the module folders: cave, crypt, fort,
## lair, mine, ruin, sewer. extra_floors are floors joined by stair rooms.
const RECIPE := {
	"necropolis": {"themes": ["crypt", "ruin"], "mix": 0.3, "rooms_base": 16, "rooms_per_10_levels": 4, "rooms_max": 56,
		"required": ["burial_hall", "ossuary", "catacomb", "sarcophagi", "chapel"], "branching": 0.45, "corridors": 0.5, "extra_floors": 3, "density": 1.2, "light": 0},
	"deep_delve": {"themes": ["mine", "cave", "lair"], "mix": 0.35, "rooms_base": 16, "rooms_per_10_levels": 4, "rooms_max": 60,
		"required": ["ore_chamber", "storeroom", "office"], "branching": 0.4, "corridors": 0.6, "extra_floors": 4, "density": 1.1, "light": 0},
	"citadel": {"themes": ["fort", "crypt"], "mix": 0.25, "rooms_base": 18, "rooms_per_10_levels": 4, "rooms_max": 60,
		"required": ["barracks", "war_room", "kitchen", "armory", "commander", "great_hall", "cells"], "branching": 0.4, "corridors": 0.5, "extra_floors": 3, "density": 1.2, "light": 1},
	"echoing_halls": {"themes": ["ruin", "mine"], "mix": 0.3, "rooms_base": 14, "rooms_per_10_levels": 4, "rooms_max": 50,
		"required": ["fallen_hall", "library"], "branching": 0.45, "corridors": 0.55, "extra_floors": 3, "density": 1.0, "light": 0},
	"frost_tomb": {"themes": ["crypt", "cave"], "mix": 0.3, "rooms_base": 12, "rooms_per_10_levels": 3, "rooms_max": 38,
		"required": ["burial_hall", "tomb"], "branching": 0.35, "corridors": 0.5, "extra_floors": 2, "density": 1.0, "light": 0},
	"dragon_roost": {"themes": ["lair", "cave"], "mix": 0.4, "rooms_base": 10, "rooms_per_10_levels": 3, "rooms_max": 34,
		"required": ["den", "sanctum"], "branching": 0.3, "corridors": 0.4, "extra_floors": 2, "density": 0.9, "light": 0},
	"smugglers_cove": {"themes": ["cave", "sewer"], "mix": 0.3, "rooms_base": 7, "rooms_per_10_levels": 2, "rooms_max": 20,
		"required": ["lake", "cavern"], "branching": 0.35, "corridors": 0.55, "extra_floors": 0, "density": 1.0, "light": 1},
	"pirate_hold": {"themes": ["fort", "cave"], "mix": 0.35, "rooms_base": 9, "rooms_per_10_levels": 3, "rooms_max": 28,
		"required": ["storeroom", "mess_hall", "cells"], "branching": 0.35, "corridors": 0.5, "extra_floors": 1, "density": 1.1, "light": 1},
	"beast_lair": {"themes": ["lair", "cave"], "mix": 0.4, "rooms_base": 5, "rooms_per_10_levels": 2, "rooms_max": 16,
		"required": ["den"], "branching": 0.3, "corridors": 0.45, "extra_floors": 0, "density": 0.8, "light": 0},
	"catacombs": {"themes": ["crypt", "sewer"], "mix": 0.35, "rooms_base": 10, "rooms_per_10_levels": 3, "rooms_max": 30,
		"required": ["catacomb", "ossuary", "burial_hall"], "branching": 0.45, "corridors": 0.6, "extra_floors": 1, "density": 1.0, "light": 0},
	"monastery": {"themes": ["ruin", "crypt"], "mix": 0.3, "rooms_base": 10, "rooms_per_10_levels": 3, "rooms_max": 32,
		"required": ["library"], "branching": 0.35, "corridors": 0.5, "extra_floors": 1, "density": 1.0, "light": 1},
	"witch_hollow": {"themes": ["cave", "lair"], "mix": 0.35, "rooms_base": 6, "rooms_per_10_levels": 2, "rooms_max": 18,
		"required": ["lake"], "branching": 0.3, "corridors": 0.5, "extra_floors": 0, "density": 1.0, "light": 0},
}

## table -> [[members, weight, count min, count max, min level]]
const TABLES := {
	"dungeon_necropolis": [[["skeleton"], 3, 2, 4, 1], [["grave_ghoul"], 3, 1, 3, 1], [["barrow_wight"], 2, 1, 3, 1], [["skeleton_knight"], 2, 1, 2, 30], [["crypt_warden"], 1, 1, 1, 40], [["vampire"], 1, 1, 1, 50]],
	"dungeon_delve": [[["deep_crawler"], 3, 2, 4, 1], [["cave_dweller"], 3, 1, 3, 1], [["giant_spider"], 2, 1, 2, 1], [["cave_troll"], 2, 1, 1, 25]],
	"dungeon_citadel": [[["deserter"], 2, 2, 3, 1], [["reaver"], 2, 1, 3, 1], [["raider_marauder"], 2, 1, 2, 1], [["skeleton_knight"], 1, 1, 2, 30], [["bandit_brute"], 1, 1, 1, 1]],
	"dungeon_halls": [[["vault_sentinel"], 3, 1, 3, 1], [["deep_crawler"], 2, 2, 3, 1], [["skeleton_knight"], 2, 1, 2, 1], [["cave_troll"], 1, 1, 1, 30]],
	"dungeon_frost_tomb": [[["barrow_wight"], 3, 1, 3, 1], [["ice_wraith"], 2, 1, 3, 1], [["skeleton_knight"], 2, 1, 2, 1], [["frost_raider"], 1, 1, 2, 1]],
	"dungeon_roost": [[["harpy"], 2, 1, 3, 1], [["ash_hound"], 2, 2, 3, 1], [["fire_spirit"], 2, 1, 2, 1], [["frost_raider"], 1, 1, 2, 1]],
	"dungeon_smugglers": [[["smuggler"], 3, 2, 3, 1], [["cutthroat"], 2, 1, 2, 1], [["sea_raider"], 2, 1, 2, 1], [["giant_rat"], 1, 2, 4, 1]],
	"dungeon_pirates": [[["sea_raider"], 3, 2, 3, 1], [["drowned_sailor"], 2, 1, 3, 1], [["cutthroat"], 2, 1, 2, 1]],
	"dungeon_lair": [[["wolf"], 2, 2, 4, 1], [["giant_spider"], 3, 1, 3, 1], [["forest_troll"], 1, 1, 1, 10], [["werewolf"], 1, 1, 1, 20]],
	"dungeon_catacombs": [[["skeleton"], 3, 2, 4, 1], [["grave_ghoul"], 2, 1, 2, 1], [["giant_rat"], 2, 2, 4, 1]],
	"dungeon_monastery": [[["grave_ghoul"], 2, 1, 2, 1], [["skeleton"], 2, 2, 3, 1], [["ash_cultist"], 2, 1, 3, 1], [["crypt_warden"], 1, 1, 1, 20]],
	"dungeon_witch": [[["marsh_hag"], 2, 1, 2, 1], [["bog_lurker"], 2, 1, 3, 1], [["giant_spider"], 2, 1, 2, 1]],
}

## dungeon -> settings. "recipe", "table", "boss"; "entrance": [name, map color, cave mouth?, colour, footprint,
## prefer]; "biomes": {land: [per km2 min, max] or [min, max, "region"] for so many in every region of
## that land}. Anything else is a DungeonData field.
const DUNGEONS := {
	"necropolis": {"display_name": "Sunken Necropolis", "recipe": "necropolis", "table": "dungeon_necropolis", "boss": "crypt_warden", "theme": "crypt", "level_offset": 6,
		"wall_color": Color(0.28, 0.27, 0.3), "floor_color": Color(0.18, 0.17, 0.19), "light_color": Color(0.55, 0.75, 1.0), "light_energy": 1.0,
		"entrance": ["Necropolis Gate", Color(0.6, 0.55, 0.9), false, Color(0.32, 0.3, 0.34), 22.0, "low"], "biomes": {"deadlands": [1, 1, "region"]}},
	"deep_delve": {"display_name": "The Deep Delve", "recipe": "deep_delve", "table": "dungeon_delve", "boss": "crawler_queen", "theme": "mine", "level_offset": 5,
		"wall_color": Color(0.33, 0.29, 0.25), "floor_color": Color(0.23, 0.2, 0.17), "light_color": Color(1.0, 0.72, 0.42), "light_energy": 1.2,
		"entrance": ["Delve Mouth", Color(0.8, 0.6, 0.35), true, Color(0.38, 0.32, 0.26), 20.0, "high"], "biomes": {"snow_mountains": [1, 1, "region"], "badlands": [0.5, 1, "region"]}},
	"citadel": {"display_name": "Black Citadel", "recipe": "citadel", "table": "dungeon_citadel", "boss": "deserter_captain", "theme": "fort", "level_offset": 6,
		"wall_color": Color(0.24, 0.22, 0.21), "floor_color": Color(0.17, 0.16, 0.15), "light_color": Color(1.0, 0.55, 0.3), "light_energy": 1.5,
		"entrance": ["Citadel Gate", Color(0.9, 0.35, 0.25), false, Color(0.25, 0.23, 0.22), 26.0, "high"], "biomes": {"ashlands": [1, 1, "region"], "frozen_crown": [1, 1, "region"]}},
	"echoing_halls": {"display_name": "Echoing Halls", "recipe": "echoing_halls", "table": "dungeon_halls", "boss": "vault_guardian", "theme": "vault", "level_offset": 5,
		"wall_color": Color(0.45, 0.38, 0.28), "floor_color": Color(0.32, 0.27, 0.2), "light_color": Color(1.0, 0.82, 0.5), "light_energy": 1.2,
		"entrance": ["Hall Doors", Color(0.95, 0.75, 0.35), false, Color(0.5, 0.42, 0.3), 20.0, "any"], "biomes": {"desert": [1, 1, "region"], "badlands": [0.4, 0.8, "region"], "ashlands": [0.02, 0.03]}},
	"frost_tomb": {"display_name": "Frost Tomb", "recipe": "frost_tomb", "table": "dungeon_frost_tomb", "boss": "wight_lord", "theme": "ice", "level_offset": 3,
		"wall_color": Color(0.62, 0.7, 0.8), "floor_color": Color(0.7, 0.76, 0.84), "light_color": Color(0.6, 0.8, 1.0), "light_energy": 1.0,
		"entrance": ["Frozen Tomb", Color(0.7, 0.85, 1.0), false, Color(0.62, 0.7, 0.78), 16.0, "any"], "biomes": {"frozen_crown": [0.05, 0.08], "tundra": [0.04, 0.06]}},
	"dragon_roost": {"display_name": "Dragon's Roost", "recipe": "dragon_roost", "table": "dungeon_roost", "boss": "dragon", "theme": "cave", "level_offset": 8,
		"wall_color": Color(0.3, 0.26, 0.23), "floor_color": Color(0.22, 0.18, 0.16), "light_color": Color(1.0, 0.5, 0.25), "light_energy": 1.3,
		"entrance": ["Roost Cave", Color(1.0, 0.45, 0.3), true, Color(0.32, 0.27, 0.24), 18.0, "high"], "biomes": {"frozen_crown": [0.02, 0.03], "ashlands": [0.02, 0.03], "snow_mountains": [0.015, 0.025]}},
	"smugglers_cove": {"display_name": "Smugglers' Cove", "recipe": "smugglers_cove", "table": "dungeon_smugglers", "boss": "smuggler_chief", "theme": "sewer", "level_offset": 1,
		"wall_color": Color(0.32, 0.31, 0.27), "floor_color": Color(0.22, 0.21, 0.18), "light_color": Color(1.0, 0.75, 0.45), "light_energy": 1.4,
		"entrance": ["Sea Cave", Color(0.5, 0.7, 0.8), true, Color(0.36, 0.34, 0.3), 14.0, "water"], "biomes": {"coast": [0.15, 0.25], "lakeland": [0.04, 0.08]}},
	"pirate_hold": {"display_name": "Pirate Hold", "recipe": "pirate_hold", "table": "dungeon_pirates", "boss": "smuggler_chief", "theme": "fort", "level_offset": 3,
		"wall_color": Color(0.38, 0.34, 0.28), "floor_color": Color(0.26, 0.22, 0.17), "light_color": Color(1.0, 0.7, 0.4), "light_energy": 1.5,
		"entrance": ["Hold Gate", Color(0.4, 0.55, 0.75), false, Color(0.4, 0.36, 0.3), 18.0, "water"], "biomes": {"coast": [0.06, 0.1], "swamp": [0.03, 0.06]}},
	"beast_lair": {"display_name": "Beast Lair", "recipe": "beast_lair", "table": "dungeon_lair", "boss": "forest_troll", "theme": "cave", "level_offset": 0,
		"wall_color": Color(0.3, 0.27, 0.22), "floor_color": Color(0.24, 0.2, 0.16), "light_color": Color(0.9, 0.7, 0.45), "light_energy": 0.9,
		"entrance": ["Lair", Color(0.6, 0.45, 0.3), true, Color(0.34, 0.3, 0.25), 12.0, "any"], "biomes": {"forest": [0.1, 0.18], "tundra": [0.06, 0.1], "highlands": [0.06, 0.1], "plains": [0.04, 0.08]}},
	"catacombs": {"display_name": "Forgotten Catacombs", "recipe": "catacombs", "table": "dungeon_catacombs", "boss": "wight_lord", "theme": "crypt", "level_offset": 1,
		"wall_color": Color(0.33, 0.31, 0.29), "floor_color": Color(0.22, 0.2, 0.19), "light_color": Color(1.0, 0.7, 0.42), "light_energy": 1.2,
		"entrance": ["Catacomb Stair", Color(0.75, 0.7, 0.6), false, Color(0.4, 0.38, 0.36), 14.0, "low"], "biomes": {"plains": [0.06, 0.1], "lakeland": [0.05, 0.09], "highlands": [0.04, 0.07]}},
	"monastery": {"display_name": "Ruined Monastery", "recipe": "monastery", "table": "dungeon_monastery", "boss": "ashen_priest", "theme": "ruin", "level_offset": 2,
		"wall_color": Color(0.44, 0.42, 0.38), "floor_color": Color(0.3, 0.28, 0.25), "light_color": Color(1.0, 0.78, 0.5), "light_energy": 1.4,
		"entrance": ["Monastery Doors", Color(0.85, 0.8, 0.6), false, Color(0.5, 0.48, 0.44), 18.0, "high"], "biomes": {"highlands": [0.05, 0.08], "snow_mountains": [0.03, 0.05], "forest": [0.02, 0.04]}},
	"witch_hollow": {"display_name": "Witch's Hollow", "recipe": "witch_hollow", "table": "dungeon_witch", "boss": "marsh_hag", "theme": "cave", "level_offset": 1,
		"wall_color": Color(0.26, 0.28, 0.22), "floor_color": Color(0.2, 0.22, 0.16), "light_color": Color(0.6, 1.0, 0.5), "light_energy": 0.9,
		"entrance": ["Hollow", Color(0.5, 0.8, 0.4), true, Color(0.3, 0.32, 0.26), 12.0, "low"], "biomes": {"swamp": [0.12, 0.2], "deadlands": [0.06, 0.1], "forest": [0.03, 0.05]}},
}

## The older POIs that filled the land, cut back (multiplied) so the new kinds have room to show
const THIN := {"cave_entrance": 0.4, "bandit_camp": 0.5, "ruined_shrine": 0.5, "crypt_entrance": 0.6, "standing_stones": 0.6, "watchtower": 0.6, "glowing_shrine": 0.6}
const BIOMES := ["plains", "lakeland", "forest", "coast", "swamp", "highlands", "snow_mountains", "frozen_crown", "tundra", "desert", "badlands", "deadlands", "ashlands"]


func _initialize() -> void:
	for key in RECIPE:
		var r := DungeonRecipe.new()
		var spec: Dictionary = RECIPE[key]
		for f in spec:
			r.set(f, PackedStringArray(spec[f]) if spec[f] is Array else spec[f])
		r.boss = true
		_save(r, RECIPES + "%s.tres" % key)
	for key in TABLES:
		var t := SpawnTable.new()
		for row: Array in TABLES[key]:
			var se := SpawnEntry.new()
			var members: Array[EnemyData] = []
			for m: String in row[0]:
				members.append(load(R + "enemies/%s.tres" % m) as EnemyData)
			se.members = members
			se.weight = row[1]
			se.count_min = row[2]
			se.count_max = row[3]
			se.min_level = row[4]
			t.entries.append(se)
		_save(t, R + "spawns/%s.tres" % key)
	for key in DUNGEONS:
		var spec: Dictionary = DUNGEONS[key]
		var path := R + "world/Dungeons/%s.tres" % key
		var d: DungeonData = load(path) if ResourceLoader.exists(path) else DungeonData.new()
		d.id = StringName(key)
		for f in spec:
			if f in ["recipe", "table", "boss", "entrance", "biomes"]:
				continue
			d.set(f, spec[f])
		d.recipe = load(RECIPES + "%s.tres" % spec["recipe"]) as DungeonRecipe
		d.spawn_table = load(R + "spawns/%s.tres" % spec["table"]) as SpawnTable
		d.boss = load(R + "enemies/%s.tres" % spec["boss"]) as EnemyData
		d.enemies_per_room_min = 0
		d.enemies_per_room_max = 2
		d.chests_min = 2
		d.chests_max = 5
		_save(d, path)
		var ent: Array = spec["entrance"]
		var poi_path := R + "world/POIs/%s_entrance.tres" % key
		var p: DungeonEntrancePOIData = load(poi_path) if ResourceLoader.exists(poi_path) else DungeonEntrancePOIData.new()
		p.id = StringName("%s_entrance" % key)
		p.display_name = ent[0]
		p.map_color = ent[1]
		p.shape = DungeonEntrancePOIData.Shape.CAVE if ent[2] else DungeonEntrancePOIData.Shape.DOORWAY
		p.color = ent[3]
		p.footprint_radius = ent[4]
		p.flatten_radius = ent[4] * 0.5
		p.max_slope_deg = 20.0
		p.prefer = ent[5]
		p.min_same_distance = 900.0
		p.path_to_road = 300.0
		p.shape_scale = 1.0 + maxf(0.0, (ent[4] - 16.0) / 20.0)  # the big ones look big
		p.dungeon = load(path) as DungeonData
		p.enter_name = spec["display_name"]
		_save(p, poi_path)
		for biome_key: String in spec["biomes"]:
			_hook(biome_key, load(poi_path) as POIData, spec["biomes"][biome_key])
	for biome_key in BIOMES:
		_thin(biome_key)
	print("build_dungeons_121: %d recipes, %d tables, %d dungeon kinds" % [RECIPE.size(), TABLES.size(), DUNGEONS.size()])
	quit()


# Adds a rule for this entrance to a land, or updates the one already there
func _hook(biome_key: String, poi: POIData, counts: Array) -> void:
	var path := R + "world/%s.tres" % biome_key
	var b := load(path) as BiomeData
	if b == null:
		return
	for rule in b.poi_rules:
		if rule != null and rule.poi != null and rule.poi.get_key() == poi.get_key():
			rule.count_mode = POIRule.CountMode.PER_REGION if counts.size() > 2 else POIRule.CountMode.PER_SQUARE_KM
			rule.count_min = counts[0]
			rule.count_max = counts[1]
			_save(b, path)
			return
	var r := POIRule.new()
	r.poi = poi
	r.count_mode = POIRule.CountMode.PER_REGION if counts.size() > 2 else POIRule.CountMode.PER_SQUARE_KM
	r.count_min = counts[0]
	r.count_max = counts[1]
	r.extra_spacing = 80
	r.border_margin = 80
	var rules := b.poi_rules.duplicate()
	rules.append(r)
	b.poi_rules = rules
	_save(b, path)


# Cuts the old filler POIs back once (a land remembers it was thinned: its meta "thinned_121")
func _thin(biome_key: String) -> void:
	var path := R + "world/%s.tres" % biome_key
	var b := load(path) as BiomeData
	if b == null or b.has_meta("thinned_121"):
		return
	for rule in b.poi_rules:
		if rule == null or rule.poi == null:
			continue
		var k := rule.poi.get_key()
		if THIN.has(k):
			rule.count_min *= THIN[k]
			rule.count_max *= THIN[k]
	b.set_meta("thinned_121", true)
	_save(b, path)


func _save(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	if err != OK:
		print("%s: error %d" % [path.get_file(), err])
