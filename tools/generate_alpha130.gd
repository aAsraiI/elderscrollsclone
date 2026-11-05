extends SceneTree
## Alpha 1.30: fish, snares, the tent, the waterskin. Run with:
##   godot --headless --path . -s res://tools/generate_alpha130.gd

func _initialize() -> void:
	var made := 0
	var base := load("res://data/materials/raw_fish.tres") as ItemData
	for id in Fishing.FISH:
		var f: Array = Fishing.FISH[id]
		var it := base.duplicate() as ItemData
		it.id = StringName("fish_" + id)
		it.display_name = f[0]
		it.description = "A fresh %s. %s" % [String(f[0]).to_lower(), "Cook it at a pot or fire." if int(f[3]) < 2 else "A rare catch: collectors pay well for one."]
		it.value = int(f[4])
		it.weight = 0.4 if int(f[3]) < 3 else 2.0
		it.treasure = int(f[3]) >= 2
		it.loot_tags = PackedStringArray()
		it.resource_path = ""
		made += int(ResourceSaver.save(it, "res://data/materials/fish_%s.tres" % id) == OK)
	made += _misc("snare", "Snare", "Set it on the ground outside (E in the inventory). Come back in a few hours: small game may be caught in it. Trains Hunting.", 8, 0.5, true)
	made += _misc("camping_kit", "Camping Kit", "A tent, a bedroll and a fire pit. Pitch camp anywhere outside (E in the inventory): sleep, cook, and rest safe while a follower keeps watch. Take it down again with E.", 60, 8.0, false)
	made += _misc("waterskin", "Waterskin (empty)", "Fill it at any water (E in the inventory, facing water) and drink from it on the road.", 10, 0.5, true)
	made += _misc("waterskin_full", "Waterskin (full)", "Fresh water. Drink it (E in the inventory) to quench your thirst.", 12, 1.5, true)
	made += _misc("bandage", "Bandage", "Use it (E in the inventory) to stop bleeding and close a wound a little. Better with Medicine.", 6, 0.1, true)
	print("made %d items" % made)
	quit()


func _misc(id: String, name: String, desc: String, value: int, weight: float, stack: bool) -> int:
	var it := ItemData.new()
	it.id = StringName(id)
	it.display_name = name
	it.description = desc
	it.item_type = ItemData.ItemType.TOOL
	it.value = value
	it.weight = weight
	it.stackable = stack
	it.max_stack = 99 if stack else 1
	it.loot_tags = PackedStringArray(["shop", "camp"])
	return int(ResourceSaver.save(it, "res://data/misc/%s.tres" % id) == OK)
