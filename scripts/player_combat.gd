class_name PlayerCombat
extends Node
## Mouse input for the player's combat.
##   Left click   TAP = light attack (tap again for a combo), HOLD = charge, release = heavy attack
##   Right click  hold = the off-hand action: block (shield), slam (two-handed hammer),
##                or an attack with the off-hand weapon (second dagger)
##   While blocking: left click = shield bash.  Right click while charging = cancel the charge.
## Setup: add a Node named PlayerCombat as a child of the Player and attach this script.
## It finds the MeleeCombat next to it, registers the "attack" / "secondary_attack" actions
## itself, and creates the first-person weapon (ViewModel) and the hit feedback
## (CombatFeedback) on its own, so there is nothing else to add.

@export var combat: MeleeCombat
## Create the weapon you see in your hands. Turn off to use your own.
@export var create_view_model := true
## Create hit markers, camera shake, hitstop, damage vignette and the enemy health bar
@export var create_feedback := true

var _primary_held := false
var _secondary_held := false


func _ready() -> void:
	_register_action("attack", MOUSE_BUTTON_LEFT)
	_register_action("secondary_attack", MOUSE_BUTTON_RIGHT)
	if combat == null:
		combat = get_parent().get_node_or_null("MeleeCombat") as MeleeCombat
	if combat == null:
		push_error("PlayerCombat: could not find a MeleeCombat next to it. Add one under the Player.")
		set_process(false)
		return
	# The parent is still setting up its children right now, so add the helpers a moment later
	_spawn_helpers.call_deferred()


func _spawn_helpers() -> void:
	var player := get_parent()
	if player == null or combat == null:
		return
	if create_feedback and player.get_node_or_null("CombatFeedback") == null:
		var fb := CombatFeedback.new()
		fb.name = "CombatFeedback"
		fb.combat = combat
		player.add_child(fb)
	if create_view_model:
		var cam := player.get_node_or_null("Head/Camera3D") as Node3D
		if cam != null and cam.get_node_or_null("ViewModel") == null:
			var vm := ViewModel.new()
			vm.name = "ViewModel"
			vm.combat = combat
			cam.add_child(vm)


func _unhandled_input(event: InputEvent) -> void:
	# The click that re-captures the mouse after Esc must not also swing the sword.
	# Children get input before the Player, so at that moment the mouse is still free.
	if combat == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or get_tree().paused:
		return
	if event.is_action_pressed("attack"):
		_primary_held = true
		combat.begin_charge()
	elif event.is_action_released("attack"):
		if _primary_held:
			_primary_held = false
			combat.release_charge()
	elif event.is_action_pressed("secondary_attack"):
		_secondary_held = true
		combat.secondary_press()
	elif event.is_action_released("secondary_attack"):
		if _secondary_held:
			_secondary_held = false
			combat.secondary_release()


func _process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _primary_held:
		if not captured:
			_primary_held = false
			combat.cancel_charge()
		elif not Input.is_action_pressed("attack"):
			_primary_held = false
			combat.release_charge()
	if _secondary_held:
		if captured and Input.is_action_pressed("secondary_attack"):
			combat.secondary_press(true)  # keeps trying: raises the guard as soon as a swing ends
		else:
			_secondary_held = false
			combat.secondary_release()


# A menu opened while a button was down: forget the button, so closing the menu doesn't swing
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and combat != null:
		if _primary_held:
			_primary_held = false
			combat.cancel_charge()
		if _secondary_held:
			_secondary_held = false
			combat.secondary_release()


func _register_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
