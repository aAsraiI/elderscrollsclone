extends SceneTree
## Stage 15's new creature families: 10 enemies, an encounter for each land that lacked its own
## creatures, and a few of them added to the dungeons. Safe to run again (it overwrites its own files
## and never adds the same encounter or dungeon entry twice).
##   godot --headless --path . -s res://tools/generate_stage15.gd

const E := "res://data/enemies/"
const ENC := "res://data/encounters/"
const SP := "res://data/spawns/"
const W := "res://data/world/"

## id -> [name, colour, scale, health, damage, poise, kit, speed, detection, knockback resist, telegraph, loot quality]
const ENEMIES := {
	"giant_spider": ["Giant Spider", Color(0.18, 0.16, 0.14), 1.2, 1.1, 1.1, 0.9, 0, 4.2, 15.0, 0.2, 0.35, 0.0],
	"bog_lurker": ["Bog Lurker", Color(0.3, 0.36, 0.22), 1.4, 1.8, 1.3, 1.8, 0, 3.0, 11.0, 0.35, 0.45, 0.0],
	"marsh_hag": ["Marsh Hag", Color(0.35, 0.42, 0.3), 0.95, 0.9, 1.0, 0.7, 3, 3.0, 16.0, 0.0, 0.3, 1.2],
	"drowned_sailor": ["Drowned Sailor", Color(0.4, 0.5, 0.52), 1.0, 1.2, 1.0, 1.0, 1, 2.8, 13.0, 0.1, 0.35, 0.8],
	"sea_raider": ["Sea Raider", Color(0.25, 0.3, 0.45), 1.0, 1.0, 1.0, 1.0, 12, 3.3, 15.0, 0.05, 0.3, 1.0],
	"sand_scorpion": ["Sand Scorpion", Color(0.75, 0.6, 0.35), 1.1, 1.3, 1.2, 1.4, 0, 3.8, 13.0, 0.3, 0.4, 0.0],
	"ash_hound": ["Ash Hound", Color(0.25, 0.2, 0.18), 1.0, 0.9, 1.1, 0.8, 0, 4.8, 17.0, 0.1, 0.3, 0.0],
	"harpy": ["Harpy", Color(0.55, 0.45, 0.35), 0.9, 0.8, 1.0, 0.6, 0, 5.0, 18.0, 0.0, 0.25, 0.0],
	"forest_troll": ["Forest Troll", Color(0.3, 0.38, 0.25), 1.6, 2.6, 1.5, 2.8, 0, 3.2, 13.0, 0.5, 0.55, 0.5],
	"grave_ghoul": ["Grave Ghoul", Color(0.5, 0.52, 0.48), 1.0, 1.0, 1.1, 0.9, 0, 4.0, 14.0, 0.1, 0.3, 0.3],
}

## encounter id -> [name, members, count min, max, min level, weight, night only, message, biomes]
const ENCOUNTERS := {
	"forest_spiders": ["Spider Nest", ["giant_spider"], 2, 4, 3, 2.0, false, "Something skitters in the undergrowth...", ["forest"]],
	"forest_troll": ["Forest Troll", ["forest_troll"], 1, 1, 10, 0.8, false, "A great shape shoulders through the trees.", ["forest"]],
	"swamp_lurkers": ["Bog Lurkers", ["bog_lurker"], 1, 2, 4, 2.0, false, "The bog heaves.", ["swamp"]],
	"swamp_hag": ["Marsh Hag's Coven", ["marsh_hag", "bog_lurker"], 2, 3, 8, 1.0, true, "Cackling drifts over the water.", ["swamp"]],
	"coast_drowned": ["The Drowned", ["drowned_sailor"], 2, 3, 5, 1.5, true, "Wet footsteps come up from the shore.", ["coast", "lakeland"]],
	"coast_raiders": ["Sea Raiders", ["sea_raider"], 2, 4, 3, 2.0, false, "A raiding party comes up from the beach!", ["coast"]],
	"desert_scorpions": ["Sand Scorpions", ["sand_scorpion"], 2, 3, 3, 2.0, false, "The sand shifts around you.", ["desert"]],
	"ash_hounds": ["Ash Hounds", ["ash_hound"], 2, 4, 6, 2.0, false, "Howls rise from the ash.", ["ashlands"]],
	"highland_harpies": ["Harpies", ["harpy"], 2, 3, 5, 1.6, false, "Shrieks from the crags above!", ["highlands", "badlands"]],
	"dead_ghouls": ["Grave Ghouls", ["grave_ghoul"], 2, 4, 6, 2.0, true, "Something is digging nearby.", ["deadlands"]],
}

## dungeon spawn table -> [enemy, weight, count min, count max]
const DUNGEONS := {
	"dungeon_cave": ["giant_spider", 1.5, 1, 3],
	"dungeon_crypt": ["grave_ghoul", 1.5, 1, 3],
	"dungeon_sewers": ["drowned_sailor", 1.0, 1, 2],
}


func _initialize() -> void:
	for id in ENEMIES:
		var v: Array = ENEMIES[id]
		var e := EnemyData.new()
		e.id = StringName(id)
		e.display_name = v[0]
		e.color = v[1]
		e.body_scale = v[2]
		e.health_mult = v[3]
		e.damage_mult = v[4]
		e.poise_mult = v[5]
		e.kit = v[6]
		e.move_speed = v[7]
		e.detection_range = v[8]
		e.knockback_resistance = v[9]
		e.telegraph_time = v[10]
		e.loot_quality = v[11]
		e.armor_tier_offset = -9 if v[11] <= 0.0 else -1
		e.talk_name = v[0]
		_save(e, E + id + ".tres")
	for id in ENCOUNTERS:
		var v: Array = ENCOUNTERS[id]
		var table := SpawnTable.new()
		var entry := SpawnEntry.new()
		for m in v[1]:
			entry.members.append(load(E + m + ".tres") as EnemyData)
		entry.count_min = v[2]
		entry.count_max = v[3]
		entry.min_level = v[4]
		table.entries.append(entry)
		_save(table, SP + "enc_" + id + ".tres")
		var enc := EncounterData.new()
		enc.id = StringName(id)
		enc.display_name = v[0]
		enc.table = load(SP + "enc_" + id + ".tres") as SpawnTable
		enc.weight = v[5]
		enc.aggro = true
		enc.night_only = v[6]
		enc.message = v[7]
		_save(enc, ENC + id + ".tres")
		var saved := load(ENC + id + ".tres") as EncounterData
		for biome in v[8]:
			var b := load(W + biome + ".tres") as BiomeData
			if b == null:
				continue
			var has := false
			for x in b.encounters:
				has = has or (x != null and x.get_key() == id)
			if not has:
				b.encounters.append(saved)
				_save(b, W + biome + ".tres")
	for t in DUNGEONS:
		var v: Array = DUNGEONS[t]
		var table := load(SP + t + ".tres") as SpawnTable
		var who := load(E + v[0] + ".tres") as EnemyData
		var has := false
		for x in table.entries:
			for m in x.members:
				has = has or (m != null and m.get_key() == v[0])
		if not has:
			var entry := SpawnEntry.new()
			entry.members.append(who)
			entry.weight = v[1]
			entry.count_min = v[2]
			entry.count_max = v[3]
			table.entries.append(entry)
			_save(table, SP + t + ".tres")
	_dragon()
	quit()


## The dragon: a rare world boss in its own lair (a ring of crags) in the high and burnt lands,
## sleeping on a hoard
func _dragon() -> void:
	var e := EnemyData.new()
	e.id = &"dragon"
	e.display_name = "Dragon"
	e.color = Color(0.32, 0.12, 0.09)
	e.body_scale = 2.5
	e.health_mult = 14.0
	e.damage_mult = 2.4
	e.poise_mult = 8.0
	e.kit = EnemyData.Kit.UNARMED
	e.move_speed = 4.4
	e.detection_range = 34.0
	e.knockback_resistance = 0.95
	e.telegraph_time = 0.6
	e.heavy_chance = 0.4
	e.loot_quality = 3.0
	e.armor_tier_offset = -9
	for v in [["res://data/materials/dragonbone_plate.tres", 2, 4], ["res://data/materials/dragonstone_ore.tres", 1, 3]]:
		var le := LootEntry.new()
		le.item = load(v[0]) as ItemData
		le.min_count = v[1]
		le.max_count = v[2]
		e.extra_loot.append(le)
	_save(e, E + "dragon.tres")
	var table := SpawnTable.new()
	var entry := SpawnEntry.new()
	entry.members.append(load(E + "dragon.tres") as EnemyData)
	table.entries.append(entry)
	_save(table, SP + "garrison_dragon.tres")
	var lair := SimplePOIData.new()
	lair.id = &"dragon_lair"
	lair.display_name = "Dragon's Lair"
	lair.map_color = Color(0.85, 0.15, 0.1)
	lair.shape = SimplePOIData.Shape.DRAGON_LAIR
	lair.color = Color(0.3, 0.28, 0.27)
	lair.footprint_radius = 26.0
	lair.flatten_radius = 19.0
	lair.max_slope_deg = 20.0
	lair.garrison = load(SP + "garrison_dragon.tres") as SpawnTable
	lair.garrison_groups_min = 1
	lair.garrison_groups_max = 1
	lair.garrison_radius = 4.0
	lair.garrison_level_offset = 6
	var hoard := POIContainer.new()
	hoard.display_name = "Dragon's Hoard"
	hoard.offset = Vector3(0.0, 0.0, 6.5)
	var gold := LootEntry.new()
	gold.item = load("res://data/consumables/gold.tres") as ItemData
	gold.min_count = 600
	gold.max_count = 1200
	hoard.loot.append(gold)
	for gem in ["res://data/materials/gold_ingot.tres", "res://data/materials/star_ore.tres"]:
		var le := LootEntry.new()
		le.item = load(gem) as ItemData
		le.min_count = 2
		le.max_count = 5
		le.chance = 0.8
		hoard.loot.append(le)
	lair.containers.append(hoard)
	_save(lair, W + "POIs/dragon_lair.tres")
	var saved := load(W + "POIs/dragon_lair.tres") as SimplePOIData
	for biome in ["highlands", "snow_mountains", "ashlands"]:
		var b := load(W + biome + ".tres") as BiomeData
		var has := false
		for r in b.poi_rules:
			has = has or (r != null and r.poi != null and r.poi.id == &"dragon_lair")
		if has:
			continue
		var rule := POIRule.new()
		rule.poi = saved
		rule.count_mode = POIRule.CountMode.PER_REGION
		rule.count_min = 0.3
		rule.count_max = 0.7
		rule.extra_spacing = 250.0
		rule.border_margin = 80.0
		b.poi_rules.append(rule)
		_save(b, W + biome + ".tres")


func _save(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	print("%s: %s" % [path, "ok" if err == OK else "error %d" % err])
