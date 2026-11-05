extends SceneTree
## Alpha 1.29: disguises. Run with: godot --headless --path . -s res://tools/generate_alpha129.gd

## file -> [base, name, faction, description]
const DISGUISES := {
	"bandit_leathers": ["res://data/clothing/fine_tunic.tres", "Bandit Leathers", "bandits", "Patched leathers with a bandit band's mark. Worn, bandits take you for one of their own, until one looks closely."],
	"ash_cult_robes": ["res://data/clothing/plain_robe.tres", "Ash Cult Robes", "cultists", "Grey robes of the Ash Cult. Worn, cultists take you for one of their own, until one looks closely."],
	"smuggler_coat": ["res://data/clothing/fine_tunic.tres", "Smuggler's Coat", "smugglers", "A salt-stained coat with hidden pockets. Worn, smugglers take you for one of their own, until one looks closely."],
}


func _initialize() -> void:
	var made := 0
	for file in DISGUISES:
		var d: Array = DISGUISES[file]
		var it := (load(d[0]) as ItemData).duplicate() as ItemData
		it.id = StringName(file)
		it.display_name = d[1]
		it.disguise_faction = d[2]
		it.description = d[3]
		it.value = 60
		it.loot_tags = PackedStringArray(["thief"])
		it.resource_path = ""
		made += int(ResourceSaver.save(it, "res://data/clothing/%s.tres" % file) == OK)
	print("made %d items" % made)
	quit()
