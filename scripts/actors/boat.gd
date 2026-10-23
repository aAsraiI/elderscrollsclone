class_name Boat
extends StaticBody3D
## A rowboat. Towns with a fishing pier keep one tied at the end of it (TownBuilder._pier). E boards
## it; then W / S row, A / D turn, and Sprint raises the sail for speed. It floats on the water at
## sea level and runs aground in the shallows; E again steps off. The last boat you used is yours
## from then on: it stays where you left it, across loads (WorldState "boat", like the horse).

const INTERACTABLE_LAYER := 4
const ROW := 4.5
const SAIL := 9.5
const TURN := 1.3
## The water must be at least this deep under the bow to move on
const DRAFT := 0.6

## The town whose pier it came from ("" for one restored from a save)
var from_town := ""
var speed := 0.0
var _player: CharacterBody3D
var _sail: Node3D
var _sea := 0.0
var _map: WorldMap
var _aground_told := false
var _save_timer := 0.0


static func make(parent: Node3D, at: Vector3, yaw: float, town: String) -> Boat:
	var b := Boat.new()
	b.name = "Boat"
	b.from_town = town
	b.position = at
	b.rotation.y = yaw
	parent.add_child(b)
	return b


## Brings back the boat you used last (if it is not at its pier any more). Player._ready calls it.
static func restore(player: Node3D) -> void:
	var rec := WorldState.get_record("boat")
	if rec.is_empty() or player == null or not player.is_inside_tree():
		return
	var scene := player.get_tree().current_scene
	var pos := SaveUtil.array_to_vec3(rec.get("pos"), player.global_position)
	make(scene, pos, float(rec.get("yaw", 0.0)), "")


## Did the player take this town's boat away? (then its pier stays empty)
static func taken_from(town: String) -> bool:
	return String(WorldState.get_record("boat").get("from", "")) == town


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER | 1
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null:
		_map = world.map
		_sea = world.settings.sea_level
	var wood := POIBuilder.get_material(Color(0.4, 0.28, 0.16))
	var dark := POIBuilder.get_material(Color(0.24, 0.16, 0.09))
	var cloth := POIBuilder.get_material(Color(0.78, 0.72, 0.6))
	_box(Vector3(1.6, 0.3, 4.2), Vector3(0, 0.0, 0), dark)          # the hull's bottom
	for side in [-1.0, 1.0]:
		_box(Vector3(0.12, 0.55, 4.0), Vector3(side * 0.8, 0.25, 0), wood)  # the sides
	_box(Vector3(1.5, 0.55, 0.12), Vector3(0, 0.25, 2.05), wood)     # the stern
	_box(Vector3(0.9, 0.5, 0.6), Vector3(0, 0.2, -2.3), wood, Vector3(0.35, 0, 0))  # the bow
	_box(Vector3(1.5, 0.1, 0.35), Vector3(0, 0.3, 0.6), dark)       # the thwart you sit on
	_box(Vector3(0.12, 3.4, 0.12), Vector3(0, 1.8, -0.8), dark)     # the mast
	_sail = Node3D.new()
	add_child(_sail)
	var sail := _box(Vector3(0.04, 2.4, 1.6), Vector3(0, 2.0, -0.05), cloth)
	sail.reparent(_sail, false)
	_sail.visible = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 0.7, 4.6)
	shape.shape = box
	shape.position = Vector3(0, 0.2, 0)
	add_child(shape)


func _box(size: Vector3, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	add_child(mi)
	return mi


func is_boarded() -> bool:
	return _player != null


func get_prompt() -> String:
	return "Board the boat" if not is_boarded() else ""


func interact(_inv: Inventory) -> void:
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p != null:
		board(p)


func board(p: CharacterBody3D) -> void:
	if is_boarded() or p.has_meta("riding") or p.has_meta("beast_form"):
		return
	_player = p
	# The boat now goes where you take it: off the pier's town and into the world
	var scene := get_tree().current_scene
	if get_parent() != scene:
		reparent(scene, true)
	p.set_meta("boat", self)
	p.add_collision_exception_with(self)
	_aground_told = false
	_remember()
	Locks.toast(get_tree(), "W/S to row, A/D to turn, Sprint for the sail, E to step off")


func leave() -> void:
	if not is_boarded():
		return
	var p := _player
	_player = null
	speed = 0.0
	_sail.visible = false
	p.remove_meta("boat")
	p.remove_collision_exception_with(self)
	# Step off onto the nearer shore side if there is one, else into the water beside the boat
	var best := global_position + global_transform.basis.x * 1.6
	for side in [1.0, -1.0]:
		for dist in [1.6, 2.6, 3.6]:
			var at: Vector3 = global_position + global_transform.basis.x * side * dist
			if _map != null and _map.get_height(at.x, at.z) > _sea - 0.2:
				best = Vector3(at.x, _map.get_height(at.x, at.z), at.z)
				break
	p.global_position = best + Vector3.UP * 0.6
	p.velocity = Vector3.ZERO
	_remember()


func _unhandled_input(event: InputEvent) -> void:
	if is_boarded() and event.is_action_pressed("interact") and not get_tree().paused:
		leave()
		get_viewport().set_input_as_handled()


## player.gd calls this instead of walking while you are in the boat
func steer(delta: float, input_dir: Vector2, sail: bool) -> void:
	var want := -input_dir.y * (SAIL if sail and input_dir.y < 0.0 else ROW)
	if want < 0.0:
		want *= 0.4  # backing water is slow
	speed = move_toward(speed, want, (2.5 if sail else 3.5) * delta)
	_sail.visible = sail and input_dir.y < 0.0
	rotation.y -= input_dir.x * TURN * delta * clampf(absf(speed) * 0.3 + 0.35, 0.35, 1.0)
	var fwd := -global_transform.basis.z
	var next := global_position + fwd * speed * delta
	var probe := next + fwd * signf(speed) * 2.4
	if absf(speed) > 0.01 and _map != null and _map.get_height(probe.x, probe.z) > _sea - DRAFT:
		speed = 0.0  # aground
		if not _aground_told:
			_aground_told = true
			Locks.toast(get_tree(), "The boat scrapes the bottom. Too shallow to go on.")
	else:
		if absf(speed) > 0.5:
			_aground_told = false
		global_position = Vector3(next.x, _sea - 0.05 + sin(Time.get_ticks_msec() * 0.002) * 0.04, next.z)
	_player.global_position = global_position + Vector3.UP * 0.55 + global_transform.basis.z * 0.6
	_player.velocity = Vector3.ZERO


func _process(delta: float) -> void:
	_save_timer -= delta
	if is_boarded() and _save_timer <= 0.0:
		_save_timer = 5.0
		_remember()


func _remember() -> void:
	var rec := WorldState.get_record("boat")
	var from := String(rec.get("from", from_town)) if from_town == "" else from_town
	WorldState.set_record("boat", {"pos": SaveUtil.vec3_to_array(global_position), "yaw": rotation.y, "from": from})
