class_name Interactor
extends RayCast3D
## Put this RayCast3D under your Camera3D, pointing forward (target_position = (0, 0, -3)).
## Set its collision mask to include physics layer 3. Needs an "interact" input action.
## Works on anything that has interact() / get_prompt(), either on the body it hits
## directly (WorldItem) or on a component registered as meta "interactable" (ContainerComponent).
##
## Tap vs hold: if the target also has can_grab() / get_grab_body() (loose items, corpses),
## a quick tap uses it (interact()) and holding the key grabs it with the Grabber.
## With latch_grab on, the grab then STAYS on after you let go of the key (hands free to move
## around), and pressing interact again drops it right where it is.
## Targets that can't be grabbed (chests) are used the instant the key is pressed.
## The Grabber is created here automatically.

signal prompt_changed(text: String)

@export var inventory: Inventory
## Seconds you must hold the interact key before it grabs instead of uses
@export var grab_hold_time := 0.3
## true = holding interact latches the grab on; press interact again to drop it.
## false = old behavior, the grab lasts only while the key is held.
@export var latch_grab := true
## Optional. Created automatically if there isn't one under this node.
@export var grabber: Grabber

var _last_prompt := ""
var _pending: Object = null
var _pending_time := 0.0
var _pending_hit := Vector3.INF


func _ready() -> void:
	collide_with_areas = true
	if inventory == null and owner != null:
		inventory = owner.get_node_or_null("Inventory")
	if inventory == null:
		var n := get_parent()
		while n != null and inventory == null:
			inventory = n.get_node_or_null("Inventory") as Inventory
			n = n.get_parent()

	if grabber == null:
		grabber = get_node_or_null("Grabber") as Grabber
	if grabber == null:
		grabber = Grabber.new()
		grabber.name = "Grabber"
		add_child(grabber)


func _physics_process(delta: float) -> void:
	var key_down := Input.is_action_pressed("interact")
	if not latch_grab and grabber != null and grabber.is_holding() and not key_down:
		grabber.release()  # polled (not an input event) so it still works if a menu paused the game
	_update_pending(delta, key_down)

	var prompt := ""
	if grabber != null and grabber.is_holding():
		prompt = "Drop" if latch_grab else ""
	else:
		var target := _get_target()
		if target != null and target.has_method("get_prompt"):
			prompt = target.get_prompt()
	if prompt != _last_prompt:
		_last_prompt = prompt
		prompt_changed.emit(prompt)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if grabber != null and grabber.is_holding():
		if latch_grab:
			grabber.release()  # drops it right where it is
			get_viewport().set_input_as_handled()
		return
	var target := _get_target()
	if target == null:
		return
	get_viewport().set_input_as_handled()
	if _can_grab(target):
		# Wait and see: a tap uses it, holding grabs it (decided in _update_pending)
		_pending = target
		_pending_time = 0.0
		_pending_hit = get_collision_point()
	else:
		target.interact(inventory)


# Decides between "tap" and "hold" for a grabbable target. It acts on the thing you pressed
# on, even if the crosshair wobbles onto a neighbouring item in the meantime.
func _update_pending(delta: float, key_down: bool) -> void:
	if _pending == null:
		return
	var target := _pending
	if not is_instance_valid(target):
		_pending = null
		return
	if not key_down:
		_pending = null  # let go quickly: it was a tap
		target.interact(inventory)
		return
	_pending_time += delta
	if _pending_time >= grab_hold_time:
		_pending = null
		grabber.grab(target, _pending_hit)


func _can_grab(target: Object) -> bool:
	return grabber != null and target.has_method("can_grab") and target.has_method("get_grab_body") and target.can_grab()


func _get_target() -> Object:
	if not is_colliding():
		return null
	var hit := get_collider()
	if hit == null:
		return null
	if hit.has_method("interact"):
		return hit
	if hit.has_meta("interactable"):
		var component = hit.get_meta("interactable")
		if is_instance_valid(component) and component.has_method("interact"):
			return component
	return null
