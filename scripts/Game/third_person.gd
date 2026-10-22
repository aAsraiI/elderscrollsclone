class_name ThirdPerson
extends Node
## V switches between first and third person. In third person a second camera sits behind your
## shoulder (pulled in when a wall is in the way) and you see your own body: your race's look,
## your armor and weapon, every animation the townsfolk have, and the werewolf when you change.
## In first person the same body only casts your shadow. Aiming, attacks and spells always come
## from your eyes, whichever camera you look through.

const ACTION := "toggle_view"
const OFFSET := Vector3(0.45, 0.35, 3.0)

var third := false
var _player: CharacterBody3D
var _cam: Camera3D
var _eye: Camera3D
var _body: CreatureBody
var _beast_shown := false
var _built_for := ""


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event(ACTION, ev)
	_eye = _player.get_node_or_null("Head/Camera3D") as Camera3D
	_cam = Camera3D.new()
	_cam.name = "ThirdCamera"
	_player.get_node("Head").add_child.call_deferred(_cam)
	_rebuild.call_deferred()
	var eq := _player.get_node_or_null("Equipment") as Equipment
	if eq != null:
		eq.equipped.connect(func(_s, _i): _dress())
		eq.unequipped.connect(func(_s, _i): _dress())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not get_tree().paused:
		set_third(not third)
		get_viewport().set_input_as_handled()


func set_third(on: bool) -> void:
	third = on
	if _cam == null or _eye == null:
		return
	if on:
		_cam.fov = _eye.fov
		_cam.attributes = _eye.attributes
		_cam.make_current()
	else:
		_eye.make_current()
	_apply_visibility()


func _rebuild() -> void:
	if _body != null:
		_body.queue_free()
	var beast := _player.has_meta("beast_form")
	_beast_shown = beast
	if beast:
		_player.set("placeholder_color", Color(0.22, 0.18, 0.15))
		_player.set("display_name", "Werewolf troll")  # "troll": fur on the limbs too
		_player.set("body_scale", 1.3)
		_player.set_meta("look", {"skin": Color(0.25, 0.2, 0.17), "hair": Color(0.15, 0.12, 0.1)})
	else:
		var data: Dictionary = _player.get_meta("character", {})
		var race := Races.get_race(String(data.get("race", "heartlander")))
		var skins: Array = race.get("skin", [Color(0.9, 0.75, 0.6)])
		_player.set("placeholder_color", Color(0.35, 0.3, 0.42))
		_player.set("display_name", "You")
		_player.set("body_scale", float(data.get("height", 1.0)) * float(race.get("height", 1.0)))
		_player.set_meta("look", {"skin": skins[int(data.get("skin", 0)) % skins.size()],
			"hair": CreatureBody.HAIR_COLORS[int(data.get("hair", 0)) % CreatureBody.HAIR_COLORS.size()]})
	_body = CreatureBody.build_for(_player, CreatureBody.Kind.HUMANOID, 77)
	_player.add_child(_body)
	_dress()
	_apply_visibility()


func _dress() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var eq := _player.get_node_or_null("Equipment") as Equipment
	if eq == null:
		return
	_body.set_weapons(eq.get_main_hand(), eq.get_equipped(ItemData.EquipSlot.OFF_HAND))
	_body.dress(eq)
	_apply_visibility.call_deferred()


func _apply_visibility() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if third else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for m in _body.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = mode
	# The first-person hands only in first person
	for n in ["Head/Camera3D/ViewModel", "Head/Camera3D/SpellHandView"]:
		var v := _player.get_node_or_null(n) as Node3D
		if v != null:
			v.visible = not third if n.ends_with("ViewModel") else (v.visible and not third)


func _process(_delta: float) -> void:
	if _player.has_meta("beast_form") != _beast_shown:
		_rebuild()
	if not third or _cam == null:
		return
	# Pull the camera in front of walls
	var head := _player.get_node("Head") as Node3D
	var want := head.global_transform * OFFSET
	var q := PhysicsRayQueryParameters3D.create(head.global_position, want, 1, [_player.get_rid()])
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	var at := want
	if not hit.is_empty():
		at = (hit["position"] as Vector3).lerp(head.global_position, 0.1)
	_cam.global_position = at
	_cam.global_rotation = head.global_rotation
	var view := _player.get_node_or_null("Head/Camera3D/SpellHandView") as Node3D
	if view != null:
		view.visible = false
