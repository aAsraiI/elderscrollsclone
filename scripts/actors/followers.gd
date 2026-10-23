class_name Followers
extends Node
## Your companions. Hire a sellsword with a Sellsword Contract (innkeepers sell them): they follow
## you, fight what you fight, carry things for you, and come with you through doors. E on one
## opens their orders: Follow, Wait here, Trade (give and take things) or Part ways. At most
## MAX at a time. Saved with your game.

const MAX := 2
const CONTRACT := "res://data/misc/sellsword_contract.tres"
const NAMES := ["Brynja", "Hadrik", "Sela", "Torvin", "Marisse", "Olaf", "Kesh", "Ilsa", "Dagan", "Rhea"]

var followers: Array[Enemy] = []
var _player: CharacterBody3D
var _pending: Array = []


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_connect_doors.call_deferred()


func _connect_doors() -> void:
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null and world.dungeons != null:
		world.dungeons.entered.connect(func(_id: String) -> void: _bring_along.call_deferred())
		world.dungeons.exited.connect(func(_id: String) -> void: _bring_along.call_deferred())
	if not _pending.is_empty():
		for d in _pending:
			_spawn_saved(d)
		_pending.clear()


func _alive() -> Array[Enemy]:
	followers = followers.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_dead())
	return followers


## The contract: a new sellsword at your side. Returns "" or why not.
func hire() -> String:
	if _alive().size() >= MAX:
		return "You can't lead more than %d companions" % MAX
	var data := load("res://data/enemies/caravan_guard.tres") as EnemyData
	if data == null:
		return "Nobody answers"
	var skills := _player.get_node_or_null("Skills") as Skills
	var level := maxi(skills.get_player_level() if skills != null else 3, 3)
	var e := Enemy.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	data.apply(e, level, rng)
	e.display_name = NAMES[rng.randi() % NAMES.size()]
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.loot = []
	e.talk_lines = PackedStringArray()
	var pos := _player.global_position - _player.global_transform.basis.z * 2.0 + Vector3.UP * 0.5
	e.position = pos
	get_tree().current_scene.add_child(e)
	e.global_position = pos
	_make_follower(e)
	return ""


func _make_follower(e: Enemy) -> void:
	e.set_meta("follower", true)
	e.max_health *= 1.0
	AllyBrain.attach(e, _player)
	var cmd := FollowerCommand.new()
	cmd.name = "FollowerCommand"
	e.add_child(cmd)
	followers.append(e)


func dismiss(e: Enemy) -> void:
	followers.erase(e)
	if is_instance_valid(e):
		var brain := e.get_node_or_null("AllyBrain")
		if brain != null:
			brain.queue_free()
		e.remove_meta("player_ally")
		e.remove_meta("follower")
		var tw := e.create_tween()
		tw.tween_interval(20.0)
		tw.tween_callback(e.queue_free)
		e.follow_route(PackedVector3Array([e.global_position + (e.global_position - _player.global_position).normalized() * 30.0]), false, 0.5)


# Through a door with you (unless told to wait)
func _bring_along() -> void:
	var i := 0
	for e in _alive():
		if e.has_meta("wait_here"):
			continue
		i += 1
		var back := _player.global_transform.basis.z
		e.global_position = _player.global_position + back * 1.5 + _player.global_transform.basis.x * (float(i) - 1.5) + Vector3.UP * 0.3
		e.velocity = Vector3.ZERO


func to_dict() -> Dictionary:
	var out := []
	for e in _alive():
		var d := e.get_persist_data()
		d["wait"] = e.has_meta("wait_here")
		out.append(d)
	return {"followers": out}


func from_dict(data: Dictionary) -> void:
	for e in _alive():
		e.queue_free()
	followers.clear()
	for d in data.get("followers", []):
		if is_inside_tree() and get_tree().current_scene != null:
			_spawn_saved(d)
		else:
			_pending.append(d)


func _spawn_saved(d: Dictionary) -> void:
	var e := Enemy.restore(d, get_tree().current_scene)
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.remove_from_group("persistent")
	_make_follower(e)
	if bool(d.get("wait", false)):
		e.set_meta("wait_here", true)


## The orders window for one follower (E on them)
class FollowerCommand extends Node:
	var _menu: CanvasLayer

	func _ready() -> void:
		var e := get_parent() as Enemy
		e.set_meta("interactable", self)
		e.collision_layer |= 4

	func get_prompt() -> String:
		var e := get_parent() as Enemy
		return "Talk to %s%s" % [e.display_name, "  (waiting)" if e.has_meta("wait_here") else ""]

	func interact(_actor: Inventory) -> void:
		var e := get_parent() as Enemy
		_menu = CanvasLayer.new()
		_menu.layer = 12
		_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_menu.add_child(center)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(300, 0)
		center.add_child(panel)
		var v := VBoxContainer.new()
		panel.add_child(v)
		v.add_child(UITheme.heading(e.display_name))
		var opts := [
			["Follow me", func() -> void: e.remove_meta("wait_here")],
			["Wait here", func() -> void:
				e.set_meta("wait_here", true)
				e.stop_route()],
			["Let me see what you carry", func() -> void: _trade(e)],
			["We part ways here", func() -> void:
				var f := get_tree().get_first_node_in_group("player").get_node_or_null("Followers") as Followers
				if f != null:
					f.dismiss(e)],
			["Never mind", func() -> void: pass],
		]
		for o in opts:
			var b := Button.new()
			b.text = o[0]
			var cb: Callable = o[1]
			b.pressed.connect(func() -> void:
				_close()
				cb.call())
			v.add_child(b)
		get_tree().root.add_child(_menu)
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	func _close() -> void:
		if _menu != null:
			_menu.queue_free()
			_menu = null
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func _trade(e: Enemy) -> void:
		var c := get_node_or_null("FollowerPack") as ContainerComponent
		if c == null:
			c = ContainerComponent.new()
			c.name = "FollowerPack"
			c.display_name = "%s's Pack" % e.display_name
			c.existing_inventory = e.inventory
			add_child(c)
		var ui := get_tree().get_first_node_in_group("container_ui") as ContainerUI
		if ui != null:
			c.roll_contents()
			ui.open(c)
