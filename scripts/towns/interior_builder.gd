class_name InteriorBuilder
extends RefCounted
## The inside of a town building: one room sized from the building, lit by warm lamps, with
## placeholder furniture that depends on what the building is (beds and a hearth in a house, a
## counter and shelves in a shop, pews in a temple...) and the owner's chest. Built from the
## building's seed, so it is the same every visit; chests remember their contents through
## WorldState. DungeonManager builds it far below the world when the player walks in.
##
## Local space: the middle of the floor is the origin, the way out is in the -Z wall.

const WALL := 0.4
const AMBIENT := Color(0.16, 0.13, 0.10)
const LAMP_COLOR := Color(1.0, 0.78, 0.5)
const WOOD := Color(0.42, 0.28, 0.16)
const DARK_WOOD := Color(0.28, 0.18, 0.10)
const CLOTH := Color(0.55, 0.20, 0.18)
const STONE := Color(0.40, 0.39, 0.37)


## Castle Dawnhold in Kingsreach is the one hand-built interior (made by tools/build_dawnhold.gd,
## then yours to edit in the editor)
const DAWNHOLD := "Castle Dawnhold"
const DAWNHOLD_SCENE := "res://scenes/world/castle_dawnhold.tscn"


## Returns {"root": Node3D, "start": Vector3, "start_yaw": float, "ambient": Color, "chests": int}
static func build(b: BuildingPlot, interior_seed: int, level: int = 5, today: int = 1) -> Dictionary:
	if b.kind == BuildingPlot.Kind.SEAT and b.display_name == DAWNHOLD and ResourceLoader.exists(DAWNHOLD_SCENE):
		return _dawnhold(b, interior_seed, level)
	var rng := RandomNumberGenerator.new()
	rng.seed = interior_seed
	var module := InteriorOverrides.building_scene(b)  # a hand-made one wins
	if module == "":
		module = pick_module(b, rng)
	if module != "":
		return _from_module(b, module, interior_seed, level, today, rng)
	var w := maxf(b.size.x + 1.5, 7.0)
	var d := maxf(b.size.z + 1.5, 6.5)
	var arena := b.kind == BuildingPlot.Kind.GUILD_HALL and b.guild == "fighters"
	if arena:  # room for the sand pit (Arena)
		w = maxf(w, 16.0)
		d = maxf(d, 22.0)
	var h := 3.4
	match b.kind:
		BuildingPlot.Kind.TEMPLE:
			h = 6.5
		BuildingPlot.Kind.INN, BuildingPlot.Kind.GUILD_HALL:
			h = 4.2
		BuildingPlot.Kind.SEAT:
			h = {"castle": 7.0, "keep": 5.5, "tower": 4.2}.get(b.seat_type, 3.6)
	var stone_hall := b.kind == BuildingPlot.Kind.TEMPLE or (b.kind == BuildingPlot.Kind.SEAT and b.seat_type != "reeve")
	var root := Node3D.new()
	root.name = "Interior"
	root.set_meta("building_id", b.id)

	var floor_color := WOOD.darkened(0.25) if not stone_hall else STONE.lightened(0.1)
	var wall_color := Color(0.55, 0.47, 0.36) if not stone_hall else STONE.lightened(0.25)
	POIBuilder.add_box(root, Vector3(w + WALL * 2.0, WALL, d + WALL * 2.0), Vector3(0.0, -WALL * 0.5, 0.0), floor_color)
	POIBuilder.add_box(root, Vector3(w + WALL * 2.0, WALL, d + WALL * 2.0), Vector3(0.0, h + WALL * 0.5, 0.0), wall_color.darkened(0.35))
	for z in [-d * 0.5 - WALL * 0.5, d * 0.5 + WALL * 0.5]:
		POIBuilder.add_box(root, Vector3(w + WALL * 2.0, h, WALL), Vector3(0.0, h * 0.5, z), wall_color)
	for x in [-w * 0.5 - WALL * 0.5, w * 0.5 + WALL * 0.5]:
		POIBuilder.add_box(root, Vector3(WALL, h, d), Vector3(x, h * 0.5, 0.0), wall_color.darkened(0.08))
	# Ceiling beams
	var beams := int(d / 2.5)
	for i in beams:
		POIBuilder.add_box(root, Vector3(w, 0.25, 0.3), Vector3(0.0, h - 0.13, -d * 0.5 + (float(i) + 0.5) * d / float(beams)), DARK_WOOD, 0.0, Vector3.ZERO, false)

	# Lamps, one every 7 m or so
	var lamps_x := maxi(int(round(w / 7.0)), 1)
	var lamps_z := maxi(int(round(d / 7.0)), 1)
	for ix in lamps_x:
		for iz in lamps_z:
			var lamp := OmniLight3D.new()
			lamp.light_color = LAMP_COLOR
			lamp.light_energy = 1.4
			lamp.omni_range = maxf(w / float(lamps_x), d / float(lamps_z)) * 1.3 + 2.0
			lamp.position = Vector3(-w * 0.5 + (float(ix) + 0.5) * w / float(lamps_x), h - 0.6, -d * 0.5 + (float(iz) + 0.5) * d / float(lamps_z))
			root.add_child(lamp)

	# The way out
	var door_z := -d * 0.5
	POIBuilder.add_box(root, Vector3(1.6, 2.4, 0.12), Vector3(0.0, 1.2, door_z + 0.06), DARK_WOOD, 0.0, Vector3.ZERO, false)
	var exit := DungeonDoor.new()
	exit.name = "Exit"
	exit.entrance_id = b.id
	exit.label = "Leave %s" % b.display_name
	exit.is_exit = true
	root.add_child(exit)
	exit.position = Vector3(0.0, 1.3, door_z + 0.7)

	var chests := 0
	var beds: Array[Vector3] = []
	var stations: Array[Vector3] = []
	var seats: Array[Vector3] = []
	var work := Vector3(0.0, 0.0, 0.0)
	match b.kind:
		BuildingPlot.Kind.HOUSE, BuildingPlot.Kind.FARM:
			beds.append(_bed(root, Vector3(-w * 0.5 + 0.8, 0.0, d * 0.5 - 1.2)))
			if rng.randf() < 0.5 or b.kind == BuildingPlot.Kind.FARM:
				beds.append(_bed(root, Vector3(-w * 0.5 + 2.2, 0.0, d * 0.5 - 1.2)))
			seats.append_array(_table(root, Vector3(w * 0.12, 0.0, 0.2), 2))
			work = Vector3(w * 0.5 - 1.6, 0.0, -0.8)
			_hearth(root, Vector3(w * 0.5 - 0.5, 0.0, 0.0))
			stations.append(_station(root, "cooking_pot", Vector3(w * 0.5 - 1.4, 0.0, 1.4)))
			_furn(root, "wardrobe", Vector3(1.6, 1.8, 0.45), Vector3(w * 0.5 - 1.3, 0.9, d * 0.5 - 0.3), WOOD, PI)
			if b.kind == BuildingPlot.Kind.FARM:
				for i in 3:
					_furn(root, "crate", Vector3(0.7, 0.9, 0.7), Vector3(-w * 0.5 + 0.6 + float(i) * 0.8, 0.45, -d * 0.5 + 1.0), DARK_WOOD)
			chests += _chest(root, b, 0, "%s's Chest" % NameGen.first_name(b.owner_name), Vector3(-w * 0.5 + 0.8, 0.35, d * 0.5 - 2.7), _home_loot(), interior_seed)
		BuildingPlot.Kind.SHOP:
			_furn(root, "counter", Vector3(w * 0.6, 1.0, 0.7), Vector3(0.0, 0.5, d * 0.1), WOOD, PI)
			_furn(root, "bookcase", Vector3(w - 1.5, 2.4, 0.5), Vector3(0.0, 1.2, d * 0.5 - 0.3), DARK_WOOD, PI)
			for i in 4:
				_furn(root, "crate", Vector3(0.6, 0.6, 0.6), Vector3(-w * 0.5 + 0.7, 0.3 + float(i % 2) * 0.6, -d * 0.2 + float(i / 2) * 0.7), WOOD.lightened(0.1))
			work = Vector3(0.0, 0.0, d * 0.1 + 1.0)
			beds.append(_bed(root, Vector3(w * 0.5 - 0.8, 0.0, -d * 0.5 + 1.6)))
			chests += _chest(root, b, 0, "Merchant Chest", Vector3(w * 0.25, 0.35, d * 0.5 - 1.1), _shop_loot(), interior_seed)
			if b.trade == "alchemy":
				stations.append(_station(root, "alchemy_lab", Vector3(-w * 0.5 + 0.5, 0.0, d * 0.3), PI * 0.5))
			elif b.trade == "jeweler":
				stations.append(_station(root, "workbench", Vector3(-w * 0.5 + 0.5, 0.0, d * 0.3), PI * 0.5))
		BuildingPlot.Kind.INN:
			_furn(root, "counter", Vector3(0.7, 1.1, d * 0.45), Vector3(-w * 0.5 + 1.8, 0.55, d * 0.05), WOOD, PI * 0.5)
			_furn(root, "keg_rack", Vector3(0.5, 2.0, d * 0.45), Vector3(-w * 0.5 + 0.3, 1.0, d * 0.05), DARK_WOOD, PI * 0.5)
			for i in 3:
				seats.append_array(_table(root, Vector3(w * 0.05 + float(i % 2) * w * 0.25, 0.0, -d * 0.2 + float(i) * d * 0.15), 4))
			_hearth(root, Vector3(w * 0.5 - 0.5, 0.0, -d * 0.15))
			stations.append(_station(root, "cooking_pot", Vector3(w * 0.5 - 1.3, 0.0, -d * 0.15 + 1.5)))
			POIBuilder.add_box(root, Vector3(0.2, h, 2.8), Vector3(w * 0.12, h * 0.5, d * 0.5 - 1.4), wall_color.darkened(0.1))
			beds.append(_bed(root, Vector3(w * 0.12 + 0.8, 0.0, d * 0.5 - 1.2)))
			beds.append(_bed(root, Vector3(w * 0.12 + 2.2, 0.0, d * 0.5 - 1.2)))
			work = Vector3(-w * 0.5 + 1.05, 0.0, d * 0.05)
			chests += _chest(root, b, 0, "Innkeeper's Chest", Vector3(-w * 0.5 + 0.9, 0.35, -d * 0.3), _shop_loot(), interior_seed)
			NoticeBoard.make(root, Vector3(w * 0.5 - 0.15, 0.0, d * 0.3), -PI * 0.5, b.town_id)  # the townsfolk's jobs
		BuildingPlot.Kind.SMITHY:
			# The smith's workstations: forge, smelter, tanning rack, grindstone, workbench
			stations.append(_station(root, "forge", Vector3(w * 0.5 - 1.2, 0.0, d * 0.5 - 1.2)))
			stations.append(_station(root, "smelter", Vector3(w * 0.5 - 0.8, 0.0, d * 0.5 - 3.0)))
			stations.append(_station(root, "tanning_rack", Vector3(-w * 0.5 + 0.3, 0.0, -d * 0.5 + 2.0), PI * 0.5))
			stations.append(_station(root, "grindstone", Vector3(-w * 0.25, 0.0, -d * 0.5 + 0.8)))
			stations.append(_station(root, "workbench", Vector3(w * 0.2, 0.0, -d * 0.5 + 0.6)))
			_furn(root, "anvil", Vector3(1.0, 0.75, 0.4), Vector3(0.0, 0.375, 0.6), Color(0.22, 0.22, 0.25))
			_furn(root, "rack", Vector3(2.4, 1.8, 0.3), Vector3(-w * 0.5 + 1.5, 0.9, d * 0.5 - 0.2), DARK_WOOD, PI)
			work = Vector3(0.0, 0.0, 1.5)
			beds.append(_bed(root, Vector3(w * 0.5 - 0.8, 0.0, -d * 0.5 + 1.6)))
			chests += _chest(root, b, 0, "Smith's Chest", Vector3(-w * 0.5 + 0.8, 0.35, 0.0), _shop_loot(), interior_seed)
		BuildingPlot.Kind.TEMPLE:
			_furn(root, "altar", Vector3(2.6, 1.1, 1.0), Vector3(0.0, 0.55, d * 0.5 - 1.3), STONE.lightened(0.3), PI)
			POIBuilder.add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(0.0, 1.5, d * 0.5 - 1.3), Color(1.0, 0.85, 0.5), 0.7, Vector3(0.4, 0.0, 0.4), false, true)
			var rows := int((d - 5.0) / 1.6)
			for i in rows:
				for side in [-1.0, 1.0]:
					_furn(root, "bench", Vector3(w * 0.32, 0.5, 0.45), Vector3(side * w * 0.24, 0.25, -d * 0.5 + 3.0 + float(i) * 1.6), WOOD)
			work = Vector3(0.0, 0.0, d * 0.5 - 2.4)
			beds.append(_bed(root, Vector3(-w * 0.5 + 0.8, 0.0, -d * 0.5 + 1.6)))
			for i in rows:
				seats.append(Vector3(-w * 0.24, 0.0, -d * 0.5 + 2.4 + float(i) * 1.6))
			chests += _chest(root, b, 0, "Offering Box", Vector3(w * 0.5 - 0.8, 0.35, d * 0.5 - 1.0), _offering_loot(), interior_seed)
			stations.append(_station(root, "alchemy_lab", Vector3(w * 0.5 - 0.45, 0.0, -d * 0.5 + 2.0), PI * 0.5))
		BuildingPlot.Kind.GUILD_HALL:
			if not arena:
				_furn(root, "table", Vector3(1.2, 0.8, d * 0.45), Vector3(0.0, 0.4, d * 0.05), WOOD)
				for side in [-1.0, 1.0]:
					_furn(root, "bench", Vector3(0.4, 0.45, d * 0.45), Vector3(side * 1.0, 0.225, d * 0.05), DARK_WOOD)
			var banner: Color = TownBuilder.GUILD_COLORS.get(b.guild, CLOTH)
			for x in [-w * 0.25, w * 0.25]:
				POIBuilder.add_box(root, Vector3(1.2, 2.4, 0.06), Vector3(x, h * 0.55, d * 0.5 - 0.05), banner, 0.0, Vector3.ZERO, false)
			match b.guild:
				"fighters":
					for i in 2:
						_furn(root, "training_dummy", Vector3(0.6, 1.7, 0.6), Vector3(w * 0.5 - 1.2, 0.85, -d * 0.2 + float(i) * 2.0), Color(0.6, 0.5, 0.3), -PI * 0.5)
					# The arena: a sand pit ringed by a low wall (open toward the door), the gong
					# at its near edge, benches for the crowd along the side walls
					var pit := Vector3(0.0, 0.0, d * 0.5 - 6.5)
					POIBuilder.add_box(root, Vector3(10.0, 0.04, 10.0), pit + Vector3(0.0, 0.02, 0.0), Color(0.72, 0.62, 0.42), 0.0, Vector3.ZERO, false)
					for k in 16:
						var a := float(k) / 16.0 * TAU
						if absf(wrapf(a - PI * 1.5, -PI, PI)) < 0.3:
							continue
						POIBuilder.add_box(root, Vector3(2.0, 0.7, 0.3), pit + Vector3(cos(a), 0.0, sin(a)) * 5.0 + Vector3(0.0, 0.35, 0.0), DARK_WOOD, -a + PI * 0.5)
					Arena.make(root, pit + Vector3(2.2, 0.0, -5.6), pit)
					for k in 8:
						stations.append(pit + Vector3(cos(float(k) * TAU / 8.0), 0.0, sin(float(k) * TAU / 8.0)) * 3.5)
					stations.append(pit)
					stations.append(pit + Vector3(2.2, 0.0, -5.6))
					for side in [-1.0, 1.0]:
						_furn(root, "bench", Vector3(0.6, 0.45, 8.0), Vector3(side * (w * 0.5 - 0.6), 0.225, pit.z), WOOD)
				"antiquarians":
					stations.append(_station(root, "grindstone", Vector3(-w * 0.3, 0.0, -d * 0.5 + 0.8)))
					stations.append(_station(root, "workbench", Vector3(w * 0.25, 0.0, -d * 0.5 + 0.6)))
					var case := MuseumCase.new()
					case.name = "MuseumCase"
					root.add_child(case)
					case.position = Vector3(w * 0.5 - 1.0, 0.0, -d * 0.1)
					case.rotation.y = PI * 0.5
				"mages":
					for side in [-1.0, 1.0]:
						_furn(root, "bookcase", Vector3(0.5, 2.6, d * 0.5), Vector3(side * (w * 0.5 - 0.3), 1.3, 0.0), DARK_WOOD, -side * PI * 0.5)
					POIBuilder.add_box(root, Vector3(0.4, 0.4, 0.4), Vector3(0.0, 1.2, d * 0.35), Color(0.4, 0.6, 1.0), 0.5, Vector3(0.4, 0.0, 0.4), false, true)
					stations.append(_station(root, "spell_altar", Vector3(w * 0.25, 0.0, -d * 0.5 + 1.2)))
					stations.append(_station(root, "enchanter", Vector3(-w * 0.25, 0.0, -d * 0.5 + 1.2)))
					stations.append(_station(root, "alchemy_lab", Vector3(w * 0.2, 0.0, d * 0.5 - 0.6)))
				_:
					for i in 2:
						_furn(root, "armor_stand", Vector3(0.7, 1.9, 0.5), Vector3(w * 0.5 - 0.8, 0.95, -d * 0.2 + float(i) * 2.0), Color(0.62, 0.62, 0.66), -PI * 0.5)
			work = Vector3(0.0, 0.0, d * 0.05 + d * 0.225 + 0.8)
			beds.append(_bed(root, Vector3(-w * 0.5 + 0.8, 0.0, -d * 0.5 + 1.6)))
			for i in 4:
				seats.append(Vector3(1.6 * (1.0 if i % 2 == 0 else -1.0), 0.0, d * 0.05 + (float(i / 2) - 0.5) * 2.0))
			if arena:  # the fighters watch from the benches; the master stands by the gong
				work = Vector3(3.4, 0.0, d * 0.5 - 12.4)
				for i in 4:
					seats[i] = Vector3((w * 0.5 - 0.6) * (1.0 if i % 2 == 0 else -1.0), 0.0, d * 0.5 - 6.5 + (float(i / 2) - 0.5) * 3.0)
			chests += _chest(root, b, 0, "Guild Chest", Vector3(-w * 0.5 + 0.8, 0.35, d * 0.5 - 1.0), _shop_loot(), interior_seed)
		BuildingPlot.Kind.SEAT:
			# The lord's high seat on a dais at the far end, under the house banners
			var banner := NamedSettlements.house_color(b.house)
			var dais_w := minf(w * 0.5, 7.0)
			POIBuilder.add_box(root, Vector3(dais_w, 0.4, 2.6), Vector3(0.0, 0.2, d * 0.5 - 1.3), STONE.darkened(0.1))
			_furn(root, "throne", Vector3(1.2, 2.0, 1.0), Vector3(0.0, 1.4, d * 0.5 - 0.85), DARK_WOOD, PI)
			for x in [-dais_w * 0.35, dais_w * 0.35]:
				POIBuilder.add_box(root, Vector3(1.2, minf(h * 0.55, 3.4), 0.06), Vector3(x, h * 0.55, d * 0.5 - 0.05), banner, 0.0, Vector3.ZERO, false)
			# A long table down the hall for council and petitioners (not in a reeve's small house)
			if b.seat_type != "reeve":
				var table_d := maxf(d - 7.5, 2.0)
				_furn(root, "table", Vector3(1.4, 0.8, table_d), Vector3(0.0, 0.4, 0.0), WOOD)
				for side in [-1.0, 1.0]:
					_furn(root, "bench", Vector3(0.4, 0.45, table_d), Vector3(side * 1.1, 0.225, 0.0), DARK_WOOD)
				for i in 4:
					seats.append(Vector3(1.6 * (1.0 if i % 2 == 0 else -1.0), 0.0, (float(i / 2) - 0.5) * minf(table_d * 0.5, 3.0)))
			else:
				seats.append_array(_table(root, Vector3(w * 0.15, 0.0, -d * 0.1), 2))
				_hearth(root, Vector3(w * 0.5 - 0.5, 0.0, 0.0))
			work = Vector3(0.0, 0.0, d * 0.5 - 3.0)  # before the high seat, hearing petitions
			beds.append(_bed(root, Vector3(-w * 0.5 + 0.8, 0.0, -d * 0.5 + 1.6)))
			# The town's bounty board by the door (BountyBoard)
			var board := BountyBoard.make(root, Vector3(w * 0.5 - 0.15, 0.0, -d * 0.5 + 1.6), -PI * 0.5, b.town_id)
			stations.append(board.position)
			var chest_name := "Tithe Chest" if b.seat_type == "reeve" else "Treasury Chest"
			chests += _chest(root, b, 0, chest_name, Vector3(w * 0.5 - 0.8, 0.35, d * 0.5 - 1.0), _shop_loot(), interior_seed)
			# The town's lorebooks, on the lord's bookshelf (LoreBooks)
			var books := LoreBooks.for_town(b.town_name)
			if not books.is_empty():
				var loot: Array[LootEntry] = []
				for id in books:
					var le := LootEntry.new()
					le.item = LoreBooks.get_item(id)
					loot.append(le)
				var shelf := POIBuilder.make_chest("Bookshelf", loot, "building/%s/lore" % b.id, interior_seed | 1)
				root.add_child(shelf)
				shelf.position = Vector3(-w * 0.5 + 0.8, 0.35, d * 0.5 - 1.0)
				stations.append(shelf.position)
				chests += 1

	# Furnish the rest of the room and put things on every surface (owned: taking them is theft;
	# guild halls belong to the guild, so members may help themselves)
	var clear_spots: Array[Vector3] = beds.duplicate()
	clear_spots.append_array(stations)
	var owner := b.id if b.kind != BuildingPlot.Kind.GUILD_HALL else "guild:" + b.guild
	var home := Homes.owns(b.id)
	if home:
		owner = ""  # your own home: nothing here is stolen
		stations.append(_station(root, "alchemy_lab", Vector3(-w * 0.5 + 0.45, 0.0, -d * 0.1), PI * 0.5))
		stations.append(_station(root, "workbench", Vector3(w * 0.25, 0.0, -d * 0.5 + 0.6)))
		for i in 2:
			var at := Vector3(-w * 0.2 + float(i) * 1.8, 0.0, -d * 0.5 + 1.4)
			Planter.place(root, at, "planter/%s/%d" % [b.id, i])
			stations.append(at)
		for c in root.get_children():
			var cc := c.get_node_or_null("ContainerComponent") as ContainerComponent
			if cc != null:
				cc.owner_id = ""
				cc.display_name = "Your Chest"
	# Beds you can sleep in, and the temple's shrine
	for bed in beds:
		RestSpot.make_bed(root, bed, b)
	if b.kind == BuildingPlot.Kind.TEMPLE:
		RestSpot.make_shrine(root, Vector3(0.0, 0.0, d * 0.5 - 1.3))
	var decor := RoomDecorator.decorate(root, Rect2(-w * 0.5, -d * 0.5, w, d), theme_for(b, rng), level, interior_seed ^ 0x5eed,
		owner, "building/%s" % b.id, _keep_clear(door_z, work, seats, clear_spots), 3, today, h)

	return {
		"root": root,
		"start": Vector3(0.0, 0.1, door_z + 2.2),
		"start_yaw": PI,  # facing into the room
		"ambient": AMBIENT,
		"chests": chests,
		"decor": decor,
		# where the people who live or work here go (local positions, on the floor)
		"spots": {"exit": Vector3(0.0, 0.1, door_z + 1.4), "beds": beds, "work": work, "seats": seats},
	}


# Castle Dawnhold from its hand-built scene: the way out, the chests and the lore shelf go where the
# scene's markers say; the King and his court use the throne, the council seats and the beds
static func _dawnhold(b: BuildingPlot, interior_seed: int, level: int) -> Dictionary:
	var root := (load(DAWNHOLD_SCENE) as PackedScene).instantiate() as Node3D
	root.name = "Interior"
	root.set_meta("building_id", b.id)
	var marks := root.get_node("Markers")
	var at := func(n: String) -> Vector3: return (marks.get_node(n) as Node3D).position
	var exit := DungeonDoor.new()
	exit.name = "Exit"
	exit.entrance_id = b.id
	exit.label = "Leave %s" % b.display_name
	exit.is_exit = true
	root.add_child(exit)
	exit.position = at.call("Exit")
	var chests := 0
	for c in marks.get_children():
		if not String(c.name).begins_with("Chest_"):
			continue
		var treasury := String(c.name) == "Chest_Treasury"
		var loot: Array[LootEntry] = ItemCatalog.treasure_loot(level, level + 6, 2.0) if treasury else ItemCatalog.curve_loot(level, level + 3)
		loot.append(ItemCatalog.gold_loot(level + (10 if treasury else 0)))
		var chest := POIBuilder.make_chest("Royal Treasury" if treasury else "The King's Chest", loot, "building/%s/%s" % [b.id, c.name], (interior_seed + chests * 104729) | 1)
		chest.set_meta("owner_building", b.id)
		(chest.get_node("ContainerComponent") as ContainerComponent).owner_id = b.id  # the Crown's: taking is stealing
		root.add_child(chest)
		chest.position = (c as Node3D).position + Vector3(0, 0.35, 0)
		chests += 1
	var books := LoreBooks.for_town(b.town_name)
	if not books.is_empty():
		var shelf_loot: Array[LootEntry] = []
		for id in books:
			var le := LootEntry.new()
			le.item = LoreBooks.get_item(id)
			shelf_loot.append(le)
		var shelf := POIBuilder.make_chest("Bookshelf", shelf_loot, "building/%s/lore" % b.id, interior_seed | 1)
		root.add_child(shelf)
		shelf.position = Vector3(-14.0, 0.35, 13.8)  # the Chancellor's shelves
	BountyBoard.make(root, Vector3(6.9, 0.0, -11.5), -PI * 0.5, b.town_id)  # on the east wall by the great door
	var beds: Array[Vector3] = []
	var seats: Array[Vector3] = []
	for c in marks.get_children():
		if String(c.name).begins_with("Bed_"):
			beds.append((c as Node3D).position)
		elif String(c.name).begins_with("Seat_"):
			seats.append((c as Node3D).position)
	var start: Vector3 = at.call("Start")
	return {
		"root": root,
		"start": start,
		"start_yaw": PI,
		"ambient": Color(0.14, 0.12, 0.1),
		"chests": chests,
		"decor": {"pieces": 0, "items": 0},
		"spots": {"exit": start, "beds": beds, "work": at.call("Throne"), "seats": seats},
	}


# ---------------------------------------------------------------- module interiors (Alpha 1.13)

## The building interiors made as scenes (tools/build_houses.gd, then yours to edit): every scene
## in this folder is a RoomModule whose kind says which buildings may use it
const HOUSE_DIR := "res://scenes/interiors/houses/"
const MODULE_KINDS := {
	BuildingPlot.Kind.HOUSE: "house", BuildingPlot.Kind.FARM: "farm", BuildingPlot.Kind.SHOP: "shop",
	BuildingPlot.Kind.SMITHY: "smithy", BuildingPlot.Kind.INN: "inn", BuildingPlot.Kind.TEMPLE: "temple",
	BuildingPlot.Kind.GUILD_HALL: "guild", BuildingPlot.Kind.SEAT: "seat",
}

## What each guild keeps at its hall's station spots (Station_guild<n>)
const GUILD_STATIONS := {
	"mages": ["spell_altar", "enchanter", "alchemy_lab"], "antiquarians": ["grindstone", "workbench"],
	"hunters": ["tanning_rack", "workbench"], "thieves": ["workbench"],
}

static var _modules: Array = []  # [path, kind, floor area]


static func house_modules() -> Array:
	if _modules.is_empty() and DirAccess.dir_exists_absolute(HOUSE_DIR):
		for f in DirAccess.get_files_at(HOUSE_DIR):
			f = f.trim_suffix(".remap")
			if not f.ends_with(".tscn"):
				continue
			var room := (load(HOUSE_DIR + f) as PackedScene).instantiate() as RoomModule
			if room != null:
				var size := room.bounds().size
				_modules.append([HOUSE_DIR + f, room.kind, size.x * size.z])
				room.free()
	return _modules


## Which interior scene a building uses ("" = none fits; it is built the old way): one of its kind
## close to its size outside. One house in five is a manor (most in a city's noble quarter, none in its slums).
static func pick_module(b: BuildingPlot, rng: RandomNumberGenerator) -> String:
	if not MODULE_KINDS.has(b.kind):
		return ""
	var kind: String = MODULE_KINDS[b.kind]
	if kind == "guild" and b.guild == "fighters":
		return ""  # the Fighters' hall is the arena (built the old way, sized for the pit)
	if kind == "seat" and b.seat_type == "reeve":
		kind = "manor"  # a reeve lives in a manor
	if kind == "house" and rng.randf() < {"noble": 0.6, "slums": 0.0, "market": 0.3}.get(b.district, 0.2):
		kind = "manor"
	var area := (b.size.x + 1.5) * (b.size.z + 1.5)
	var fits := house_modules().filter(func(m: Array) -> bool: return m[1] == kind)
	if fits.is_empty():
		return ""
	fits.sort_custom(func(x: Array, y: Array) -> bool: return absf(x[2] - area) < absf(y[2] - area) or (absf(x[2] - area) == absf(y[2] - area) and x[0] < y[0]))
	var best: float = absf(fits[0][2] - area)
	var near := fits.filter(func(m: Array) -> bool: return absf(m[2] - area) <= best + 0.1)
	return near[rng.randi_range(0, near.size() - 1)][0]


## The way from one spot to another indoors: back out through the doorways or down the stairs from a
## spot that needs them, then along the way to the next (spots["via"]); else straight there
static func route(spots: Dictionary, from: Vector3, to: Vector3) -> PackedVector3Array:
	var via: Dictionary = spots.get("via", {})
	var out := PackedVector3Array()
	for k: Vector3 in via:
		if k.distance_to(from) < 1.0 and k.distance_to(to) > 1.0:
			var back: PackedVector3Array = via[k]
			for i in range(back.size() - 1, -1, -1):
				out.append(back[i])
			break
	for k: Vector3 in via:
		if k.distance_to(to) < 0.1:
			out.append_array(via[k])
			break
	out.append(to)
	return out


# A building from its scene: the spawn points furnish it (RoomFiller), the markers say where the
# door, the beds, the chests, the stations and the people's places are
static func _from_module(b: BuildingPlot, path: String, interior_seed: int, level: int, today: int, rng: RandomNumberGenerator) -> Dictionary:
	var room := (load(path) as PackedScene).instantiate() as RoomModule
	room.set_meta("room_id", "building/%s" % b.id)
	RoomFiller.fill(room, {"props_only": true, "seed": interior_seed})
	var root := Node3D.new()
	root.name = "Interior"
	root.set_meta("building_id", b.id)
	root.set_meta("module", path)
	# everything comes out of the module, so the decorator measures each piece on its own
	for n in room.find_children("*", "", true, false):
		n.owner = null
	for c in room.get_children():
		room.remove_child(c)
		root.add_child(c)
	var floors := room.cells.y
	var room_theme := String(room.themes[0]) if not room.themes.is_empty() else "house"
	var bounds := room.bounds()
	room.free()
	var marks := {}
	for c in root.get_children():
		if c is Marker3D:
			marks[String(c.name)] = c
	# a building over a cellar: its ground floor (where the door is) goes to y 0, the cellar below
	var ground := (marks["Door"] as Node3D).position.y if marks.has("Door") else 0.0
	if ground != 0.0:
		for c in root.get_children():
			(c as Node3D).position.y -= ground
	var at := func(n: String, fallback: Vector3 = Vector3.ZERO) -> Vector3: return (marks[n] as Node3D).position if marks.has(n) else fallback
	var numbered := func(prefix: String) -> Array:
		var out: Array = []
		var i := 0
		while marks.has("%s%d" % [prefix, i]):
			out.append(marks["%s%d" % [prefix, i]])
			i += 1
		return out
	var hx := bounds.size.x * 0.5
	var hz := bounds.size.z * 0.5
	var h := RoomModule.LEVEL - (InteriorKit.SLAB if floors > 1 else 0.0)

	# lamps on every floor, one every 7 m or so
	var lx := maxi(int(round(bounds.size.x / 7.0)), 1)
	var lz := maxi(int(round(bounds.size.z / 7.0)), 1)
	for f in floors:
		for ix in lx:
			for iz in lz:
				var lamp := OmniLight3D.new()
				lamp.light_color = LAMP_COLOR
				lamp.light_energy = 1.3
				lamp.omni_range = maxf(bounds.size.x / lx, bounds.size.z / lz) * 1.2 + 2.0
				lamp.position = Vector3(-hx + (ix + 0.5) * bounds.size.x / lx, f * RoomModule.LEVEL - ground + 3.2, -hz + (iz + 0.5) * bounds.size.z / lz)
				root.add_child(lamp)

	var door: Vector3 = at.call("Door", Vector3(0, 0, -hz + 0.7))
	var exit := DungeonDoor.new()
	exit.name = "Exit"
	exit.entrance_id = b.id
	exit.label = "Leave %s" % b.display_name
	exit.is_exit = true
	root.add_child(exit)
	exit.position = door + Vector3(0, 1.3, 0)

	var beds: Array[Vector3] = []
	for m: Node3D in numbered.call("Bed"):
		beds.append(m.position)
		RestSpot.make_bed(root, m.position, b)
	var seats: Array[Vector3] = []
	for m: Node3D in numbered.call("Seat"):
		seats.append(m.position)
	var work: Vector3 = at.call("Work")
	var stations: Array[Vector3] = []
	for n: String in marks:
		if not n.begins_with("Station_"):
			continue
		var kind := n.substr(8)
		if kind == "trade":
			kind = {"alchemy": "alchemy_lab", "jeweler": "workbench"}.get(b.trade, "")
		elif kind.begins_with("guild"):
			var own: Array = GUILD_STATIONS.get(b.guild, [])
			var i := kind.substr(5).to_int()
			kind = own[i] if i < own.size() else ""
		if kind != "":
			stations.append(_station(root, kind, (marks[n] as Node3D).position, (marks[n] as Node3D).rotation.y))
	var chests := 0
	var chest_marks: Array = numbered.call("Chest")
	for i in chest_marks.size():
		var cname := "%s's Chest" % NameGen.first_name(b.owner_name)
		var loot := _home_loot()
		match b.kind:
			BuildingPlot.Kind.SHOP:
				cname = "Merchant Chest"
				loot = _shop_loot()
			BuildingPlot.Kind.SMITHY:
				cname = "Smith's Chest"
				loot = _shop_loot()
			BuildingPlot.Kind.INN:
				cname = "Innkeeper's Chest"
				loot = _shop_loot()
			BuildingPlot.Kind.TEMPLE:
				cname = "Offering Box"
				loot = _offering_loot()
			BuildingPlot.Kind.GUILD_HALL:
				cname = "Guild Chest"
				loot = _shop_loot()
			BuildingPlot.Kind.SEAT:
				cname = "Tithe Chest" if b.seat_type == "reeve" else "Treasury Chest"
				loot = _shop_loot()
		if i > 0:
			cname = "Strongbox"
			loot = _shop_loot()
		chests += _chest(root, b, i, cname, (chest_marks[i] as Node3D).position + Vector3(0, 0.35, 0), loot, interior_seed)
	if b.kind == BuildingPlot.Kind.INN:
		NoticeBoard.make(root, at.call("Notice", Vector3(-2.6, 0, -hz + 0.15)), (marks["Notice"] as Node3D).rotation.y if marks.has("Notice") else 0.0, b.town_id)
	if b.kind == BuildingPlot.Kind.TEMPLE:
		RestSpot.make_shrine(root, at.call("Shrine", Vector3(0, 0, hz - 1.3)))
	# the banners of the guild or the lord's house
	var banner_color := CLOTH
	if b.kind == BuildingPlot.Kind.GUILD_HALL:
		banner_color = TownBuilder.GUILD_COLORS.get(b.guild, CLOTH)
	elif b.kind == BuildingPlot.Kind.SEAT:
		banner_color = NamedSettlements.house_color(b.house)
	for m: Node3D in numbered.call("Banner"):
		POIBuilder.add_box(root, Vector3(1.2, 2.6, 0.06), m.position + Vector3(0, 2.6, -0.03), banner_color, 0.0, Vector3.ZERO, false)
	if b.kind == BuildingPlot.Kind.GUILD_HALL and b.guild == "antiquarians" and marks.has("Case"):
		var case := MuseumCase.new()
		case.name = "MuseumCase"
		root.add_child(case)
		case.position = at.call("Case")
		case.rotation.y = (marks["Case"] as Node3D).rotation.y
	if b.kind == BuildingPlot.Kind.SEAT:
		var board_mark: Vector3 = at.call("Bounty", Vector3(hx - 0.15, 0, 0))
		var board := BountyBoard.make(root, board_mark, (marks["Bounty"] as Node3D).rotation.y if marks.has("Bounty") else -PI * 0.5, b.town_id)
		stations.append(board.position)
		var books := LoreBooks.for_town(b.town_name)
		if not books.is_empty():
			var loot: Array[LootEntry] = []
			for id in books:
				var le := LootEntry.new()
				le.item = LoreBooks.get_item(id)
				loot.append(le)
			var shelf := POIBuilder.make_chest("Bookshelf", loot, "building/%s/lore" % b.id, interior_seed | 1)
			root.add_child(shelf)
			shelf.position = at.call("Lore", Vector3(-hx + 0.8, 0, hz - 1.0)) + Vector3(0, 0.35, 0)
			stations.append(shelf.position)
			chests += 1
	# the ways to spots behind walls or upstairs
	var via := {}
	for n: String in marks:
		if not n.begins_with("Via_"):
			continue
		var spot := n.substr(4, n.rfind("_") - 4)
		if not marks.has(spot):
			continue
		var key: Vector3 = (marks[spot] as Node3D).position
		var list: Array = via.get(key, [])
		list.append([int(n.substr(n.rfind("_") + 1)), (marks[n] as Node3D).position])
		via[key] = list
	for key: Vector3 in via:
		var list: Array = via[key]
		list.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var pts := PackedVector3Array()
		for e: Array in list:
			pts.append(e[1])
		via[key] = pts

	var owner := b.id if b.kind != BuildingPlot.Kind.GUILD_HALL else "guild:" + b.guild
	if Homes.owns(b.id):
		owner = ""  # your own home: nothing here is stolen
		var spare: Array = numbered.call("Spare")
		var extras := ["alchemy_lab", "workbench", "planter", "planter"]
		for i in mini(spare.size(), extras.size()):
			var m: Node3D = spare[i]
			if extras[i] == "planter":
				Planter.place(root, m.position, "planter/%s/%d" % [b.id, i - 2])
				stations.append(m.position)
			else:
				stations.append(_station(root, extras[i], m.position, m.rotation.y))
		for c in root.get_children():
			var cc := c.get_node_or_null("ContainerComponent") as ContainerComponent
			if cc != null:
				cc.owner_id = ""
				cc.display_name = "Your Chest"
	var clear: Array[Vector3] = [door, work]
	clear.append_array(seats)
	clear.append_array(beds)
	clear.append_array(stations)
	for k: Vector3 in via:
		for p in via[k]:
			if p.y < 1.0:
				clear.append(p)
	var theme := "rich_home" if path.get_file().begins_with("manor") else theme_for(b, rng)
	if b.kind == BuildingPlot.Kind.HOUSE and theme == "rich_home" and not path.get_file().begins_with("manor"):
		theme = "home"
	var decor := RoomDecorator.decorate(root, Rect2(-hx + InteriorKit.WALL, -hz + InteriorKit.WALL, hx * 2.0 - InteriorKit.WALL * 2.0, hz * 2.0 - InteriorKit.WALL * 2.0),
		theme, level, interior_seed ^ 0x5eed, owner, "building/%s" % b.id, clear, 3, today, h)
	var start: Vector3 = at.call("Start", door + Vector3(0, 0, 1.9))
	return {
		"root": root,
		"start": start + Vector3(0, 0.1, 0),
		"start_yaw": PI,
		"ambient": AMBIENT,
		"chests": chests,
		"decor": decor,
		"spots": {"exit": at.call("ExitSpot", door + Vector3(0, 0, 1.0)) + Vector3(0, 0.1, 0), "beds": beds, "work": work, "seats": seats, "via": via},
		"theme": room_theme,
	}


## Which RoomDecorator theme a building gets
static func theme_for(b: BuildingPlot, rng: RandomNumberGenerator) -> String:
	match b.kind:
		BuildingPlot.Kind.HOUSE:
			return "rich_home" if rng.randf() < 0.2 else "home"
		BuildingPlot.Kind.FARM:
			return "farm"
		BuildingPlot.Kind.INN:
			return "tavern"
		BuildingPlot.Kind.SMITHY:
			return "smithy"
		BuildingPlot.Kind.TEMPLE:
			return "temple"
		BuildingPlot.Kind.SEAT:
			return "home" if b.seat_type == "reeve" else "rich_home"
		BuildingPlot.Kind.GUILD_HALL:
			var g := "guild_" + b.guild
			return g if RoomDecorator.THEMES.has(g) else "guild"
		BuildingPlot.Kind.SHOP:
			match b.trade:
				"alchemy":
					return "alchemist"
				"jeweler", "pawnbroker":
					return "rich_home"
	return "shop"


# ---------------------------------------------------------------- furniture

## A workstation (see CraftingStation); returns where it stands so the decorator keeps it clear
static func _station(root: Node3D, kind: String, at: Vector3, yaw: float = 0.0) -> Vector3:
	CraftingStation.place(root, kind, at, yaw)
	return at


## A piece of furniture: a box the size of the space it takes, swapped for its model ("prop/<kind>")
## when there is one. A long space (pews, a counter, wall shelving, a hall table) is filled with as many
## real-size models as fit along it, rather than one stretched or one lost in the middle.
static func _furn(root: Node3D, kind: String, size: Vector3, center: Vector3, color: Color, yaw: float = 0.0) -> void:
	var key := "prop/" + kind
	var count := 1
	if String(ModelLibrary.entry(key).get("fit", "")) == "real":
		var probe := ModelLibrary.instance(key)
		if probe != null:
			var pb := ModelLibrary.bounds(probe)
			probe.free()
			count = clampi(roundi(maxf(size.x, size.z) / maxf(maxf(pb.size.x, pb.size.z), 0.3)), 1, 12)
	# `size` and the row run along the world's axes; each piece is turned by `yaw` to face the room
	var along_x := size.x >= size.z
	var piece := Vector3(size.x / count, size.y, size.z) if along_x else Vector3(size.x, size.y, size.z / count)
	if absf(sin(yaw)) > 0.5:
		piece = Vector3(piece.z, piece.y, piece.x)  # in the turned piece's own axes
	for i in count:
		var off := (float(i) + 0.5) / float(count) - 0.5
		var c := center + (Vector3(size.x * off, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, size.z * off))
		var holder := Node3D.new()
		holder.name = "Decor_" + kind
		holder.position = Vector3(c.x, center.y - size.y * 0.5, c.z)
		holder.rotation.y = yaw
		root.add_child(holder, true)
		POIBuilder.add_box(holder, piece, Vector3(0.0, size.y * 0.5, 0.0), color)
		ModelLibrary.replace_meshes(holder, key)


static func _bed(root: Node3D, at: Vector3) -> Vector3:
	_furn(root, "bed", Vector3(1.0, 0.65, 2.0), at + Vector3(0.0, 0.325, 0.0), DARK_WOOD)
	return at


static func _table(root: Node3D, at: Vector3, stools: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	_furn(root, "table", Vector3(1.4, 0.82, 0.9), at + Vector3(0.0, 0.41, 0.0), WOOD)
	for i in stools:
		var a := float(i) / float(stools) * TAU
		_furn(root, "stool", Vector3(0.4, 0.45, 0.4), at + Vector3(cos(a) * 1.0, 0.225, sin(a) * 0.8), DARK_WOOD)
		out.append(at + Vector3(cos(a) * 1.5, 0.0, sin(a) * 1.25))  # a place to stand by the table
	return out


static func _hearth(root: Node3D, at: Vector3) -> void:
	_furn(root, "hearth", Vector3(0.8, 1.3, 1.8), at + Vector3(0.0, 0.65, 0.0), STONE)
	POIBuilder.add_box(root, Vector3(0.3, 0.4, 0.9), at + Vector3(-0.3, 0.35, 0.0), Color(1.0, 0.5, 0.15), 0.0, Vector3.ZERO, false, true)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 1.2
	fire.omni_range = 5.0
	fire.position = at + Vector3(-0.8, 0.6, 0.0)
	root.add_child(fire)


# The owner's chest. Saved by id, so what you take stays taken (and later counts as stealing).
static func _chest(root: Node3D, b: BuildingPlot, i: int, chest_name: String, at: Vector3, loot: Array[LootEntry], interior_seed: int) -> int:
	var chest := POIBuilder.make_chest(chest_name, loot, "building/%s/chest_%d" % [b.id, i], (interior_seed + i * 104729) | 1)
	chest.set_meta("owner_building", b.id)
	(chest.get_node("ContainerComponent") as ContainerComponent).owner_id = b.id  # taking from it is stealing
	root.add_child(chest)
	chest.position = at
	return 1


static func _entry(path: String, chance: float, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.item = load(path) as ItemData if ResourceLoader.exists(path) else null
	e.chance = chance
	e.min_count = lo
	e.max_count = hi
	return e


const C := "res://data/consumables/"


static func _home_loot() -> Array[LootEntry]:
	return [_entry(C + "gold.tres", 0.8, 3, 25), _entry(C + "bread.tres", 0.5, 1, 2), _entry(C + "apple.tres", 0.5, 1, 3), _entry(C + "minor_health_potion.tres", 0.2, 1, 1)]


static func _shop_loot() -> Array[LootEntry]:
	return [_entry(C + "gold.tres", 1.0, 20, 80), _entry(C + "health_potion.tres", 0.3, 1, 1), _entry(Locks.LOCKPICK_PATH, 0.3, 1, 3)]


static func _offering_loot() -> Array[LootEntry]:
	return [_entry(C + "gold.tres", 0.9, 5, 30), _entry(C + "minor_health_potion.tres", 0.4, 1, 2)]


# The door and every spot people walk to: the decorator keeps a path from each to the middle
static func _keep_clear(door_z: float, work: Vector3, seats: Array[Vector3], beds: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3(0.0, 0.0, door_z), work]
	out.append_array(seats)
	out.append_array(beds)
	return out
