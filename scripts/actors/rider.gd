class_name Rider
extends Node
## Riding (see Horse). Under the Player: while riding you sit in the saddle and the horse moves. You
## can fight from the saddle: more reach, and a gallop adds to every blow (MeleeCombat._charge_mult).
## Also owns your horse: brings it back after a load and remembers where it is.

const DEED := "res://data/misc/horse_deed.tres"
const WALK := 6.0
const GALLOP := 13.0

var horse: Horse
var _player: CharacterBody3D
var _save_timer := 0.0
var _ride_xp := 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_restore.call_deferred()
	Boat.restore.call_deferred(_player)  # and the boat you sailed last


func is_riding() -> bool:
	return horse != null and is_instance_valid(horse) and horse.has_meta("ridden")


static func owns_horse() -> bool:
	return WorldState.has_record("horse")


## The deed: the first use gives you the horse, later uses call it to you
func use_deed() -> void:
	var p := _player.global_position - _player.global_transform.basis.z * 4.0 + Vector3.UP * 0.5
	if horse == null or not is_instance_valid(horse):
		horse = Horse.spawn_at(get_tree().current_scene, p, _player.rotation.y)
		_remember()
		Locks.toast(get_tree(), "Your horse is here. Press E on it to ride.")
		return
	if horse.global_position.distance_to(_player.global_position) > 150.0:
		var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
		if world != null:
			world.ensure_area_loaded(p)
		horse.global_position = p
	else:
		horse.come_to(_player.global_position)
	Locks.toast(get_tree(), "You whistle for your horse")


func mount(h: Horse) -> void:
	if is_riding() or _player.has_meta("beast_form"):
		return
	horse = h
	h.set_meta("ridden", true)
	_player.set_meta("riding", h)
	_barding_on(true)  # 1.27
	h.add_collision_exception_with(_player)
	_player.add_collision_exception_with(h)


func dismount() -> void:
	if not is_riding():
		return
	var h := horse
	h.remove_meta("ridden")
	_player.remove_meta("riding")
	_barding_on(false)
	var side := h.global_transform.basis.x * 1.4
	_player.global_position = h.global_position + side + Vector3.UP * 0.6
	_player.velocity = Vector3.ZERO
	h.velocity = Vector3.ZERO
	h.remove_collision_exception_with(_player)
	_player.remove_collision_exception_with(h)
	_remember()


func _unhandled_input(event: InputEvent) -> void:
	if is_riding() and event.is_action_pressed("interact") and not get_tree().paused:
		dismount()
		get_viewport().set_input_as_handled()


## player.gd calls this instead of walking
func ride(delta: float, input_dir: Vector2, gallop: bool) -> void:
	var h := horse
	# The horse turns with your view
	var yaw := _player.rotation.y
	h.rotation.y = lerp_angle(h.rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
	var fwd := -h.global_transform.basis.z
	var right := h.global_transform.basis.x
	var st := _player.get_node_or_null("Stats") as Stats
	var speed_mult := clampf(st.get_stat("horse_speed_mult"), 0.3, 4.0) if st != null else 1.0
	var tire := 1.0 / clampf(st.get_stat("horse_stamina_mult"), 0.25, 10.0) if st != null else 1.0
	var speed := WALK * speed_mult
	if gallop and h.stamina > 1.0 and input_dir.y < 0.0:
		speed = GALLOP * speed_mult
		h.stamina -= 12.0 * delta * tire
	else:
		h.stamina = minf(h.stamina + 6.0 * delta, 100.0)
	var want := (fwd * -input_dir.y + right * input_dir.x * 0.4) * speed
	h.velocity.x = move_toward(h.velocity.x, want.x, 14.0 * delta)
	h.velocity.z = move_toward(h.velocity.z, want.z, 14.0 * delta)
	if Input.is_action_just_pressed("jump") and h.is_on_floor():
		h.velocity.y = 5.0
	h.move_and_slide()
	if input_dir != Vector2.ZERO:
		_ride_xp += delta * (1.6 if speed > WALK * speed_mult else 1.0)
		if _ride_xp >= 3.0:
			_ride_xp = 0.0
			var sk := _player.get_node_or_null("Skills") as Skills
			if sk != null:
				sk.add_xp(&"riding", 1.0)
	_player.global_position = h.global_position + Vector3.UP * 1.25
	_player.velocity = Vector3.ZERO


func _process(delta: float) -> void:
	_save_timer -= delta
	if _save_timer <= 0.0 and horse != null and is_instance_valid(horse):
		_save_timer = 5.0
		_remember()


func _remember() -> void:
	if horse != null and is_instance_valid(horse):
		WorldState.set_record("horse", {"pos": SaveUtil.vec3_to_array(horse.global_position), "yaw": horse.rotation.y})


func _restore() -> void:
	if not owns_horse() or (horse != null and is_instance_valid(horse)):
		return
	await get_tree().create_timer(1.0, false).timeout
	if horse != null and is_instance_valid(horse):
		return
	var rec := WorldState.get_record("horse")
	var pos := SaveUtil.array_to_vec3(rec.get("pos"), _player.global_position)
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null:
		world.ensure_area_loaded(pos)
	horse = Horse.spawn_at(get_tree().current_scene, pos + Vector3.UP * 0.5, float(rec.get("yaw", 0.0)))


# ---------------------------------------------------------------- 1.27: horse barding

## The armour your horse wears gives you this much armour while you ride
static func barding_armor() -> float:
	return float(WorldState.get_record("barding").get("armor", 0.0))


func _barding_on(on: bool) -> void:
	var st := _player.get_node_or_null("Stats") as Stats
	if st == null:
		return
	if on and barding_armor() > 0.0:
		st.add_modifiers("barding", {"armor": barding_armor()})
	else:
		st.remove_modifiers("barding")


## A barding from the inventory goes on your horse (it must be near). The old one comes back.
static func put_on_barding(player: Node, item: ItemData) -> String:
	var rider := player.get_node_or_null("Rider") as Rider
	if rider == null or rider.horse == null or not is_instance_valid(rider.horse) \
			or rider.horse.global_position.distance_to((player as Node3D).global_position) > 8.0:
		return "Your horse needs to be close by."
	var inv := player.get_node("Inventory") as Inventory
	var old := String(WorldState.get_record("barding").get("path", ""))
	var armor := float(item.stat_modifiers.get("barding_armor", 15.0))
	inv.remove_item(item, 1)
	if old != "" and ResourceLoader.exists(old):
		inv.add_item(load(old) as ItemData, 1)
	WorldState.set_record("barding", {"path": item.resource_path, "armor": armor, "name": item.display_name})
	if rider.is_riding():
		rider._barding_on(true)
	Achievements.note("barding")
	return "Your horse wears the %s now (+%d armour while you ride)." % [item.display_name, roundi(armor)]
