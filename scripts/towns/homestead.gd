class_name Homestead
extends Node
## Your own house, built by you. A town's lord sells land outside the town ("land for sale",
## LAND_PRICE gold; one plot in the realm). On the plot stands a drafting table: E on it builds the
## next part of the house for gold, in order: the hall, a bedroom, a steward, a workshop, a
## storeroom and a garden. The steward looks after the place and the farmland around it, and hands
## you STEWARD_RENT gold for every day you were away (up to RENT_DAYS days).
##
## Under the Player. The house is drawn when you come near the plot and dropped when you leave.
## Saved in WorldState "homestead": {"town", "pos", "yaw", "built": [part ids], "paid"}.

const LAND_PRICE := 1500
const STEWARD_RENT := 50
const RENT_DAYS := 10
const NEAR := 250.0
const FAR := 320.0
const ROOM := 7.0
const WALL_H := 3.2
const T := 0.3
const TOPIC := "land for sale"
## The parts in the order they are built: [id, name, gold, where (room middle in the plot)]
const PARTS := [
	["hall", "the Hall", 800, Vector3(0, 0, 0)],
	["bedroom", "a Bedroom", 400, Vector3(7, 0, 0)],
	["steward", "a Steward", 500, Vector3.ZERO],
	["workshop", "a Workshop", 700, Vector3(-7, 0, 0)],
	["storeroom", "a Storeroom", 400, Vector3(0, 0, 7)],
	["garden", "a Garden", 300, Vector3(7, 0, 7)],
]

var _house: Node3D
var _clock := 0.0


static func record() -> Dictionary:
	return WorldState.get_record("homestead")


static func owns() -> bool:
	return not record().is_empty()


static func built() -> Array:
	return record().get("built", [])


static func has_part(id: String) -> bool:
	return built().has(id)


## The next part to build ([] when the house is finished)
static func next_part() -> Array:
	for p in PARTS:
		if not has_part(String(p[0])):
			return p
	return []


static func plot_position() -> Vector3:
	return SaveUtil.array_to_vec3(record().get("pos"), Vector3.ZERO)


# ---------------------------------------------------------------- buying the land

static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	if s != null and s.role == NpcData.Role.LORD and s.town != null and not owns():
		return PackedStringArray([TOPIC])
	return PackedStringArray()


## The lord's answer about the land, or {} when it isn't that topic
static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, world: WorldManager, today: int) -> Dictionary:
	if topic != TOPIC or not topics_for(s).has(topic):
		return {}
	var inv := player.get_node("Inventory") as Inventory
	if Currency.get_gold(inv) < LAND_PRICE:
		return _say("There is good land outside %s, if you want to build. %d gold for the deed, and you'd need to build the house yourself." % [s.town.town.display_name, LAND_PRICE])
	var spot := pick_spot(s.town, world)
	if spot.is_empty():
		return _say("I'm afraid there's no land left to sell around here.")
	Currency.spend_gold(inv, LAND_PRICE)
	buy(s.town, spot, today)
	var to: Vector3 = spot["pos"] - s.town.position
	return _say("Done. The plot is %s of %s; there's a drafting table on it. Build what you like, and hire a steward when you can." % [_compass(to), s.town.town.display_name])


static func buy(town: PlacedPOI, spot: Dictionary, today: int) -> void:
	WorldState.set_record("homestead", {"town": town.id, "pos": SaveUtil.vec3_to_array(spot["pos"]), "yaw": float(spot["yaw"]),
		"built": [], "paid": today})
	MapMarkers.add(Vector2(spot["pos"].x, spot["pos"].z), "Homestead")


## The flattest dry ground in a ring outside the town, facing it: {"pos", "yaw"} or {}
static func pick_spot(town: PlacedPOI, world: WorldManager) -> Dictionary:
	var best := {}
	var best_rough := INF
	var sea := world.settings.sea_level if world.settings.water_enabled else -INF
	var ring := town.poi.footprint_radius + 45.0
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var at := town.position + Vector3(cos(a), 0, sin(a)) * ring
		var lo := INF
		var hi := -INF
		for x in [-11.0, 0.0, 11.0]:
			for z in [-8.0, 0.0, 12.0]:
				var h := world.map.get_height(at.x + x, at.z + z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
		if lo < sea + 0.5 or world.get_town_at(at, 30.0) != null or not world.get_pois_near(at, 40.0).is_empty():
			continue
		if hi - lo < best_rough:
			best_rough = hi - lo
			var to_town := (town.position - at).normalized()
			best = {"pos": Vector3(at.x, world.map.get_height(at.x, at.z), at.z), "yaw": atan2(-to_town.x, -to_town.z)}
	return best


static func _compass(v: Vector3) -> String:
	var dirs := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]  # -Z is north
	return dirs[posmod(roundi(atan2(v.z, v.x) / (TAU / 8.0)), 8)]


static func _say(text: String) -> Dictionary:
	return {"text": text, "journal": true, "quest_id": "", "quest_name": "", "learn": PackedStringArray()}


# ---------------------------------------------------------------- building

## Builds the next part if you can pay for it. Returns what happened (a toast).
func build_next(inv: Inventory) -> String:
	var p := next_part()
	if p.is_empty():
		return "Your house is finished."
	if Currency.get_gold(inv) < int(p[2]):
		return "You need %d gold to build %s." % [p[2], p[1]]
	Currency.spend_gold(inv, int(p[2]))
	var rec := record()
	var list: Array = rec.get("built", []).duplicate()
	list.append(String(p[0]))
	rec["built"] = list
	if String(p[0]) == "steward":
		rec["paid"] = _today()
	WorldState.set_record("homestead", rec)
	_rebuild()
	return "You hired a steward." if String(p[0]) == "steward" else "The builders finish %s." % p[1]


func _today() -> int:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	return clock.day if clock != null else 1


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = 1.0
	if not owns():
		return
	var player := get_parent() as Node3D
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	var d := Vector2(player.global_position.x - plot_position().x, player.global_position.z - plot_position().z).length()
	if _house == null and d < NEAR and (dm == null or not dm.is_inside()):
		_build()
		_collect_rent()
	elif _house != null and d > FAR:
		_house.queue_free()
		_house = null


func _rebuild() -> void:
	if _house != null:
		_house.free()
		_house = null
	_build()


## The steward's rents for the days you were away
func _collect_rent() -> void:
	if not has_part("steward"):
		return
	var rec := record()
	var days := clampi(_today() - int(rec.get("paid", _today())), 0, RENT_DAYS)
	if days <= 0:
		return
	rec["paid"] = _today()
	WorldState.set_record("homestead", rec)
	var inv := get_parent().get_node("Inventory") as Inventory
	Currency.add_gold(inv, days * STEWARD_RENT)
	Locks.toast(get_tree(), "Your steward hands you %d gold in rents." % (days * STEWARD_RENT))


func _build() -> void:
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world == null:
		return
	var at := plot_position()
	var yaw := float(record().get("yaw", 0.0))
	_house = Node3D.new()
	_house.name = "Homestead"
	get_tree().current_scene.add_child(_house)
	_house.global_position = at
	_house.rotation.y = yaw
	# Everything stands on one floor level: the highest ground under the house
	var floor_y := 0.0
	for x in [-10.5, 0.0, 10.5]:
		for z in [-3.5, 3.5, 10.5]:
			var g := _house.to_global(Vector3(x, 0, z))
			floor_y = maxf(floor_y, world.map.get_height(g.x, g.z) - at.y)
	floor_y += 0.15
	var plot := BuildingPlot.new()
	plot.id = "homestead"
	plot.kind = BuildingPlot.Kind.HOUSE
	plot.display_name = "Your House"
	# The drafting table, in front of the hall
	var table := DraftingTable.new()
	table.homestead = self
	_house.add_child(table)
	table.position = Vector3(-2.5, floor_y, -6.0)
	# Corner stakes until the hall stands
	if not has_part("hall"):
		for c in [Vector3(-3.5, 0, -3.5), Vector3(3.5, 0, -3.5), Vector3(-3.5, 0, 3.5), Vector3(3.5, 0, 3.5)]:
			POIBuilder.add_box(_house, Vector3(0.12, 1.0, 0.12), c + Vector3(0, floor_y + 0.3, 0), InteriorBuilder.WOOD)
		return
	for p in PARTS:
		var id := String(p[0])
		if not has_part(id) or id == "steward":
			continue
		var mid: Vector3 = p[3] + Vector3(0, floor_y, 0)
		if id == "garden":
			_garden(mid)
			continue
		_room(mid, id, world, at.y)
		match id:
			"hall":
				InteriorBuilder._hearth(_house, mid + Vector3(ROOM * 0.5 - 0.7, 0, 1.5))
				InteriorBuilder._table(_house, mid + Vector3(-0.5, 0, 0.5), 3)
				InteriorBuilder._station(_house, "cooking_pot", mid + Vector3(ROOM * 0.5 - 1.3, 0, -1.8))
			"bedroom":
				InteriorBuilder._bed(_house, mid + Vector3(1.5, 0, 1.8))
				RestSpot.make_bed(_house, mid + Vector3(1.5, 0, 1.8), plot)
				POIBuilder.add_box(_house, Vector3(1.4, 1.8, 0.45), mid + Vector3(-1.8, 0.9, ROOM * 0.5 - 0.4), InteriorBuilder.WOOD)
			"workshop":
				InteriorBuilder._station(_house, "forge", mid + Vector3(-1.6, 0, 1.8))
				InteriorBuilder._station(_house, "workbench", mid + Vector3(1.4, 0, 2.4))
				InteriorBuilder._station(_house, "alchemy_lab", mid + Vector3(-ROOM * 0.5 + 0.5, 0, -1.0), PI * 0.5)
				InteriorBuilder._station(_house, "grindstone", mid + Vector3(1.6, 0, -1.6))
			"storeroom":
				for i in 4:
					var chest := POIBuilder.make_chest("Your Chest", [], "homestead/chest_%d" % i, 1)
					(chest.get_node("ContainerComponent") as ContainerComponent).owner_id = ""
					_house.add_child(chest)
					chest.position = mid + Vector3(-2.4 + i * 1.6, 0.35, ROOM * 0.5 - 0.7)
	if has_part("steward"):
		_steward(world, Vector3(1.5, floor_y + 0.1, -4.8))
	var lamp := OmniLight3D.new()
	lamp.light_color = InteriorBuilder.LAMP_COLOR
	lamp.light_energy = 1.2
	lamp.omni_range = 9.0
	_house.add_child(lamp)
	lamp.position = Vector3(0, floor_y + WALL_H - 0.6, 0)


# One room: a floor on stone footings, four walls (doorways toward the hall and out the front of
# the hall), and a roof
func _room(mid: Vector3, id: String, world: WorldManager, base_y: float) -> void:
	var stone := InteriorBuilder.STONE
	var wall := Color(0.55, 0.47, 0.36)
	var half := ROOM * 0.5
	POIBuilder.add_box(_house, Vector3(ROOM, 0.3, ROOM), mid + Vector3(0, -0.15, 0), InteriorBuilder.WOOD.darkened(0.25))
	var low := mid.y
	for c in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(-half, 0, half), Vector3(half, 0, half)]:
		var g := _house.to_global(mid + c)
		low = minf(low, world.map.get_height(g.x, g.z) - base_y)
	var footing := mid.y - low + 1.0
	POIBuilder.add_box(_house, Vector3(ROOM, footing, ROOM) * Vector3(0.98, 1, 0.98), mid + Vector3(0, -0.3 - footing * 0.5, 0), stone)
	POIBuilder.add_box(_house, Vector3(ROOM + 0.6, 0.25, ROOM + 0.6), mid + Vector3(0, WALL_H + 0.12, 0), InteriorBuilder.DARK_WOOD)
	POIBuilder.add_box(_house, Vector3(ROOM + 0.2, 0.9, ROOM * 0.6), mid + Vector3(0, WALL_H + 0.6, 0), InteriorBuilder.DARK_WOOD.darkened(0.2), 0.0, Vector3.ZERO, false)
	# The walls: a side room's wall toward the hall has a doorway (and the hall leaves that side to
	# it); the hall's front has the way in; every other side is a plain wall
	var here := Vector3(mid.x, 0, mid.z)
	for side in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		var there := _room_at(here + side * ROOM)
		if id == "hall" and there != "":
			continue
		_wall(mid, side, (id == "hall" and side.z < 0.0) or there == "hall", wall)


## The built room standing at a plot position ("" if none; the garden is not a room)
func _room_at(at: Vector3) -> String:
	for p in PARTS:
		var id := String(p[0])
		if id != "steward" and id != "garden" and has_part(id) and Vector3(p[3]).is_equal_approx(at):
			return id
	return ""


func _wall(mid: Vector3, side: Vector3, door: bool, color: Color) -> void:
	var half := ROOM * 0.5
	var along := Vector3(absf(side.z), 0, absf(side.x))  # the wall runs across the side it faces
	var at := mid + side * (half - T * 0.5) + Vector3(0, WALL_H * 0.5, 0)
	var thick := Vector3(absf(side.x), 0, absf(side.z)) * T
	if not door:
		POIBuilder.add_box(_house, along * ROOM + thick + Vector3(0, WALL_H, 0), at, color)
		return
	var seg := (ROOM - 1.6) * 0.5
	for s in [-1.0, 1.0]:
		POIBuilder.add_box(_house, along * seg + thick + Vector3(0, WALL_H, 0), at + along * s * (0.8 + seg * 0.5), color)
	POIBuilder.add_box(_house, along * 1.6 + thick + Vector3(0, WALL_H - 2.4, 0), at + Vector3(0, 1.2, 0), color)


func _garden(mid: Vector3) -> void:
	var half := ROOM * 0.5
	for k in 4:
		var a := float(k) * PI * 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		var along := Vector3(absf(dir.z), 0, absf(dir.x))
		POIBuilder.add_box(_house, along * ROOM + Vector3(0.12, 0.9, 0.12), mid + dir * half + Vector3(0, 0.45, 0), InteriorBuilder.WOOD, 0.0, Vector3.ZERO, false)
	for i in 4:
		var at := mid + Vector3(-1.8 + (i % 2) * 3.6, 0, -1.6 + (i / 2) * 3.2)
		Planter.place(_house, at, "planter/homestead/%d" % i)


func _steward(_world: WorldManager, at: Vector3) -> void:
	var data := load("res://data/enemies/wanderer.tres") as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var e := Population.spawn_enemy(data, 5, _house, _house.to_global(at), rng, {"persist_mode": Enemy.PersistMode.NEVER})
	e.disposition = Enemy.Disposition.FRIENDLY
	e.display_name = "Your Steward"
	e.wander_radius = 0.0
	e.set_meta("greeting", "Welcome home. The house is in good order, and the tenants paid on time.")


## E on the drafting table builds the next part of the house (see Homestead.build_next)
class DraftingTable extends StaticBody3D:
	var homestead: Homestead

	func _ready() -> void:
		collision_layer = 4 | 1
		POIBuilder.add_box(self, Vector3(1.4, 0.08, 0.9), Vector3(0, 1.0, 0), InteriorBuilder.WOOD, 0.0, Vector3(0.25, 0, 0), false)
		POIBuilder.add_box(self, Vector3(0.12, 1.0, 0.12), Vector3(0, 0.5, 0), InteriorBuilder.DARK_WOOD, 0.0, Vector3.ZERO, false)
		POIBuilder.add_box(self, Vector3(1.0, 0.01, 0.7), Vector3(0, 1.05, 0), Color(0.86, 0.82, 0.7), 0.0, Vector3(0.25, 0, 0), false)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.4, 1.1, 0.9)
		shape.shape = box
		shape.position = Vector3(0, 0.55, 0)
		add_child(shape)

	func get_prompt() -> String:
		var p := Homestead.next_part()
		return "Your house is finished" if p.is_empty() else "Build %s (%d gold)" % [p[1], p[2]]

	func interact(inv: Inventory) -> void:
		Locks.toast(get_tree(), homestead.build_next(inv))
