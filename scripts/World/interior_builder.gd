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


## Returns {"root": Node3D, "start": Vector3, "start_yaw": float, "ambient": Color, "chests": int}
static func build(b: BuildingPlot, interior_seed: int, level: int = 5, today: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = interior_seed
	var w := maxf(b.size.x + 1.5, 7.0)
	var d := maxf(b.size.z + 1.5, 6.5)
	var h := 3.4
	match b.kind:
		BuildingPlot.Kind.TEMPLE:
			h = 6.5
		BuildingPlot.Kind.INN, BuildingPlot.Kind.GUILD_HALL:
			h = 4.2
	var root := Node3D.new()
	root.name = "Interior"
	root.set_meta("building_id", b.id)

	var floor_color := WOOD.darkened(0.25) if b.kind != BuildingPlot.Kind.TEMPLE else STONE.lightened(0.1)
	var wall_color := Color(0.55, 0.47, 0.36) if b.kind != BuildingPlot.Kind.TEMPLE else STONE.lightened(0.25)
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
			POIBuilder.add_box(root, Vector3(1.6, 1.8, 0.45), Vector3(w * 0.5 - 1.3, 0.9, d * 0.5 - 0.3), WOOD)
			if b.kind == BuildingPlot.Kind.FARM:
				for i in 3:
					POIBuilder.add_box(root, Vector3(0.7, 0.9, 0.7), Vector3(-w * 0.5 + 0.6 + float(i) * 0.8, 0.45, -d * 0.5 + 1.0), DARK_WOOD)
			chests += _chest(root, b, 0, "%s's Chest" % NameGen.first_name(b.owner_name), Vector3(-w * 0.5 + 0.8, 0.35, d * 0.5 - 2.7), _home_loot(), interior_seed)
		BuildingPlot.Kind.SHOP:
			POIBuilder.add_box(root, Vector3(w * 0.6, 1.0, 0.7), Vector3(0.0, 0.5, d * 0.1), WOOD)
			POIBuilder.add_box(root, Vector3(w - 1.5, 2.4, 0.5), Vector3(0.0, 1.2, d * 0.5 - 0.3), DARK_WOOD)
			for i in 4:
				POIBuilder.add_box(root, Vector3(0.6, 0.6, 0.6), Vector3(-w * 0.5 + 0.7, 0.3 + float(i % 2) * 0.6, -d * 0.2 + float(i / 2) * 0.7), WOOD.lightened(0.1))
			work = Vector3(0.0, 0.0, d * 0.1 + 1.0)
			beds.append(_bed(root, Vector3(w * 0.5 - 0.8, 0.0, -d * 0.5 + 1.6)))
			chests += _chest(root, b, 0, "Merchant Chest", Vector3(w * 0.25, 0.35, d * 0.5 - 1.1), _shop_loot(), interior_seed)
		BuildingPlot.Kind.INN:
			POIBuilder.add_box(root, Vector3(0.7, 1.1, d * 0.45), Vector3(-w * 0.5 + 1.8, 0.55, d * 0.05), WOOD)
			POIBuilder.add_box(root, Vector3(0.5, 2.0, d * 0.45), Vector3(-w * 0.5 + 0.3, 1.0, d * 0.05), DARK_WOOD)
			for i in 3:
				seats.append_array(_table(root, Vector3(w * 0.05 + float(i % 2) * w * 0.25, 0.0, -d * 0.2 + float(i) * d * 0.15), 4))
			_hearth(root, Vector3(w * 0.5 - 0.5, 0.0, -d * 0.15))
			POIBuilder.add_box(root, Vector3(0.2, h, 2.8), Vector3(w * 0.12, h * 0.5, d * 0.5 - 1.4), wall_color.darkened(0.1))
			beds.append(_bed(root, Vector3(w * 0.12 + 0.8, 0.0, d * 0.5 - 1.2)))
			beds.append(_bed(root, Vector3(w * 0.12 + 2.2, 0.0, d * 0.5 - 1.2)))
			work = Vector3(-w * 0.5 + 1.05, 0.0, d * 0.05)
			chests += _chest(root, b, 0, "Innkeeper's Chest", Vector3(-w * 0.5 + 0.9, 0.35, -d * 0.3), _shop_loot(), interior_seed)
		BuildingPlot.Kind.SMITHY:
			POIBuilder.add_box(root, Vector3(1.8, 1.0, 1.8), Vector3(w * 0.5 - 1.2, 0.5, d * 0.5 - 1.2), STONE.darkened(0.2))
			POIBuilder.add_box(root, Vector3(1.0, 0.25, 1.0), Vector3(w * 0.5 - 1.2, 1.1, d * 0.5 - 1.2), Color(1.0, 0.45, 0.1), 0.0, Vector3.ZERO, false, true)
			POIBuilder.add_box(root, Vector3(0.5, 0.6, 0.4), Vector3(0.0, 0.3, 0.6), STONE.darkened(0.4))
			POIBuilder.add_box(root, Vector3(1.0, 0.15, 0.4), Vector3(0.0, 0.68, 0.6), Color(0.22, 0.22, 0.25))
			POIBuilder.add_box(root, Vector3(2.4, 1.8, 0.3), Vector3(-w * 0.5 + 1.5, 0.9, d * 0.5 - 0.2), DARK_WOOD)
			work = Vector3(0.0, 0.0, 1.5)
			beds.append(_bed(root, Vector3(w * 0.5 - 0.8, 0.0, -d * 0.5 + 1.6)))
			chests += _chest(root, b, 0, "Smith's Chest", Vector3(-w * 0.5 + 0.8, 0.35, 0.0), _shop_loot(), interior_seed)
		BuildingPlot.Kind.TEMPLE:
			POIBuilder.add_box(root, Vector3(2.6, 1.1, 1.0), Vector3(0.0, 0.55, d * 0.5 - 1.3), STONE.lightened(0.3))
			POIBuilder.add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(0.0, 1.5, d * 0.5 - 1.3), Color(1.0, 0.85, 0.5), 0.7, Vector3(0.4, 0.0, 0.4), false, true)
			var rows := int((d - 5.0) / 1.6)
			for i in rows:
				for side in [-1.0, 1.0]:
					POIBuilder.add_box(root, Vector3(w * 0.32, 0.5, 0.45), Vector3(side * w * 0.24, 0.25, -d * 0.5 + 3.0 + float(i) * 1.6), WOOD)
			work = Vector3(0.0, 0.0, d * 0.5 - 2.4)
			beds.append(_bed(root, Vector3(-w * 0.5 + 0.8, 0.0, -d * 0.5 + 1.6)))
			for i in rows:
				seats.append(Vector3(-w * 0.24, 0.0, -d * 0.5 + 2.4 + float(i) * 1.6))
			chests += _chest(root, b, 0, "Offering Box", Vector3(w * 0.5 - 0.8, 0.35, d * 0.5 - 1.0), _offering_loot(), interior_seed)
		BuildingPlot.Kind.GUILD_HALL:
			POIBuilder.add_box(root, Vector3(1.2, 0.8, d * 0.45), Vector3(0.0, 0.4, d * 0.05), WOOD)
			for side in [-1.0, 1.0]:
				POIBuilder.add_box(root, Vector3(0.4, 0.45, d * 0.45), Vector3(side * 1.0, 0.23, d * 0.05), DARK_WOOD)
			var banner: Color = TownBuilder.GUILD_COLORS.get(b.guild, CLOTH)
			for x in [-w * 0.25, w * 0.25]:
				POIBuilder.add_box(root, Vector3(1.2, 2.4, 0.06), Vector3(x, h * 0.55, d * 0.5 - 0.05), banner, 0.0, Vector3.ZERO, false)
			match b.guild:
				"fighters":
					for i in 2:
						POIBuilder.add_box(root, Vector3(0.35, 1.7, 0.35), Vector3(w * 0.5 - 1.2, 0.85, -d * 0.2 + float(i) * 2.0), Color(0.6, 0.5, 0.3))
				"antiquarians":
					var case := MuseumCase.new()
					case.name = "MuseumCase"
					root.add_child(case)
					case.position = Vector3(w * 0.5 - 1.0, 0.0, -d * 0.1)
					case.rotation.y = PI * 0.5
				"mages":
					for side in [-1.0, 1.0]:
						POIBuilder.add_box(root, Vector3(0.5, 2.6, d * 0.5), Vector3(side * (w * 0.5 - 0.3), 1.3, 0.0), DARK_WOOD)
					POIBuilder.add_box(root, Vector3(0.4, 0.4, 0.4), Vector3(0.0, 1.2, d * 0.35), Color(0.4, 0.6, 1.0), 0.5, Vector3(0.4, 0.0, 0.4), false, true)
				_:
					for i in 2:
						POIBuilder.add_box(root, Vector3(0.7, 1.9, 0.5), Vector3(w * 0.5 - 0.8, 0.95, -d * 0.2 + float(i) * 2.0), Color(0.62, 0.62, 0.66))
			work = Vector3(0.0, 0.0, d * 0.05 + d * 0.225 + 0.8)
			beds.append(_bed(root, Vector3(-w * 0.5 + 0.8, 0.0, -d * 0.5 + 1.6)))
			for i in 4:
				seats.append(Vector3(1.6 * (1.0 if i % 2 == 0 else -1.0), 0.0, d * 0.05 + (float(i / 2) - 0.5) * 2.0))
			chests += _chest(root, b, 0, "Guild Chest", Vector3(-w * 0.5 + 0.8, 0.35, d * 0.5 - 1.0), _shop_loot(), interior_seed)

	# Furnish the rest of the room and put things on every surface (owned: taking them is theft;
	# guild halls belong to the guild, so members may help themselves)
	var owner := b.id if b.kind != BuildingPlot.Kind.GUILD_HALL else "guild:" + b.guild
	var decor := RoomDecorator.decorate(root, Rect2(-w * 0.5, -d * 0.5, w, d), theme_for(b, rng), level, interior_seed ^ 0x5eed,
		owner, "building/%s" % b.id, _keep_clear(door_z, work, seats, beds), 3, today, h)

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

static func _bed(root: Node3D, at: Vector3) -> Vector3:
	POIBuilder.add_box(root, Vector3(1.0, 0.5, 2.0), at + Vector3(0.0, 0.25, 0.0), DARK_WOOD)
	POIBuilder.add_box(root, Vector3(0.9, 0.12, 1.5), at + Vector3(0.0, 0.56, -0.2), CLOTH, 0.0, Vector3.ZERO, false)
	POIBuilder.add_box(root, Vector3(0.7, 0.15, 0.35), at + Vector3(0.0, 0.58, 0.75), Color(0.85, 0.82, 0.75), 0.0, Vector3.ZERO, false)
	return at


static func _table(root: Node3D, at: Vector3, stools: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	POIBuilder.add_box(root, Vector3(1.4, 0.08, 0.9), at + Vector3(0.0, 0.78, 0.0), WOOD)
	POIBuilder.add_box(root, Vector3(0.9, 0.74, 0.5), at + Vector3(0.0, 0.37, 0.0), DARK_WOOD)
	for i in stools:
		var a := float(i) / float(stools) * TAU
		POIBuilder.add_box(root, Vector3(0.4, 0.45, 0.4), at + Vector3(cos(a) * 1.0, 0.23, sin(a) * 0.8), DARK_WOOD)
		out.append(at + Vector3(cos(a) * 1.5, 0.0, sin(a) * 1.25))  # a place to stand by the table
	return out


static func _hearth(root: Node3D, at: Vector3) -> void:
	POIBuilder.add_box(root, Vector3(0.8, 1.3, 1.8), at + Vector3(0.0, 0.65, 0.0), STONE)
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


const C := "res://scripts/Resources/Consumables/"


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
