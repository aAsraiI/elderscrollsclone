class_name QuestEvents
extends RefCounted
## The quest event bus: combat, inventory, the world and dialogue report what happens here, and
## every quest system that listens hears it (QuestRunner). The senders never need to know which
## quests exist.
##   kill      an Enemy died (Enemy._on_died)
##   talk      the player asked someone about a topic (DialogueUI.ask)
##   steal     the player took something from someone else's container (CrimeManager)
##   persuade  someone's disposition rose through persuasion (DialogueUI.persuade)
##   use       the player used an item (ItemUse)
##   discover  a place was found (Discovery)
##   enter     the player went into a building or dungeon (DungeonManager)

static var _log_events := false


static func emit(tree: SceneTree, kind: String, data: Dictionary) -> void:
	if tree == null:
		return
	if _log_events:
		print("[QuestEvent] %s %s" % [kind, data])
	var runner := tree.get_first_node_in_group("quest_runner") as QuestRunner
	if runner != null:
		runner.on_event(kind, data)


static func kill(e: Enemy) -> void:
	if e != null and e.is_inside_tree():
		emit(e.get_tree(), "kill", {"enemy": e, "id": String(e.enemy_id), "name": e.display_name, "key": e.spawn_key,
			"npc": String(e.get_meta("npc_id", ""))})


static func talk(tree: SceneTree, s: DialogueEngine.Speaker, topic: String) -> void:
	emit(tree, "talk", {"speaker": s, "topic": topic})


static func steal(tree: SceneTree, item: ItemData, count: int) -> void:
	emit(tree, "steal", {"item": item, "count": count})


static func persuade(tree: SceneTree, s: DialogueEngine.Speaker, disposition: int) -> void:
	emit(tree, "persuade", {"speaker": s, "disposition": disposition})


static func use(tree: SceneTree, item: ItemData) -> void:
	emit(tree, "use", {"item": item})


static func discover(tree: SceneTree, poi_id: String) -> void:
	emit(tree, "discover", {"poi": poi_id})


static func enter(tree: SceneTree, place_id: String) -> void:
	emit(tree, "enter", {"place": place_id})
