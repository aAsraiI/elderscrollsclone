extends SceneTree
## Headless tests for stage 9a (items for every slot, new weapons, level cap 100, blended loot).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage9a.gd

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
	p.add_child(sk)
	var fx := StatusEffects.new()
	fx.name = "StatusEffects"
	fx.create_hud = false
	p.add_child(fx)
	world.add_child(p)
	return p


func _run() -> void:
	await frames(2)
	t_files()
	t_curve()
	t_loot()
	await t_player()
	t_enemies()
	t_models()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_files() -> void:
	print("-- item files")
	var missing := []
	for t in 7:
		for k in ItemCatalog.WEAPON_KINDS.size():
			if ItemCatalog.get_weapon(k, t) == null:
				missing.append("%s %d" % [ItemCatalog.WEAPON_KINDS[k], t])
		for piece in ItemCatalog.ARMOR_PIECES:
			for heavy in [true, false]:
				if ItemCatalog.get_armor(t, piece, heavy) == null:
					missing.append("%s %s %d" % ["heavy" if heavy else "light", piece, t])
	check("8 weapon kinds and 10 armor pieces load in all 7 tiers", missing.is_empty(), str(missing))
	var slots_ok := true
	for t in 7:
		var set_total := 0.0
		var light_total := 0.0
		for piece in ItemCatalog.ARMOR_PIECES:
			var h := ItemCatalog.get_armor(t, piece, true)
			var l := ItemCatalog.get_armor(t, piece, false)
			set_total += float(h.stat_modifiers["armor"])
			light_total += float(l.stat_modifiers["armor"])
			slots_ok = slots_ok and h.equip_slot == l.equip_slot and h.weight > l.weight and h.armor_set != l.armor_set
		if absf(set_total - [30, 38, 46, 54, 62, 70, 78][t]) > 0.5 or light_total >= set_total:
			slots_ok = false
	check("a full heavy set gives its tier's armor; light gives less and weighs less", slots_ok)
	check("the iron cuirass keeps its old file and id", ItemCatalog.get_chest(0) == load(R + "weapons/iron_chestplate.tres") and FileAccess.get_file_as_string(R + "weapons/iron_chestplate.tres").begins_with('[gd_resource type="Resource" script_class="ItemData" format=3 uid="uid://bu7yro4jl28nt"]'))
	var mace := ItemCatalog.get_weapon(ItemCatalog.Weapon.MACE, 2)
	check("maces ignore a quarter of armor and say so", mace.armor_pierce == 0.25 and mace.get_combat_description().contains("Ignores 25% of armor"))
	var spear := ItemCatalog.get_weapon(ItemCatalog.Weapon.SPEAR, 0)
	var sword := ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 0)
	check("spears reach furthest and are two-handed", spear.reach > sword.reach and spear.two_handed and ItemCatalog.get_weapon(ItemCatalog.Weapon.BATTLEAXE, 0).two_handed)
	check("there are 40 rings and amulets", ItemCatalog.tagged("jewelry").size() == 40, str(ItemCatalog.tagged("jewelry").size()))
	var arts := ItemCatalog.all_items().filter(func(i: ItemData) -> bool: return i.artifact)
	check("24 artifacts, all treasure", arts.size() == 24 and arts.all(func(i: ItemData) -> bool: return i.treasure and i.min_level >= 1), str(arts.size()))
	var ingr := ItemCatalog.all_items().filter(func(i: ItemData) -> bool: return i.item_type == ItemData.ItemType.INGREDIENT)
	check("20 ingredients fill the Ingredients tab", ingr.size() >= 20, str(ingr.size()))
	check("kitchens and smithies have things to put on their shelves", ItemCatalog.tagged("kitchen").size() >= 6 and ItemCatalog.tagged("smithy").size() >= 10)
	check("clutter is marked as junk", (load(R + "clutter/tankard.tres") as ItemData).junk and not (load(R + "clutter/iron_ingot.tres") as ItemData).junk)
	check("old items still load", load(R + "consumables/bread.tres") is ItemData and load(R + "treasure/ruby.tres") is ItemData)


func t_curve() -> void:
	print("-- level curve")
	var smooth := true
	var sums := true
	var prev := LevelCurve.tier_weights(1)
	for level in range(1, 101):
		var w := LevelCurve.tier_weights(level)
		var s := 0.0
		for i in w.size():
			s += w[i]
			if absf(w[i] - prev[i]) > 0.25:
				smooth = false
		sums = sums and absf(s - 1.0) < 0.001
		prev = w
	check("tier chances always add up to 1", sums)
	check("no tier's chance moves more than 25% between two levels", smooth)
	var at10 := LevelCurve.tier_weights(10)
	check("level 10 is mostly steel, some iron, no silver yet", at10[1] > 0.5 and at10[0] > 0.05 and at10[2] == 0.0, str(at10))
	var before := LevelCurve.tier_weights(LevelCurve.TIER_MIN_LEVEL[3] - 1)
	check("a tier shows up as a rare find just before it starts", before[3] > 0.0 and before[3] < 0.2, str(before))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := [0, 0, 0, 0, 0, 0, 0]
	for i in 1000:
		counts[LevelCurve.roll_tier(30, rng)] += 1
	check("rolls at level 30 follow the weights (obsidian and silver)", counts[3] > 420 and counts[2] > 350 and counts[0] == 0, str(counts))
	check("gold grows with level", LevelCurve.gold_range(60).x > LevelCurve.gold_range(10).y)
	check("level cap is 100", LevelCurve.MAX_LEVEL == 100)
	check("skill levels get slower the higher they are", SkillDatabase.xp_to_next_level(90) / SkillDatabase.xp_to_next_level(50) > SkillDatabase.xp_to_next_level(50) / SkillDatabase.xp_to_next_level(10) * 0.35 and SkillDatabase.xp_to_next_level(90) > 700.0)
	var costs_rise := true
	for level in range(2, 100):
		var a := SkillDatabase.player_xp_to_reach(level) - SkillDatabase.player_xp_to_reach(level - 1)
		var b := SkillDatabase.player_xp_to_reach(level + 1) - SkillDatabase.player_xp_to_reach(level)
		costs_rise = costs_rise and b > a
	check("every player level costs more than the one before", costs_rise)


func t_loot() -> void:
	print("-- loot")
	var low := ItemCatalog.curve_loot(1, 5)
	check("low chests hold low gear", low.all(func(e: LootEntry) -> bool: return e.item.tier <= 2))
	var high := ItemCatalog.curve_loot(80, 95)
	var star := high.any(func(e: LootEntry) -> bool: return e.item.tier == 7 and e.item.item_type == ItemData.ItemType.WEAPON)
	check("level 80-95 chests hold starforged weapons", star)
	check("loot includes light and heavy armor pieces", high.any(func(e: LootEntry) -> bool: return e.item.governing_skill == "light_armor") and high.any(func(e: LootEntry) -> bool: return e.item.equip_slot == ItemData.EquipSlot.FEET))
	var crypt_low := ItemCatalog.tag_loot(PackedStringArray(["crypt"]), 3)
	var crypt_high := ItemCatalog.tag_loot(PackedStringArray(["crypt"]), 40)
	check("a low crypt has no artifacts beyond its level", crypt_low.all(func(e: LootEntry) -> bool: return e.item.min_level <= 3 or e.item.tier > 0))
	check("a deeper crypt can hold artifacts", crypt_high.any(func(e: LootEntry) -> bool: return e.item.artifact))
	var gold := ItemCatalog.gold_loot(50)
	check("chest gold follows the level", gold.min_count == LevelCurve.gold_range(50).x and gold.item != null)
	check("rarity: gear two tiers ahead is purple, artifacts gold", ItemCatalog.rarity_color(ItemCatalog.get_weapon(0, 3), 1).b > 0.9 and ItemCatalog.rarity_color(load(R + "artifacts/sunfire_idol.tres"), 1).r > 0.9)


func t_player() -> void:
	print("-- the player")
	var p := make_player()
	await frames(2)
	var sk := p.get_node("Skills") as Skills
	var st := p.get_node("Stats") as Stats
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	for id in sk.levels:
		sk.levels[id] = 100
	var by_skills := sk.get_player_level()
	check("all skills at 100 alone do not reach the cap", by_skills < 100 and by_skills > 70, str(by_skills))
	sk.add_deed_xp(10000000)
	check("deeds carry you to level 100 and never past it", sk.get_player_level() == 100)
	var saved := sk.to_dict()
	sk.deed_xp = 0
	sk.from_dict(saved)
	check("deed XP is saved", sk.deed_xp == 10000000)
	for id in sk.levels:
		sk.levels[id] = 1
	sk.deed_xp = 0
	sk.from_dict(sk.to_dict())
	# armor set bonus
	for piece in ItemCatalog.ARMOR_PIECES:
		var it := ItemCatalog.get_armor(0, piece, true)
		inv.add_item(it)
		eq.equip(it)
	check("all five iron pieces: 30 armor + 10%", absf(st.get_stat("armor") - 33.0) < 0.2 and eq.has_full_set(), str(st.get_stat("armor")))
	eq.unequip(ItemData.EquipSlot.FEET)
	check("four pieces: no set bonus", absf(st.get_stat("armor") - 27.0) < 0.2 and not eq.has_full_set(), str(st.get_stat("armor")))
	# potions
	var fx := p.get_node("StatusEffects") as StatusEffects
	var pot: ItemData = load(R + "consumables/stamina_potion.tres")
	inv.add_item(pot)
	st.modify_vital("stamina", -90.0)
	var before := st.stamina
	fx.use_item(pot)
	check("a stamina potion gives stamina back at once", st.stamina >= before + 79.0, "%f -> %f" % [before, st.stamina])
	# jewelry
	var ring: ItemData = load(R + "jewelry/gold_ring_vigor.tres")
	inv.add_item(ring)
	var hp := st.get_stat("max_health")
	eq.equip(ring)
	check("a ring of vigor raises max health", st.get_stat("max_health") > hp)


func t_enemies() -> void:
	print("-- enemies")
	var data := EnemyData.new()
	data.kit = EnemyData.Kit.MACE_SHIELD
	data.armor_tier_offset = 0
	var e := Enemy.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	data.apply(e, 45, rng)
	check("a mace-and-shield enemy carries both", e.starting_weapon != null and e.starting_weapon.animation_set == &"mace" and e.starting_off_hand != null)
	check("a tier-matched enemy wears a full heavy set", e.starting_armor.size() == 5 and e.starting_armor.all(func(a: ItemData) -> bool: return a.governing_skill == "heavy_armor"), str(e.starting_armor.size()))
	e.free()
	data.kit = EnemyData.Kit.DAGGER
	data.armor_tier_offset = -1
	var e2 := Enemy.new()
	data.apply(e2, 45, rng)
	check("a dagger enemy wears three light pieces", e2.starting_armor.size() == 3 and e2.starting_armor.all(func(a: ItemData) -> bool: return a.governing_skill == "light_armor"))
	e2.free()


func t_models() -> void:
	print("-- models")
	for k in ["waraxe", "mace", "spear", "battleaxe"]:
		var it := ItemCatalog.get_weapon(ItemCatalog.WEAPON_KINDS.find(k), 0)
		var m := ItemModels.build_view(it)
		var size := ItemModels.get_bounds(m).size
		check("%s has its own shape" % it.display_name, m.get_child_count() >= 2 and size.y > 0.4)
		m.free()
	for piece in ItemCatalog.ARMOR_PIECES:
		var m := ItemModels.build_world(ItemCatalog.get_armor(2, piece, false))
		check("light %s has a model" % piece, m.find_children("*", "MeshInstance3D", true, false).size() >= 1)
		m.free()
	var book := ItemModels.build_world(load(R + "clutter/old_book.tres"))
	check("a book looks like a book (flat)", ItemModels.get_bounds(book).size.y < 0.1)
	book.free()
