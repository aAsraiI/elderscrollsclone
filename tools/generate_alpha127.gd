extends SceneTree
## Alpha 1.27.1: crossbows, bolts and thrown weapons for every tier, made from that tier's bow
## and arrow so they keep pace. Run with:
##   godot --headless --path . -s res://tools/generate_alpha127.gd
## Writes data/ranged/<tier>_crossbow, <tier>_bolt, <tier>_throwing_knife, <tier>_throwing_axe and
## <tier>_javelin. Rerunning overwrites them.

const DIR := "res://data/ranged/"
const NAMES := ["Iron", "Steel", "Silver", "Obsidian", "Ebon", "Dragonbone", "Starforged", "Voidsteel", "Sunsteel", "Astral", "Primordial"]

## kind -> [name, damage x (bow + arrow), speed, cooldown, weight, value x arrow value, stack value floor, model, poise]
const THROWN := {
	"throwing_knife": ["Throwing Knife", 0.75, 34.0, 0.4, 0.5, 4, 2, &"dagger", 6.0],
	"throwing_axe": ["Throwing Axe", 1.0, 28.0, 0.7, 1.5, 8, 4, &"waraxe", 14.0],
	"javelin": ["Javelin", 1.3, 32.0, 0.95, 2.5, 12, 6, &"spear", 18.0],
}


func _initialize() -> void:
	var made := 0
	for t in LevelCurve.TIER_KEYS.size():
		var key: String = LevelCurve.TIER_KEYS[t]
		var bow := ItemCatalog.get_bow(t)
		var arrow := ItemCatalog.get_arrow(t)
		if bow == null or arrow == null:
			push_error("no bow or arrow for tier %d" % t)
			continue
		var name: String = NAMES[t]
		# ---- the crossbow: no draw, a full-power shot, then a slow reload. Pierces half of armour.
		var cb := bow.duplicate() as ItemData
		cb.id = StringName(key + "_crossbow")
		cb.display_name = name + " Crossbow"
		cb.description = "Left click shoots at full power; then it must be wound again. Bolts pierce half of any armour. Uses the best bolts you carry. Right click zooms."
		cb.is_crossbow = true
		cb.weapon_damage = snappedf(bow.weapon_damage * 1.35, 0.5)
		cb.draw_time = snappedf(bow.draw_time * 2.2, 0.01)  # the reload
		cb.arrow_speed = snappedf(bow.arrow_speed * 1.25, 0.5)
		cb.armor_pierce = 0.5
		cb.weight = snappedf(bow.weight * 1.4, 0.5)
		cb.value = int(bow.value * 1.3)
		made += _save(cb, key + "_crossbow")
		# ---- bolts
		var bolt := arrow.duplicate() as ItemData
		bolt.id = StringName(key + "_bolt")
		bolt.display_name = name + " Bolt"
		bolt.description = "Shot from a crossbow. Better bolts hit harder."
		bolt.is_bolt = true
		bolt.arrow_damage = snappedf(arrow.arrow_damage * 1.15, 0.5)
		bolt.value = maxi(arrow.value, 1) + 1
		made += _save(bolt, key + "_bolt")
		# ---- thrown weapons: the weapon is its own ammunition (equip the stack, each throw uses one)
		for kind in THROWN:
			var d: Array = THROWN[kind]
			var it := arrow.duplicate() as ItemData
			it.id = StringName(key + "_" + kind)
			it.display_name = "%s %s" % [name, d[0]]
			it.description = "Equip the stack: left click throws one. It can often be picked up again where it lands. Trains Archery."
			it.is_arrow = false
			it.arrow_damage = 0.0
			it.is_thrown = true
			it.item_type = ItemData.ItemType.WEAPON
			it.equip_slot = ItemData.EquipSlot.MAIN_HAND
			it.governing_skill = "archery"
			it.stackable = true
			it.max_stack = 99
			it.weapon_damage = snappedf((bow.weapon_damage + arrow.arrow_damage) * float(d[1]), 0.5)
			it.arrow_speed = float(d[2])
			it.attack_cooldown = float(d[3])
			it.weight = float(d[4])
			it.value = maxi(arrow.value * int(d[5]), int(d[6]))
			it.animation_set = d[7]
			it.poise_damage = float(d[8])
			it.two_handed = false
			made += _save(it, key + "_" + kind)
	print("made %d items" % made)
	quit()


func _save(item: ItemData, file: String) -> int:
	item.resource_path = ""
	var err := ResourceSaver.save(item, DIR + file + ".tres")
	if err != OK:
		push_error("could not save %s (%d)" % [file, err])
		return 0
	return 1
