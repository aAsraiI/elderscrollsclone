extends SceneTree
## Headless tests for items, creatures, spawn tables, dungeons, garrisons and encounters. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_population.gd

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
		await physics_frame


func secs(s: float) -> void:
	await frames(int(round(s * 60.0)))


func reset_world() -> void:
	if world != null:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	world.name = "TestWorld"
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)


func make_player(parent: Node, high_level := false) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.collision_layer = 1
	p.collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	p.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	var stats := Stats.new()
	stats.name = "Stats"
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	stats.base_stats["max_health"] = 50000.0
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
	var mc := MeleeCombat.new()
	mc.name = "MeleeCombat"
	p.add_child(mc)
	p.add_to_group("player")
	parent.add_child(p)
	if high_level:
		for id in sk.levels.keys():
			sk.levels[id] = 40
	return p


func _run() -> void:
	await process_frame
	await process_frame
	t_items()
	t_curve()
	t_enemy_data()
	t_spawn_tables()
	await t_dispositions()
	await t_persistence_modes()
	await t_dungeon_builder()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- items and the curve

func t_items() -> void:
	print("-- gear files")
	var all_ok := true
	var missing: Array[String] = []
	for t in 7:
		for k in ItemCatalog.WEAPON_KINDS.size():
			if ItemCatalog.get_weapon(k, t) == null:
				all_ok = false
				missing.append("%d/%d" % [t, k])
		if ItemCatalog.get_shield(t) == null or ItemCatalog.get_chest(t) == null:
			all_ok = false
			missing.append("shield/chest %d" % t)
	check("all 42 gear files load", all_ok, str(missing))
	var rising := true
	var detail := ""
	for k in ItemCatalog.WEAPON_KINDS.size():
		for t in range(1, 7):
			var a := ItemCatalog.get_weapon(k, t - 1)
			var b := ItemCatalog.get_weapon(k, t)
			if b.weapon_damage <= a.weapon_damage or b.poise_damage < a.poise_damage or b.value <= a.value:
				rising = false
				detail += " %s@%d" % [ItemCatalog.WEAPON_KINDS[k], t]
	check("damage, poise and value rise with every tier", rising, detail)
	var armor_rising := true
	for t in range(1, 7):
		var a := ItemCatalog.get_chest(t - 1).stat_modifiers["armor"] as float
		var b := ItemCatalog.get_chest(t).stat_modifiers["armor"] as float
		if b <= a or b >= 80.0:
			armor_rising = false
	check("armor rises with every tier and stays under the 80 cap", armor_rising)
	var tiers_ok := true
	for t in 7:
		var w := ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, t)
		if w.tier != t + 1 or w.min_level != LevelCurve.TIER_MIN_LEVEL[t]:
			tiers_ok = false
	check("tier and min_level fields match the curve", tiers_ok)
	check("iron sword is the old file", ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 0) == load(R + "weapons/iron_sword.tres"))
	check("iron sword keeps its old stats (10 damage)", absf(ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 0).weapon_damage - 10.0) < 0.01)
	check("steel greatsword file is the steel tier", ItemCatalog.get_weapon(ItemCatalog.Weapon.GREATSWORD, 1) == load(R + "weapons/steel_greatsword.tres"))
	var dagger := ItemCatalog.get_weapon(ItemCatalog.Weapon.DAGGER, 3)
	check("high tier daggers can still be dual wielded", dagger.can_dual_wield and dagger.combo_length == 4)
	check("warhammers keep their slam", ItemCatalog.get_weapon(ItemCatalog.Weapon.WARHAMMER, 6).secondary_action == ItemData.SecondaryAction.SLAM)
	check("shields keep parry and bash", ItemCatalog.get_shield(4).parry_window > 0.0 and ItemCatalog.get_shield(4).bash_poise > 30.0)
	var sword := ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 5)
	check("a dragonbone sword is named and described", sword.display_name == "Dragonbone Sword" and sword.description.length() > 20, sword.display_name)

	var loot := ItemCatalog.curve_loot(1, 5)
	var low_only := true
	for e in loot:
		if e.item.tier > 2:
			low_only = false
	check("level 1-5 chests hold iron and maybe steel gear only", not loot.is_empty() and low_only)
	loot = ItemCatalog.curve_loot(45, 55)
	var high := false
	var any_iron := false
	for e in loot:
		if e.item.armor_set == &"" and e.item.item_type == ItemData.ItemType.ARMOR and e.item.equip_slot != ItemData.EquipSlot.OFF_HAND:
			continue  # jewelry has its own grades
		high = high or e.item.tier >= 6
		any_iron = any_iron or e.item.tier == 1
	check("level 45-55 chests hold the first dragonbone, no iron", high and not any_iron)
	check("a quality of 0 gives no enemy drops", ItemCatalog.enemy_loot(10, 0.0).is_empty())


func t_curve() -> void:
	print("-- level curve")
	check("level 1 is tier 0, level 7 still 0, level 8 is steel", LevelCurve.tier_for_level(1) == 0 and LevelCurve.tier_for_level(7) == 0 and LevelCurve.tier_for_level(8) == 1)
	check("level 73 is dragonbone, 74 starforged, 100 stays starforged", LevelCurve.tier_for_level(73) == 5 and LevelCurve.tier_for_level(74) == 6 and LevelCurve.tier_for_level(100) == 6)
	check("enemy health grows with level", LevelCurve.enemy_health(1) < LevelCurve.enemy_health(20) and LevelCurve.enemy_health(60) > 400.0)
	check("scaling a level keeps it inside the zone", LevelCurve.scale_level(1, 6, 18) == 6 and LevelCurve.scale_level(40, 6, 18) == 18 and LevelCurve.scale_level(10, 6, 18) == 10)
	# a fair fight: hits an enemy of the right level takes with the matching tier of sword
	var fair := true
	var note := ""
	for level in LevelCurve.TIER_MIN_LEVEL:
		var tier := LevelCurve.tier_for_level(level)
		var sword := ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, tier)
		var hits := LevelCurve.enemy_health(level) / (5.0 + sword.weapon_damage)
		note += " L%d:%.1f" % [level, hits]
		if hits < 3.0 or hits > 8.0:
			fair = false
	check("an average enemy takes 3-8 sword hits at every tier", fair, note)


# ---------------------------------------------------------------- creatures

func t_enemy_data() -> void:
	print("-- EnemyData")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var bandit := load(R + "enemies/bandit.tres") as EnemyData
	var wolf := load(R + "enemies/wolf.tres") as EnemyData
	var brute := load(R + "enemies/bandit_brute.tres") as EnemyData
	var cutthroat := load(R + "enemies/cutthroat.tres") as EnemyData
	var knight := load(R + "enemies/skeleton_knight.tres") as EnemyData
	check("enemy files load", bandit != null and wolf != null and brute != null and cutthroat != null and knight != null)
	var low := Enemy.new()
	bandit.apply(low, 1, rng)
	var high := Enemy.new()
	bandit.apply(high, 30, rng)
	check("level is stored", low.level == 1 and high.level == 30)
	check("health follows the curve", absf(low.max_health - LevelCurve.enemy_health(1)) < 0.01 and absf(high.max_health - LevelCurve.enemy_health(30)) < 0.01)
	check("poise follows the curve", high.max_poise > low.max_poise)
	check("a level 1 bandit wields iron", low.starting_weapon != null and low.starting_weapon.tier == 1, str(low.starting_weapon))
	check("a level 30 bandit wields ebon or the tier below", high.starting_weapon != null and high.starting_weapon.tier >= 4, str(high.starting_weapon.tier))
	check("a level 30 bandit wears armor (cuirass, helmet, greaves), a level 1 bandit wears none", high.starting_armor.size() == 3 and low.starting_armor.is_empty())
	var pair := Enemy.new()
	cutthroat.apply(pair, 8, rng)
	check("cutthroats carry two daggers", pair.starting_weapon != null and pair.starting_weapon == pair.starting_off_hand and pair.starting_weapon.can_dual_wield)
	var shield := Enemy.new()
	knight.apply(shield, 10, rng)
	check("knights carry a shield", shield.starting_off_hand != null and shield.starting_off_hand.equip_slot == ItemData.EquipSlot.OFF_HAND)
	var beast := Enemy.new()
	wolf.apply(beast, 10, rng)
	check("a wolf is unarmed and bites for the beast damage", beast.starting_weapon == null and absf(beast.base_damage - LevelCurve.beast_damage(10)) < 0.01 and beast.body_scale < 1.0)
	check("a wolf drops only its pelt and meat (stage 10)", beast.loot.all(func(l: LootEntry) -> bool: return l.item.item_type == ItemData.ItemType.MATERIAL))
	var big := Enemy.new()
	brute.apply(big, 10, rng)
	check("a brute is bigger, slower, tougher", big.body_scale > 1.0 and big.move_speed < 3.2 and big.max_health > low.max_health * 2.0)
	check("brutes wield a greatsword", big.starting_weapon != null and big.starting_weapon.animation_set == &"greatsword")
	for e in [low, high, pair, shield, beast, big]:
		e.free()


func t_spawn_tables() -> void:
	print("-- spawn tables")
	var table := load(R + "spawns/garrison_camp.tres") as SpawnTable
	check("spawn table loads with entries", table != null and table.entries.size() == 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var brute_at_1 := false
	var brute_at_10 := false
	var sizes := {}
	for i in 300:
		for m in table.roll(rng, 1):
			if m.id == &"bandit_brute":
				brute_at_1 = true
		for m in table.roll(rng, 10):
			if m.id == &"bandit_brute":
				brute_at_10 = true
		sizes[table.roll(rng, 5).size()] = true
	check("level-gated entries never roll below their level", not brute_at_1)
	check("and do roll once the level allows them", brute_at_10)
	check("group sizes vary", sizes.size() >= 2)
	var caravan := load(R + "spawns/enc_caravan.tres") as SpawnTable
	var group := caravan.roll(rng, 3)
	check("a caravan is a merchant with two guards", group.size() == 3 and group[0].id == &"merchant" and group[1].id == &"caravan_guard")
	var empty := SpawnTable.new()
	check("an empty table rolls nothing", empty.roll(rng, 5).is_empty() and not empty.has_entries_for(5))
	var crypt := load(R + "spawns/dungeon_crypt.tres") as SpawnTable
	var rolled := false
	for i in 50:
		for m in crypt.roll(rng, 3):
			if m.id == &"skeleton_knight":
				rolled = true
	check("skeleton knights wait for level 5", not rolled)
	var all_have := true
	for f in ["garrison_camp", "garrison_tower", "garrison_ruins", "garrison_shrine", "garrison_stones", "garrison_cave_mouth", "garrison_crypt_mouth", "dungeon_cave", "dungeon_crypt"]:
		var t := load(R + "spawns/%s.tres" % f) as SpawnTable
		for lvl in [1, 5, 10, 20, 30]:
			if not t.has_entries_for(lvl):
				all_have = false
	check("every garrison and dungeon table has something at every level", all_have)


# ---------------------------------------------------------------- behavior of NPCs and enemies

func t_dispositions() -> void:
	print("-- hostile, neutral and friendly")
	await reset_world()
	var p := make_player(world)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var wanderer := Population.spawn_enemy(load(R + "enemies/wanderer.tres"), 3, world, Vector3(6, 0.05, 0), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	var hunter := Population.spawn_enemy(load(R + "enemies/hunter.tres"), 3, world, Vector3(-6, 0.05, 0), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	var bandit := Population.spawn_enemy(load(R + "enemies/bandit.tres"), 3, world, Vector3(0, 0.05, -9), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	bandit.field_of_view = 360.0
	await secs(0.5)
	check("a friendly NPC does not attack on sight", wanderer.state != Enemy.State.CHASE and wanderer.state != Enemy.State.ATTACK)
	check("a neutral NPC does not attack on sight", hunter.state != Enemy.State.CHASE and hunter.state != Enemy.State.ATTACK)
	check("a hostile bandit notices the player", bandit.state == Enemy.State.CHASE or bandit.state == Enemy.State.ATTACK)

	# talking
	var talk := wanderer.get_node_or_null("NpcTalk") as NpcTalk
	check("friendly NPCs can be talked to", talk != null and wanderer.get_meta("interactable") == talk)
	check("talking is on the interactable physics layer", (wanderer.collision_layer & 4) != 0)
	check("the prompt names the NPC", talk != null and talk.get_prompt() == "Talk to Wanderer", talk.get_prompt() if talk != null else "")
	talk.interact(null)
	var bubbles := wanderer.get_children().filter(func(c: Node) -> bool: return c is Label3D).size()
	check("talking says a line, with no bubble over the head (1.17)", bubbles == 0 and talk.last_line.begins_with("Wanderer: "))
	talk.interact(null)
	check("pressing again says the next line", talk._index == 2)
	check("hostile enemies cannot be talked to", bandit.get_node_or_null("NpcTalk") == null)

	# provoking
	var player_combat := p.get_node("MeleeCombat") as MeleeCombat
	var hit := DamageInfo.new(4.0, p, &"melee")
	hit.direction = Vector3(-1, 0, 0)
	hit.hit_position = hunter.global_position
	hunter.combat.take_damage(hit)
	await secs(0.3)
	check("a neutral NPC turns hostile when hit", hunter.disposition == Enemy.Disposition.HOSTILE)
	check("and goes for the player", hunter.state == Enemy.State.CHASE or hunter.state == Enemy.State.ATTACK, str(hunter.state))
	check("and stops talking", hunter.get_node_or_null("NpcTalk") == null or hunter.get_node("NpcTalk").is_queued_for_deletion())

	var hit2 := DamageInfo.new(4.0, p, &"melee")
	hit2.direction = Vector3(1, 0, 0)
	hit2.hit_position = wanderer.global_position
	var before := wanderer.global_position.distance_to(p.global_position)
	wanderer.combat.take_damage(hit2)
	await secs(1.5)
	check("a friendly NPC runs from you when hit", wanderer.state == Enemy.State.FLEE, str(wanderer.state))
	check("and gets further away", wanderer.global_position.distance_to(p.global_position) > before + 2.0)
	check("and never turns hostile", wanderer.disposition == Enemy.Disposition.FRIENDLY)
	await secs(9.0)
	check("it calms down after a while", wanderer.state == Enemy.State.IDLE or wanderer.state == Enemy.State.WANDER, str(wanderer.state))

	# wandering
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var stroller := Population.spawn_enemy(load(R + "enemies/prospector.tres"), 3, world, Vector3(20, 0.05, 20), rng2, {"persist_mode": Enemy.PersistMode.NEVER})
	var start := stroller.global_position
	var moved := 0.0
	var farthest := 0.0
	for i in 60 * 25:
		await physics_frame
		moved = maxf(moved, stroller.global_position.distance_to(start))
		farthest = maxf(farthest, Vector2(stroller.global_position.x - start.x, stroller.global_position.z - start.z).length())
	check("wandering NPCs stroll around", moved > 1.5, str(moved))
	check("but stay near their home", farthest <= stroller.wander_radius + 3.0, str(farthest))

	# dying: the NPC's body becomes a lootable corpse, talking goes away
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 6
	var victim := Population.spawn_enemy(load(R + "enemies/merchant.tres"), 3, world, Vector3(0, 0.05, 12), rng3, {"persist_mode": Enemy.PersistMode.NEVER})
	await frames(3)
	var kill := DamageInfo.new(99999.0, p, &"melee")
	kill.direction = Vector3(0, 0, -1)
	victim.combat.take_damage(kill)
	await frames(3)
	check("a killed NPC is dead", victim.is_dead())
	check("its body is now a container, not a conversation", victim.get_meta("interactable") is ContainerComponent)
	check("the interaction prompt searches the body", (victim.get_meta("interactable") as ContainerComponent).get_prompt() == "Search Merchant's Body")
	player_combat.is_alive()


func t_persistence_modes() -> void:
	print("-- save modes and remembered kills")
	await reset_world()
	var p := make_player(world)
	WorldState.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var bandit := load(R + "enemies/bandit.tres") as EnemyData
	var garrison := Population.spawn_enemy(bandit, 2, world, Vector3(0, 0.05, -6), rng, {"key": "test/g0", "persist_mode": Enemy.PersistMode.CORPSE_ONLY})
	var transient := Population.spawn_enemy(bandit, 2, world, Vector3(4, 0.05, -6), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	var always := Enemy.new()
	always.position = Vector3(-4, 0.05, -6)
	world.add_child(always)
	await frames(3)
	check("a living garrison member is not saved", not garrison.is_in_group("persistent"))
	check("a transient creature is not saved", not transient.is_in_group("persistent"))
	check("a plain Enemy is still saved like before", always.is_in_group("persistent"))
	var kill := DamageInfo.new(99999.0, p, &"melee")
	kill.direction = Vector3(0, 0, 1)
	garrison.combat.take_damage(kill)
	transient.combat.take_damage(kill)
	await frames(3)
	check("a garrison member's corpse is saved", garrison.is_in_group("persistent"))
	check("a transient creature's corpse is not", not transient.is_in_group("persistent"))
	check("killing a keyed enemy is remembered", WorldState.has_record("kill/test/g0"))
	check("an unkeyed kill leaves no record", WorldState.records.size() == 1)
	var data := garrison.get_persist_data()
	check("the corpse keeps level, size and color for the save file", int(data["level"]) == 2 and data.has("body_scale") and data.has("color"))
	var back := Enemy.restore(data, world)
	await frames(2)
	check("a restored corpse is dead and keeps its level", back.is_dead() and back.level == 2)
	WorldState.clear()


# ---------------------------------------------------------------- dungeons

func _enemies_in(node: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in node.find_children("*", "Enemy", true, false):
		out.append(n as Enemy)
	return out


func t_dungeon_builder() -> void:
	print("-- dungeon enemies")
	WorldState.clear()
	await reset_world()
	var cave := load(R + "world/Dungeons/dark_cave.tres") as DungeonData
	var crypt := load(R + "world/Dungeons/crypt.tres") as DungeonData
	check("dungeon files are hooked up to spawn tables and bosses", cave.spawn_table != null and cave.boss != null and crypt.spawn_table != null and crypt.boss != null)
	var seed_value := 424242

	var result := DungeonBuilder.build(cave, seed_value, "test_cave", 1, 5)
	var root3d: Node3D = result["root"]
	world.add_child(root3d)
	root3d.position = Vector3(0, 0, 0)
	await frames(3)
	var enemies := _enemies_in(root3d)
	check("a cave has enemies in it", enemies.size() > 0 and int(result["enemies"]) == enemies.size(), str(enemies.size()))
	check("the start room is empty", _count_near(enemies, Vector3.ZERO, 7.0) == 0)
	var boss: Enemy = null
	for e in enemies:
		if e.display_name == "Cave Troll":
			boss = e
	check("the farthest room has a boss", boss != null and bool(result["boss"]))
	check("the boss is stronger than anything else", boss != null and boss.max_health > 300.0 and boss.level >= 8)
	var in_range := true
	for e in enemies:
		if e != boss and (e.level < 1 or e.level > 6):
			in_range = false
	check("other enemies are made for the biome's levels 1-5", in_range)
	var bosschest: ContainerComponent = null
	var chests := 0
	for c in root3d.find_children("*", "ContainerComponent", true, false):
		chests += 1
		if (c as ContainerComponent).save_id.ends_with("chest_boss"):
			bosschest = c
	check("the boss room has its own chest", bosschest != null and chests >= 2)
	check("chests hold gear that suits the level on top of the fixed loot", bosschest != null and bosschest.contents.size() > cave.loot_table.size() + 3)
	var names_a: Array[String] = []
	for e in enemies:
		names_a.append("%s%d" % [e.display_name, e.level])
	var keys_a: Array[String] = []
	for e in enemies:
		keys_a.append(e.spawn_key)
	check("every enemy has a stable key", not keys_a.has("") and keys_a.size() == names_a.size())

	# the same seed makes the same dungeon
	root3d.queue_free()
	await frames(2)
	var again := DungeonBuilder.build(cave, seed_value, "test_cave", 1, 5)
	var root2: Node3D = again["root"]
	world.add_child(root2)
	await frames(3)
	var names_b: Array[String] = []
	for e in _enemies_in(root2):
		names_b.append("%s%d" % [e.display_name, e.level])
	check("same seed, same enemies", names_a == names_b, "%s vs %s" % [names_a, names_b])
	check("same seed, same layout", result["signature"] == again["signature"])

	# a kill is remembered: that enemy is not there next time
	var victim_key := keys_a[0]
	WorldState.set_record("kill/" + victim_key, {"dead": true})
	root2.queue_free()
	await frames(2)
	var third := DungeonBuilder.build(cave, seed_value, "test_cave", 1, 5)
	var root3: Node3D = third["root"]
	world.add_child(root3)
	await frames(3)
	var survivors := _enemies_in(root3)
	var found := false
	for e in survivors:
		if e.spawn_key == victim_key:
			found = true
	check("a killed enemy does not come back", not found and survivors.size() == enemies.size() - 1, "%d vs %d" % [survivors.size(), enemies.size()])

	# killing the boss is remembered too
	root3.queue_free()
	await frames(2)
	WorldState.set_record("kill/dungeon/test_cave/boss", {"dead": true})
	var fourth := DungeonBuilder.build(cave, seed_value, "test_cave", 1, 5)
	var root4: Node3D = fourth["root"]
	world.add_child(root4)
	await frames(3)
	var bossless := true
	for e in _enemies_in(root4):
		if e.display_name == "Cave Troll":
			bossless = false
	check("a dead boss stays dead (its chest is still there)", bossless)
	root4.queue_free()
	await frames(2)

	# harder land makes a harder dungeon; the crypt is harder than the land it stands in
	WorldState.clear()
	var weak := DungeonBuilder.build(crypt, 99, "easy_crypt", 1, 3)
	var strong := DungeonBuilder.build(crypt, 99, "easy_crypt", 20, 25)
	var weak_root: Node3D = weak["root"]
	var strong_root: Node3D = strong["root"]
	world.add_child(weak_root)
	world.add_child(strong_root)
	strong_root.position = Vector3(500, 0, 0)
	await frames(3)
	var weak_avg := _avg_level(_enemies_in(weak_root))
	var strong_avg := _avg_level(_enemies_in(strong_root))
	check("the same dungeon is tougher in tougher land", strong_avg > weak_avg + 10.0, "%.1f vs %.1f" % [weak_avg, strong_avg])
	check("the crypt adds its own level offset (+2)", weak_avg >= 2.0, "%.1f" % weak_avg)
	var undead := true
	for e in _enemies_in(weak_root):
		if e.display_name != "Skeleton" and e.display_name != "Skeleton Knight" and e.display_name != "Crypt Warden":
			undead = false
	check("a crypt holds only the dead", undead)
	weak_root.queue_free()
	strong_root.queue_free()
	await frames(2)

	# an empty table means an empty dungeon
	var bare := DungeonData.new()
	bare.min_rooms = 4
	bare.max_rooms = 4
	var bare_result := DungeonBuilder.build(bare, 5, "bare", 1, 5)
	check("a dungeon without a table has no enemies", int(bare_result["enemies"]) == 0 and not bool(bare_result["boss"]))
	(bare_result["root"] as Node3D).free()
	WorldState.clear()


func _count_near(list: Array[Enemy], pos: Vector3, radius: float) -> int:
	var n := 0
	for e in list:
		if Vector2(e.position.x - pos.x, e.position.z - pos.z).length() < radius:
			n += 1
	return n


func _avg_level(list: Array[Enemy]) -> float:
	if list.is_empty():
		return 0.0
	var total := 0.0
	for e in list:
		total += e.level
	return total / float(list.size())


# ---------------------------------------------------------------- the real world

func _find_poi(wm: WorldManager, key: String, biome_name: String = "") -> PlacedPOI:
	for p in wm.pois:
		if p.poi.get_key() != key:
			continue
		if biome_name == "":
			return p
		var b := wm.get_biome_at(p.position.x, p.position.z)
		if b != null and b.display_name == biome_name:
			return p
	return null


# Encounters never start in or near a town, so the encounter tests stand somewhere else in the
# same biome
func _away_from_towns(wm: WorldManager, pos: Vector3) -> Vector3:
	var biome := wm.get_biome_at(pos.x, pos.z)
	for ring in range(0, 12):
		for k in 8:
			var a := float(k) * TAU / 8.0
			var at := pos + Vector3(cos(a), 0.0, sin(a)) * float(ring) * 60.0
			if wm.get_town_at(at, 220.0) == null and wm.get_biome_at(at.x, at.z) == biome and wm.map.get_inside_distance(at.x, at.z) > 350.0:
				return at
	return pos


func _teleport(wm: WorldManager, p: Node3D, pos: Vector3) -> void:
	wm.ensure_area_loaded(pos, 2)
	p.global_position = Vector3(pos.x, wm.get_height_at(pos.x, pos.z) + 2.0, pos.z)


func t_world() -> void:
	print("-- garrisons, encounters and dungeons in a real world")
	WorldState.clear()
	if world != null:
		world.queue_free()
		await process_frame
	world = null
	var settings := (load(R + "world/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	settings.view_distance_chunks = 3
	settings.spawn_radius_chunks = 1
	settings.debug_map_enabled = false
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var player := make_player(holder)
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = settings
	holder.add_child(wm)
	await frames(10)
	check("the world has an encounter manager", wm.encounters != null)
	check("the world planned points of interest", wm.pois.size() > 5, str(wm.pois.size()))

	# ---- garrisons
	var camp := _find_poi(wm, "bandit_camp", "Plains")
	check("there is a bandit camp in the plains to visit", camp != null)
	if camp == null:
		return
	_teleport(wm, player, camp.position + Vector3(0, 0, 14))
	await secs(1.0)
	var garrison := wm.get_garrison(camp.id)
	check("a bandit camp has people in it", garrison.size() >= 2, str(garrison.size()))
	var near := true
	var grounded := true
	var names_first: Array[String] = []
	for e in garrison:
		var flat := Vector2(e.global_position.x - camp.position.x, e.global_position.z - camp.position.z).length()
		if flat > camp.poi.footprint_radius + 1.0:
			near = false
		if absf(e.global_position.y - wm.get_height_at(e.global_position.x, e.global_position.z)) > 3.0:
			grounded = false
		names_first.append("%s%d" % [e.display_name, e.level])
	check("they stand inside the camp", near)
	check("and on the ground", grounded)
	var zone := LevelCurve.zone_range(wm.map, camp.position)
	var levels_ok := true
	for e in garrison:
		if e.level < zone.x or e.level > zone.y + 1:
			levels_ok = false
	check("their levels belong to the biome (%d-%d)" % [zone.x, zone.y], levels_ok)
	var persistent_alive := false
	for e in garrison:
		persistent_alive = persistent_alive or e.is_in_group("persistent")
	check("living garrison members are not part of the save file", not persistent_alive)

	# a camp has a chest with gear for its land
	var camp_node := wm.get_poi_node(camp.id)
	var chest_ok := false
	if camp_node != null:
		for c in camp_node.find_children("*", "ContainerComponent", true, false):
			chest_ok = chest_ok or (c as ContainerComponent).contents.size() > 2
	check("camp chests hold level-appropriate gear on top of their own loot", chest_ok)

	# leave, come back: the same people
	var far := wm.map.get_bounds().get_center()
	var far_target := Vector3(far.x + 900.0, 0.0, far.y + 900.0)
	if camp.position.distance_to(far_target) < 700.0:
		far_target = Vector3(far.x - 900.0, 0.0, far.y - 900.0)
	_teleport(wm, player, far_target)
	await secs(2.0)
	check("when the chunk unloads the living garrison goes with it", wm.get_garrison(camp.id).is_empty())
	var gone := true
	for e in garrison:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			gone = false
	check("and the nodes are freed", gone)
	_teleport(wm, player, camp.position + Vector3(0, 0, 14))
	await secs(1.0)
	var names_second: Array[String] = []
	for e in wm.get_garrison(camp.id):
		names_second.append("%s%d" % [e.display_name, e.level])
	check("coming back finds the same garrison (world seed)", names_first == names_second, "%s vs %s" % [names_first, names_second])

	# kill one: the camp stays one short
	var victim := wm.get_garrison(camp.id)[0] as Enemy
	var key := victim.spawn_key
	var kill := DamageInfo.new(99999.0, player, &"melee")
	kill.direction = Vector3(0, 0, 1)
	victim.combat.take_damage(kill)
	await frames(3)
	check("the kill is recorded under its key", WorldState.has_record("kill/" + key), key)
	_teleport(wm, player, far_target)
	await secs(2.0)
	_teleport(wm, player, camp.position + Vector3(0, 0, 14))
	await secs(1.0)
	var alive := 0
	var had_key := false
	for e in wm.get_garrison(camp.id):
		alive += 1
		if e.spawn_key == key:
			had_key = true
	check("a cleared camp member stays dead after the chunk reloads", alive == names_first.size() - 1 and not had_key, "%d of %d" % [alive, names_first.size()])
	check("and its corpse is still lying there", is_instance_valid(victim) and victim.is_dead())

	# ---- encounters
	var plains_names := ["Bandit", "Bandit Thug", "Bandit Brute", "Cutthroat", "Wolf", "Wanderer", "Hunter", "Merchant", "Caravan Guard"]
	var plains_pos := camp.position + Vector3(0, 0, 14)
	var em := wm.encounters
	em.chance = 1.0
	var biome := wm.get_biome_at(plains_pos.x, plains_pos.z)
	check("the camp is in the plains with encounters defined", biome != null and biome.encounters.size() == 5, biome.display_name if biome != null else "none")
	var did_spawn := 0
	var all_in_range := true
	var all_plain := true
	var distance_ok := true
	var aggro_ok := true
	for enc in biome.encounters:
		em.cleanup_now()
		var spawned := em.try_encounter(true, enc)
		if spawned.is_empty():
			continue
		did_spawn += 1
		for n in spawned:
			var e := n as Enemy
			if not plains_names.has(e.display_name):
				all_plain = false
			if e.level < 1 or e.level > 3:
				all_in_range = false
			var d := Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z).length()
			if d < enc.distance_min - enc.group_spread - 1.0 or d > enc.distance_max + enc.group_spread + 1.0:
				distance_ok = false
			if e.persist_mode != Enemy.PersistMode.NEVER:
				all_plain = false
			if enc.aggro and e.disposition == Enemy.Disposition.HOSTILE and e.state != Enemy.State.CHASE:
				aggro_ok = false
		await secs(0.2)
	check("most plains encounters found room to spawn", did_spawn >= 3, str(did_spawn))
	check("plains encounters only bring plains creatures", all_plain)
	check("at a level made for a level 1 player (1-3)", all_in_range)
	check("they appear 40-75 m away", distance_ok)
	check("ambushers come straight at the player", aggro_ok)

	# a forced ambush
	em.cleanup_now()
	for r in em.get_spawned():
		r.queue_free()
	await frames(2)
	em.cleanup_now()
	var ambush := load(R + "encounters/plains_ambush.tres") as EncounterData
	var group := em.try_encounter(true, ambush)
	await secs(2.0)
	var closing := 0
	for n in group:
		var e := n as Enemy
		if e != null and is_instance_valid(e) and (e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK):
			closing += 1
	check("the ambush is on the way to the player", group.size() >= 2 and closing == group.size(), "%d of %d" % [closing, group.size()])
	var gaining := 0
	var d0 := []
	for n in group:
		d0.append(Vector2(n.global_position.x - player.global_position.x, n.global_position.z - player.global_position.z).length())
	await secs(2.0)
	for i in group.size():
		var n: Node3D = group[i]
		if Vector2(n.global_position.x - player.global_position.x, n.global_position.z - player.global_position.z).length() < d0[i] - 3.0:
			gaining += 1
	check("and they really run at the player", gaining >= 1, "%d of %d" % [gaining, group.size()])

	# caps and calm
	em.max_alive = 1
	check("no new encounter while the cap is reached", em.try_encounter(false).is_empty())
	em.max_alive = 10
	var cleared_group := em.get_spawned()
	for n in cleared_group:
		n.queue_free()
	await frames(2)
	em.cleanup_now()
	check("the manager forgets freed creatures", em.get_alive_count() == 0)

	# biome decides what shows up: the desert and the snow
	var desert_names := ["Desert Raider", "Raider Marauder", "Cutthroat", "Dune Stalker", "Prospector", "Merchant", "Caravan Guard", "Sand Scorpion"]
	var snow_names := ["Mountain Reaver", "Frost Raider", "Frost Bear", "Wolf", "Trapper"]
	var desert_pos := _away_from_towns(wm, Vector3(750, 0, -250))
	_teleport(wm, player, desert_pos)
	await secs(1.0)
	var desert_biome := wm.get_biome_at(player.global_position.x, player.global_position.z)
	check("this is the desert", desert_biome != null and desert_biome.display_name == "Desert", desert_biome.display_name if desert_biome != null else "none")
	var desert_ok := true
	var desert_level_ok := true
	var desert_total := 0
	for i in 8:
		em.cleanup_now()
		for n in em.try_encounter(true):
			var e := n as Enemy
			desert_total += 1
			if not desert_names.has(e.display_name):
				desert_ok = false
			if e.level < 5 or e.level > 7:
				desert_level_ok = false  # a level 1 player in a 6-18 biome meets level 6
	check("desert encounters spawned", desert_total >= 5, str(desert_total))
	check("desert encounters only bring desert creatures", desert_ok)
	check("a weak player in the desert meets level 6 (5-7), not level 1", desert_level_ok)

	for n in em.get_spawned():
		n.queue_free()
	await frames(2)
	_teleport(wm, player, _away_from_towns(wm, Vector3(0, 0, -1500)))
	await secs(1.0)
	var snow_biome := wm.get_biome_at(player.global_position.x, player.global_position.z)
	check("this is the snow", snow_biome != null and snow_biome.display_name == "Snowy Mountains", snow_biome.display_name if snow_biome != null else "none")
	var snow_ok := true
	var snow_total := 0
	for i in 8:
		em.cleanup_now()
		for n in em.try_encounter(true):
			var e := n as Enemy
			snow_total += 1
			if not snow_names.has(e.display_name):
				snow_ok = false
	check("snow encounters spawned", snow_total >= 5, str(snow_total))
	check("snow encounters only bring snow creatures", snow_ok)

	# a strong player meets strong things
	for n in em.get_spawned():
		n.queue_free()
	await frames(2)
	var strong := player.get_node("Skills") as Skills
	for id in strong.levels.keys():
		strong.levels[id] = 40
	var hi_level := strong.get_player_level()
	var high_ok := true
	var met := 0
	for i in 6:
		em.cleanup_now()
		for n in em.try_encounter(true):
			met += 1
			if (n as Enemy).level < snow_biome.level_max - 1:
				high_ok = false
	check("player level %d is held to the biome's top (%d)" % [hi_level, snow_biome.level_max], met > 0 and high_ok)

	# cleanup
	for n in em.get_spawned():
		n.queue_free()
	await frames(2)
	em.cleanup_now()
	em.despawn_distance = 10.0
	var batch := em.try_encounter(true)
	await frames(2)
	em.cleanup_now()
	await frames(2)
	var left := 0
	for n in batch:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			left += 1
	check("creatures beyond the despawn distance are removed", batch.size() > 0 and left == 0, "%d of %d" % [left, batch.size()])
	em.despawn_distance = 150.0
	var corpses := em.try_encounter(true)
	await frames(2)
	var one := corpses[0] as Enemy
	var killer := DamageInfo.new(99999.0, player, &"melee")
	killer.direction = Vector3(0, 0, 1)
	one.combat.take_damage(killer)
	await frames(2)
	em.corpse_seconds = 0.0
	em.cleanup_now()
	await secs(0.1)
	em.cleanup_now()
	await frames(2)
	check("old corpses are cleaned up", not is_instance_valid(one) or one.is_queued_for_deletion())
	check("event creatures are never saved, alive or dead", not (corpses.size() > 1 and corpses[1].is_in_group("persistent")))
	for n in em.get_spawned():
		n.queue_free()

	# ---- a dungeon in the real world
	var entrance := _find_poi(wm, "cave_entrance")
	check("there is a cave entrance", entrance != null)
	if entrance == null:
		return
	_teleport(wm, player, entrance.position + Vector3(0, 0, -6))
	await secs(0.5)
	var entered: bool = await wm.dungeons.enter(entrance.id, entrance.position + Vector3(0, 0, -6), 0.0)
	check("the player can enter the cave", entered and wm.dungeons.is_inside())
	await secs(1.0)
	var inside := _enemies_in(wm.dungeons._root)
	check("the cave has enemies at the biome's level", inside.size() >= 1, str(inside.size()))
	var dungeon_levels_ok := true
	var biome_here := wm.get_biome_at(entrance.position.x, entrance.position.z)
	for e in inside:
		if e.level < biome_here.level_min or e.level > biome_here.level_max + 4:
			dungeon_levels_ok = false
	check("whose levels follow the land the entrance is in (%d-%d)" % [biome_here.level_min, biome_here.level_max], dungeon_levels_ok)
	check("random encounters never start inside a dungeon", em.try_encounter(true).is_empty())
	var inside_root: Node = wm.dungeons._root
	await wm.dungeons.exit()
	await secs(0.5)
	check("leaving closes the dungeon and removes its enemies", not wm.dungeons.is_inside() and not is_instance_valid(inside_root))
	var stragglers := 0
	for n in get_nodes_in_group("enemies"):
		if (n as Node3D).global_position.y < -4000.0:
			stragglers += 1
	check("nothing is left behind below the world", stragglers == 0, str(stragglers))
	holder.queue_free()
	await frames(2)
	WorldState.clear()
