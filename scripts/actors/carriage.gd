class_name Carriage
extends StaticBody3D
## A carriage outside every city gate. E: pick another city and pay the driver; time passes on the
## road and you arrive at that city's carriage. Works even when fast travel is turned off for the
## world, because it is a paid trip, not a jump. Placed by TownBuilder.

const GOLD_PER_KM := 9
const MIN_PRICE := 25
const SPEED_KMH := 12.0

var town_id := ""
var _menu: CanvasLayer


func _ready() -> void:
	add_to_group("carriage")
	collision_layer = 1 | 4
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.0, 3.6)
	shape.shape = box
	shape.position.y = 1.0
	add_child(shape)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.15)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.55, 0.5, 0.4)
	_box(Vector3(2.0, 0.6, 3.4), Vector3(0, 0.9, 0), wood)
	_box(Vector3(2.0, 1.0, 2.2), Vector3(0, 1.7, 0.5), cloth)
	for x in [-1.05, 1.05]:
		for z in [-1.2, 1.2]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 0.1
			wheel.mesh = cyl
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(x, 0.5, z)
			wheel.material_override = wood
			add_child(wheel)


func _box(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = m
	add_child(mi)


func get_prompt() -> String:
	return "Take the carriage"


func _world() -> WorldManager:
	return get_tree().get_first_node_in_group("world_manager") as WorldManager


func _cities() -> Array[PlacedPOI]:
	var out: Array[PlacedPOI] = []
	var w := _world()
	if w == null:
		return out
	for t in w.towns:
		if t.id != town_id and t.poi is TownData and (t.poi as TownData).kind == TownData.Kind.CITY:
			out.append(t)
	return out


func price_to(t: PlacedPOI) -> int:
	var km := Vector2(t.position.x - global_position.x, t.position.z - global_position.z).length() / 1000.0
	return maxi(MIN_PRICE, roundi(km * GOLD_PER_KM))


func interact(actor: Inventory) -> void:
	if get_tree().get_first_node_in_group("player").has_meta("beast_form"):
		Locks.toast(get_tree(), "The driver runs screaming", true)
		return
	_open_menu(actor)


func _open_menu(actor: Inventory) -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 12
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UITheme.heading("Carriage"))
	v.add_child(UITheme.hint("Where to? You have %d gold." % Currency.get_gold(actor)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var w := _world()
	for t in _cities():
		var b := Button.new()
		var cost := price_to(t)
		var km := Vector2(t.position.x - global_position.x, t.position.z - global_position.z).length() / 1000.0
		b.text = "%s   %.1f km, %d h   %d gold" % [t.town.display_name if t.town != null else t.id, km, ceili(km / SPEED_KMH), cost]
		b.disabled = Currency.get_gold(actor) < cost
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _travel(t, actor))
		list.add_child(b)
	var close := Button.new()
	close.text = "Stay here"
	close.pressed.connect(_close)
	v.add_child(close)
	get_tree().root.add_child(_menu)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if w == null:
		_close()


func _close() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _travel(t: PlacedPOI, actor: Inventory) -> void:
	var cost := price_to(t)
	_close()
	if not Currency.spend_gold(actor, cost):
		return
	var w := _world()
	var km := Vector2(t.position.x - global_position.x, t.position.z - global_position.z).length() / 1000.0
	var spot := Carriage.stop_for(t)
	w.ensure_area_loaded(spot, 1)
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	p.global_position = Vector3(spot.x, w.get_height_at(spot.x, spot.z) + 1.2, spot.z)
	p.velocity = Vector3.ZERO
	if w.clock != null:
		w.clock.advance_hours(km / SPEED_KMH)
	var weather := Weather.get_instance(get_tree())
	if weather != null:
		weather.hours_left -= km / SPEED_KMH
	if w.discovery != null:
		w.discovery.mark_found(t)
	Locks.toast(get_tree(), "You arrive at %s" % (t.town.display_name if t.town != null else ""))


## Where a city's carriage stands (local to the world), just outside its first gate
static func stop_for(t: PlacedPOI) -> Vector3:
	var layout := t.town
	if layout == null or layout.gates.is_empty():
		return t.position + Vector3(0, 0, t.poi.footprint_radius + 10.0)
	var gate := layout.gates[0]
	var out := gate.normalized()
	return layout.to_world(gate + out * 10.0 + Vector3(-out.z, 0, out.x) * 4.0)
