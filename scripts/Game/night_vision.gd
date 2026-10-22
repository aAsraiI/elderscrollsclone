class_name NightVision
extends Node
## Night Eye (spell, potion, Sandcat power, vampires, enchantments): the camera's exposure goes up
## so dark places are bright enough to see in. Checks twice a second.

var _cam: Camera3D
var _attrs: CameraAttributesPractical
var _on := false
var _timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var p := get_parent()
	var stats := p.get_node_or_null("Stats") as Stats
	var want := p.has_meta("night_eye") or (stats != null and stats.get_stat("night_eye") > 0.0)
	if want == _on:
		return
	_on = want
	if _cam == null:
		_cam = p.get_node_or_null("Head/Camera3D") as Camera3D
	if _cam == null:
		return
	if want:
		_attrs = CameraAttributesPractical.new()
		_attrs.exposure_multiplier = 3.2
		_cam.attributes = _attrs
	else:
		_cam.attributes = null
