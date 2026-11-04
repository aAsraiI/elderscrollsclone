extends "res://tools/generate_content.gd"
## Alpha 1.22: the gear and loot of levels 100-200 (the outer islands). Run with:
##   godot --headless --path . -s res://tools/generate_alpha122.gd
## Like generate_content.gd (which it builds on), an existing file is loaded and only these fields
## are set, so hand-set fields survive a rerun. It writes:
##   data/weapons, data/armor   every weapon, shield and armor piece in the four new tiers:
##                              Voidsteel 100, Sunsteel 125, Astral 150, Primordial 175
##   data/ranged                bows and arrows of those tiers
##   data/materials             the island ores and ingots (smelter and forge recipes use them)
##   data/jewelry               Voidstone (100) and Starstone (150) rings and amulets
##   data/consumables           supreme potions (100+) and the Elixir of the Ancients (150+)
##   data/artifacts             relics of the islands for the Antiquarian Society (100-190)
##   data/weapons, armor, jewelry  legendary uniques, "legendary" loot tag (rare in high chests)

const NEW_TIERS := [7, 8, 9, 10]

## key -> [name, value, ingot name, ingot value]
const METALS := {
	"void": ["Void Ore", 160, "voidsteel_ingot", "Voidsteel Ingot", 380],
	"sun": ["Sun Ore", 260, "sunsteel_ingot", "Sunsteel Ingot", 620],
	"astral": ["Astral Ore", 420, "astral_ingot", "Astral Ingot", 980],
	"primordial": ["Primordial Ore", 650, "primordial_ingot", "Primordial Ingot", 1500],
}

## [name, min level, tier, ring value, amounts per effect key]
const HIGH_GRADES := [
	["Voidstone", 100, 9, 3200, {"vigor": 90, "insight": 90, "endurance": 90, "mule": 120, "wind": 0.7}],
	["Starstone", 150, 11, 7000, {"vigor": 140, "insight": 140, "endurance": 140, "mule": 170, "wind": 0.9}],
]

const HIGH_POTIONS := {
	"supreme_health_potion": ["Supreme Health Potion", "Drink", "potion", 600.0, 1.0, 0.0, 0.0, 0.0, 700, 0.5, 100, ["alchemist", "vault"]],
	"supreme_magicka_potion": ["Supreme Magicka Potion", "Drink", "potion", 0.0, 1.0, 0.0, 0.0, 550.0, 700, 0.5, 100, ["alchemist", "vault", "library"]],
	"supreme_stamina_potion": ["Supreme Stamina Potion", "Drink", "potion", 0.0, 1.0, 0.0, 650.0, 0.0, 650, 0.5, 100, ["alchemist", "vault"]],
	"elixir_of_the_ancients": ["Elixir of the Ancients", "Drink", "potion", 450.0, 1.0, 0.0, 400.0, 400.0, 1800, 0.5, 150, ["vault"]],
}

const HIGH_ARTIFACTS := {
	"void_lantern": ["Lantern of the Void Isles", 100, 4200, 2.0, ["vault", "ruin"]],
	"sunken_scepter": ["Sunken Scepter of the Tide Kings", 110, 4800, 3.0, ["vault", "coast"]],
	"sunfire_chalice": ["Sunfire Chalice", 125, 5600, 1.5, ["vault", "desert", "temple"]],
	"cinder_crown": ["Cinder Crown of the Fire Lords", 140, 6800, 2.0, ["ashen", "vault"]],
	"astral_orrery": ["Astral Orrery", 150, 8200, 6.0, ["ruin", "vault"]],
	"frost_heart": ["Heart of the Frozen Throne", 165, 9600, 2.0, ["ice", "vault"]],
	"primordial_egg": ["Primordial Egg", 180, 12000, 5.0, ["vault", "ashen"]],
	"first_tablet": ["Tablet of the First Words", 190, 15000, 8.0, ["ruin", "vault", "library"]],
}

## Legendary uniques: key -> [name, base kind ("sword", ..., "shield", "bow", "cuirass", "helmet", "boots",
## "ring", "amulet"), tier index, heavy?, min level, description, stat_modifiers]
const LEGENDARIES := {
	"duskfang": ["Duskfang", "dagger", 7, true, 105, "A black dagger that finds the heart in the dark.", {"crit_chance": 0.08, "life_leech": 0.03}],
	"oathbreaker": ["Oathbreaker", "greatsword", 7, true, 110, "The greatsword of a king who broke every vow.", {"power_attack_pct": 0.30, "damage_pct": 0.05}],
	"tidecaller": ["Tidecaller", "spear", 8, true, 120, "A spear from the drowned halls; it moves like a wave.", {"attack_cost_mult": -0.15, "resist_shock": 0.20, "swim_speed_mult": 0.25}],
	"emberheart_maul": ["Emberheart Maul", "warhammer", 8, true, 130, "Its head still glows from the forge of the sun.", {"resist_fire": 0.30, "poise_bonus": 0.30}],
	"starfall": ["Starfall", "sword", 9, true, 150, "A sword cut from a falling star.", {"crit_mult": 0.50, "spell_power": 0.10}],
	"wyrmsbane": ["Wyrmsbane", "battleaxe", 9, true, 160, "Made to kill dragons, and good at it.", {"bane_beast": 0.50, "execute_bonus": 0.25}],
	"heartseeker": ["Heartseeker", "bow", 9, true, 155, "Its arrows never miss the heart.", {"bow_damage": 0.30, "crit_chance": 0.06}],
	"the_last_word": ["The Last Word", "mace", 10, true, 180, "Arguments end where it lands.", {"armor_pen": 0.30, "damage_pct": 0.15}],
	"worldsplitter": ["Worldsplitter", "greatsword", 10, true, 190, "The blade that cut the first sky.", {"damage_pct": 0.20, "crit_chance": 0.05, "power_attack_pct": 0.30}],
	"drowned_kings_mantle": ["Mantle of the Drowned King", "cuirass", 8, true, 125, "Plate of a king who lived beneath the sea.", {"water_breathing": 1.0, "max_health": 80.0}],
	"veil_of_the_unseen": ["Veil of the Unseen", "helmet", 9, false, 150, "Wearers are never seen again, unless they wish it.", {"noise_mult": -0.25, "sneak_attack_bonus": 0.50}],
	"endless_road_boots": ["Boots of the Endless Road", "boots", 7, false, 100, "Worn by a pilgrim who walked for a thousand years.", {"move_speed_mult": 0.10, "jump_mult": 0.25, "fall_resist": 0.30}],
	"aegis_of_dawn": ["Aegis of Dawn", "shield", 10, true, 175, "The first light of the world, held in steel.", {"block_strength": 0.15, "damage_reduction": 0.08}],
	"ring_of_the_archmagus": ["Ring of the Archmagus", "ring", 9, false, 140, "Worn by the first master of magic.", {"max_magicka": 150.0, "magicka_cost_mult": -0.15}],
	"amulet_of_ages": ["Amulet of Ages", "amulet", 10, false, 185, "It has seen every age of the world.", {"skill_xp_pct": 0.15, "health_regen": 2.0}],
}


func _initialize() -> void:
	for t in NEW_TIERS:
		for kind in WEAPONS:
			_weapon(kind, t)
		_shield(t)
		for piece in PIECES:
			_armor(piece, t, true)
			_armor(piece, t, false)
		_bow(t)
	for k in METALS:
		_metal(k)
	for g in HIGH_GRADES.size():
		for e in JEWEL_EFFECTS:
			_high_jewel(g, e, false)
			_high_jewel(g, e, true)
	for k in HIGH_POTIONS:
		_high_potion(k)
	for k in HIGH_ARTIFACTS:
		_high_artifact(k)
	for k in LEGENDARIES:
		_legendary(k)
	print("generate_alpha122: wrote %d item files" % _count)
	quit()


func _bow(t: int) -> void:
	var key: String = TIER_KEYS[t]
	var path := RES + "ranged/%s_bow.tres" % key
	var b := _open(path)
	b.id = StringName(key + "_bow")
	b.display_name = "%s Bow" % TIER_NAMES[t]
	b.description = "%s Hold left click to draw, let go to shoot. Right click zooms. Uses the best arrows you carry." % TIER_FLAVOR[t]
	b.item_type = ItemData.ItemType.WEAPON
	b.equip_slot = ItemData.EquipSlot.MAIN_HAND
	b.governing_skill = "archery"
	b.two_handed = true
	b.is_bow = true
	b.weapon_damage = snappedf(7.0 * DAMAGE_MULT[t], 0.5)
	b.draw_time = maxf(0.95 - 0.04 * t, 0.5)
	b.arrow_speed = 46.0 + 3.0 * t
	b.reach = 1.6
	b.attack_cooldown = 0.8
	b.poise_damage = 6.0
	b.weight = 6.0 + t * 0.5
	b.value = roundi(30.0 * VALUE_MULT[t])
	b.tier = t + 1
	b.min_level = TIER_MIN_LEVEL[t]
	b.animation_set = &"bow"
	b.loot_tags = PackedStringArray(["smithy", "hunter", "weapons"])
	_save(b, path)
	var apath := RES + "ranged/%s_arrow.tres" % key
	var a := _open(apath)
	a.id = StringName(key + "_arrow")
	a.display_name = "%s Arrow" % TIER_NAMES[t]
	a.description = "Shot from a bow. Better arrows hit harder."
	a.item_type = ItemData.ItemType.MISC
	a.is_arrow = true
	a.arrow_damage = snappedf(6.0 * DAMAGE_MULT[t], 0.5)
	a.stackable = true
	a.max_stack = 999
	a.weight = 0.0
	a.value = maxi(1, roundi(1.0 * VALUE_MULT[t]))
	a.tier = t + 1
	a.min_level = TIER_MIN_LEVEL[t]
	a.loot_tags = PackedStringArray(["smithy", "hunter", "weapons"])
	_save(a, apath)


func _metal(k: String) -> void:
	var m: Array = METALS[k]
	var opath := RES + "materials/%s_ore.tres" % k
	var o := _open(opath)
	o.id = StringName(k + "_ore")
	o.display_name = m[0]
	o.description = "Raw ore from the outer islands. Smelt it into ingots at a smelter."
	o.item_type = ItemData.ItemType.MATERIAL
	o.weight = 1.0
	o.value = m[1]
	o.stackable = true
	o.max_stack = 999
	o.loot_tags = PackedStringArray(["smithy", "mine"])
	_save(o, opath)
	var ipath := RES + "materials/%s.tres" % m[2]
	var i := _open(ipath)
	i.id = StringName(m[2])
	i.display_name = m[3]
	i.description = "Forge weapons and armor from it, or improve gear of its kind at a grindstone or workbench."
	i.item_type = ItemData.ItemType.MATERIAL
	i.weight = 1.0
	i.value = m[4]
	i.stackable = true
	i.max_stack = 999
	i.loot_tags = PackedStringArray(["smithy"])
	_save(i, ipath)


func _high_jewel(g: int, effect: String, amulet: bool) -> void:
	var grade: Array = HIGH_GRADES[g]
	var e: Array = JEWEL_EFFECTS[effect]
	var key := "%s_%s_%s" % [String(grade[0]).to_lower(), "amulet" if amulet else "ring", effect]
	var path := RES + "jewelry/" + key + ".tres"
	var it := _open(path)
	var amount: float = float(grade[4][effect]) * (1.5 if amulet else 1.0)
	it.id = StringName(key)
	it.display_name = "%s %s of %s" % [grade[0], "Amulet" if amulet else "Ring", e[0]]
	var shown := "+%d%%" % roundi(amount * 100.0) if e[1] == "stamina_regen_mult" else "+%d" % roundi(amount)
	it.description = "%s %s while worn." % [shown, String(e[1]).replace("_mult", "").replace("_", " ").replace("max ", "maximum ")]
	it.item_type = ItemData.ItemType.ARMOR
	it.equip_slot = ItemData.EquipSlot.AMULET if amulet else ItemData.EquipSlot.RING
	it.stat_modifiers = {e[1]: snappedf(amount, 0.01)}
	it.weight = 0.3 if amulet else 0.1
	it.value = roundi(float(grade[3]) * (1.4 if amulet else 1.0))
	it.tier = grade[2]
	it.min_level = grade[1]
	it.loot_tags = PackedStringArray(["jewelry", "jeweler", "vault"])
	_save(it, path)


func _high_potion(k: String) -> void:
	var c: Array = HIGH_POTIONS[k]
	var path := RES + "consumables/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.use_verb = c[1]
	it.effect_group = c[2]
	it.heal_amount = c[3]
	it.effect_duration = c[4]
	it.stamina_regen_bonus = c[5]
	it.restore_stamina = c[6]
	it.restore_magicka = c[7]
	it.value = c[8]
	it.weight = c[9]
	it.min_level = c[10]
	it.loot_tags = PackedStringArray(c[11])
	it.item_type = ItemData.ItemType.CONSUMABLE
	it.stackable = true
	it.max_stack = 99
	it.description = ""
	_save(it, path)


func _high_artifact(k: String) -> void:
	var c: Array = HIGH_ARTIFACTS[k]
	var path := RES + "artifacts/" + k + ".tres"
	var it := _open(path)
	it.id = StringName(k)
	it.display_name = c[0]
	it.description = "A relic of the outer islands. Ordinary merchants pay little for it; the Antiquarian Society pays its full worth."
	it.item_type = ItemData.ItemType.MISC
	it.min_level = c[1]
	it.value = c[2]
	it.weight = c[3]
	it.treasure = true
	it.artifact = true
	it.loot_tags = PackedStringArray(c[4])
	_save(it, path)


## The base item a legendary is made from (already written above)
func _base_for(kind: String, t: int, heavy: bool) -> ItemData:
	var p := ""
	match kind:
		"shield":
			p = RES + "weapons/%s_shield.tres" % TIER_KEYS[t]
		"bow":
			p = RES + "ranged/%s_bow.tres" % TIER_KEYS[t]
		"cuirass":
			p = RES + ("weapons/%s_chestplate.tres" % TIER_KEYS[t] if heavy else "armor/%s_cuirass.tres" % LIGHT_KEYS[t])
		"helmet", "boots", "gauntlets", "greaves":
			p = RES + "armor/%s_%s.tres" % [TIER_KEYS[t] if heavy else LIGHT_KEYS[t], kind]
		"ring", "amulet":
			p = RES + "jewelry/%s_%s_vigor.tres" % ["voidstone" if t < 10 else "starstone", kind]
		_:
			p = RES + "weapons/%s_%s.tres" % [TIER_KEYS[t], kind]
	return ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemData if ResourceLoader.exists(p) else null


func _legendary(k: String) -> void:
	var c: Array = LEGENDARIES[k]
	var kind: String = c[1]
	var base := _base_for(kind, c[2], c[3])
	if base == null:
		push_error("generate_alpha122: no base item for %s" % k)
		return
	var folder := "weapons"
	if kind in ["cuirass", "helmet", "boots", "gauntlets", "greaves"]:
		folder = "armor"
	elif kind in ["ring", "amulet"]:
		folder = "jewelry"
	var path := RES + "%s/legendary_%s.tres" % [folder, k]
	var it: ItemData = base.duplicate(true) as ItemData
	if ResourceLoader.exists(path):
		it = _open(path)
		# keep a rerun in step with the base item's numbers
		for prop in ["weapon_damage", "reach", "attack_style", "arc_degrees", "attack_cooldown", "attack_windup", "attack_active",
				"stamina_cost", "knockback", "poise_damage", "combo_length", "two_handed", "can_dual_wield", "armor_pierce",
				"heavy_charge_time", "heavy_windup", "heavy_damage_mult", "heavy_stamina_mult", "heavy_poise_mult", "heavy_reach_bonus",
				"secondary_action", "secondary_cooldown", "secondary_windup", "secondary_stamina_cost", "secondary_damage_mult",
				"secondary_radius", "block_reduction", "block_angle", "parry_window", "bash_damage", "bash_poise", "bash_stamina_cost",
				"is_bow", "draw_time", "arrow_speed", "item_type", "equip_slot", "governing_skill", "weight", "animation_set"]:
			if prop in base:
				it.set(prop, base.get(prop))
	it.id = StringName("legendary_" + k)
	it.display_name = c[0]
	it.description = "%s Legendary: one of a kind." % c[5]
	var mods: Dictionary = (base.stat_modifiers as Dictionary).duplicate()
	var extra: Dictionary = c[6]
	for s in extra:
		mods[s] = float(mods.get(s, 0.0)) + float(extra[s])
	if mods.has("armor"):
		mods["armor"] = snappedf(float(mods["armor"]) * 1.25, 0.1)
	it.stat_modifiers = mods
	if it.item_type == ItemData.ItemType.WEAPON:
		it.weapon_damage = snappedf(base.weapon_damage * 1.2, 0.01)
	it.tier = base.tier
	it.min_level = c[4]
	it.value = roundi(float(base.value) * 4.0)
	it.armor_set = &""
	it.loot_tags = PackedStringArray(["legendary", "vault"])
	_save(it, path)
