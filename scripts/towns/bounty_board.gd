class_name BountyBoard
extends StaticBody3D
## The bounty board in every town hall (lords' halls, Castle Dawnhold): E takes a bounty on a bandit
## chief or a dangerous beast near the town, one at a time. Kill it, come back, and E claims the
## reward. The bounty is a QuestManager job, so it shows in the journal, on the map and the compass.

const INTERACTABLE_LAYER := 4

var town_id := ""
var board_id := ""


static func make(parent: Node3D, at: Vector3, yaw: float, town: String) -> BountyBoard:
	var b := BountyBoard.new()
	b.name = "BountyBoard"
	b.town_id = town
	b.board_id = "board:" + town
	parent.add_child(b)
	b.position = at
	b.rotation.y = yaw
	return b


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER | 1
	# A wooden board on two posts, with a few notices pinned to it
	var wood := POIBuilder.get_material(Color(0.36, 0.24, 0.14))
	var paper := POIBuilder.get_material(Color(0.86, 0.82, 0.7))
	_box(Vector3(1.6, 1.0, 0.08), Vector3(0, 1.5, 0), wood)
	for x in [-0.75, 0.75]:
		_box(Vector3(0.1, 2.0, 0.1), Vector3(x, 1.0, 0), wood)
	for i in 4:
		_box(Vector3(0.32, 0.38, 0.01), Vector3(-0.55 + i * 0.37, 1.5 + (0.12 if i % 2 == 0 else -0.1), 0.05), paper)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 2.1, 0.3)
	shape.shape = box
	shape.position = Vector3(0, 1.05, 0)
	add_child(shape)


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	add_child(mi)


func _manager() -> QuestManager:
	var wm := get_tree().get_first_node_in_group("world_manager") as WorldManager
	return wm.quests if wm != null else null


func get_prompt() -> String:
	var qm := _manager()
	var q := qm.bounty_of(board_id) if qm != null else {}
	if q.is_empty():
		return "Read the bounty board"
	if qm.is_ready(q):
		return "Claim the bounty: %s (%d gold)" % [String(q["name"]).trim_prefix("Bounty: "), int(q["reward"])]
	return "Bounty board: %s" % String(q["name"]).trim_prefix("Bounty: ")


func interact(_inv: Inventory) -> void:
	var qm := _manager()
	var wm := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if qm == null or wm == null:
		return
	var q := qm.bounty_of(board_id)
	if not q.is_empty():
		if qm.is_ready(q):
			var gold := qm.complete(q)
			Locks.toast(get_tree(), "Bounty claimed: %d gold." % gold)
		else:
			Locks.toast(get_tree(), String(q["objective"]))
		return
	var town := wm.get_poi(town_id)
	q = qm.offer_bounty(town, board_id)
	if q.is_empty():
		Locks.toast(get_tree(), "No bounties posted today.", true)
		return
	Locks.toast(get_tree(), "Bounty taken: %s. %s" % [String(q["name"]).trim_prefix("Bounty: "), String(q["objective"])])
