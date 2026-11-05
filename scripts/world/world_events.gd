class_name WorldEvents
extends Node
## Alpha 1.31.1: things that happen in the world, under WorldManager.
##   METEORS   on a clear night, now and then a star falls within sight: a streak, a flash, and
##             where it struck a crater with Star Ore in it (saved until mined out; a rumour too)
##   TREASURE  a Treasure Map (found on bandits, in camps and chests) marks a spot on your map. Dig
##             there with a pickaxe or shovel: a buried chest and sometimes those who guard it.
## Saved in WorldState "meteors" and "treasure" {"list"}; things are built when you come near.

const METEOR_GAP_DAYS := 3
const METEOR_CHANCE := 0.04  # per in-game hour of a dark night, after the gap
const NEAR := 200.0
const TREASURE_SPREAD := 2500.0

var world: WorldManager
var _t := 0.0
var _nodes := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("world_events")
	world = get_parent() as WorldManager
	_rng.randomize()


static func of(tree: SceneTree) -> WorldEvents:
	return tree.get_first_node_in_group("world_events") as WorldEvents


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or get_tree().paused:
		return
	_t = 3.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or world == null or world.clock == null:
		return
	if world.dungeons != null and world.dungeons.is_inside():
		return
	_stream(player)
	_maybe_meteor(player)


# Crater ore and treasure mounds exist only near you
func _stream(player: Node3D) -> void:
	for rec_name in ["meteors", "treasure"]:
		for s in WorldState.get_record(rec_name).get("list", []):
			var id := String(s["id"])
			var p: Array = s["pos"]
			var at := Vector3(p[0], p[1], p[2])
			var near := at.distance_to(player.global_position) < NEAR
			if near and (not _nodes.has(id) or not is_instance_valid(_nodes[id])):
				_nodes[id] = _build(rec_name, s, at)
			elif not near and _nodes.has(id):
				if is_instance_valid(_nodes[id]):
					_nodes[id].queue_free()
				_nodes.erase(id)


func _build(rec_name: String, s: Dictionary, at: Vector3) -> Node3D:
	if rec_name == "treasure":
		var spot := TreasureSpot.new()
		spot.treasure_id = String(s["id"])
		add_child(spot)
		spot.global_position = at
		return spot
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	# the crater: a ring of dark rock, and the ore in the middle
	for i in 7:
		var a := float(i) / 7.0 * TAU
		POIBuilder.add_box(root, Vector3(1.4, 0.6, 1.0), Vector3(cos(a) * 3.0, 0.2, sin(a) * 3.0), Color(0.16, 0.14, 0.13), -a, Vector3.ZERO, false)
	var node := HarvestNode.new()
	node.kind = "ore"
	node.item_id = "star_ore"
	node.key = "harvest/" + String(s["id"])
	root.add_child(node)
	return root


# ---------------------------------------------------------------- meteors

func _maybe_meteor(player: Node3D) -> void:
	var clock := world.clock
	if not clock.is_night():
		return
	var w := Weather.get_instance(get_tree())
	if w != null and w.enabled and w.current != Weather.Kind.CLEAR:
		return
	if clock.day - int(WorldState.get_record("meteor_last").get("day", -99)) < METEOR_GAP_DAYS:
		return
	# called every 3 s; turn the hourly chance into a per-call one
	var per_call := METEOR_CHANCE * 3.0 / maxf(clock.day_length_minutes * 60.0 / 24.0, 1.0) * clock.time_scale
	if _rng.randf() < per_call:
		fall(player)


## A star falls. Returns where it struck (INF if nowhere fit).
func fall(player: Node3D) -> Vector3:
	var dir := (-player.global_transform.basis.z).rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
	dir.y = 0.0
	var at := player.global_position + dir.normalized() * _rng.randf_range(90.0, 180.0)
	var g := world.get_height_at(at.x, at.z)
	var town := world.get_nearest_town(at)
	if g < world.map.get_water_level(at.x, at.z) + 0.3 or (town != null and town.position.distance_to(at) < 120.0):
		return Vector3.INF
	at.y = g
	WorldState.set_record("meteor_last", {"day": world.clock.day})
	var list: Array = (WorldState.get_record("meteors").get("list", []) as Array).duplicate(true)
	list.append({"id": "meteor/%d_%d" % [world.clock.day, _rng.randi() % 10000], "pos": [at.x, at.y, at.z]})
	WorldState.set_record("meteors", {"list": list})
	_streak(at)
	Locks.toast(get_tree(), "A star falls from the sky, away over there!")
	Achievements.note("meteor")
	if town != null:
		Rumors.add("meteor", "A star fell near %s the other night. They say the rock it left is worth a fortune." % town.town.display_name, at, Rumors._day())
	return at


func _streak(at: Vector3) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.2
	sm.height = 2.4
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.5)
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 4.0
	light.omni_range = 60.0
	ball.add_child(light)
	add_child(ball)
	ball.global_position = at + Vector3(_rng.randf_range(-120, 120), 260.0, _rng.randf_range(-120, 120))
	var tw := create_tween()
	tw.tween_property(ball, "global_position", at, 2.2)
	tw.tween_callback(ball.queue_free)


# ---------------------------------------------------------------- treasure

## A Treasure Map from the inventory: a spot is chosen in the wilds, and marked on your map
static func read_map(player: Node3D, map_item: ItemData) -> String:
	var ev := of(player.get_tree())
	if ev == null:
		return ""
	var at := ev.pick_treasure_spot(player)
	if not at.is_finite():
		return "You can't make out where this map leads."
	var list: Array = (WorldState.get_record("treasure").get("list", []) as Array).duplicate(true)
	var id := "treasure/%d_%d" % [ev.world.clock.day, ev._rng.randi() % 100000]
	list.append({"id": id, "pos": [at.x, at.y, at.z]})
	WorldState.set_record("treasure", {"list": list})
	(player.get_node("Inventory") as Inventory).remove_item(map_item, 1)
	MapMarkers.add(Vector2(at.x, at.z), "Treasure")
	DialogueState.system_entry("Knowledge", "An old treasure map: an X, and enough landmarks to work out where. I've marked it on my map. I'll need a pickaxe or shovel.", "")
	Achievements.note("treasure_map")
	return "An X on old parchment. You mark the place on your map."


func pick_treasure_spot(player: Node3D) -> Vector3:
	for i in 40:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(400.0, TREASURE_SPREAD)
		var at := player.global_position + Vector3(cos(a), 0, sin(a)) * r
		var g := world.get_height_at(at.x, at.z)
		if not world.map.get_bounds().has_point(Vector2(at.x, at.z)) or g < world.map.get_water_level(at.x, at.z) + 0.5:
			continue
		var t := world.get_nearest_town(at)
		if t != null and t.position.distance_to(at) < t.poi.footprint_radius + 60.0:
			continue
		return Vector3(at.x, g, at.z)
	return Vector3.INF


static func dig(player: Node3D, id: String) -> String:
	var inv := player.get_node("Inventory") as Inventory
	if not DigSpot.has_tool(inv):
		return "You need a pickaxe or a shovel to dig here."
	var list: Array = (WorldState.get_record("treasure").get("list", []) as Array).filter(func(s) -> bool: return String(s["id"]) != id)
	WorldState.set_record("treasure", {"list": list})
	var sk := player.get_node_or_null("Skills") as Skills
	var level := sk.get_player_level() if sk != null else 5
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	Currency.add_gold(inv, 150 + level * 20 + rng.randi() % (100 + level * 10))
	for e in ItemCatalog.enemy_loot(level, 2):
		if e.item != null and rng.randf() < 0.6:
			inv.add_item(e.item, 1)
	Achievements.note("treasure_dug")
	if rng.randf() < 0.35:
		var w := player.get_tree().get_first_node_in_group("world_manager") as WorldManager
		var data := load(DigSpot.GUARD) as EnemyData
		for i in 2:
			var at := player.global_position + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
			at.y = w.get_height_at(at.x, at.z) + 0.5
			var e := Population.spawn_enemy(data, level, w, at, rng)
			if e != null:
				e.aggro.call_deferred(player)
		return "You dig up the chest, and the dead who were buried with it!"
	return "You dig up a rotting chest: gold and old things."


class TreasureSpot extends StaticBody3D:
	var treasure_id := ""

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 0.6, 1.6)
		shape.shape = box
		add_child(shape)
		var mound := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.8
		sm.height = 0.5
		mound.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.27, 0.18)
		mound.material_override = mat
		add_child(mound)

	func get_prompt() -> String:
		return "Dig here"

	func interact(actor: Inventory) -> void:
		if actor == null:
			return
		var said := WorldEvents.dig(actor.get_parent() as Node3D, treasure_id)
		Locks.toast(get_tree(), said)
		if not said.begins_with("You need"):
			queue_free()
