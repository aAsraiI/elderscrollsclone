class_name SpawnQueue
extends Node
## Alpha 1.23 performance: people and creatures that come with a place streaming in (its garrison,
## the folk at a camp's spawn points) are made at once but join the world a few at a time, BUDGET_MS
## per frame, instead of all in the frame the place appears (a bandit hold used to stop the game for
## over half a second). Places stream in 150 m and more away, so nobody sees them arrive late.
## WorldManager switches `defer` on while it builds places and owns the one SpawnQueue node.

const BUDGET_MS := 3.0

## While true, Population.spawn_enemy hands its creature here instead of adding it
static var defer := false
static var _held: Array = []  # [parent, enemy]


static func hold(parent: Node, e: Enemy) -> void:
	_held.append([parent, e])


## Creatures still waiting to join, under this node (or under anything inside it)
static func held_under(root: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for h in _held:
		var parent: Node = h[0]
		if is_instance_valid(parent) and is_instance_valid(h[1]) and (parent == root or root.is_ancestor_of(parent)):
			out.append(h[1])
	return out


static func pending() -> int:
	return _held.size()


## Everyone waiting joins now (tests, saving, going through a door)
static func flush() -> void:
	while not _held.is_empty():
		_place(_held.pop_front())


func _ready() -> void:
	add_to_group("spawn_queue")


func _exit_tree() -> void:
	_held.clear()


func _process(_delta: float) -> void:
	if _held.is_empty():
		return
	var start := Time.get_ticks_usec()
	var tries := _held.size()
	while not _held.is_empty() and tries > 0 and (Time.get_ticks_usec() - start) < BUDGET_MS * 1000.0:
		tries -= 1
		var h: Array = _held.pop_front()
		var parent: Node = h[0]
		if is_instance_valid(parent) and not parent.is_inside_tree():
			_held.append(h)  # its place is not in the world yet
			continue
		_place(h)


static func _place(h: Array) -> void:
	var parent: Node = h[0]
	var e: Enemy = h[1]
	if not is_instance_valid(e) or e.is_queued_for_deletion():
		return
	if not is_instance_valid(parent) or parent.is_queued_for_deletion():
		e.free()  # its place went away first
		return
	parent.add_child(e)
