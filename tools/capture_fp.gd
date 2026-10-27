extends SceneTree
## A strip of first-person shots of one move, for checking the arms (FirstPersonArms).
##   godot --path . -s res://tools/capture_fp.gd -- out.png <loadout> <action> [shots] [every]
## loadout, joined with "+": sword shield greatsword spear dagger bow fists firebolt (left hand)
##   rfirebolt (right hand), e.g. sword+shield, sword+dagger, greatsword, firebolt+rfirebolt
## action: idle light light2 heavy block bash cast dual bow offhand

const W := "res://data/weapons/"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var loadout := args[1].split("+")
	var action := args[2]
	var shots := int(args[3]) if args.size() > 3 else 6
	var every := int(args[4]) if args.size() > 4 else 6
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	world.add_child(floor_body)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.set("spawn_test_enemy", false)
	world.add_child(p)
	for i in 10:
		await process_frame
	(p.get_node("Stats") as Stats).invulnerable = true
	var eq := p.get_node("Equipment") as Equipment
	var inv := p.get_node("Inventory") as Inventory
	var book := p.get_node("Spellbook") as Spellbook
	for slot in [ItemData.EquipSlot.MAIN_HAND, ItemData.EquipSlot.OFF_HAND]:
		if eq.get_equipped(slot) != null:
			eq.unequip(slot)
	var main_done := false
	for what in loadout:
		var item: ItemData = null
		match what:
			"sword": item = load(W + "iron_sword.tres")
			"shield": item = load(W + "iron_shield.tres")
			"greatsword": item = load(W + "iron_greatsword.tres")
			"spear": item = load(W + "iron_spear.tres")
			"dagger": item = load(W + "iron_dagger.tres")
			"bow": item = ItemCatalog.get_bow(1)
			"fists": pass
			_:
				var id := what.trim_prefix("r")
				book.learn(SpellCatalog.get_spell(id), true)
				if what.begins_with("r"):
					book.equip_right(id)
				else:
					book.equip_spell(id)
		if item != null:
			inv.add_item(item)
			if item.item_type == ItemData.ItemType.WEAPON and main_done and not item.two_handed:
				inv.add_item(item)
				eq.equip(item)
			else:
				eq.equip(item)
			main_done = true
	if "bow" in loadout:
		inv.add_item(ItemCatalog.get_arrow(1), 20)
	for i in 20:
		await process_frame
	var combat := p.get_node("MeleeCombat") as MeleeCombat
	var ranged := p.get_node_or_null("RangedCombat") as RangedCombat
	var left := p.get_node_or_null("SpellCaster") as SpellCaster
	var right := p.get_node_or_null("SpellCasterRight") as SpellCaster
	match action:
		"light":
			combat.light_attack()
		"light2":
			combat.light_attack()
			for i in 40:
				await process_frame
				if combat.get_phase() == MeleeCombat.Phase.RECOVERY and combat.get_phase_progress() > 0.6:
					break
			combat.light_attack()
		"heavy":
			combat.begin_charge()
			for i in 50:
				await physics_frame
			combat.release_charge()
		"block", "bash":
			combat.secondary_press()
			if action == "bash":
				for i in 10:
					await physics_frame
				combat.primary_attack()
		"offhand":
			combat.secondary_press()
		"cast":
			left.begin_cast(book.get_equipped())
		"dual":
			left.begin_cast(book.get_equipped())
			right.dual = true
			left.dual = true
			right.begin_cast(book.get_right())
		"bow":
			ranged.begin_draw()
	var frames: Array[Image] = []
	for s in shots:
		for i in every:
			await process_frame
			if action == "block" or action == "offhand":
				combat.secondary_press(true)
		if action in ["cast", "dual"] and s == shots / 2:
			left.release_cast()
			if action == "dual":
				right.release_cast()
		if action == "bow" and s == shots / 2:
			ranged.release()
		var img := root.get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		frames.append(img)
		print("shot %d phase %d progress %.2f kind %d" % [s, combat.get_phase(), combat.get_phase_progress(), combat.get_action_kind()])
		var arms := p.get_node("Head/Camera3D/FirstPersonArms")
		for side in [1, -1]:
			if arms.debug.has(side):
				print("   side %d want %s  got %s" % [side, arms.debug[side], arms.actual(side)])
	var cols := 3
	var fw := frames[0].get_width()
	var fh := frames[0].get_height()
	var sheet := Image.create(fw * cols, fh * int(ceil(frames.size() / float(cols))), false, frames[0].get_format())
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, fw, fh), Vector2i((i % cols) * fw, (i / cols) * fh))
	sheet.save_png(out)
	print("saved ", out)
	quit()
