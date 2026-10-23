class_name Alchemy
extends RefCounted
## Brewing at an alchemy lab, Morrowind / Skyrim style. Every ingredient hides four effects. Mix
## two or three: every effect at least two of them share goes into the potion. A mix whose
## strongest effect is harmful makes a poison instead (put it on your blade).
## You learn an ingredient's first effect by eating it, and every effect that shows up in a brew.
## Strength: the effect's base below x (1 + 1.5% per Alchemy level + Fortify Alchemy).

## The four effects of each ingredient (by item id). tools/generate_stage10.gd copies them into the
## item files too (ItemData.ingredient_effects), so a hand-made ingredient only needs those.
const INGREDIENTS := {
	"ash_salt": ["resist_fire", "restore_magicka", "fortify_magic", "weakness_frost"],
	"bear_claw": ["restore_stamina", "fortify_health", "fortify_attack", "fortify_strength"],
	"bloodmoss": ["restore_health", "regenerate_health", "weakness_poison", "fortify_stamina"],
	"blue_mountain_flower": ["restore_health", "fortify_wisdom", "restore_magicka", "resist_shock"],
	"bone_meal": ["damage_stamina", "resist_fire", "fortify_block", "regenerate_stamina"],
	"crawler_eye": ["night_eye", "detect_life", "poison_damage", "fortify_sneak"],
	"fire_salts": ["weakness_frost", "resist_fire", "restore_magicka", "fire_damage"],
	"frost_mirriam": ["resist_frost", "fortify_sneak", "frost_damage", "haste"],
	"glowcap": ["night_eye", "restore_magicka", "fortify_magicka", "regenerate_magicka"],
	"lavender": ["resist_magic", "fortify_stamina", "restore_health", "fortify_wisdom"],
	"nightshade": ["damage_health", "poison_damage", "fear", "invisibility"],
	"sandroot": ["resist_fire", "fortify_endurance", "restore_stamina", "feather"],
	"snowberries": ["resist_frost", "resist_shock", "restore_health", "fortify_magic"],
	"swamp_lily": ["cure_poison", "restore_health", "resist_poison", "slow"],
	"thistle": ["resist_frost", "restore_stamina", "shield", "fortify_endurance"],
	"troll_fat": ["regenerate_health", "fortify_health", "damage_magicka", "frenzy"],
	"venom_sac": ["poison_damage", "paralyze", "damage_stamina", "weakness_poison"],
	"void_salt": ["resist_shock", "damage_health", "fortify_magicka", "weakness_magic"],
	"wisp_dust": ["invisibility", "fortify_magicka", "resist_magic", "muffle"],
	"wolf_fang": ["fortify_attack", "damage_stamina", "haste", "fortify_agility"],
	"red_mountain_flower": ["restore_magicka", "fortify_magicka", "restore_health", "damage_stamina"],
	"juniper_berries": ["fortify_lockpicking", "regenerate_health", "weakness_shock", "resist_frost"],
	"cactus_flower": ["restore_stamina", "resist_fire", "fortify_agility", "feather"],
	"wild_garlic": ["resist_poison", "fortify_stamina", "cure_disease", "fortify_charisma"],
	"spider_egg": ["paralyze", "fear", "frenzy", "damage_magicka"],
	"river_scale": ["slow", "shield", "fortify_block", "weakness_magic"],
	"hawk_feather": ["fortify_strength", "regenerate_stamina", "fortify_lockpicking", "muffle"],
	"storm_crystal": ["fire_damage", "frost_damage", "weakness_shock", "regenerate_magicka"],
	"mandrake_root": ["detect_life", "cure_poison", "fortify_charisma", "cure_disease"],
}
## Base strength of each effect in a potion: [magnitude, duration]
const BASE := {
	&"restore_health": [30.0, 0.0], &"restore_stamina": [35.0, 0.0], &"restore_magicka": [35.0, 0.0],
	&"fire_damage": [18.0, 0.0], &"frost_damage": [18.0, 0.0], &"shock_damage": [18.0, 0.0],
	&"poison_damage": [4.0, 8.0], &"damage_health": [15.0, 0.0], &"damage_stamina": [30.0, 0.0], &"damage_magicka": [30.0, 0.0],
	&"paralyze": [0.0, 4.0], &"fear": [12.0, 20.0], &"frenzy": [12.0, 20.0], &"slow": [30.0, 15.0],
	&"invisibility": [0.0, 25.0], &"night_eye": [0.0, 60.0], &"muffle": [0.0, 60.0], &"detect_life": [50.0, 40.0],
	&"cure_poison": [0.0, 0.0],
}
const XP_BASE := 6.0


static func effects_of(item: ItemData) -> PackedStringArray:
	if item == null:
		return PackedStringArray()
	if not item.ingredient_effects.is_empty():
		return item.ingredient_effects
	return PackedStringArray(INGREDIENTS.get(String(item.id) if item.id != &"" else item.resource_path.get_file().get_basename(), []))


static func is_ingredient(item: ItemData) -> bool:
	return item != null and not effects_of(item).is_empty()


## The effects a mix would have (ids, strongest first)
static func shared_effects(items: Array) -> Array[StringName]:
	var count := {}
	for it in items:
		var seen := {}
		for e in effects_of(it):
			if not seen.has(e):
				seen[e] = true
				count[e] = int(count.get(e, 0)) + 1
	var out: Array[StringName] = []
	for e in count:
		if int(count[e]) >= 2:
			out.append(StringName(e))
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return SpellData.effect_cost(make_effect(a, 1.0)) > SpellData.effect_cost(make_effect(b, 1.0)))
	return out


static func make_effect(id: StringName, mult: float) -> Dictionary:
	var d := MagicEffects.get_def(id)
	var base: Array = BASE.get(id, [])
	if base.is_empty():
		if int(d.get("kind", 0)) == MagicEffects.Kind.BUFF:
			var per := absf(float(d.get("per", 1.0)))
			base = [15.0 if per >= 1.0 else 20.0, 60.0]
			if id == &"feather":
				base = [60.0, 120.0]
			elif id == &"shield":
				base = [20.0, 60.0]
		else:
			base = [15.0, 0.0]
	var mag := float(base[0]) * mult if d.get("mag", true) else 0.0
	var dur := float(base[1]) * (1.0 + (mult - 1.0) * 0.5) if float(base[1]) > 0.0 else 0.0
	return {"id": id, "mag": roundf(mag), "dur": roundf(dur)}


static func skill_mult(player: Node) -> float:
	var skills := player.get_node_or_null("Skills") as Skills
	var stats := player.get_node_or_null("Stats") as Stats
	var lvl := skills.get_level(&"alchemy") if skills != null else 1
	return 1.0 + float(lvl) * 0.015 + (stats.get_stat("alchemy_potency") if stats != null else 0.0)


## Brews one potion from 2-3 ingredients you carry. Returns the potion, or null if nothing shared.
static func brew(player: Node, items: Array) -> ItemData:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or items.size() < 2:
		return null
	for it in items:
		if not inv.has_item(it):
			return null
	var shared := shared_effects(items)
	var book := player.get_node_or_null("Spellbook") as Spellbook
	for it in items:
		inv.remove_item(it, 1)
	if shared.is_empty():
		return null  # the ingredients are wasted, like in the old games
	var mult := skill_mult(player)
	var effects: Array = []
	for id in shared:
		effects.append(make_effect(id, mult))
		if book != null:
			for it in items:
				var idx := effects_of(it).find(String(id))
				if idx >= 0:
					book.learn_ingredient_effect(it, idx)
	var poison := MagicEffects.is_harmful(shared[0])
	var potion := CraftedItems.potion(effects, poison)
	inv.add_item(potion, 1)
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_xp(&"alchemy", XP_BASE + float(potion.value) * 0.08)
	return potion


## Eating a raw ingredient: a weak dose of its first effect, and you learn it
static func eat(player: Node, item: ItemData) -> String:
	var inv := player.get_node_or_null("Inventory") as Inventory
	var list := effects_of(item)
	if inv == null or list.is_empty() or not inv.has_item(item):
		return ""
	inv.remove_item(item, 1)
	var id := StringName(list[0])
	var book := player.get_node_or_null("Spellbook") as Spellbook
	var learned := book != null and book.learn_ingredient_effect(item, 0)
	var m := ActiveMagic.of(player)
	if m != null:
		m.apply_list([make_effect(id, 0.25)], null, item.display_name, "potion")
	var skills := player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.add_xp(&"alchemy", 1.0)
	return ("You learn: %s" % MagicEffects.display_name(id)) if learned else ""
