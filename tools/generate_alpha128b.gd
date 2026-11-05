extends SceneTree
## Alpha 1.28.5: the eight Patrons' artifacts. Run with:
##   godot --headless --path . -s res://tools/generate_alpha128b.gd

## file -> [base item, name, description, stat modifiers, extra damage x]
const ARTIFACTS := {
	"vael_emberheart": ["res://data/weapons/obsidian_sword.tres", "Emberheart", "Vael's own blade, warm as a coal. Your spells burn hotter.", {"spell_power": 0.15, "resist_fire": 0.5}, 1.3],
	"morrowgast_rotfang": ["res://data/weapons/ebon_dagger.tres", "Rotfang", "A dagger of the Lord of Rot. Every wound feeds you.", {"life_leech": 0.05, "resist_poison": 0.5}, 1.3],
	"ilsira_moonveil": ["res://data/armor/ebon_helmet.tres", "Moonveil Cowl", "Ilsira's veil. You are harder to see, and locks give way.", {"stealth": 15.0, "security_bonus": 0.2}, 1.0],
	"kharn_maul": ["res://data/weapons/dragonbone_warhammer.tres", "Maul of the Unbroken", "Kharn's maul. Every blow staggers.", {"poise_bonus": 0.35, "max_health": 40.0}, 1.25],
	"sythara_loom": ["res://data/jewelry/gemmed_amulet_insight.tres", "Loom of Sythara", "The Weaver's amulet: the threads of magic come easier.", {"max_magicka": 80.0, "magicka_cost_mult": -0.15}, 1.0],
	"dorun_heart": ["res://data/jewelry/gemmed_amulet_endurance.tres", "Heart of the Deep", "A stone from under the mountains. You carry more and mine better.", {"carry_capacity": 80.0, "mining_bonus": 0.3, "armor": 15.0}, 1.0],
	"choir_whisper": ["res://data/ranged/ebon_bow.tres", "Whisper of the Choir", "A bow that makes no sound. Shots from hiding strike deep.", {"sneak_attack_bonus": 0.5, "noise_mult": -0.2}, 1.2],
	"thornwood_band": ["res://data/jewelry/gemmed_amulet_vigor.tres", "Thornmother's Band", "Mother Thornwood's band of living root. Beasts fear you; wounds close.", {"health_regen": 1.5, "bane_beast": 0.25}, 1.0],
}


func _initialize() -> void:
	var made := 0
	for file in ARTIFACTS:
		var d: Array = ARTIFACTS[file]
		var base := load(d[0]) as ItemData
		if base == null:
			push_error("no base " + d[0])
			continue
		var it := base.duplicate() as ItemData
		it.id = StringName(file)
		it.display_name = d[1]
		it.description = d[2]
		var mods: Dictionary = (base.stat_modifiers as Dictionary).duplicate()
		for k in d[3]:
			mods[k] = float(mods.get(k, 0.0)) + float(d[3][k])
		it.stat_modifiers = mods
		it.weapon_damage = snappedf(base.weapon_damage * float(d[4]), 0.5)
		it.value = base.value * 4 + 2000
		it.artifact = false  # not a museum relic: the museum would take it
		it.loot_tags = PackedStringArray()
		it.resource_path = ""
		made += int(ResourceSaver.save(it, "res://data/artifacts/%s.tres" % file) == OK)
	print("made %d items" % made)
	quit()
