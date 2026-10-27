class_name LanternLight
extends Node3D
## A lantern worn in the Lantern slot (on the belt) lights the ground around you with a warm,
## slowly flickering light, and goes out when you take it off. Its light counts for stealth like
## any other, so carrying one lit makes you easier to see.

## How far it lights (m)
const RANGE := 9.0
const ENERGY := 1.25

var _light: OmniLight3D
var _equipment: Equipment
var _time := 0.0


## Puts a lantern light on `player` that follows its Equipment
static func attach(player: Node3D) -> LanternLight:
	var l := LanternLight.new()
	l.name = "LanternLight"
	player.add_child(l)
	return l


func _ready() -> void:
	# At the hip, a little to the side and in front, so it lights the way ahead and your feet
	position = Vector3(0.3, 0.95, -0.25)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color(1.0, 0.74, 0.45)
	_light.omni_range = RANGE
	_light.omni_attenuation = 1.4
	_light.light_energy = ENERGY
	_light.shadow_enabled = true
	_light.visible = false
	add_child(_light)
	_equipment = get_parent().get_node_or_null("Equipment") as Equipment
	if _equipment != null:
		_equipment.equipped.connect(func(_s: int, _i: ItemData) -> void: _refresh())
		_equipment.unequipped.connect(func(_s: int, _i: ItemData) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	_light.visible = is_lit()
	set_process(_light.visible)


## Is a lantern being carried?
func is_lit() -> bool:
	return _equipment != null and _equipment.get_equipped(ItemData.EquipSlot.LANTERN) != null


func _process(delta: float) -> void:
	_time += delta
	_light.light_energy = ENERGY * (0.92 + 0.05 * sin(_time * 7.3) + 0.03 * sin(_time * 17.1))
