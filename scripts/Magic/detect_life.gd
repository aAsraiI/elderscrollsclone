class_name DetectLife
extends Node3D
## Detect Life: a glowing marker over every living creature within `radius`, seen through walls.
## Made by ActiveMagic while the effect lasts.

var radius := 50.0
var _markers := {}   # instance id -> Label3D
var _timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	var host := get_parent() as Node3D
	if host == null:
		return
	var seen := {}
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or e.global_position.distance_to(host.global_position) > radius:
			continue
		seen[e.get_instance_id()] = true
		if not _markers.has(e.get_instance_id()):
			var m := Label3D.new()
			m.text = "◆"
			m.font_size = 48
			m.pixel_size = 0.006
			m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			m.no_depth_test = true
			m.modulate = Color(1.0, 0.35, 0.3) if e.disposition == Enemy.Disposition.HOSTILE else Color(0.5, 1.0, 0.7)
			m.position = Vector3(0.0, 2.3 * e.body_scale, 0.0)
			e.add_child(m)
			_markers[e.get_instance_id()] = m
	for id in _markers.keys():
		var m: Label3D = _markers[id]
		if not seen.has(id) or not is_instance_valid(m):
			if is_instance_valid(m):
				m.queue_free()
			_markers.erase(id)


func _exit_tree() -> void:
	for id in _markers:
		var m: Variant = _markers[id]
		if is_instance_valid(m):
			(m as Node).queue_free()
	_markers.clear()
