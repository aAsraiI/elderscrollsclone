extends SceneTree
## Headless tests for stage 5: treasure, merchants, prices, stock and gold, the trade window. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage5.gd

const R := "res://scripts/Resources/"
const M := "res://scripts/Resources/Merchants/"

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
		await physics_frame


func secs(s: float) -> void:
	await frames(int(round(s * 60.0)))


func _run() -> void:
	await process_frame
	t_treasure()
	t_prices()
	t_shop()
	await t_world()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- pure logic

func t_treasure() -> void:
	print("-- treasure")
	var all := ItemCatalog.get_treasures()
	check("there are gems, jewelry and relics", all.size() >= 15, str(all.size()))
	var ok := true
	for i in all.size():
		ok = ok and all[i].treasure and all[i].item_type == ItemData.ItemType.MISC and all[i].weight <= 2.5
		if i > 0:
			ok = ok and all[i].value >= all[i - 1].value
	check("all marked as treasure, light, and sorted cheapest first", ok)
	var low := ItemCatalog.treasure_loot(1, 3)
	var high := ItemCatalog.treasure_loot(30, 40)
	var low_max := 0
	for e in low:
		low_max = maxi(low_max, e.item.value)
	var has_diamond := false
	var coin_chance := 0.0
	var diamond_chance := 1.0
	for e in high:
		if e.item.id == &"diamond":
			has_diamond = true
			diamond_chance = e.chance
		if e.item.id == &"ancient_coin":
			coin_chance = e.chance
	check("low-level chests only hold cheap treasure", low.size() >= 2 and low_max <= 100, str(low_max))
	check("high-level chests can hold diamonds", has_diamond)
	check("valuable treasure is rarer", diamond_chance < coin_chance)
	var dungeon := load(R + "World/Dungeons/crypt.tres") as DungeonData
	var built := DungeonBuilder.build(dungeon, 12345, "test_crypt", 5, 12)
	var chest_treasure := false
	for c in (built["root"] as Node3D).find_children("*", "ContainerComponent", true, false):
		for e in (c as ContainerComponent).contents:
			chest_treasure = chest_treasure or (e.item != null and e.item.treasure)
	check("dungeon chests can hold treasure", chest_treasure)
	(built["root"] as Node3D).free()


func _merchant(key: String) -> MerchantData:
	return load(M + key + ".tres") as MerchantData


func _deal(speech: int, disp: int) -> Barter.Deal:
	var d := Barter.Deal.new()
	d.speech = speech
	d.disposition = disp
	return d


func t_prices() -> void:
	print("-- prices")
	var general := _merchant("general")
	var smith := _merchant("smith")
	var jeweler := _merchant("jeweler")
	var temple := _merchant("temple")
	var sword := load(R + "iron_sword.tres") as ItemData
	var bread := load(R + "Consumables/bread.tres") as ItemData
	var ruby := load(R + "Treasure/ruby.tres") as ItemData
	var key := KeyRing.get_key("t/b1", "Test House")
	var gold := load(R + "Consumables/gold.tres") as ItemData
	check("every kind of shop exists", general != null and smith != null and jeweler != null and temple != null and _merchant("alchemy") != null and _merchant("pawnbroker") != null and _merchant("provisioner") != null and _merchant("innkeeper") != null)
	check("a general store buys anything", general.will_buy(sword) and general.will_buy(bread) and general.will_buy(ruby))
	check("a smith buys weapons, not bread", smith.will_buy(sword) and not smith.will_buy(bread))
	check("a jeweler buys treasure, not swords", jeweler.will_buy(ruby) and not jeweler.will_buy(sword))
	check("a temple buys nothing", not temple.will_buy(sword) and not temple.will_buy(ruby))
	check("nobody buys keys or gold", not general.will_buy(key) and not general.will_buy(gold))

	var always_less := true
	for m in [general, smith, jeweler, _merchant("pawnbroker"), _merchant("innkeeper")]:
		for item in [sword, bread, ruby, load(R + "Weapons/ebon_greatsword.tres")]:
			for speech in [1, 50, 100]:
				for disp in [0, 50, 100]:
					var d := _deal(speech, disp)
					d.buy_mult = 0.9
					d.sell_mult = 1.1
					var s := Barter.sell_price(item, m, d)
					if s > 0 and s >= Barter.buy_price(item, m, d):
						always_less = false
	check("a merchant never pays as much as they charge (no free money)", always_less)
	check("better Speech: cheaper to buy", Barter.buy_price(sword, smith, _deal(80, 50)) < Barter.buy_price(sword, smith, _deal(5, 50)))
	check("better Speech: more when selling", Barter.sell_price(sword, smith, _deal(80, 50)) > Barter.sell_price(sword, smith, _deal(5, 50)))
	check("a merchant who likes you charges less", Barter.buy_price(sword, smith, _deal(10, 90)) < Barter.buy_price(sword, smith, _deal(10, 20)))
	check("and pays more", Barter.sell_price(ruby, jeweler, _deal(10, 90)) > Barter.sell_price(ruby, jeweler, _deal(10, 20)))
	var d50 := _deal(10, 50)
	check("treasure sells best at a jeweler", Barter.sell_price(ruby, jeweler, d50) > Barter.sell_price(ruby, general, d50))
	check("treasure sells for much more of its value than ordinary loot", float(Barter.sell_price(ruby, general, d50)) / ruby.value > float(Barter.sell_price(sword, general, d50)) / sword.value)
	var cheap := _deal(10, 50)
	cheap.buy_mult = 0.8
	check("Speech milestones (buy_price_mult) lower prices", Barter.buy_price(sword, smith, cheap) < Barter.buy_price(sword, smith, d50))
	var member := _deal(10, 50)
	member.guild = 0.1
	check("a guild discount (stage 6) would lower prices too", Barter.buy_price(sword, smith, d50) > Barter.buy_price(sword, smith, member))
	print("   sample: iron sword %d / %d, ruby at the jeweler %d" % [Barter.buy_price(sword, smith, d50), Barter.sell_price(sword, smith, d50), Barter.sell_price(ruby, jeweler, d50)])


func _player_bits() -> Dictionary:
	var stats := Stats.new()
	stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
	var inv := Inventory.new()
	inv.stats = stats
	var eq := Equipment.new()
	eq.inventory = inv
	eq.stats = stats
	var holder := Node.new()
	holder.add_child(stats)
	holder.add_child(inv)
	holder.add_child(eq)
	root.add_child(holder)
	return {"holder": holder, "inv": inv, "eq": eq}


func t_shop() -> void:
	print("-- a shop's stock and gold")
	WorldState.clear()
	var smith := _merchant("smith")
	var s1 := Barter.open_shop("t/smithy", smith, 1, 5, 12)
	var stock1 := s1.inventory.to_dict()
	var gold1 := s1.gold
	check("a new shop gets stock and gold", s1.inventory.stacks.size() > 2 and gold1 >= smith.gold_min and gold1 <= smith.gold_max, "%d stacks, %d gold" % [s1.inventory.stacks.size(), gold1])
	var gear := false
	for st in s1.inventory.stacks:
		gear = gear or st.item.tier >= 2
	check("a smith stocks gear for the land's levels", gear)
	check("the shop is saved in WorldState", WorldState.has_record("shop/t/smithy"))
	Barter.close_shop(s1)
	var s2 := Barter.open_shop("t/smithy", smith, 2, 5, 12)
	check("before restock day, the same stock and gold", s2.inventory.to_dict() == stock1 and s2.gold == gold1)
	Barter.close_shop(s2)
	WorldState.clear()
	var s3 := Barter.open_shop("t/smithy", smith, 1, 5, 12)
	check("the same shop on the same day always rolls the same", s3.inventory.to_dict() == stock1 and s3.gold == gold1)
	Barter.close_shop(s3)

	var bits := _player_bits()
	var inv: Inventory = bits["inv"]
	var eq: Equipment = bits["eq"]
	var shop := Barter.open_shop("t/general", _merchant("general"), 1)
	var d := _deal(10, 50)
	var item: ItemData = shop.inventory.stacks[0].item
	var price := Barter.buy_price(item, shop.data, d)
	var r := Barter.buy(shop, inv, item, 1, d)
	check("no gold, no sale", r["error"] != "" and not inv.has_item(item))
	Currency.add_gold(inv, price * 2)
	var shop_gold := shop.gold
	var on_shelf := shop.inventory.get_count(item)
	r = Barter.buy(shop, inv, item, 1, d)
	check("buying takes your gold and gives you the item", r["error"] == "" and inv.has_item(item) and Currency.get_gold(inv) == price)
	check("the merchant gets the gold and loses the item", shop.gold == shop_gold + price and shop.inventory.get_count(item) == on_shelf - 1)
	r = Barter.buy(shop, inv, item, 99, d)
	check("you can't buy more than you can pay for", Currency.get_gold(inv) >= 0 and int(r["count"]) <= 1)
	var saved := WorldState.get_record("shop/t/general")
	check("every trade is saved", int(saved["gold"]) == shop.gold)

	var ruby := load(R + "Treasure/ruby.tres") as ItemData
	inv.add_item(ruby, 3)
	var gold_before := Currency.get_gold(inv)
	var unit := Barter.sell_price(ruby, shop.data, d)
	shop.gold = unit * 2  # can only afford two
	r = Barter.sell(shop, inv, eq, ruby, 3, d)
	check("a merchant only buys what they can pay for", int(r["count"]) == 2 and inv.get_count(ruby) == 1 and shop.gold == 0 and Currency.get_gold(inv) == gold_before + unit * 2)
	r = Barter.sell(shop, inv, eq, ruby, 1, d)
	check("out of gold: they can't buy", r["error"] != "" and inv.get_count(ruby) == 1)
	shop.gold = 5000
	var sword := load(R + "iron_sword.tres") as ItemData
	inv.add_item(sword)
	eq.equip(sword)
	r = Barter.sell(shop, inv, eq, sword, 1, d)
	check("you can't sell the sword in your hand", r["error"] != "" and inv.has_item(sword))
	inv.add_item(sword)
	r = Barter.sell(shop, inv, eq, sword, 2, d)
	check("with a spare, the spare is sold and the one in hand stays", int(r["count"]) == 1 and inv.get_count(sword) == 1 and eq.is_equipped(sword))
	var key := KeyRing.get_key("t/b9", "Somewhere")
	inv.add_item(key)
	check("keys can't be sold", Barter.sell(shop, inv, eq, key, 1, d)["error"] != "")
	Barter.close_shop(shop)
	(bits["holder"] as Node).queue_free()
	WorldState.clear()


# ---------------------------------------------------------------- in a running world

func make_player(parent: Node) -> CharacterBody3D:
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
	head.add_child(Camera3D.new())
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
	for ui in [DialogueUI.new(), BarterUI.new(), JournalUI.new()]:
		ui.name = ui.get_script().get_global_name()
		p.add_child(ui)
	p.add_to_group("player")
	parent.add_child(p)
	return p


func t_world() -> void:
	print("-- trading in a running world")
	WorldState.clear()
	var holder := Node3D.new()
	holder.name = "WorldHolder"
	root.add_child(holder)
	var player := make_player(holder)
	var inv := player.get_node("Inventory") as Inventory
	var skills := player.get_node("Skills") as Skills
	var ui := player.get_node("DialogueUI") as DialogueUI
	var barter := player.get_node("BarterUI") as BarterUI
	var s := (load(R + "World/multi_biome_world.tres") as WorldSettings).duplicate() as WorldSettings
	s.view_distance_chunks = 3
	s.spawn_radius_chunks = 1
	s.debug_map_enabled = false
	var wm := WorldManager.new()
	wm.name = "World"
	wm.settings = s
	holder.add_child(wm)
	await frames(10)
	wm.clock.set_time(12.0)
	await secs(1.0)

	var shop_names_ok := true
	for t in wm.towns:
		for b in t.town.buildings:
			if b.kind == BuildingPlot.Kind.SHOP:
				shop_names_ok = shop_names_ok and NameGen.TRADES.has(b.trade) and Barter.merchant_for(b) != null
			if b.kind == BuildingPlot.Kind.HOUSE:
				shop_names_ok = shop_names_ok and Barter.merchant_for(b) == null
	check("every shop, inn, smithy and temple has a merchant; houses don't", shop_names_ok)

	# find a town with a smithy
	var smith: TownLife.Resident = null
	var town: PlacedPOI = null
	for t in wm.towns:
		for r: TownLife.Resident in wm.life.get_town_residents(t.id):
			if r.data.role == NpcData.Role.SMITH and smith == null:
				smith = r
				town = t
	check("a smith to trade with", smith != null)
	if smith == null:
		return
	player.global_position = town.position + Vector3(0, 1, 0)
	wm.ensure_area_loaded(town.position, 2)
	await secs(1.0)
	var forge := wm.get_building(smith.data.work_id)
	await wm.dungeons.enter(forge.id, forge.get_door_position(), 0.0)
	await frames(10)
	check("the smith is at work", smith.node != null and is_instance_valid(smith.node) and smith.node_inside)
	check("talking to them", ui.open_with(smith.node))
	check("the Barter button shows, ready", ui._barter_button.visible and not ui._barter_button.disabled)
	check("the trade window opens", ui.open_barter() and barter.is_open() and ui.is_open() and paused)
	check("it shows their stock", barter._left.get_root().get_child_count() > 2)
	var first := barter.shop.inventory.stacks[0].item
	Currency.add_gold(inv, 20000)
	var xp_before := skills.get_xp(&"speech") + skills.get_level(&"speech") * 1000.0
	var res := barter.buy(first)
	check("buying in the window", res["error"] == "" and inv.has_item(first))
	check("trading trains Speech", skills.get_xp(&"speech") + skills.get_level(&"speech") * 1000.0 > xp_before)
	var bread := load(R + "Consumables/bread.tres") as ItemData
	inv.add_item(bread, 2)
	check("a smith won't buy bread", barter.sell(bread)["error"] != "" and inv.get_count(bread) == 2)
	var sold := barter.sell(first)
	check("selling it back gets less than you paid", sold["error"] == "" and int(sold["gold"]) < int(res["gold"]))
	var record := WorldState.get_record("shop/" + forge.id)
	check("the smithy remembers its gold and stock", int(record.get("gold", -1)) == barter.shop.gold)
	barter.close()
	check("closing the trade window goes back to talking, still paused", not barter.is_open() and ui.is_open() and paused)
	ui.close()
	check("then the game goes on", not paused)
	await wm.dungeons.exit()
	await frames(5)

	# after closing time
	wm.clock.set_time(smith.data.work_end + 0.5)
	await secs(1.0)
	var speaker := DialogueEngine.Speaker.new()
	speaker.data = smith.data
	speaker.id = smith.data.id
	var status := Barter.trade_status(speaker, wm)
	check("after hours the smith won't trade", status["merchant"] != null and not status["open"] and String(status["why"]).begins_with("Open "))
	check("the trade window refuses to open", not barter.open_for(speaker))
	holder.queue_free()
	await frames(2)
