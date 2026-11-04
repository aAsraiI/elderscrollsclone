class_name DeathRules
extends RefCounted
## Alpha 1.26: what dying costs, chosen on World Creation (GameRules "death"):
##   reload      the death screen: load a save (the old way, and the default)
##   gold        you wake at the nearest town's gate, and a quarter of your gold is gone
##   grave       you wake at the nearest town's gate; everything you carried but did not wear lies in
##               a grave where you fell, and stays there until you dig it up (on the map, and saved)
##   permadeath  one life (the old Ironman)
## Graves are saved in WorldState "graves" [{"id", "pos"}] and rebuilt when the world loads.

const GOLD_LOST := 0.25
const KINDS := ["reload", "gold", "grave", "permadeath"]
const NAMES := ["Reload a save", "Lose some gold", "Leave a grave", "Permadeath"]


static func kind() -> String:
	if GameRules.ironman():
		return "permadeath"
	return String(GameRules.get_rule("death"))


## Does dying take you back to life here, without a save? (gold and grave)
static func wakes() -> bool:
	return kind() in ["gold", "grave"]


## You fell: pay the price, then wake at the nearest town gate. Returns what it cost, for the screen.
static func wake(player: Node3D) -> String:
	var tree := player.get_tree()
	var world := tree.get_first_node_in_group("world_manager") as WorldManager
	var inv := player.get_node("Inventory") as Inventory
	var said := ""
	var fell := player.global_position
	if world != null and world.dungeons != null and world.dungeons.is_inside():
		fell = world.dungeons._return_position  # a grave inside would be lost with the dungeon: it goes at the door
		(player.get_node("Stats") as Stats).revive()
		await world.dungeons.exit()
	match kind():
		"gold":
			var lost := int(Currency.get_gold(inv) * GOLD_LOST)
			Currency.spend_gold(inv, lost)
			said = "You lost %d gold." % lost
		"grave":
			var n := make_grave(player, fell if fell.is_finite() else player.global_position)
			said = "Your pack lies in a grave where you fell (%d things)." % n
	var stats := player.get_node("Stats") as Stats
	stats.revive()
	if world != null:
		var town := world.get_nearest_town(player.global_position)
		if town != null:
			var p := town.position + Vector3(town.poi.footprint_radius + 10.0, 0, 0)
			world.ensure_area_loaded(p, 1)
			player.global_position = Vector3(p.x, world.get_height_at(p.x, p.z) + 1.5, p.z)
		if world.clock != null:
			world.clock.advance_hours(8.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	DialogueState.system_entry("Death", "I fell, and woke at the edge of a town with no memory of the road. %s" % said, "")
	return said


## Everything carried but not worn goes into a grave here. Returns how many stacks.
static func make_grave(player: Node3D, at: Vector3) -> int:
	var inv := player.get_node("Inventory") as Inventory
	var eq := player.get_node_or_null("Equipment") as Equipment
	var taken: Array = []
	for st in inv.stacks.duplicate():
		if st.item == null or QuestItems.is_quest_item(st.item):
			continue
		if eq != null and eq.has_method("is_equipped") and eq.is_equipped(st.item):
			continue
		taken.append([st.item, st.count])
	if taken.is_empty():
		return 0
	var graves: Array = (WorldState.get_record("graves").get("list", []) as Array).duplicate(true)
	var id := "grave/%d" % (Time.get_ticks_msec() + graves.size())
	var chest := _build(player.get_tree(), id, at)
	if chest == null:
		return 0
	var cc := chest.get_node("ContainerComponent") as ContainerComponent
	for t in taken:
		inv.remove_item(t[0], t[1])
		cc.inventory.add_item(t[0], t[1])
	graves.append({"id": id, "pos": [at.x, at.y, at.z]})
	WorldState.set_record("graves", {"list": graves})
	return taken.size()


## The graves still standing (WorldManager calls this as the world loads); empty ones crumble
static func restore(tree: SceneTree) -> void:
	var keep: Array = []
	for g in WorldState.get_record("graves").get("list", []):
		var p: Array = g["pos"]
		var chest := _build(tree, String(g["id"]), Vector3(p[0], p[1], p[2]))
		if chest != null and (chest.get_node("ContainerComponent") as ContainerComponent).inventory.stacks.is_empty():
			chest.queue_free()
			WorldState.erase_record(String(g["id"]))
			continue
		keep.append(g)
	if not keep.is_empty() or WorldState.has_record("graves"):
		WorldState.set_record("graves", {"list": keep})


## Empty graves crumble (ContainerComponent tells us nothing, so check as you walk away)
static func tidy(tree: SceneTree) -> void:
	var list: Array = (WorldState.get_record("graves").get("list", []) as Array).duplicate(true)
	var keep: Array = []
	for g in list:
		var node := _find(tree, String(g["id"]))
		if node != null:
			var cc := node.get_node("ContainerComponent") as ContainerComponent
			if cc.inventory.stacks.is_empty():
				node.queue_free()
				WorldState.erase_record(String(g["id"]))
				continue
		keep.append(g)
	if keep.size() != list.size():
		WorldState.set_record("graves", {"list": keep})


static func _find(tree: SceneTree, id: String) -> Node3D:
	for n in tree.get_nodes_in_group("graves"):
		if String(n.get_meta("grave_id", "")) == id:
			return n
	return null


static func _build(tree: SceneTree, id: String, at: Vector3) -> StaticBody3D:
	var world := tree.get_first_node_in_group("world_manager") as WorldManager
	if world == null or _find(tree, id) != null:
		return null
	var empty: Array[LootEntry] = []
	var chest := POIBuilder.make_chest("Your Grave", empty, id, 1)
	chest.add_to_group("graves")
	chest.set_meta("grave_id", id)
	world.add_child(chest)
	chest.global_position = Vector3(at.x, world.get_height_at(at.x, at.z) + 0.35, at.z) if not (world.dungeons != null and world.dungeons.is_inside()) else at
	var mark := Label3D.new()
	mark.text = "✝"
	mark.font_size = 64
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.position = Vector3(0, 1.2, 0)
	mark.modulate = Color(0.85, 0.85, 0.8)
	chest.add_child(mark)
	return chest
