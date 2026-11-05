class_name Campsite
extends Node3D
## Alpha 1.30.2: your camp. A Camping Kit (workbench) pitched anywhere outside, away from towns
## (E in the inventory): a tent, a bedroll to sleep in, and a fire to cook at and warm yourself by.
## One camp at a time (pitch again elsewhere and it moves); E on the tent strikes it and gives
## the kit back. Saved in WorldState "camp" and rebuilt when the world loads.
## Sleeping out in the wild is a risk: one night in four something finds you, unless a
## follower or a tamed animal keeps watch.

const KIT := "res://data/misc/camping_kit.tres"
const AMBUSH_CHANCE := 0.25

var _tent: StaticBody3D


static func current(tree: SceneTree) -> Campsite:
	return tree.get_first_node_in_group("campsite") as Campsite


static func pitch(player: Node3D, kit: ItemData) -> String:
	var tree := player.get_tree()
	var w := tree.get_first_node_in_group("world_manager") as WorldManager
	if w == null or (w.dungeons != null and w.dungeons.is_inside()):
		return "Pitch camp outside."
	var t := w.get_nearest_town(player.global_position)
	if t != null and t.position.distance_to(player.global_position) < t.poi.footprint_radius + 25.0:
		return "Not this close to a town: find a spot in the wild."
	var at := player.global_position - player.global_transform.basis.z * 3.0
	if w.get_height_at(at.x, at.z) < w.map.get_water_level(at.x, at.z):
		return "Not in the water."
	at.y = w.get_height_at(at.x, at.z)
	var old := current(tree)
	if old != null:
		old.queue_free()
	(player.get_node("Inventory") as Inventory).remove_item(kit, 1)
	WorldState.set_record("camp", {"pos": [at.x, at.y, at.z], "yaw": player.rotation.y})
	_build(tree, at, player.rotation.y)
	Achievements.note("camp")
	return "You pitch camp: a tent, a bedroll and a fire."


## The camp, as the world loads (WorldManager calls this)
static func restore(tree: SceneTree) -> void:
	var rec := WorldState.get_record("camp")
	if rec.is_empty() or current(tree) != null:
		return
	var p: Array = rec["pos"]
	_build(tree, Vector3(p[0], p[1], p[2]), float(rec.get("yaw", 0.0)))


static func _build(tree: SceneTree, at: Vector3, yaw: float) -> Campsite:
	var w := tree.get_first_node_in_group("world_manager") as WorldManager
	var c := Campsite.new()
	c.add_to_group("campsite")
	w.add_child(c)
	c.global_position = at
	c.rotation.y = yaw
	c._make()
	return c


func _make() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.52, 0.45, 0.33)
	# the tent: a prism of canvas you strike with E
	_tent = TentBody.new()
	_tent.collision_layer = 4 | 1
	add_child(_tent)
	_tent.position = Vector3(0, 0, -1.6)
	var mesh := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(2.2, 1.5, 2.4)
	mesh.mesh = prism
	mesh.material_override = cloth
	mesh.position.y = 0.75
	mesh.rotation.y = PI * 0.5
	_tent.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.5, 2.4)
	shape.shape = box
	shape.position.y = 0.75
	_tent.add_child(shape)
	# the bedroll (a bed that is anyone's), beside the tent
	var roll := RestSpot.new()
	roll.kind = "bed"
	add_child(roll)
	roll.position = Vector3(1.6, 0.1, -1.4)
	var rm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.12, 1.9)
	rm.mesh = bm
	rm.material_override = cloth
	roll.add_child(rm)
	# the fire: a cooking spot that warms you
	var fire := CraftingStation.place(self, "cooking_pot", Vector3(0, 0, 1.2))
	fire.add_to_group("heat_sources")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0.8, 1.2)
	add_child(light)


## After sleeping in the camp's bedroll (WaitMenu tells RestSpot): did something find you?
static func night_ambush(player: Node3D, bed: RestSpot) -> String:
	var camp := bed.get_parent() as Campsite if bed != null else null
	if camp == null:
		return ""
	if guarded(player):
		return ""
	if randf() >= AMBUSH_CHANCE:
		return ""
	var w := player.get_tree().get_first_node_in_group("world_manager") as WorldManager
	var data := load("res://data/enemies/wolf.tres") as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sk := player.get_node_or_null("Skills") as Skills
	for i in 2:
		var at := player.global_position + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		at.y = w.get_height_at(at.x, at.z) + 0.5
		var e := Population.spawn_enemy(data, maxi(sk.get_player_level() if sk != null else 3, 3), w, at, rng)
		if e != null:
			e.aggro.call_deferred(player)
	return "Something found your camp in the night!"


## A follower or a tamed beast keeps watch
static func guarded(player: Node) -> bool:
	var f := player.get_node_or_null("Followers") as Followers
	if f != null and not f.followers.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_dead()).is_empty():
		return true
	return Taming.pets(player) > 0


func strike(player: Node) -> String:
	(player.get_node("Inventory") as Inventory).add_item(load(KIT) as ItemData, 1)
	WorldState.erase_record("camp")
	queue_free()
	return "You strike camp and pack the kit away."


class TentBody extends StaticBody3D:
	func get_prompt() -> String:
		return "Strike camp"

	func interact(actor: Inventory) -> void:
		var camp := get_parent() as Campsite
		if camp != null and actor != null:
			Locks.toast(get_tree(), camp.strike(actor.get_parent()))
