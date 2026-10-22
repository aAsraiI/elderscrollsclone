extends SceneTree
## Makes the stage 9 dungeon types: their enemies, spawn tables, DungeonData, entrances, and adds
## the entrances to the biomes they belong in. Run with:
##   godot --headless --path . -s res://tools/build_dungeons.gd
## Running it again overwrites the files it owns and does not add a biome rule twice.

const R := "res://scripts/Resources/"
const K := EnemyData.Kit

## key -> settings (anything EnemyData has)
const ENEMIES := {
	"giant_rat": {"display_name": "Giant Rat", "color": Color(0.40, 0.34, 0.30), "kit": K.UNARMED, "health_mult": 0.4, "poise_mult": 0.4, "body_scale": 0.5, "move_speed": 5.0, "telegraph_time": 0.12, "chain_chance": 0.6, "armor_tier_offset": -9, "loot_quality": 0.0},
	"smuggler": {"display_name": "Smuggler", "color": Color(0.45, 0.33, 0.25), "kit": K.DAGGER, "health_mult": 0.9, "move_speed": 3.8, "telegraph_time": 0.2, "chain_chance": 0.5, "armor_tier_offset": -1},
	"smuggler_chief": {"display_name": "Smuggler Chief", "color": Color(0.55, 0.30, 0.20), "kit": K.MACE_SHIELD, "health_mult": 4.0, "damage_mult": 1.2, "poise_mult": 2.5, "body_scale": 1.2, "knockback_resistance": 0.5, "armor_tier_offset": 0, "loot_quality": 2.5},
	"barrow_wight": {"display_name": "Barrow Wight", "color": Color(0.55, 0.60, 0.66), "kit": K.SWORD, "health_mult": 1.1, "armor_tier_offset": 0, "telegraph_time": 0.35},
	"wight_lord": {"display_name": "Wight Lord", "color": Color(0.40, 0.50, 0.70), "kit": K.BATTLEAXE, "health_mult": 5.0, "damage_mult": 1.3, "poise_mult": 3.0, "body_scale": 1.4, "move_speed": 3.0, "telegraph_time": 0.5, "heavy_chance": 0.35, "knockback_resistance": 0.6, "armor_tier_offset": 1, "loot_quality": 2.5},
	"deep_crawler": {"display_name": "Deep Crawler", "color": Color(0.25, 0.32, 0.22), "kit": K.UNARMED, "health_mult": 0.9, "poise_mult": 0.8, "body_scale": 0.9, "move_speed": 4.5, "telegraph_time": 0.18, "chain_chance": 0.5, "armor_tier_offset": -9, "loot_quality": 0.0},
	"crawler_queen": {"display_name": "Crawler Queen", "color": Color(0.30, 0.40, 0.25), "kit": K.UNARMED, "health_mult": 6.0, "damage_mult": 1.5, "poise_mult": 3.0, "body_scale": 1.6, "move_speed": 3.4, "telegraph_time": 0.5, "heavy_chance": 0.4, "knockback_resistance": 0.7, "armor_tier_offset": -9, "loot_quality": 0.0},
	"deserter": {"display_name": "Deserter", "color": Color(0.40, 0.38, 0.32), "kit": K.SPEAR, "health_mult": 1.1, "armor_tier_offset": 0},
	"deserter_captain": {"display_name": "Deserter Captain", "color": Color(0.50, 0.42, 0.30), "kit": K.AXE_SHIELD, "health_mult": 5.0, "damage_mult": 1.2, "poise_mult": 2.8, "body_scale": 1.25, "knockback_resistance": 0.5, "armor_tier_offset": 1, "loot_quality": 2.5},
	"ice_wraith": {"display_name": "Ice Wraith", "color": Color(0.78, 0.88, 1.0), "kit": K.UNARMED, "health_mult": 1.0, "body_scale": 0.9, "move_speed": 4.2, "telegraph_time": 0.2, "chain_chance": 0.5, "armor_tier_offset": -9, "loot_quality": 0.0},
	"frost_giant": {"display_name": "Frost Giant", "color": Color(0.70, 0.80, 0.92), "kit": K.UNARMED, "health_mult": 7.0, "damage_mult": 1.6, "poise_mult": 3.5, "body_scale": 1.9, "move_speed": 2.9, "telegraph_time": 0.6, "heavy_chance": 0.45, "knockback_resistance": 0.8, "armor_tier_offset": -9, "loot_quality": 0.0},
	"fire_spirit": {"display_name": "Fire Spirit", "color": Color(1.0, 0.50, 0.15), "kit": K.UNARMED, "health_mult": 0.9, "body_scale": 0.85, "move_speed": 4.3, "telegraph_time": 0.18, "chain_chance": 0.5, "armor_tier_offset": -9, "loot_quality": 0.0},
	"ash_cultist": {"display_name": "Ash Cultist", "color": Color(0.25, 0.20, 0.20), "kit": K.MACE, "health_mult": 1.1, "armor_tier_offset": -1},
	"ashen_priest": {"display_name": "Ashen Priest", "color": Color(0.35, 0.15, 0.12), "kit": K.BATTLEAXE, "health_mult": 5.5, "damage_mult": 1.4, "poise_mult": 3.0, "body_scale": 1.35, "knockback_resistance": 0.6, "armor_tier_offset": 1, "loot_quality": 2.5},
	"vault_sentinel": {"display_name": "Vault Sentinel", "color": Color(0.70, 0.55, 0.30), "kit": K.MACE_SHIELD, "health_mult": 1.5, "poise_mult": 1.6, "move_speed": 2.8, "knockback_resistance": 0.4, "armor_tier_offset": 1},
	"vault_guardian": {"display_name": "Vault Guardian", "color": Color(0.80, 0.62, 0.30), "kit": K.WARHAMMER, "health_mult": 6.5, "damage_mult": 1.5, "poise_mult": 3.5, "body_scale": 1.6, "move_speed": 2.7, "telegraph_time": 0.55, "heavy_chance": 0.4, "knockback_resistance": 0.8, "armor_tier_offset": 1, "loot_quality": 3.0},
}

## table -> [[members, weight, count min, count max, min level]]
const TABLES := {
	"dungeon_sewers": [[["giant_rat"], 3, 2, 4, 1], [["smuggler"], 3, 1, 3, 1], [["cutthroat"], 1, 1, 2, 4]],
	"dungeon_mine": [[["deep_crawler"], 4, 1, 3, 1], [["bandit"], 2, 1, 2, 1], [["cave_dweller"], 1, 1, 2, 1]],
	"dungeon_barrow": [[["barrow_wight"], 4, 1, 3, 1], [["skeleton"], 2, 2, 3, 1], [["skeleton_knight"], 1, 1, 1, 10]],
	"dungeon_fort": [[["deserter"], 3, 2, 3, 1], [["bandit_thug"], 2, 1, 2, 1], [["bandit_brute"], 1, 1, 1, 8], [["deserter", "deserter"], 1, 1, 1, 20]],
	"dungeon_ice": [[["ice_wraith"], 4, 1, 3, 1], [["frost_bear"], 1, 1, 1, 1], [["wolf"], 1, 2, 3, 1]],
	"dungeon_ashen": [[["fire_spirit"], 3, 1, 3, 1], [["ash_cultist"], 3, 1, 3, 1]],
	"dungeon_vault": [[["vault_sentinel"], 4, 1, 2, 1], [["skeleton_knight"], 2, 1, 2, 1]],
}

## dungeon -> settings. "entrance": [display name, map color, cave shape?, entrance color, footprint], "biomes": {biome: [count min, count max] per km2}
const DUNGEONS := {
	"sewers": {"display_name": "Old Sewers", "theme": "sewer", "table": "dungeon_sewers", "boss": "smuggler_chief", "min_rooms": 5, "max_rooms": 8, "room_size": 12.0, "ceiling_height": 3.6, "level_offset": 0, "rooms_per_10_levels": 1.0,
		"wall_color": Color(0.30, 0.32, 0.26), "floor_color": Color(0.20, 0.22, 0.18), "light_color": Color(0.8, 0.9, 0.6), "light_energy": 1.2,
		"entrance": ["Sewer Grate", Color(0.5, 0.6, 0.4), false, Color(0.32, 0.34, 0.30), 12.0], "biomes": {"plains": [0.08, 0.15], "lakeland": [0.08, 0.15], "coast": [0.1, 0.2], "swamp": [0.05, 0.1]}},
	"abandoned_mine": {"display_name": "Abandoned Mine", "theme": "mine", "table": "dungeon_mine", "boss": "crawler_queen", "min_rooms": 6, "max_rooms": 10, "room_size": 14.0, "ceiling_height": 4.5, "level_offset": 0,
		"wall_color": Color(0.35, 0.30, 0.25), "floor_color": Color(0.25, 0.22, 0.18), "light_color": Color(1.0, 0.75, 0.45), "light_energy": 1.5,
		"entrance": ["Mine Entrance", Color(0.75, 0.6, 0.35), true, Color(0.40, 0.33, 0.26), 14.0], "biomes": {"highlands": [0.15, 0.3], "badlands": [0.2, 0.35], "snow_mountains": [0.1, 0.2]}},
	"barrow": {"display_name": "Ancient Barrow", "theme": "barrow", "table": "dungeon_barrow", "boss": "wight_lord", "min_rooms": 7, "max_rooms": 11, "room_size": 13.0, "ceiling_height": 4.2, "level_offset": 3,
		"wall_color": Color(0.33, 0.33, 0.36), "floor_color": Color(0.22, 0.22, 0.24), "light_color": Color(0.6, 0.8, 1.0), "light_energy": 1.2,
		"entrance": ["Barrow Entrance", Color(0.6, 0.65, 0.9), false, Color(0.40, 0.40, 0.44), 16.0], "biomes": {"plains": [0.05, 0.1], "tundra": [0.15, 0.3], "snow_mountains": [0.1, 0.2], "highlands": [0.08, 0.15]}},
	"fort_ruin": {"display_name": "Ruined Fort", "theme": "fort", "table": "dungeon_fort", "boss": "deserter_captain", "min_rooms": 7, "max_rooms": 11, "room_size": 16.0, "ceiling_height": 5.0, "level_offset": 2,
		"wall_color": Color(0.45, 0.43, 0.40), "floor_color": Color(0.30, 0.29, 0.27), "light_color": Color(1.0, 0.7, 0.4), "light_energy": 1.6,
		"entrance": ["Fort Gate", Color(0.85, 0.5, 0.3), false, Color(0.48, 0.46, 0.42), 18.0], "biomes": {"forest": [0.08, 0.15], "desert": [0.08, 0.15], "highlands": [0.1, 0.18], "deadlands": [0.12, 0.2], "badlands": [0.08, 0.15]}},
	"ice_cavern": {"display_name": "Ice Cavern", "theme": "ice", "table": "dungeon_ice", "boss": "frost_giant", "min_rooms": 7, "max_rooms": 11, "room_size": 15.0, "ceiling_height": 5.5, "level_offset": 0,
		"wall_color": Color(0.70, 0.80, 0.90), "floor_color": Color(0.80, 0.86, 0.92), "light_color": Color(0.6, 0.8, 1.0), "light_energy": 1.0,
		"entrance": ["Ice Cave", Color(0.7, 0.9, 1.0), true, Color(0.75, 0.85, 0.95), 14.0], "biomes": {"frozen_crown": [0.2, 0.35], "tundra": [0.1, 0.2]}},
	"ashen_temple": {"display_name": "Ashen Temple", "theme": "ashen", "table": "dungeon_ashen", "boss": "ashen_priest", "min_rooms": 8, "max_rooms": 12, "room_size": 15.0, "ceiling_height": 6.0, "level_offset": 2,
		"wall_color": Color(0.20, 0.17, 0.16), "floor_color": Color(0.15, 0.12, 0.11), "light_color": Color(1.0, 0.45, 0.2), "light_energy": 1.6,
		"entrance": ["Temple Steps", Color(1.0, 0.4, 0.2), false, Color(0.22, 0.18, 0.17), 18.0], "biomes": {"ashlands": [0.25, 0.4]}},
	"sunken_vault": {"display_name": "Sunken Vault", "theme": "vault", "table": "dungeon_vault", "boss": "vault_guardian", "min_rooms": 8, "max_rooms": 12, "room_size": 16.0, "ceiling_height": 6.0, "level_offset": 6,
		"wall_color": Color(0.42, 0.40, 0.30), "floor_color": Color(0.30, 0.28, 0.22), "light_color": Color(1.0, 0.85, 0.5), "light_energy": 1.3,
		"entrance": ["Vault Door", Color(1.0, 0.85, 0.3), false, Color(0.55, 0.50, 0.35), 16.0], "biomes": {"coast": [0.1, 0.2], "desert": [0.08, 0.15], "deadlands": [0.1, 0.2]}},
}


func _initialize() -> void:
	for key in ENEMIES:
		var e := _load_or_new(R + "Enemies/%s.tres" % key, EnemyData) as EnemyData
		e.id = StringName(key)
		var spec: Dictionary = ENEMIES[key]
		for f in spec:
			e.set(f, spec[f])
		e.talk_name = e.display_name
		ResourceSaver.save(e, R + "Enemies/%s.tres" % key)
	for key in TABLES:
		var t := SpawnTable.new()
		for row: Array in TABLES[key]:
			var se := SpawnEntry.new()
			var members: Array[EnemyData] = []
			for m: String in row[0]:
				members.append(load(R + "Enemies/%s.tres" % m) as EnemyData)
			se.members = members
			se.weight = row[1]
			se.count_min = row[2]
			se.count_max = row[3]
			se.min_level = row[4]
			t.entries.append(se)
		ResourceSaver.save(t, R + "Spawns/%s.tres" % key)
	for key in DUNGEONS:
		var spec: Dictionary = DUNGEONS[key]
		var d := _load_or_new(R + "World/Dungeons/%s.tres" % key, DungeonData) as DungeonData
		d.id = StringName(key)
		for f in spec:
			if f in ["table", "boss", "entrance", "biomes"]:
				continue
			d.set(f, spec[f])
		d.spawn_table = load(R + "Spawns/%s.tres" % spec["table"]) as SpawnTable
		d.boss = load(R + "Enemies/%s.tres" % spec["boss"]) as EnemyData
		d.enemies_per_room_min = 0
		d.enemies_per_room_max = 1
		d.chests_min = 1
		d.chests_max = 3
		ResourceSaver.save(d, R + "World/Dungeons/%s.tres" % key)
		var ent: Array = spec["entrance"]
		var poi_path := R + "World/POIs/%s_entrance.tres" % key
		var p := _load_or_new(poi_path, DungeonEntrancePOIData) as DungeonEntrancePOIData
		p.id = StringName("%s_entrance" % key)
		p.display_name = ent[0]
		p.map_color = ent[1]
		p.shape = DungeonEntrancePOIData.Shape.CAVE if ent[2] else DungeonEntrancePOIData.Shape.DOORWAY
		p.color = ent[3]
		p.footprint_radius = ent[4]
		p.flatten_radius = ent[4] * 0.5
		p.max_slope_deg = 14.0
		p.dungeon = load(R + "World/Dungeons/%s.tres" % key) as DungeonData
		p.enter_name = spec["display_name"]
		ResourceSaver.save(p, poi_path)
		for biome_key: String in spec["biomes"]:
			_hook(biome_key, load(poi_path) as POIData, spec["biomes"][biome_key])
	# the two old dungeon types get their furnishing themes
	for pair in [["dark_cave", "cave"], ["crypt", "crypt"]]:
		var d := load(R + "World/Dungeons/%s.tres" % pair[0]) as DungeonData
		d.theme = pair[1]
		ResourceSaver.save(d)
	print("build_dungeons: %d enemies, %d tables, %d dungeon types" % [ENEMIES.size(), TABLES.size(), DUNGEONS.size()])
	quit()


func _load_or_new(path: String, type: Variant) -> Resource:
	if ResourceLoader.exists(path):
		var r := load(path)
		if r != null:
			return r
	return type.new()


# Adds a rule for this entrance to a biome, once
func _hook(biome_key: String, poi: POIData, counts: Array) -> void:
	var path := R + "World/%s.tres" % biome_key
	var b := load(path) as BiomeData
	if b == null:
		return
	for rule in b.poi_rules:
		if rule != null and rule.poi != null and rule.poi.id == poi.id:
			return
	var r := POIRule.new()
	r.poi = poi
	r.count_mode = POIRule.CountMode.PER_SQUARE_KM
	r.count_min = counts[0]
	r.count_max = counts[1]
	r.extra_spacing = 80
	r.border_margin = 80
	var rules := b.poi_rules.duplicate()
	rules.append(r)
	b.poi_rules = rules
	ResourceSaver.save(b)
