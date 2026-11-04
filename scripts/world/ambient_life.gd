class_name AmbientLife
extends Node
## Alpha 1.24: the small life around you outside (Critter): rabbits, squirrels, frogs (more in rain,
## by water), birds overhead by day, bats and owls at night, crows that come down to a body left in
## the open, and fireflies on warm nights. At most MAX near you, one new one every few seconds, each
## gone once it is 60 m behind you. Created by WorldManager.

const MAX := 8
const EVERY := 2.5
const NEAR := 18.0
const FAR := 40.0
const GONE := 60.0

## What each small creature looks like and does
const KINDS := {
	"rabbit": {"model": "creature/giant_rat", "tint": Color(0.55, 0.47, 0.38), "size": 0.32, "speed": 3.4, "move": 0,
		"drops": [["res://data/materials/raw_meat.tres", 0.7], ["res://data/materials/animal_hide.tres", 0.3]]},
	"squirrel": {"model": "creature/giant_rat", "tint": Color(0.62, 0.32, 0.16), "size": 0.22, "speed": 3.8, "move": 0, "drops": []},
	"frog": {"model": "creature/bog_lurker", "tint": Color(0.35, 0.55, 0.25), "size": 0.16, "speed": 1.6, "move": 0, "drops": []},
	"bird": {"model": "creature/harpy", "tint": Color(0.3, 0.28, 0.26), "size": 0.3, "speed": 9.0, "move": 1, "drops": []},
	"bat": {"model": "creature/harpy", "tint": Color(0.12, 0.1, 0.1), "size": 0.25, "speed": 11.0, "move": 1, "drops": []},
	"owl": {"model": "creature/harpy", "tint": Color(0.5, 0.4, 0.3), "size": 0.35, "speed": 6.0, "move": 1, "drops": []},
	"crow": {"model": "creature/harpy", "tint": Color(0.06, 0.06, 0.07), "size": 0.28, "speed": 1.2, "move": 0, "drops": []},
}

## Which small life each land has by day (night: bats and owls everywhere outside the desert)
const LANDS := {
	"forest": ["rabbit", "squirrel", "squirrel", "bird", "frog"], "plains": ["rabbit", "rabbit", "bird", "bird"],
	"highlands": ["rabbit", "bird"], "lakeland": ["frog", "frog", "rabbit", "bird"], "swamp": ["frog", "frog", "frog", "bird"],
	"coast": ["bird", "bird"], "tundra": ["rabbit", "bird"], "snow_mountains": ["bird"], "badlands": ["rabbit", "bird"],
	"desert": ["bird"], "ashlands": [], "deadlands": ["crow", "crow"], "frozen_crown": [], "default": ["rabbit", "bird"],
}

var world: WorldManager
var enabled := true
var _timer := 2.0
var _crow_t := 5.0
var _fireflies: GPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("ambient_life")
	world = get_parent() as WorldManager
	_rng.randomize()


func _process(delta: float) -> void:
	if world == null or world.map == null or get_tree().paused:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var inside := world.dungeons != null and world.dungeons.is_inside()
	_timer -= delta
	if _timer <= 0.0:
		_timer = EVERY
		_clean(p, inside)
		if enabled and not inside:
			_spawn(p)
	_crow_t -= delta
	if _crow_t <= 0.0:
		_crow_t = 6.0
		if enabled and not inside:
			_crows(p)
	_tick_fireflies(p, inside)


func _spawn(p: Node3D) -> void:
	if get_tree().get_nodes_in_group("critters").size() >= MAX:
		return
	var night := world.clock != null and world.clock.is_night()
	var land := _land(p.global_position)
	var raining := world.weather != null and world.weather.current in [Weather.Kind.RAIN, Weather.Kind.STORM]
	var pool: Array = []
	if night:
		if land != "desert" and land != "ashlands":
			pool = ["bat", "bat", "owl"]
	else:
		pool = (LANDS.get(land, LANDS["default"]) as Array).duplicate()
	if raining and land in ["forest", "lakeland", "swamp", "plains"]:
		pool.append_array(["frog", "frog"])  # frogs come out in the rain
	if world.clock != null and world.clock.get_season() == 0:
		pool.erase("frog")  # and sleep through the winter
		pool.erase("squirrel")
	if pool.is_empty():
		return
	var kind: String = pool[_rng.randi() % pool.size()]
	var ang := _rng.randf() * TAU
	var d := _rng.randf_range(NEAR, FAR)
	var x := p.global_position.x + cos(ang) * d
	var z := p.global_position.z + sin(ang) * d
	var y := world.get_height_at(x, z)
	if y < world.map.get_water_level(x, z) and kind != "bird" and kind != "bat" and kind != "owl":
		return
	world.add_child(Critter.make(kind, Vector3(x, y, z), world))


# Crows come down to a body lying in the open a while
func _crows(p: Node3D) -> void:
	var night := world.clock != null and world.clock.is_night()
	if night:
		return
	var crows := 0
	for c in get_tree().get_nodes_in_group("critters"):
		if (c as Critter).kind == "crow":
			crows += 1
	if crows >= 4:
		return
	for n in get_tree().get_nodes_in_group("persistent"):
		var e := n as Enemy
		if e == null or not e.is_dead() or not e.is_inside_tree():
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d < 14.0 or d > 50.0 or e.has_meta("crowed"):
			continue
		e.set_meta("crowed", true)
		for i in _rng.randi_range(1, 3):
			var at := e.global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
			at.y = world.get_height_at(at.x, at.z)
			var c := Critter.make("crow", at, world)
			world.add_child(c)
		return


func _clean(p: Node3D, inside: bool) -> void:
	for c in get_tree().get_nodes_in_group("critters"):
		var cr := c as Critter
		if inside or cr.global_position.distance_to(p.global_position) > GONE:
			cr.queue_free()


# Fireflies over the grass on a warm night: one emitter that follows you
func _tick_fireflies(p: Node3D, inside: bool) -> void:
	var want := enabled and not inside and world.clock != null and world.clock.is_night() and world.clock.get_season() in [1, 2] \
			and world.weather != null and world.weather.current in [Weather.Kind.CLEAR, Weather.Kind.CLOUDY] \
			and _land(p.global_position) in ["forest", "plains", "lakeland", "swamp", "highlands", "default"]
	if want and _fireflies == null:
		_fireflies = _make_fireflies()
		world.add_child(_fireflies)
	elif not want and _fireflies != null:
		_fireflies.queue_free()
		_fireflies = null
	if _fireflies != null:
		_fireflies.global_position = p.global_position


func _make_fireflies() -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.name = "Fireflies"
	g.amount = 60
	g.lifetime = 6.0
	g.visibility_aabb = AABB(Vector3(-25, -3, -25), Vector3(50, 8, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1.2, 22)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 0.6, 0))
	fade.add_point(0.3, Color(1, 1, 0.6, 1))
	fade.add_point(0.7, Color(1, 1, 0.6, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 0.6, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	g.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.9, 1.0, 0.4)
	mat.emission_energy_multiplier = 3.0
	quad.material = mat
	g.draw_pass_1 = quad
	g.position.y = 0.8
	return g


func _land(pos: Vector3) -> String:
	var b := world.get_biome_at(pos.x, pos.z)
	return String(b.id) if b != null else "default"
