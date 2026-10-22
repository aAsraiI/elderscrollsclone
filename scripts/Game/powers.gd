class_name Powers
extends Node
## Once-a-day abilities. Z = your racial power (see Races); B = Beast Form for a werewolf (see
## Afflictions). Each can be used once per in-game day. Lives under the Player (player.gd adds it).

const RACIAL_ACTION := "racial_power"
const BEAST_ACTION := "beast_form"

var racial := ""
## Day the racial power was last used
var used_day := -1


func _ready() -> void:
	_register(RACIAL_ACTION, KEY_Z)
	_register(BEAST_ACTION, KEY_B)


func _register(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed(RACIAL_ACTION):
		use_racial()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(BEAST_ACTION):
		var aff := get_parent().get_node_or_null("Afflictions") as Afflictions
		if aff != null and aff.werewolf:
			aff.toggle_beast_form()
		get_viewport().set_input_as_handled()


func _today() -> int:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	return clock.day if clock != null else 1


func is_ready() -> bool:
	return racial != "" and used_day != _today()


func use_racial() -> bool:
	if racial == "":
		return false
	if used_day == _today():
		Locks.toast(get_tree(), "You have already used your power today", true)
		return false
	var p := Races.power_effects(racial)
	if p.is_empty():
		return false
	var spell := SpellData.make("power_" + racial, racial.capitalize().replace("_", " "), p["form"], p["effects"], float(p.get("area", 0.0)))
	var caster := get_parent().get_node_or_null("SpellCaster") as SpellCaster
	if caster == null:
		return false
	if not caster.cast_now(spell, true):  # powers cost no magicka
		return false
	used_day = _today()
	Locks.toast(get_tree(), "Power used: %s" % Races.get_race(String(get_parent().get_meta("character", {}).get("race", ""))).get("power_desc", racial).get_slice(":", 0))
	return true


func to_dict() -> Dictionary:
	return {"racial": racial, "used_day": used_day}


func from_dict(d: Dictionary) -> void:
	if String(d.get("racial", "")) != "":
		racial = String(d["racial"])
	used_day = int(d.get("used_day", -1))
