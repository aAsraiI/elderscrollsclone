class_name BarterUI
extends CanvasLayer
## The trade window. Opens from the dialogue window's Barter button while a shopkeeper, smith,
## innkeeper or priest is at work. Created by player.gd. The game stays paused.
##
##   left    what they sell, at their price          right   your things, at what they'd pay
##   Enter / double-click = trade one     Shift = the whole stack     Tab = switch list
## Things they don't buy show "-". Each trade trains Speech a little.

signal opened
signal closed
signal traded(bought: bool, item: ItemData, count: int, gold: int)

const GOLD := Color(1.0, 0.85, 0.35)

var shop: Barter.Shop
var deal: Barter.Deal

var _open := false
var _player: Node
var _inventory: Inventory
var _equipment: Equipment
var _root: Control
var _title: Label
var _left: Tree
var _right: Tree
var _details: RichTextLabel
var _gold_label: Label
var _message: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 17
	add_to_group("barter_ui")
	_player = get_parent()
	_inventory = _player.get_node_or_null("Inventory") as Inventory
	_equipment = _player.get_node_or_null("Equipment") as Equipment
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _open


## Opens trading with the shop of this speaker. Returns false if they can't trade right now.
func open_for(s: DialogueEngine.Speaker) -> bool:
	if _open or s == null:
		return false
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var status := Barter.trade_status(s, world)
	if status["merchant"] == null or not status["open"]:
		return false
	# a shop in town, or a travelling merchant's pack (no building)
	var b: BuildingPlot = world.get_building(s.data.work_id) if s.data != null else null
	var shop_id := b.id if b != null else String(s.enemy.get_meta("shop_id", "road/" + s.name))
	var shop_name := b.display_name if b != null else "Travelling Merchant"
	if Marriage.is_spouse(s):
		shop_id = Marriage.SHOP_ID
		shop_name = "%s's Shop" % s.name
	var zone := LevelCurve.zone_range(world.map, b.world_pos if b != null else s.position)
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var kind := int((s.town.poi as TownData).kind) if s.town != null and b != null else 1
	var merchant: MerchantData = status["merchant"]
	if Factions.leader_of(s, world) == "thieves" and Factions.is_member("thieves"):
		merchant = merchant.duplicate() as MerchantData  # for guild members the contact is a fence
		merchant.buys_stolen = true
	shop = Barter.open_shop(shop_id, merchant, clock.day if clock != null else 1, zone.x, zone.y, Barter.GOLD_SCALE[clampi(kind, 0, 2)])
	deal = Barter.deal_for(_player, DialogueEngine.get_disposition(s))
	deal.guild = Factions.discount_for(merchant)
	# The town's market (Economy): what the land makes, what you've flooded it with, festivals
	var market_pos := b.world_pos if b != null else s.position
	var town := world.get_town_at(market_pos, 40.0)
	var biome := world.get_biome_at(market_pos.x, market_pos.z)
	var fest := Festivals.current(clock)
	deal.town_id = town.id if town != null else ""
	deal.biome = biome.get_key() if biome != null else ""
	deal.festival = town != null and Festivals.keeps(fest, world, town)
	deal.today = clock.day if clock != null else 1
	_title.text = "%s  ·  %s" % [shop_name, s.name]
	_message.text = Economy.note(deal.town_id, deal.biome, deal.festival, deal.today) if deal.town_id != "" else ""
	_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_left.grab_focus()
	opened.emit()
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	Barter.close_shop(shop)
	shop = null
	var dialogue := get_tree().get_first_node_in_group("dialogue_ui") as DialogueUI
	if dialogue == null or not dialogue.is_open():
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## Buys `count` of an item from the shop (what the left list does)
func buy(item: ItemData, count: int = 1) -> Dictionary:
	var r := Barter.buy(shop, _inventory, item, count, deal)
	_after_trade(r, true, item)
	return r


## Sells `count` of an item to the shop (what the right list does)
func sell(item: ItemData, count: int = 1) -> Dictionary:
	var r := Barter.sell(shop, _inventory, _equipment, item, count, deal)
	_after_trade(r, false, item)
	return r


## Sells every junk item (clutter like tankards and plates) the merchant will buy.
## Returns {"count": items sold, "gold": earned}.
func sell_junk() -> Dictionary:
	var count := 0
	var gold := 0
	var junk: Array[ItemData] = []
	for st in _inventory.stacks:
		if st.item.junk and not junk.has(st.item):
			junk.append(st.item)
	for item in junk:
		var r := Barter.sell(shop, _inventory, _equipment, item, _inventory.get_count(item), deal)
		if r["error"] == "":
			count += int(r["count"])
			gold += int(r["gold"])
	if count > 0:
		_message.text = "Sold %d pieces of junk for %d gold" % [count, gold]
		_message.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		var skills := _player.get_node_or_null("Skills") as Skills
		if skills != null:
			skills.add_xp(&"speech", maxf(float(gold) / 40.0, 0.5))
	else:
		_message.text = "Nothing they want to buy."
		_message.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_refresh()
	return {"count": count, "gold": gold}


func _after_trade(r: Dictionary, bought: bool, item: ItemData) -> void:
	if r["error"] != "":
		_message.text = r["error"]
		_message.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		_message.text = "%s %s%s for %d gold" % ["Bought" if bought else "Sold", item.display_name, " x%d" % r["count"] if r["count"] > 1 else "", r["gold"]]
		_message.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		var skills := _player.get_node_or_null("Skills") as Skills
		if skills != null:
			skills.add_xp(&"speech", maxf(float(r["gold"]) / 40.0, 0.5))
		traded.emit(bought, item, r["count"], r["gold"])
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_E):
		_trade_selected(Input.is_key_pressed(KEY_SHIFT))
	else:
		return
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- lists

func _refresh() -> void:
	if not _open or shop == null:
		return
	_fill(_left, shop.inventory, true)
	_fill(_right, _inventory, false)
	_gold_label.text = "Your gold: %d      %s's gold: %d" % [Currency.get_gold(_inventory), shop.data.display_name, shop.gold]
	_update_details()


func _fill(tree: Tree, source: Inventory, selling_to_you: bool) -> void:
	var idx := 0
	var selected := tree.get_selected()
	if selected != null:
		idx = selected.get_index()
	tree.clear()
	var root := tree.create_item()
	var totals := {}
	var order: Array[ItemData] = []
	for s in source.stacks:
		if s.item.id == &"gold":
			continue
		if not totals.has(s.item):
			order.append(s.item)
		totals[s.item] = int(totals.get(s.item, 0)) + s.count
	for item in order:
		var row := tree.create_item(root)
		var count: int = totals[item]
		row.set_metadata(0, {"item": item, "count": count})
		var equipped := not selling_to_you and _equipment != null and _equipment.is_equipped(item)
		row.set_text(0, "E" if equipped else "")
		row.set_text(1, item.display_name + (" (%d)" % count if count > 1 else ""))
		var stolen := 0 if selling_to_you else CrimeManager.stolen_count(source, item)
		if stolen > 0:
			row.set_text(1, row.get_text(1) + ("  [stolen]" if stolen >= count else "  [%d stolen]" % stolen))
		row.set_text(2, "%.1f" % item.weight)
		var price := Barter.buy_price(item, shop.data, deal) if selling_to_you else Barter.sell_price(item, shop.data, deal)
		if not selling_to_you and stolen >= count and not shop.data.buys_stolen:
			price = 0
		row.set_text(3, str(price) if price > 0 else "-")
		if price <= 0:
			for c in 4:
				row.set_custom_color(c, Color(1, 1, 1, 0.35))
		elif item.treasure:
			row.set_custom_color(1, GOLD)
		row.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		row.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
	var n := root.get_child_count()
	if n > 0:
		var target := root.get_child(clampi(idx, 0, n - 1))
		target.select(0)
		tree.scroll_to_item(target)


func _active_tree() -> Tree:
	return _right if _right.has_focus() else _left


func _trade_selected(whole_stack: bool) -> void:
	var tree := _active_tree()
	var row := tree.get_selected()
	if row == null:
		return
	var data: Dictionary = row.get_metadata(0)
	var count: int = data["count"] if whole_stack else 1
	if tree == _left:
		buy(data["item"], count)
	else:
		sell(data["item"], count)


func _update_details() -> void:
	var row := _active_tree().get_selected()
	if row == null or shop == null:
		_details.text = ""
		return
	var item: ItemData = row.get_metadata(0)["item"]
	var t := "[b][font_size=20]%s[/font_size][/b]   [color=gray]value %d[/color]\n" % [item.display_name, item.value]
	if item.description != "":
		t += item.description + "\n"
	var buy_p := Barter.buy_price(item, shop.data, deal)
	var sell_p := Barter.sell_price(item, shop.data, deal)
	t += "[color=#e8c46a]Buy for %d" % buy_p
	t += ("   ·   Sell for %d" % sell_p) if sell_p > 0 else "   ·   %s won't buy this" % shop.data.display_name
	t += "[/color]"
	if item.treasure:
		t += "\n[color=#e8c46a]Treasure: jewelers and pawnbrokers pay the most for it.[/color]"
	_details.text = t


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 600)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_title)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	vbox.add_child(columns)
	for side in 2:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(box)
		var label := Label.new()
		label.text = "For sale" if side == 0 else "Your things"
		label.add_theme_color_override("font_color", GOLD)
		box.add_child(label)
		var tree := _make_tree("Price" if side == 0 else "They pay")
		box.add_child(tree)
		if side == 0:
			_left = tree
		else:
			_right = tree
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(0, 86)
	vbox.add_child(_details)
	var bottom := HBoxContainer.new()
	vbox.add_child(bottom)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", GOLD)
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_gold_label)
	_message = Label.new()
	bottom.add_child(_message)
	var junk := Button.new()
	junk.text = "Sell all junk"
	junk.focus_mode = Control.FOCUS_NONE
	junk.pressed.connect(sell_junk)
	bottom.add_child(junk)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 34)
	done.pressed.connect(close)
	bottom.add_child(done)
	var hints := Label.new()
	hints.text = "[Enter / E / double-click] Trade one   [Shift] Whole stack   [Tab] Switch list   [Esc] Done"
	hints.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(hints)


func _make_tree(price_title: String) -> Tree:
	var t := Tree.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.columns = 4
	t.hide_root = true
	t.hide_folding = true
	t.column_titles_visible = true
	t.select_mode = Tree.SELECT_ROW
	t.allow_search = false
	t.set_column_title(0, "")
	t.set_column_title(1, "Name")
	t.set_column_title(2, "Wt")
	t.set_column_title(3, price_title)
	t.set_column_expand(0, false)
	t.set_column_custom_minimum_width(0, 30)
	t.set_column_expand(2, false)
	t.set_column_custom_minimum_width(2, 60)
	t.set_column_expand(3, false)
	t.set_column_custom_minimum_width(3, 80)
	t.item_selected.connect(_update_details)
	t.focus_entered.connect(_update_details)
	t.item_activated.connect(func() -> void: _trade_selected(Input.is_key_pressed(KEY_SHIFT)))
	return t
