class_name CraftedItems
extends RefCounted
## Items made while playing: brewed potions and poisons, improved (tempered) weapons and armor,
## and enchanted gear. Each one is written down in WorldState ("crafted/<id>"), so it is saved with
## the game and rebuilt on load; its save path is "crafted://<id>" (see SaveUtil).
##
## The same potion brewed twice gets the same id, so potions stack. Every piece of gear gets its
## own id (an enchanted weapon keeps its own charge).

const PREFIX := "crafted://"
const QUALITY_NAMES: Array[String] = ["", "Fine", "Superior", "Exquisite", "Flawless", "Epic", "Legendary"]
## Per quality level: weapon damage +10%, armor +8% (+1)
const WEAPON_PER_QUALITY := 0.1
const ARMOR_PER_QUALITY := 0.08

static var _cache: Dictionary = {}


static func is_path(path: String) -> bool:
	return path.begins_with(PREFIX)


static func from_path(path: String) -> ItemData:
	var id := path.trim_prefix(PREFIX)
	if _cache.has(id):
		return _cache[id]
	var rec := WorldState.get_record("crafted/" + id)
	if rec.is_empty():
		return null
	return _build(id, rec)


## Forgets the built items (a new game or a load: WorldState was replaced)
static func clear_cache() -> void:
	_cache.clear()


# ---------------------------------------------------------------- making

## A potion (or poison) from alchemy. effects: [{"id", "mag", "dur"}]
static func potion(effects: Array, poison: bool) -> ItemData:
	var list: Array = []
	for e in effects:
		list.append({"id": String(e["id"]), "mag": snappedf(float(e["mag"]), 1.0), "dur": snappedf(float(e.get("dur", 0.0)), 1.0)})
	var rec := {"kind": "potion", "effects": list, "poison": poison}
	var id := "p%d" % (JSON.stringify(rec).hash() & 0x7FFFFFFF)
	if not WorldState.has_record("crafted/" + id):
		WorldState.set_record("crafted/" + id, rec)
	return from_path(PREFIX + id)


## A copy of `base` (a weapon, armor, clothing or jewelry) at a quality and / or with an
## enchantment. Always a new, separate item.
static func gear(base: ItemData, quality: int, enchant: Array = [], charge: float = 0.0, custom_name: String = "") -> ItemData:
	var root := base_of(base)
	var list: Array = []
	for e in enchant:
		list.append({"id": String(e["id"]), "mag": snappedf(float(e["mag"]), 1.0), "dur": snappedf(float(e.get("dur", 0.0)), 1.0)})
	var rec := {"kind": "gear", "base": root.resource_path, "quality": clampi(quality, 0, 6), "enchant": list,
		"charge": charge, "max_charge": charge, "name": custom_name}
	var id := "g%d_%d" % [Time.get_ticks_usec() & 0xFFFFFF, randi() & 0xFFFF]
	WorldState.set_record("crafted/" + id, rec)
	return from_path(PREFIX + id)


## The plain item a crafted one was made from (itself for an ordinary item)
static func base_of(item: ItemData) -> ItemData:
	if item != null and item.has_meta("crafted_base"):
		var b: Variant = load(String(item.get_meta("crafted_base")))
		if b is ItemData:
			return b
	return item


static func record_of(item: ItemData) -> Dictionary:
	if item == null or not item.has_meta("crafted_id"):
		return {}
	return WorldState.get_record("crafted/" + String(item.get_meta("crafted_id")))


static func is_crafted(item: ItemData) -> bool:
	return item != null and item.has_meta("crafted_id")


# ---------------------------------------------------------------- weapon charge

static func get_charge(item: ItemData) -> float:
	return float(record_of(item).get("charge", 0.0))


static func get_max_charge(item: ItemData) -> float:
	return float(record_of(item).get("max_charge", 0.0))


static func set_charge(item: ItemData, value: float) -> void:
	if not is_crafted(item):
		return
	var key := "crafted/" + String(item.get_meta("crafted_id"))
	var rec := WorldState.get_record(key).duplicate()
	rec["charge"] = clampf(value, 0.0, float(rec.get("max_charge", 0.0)))
	WorldState.set_record(key, rec)


# ---------------------------------------------------------------- building the ItemData

static func _build(id: String, rec: Dictionary) -> ItemData:
	var item: ItemData = null
	match String(rec.get("kind", "")):
		"potion":
			item = _build_potion(rec)
		"gear":
			item = _build_gear(rec)
	if item == null:
		return null
	item.id = StringName("crafted_" + id)
	item.set_meta("crafted_id", id)
	item.set_meta("save_path", PREFIX + id)
	_cache[id] = item
	return item


static func _effects_of(rec: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in rec.get(key, []):
		if MagicEffects.has(StringName(e.get("id", ""))):
			out.append({"id": StringName(e["id"]), "mag": float(e.get("mag", 0.0)), "dur": float(e.get("dur", 0.0))})
	return out


static func _build_potion(rec: Dictionary) -> ItemData:
	var item := ItemData.new()
	var effects := _effects_of(rec, "effects")
	if effects.is_empty():
		return null
	var poison := bool(rec.get("poison", false))
	item.item_type = ItemData.ItemType.CONSUMABLE
	item.magic_effects = effects
	item.is_poison = poison
	item.stackable = true
	item.max_stack = 99
	item.weight = 0.5
	item.use_verb = "Drink"
	item.effect_group = "potion"
	item.effect_duration = 1.0
	item.loot_tags = PackedStringArray(["alchemy"])
	var main := effects[0]
	var strength := ""
	var mag := float(main["mag"])
	if MagicEffects.get_def(main["id"]).get("mag", true):
		strength = "Weak " if mag < 15.0 else ("" if mag < 40.0 else ("Strong " if mag < 80.0 else "Grand "))
	item.display_name = "%s%s of %s" % [strength, "Poison" if poison else "Potion", MagicEffects.display_name(main["id"])]
	if effects.size() > 1:
		item.display_name += " (+%d)" % (effects.size() - 1)
	var v := 0.0
	for e in effects:
		v += SpellData.effect_cost(e) * 1.6
	item.value = maxi(roundi(v), 5)
	item.description = "Brewed by your own hand." if not poison else "A brewed poison. Apply it to your weapon: the next hits carry it."
	return item


static func _build_gear(rec: Dictionary) -> ItemData:
	var path := String(rec.get("base", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var base := load(path) as ItemData
	if base == null:
		return null
	var item := base.duplicate() as ItemData
	item.stat_modifiers = base.stat_modifiers.duplicate()
	item.set_meta("crafted_base", path)
	var q := clampi(int(rec.get("quality", 0)), 0, 6)
	item.quality = q
	if q > 0:
		if item.item_type == ItemData.ItemType.WEAPON:
			item.weapon_damage = snappedf(base.weapon_damage * (1.0 + WEAPON_PER_QUALITY * q), 0.1)
		if item.stat_modifiers.has("armor"):
			item.stat_modifiers["armor"] = snappedf(float(base.stat_modifiers["armor"]) * (1.0 + ARMOR_PER_QUALITY * q) + float(q), 0.1)
	var ench := _effects_of(rec, "enchant")
	item.enchant_effects = ench
	item.enchant_charge = float(rec.get("max_charge", 0.0))
	var worn := item.item_type != ItemData.ItemType.WEAPON
	if worn:
		# Worn gear: the enchantment is simply always on (Stats modifiers while equipped)
		for e in ench:
			var d := MagicEffects.get_def(e["id"])
			var stat := String(d.get("stat", ""))
			if stat != "":
				item.stat_modifiers[stat] = float(item.stat_modifiers.get(stat, 0.0)) + float(e["mag"]) * float(d["per"])
			elif e["id"] == &"muffle":
				item.stat_modifiers["noise_mult"] = float(item.stat_modifiers.get("noise_mult", 0.0)) - 0.6
			elif e["id"] == &"night_eye":
				item.stat_modifiers["night_eye"] = 1.0
	var name := String(rec.get("name", ""))
	if name == "":
		name = base.display_name
		if q > 0:
			name = "%s %s" % [QUALITY_NAMES[q], name]
		if not ench.is_empty():
			name += " of " + ench_suffix(ench[0]["id"])
	item.display_name = name
	var v := float(base.value) * (1.0 + 0.2 * q)
	for e in ench:
		v += SpellData.effect_cost(e) * (4.0 if worn else 2.0) + 20.0
	item.value = roundi(v)
	return item


## "of Embers", "of Health"...
static func ench_suffix(id: StringName) -> String:
	const NAMES := {
		&"fire_damage": "Embers", &"frost_damage": "Frost", &"shock_damage": "Storms", &"poison_damage": "Venom",
		&"absorb_health": "the Leech", &"absorb_stamina": "Fatigue", &"absorb_magicka": "the Mage-Eater",
		&"damage_stamina": "Weariness", &"damage_magicka": "Silence", &"paralyze": "Stillness", &"soul_trap": "Souls",
		&"fear": "Dread", &"fortify_health": "Health", &"fortify_magicka": "Magicka", &"fortify_stamina": "Stamina",
		&"fortify_strength": "Strength", &"fortify_agility": "Agility", &"fortify_endurance": "Endurance",
		&"fortify_wisdom": "Wisdom", &"fortify_charisma": "Charm", &"fortify_attack": "Might",
		&"regenerate_health": "Renewal", &"regenerate_magicka": "the Arcane Well", &"regenerate_stamina": "Second Wind",
		&"resist_fire": "Fire Resistance", &"resist_frost": "Frost Resistance", &"resist_shock": "Shock Resistance",
		&"resist_poison": "Purity", &"resist_magic": "Warding", &"shield": "Protection", &"feather": "the Mule",
		&"haste": "Swiftness", &"jump": "Leaping", &"muffle": "Silent Steps", &"night_eye": "Night Sight",
		&"fortify_block": "Blocking", &"fortify_sneak": "the Assassin", &"fortify_speech": "Haggling",
		&"fortify_lockpicking": "Lockpicking", &"fortify_smithing": "the Smith", &"fortify_alchemy": "Alchemy",
		&"fortify_magic": "Sorcery", &"spell_absorption": "Absorption", &"reflect": "Reflection",
	}
	return NAMES.get(id, MagicEffects.display_name(id))
