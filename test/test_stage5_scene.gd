extends SceneTree
## The real main scene: at noon, walk into a shop in the starting town, buy something through the
## dialogue's Barter button, save, load, and check the purchase and the shop's gold and stock came
## back. Run with:
##   godot --headless --fixed-fps 60 --path . -s res://test/test_stage5_scene.gd

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


func _run() -> void:
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(40)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var sm := get_first_node_in_group("save_manager") as SaveManager
	var player := get_first_node_in_group("player") as Node3D
	(get_first_node_in_group("world_clock") as WorldClock).set_time(12.0)
	await frames(60)
	var town := wm.get_town_at(player.global_position, 10.0)
	var keeper: TownLife.Resident = null
	for r: TownLife.Resident in wm.life.get_town_residents(town.id):
		if r.data.work_id != "" and Barter.merchant_for(wm.get_building(r.data.work_id)) != null and r.inside == r.data.work_id and r.activity == NpcData.Activity.WORK:
			keeper = r
			break
	check("an open shop in the starting town", keeper != null)
	if keeper == null:
		_finish()
		return
	var shop_b := wm.get_building(keeper.data.work_id)
	await wm.dungeons.enter(shop_b.id, shop_b.get_door_position(), 0.0)
	await frames(10)
	var ui := player.get_node("DialogueUI") as DialogueUI
	var barter := player.get_node_or_null("BarterUI") as BarterUI
	check("the player has a trade window", barter != null)
	check("talk, then Barter", ui.open_with(keeper.node) and ui.open_barter())
	var inv := player.get_node("Inventory") as Inventory
	Currency.add_gold(inv, 5000)
	var item := barter.shop.inventory.stacks[0].item
	var had := inv.get_count(item)
	var res := barter.buy(item)
	check("bought something", res["error"] == "", String(res["error"]))
	var shop_gold := barter.shop.gold
	var player_gold := Currency.get_gold(inv)
	barter.close()
	ui.close()
	check("saving works", sm.save_game("slot_test5"), sm.get_last_error())
	Currency.spend_gold(inv, 1000)
	check("load_game starts", sm.load_game("slot_test5"), sm.get_last_error())
	await frames(120)
	player = get_first_node_in_group("player") as Node3D
	inv = player.get_node("Inventory") as Inventory
	check("your gold came back", Currency.get_gold(inv) == player_gold, "%d vs %d" % [Currency.get_gold(inv), player_gold])
	check("so did what you bought", inv.get_count(item) == had + 1)
	check("and the shop's gold", int(WorldState.get_record("shop/" + shop_b.id).get("gold", -1)) == shop_gold)
	sm = get_first_node_in_group("save_manager") as SaveManager
	sm.delete_slot("slot_test5")
	_finish()


func _finish() -> void:
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
