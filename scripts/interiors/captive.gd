class_name Captive
extends StaticBody3D
## A prisoner in a dungeon's cells (an NPC spawn point tagged "captive"; RoomFiller makes one now
## and then). E frees them: they thank you, find their way out through the doorways (InteriorNav)
## and the deed is talked about (Rumors). Remembered in WorldState "freed/<key>", so a freed
## captive is never there again. Quests can ask for one by its key.

var key := ""
var person: Enemy


## Puts a captive at a spawn point (does nothing if this one was freed already)
static func make(socket: Node3D, room: Node3D, socket_key: String, rng: RandomNumberGenerator, level: int) -> Captive:
	if WorldState.has_record("freed/" + socket_key):
		return null
	var e := Enemy.create()
	(load("res://data/npcs/townsfolk.tres") as EnemyData).apply(e, maxi(level - 4, 1), rng)
	var name := NameGen.person(rng)
	e.display_name = name
	e.talk_name = name
	e.talk_lines = PackedStringArray(["Please, get me out of here!", "They'll be back. Hurry!"])
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.spawn_key = socket_key
	e.wander_radius = 0.0
	e.set_meta("greeting", "Please, get me out of here!")
	room.add_child(e)
	e.position = socket.position + Vector3(0, 0.3, 0)
	var c := Captive.new()
	c.name = "Captive"
	c.key = socket_key
	c.person = e
	e.add_child(c)
	return c


func _ready() -> void:
	collision_layer = 4  # E finds it
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	_sit.call_deferred()  # the body is made after this (the person is our parent)


func _sit() -> void:
	if is_instance_valid(person) and person.body != null and not WorldState.has_record("freed/" + key):
		person.body.pose = &"sit"


func get_prompt() -> String:
	return "Free %s" % person.display_name if is_instance_valid(person) else ""


func interact(_actor: Inventory) -> void:
	if not is_instance_valid(person) or WorldState.has_record("freed/" + key):
		return
	WorldState.set_record("freed/" + key, {"name": person.display_name})
	Locks.toast(get_tree(), "%s: \"Thank you! I'll find my own way out.\"" % person.display_name)
	if person.body != null:
		person.body.pose = &""
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	if skills != null:
		skills.add_deed_xp(SkillDatabase.deed_xp(5, 1.5))
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null and world.dungeons != null:
		var dm := world.dungeons
		Rumors.add("freed", "Someone freed %s from the cells of %s." % [person.display_name, Discovery._name_of(dm.current_entrance_id)], p.global_position if p != null else Vector3.ZERO, Rumors._day(), dm.current_entrance_id)
		var exit := dm.get_interior_root().find_child("Exit", true, false) as Node3D if dm.get_interior_root() != null else null
		if exit != null and dm.nav != null:
			person.follow_route(dm.nav.path(person.global_position, exit.global_position), false, 0.8)
			person.route_finished.connect(person.queue_free, CONNECT_ONE_SHOT)
	queue_free()
