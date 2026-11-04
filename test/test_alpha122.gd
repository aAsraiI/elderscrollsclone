extends SceneTree
## Headless tests for Alpha 1.22, the character build and leveling update: no skill or level cap,
## milestones at 10/25/50/75/100 and mastery past 100, the new skills and what they do, perks,
## feats, attribute and vital points, respec, specializations and backgrounds, the island tiers
## (levels 100-200) and their gear.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha122.gd

const R := "res://data/"

var passes := 0
var fails := 0
var world: Node3D


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func make_player() -> CharacterBody3D:
	if world != null:
		world.queue_free()
	world = Node3D.new()
	root.add_child(world)
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.add_to_group("player")
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	p.add_child(stats)
	var inv := Inventory.new()
	inv.name = "Inventory"
	inv.stats = stats
	p.add_child(inv)
	var eq := Equipment.new()
	eq.name = "Equipment"
	eq.inventory = inv
	eq.stats = stats
	p.add_child(eq)
	var sk := Skills.new()
	sk.name = "Skills"
	sk.announce = false
	p.add_child(sk)
	var fx := StatusEffects.new()
	fx.name = "StatusEffects"
	fx.create_hud = false
	p.add_child(fx)
	world.add_child(p)
	return p


func _run() -> void:
	await frames(2)
	t_tables()
	await t_uncapped()
	await t_milestones()
	await t_new_skills()
	await t_perks()
	await t_character_creation()
	t_world()
	t_gear()
	print("\n%d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_tables() -> void:
	print("-- tables")
	var ids := SkillDatabase.get_all().map(func(d: SkillData) -> String: return String(d.id))
	check("at least 30 skills", ids.size() >= 30, str(ids.size()))
	for want in ["acrobatics", "hand_to_hand", "unarmored", "dual_wielding", "swimming", "riding", "mercantile", "leadership",
			"devotion", "lore", "survival", "hunting", "herbalism", "mining", "farming", "medicine"]:
		check("new skill: %s" % want, ids.has(want))
	var all_five := true
	for def in SkillDatabase.get_all():
		for m in SkillDatabase.MAJOR_LEVELS:
			if not def.milestones.has(m):
				all_five = false
				print("   missing milestone ", def.id, " ", m)
		if def.mastery.is_empty():
			all_five = false
			print("   no mastery ", def.id)
		if not SkillDatabase.GROUPS.has(def.group):
			all_five = false
			print("   bad group ", def.id, " ", def.group)
	check("every skill has milestones at 10, 25, 50, 75, 100 and a mastery bonus", all_five)
	# every stat a skill, perk or feat names is one the game knows (a base stat, an attribute, a resist, power_/cost_ a school)
	var known := Stats.DEFAULT_BASE_STATS.keys()
	var bad := PackedStringArray()
	var check_stat := func(stat: String) -> void:
		var s := stat.trim_suffix("_pct")
		if known.has(s) or s.begins_with("power_") or s.begins_with("cost_") or s in ["water_breathing", "night_eye", "resist_disease", "unarmed_damage", "bane_undead", "bane_beast", "skill_xp"]:
			return
		bad.append(stat)
	for def in SkillDatabase.get_all():
		for s in def.tier_effects:
			check_stat.call(s)
		for m in def.milestones:
			for s in def.milestones[m]["stats"]:
				check_stat.call(s)
		for s in def.mastery:
			check_stat.call(s)
	for p in PerkDatabase.all():
		for s in p["stats"]:
			check_stat.call(s)
	check("every bonus names a stat the game uses", bad.is_empty(), ", ".join(bad))
	check("at least 80 perks", PerkDatabase.all().filter(func(p: Dictionary) -> bool: return not p["feat"]).size() >= 80,
		str(PerkDatabase.all().size()))
	check("at least 30 feats", PerkDatabase.feats().size() >= 30, str(PerkDatabase.feats().size()))
	var reqs_ok := true
	for p in PerkDatabase.all():
		for r in p["requires"]:
			if PerkDatabase.get_perk(String(r)).is_empty():
				reqs_ok = false
		if String(p["skill"]) != "" and SkillDatabase.get_skill(StringName(p["skill"])) == null:
			reqs_ok = false
	check("every perk requirement exists", reqs_ok)
	check("athletics gives movement speed", SkillDatabase.get_skill(&"athletics").tier_effects.has("move_speed_mult"))
	check("acrobatics gives jump height", SkillDatabase.get_skill(&"acrobatics").tier_effects.has("jump_mult"))
	check("feat levels: 10, 25, 50, 75, 100, then every 25", PerkDatabase.is_feat_level(10) and PerkDatabase.is_feat_level(125)
		and PerkDatabase.is_feat_level(250) and not PerkDatabase.is_feat_level(30) and PerkDatabase.feats_by_level(150) == 7)
	check("rank names", SkillDatabase.rank_name(24) == "Apprentice" and SkillDatabase.rank_name(100) == "Master" and SkillDatabase.rank_name(220) == "Legend")
	check("every class's skills exist", Classes.LIST.values().all(func(c: Dictionary) -> bool:
		return (c["major"] + c["minor"]).all(func(s: String) -> bool: return SkillDatabase.get_skill(StringName(s)) != null)))
	check("every background's skills exist", Classes.BACKGROUNDS.values().all(func(b: Dictionary) -> bool:
		return (b["skills"] as Dictionary).keys().all(func(s: String) -> bool: return SkillDatabase.get_skill(StringName(s)) != null)))


func t_uncapped() -> void:
	print("-- no cap")
	var p := make_player()
	await frames(2)
	var sk := p.get_node("Skills") as Skills
	sk.set_level(&"one_handed", 99)
	for i in 30:
		sk.debug_level_up(&"one_handed")
	check("a skill goes past 100", sk.get_level(&"one_handed") == 129, str(sk.get_level(&"one_handed")))
	for id in sk.levels:
		sk.levels[id] = 100
	sk.from_dict(sk.to_dict())
	var at100 := sk.get_player_level()
	sk.add_deed_xp(5000000)
	check("the player level goes past 100", sk.get_player_level() > 150, "%d -> %d" % [at100, sk.get_player_level()])
	var rising := true
	for level in range(95, 260):
		var a := SkillDatabase.player_xp_to_reach(level) - SkillDatabase.player_xp_to_reach(level - 1)
		var b := SkillDatabase.player_xp_to_reach(level + 1) - SkillDatabase.player_xp_to_reach(level)
		rising = rising and b > a
	check("levels past 100 still cost more each time", rising)
	var saved := sk.to_dict()
	sk.from_dict(saved)
	check("levels past 100 survive save and load", sk.get_level(&"one_handed") == 100 and int(saved["one_handed"]["level"]) == 100)
	sk.set_level(&"sneak", 345)
	sk.from_dict(sk.to_dict())
	check("a very high skill level loads unchanged", sk.get_level(&"sneak") == 345)
	check("small tiers count half past 100", is_equal_approx(SkillDatabase.effective_tiers(150), 25.0) and is_equal_approx(SkillDatabase.effective_tiers(100), 20.0))


func t_milestones() -> void:
	print("-- milestones")
	var p := make_player()
	await frames(2)
	var sk := p.get_node("Skills") as Skills
	var st := p.get_node("Stats") as Stats
	var seen: Array = []
	sk.major_milestone.connect(func(id: StringName, level: int, _t: String) -> void: seen.append([id, level]))
	var base_crit := st.get_stat("crit_chance")
	var eq := p.get_node("Equipment") as Equipment
	var inv := p.get_node("Inventory") as Inventory
	var sword := load(R + "weapons/iron_sword.tres") as ItemData
	inv.add_item(sword)
	eq.equip(sword)
	sk.set_level(&"one_handed", 24)
	sk.debug_level_up(&"one_handed")
	check("reaching 25 fires the big milestone", seen.has([&"one_handed", 25]), str(seen))
	check("One-Handed 25 (Keen Edge) adds crit chance with a sword in hand", st.get_stat("crit_chance") >= base_crit + 0.049, "%f -> %f" % [base_crit, st.get_stat("crit_chance")])
	eq.unequip(ItemData.EquipSlot.MAIN_HAND)
	check("... and not with empty hands", st.get_stat("crit_chance") < base_crit + 0.01)
	var before := st.get_stat("move_speed_mult")
	sk.set_level(&"athletics", 50)
	var after := st.get_stat("move_speed_mult")
	check("Athletics 50 is clearly faster", after > before + 0.1, "%f -> %f" % [before, after])
	var jump := st.get_stat("jump_mult")
	sk.set_level(&"acrobatics", 100)
	check("Acrobatics 100 jumps more than twice as high", st.get_stat("jump_mult") > jump + 1.0 and st.get_stat("fall_resist") > 0.9,
		"%f -> %f, fall %f" % [jump, st.get_stat("jump_mult"), st.get_stat("fall_resist")])
	sk.set_level(&"athletics", 100)
	var speed100 := st.get_stat("move_speed_mult")
	sk.set_level(&"athletics", 150)
	check("past 100 mastery keeps adding speed", st.get_stat("move_speed_mult") > speed100 + 0.03, "%f -> %f" % [speed100, st.get_stat("move_speed_mult")])
	check("Skills.major_title names milestones and mastery", Skills.major_title(SkillDatabase.get_skill(&"athletics"), 100) == "Windrunner"
		and Skills.major_title(SkillDatabase.get_skill(&"athletics"), 150).contains("Mastery") and Skills.major_title(SkillDatabase.get_skill(&"athletics"), 51) == "")
	var dmg_mods := Skills.modifiers_at(SkillDatabase.get_skill(&"one_handed"), 100, true)
	check("One-Handed 100: tier damage plus milestone damage", float(dmg_mods.get("damage_pct", 0.0)) > 0.9, str(dmg_mods))


func t_new_skills() -> void:
	print("-- new skills do things")
	var p := make_player()
	await frames(2)
	var sk := p.get_node("Skills") as Skills
	var st := p.get_node("Stats") as Stats
	var eq := p.get_node("Equipment") as Equipment
	var inv := p.get_node("Inventory") as Inventory
	sk.set_level(&"unarmored", 50)
	var bare := st.get_stat("armor")
	check("Unarmored gives armor with no armor on", bare >= 50.0, str(bare))
	var helm := ItemCatalog.get_armor(0, "helmet", true)
	inv.add_item(helm)
	eq.equip(helm)
	check("... and stops with armor on", st.get_stat("armor") < bare, "%f vs %f" % [st.get_stat("armor"), bare])
	sk.set_level(&"hand_to_hand", 50)
	check("Hand-to-Hand raises unarmed damage", st.get_stat("unarmed_damage") >= 20.0, str(st.get_stat("unarmed_damage")))
	sk.set_level(&"mercantile", 100)
	check("Mercantile lowers buy prices", st.get_stat("buy_price_mult") < 0.7, str(st.get_stat("buy_price_mult")))
	sk.set_level(&"medicine", 100)
	check("Medicine makes potions heal more", st.get_stat("potion_mult") > 1.5, str(st.get_stat("potion_mult")))
	sk.set_level(&"swimming", 100)
	check("Swimming 100: faster in water and water breathing", st.get_stat("swim_speed_mult") > 1.9 and st.get_stat("water_breathing") > 0.0)
	sk.set_level(&"conjuration", 50)
	check("Conjuration 50 makes summons stronger", st.get_stat("follower_damage") > 0.1)
	# training hooks
	var xp0 := sk.get_xp(&"herbalism") + sk.get_level(&"herbalism") * 1000.0
	BuildHooks.train(self, &"herbalism", 3.0)
	check("BuildHooks.train reaches the player's skills", sk.get_xp(&"herbalism") + sk.get_level(&"herbalism") * 1000.0 > xp0)
	check("bonus_count: no bonus, no extra", BuildHooks.bonus_count(4, 0.0) == 4)
	check("bonus_count: +100% doubles", BuildHooks.bonus_count(4, 1.0) == 8)
	check("short falls never hurt", BuildHooks.fall_damage(5.0, 0.0) == 0.0)
	check("long falls hurt, less with Acrobatics", BuildHooks.fall_damage(20.0, 0.0) > 100.0 and BuildHooks.fall_damage(20.0, 0.9) < 15.0)
	# crits: with 90% crit chance nearly every hit crits
	st.base_stats["crit_chance"] = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var crits := 0
	for i in 100:
		var info := DamageInfo.new(10.0, p)
		var m := BuildHooks.outgoing_mult(p, null, info, rng)
		if info.has_meta("crit") and m >= 1.5:
			crits += 1
	check("crit chance makes critical hits", crits > 80, str(crits))
	st.base_stats["crit_chance"] = 0.02
	check("damage reduction is capped", is_equal_approx(BuildHooks.reduce(null, 100.0), 100.0))
	var stats2 := Stats.new()
	stats2.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	stats2.base_stats["damage_reduction"] = 5.0
	world.add_child(stats2)
	check("... at 75%", is_equal_approx(BuildHooks.reduce(stats2, 100.0), 25.0))
	# favored skills learn faster
	p.set_meta("character", {"class": "monk", "specialization": "movement"})
	var fav := sk.favored_bonus(SkillDatabase.get_skill(&"acrobatics"))
	check("a major skill in your specialization learns 35% faster", is_equal_approx(fav, 0.35), str(fav))
	check("an off-class skill learns at normal speed", is_equal_approx(sk.favored_bonus(SkillDatabase.get_skill(&"smithing")), 0.0))
	check("archetype names your build", CharacterBuild.archetype(sk) != "")


func t_perks() -> void:
	print("-- perks, feats and points")
	var p := make_player()
	await frames(2)
	var sk := p.get_node("Skills") as Skills
	var st := p.get_node("Stats") as Stats
	var inv := p.get_node("Inventory") as Inventory
	var b := sk.build
	check("a new character has no points", b.perk_points() == 0 and b.feat_points() == 0 and b.attribute_points() == 0)
	sk.add_deed_xp(SkillDatabase.player_xp_to_reach(12))
	var lvl := sk.get_player_level()
	check("level 12: 11 perk points, 1 feat point, 11 attribute and vital points", lvl == 12 and b.perk_points() == 11 and b.feat_points() == 1
		and b.attribute_points() == 11 and b.vital_points() == 11, "level %d perks %d feats %d" % [lvl, b.perk_points(), b.feat_points()])
	var hp := st.get_stat("max_health")
	check("take Toughness", b.take("g_toughness") and st.get_stat("max_health") > hp + 14.0)
	check("Resolute needs level 15", b.why_not("g_resolute").contains("level 15"))
	check("Power Strikes needs Brawn first", b.why_not("w_power_strikes").contains("Brawn"))
	check("a feat at level 10+", b.take("f_duelist") and b.feat_points() == 0 and st.get_stat("crit_mult") > 1.7)
	check("no second feat without a point", not b.take("f_pathfinder"))
	var str0 := st.get_stat("strength")
	check("spend an attribute point (+2)", b.spend_attribute("strength") and is_equal_approx(st.get_stat("strength"), str0 + 2.0))
	var mg := st.get_stat("max_magicka")
	check("spend a vital point (+10 magicka)", b.spend_vital("magicka") and is_equal_approx(st.get_stat("max_magicka"), mg + 10.0))
	var saved := sk.to_dict()
	b.owned.clear()
	b.apply()
	sk.from_dict(saved)
	check("perks and points survive save and load", sk.build.rank_of("g_toughness") == 1 and sk.build.rank_of("f_duelist") == 1
		and sk.build.attribute_points() == 10 and is_equal_approx(st.get_stat("strength"), str0 + 2.0))
	sk.add_deed_xp(SkillDatabase.player_xp_to_reach(60) - SkillDatabase.player_xp_to_reach(12))
	check("Elementalist needs Destruction 20", b.why_not("s_elementalist").contains("Destruction"), b.why_not("s_elementalist"))
	var taken := 0
	while b.take("w_paragon") or b.take("w_brawn"):
		taken += 1
		if taken > 200:
			break
	check("unlimited Paragon perks soak up every point", b.perk_points() == 0 and b.rank_of("w_paragon") > 10, "paragon %d" % b.rank_of("w_paragon"))
	Currency.add_gold(inv, 10)
	check("respec needs gold", b.respec(inv) != "")
	Currency.add_gold(inv, b.respec_cost())
	check("respec gives every point back", b.respec(inv) == "" and b.owned.is_empty() and b.perk_points() == sk.get_player_level() - 1
		and is_equal_approx(st.get_stat("strength"), str0))


func t_character_creation() -> void:
	print("-- specialization and background")
	var p := make_player()
	await frames(2)
	var sk := p.get_node("Skills") as Skills
	var st := p.get_node("Stats") as Stats
	var data := CharacterSetup.default_data()
	data["class"] = "scout"
	data["background"] = "sailor"
	data["specialization"] = "movement"
	CharacterSetup.apply(p, data, true)
	check("a scout starts with Acrobatics as a major skill", sk.get_level(&"acrobatics") >= 11)
	check("a sailor starts with Swimming +10", sk.get_level(&"swimming") >= 11 and st.get_stat("breath_mult") > 1.2)
	check("still player level 1", sk.get_player_level() == 1)
	check("every new class can be built", ["monk", "scout", "crusader", "trader", "druid", "duelist"].all(func(c: String) -> bool: return Classes.LIST.has(c)))


func t_world() -> void:
	print("-- the islands")
	var lows := {}
	for f in DirAccess.get_files_at(R + "world/Islands/"):
		if not f.ends_with(".tres"):
			continue
		var isl := load(R + "world/Islands/" + f) as IslandData
		for pl in isl.placements:
			var r := pl.get_level_range()
			lows[isl.name + " " + str(r)] = r
	var ok := true
	for k in lows:
		var r: Vector2i = lows[k]
		if r.x < 100 or r.y > 200:
			ok = false
	check("every island region is level 100-200", ok and not lows.is_empty(), str(lows.keys()))
	check("the top tier never drops out at very high levels", LevelCurve.tier_weights(400)[LevelCurve.MAX_TIER] > 0.99)
	check("level 160 is mostly Astral", LevelCurve.tier_weights(160)[9] > 0.4, str(LevelCurve.tier_weights(160)))
	var se := SpawnEntry.new()
	se.members = [load(R + "enemies/bandit.tres") if ResourceLoader.exists(R + "enemies/bandit.tres") else EnemyData.new()]
	check("spawn tables allow level 180", se.allows(180))
	check("enemies at 200 are tougher than at 100", LevelCurve.enemy_health(200) > LevelCurve.enemy_health(100) * 1.5)


func t_gear() -> void:
	print("-- island gear")
	for t in [7, 8, 9, 10]:
		var ok := true
		for k in ItemCatalog.WEAPON_KINDS.size():
			var w := ItemCatalog.get_weapon(k, t)
			ok = ok and w != null and w.tier == t + 1 and w.min_level == LevelCurve.TIER_MIN_LEVEL[t]
		for piece in ItemCatalog.ARMOR_PIECES:
			ok = ok and ItemCatalog.get_armor(t, piece, true) != null and ItemCatalog.get_armor(t, piece, false) != null
		ok = ok and ItemCatalog.get_shield(t) != null and ItemCatalog.get_bow(t) != null and ItemCatalog.get_arrow(t) != null
		check("%s: every weapon, armor piece, shield, bow and arrow" % LevelCurve.TIER_NAMES[t], ok)
	check("Primordial hits harder than Starforged", ItemCatalog.get_weapon(0, 10).weapon_damage > ItemCatalog.get_weapon(0, 6).weapon_damage * 2.0)
	var forge := Recipes.for_station("forge").filter(func(r: Dictionary) -> bool: return String(r["result"]).contains("primordial"))
	check("Primordial gear can be forged", not forge.is_empty())
	var smelt := Recipes.for_station("smelter").filter(func(r: Dictionary) -> bool: return String(r["result"]).contains("voidsteel"))
	check("Void ore smelts into Voidsteel", not smelt.is_empty())
	var legends := ItemCatalog.tagged("legendary")
	check("at least 12 legendary uniques", legends.size() >= 12, str(legends.size()))
	check("legendaries are orange", ItemCatalog.rarity_color(legends[0], 150).r > 0.95 and ItemCatalog.rarity_color(legends[0], 150).b < 0.3)
	var high := ItemCatalog.curve_loot(170, 200, 2.0)
	check("a level 170-200 chest can hold Primordial gear and legendaries", high.any(func(e: LootEntry) -> bool: return e.item.tier == 11)
		and high.any(func(e: LootEntry) -> bool: return e.item.loot_tags.has("legendary")))
	var low := ItemCatalog.curve_loot(10, 20)
	check("a low chest never holds island gear", low.all(func(e: LootEntry) -> bool: return e.item.tier <= 4 and not e.item.loot_tags.has("legendary")))
	check("supreme potions exist", ResourceLoader.exists(R + "consumables/supreme_health_potion.tres"))
	check("island relics exist", ResourceLoader.exists(R + "artifacts/primordial_egg.tres"))
	check("Voidstone and Starstone jewelry", ResourceLoader.exists(R + "jewelry/voidstone_ring_vigor.tres") and ResourceLoader.exists(R + "jewelry/starstone_amulet_insight.tres"))
