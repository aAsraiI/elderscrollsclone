extends SceneTree
## The main quest's first dungeon, end to end: the priest sends you to the Codex vault, the Codex
## appears in its deepest room, you can reach and take it, and the story moves on to the Mages Guild.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_story_dungeon.gd

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


func _run() -> void:
	await process_frame
	await t_story_dungeon()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func t_story_dungeon() -> void:
	print("-- the Codex vault")
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(90)
	var wm := get_first_node_in_group("world_manager") as WorldManager
	var p := get_first_node_in_group("player") as CharacterBody3D
	var story := get_first_node_in_group("story") as Story
	check("the game is up", wm != null and p != null and story != null)
	if wm == null or p == null or story == null:
		return
	(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
	WorldState.erase_record(Story.ID)
	story._begin(p)
	check("stage 1", Story.stage() == 1, str(Story.state()))
	# what the priest does when you hand over the letter
	var dungeon := story._story_dungeon(p.global_position)
	check("a story dungeon is found", dungeon != null)
	if dungeon == null:
		return
	var s2 := Story.state().duplicate()
	s2["dungeon"] = dungeon.id
	s2["stage"] = 2
	_store(s2)
	if not WorldState.has_record("stitched/" + dungeon.id) and ResourceLoader.exists(Story.CODEX_VAULT):
		WorldState.set_record("handmade/" + dungeon.id, {"scene": Story.CODEX_VAULT})
	print("  dungeon ", dungeon.id, " ", (dungeon.poi as DungeonEntrancePOIData).dungeon.resource_path)
	var ok: bool = await wm.dungeons.enter(dungeon.id, dungeon.position, 0.0)
	await frames(30)
	check("you can enter it", ok and wm.dungeons.is_inside() and wm.dungeons.current_entrance_id == dungeon.id,
		"%s inside=%s id=%s" % [ok, wm.dungeons.is_inside(), wm.dungeons.current_entrance_id])
	var inside := wm.dungeons.get_interior_root()
	var chests := inside.find_children("Chest*", "StaticBody3D", true, false) if inside != null else []
	var boss_chests := 0
	for c in chests:
		var cc := c.get_node_or_null("ContainerComponent") as ContainerComponent
		if cc != null and cc.display_name == "Boss Chest":
			boss_chests += 1
	print("  chests: %d (boss chests %d), floors %d" % [chests.size(), boss_chests, wm.dungeons.floor_count])
	check("it has chests", chests.size() > 0)
	story._timer = 0.0
	await frames(10)
	var item := QuestItems.get_item("story_codex", "Eclipse Codex")
	var holder: ContainerComponent = null
	for cc in inside.find_children("*", "ContainerComponent", true, false):
		if (cc as ContainerComponent).inventory != null and (cc as ContainerComponent).inventory.has_item(item):
			holder = cc
	check("the Codex is in a chest", holder != null)
	if holder == null:
		return
	var chest := holder.get_parent() as Node3D
	check("in the boss chest", holder.display_name == "Boss Chest", holder.display_name)
	# can you reach that chest? a ray from above must hit the chest itself, not furniture over it
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(chest.global_position + Vector3(0, 2.0, 0), chest.global_position - Vector3(0, 0.3, 0), 4 | 1)
	var hit := space.intersect_ray(q)
	check("its chest is not buried in furniture", not hit.is_empty() and hit["collider"] == chest,
		"hit %s at %s, chest at %s" % [hit.get("collider"), hit.get("position"), chest.global_position])
	story._timer = 0.0
	await frames(10)
	check("it is put there only once", holder.inventory.get_count(item) == 1, str(holder.inventory.get_count(item)))
	holder.inventory.remove_item(item, 1)
	(p.get_node("Inventory") as Inventory).add_item(item, 1)
	# every chest in the dungeon can be reached: a ray from above hits the chest, not furniture over it
	var buried := PackedStringArray()
	for c in inside.find_children("Chest*", "StaticBody3D", true, false):
		var cn := c as Node3D
		var rq := PhysicsRayQueryParameters3D.create(cn.global_position + Vector3(0, 2.0, 0), cn.global_position - Vector3(0, 0.3, 0), 4 | 1)
		var rh := space.intersect_ray(rq)
		if rh.is_empty() or not (rh["collider"] == cn or cn.is_ancestor_of(rh["collider"])):
			buried.append("%s at %s under %s at %s" % [cn.get_path(), cn.global_position, (rh["collider"] as Node).get_path() if not rh.is_empty() else "nothing", rh.get("position")])
	check("no chest stands inside furniture", buried.is_empty(), str(buried))
	await frames(5)
	story._timer = 0.0
	await frames(10)
	check("taking the Codex moves the story on", Story.stage() == 3, str(Story.state()))
	check("its marker points at a Mages Guild hall", not Story.target().is_empty())


func _store(d: Dictionary) -> void:
	WorldState.set_record(Story.ID, d)
