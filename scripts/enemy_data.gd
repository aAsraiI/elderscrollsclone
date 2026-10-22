class_name EnemyData
extends Resource
## One kind of creature or NPC: a bandit, a wolf, a skeleton, a wandering merchant. It does NOT
## hold numbers like health: those come from the LEVEL it is spawned at (see LevelCurve), so one
## EnemyData works at every level. It holds what makes the kind different: what it wields, how
## tough or fast it is compared to an average enemy of its level, how it fights, what it says.
## Create in the editor: FileSystem > right-click > New Resource > EnemyData.
## Put it in a SpawnTable (garrisons, dungeons, random encounters) to use it.

## What it fights with. The weapon's tier comes from the level, not from here.
enum Kit { UNARMED, SWORD, SWORD_SHIELD, DAGGER, DAGGER_PAIR, GREATSWORD, WARHAMMER, WAR_AXE, MACE, SPEAR, BATTLEAXE, MACE_SHIELD, AXE_SHIELD }

@export var id: StringName
@export var display_name := "Bandit"
## HOSTILE attacks on sight. NEUTRAL wanders and talks, fights back if hit. FRIENDLY wanders, talks,
## runs if hit.
@export var disposition: Enemy.Disposition = Enemy.Disposition.HOSTILE
## Body color of the placeholder model. Friendly NPCs are blue and green by default, hostiles red and brown.
@export var color := Color(0.7, 0.2, 0.2)
@export_range(0.4, 2.5, 0.05) var body_scale := 1.0

@export_group("Compared to an average enemy of its level")
@export var health_mult := 1.0
@export var damage_mult := 1.0
@export var poise_mult := 1.0
## Scales the chance of extra drops (the weapon it wields is always lootable). 0 = nothing extra.
@export var loot_quality := 1.0
## -1 = carries gear one tier worse than the level's tier, +1 = one better
@export var weapon_tier_offset := 0
## Armor tier relative to the level's tier. -1 = one tier worse. -9 = wears no armor.
@export var armor_tier_offset := -1

@export_group("Gear")
@export var kit: Kit = Kit.SWORD
## A fixed weapon instead of the level's tier (a legendary sword on a boss)
@export var weapon_override: ItemData
## Extra things it may drop, on top of the level's gear drops
@export var extra_loot: Array[LootEntry] = []

@export_group("Behavior")
@export var move_speed := 3.2
@export var detection_range := 14.0
## Extra windup on its swings (readable tell). Smaller = harder to react to.
@export var telegraph_time := 0.3
@export_range(0.0, 1.0, 0.05) var heavy_chance := 0.2
@export_range(0.0, 1.0, 0.05) var chain_chance := 0.3
@export var attack_pause_min := 0.3
@export var attack_pause_max := 1.0
@export_range(0.0, 1.0, 0.05) var knockback_resistance := 0.0
## 0 = stands still until it sees you; bigger = strolls around within this many meters
@export var wander_radius := 0.0

@export_group("Talk (neutral and friendly NPCs)")
@export var talk_name := ""
@export var talk_lines: PackedStringArray = []


func get_key() -> String:
	if id != &"":
		return String(id)
	if resource_path != "":
		return resource_path.get_file().get_basename()
	return display_name


## Configures a fresh Enemy (not yet in the tree) for this kind at this level.
func apply(e: Enemy, level: int, rng: RandomNumberGenerator) -> void:
	level = maxi(level, 1)
	e.level = level
	e.display_name = display_name
	e.disposition = disposition
	e.placeholder_color = color
	e.body_scale = body_scale
	e.max_health = LevelCurve.enemy_health(level) * health_mult
	e.max_poise = LevelCurve.enemy_poise(level) * poise_mult
	e.damage_mult = LevelCurve.enemy_damage_mult(level) * damage_mult
	e.move_speed = move_speed
	e.detection_range = detection_range
	e.telegraph_time = telegraph_time
	e.heavy_chance = heavy_chance
	e.chain_chance = chain_chance
	e.attack_pause_min = attack_pause_min
	e.attack_pause_max = attack_pause_max
	e.knockback_resistance = knockback_resistance
	e.wander_radius = wander_radius
	e.talk_name = talk_name if talk_name != "" else display_name
	e.talk_lines = talk_lines
	e.base_damage = 3.0

	var tier := LevelCurve.tier_for_level(level)
	if rng.randf() < 0.25:
		tier -= 1  # a little variety: some carry older gear
	var weapon_tier := clampi(tier + weapon_tier_offset, 0, LevelCurve.MAX_TIER)
	match kit:
		Kit.UNARMED:
			e.base_damage = LevelCurve.beast_damage(level)  # no weapon to add damage
		Kit.SWORD:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, weapon_tier)
		Kit.SWORD_SHIELD:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, weapon_tier)
			e.starting_off_hand = ItemCatalog.get_shield(weapon_tier)
		Kit.DAGGER:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.DAGGER, weapon_tier)
		Kit.DAGGER_PAIR:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.DAGGER, weapon_tier)
			e.starting_off_hand = e.starting_weapon
		Kit.GREATSWORD:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.GREATSWORD, weapon_tier)
		Kit.WARHAMMER:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.WARHAMMER, weapon_tier)
		Kit.WAR_AXE:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.WAR_AXE, weapon_tier)
		Kit.MACE:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.MACE, weapon_tier)
		Kit.SPEAR:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.SPEAR, weapon_tier)
		Kit.BATTLEAXE:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.BATTLEAXE, weapon_tier)
		Kit.MACE_SHIELD:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.MACE, weapon_tier)
			e.starting_off_hand = ItemCatalog.get_shield(weapon_tier)
		Kit.AXE_SHIELD:
			e.starting_weapon = ItemCatalog.get_weapon(ItemCatalog.Weapon.WAR_AXE, weapon_tier)
			e.starting_off_hand = ItemCatalog.get_shield(weapon_tier)
	if weapon_override != null:
		e.starting_weapon = weapon_override

	# Armor: the cuirass, helmet and greaves of the tier (heavy if it carries a shield or a
	# two-handed weapon, light otherwise); all five pieces when it is a tier ahead
	var armor_tier := tier + armor_tier_offset
	if armor_tier >= 0:
		armor_tier = clampi(armor_tier, 0, LevelCurve.MAX_TIER)
		var heavy := e.starting_off_hand != null and e.starting_off_hand != e.starting_weapon \
			or (e.starting_weapon != null and e.starting_weapon.two_handed)
		var pieces: Array[String] = ["cuirass", "helmet", "greaves"]
		if armor_tier_offset >= 0:
			pieces.append_array(["gauntlets", "boots"])
		for piece in pieces:
			var armor := ItemCatalog.get_armor(armor_tier, piece, heavy)
			if armor != null:
				e.starting_armor.append(armor)

	var drops: Array[LootEntry] = extra_loot.duplicate()
	drops.append_array(ItemCatalog.enemy_loot(level, loot_quality))
	drops.append_array(CraftStock.creature_drops(get_key(), level))
	e.loot = drops
	_apply_stage10(e, level, rng)


## Stage 10: the body, the fighting style, spells and resistances of this kind of enemy
func _apply_stage10(e: Enemy, level: int, rng: RandomNumberGenerator) -> void:
	var key := get_key()
	e.enemy_id = key
	var tough := float(GameRules.get_rule("enemy_toughness"))
	e.max_health *= tough
	e.damage_mult *= tough
	e.body_kind = CreatureBody.kind_for(key)
	# Sharper with level: dodges, blocks, parries and feints more often
	e.cunning = clampf(0.12 + float(level) * 0.012, 0.12, 0.85)
	# The tell before a swing gets shorter as enemies get better
	e.telegraph_time = telegraph_time * clampf(1.0 - float(level) * 0.006, 0.6, 1.0)
	e.max_attackers = 3 if level >= 15 else 2
	match e.body_kind:
		CreatureBody.Kind.BEAST, CreatureBody.Kind.CRAWLER:
			e.style = Enemy.Style.BEAST
		CreatureBody.Kind.SPIRIT:
			e.style = Enemy.Style.SPIRIT
		_:
			e.style = Enemy.Style.BRUTE if (e.starting_weapon != null and e.starting_weapon.two_handed) or body_scale >= 1.3 else Enemy.Style.DUELIST
	if e.body_kind == CreatureBody.Kind.HUMANOID and disposition == Enemy.Disposition.HOSTILE and not key.contains("skeleton") and not key.contains("wight"):
		e.potions = 1 if rng.randf() < 0.5 else 0
	var res := {}
	var spell_ids: Array = []
	match key:
		"fire_spirit":
			res = {"resist_fire": 1.0, "resist_frost": -0.5}
			spell_ids = ["e_firebolt"]
		"ice_wraith":
			res = {"resist_frost": 1.0, "resist_fire": -0.5}
			spell_ids = ["e_icebolt"]
		"ash_cultist":
			res = {"resist_fire": 0.5}
			spell_ids = ["e_firebolt", "e_ward"]
			e.style = Enemy.Style.MAGE
		"ashen_priest":
			res = {"resist_fire": 0.5}
			spell_ids = ["e_firebolt", "e_heal", "e_ward"]
			e.style = Enemy.Style.MAGE
		"skeleton", "skeleton_knight":
			res = {"resist_frost": 0.5, "resist_poison": 1.0, "resist_fire": -0.25}
		"barrow_wight", "wight_lord", "crypt_warden":
			res = {"resist_frost": 0.5, "resist_poison": 1.0}
			spell_ids = ["e_drain", "e_icebolt"] if key != "crypt_warden" else ["e_drain"]
		"vault_sentinel", "vault_guardian":
			res = {"resist_shock": 0.5, "resist_magic": 0.25}
			spell_ids = ["e_shock"]
		"frost_bear", "frost_giant", "frost_raider", "reaver":
			res = {"resist_frost": 0.4}
		"cave_troll":
			res = {"resist_fire": -0.3}
		"vampire":
			res = {"resist_frost": 0.5, "resist_fire": -0.5, "resist_poison": 1.0}
			spell_ids = ["e_drain"]
		"werewolf":
			res = {"resist_frost": 0.3, "resist_poison": 0.5}
			e.style = Enemy.Style.BEAST
		"deep_crawler", "crawler_queen", "dune_stalker":
			res = {"resist_poison": 0.6}
		"bandit", "raider", "cutthroat", "smuggler", "deserter":
			# now and then a bandit has picked up a little magic
			if rng.randf() < 0.15:
				spell_ids = ["e_firebolt"] if rng.randf() < 0.5 else ["e_shock"]
				e.style = Enemy.Style.MAGE
	# Archers: hunters mostly, bandits and raiders now and then
	var archer_chance: float = {"hunter": 0.7, "trapper": 0.6, "bandit": 0.25, "raider": 0.25, "smuggler": 0.2,
		"deserter": 0.25, "frost_raider": 0.25, "reaver": 0.2, "wanderer": 0.15}.get(key, 0.0)
	if spell_ids.is_empty() and rng.randf() < float(archer_chance):
		var bow := ItemCatalog.get_bow(LevelCurve.tier_for_level(level))
		if bow != null:
			e.starting_weapon = bow
			e.starting_off_hand = null
	if not res.is_empty():
		e.set_meta("resists", res)
	for id in spell_ids:
		var s := SpellCatalog.get_spell(String(id))
		if s == null:
			continue
		# Enemy spells are made for their level: damage like a weapon hit of that level
		for fx in s.effects:
			var kind := int(MagicEffects.get_def(StringName(fx["id"])).get("kind", 0))
			if kind == MagicEffects.Kind.INSTANT:
				fx["mag"] = LevelCurve.enemy_spell_damage(level) * (1.6 if fx["id"] == &"restore_health" else 1.0)
			elif kind == MagicEffects.Kind.BUFF:
				fx["mag"] = 10.0 + float(level) * 0.8
		e.spells.append(s)
