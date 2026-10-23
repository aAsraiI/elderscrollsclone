extends SceneTree
## Headless tests for stage 10 (magic and crafting, bodies and ragdolls, harder enemies, NPC days,
## calendar, seasons and weather, grass and rocks).
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage10.gd

var passes := 0
var fails := 0


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


func physics(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	t_magic_data()
	t_alchemy_data()
	t_crafting_data()
	t_calendar()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_magic_data() -> void:
	print("-- magic data")
	check("lots of effects", MagicEffects.all_ids().size() >= 60, str(MagicEffects.all_ids().size()))
	for school in MagicEffects.SCHOOLS:
		check("%s has effects and a skill" % school, MagicEffects.ids_of_school(school).size() >= 5 and SkillDatabase.get_skill(school) != null)
	check("the old magic skills are gone, cooking is in", SkillDatabase.get_skill(&"offensive_magic") == null and SkillDatabase.get_skill(&"cooking") != null)
	var bad := []
	for id in SpellCatalog.all_ids():
		var s := SpellCatalog.get_spell(id)
		if s.validate() != "" or s.get_cost() <= 0.0:
			bad.append(id)
	check("every premade spell is valid", bad.is_empty(), str(bad))
	var missing := []
	for id in SpellCatalog.tome_ids():
		var t := SpellCatalog.get_tome(id)
		if t == null or t.teaches_spell != id or t.item_type != ItemData.ItemType.BOOK:
			missing.append(id)
	check("every learnable spell has a tome", missing.is_empty(), str(missing))
	var fb := SpellCatalog.get_spell("firebolt")
	check("skill makes spells cheaper", fb.get_cost(80) < fb.get_cost(10))
	var big := fb.duplicate_spell()
	big.area = 5.0
	check("a burst costs more", big.get_cost() > fb.get_cost())
	var back := SpellData.from_dict(fb.to_dict())
	check("a spell saves and loads", back.display_name == fb.display_name and back.form == fb.form and back.effects.size() == 1)
	var selfharm := SpellData.make("x", "x", SpellData.Form.SELF, [["fire_damage", 10, 0]])
	check("harmful self spells are refused", selfharm.validate() != "")
	var summon_far := SpellData.make("x", "x", SpellData.Form.TARGET, [["summon_wolf", 0, 30]])
	check("self-only effects are refused on others", summon_far.validate() != "")


func t_alchemy_data() -> void:
	print("-- alchemy")
	var counts := {}
	var all_four := true
	for id in Alchemy.INGREDIENTS:
		var list: Array = Alchemy.INGREDIENTS[id]
		all_four = all_four and list.size() == 4
		for e in list:
			counts[e] = int(counts.get(e, 0)) + 1
	check("every ingredient has 4 effects", all_four)
	var lonely := counts.keys().filter(func(e: String) -> bool: return int(counts[e]) < 2)
	check("every effect is in at least two ingredients (so it can be brewed)", lonely.is_empty(), str(lonely))
	var lav := load("res://scripts/Resources/Ingredients/lavender.tres") as ItemData
	var blue := load("res://scripts/Resources/Ingredients/blue_mountain_flower.tres") as ItemData
	check("ingredient files carry their effects", lav.ingredient_effects.size() == 4)
	check("lavender + mountain flower share Restore Health", Alchemy.shared_effects([lav, blue]).has(&"restore_health"))
	var p1 := CraftedItems.potion([{"id": &"restore_health", "mag": 30, "dur": 0}], false)
	var p2 := CraftedItems.potion([{"id": &"restore_health", "mag": 30, "dur": 0}], false)
	check("the same potion twice is the same item (it stacks)", p1 == p2 and p1.is_consumable())
	check("crafted items load from their save path", SaveUtil.path_to_item(SaveUtil.item_to_path(p1)) == p1)
	var poison := CraftedItems.potion([{"id": &"poison_damage", "mag": 4, "dur": 8}], true)
	check("poisons are not drunk", poison.is_poison and not poison.is_consumable())


func t_crafting_data() -> void:
	print("-- crafting")
	for st in ["forge", "smelter", "tanning_rack", "workbench", "cooking_pot"]:
		check("%s has recipes" % st, Recipes.for_station(st).size() >= 3, str(Recipes.for_station(st).size()))
	var bad := []
	for r in Recipes.all():
		for i in r["inputs"]:
			if not ResourceLoader.exists(i[0]):
				bad.append(i[0])
	check("every recipe ingredient exists", bad.is_empty(), str(bad.slice(0, 5)))
	var tiers := {}
	for r in Recipes.for_station("forge"):
		tiers[Recipes.item(r["result"]).tier] = true
	check("every tier can be forged", tiers.size() == 7, str(tiers.keys()))
	var weak := Enchanting.make_effect(&"fire_damage", 0, 1.0, true)
	var strong := Enchanting.make_effect(&"fire_damage", 4, 1.0, true)
	check("bigger soul gems make stronger enchantments", float(strong["mag"]) > float(weak["mag"]))
	var sword := ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 0)
	var fine := CraftedItems.gear(sword, 2)
	check("an improved sword hits harder", fine.weapon_damage > sword.weapon_damage and fine.display_name.begins_with("Superior"))
	var ring := load("res://scripts/Resources/Jewelry/silver_ring_vigor.tres") as ItemData
	if ring != null:
		var e := Enchanting.make_effect(&"resist_fire", 2, 1.0, false)
		var magic_ring := CraftedItems.gear(ring, 0, [e])
		check("a worn enchantment is a stat while worn", float(magic_ring.stat_modifiers.get("resist_fire", 0.0)) > 0.1)
	check("a smith sells ingots and a pickaxe", CraftStock.extra_for("smith", 1, 10).size() >= 5)
	check("the Mages Guild sells tomes", CraftStock.extra_for("mages", 1, 40).any(func(e: LootEntry) -> bool: return e.item.item_type == ItemData.ItemType.BOOK))
	check("wolves leave pelts", CraftStock.creature_drops("wolf", 5).any(func(e: LootEntry) -> bool: return e.item.resource_path.ends_with("wolf_pelt.tres")))


func t_calendar() -> void:
	print("-- calendar")
	var c := WorldClock.new()
	c.control_environment = false
	c.day = 1
	check("day 1 is the 1st of Seedfall, 412", c.get_month() == 2 and c.get_day_of_month() == 1 and c.get_year() == 412)
	check("it is spring", c.get_season_name() == "Spring")
	c.day = 31
	check("a month later it is Rainhand", WorldClock.MONTHS[c.get_month()] == "Rainhand")
	c.day = 1 + 30 * 10
	check("winter comes", c.get_season() == 0)
	c.day = 1 + 360
	check("a year later it is 413", c.get_year() == 413 and c.get_month() == 2)
	c.day = 7
	check("the 7th day is Sunsday, a day of rest", c.is_rest_day())
	check("ordinals", WorldClock.ordinal(1) == "1st" and WorldClock.ordinal(12) == "12th" and WorldClock.ordinal(23) == "23rd")
	check("the date reads well", c.get_date_text().contains("Seedfall"))
	c.free()


func t_in_game() -> void:
	print("-- in the game")
	WorldState.clear()
	change_scene_to_file("res://test_level.tscn")
	await frames(60)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var book := p.get_node("Spellbook") as Spellbook
	var stats := p.get_node("Stats") as Stats
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	var caster := p.get_node("SpellCaster") as SpellCaster
	check("you start knowing Flames and Healing", book.knows("flames") and book.knows("healing"))
	check("the Magic page is in the Tab menu", (p.get_node("MenuHub") as MenuHub).page_index("magic") == 4 and p.get_node_or_null("MagicUI") != null)
	var shield := load("res://scripts/Resources/iron_shield.tres") as ItemData
	eq.equip(shield)
	book.equip_spell("healing")
	check("a spell takes the off hand", book.get_equipped() != null and eq.get_equipped(ItemData.EquipSlot.OFF_HAND) == null)
	eq.equip(shield)
	check("a shield puts the spell away", book.get_equipped() == null)
	stats.modify_vital("health", -50.0)
	var before := stats.health
	stats.magicka = stats.get_stat("max_magicka")
	check("Healing heals", caster.cast_now(SpellCatalog.get_spell("healing")) and stats.health > before + 20.0, "%f -> %f" % [before, stats.health])
	check("casting costs magicka", stats.magicka < stats.get_stat("max_magicka"))
	# Buffs
	var magic := ActiveMagic.of(p)
	var armor := stats.get_stat("armor")
	magic.apply_list([{"id": &"shield", "mag": 20, "dur": 0.5}], p, "test", "spell")
	check("Shield adds armor", stats.get_stat("armor") >= armor + 19.0)
	await physics(90)
	check("...and wears off", absf(stats.get_stat("armor") - armor) < 0.5)
	# A target in front of you
	var fwd := -p.global_transform.basis.z
	var e := Enemy.spawn(current_scene, p.global_position + fwd * 6.0 + Vector3.UP * 0.5, ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 0))
	e.disposition = Enemy.Disposition.HOSTILE
	await physics(10)
	check("enemies get a jointed body", e.body != null and e.body.bones.has("r_elbow") and e.body.grip.get_child_count() > 0)
	var hp := e.stats.health
	var hand := ActiveMagic.of(e)
	hand.apply_list([{"id": &"fire_damage", "mag": 20, "dur": 0}], p, "test", "spell")
	check("fire burns an enemy", e.stats.health < hp - 10.0, "%f -> %f" % [hp, e.stats.health])
	e.stats.add_modifiers("immune", {"resist_fire": 1.0})
	hp = e.stats.health
	hand.apply_list([{"id": &"fire_damage", "mag": 20, "dur": 0}], p, "test", "spell")
	check("a fire-immune creature doesn't burn", absf(e.stats.health - hp) < 0.01)
	hand.apply_list([{"id": &"frost_damage", "mag": 10, "dur": 0}], p, "test", "spell")
	check("frost still works on it", e.stats.health < hp)
	hand.apply_list([{"id": &"paralyze", "mag": 0, "dur": 1.0}], p, "test", "spell")
	check("Paralyze stuns", e.combat.is_stunned())
	# Death: a ragdoll you can search and drag
	e.stats.modify_vital("health", -99999.0)
	await physics(5)
	var rag := e.get_node_or_null("Ragdoll") as Ragdoll
	check("the dead fall as ragdolls", rag != null and rag.parts.size() >= 10, str(rag.parts.size() if rag != null else 0))
	if rag != null:
		var part: RigidBody3D = rag.parts["spine"]
		# Let the body finish falling, then stand beside it on solid ground. (The hold point follows
		# the camera: a player dropped in mid-air falls during the test and drags the limb back down.)
		for i in 120:
			if rag.is_resting():
				break
			await physics(1)
		p.global_position = part.global_position - fwd * 1.8 + Vector3.UP * 1.0
		for i in 60:
			await physics(1)
			if p.is_on_floor():
				break
		await physics(2)
		var comp: Variant = part.get_meta("interactable", null)
		check("every limb can be searched", comp is ContainerComponent)
		var grabber := p.get_node("Head/RayCast3D/Grabber") as Grabber
		var ok := grabber.grab(comp, part.global_position)
		check("a body can be grabbed by a limb", ok and grabber.get_held_target() == comp)
		var start := part.global_position
		var rose := 0.0
		for i in 40:
			await physics(1)
			rose = maxf(rose, part.global_position.y - start.y)
		check("...and the limb comes up to you", grabber.is_holding() and rose > 0.2, "holding=%s rose=%.2f on_floor=%s" % [grabber.is_holding(), rose, p.is_on_floor()])
		grabber.release()
		await physics(5)
		check("...and drops when let go", not grabber.is_holding())
		check("the body's place follows the ragdoll", e.global_position.distance_to(rag.root_part.global_position) < 1.5)
	# Alchemy, cooking, forging, enchanting
	var lav := load("res://scripts/Resources/Ingredients/lavender.tres") as ItemData
	var blue := load("res://scripts/Resources/Ingredients/blue_mountain_flower.tres") as ItemData
	inv.add_item(lav, 2)
	inv.add_item(blue, 2)
	var potion := Alchemy.brew(p, [lav, blue])
	check("brewing makes a potion", potion != null and inv.has_item(potion) and potion.magic_effects.any(func(x: Dictionary) -> bool: return x["id"] == &"restore_health"))
	check("...and teaches the effects", book.known_ingredient_effects(lav).size() >= 1)
	var mat := "res://scripts/Resources/Materials/"
	inv.add_item(load(mat + "raw_meat.tres"), 1)
	var roast: Dictionary = Recipes.for_station("cooking_pot").filter(func(r: Dictionary) -> bool: return String(r["result"]).ends_with("roast_meat.tres"))[0]
	var meat := load("res://scripts/Resources/Consumables/roast_meat.tres") as ItemData
	var had := inv.get_count(meat)
	check("cooking roasts meat", Recipes.make(roast, p) != null and inv.get_count(meat) > had)
	inv.add_item(load(mat + "iron_ingot.tres"), 6)
	inv.add_item(load(mat + "leather_strips.tres"), 3)
	var dagger_r: Array = Recipes.for_station("forge").filter(func(r: Dictionary) -> bool: return String(r["result"]).ends_with("iron_dagger.tres"))
	check("the forge makes an iron dagger", not dagger_r.is_empty() and Recipes.make(dagger_r[0], p) != null)
	var sword := ItemCatalog.get_weapon(ItemCatalog.Weapon.SWORD, 0)
	inv.add_item(sword, 1)
	var better := Recipes.improve(p, sword)
	check("the grindstone improves a sword", better != null and better.quality == 1 and inv.has_item(better))
	book.learn_enchantment(&"fire_damage")
	var gem := SoulGems.gem(1, true)
	inv.add_item(gem, 1)
	var dag := ItemCatalog.get_weapon(ItemCatalog.Weapon.DAGGER, 0)
	inv.add_item(dag, 1)
	var flaming := Enchanting.enchant(p, dag, &"fire_damage", gem)
	check("enchanting a dagger with fire", flaming != null and not flaming.enchant_effects.is_empty() and CraftedItems.get_charge(flaming) > 0.0)
	if flaming != null:
		Enchanting.disenchant(p, flaming)
	check("disenchanting destroys it", flaming == null or not inv.has_item(flaming))
	# The world
	var grass := 0
	var herbs := 0
	for ch in wm.get_children():
		if ch is TerrainChunk:
			for c in ch.get_children():
				if String(c.name).begins_with("Grass"):
					grass += 1
				if c is HarvestNode:
					herbs += 1
	check("grass grows on the land", grass > 0, str(grass))
	check("herbs or ore can be gathered somewhere", herbs > 0, str(herbs))
	check("the weather runs", wm.weather != null and Weather.NAMES[wm.weather.current] != "")
	wm.weather.set_weather(Weather.Kind.RAIN)
	await frames(5)
	var f := Weather.factors(self)
	check("rain dims the sun", f.is_empty() or float(f.get("sun", 1.0)) < 1.0 or wm.weather.blend >= 1.0)
	# Workstations in town
	var town := wm.get_nearest_town(p.global_position)
	var smithy: BuildingPlot = null
	for b in town.town.buildings:
		if b.kind == BuildingPlot.Kind.SMITHY:
			smithy = b
	if smithy != null:
		var built := InteriorBuilder.build(smithy, 7)
		var root: Node3D = built["root"]
		var kinds: Array = root.find_children("*", "CraftingStation", true, false).map(func(s: Node) -> String: return (s as CraftingStation).kind)
		check("a smithy has a forge, smelter, tanning rack, grindstone and workbench", kinds.has("forge") and kinds.has("smelter") and kinds.has("tanning_rack") and kinds.has("grindstone") and kinds.has("workbench"), str(kinds))
		root.free()
	# Townsfolk: free time is spent in many places, not only the square
	var life := wm.life
	if life != null:
		var places := {}
		for r in life.residents:
			if r.data.role == NpcData.Role.GUARD:
				continue
			r.slot = 3
			var g: Dictionary = life._leisure_goal(r, r.town.town)
			places[g.keys()[0] + String(g.get("pose", ""))] = true
		check("free time goes to many places", places.size() >= 4, str(places.keys()))
	# Saving
	var d := book.to_dict()
	book.forget("flames")
	book.from_dict(d)
	check("the spellbook saves and loads", book.knows("flames") and book.knows_enchantment(&"fire_damage"))
	var sm := get_first_node_in_group("save_manager") as SaveManager
	if sm != null:
		var data: Dictionary = sm.build_save_data()
		check("saves hold the spellbook and the weather", data["player"].has("spellbook") and data.has("weather"))
