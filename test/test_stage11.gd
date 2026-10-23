extends SceneTree
## Headless tests for stage 11: world and character creation, survival, diseases, vampires and
## werewolves, archery, homes, horses, carriages, followers, the story, sound, controls, and the
## dungeon ragdoll fix.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage11.gd

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
	t_tables()
	await t_in_game()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_tables() -> void:
	print("-- tables")
	check("ten races, each with a power", Races.ids().size() == 10 and Races.ids().all(func(id: String) -> bool: return not Races.power_effects(Races.get_race(id)["power"]).is_empty()))
	var bad := []
	for id in Classes.LIST:
		var cls := Classes.get_class_data(id)
		for s in cls["major"] + cls["minor"]:
			if SkillDatabase.get_skill(StringName(s)) == null:
				bad.append(s)
		for g in cls["gear"]:
			if not ResourceLoader.exists(String(g[0])):
				bad.append(g[0])
		for sp in cls["spells"]:
			if SpellCatalog.get_spell(sp) == null:
				bad.append(sp)
	check("every class has real skills, gear and spells", bad.is_empty(), str(bad))
	check("all warrior answers make a warrior", Classes.class_from_quiz([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) == "warrior")
	check("all mage answers make a mage", Classes.class_from_quiz([1, 1, 1, 1, 1, 1, 1, 1, 1, 1]) == "mage")
	check("a mix of thief and warrior makes an assassin", Classes.class_from_quiz([2, 2, 2, 2, 2, 2, 0, 0, 0, 0]) == "assassin")
	check("advantages slow leveling, disadvantages speed it", Classes.xp_mult(["iron_skin", "rapid_healing"], []) < 1.0 and Classes.xp_mult([], ["frail", "weak_magic"]) > 1.0)
	check("bows and arrows for every tier", ItemCatalog.get_bow(0) != null and ItemCatalog.get_bow(6) != null and ItemCatalog.get_arrow(3) != null and ItemCatalog.get_bow(2).is_bow)
	check("the forge makes bows and arrows", Recipes.for_station("forge").any(func(r: Dictionary) -> bool: return String(r["result"]).ends_with("_bow.tres")))
	check("vampires and werewolves exist", ResourceLoader.exists("res://data/enemies/vampire.tres") and ResourceLoader.exists("res://data/enemies/werewolf.tres"))
	check("sounds are made in code", Synth.get_sound("hit") is AudioStreamWAV and Synth.get_sound("swing") is AudioStreamWAV)
	Bindings.apply()
	check("controls: keys and controller", InputMap.has_action("favorites") and InputMap.action_get_events("jump").any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton))
	var c := WorldClock.new()
	c.control_environment = false
	c.day = 15
	c.hour = 22.0
	check("the 15th is a full moon night", c.is_full_moon_night() and c.get_moon_name() == "Full Moon")
	c.day = 16
	c.hour = 22.0
	check("the 16th is not", not c.is_full_moon_night())
	c.free()


func t_in_game() -> void:
	print("-- a created character")
	WorldState.clear()
	GameRules.from_dict({"survival": true, "afflictions": true})
	CharacterSetup.pending = {"name": "Testa", "race": "highborn", "sex": 1, "skin": 0, "hair": 1, "height": 1.0, "class": "ranger",
		"advantages": ["iron_skin"], "disadvantages": ["forbid_heavy"], "sign": "staff", "affliction": ""}
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(60)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var inv := p.get_node("Inventory") as Inventory
	var eq := p.get_node("Equipment") as Equipment
	var stats := p.get_node("Stats") as Stats
	var skills := p.get_node("Skills") as Skills
	check("the class gear is in the bag (a bow and arrows)", inv.stacks.any(func(s: Inventory.Stack) -> bool: return s.item.is_bow) and inv.stacks.any(func(s: Inventory.Stack) -> bool: return s.item.is_arrow))
	check("no test sword", not inv.stacks.any(func(s: Inventory.Stack) -> bool: return s.item.resource_path.ends_with("weapons/steel_greatsword.tres")))
	check("class skills start higher, the player level stays 1", skills.get_level(&"archery") == 11 and skills.get_level(&"heavy_armor") == 1 and skills.get_player_level() == 1, "%d %d" % [skills.get_level(&"archery"), skills.get_player_level()])
	check("race and sign traits apply", stats.get_stat("max_magicka") >= 140.0, str(stats.get_stat("max_magicka")))
	var heavy := ItemCatalog.get_armor(0, "cuirass", true)
	inv.add_item(heavy, 1)
	check("a forbidden armor won't go on", not eq.equip(heavy))
	check("the racial power is set", (p.get_node("Powers") as Powers).racial == "highborn")
	await frames(130)
	check("the main story begins", Story.stage() == 1 and not Story.target().is_empty())
	# Survival
	var surv := p.get_node("Survival") as Survival
	var h0 := surv.hunger
	wm.clock.advance_hours(10.0)
	await frames(3)
	check("hunger grows with time", surv.hunger > h0 + 30.0, "%f -> %f" % [h0, surv.hunger])
	var bread := load("res://data/consumables/bread.tres") as ItemData
	inv.add_item(bread, 1)
	var before := surv.hunger
	(p.get_node("StatusEffects") as StatusEffects)._cooldown = 0.0
	(p.get_node("StatusEffects") as StatusEffects).use_item(bread)
	check("eating lowers it", surv.hunger < before)
	# Archery
	var bow := ItemCatalog.get_bow(0)
	eq.equip(bow)
	var ranged := p.get_node("RangedCombat") as RangedCombat
	var fwd := -p.global_transform.basis.z
	var target := Enemy.spawn(current_scene, p.global_position + fwd * 8.0 + Vector3.UP * 0.4, null)
	target.disposition = Enemy.Disposition.HOSTILE
	await physics(5)
	var hp := target.stats.health
	var arrows_before := inv.get_count(ItemCatalog.get_arrow(0))
	check("drawing a bow", ranged.begin_draw())
	await physics(70)
	ranged.aim_target = target
	ranged.release()
	await physics(40)
	ranged.aim_target = null
	check("the arrow flies and hits", target.stats.health < hp, "%f -> %f" % [hp, target.stats.health])
	check("an arrow was used", inv.get_count(ItemCatalog.get_arrow(0)) == arrows_before - 1)
	# Vampires
	var aff := p.get_node("Afflictions") as Afflictions
	aff.become_vampire()
	check("a vampire knows Vampiric Drain", (p.get_node("Spellbook") as Spellbook).knows("vampiric_drain"))
	check("vampires refuse bread", aff.refuses_food(bread))
	wm.clock.advance_hours(50.0)
	await frames(80)
	check("two days without blood: starving", aff.hunger_stage() == 2, str(aff.hunger_stage()))
	target.stats.modify_vital("health", -99999.0)
	await physics(5)
	var comp := target.get_node_or_null("ContainerComponent")
	for c in target.get_children():
		if c is ContainerComponent:
			comp = c
	var empty := load(Afflictions.BOTTLE) as ItemData
	inv.add_item(empty, 2)
	check("feeding on a fresh body", aff.feed(comp, false) and aff.hunger_stage() == 0)
	check("...only once per body", not aff.feed(comp, true))
	aff.cure_vampire()
	check("the shrine's cure ends it", not aff.vampire and not (p.get_node("Spellbook") as Spellbook).knows("vampiric_drain"))
	# Werewolves
	aff.become_werewolf()
	eq.equip(bow)
	aff.start_beast_form(false)
	check("beast form takes the weapon away", p.has_meta("beast_form") and eq.get_main_hand() == null)
	check("the beast can't put it back on", not eq.equip(bow))
	check("no resting in beast form", (p.get_node("WaitMenu") as WaitMenu)._cant_wait() != "")
	check("no fast travel either", wm.discovery.can_travel_to(wm.towns[0]) != "")
	aff.end_beast_form()
	check("changing back returns the bow", not p.has_meta("beast_form") and eq.get_main_hand() == bow)
	aff.cure_werewolf()
	# Diseases
	aff.catch("rattle_fever")
	check("diseases weaken you", aff.diseases.has("rattle_fever") and stats.get_stat("stamina_regen_mult") < 1.0)
	ActiveMagic.of(p).apply_list([{"id": &"cure_disease", "mag": 0, "dur": 0}], null, "test", "potion")
	check("Cure Disease cures it", aff.diseases.is_empty())
	# Horse
	var rider := p.get_node("Rider") as Rider
	rider.use_deed()
	await physics(10)
	check("the deed brings a horse", rider.horse != null and is_instance_valid(rider.horse))
	rider.mount(rider.horse)
	check("you can ride it", rider.is_riding() and p.has_meta("riding"))
	var hpos := rider.horse.global_position
	Input.action_press("move_forward")
	await physics(40)
	Input.action_release("move_forward")
	check("riding forward moves the horse", rider.horse.global_position.distance_to(hpos) > 1.0, str(rider.horse.global_position.distance_to(hpos)))
	rider.dismount()
	check("and you get off", not rider.is_riding())
	# Followers
	var f := p.get_node("Followers") as Followers
	check("a sellsword can be hired", f.hire() == "" and f.followers.size() == 1 and f.followers[0].has_meta("player_ally"))
	var saved := f.to_dict()
	check("followers are saved", (saved["followers"] as Array).size() == 1)
	# Homes and carriages
	var city: PlacedPOI = null
	for t in wm.towns:
		if (t.poi as TownData).kind == TownData.Kind.CITY:
			city = t
	if city != null:
		var sale := Homes.for_sale_id(city.town, TownData.Kind.CITY)
		check("cities have a house for sale with nobody living in it", sale != "" and wm.life.get_owner_of(sale) == null)
		var b := wm.get_building(sale)
		Currency.add_gold(inv, 6000)
		check("buying it", Homes.buy(b, inv, wm) == "" and Homes.owns(sale))
		var built := InteriorBuilder.build(b, 3)
		var body_root: Node3D = built["root"]
		check("your home has planters, a bed and an alchemy lab", not body_root.find_children("*", "Planter", true, false).is_empty() \
			and not body_root.find_children("*", "RestSpot", true, false).is_empty() \
			and body_root.find_children("*", "CraftingStation", true, false).any(func(s: Node) -> bool: return (s as CraftingStation).kind == "alchemy_lab"))
		body_root.free()
		check("cities have a carriage stop", Carriage.stop_for(city).length() > 0.0)
	# The ragdoll fix: a body far below the world (where dungeons are) still falls
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	current_scene.add_child(floor_body)
	floor_body.global_position = Vector3(0, -5000.0, 0)
	var deep := Enemy.spawn(current_scene, Vector3(0, -4998.5, 0), null)
	await physics(5)
	deep.stats.modify_vital("health", -99999.0)
	await physics(30)
	var rag := deep.get_node_or_null("Ragdoll") as Ragdoll
	check("ragdolls work deep below the world (dungeons)", rag != null and not (rag.root_part as RigidBody3D).freeze and rag.root_part.global_position.y < -4998.4,
		str(rag.root_part.global_position.y) if rag != null else "none")
	# Map speed: roads are cached
	var dbg := get_first_node_in_group("world_map") as WorldDebugMap
	if dbg != null:
		dbg._cache_roads()
		check("map roads are cached once", dbg._road_lines.size() > 0)
	# Saving it all
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var data := sm.build_save_data()
	check("saves hold the character, rules and afflictions", data["player"].has("character") and data["player"].has("afflictions") and data["player"].has("survival") and data.has("rules"))
	GameRules.reset()
	CharacterSetup.pending = {}
