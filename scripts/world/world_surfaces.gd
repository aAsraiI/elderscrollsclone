class_name WorldSurfaces
extends Node
## Alpha 1.24 (immersive sim): the elements as rules of the world, on the ground where things happen.
##   oil     a pool from a thrown Flask of Oil; fire lights it (a hot, big fire)
##   water   puddles form in the rain; water puts fire out; frost freezes it; shock runs through it
##   fire    burns whoever stands in it; spreads across dry grass outside (with the wind, not in rain)
##   ice     frost on a puddle, or on a river or lake, makes ice you can walk on for a while
## A fire, frost or shock spell (or a fire arrow) landing does what it does to whatever is there
## (react()). Shock also arcs to anyone in metal armour close by. A surface is a flat disc and a
## radius: actors are checked four times a second against the few that exist. Created by WorldManager.

enum Kind { OIL, WATER, FIRE, ICE }

const TICK := 0.25
const MAX := 40
const FIRE_DPS := 9.0
const OIL_FIRE_DPS := 16.0
const SPREAD_EVERY := 1.6
const GRASS_FIRE_LIMIT := 14
const ICE_SECONDS := 25.0
const SHOCK_ARC := 3.5
const RAIN_PUDDLE_EVERY := 12.0

const COLORS := {Kind.OIL: Color(0.08, 0.07, 0.05, 0.85), Kind.WATER: Color(0.3, 0.4, 0.5, 0.55),
	Kind.FIRE: Color(1.0, 0.45, 0.1, 0.9), Kind.ICE: Color(0.75, 0.9, 1.0, 0.8)}

class Surface:
	var kind: int
	var at: Vector3
	var radius := 1.5
	var life := 60.0
	var oily := false  # a fire burning oil
	var grass := false  # a grass fire (it spreads)
	var node: Node3D
	var spread_t := 0.0

var world: WorldManager
var surfaces: Array[Surface] = []
var _t := 0.0
var _rain_t := RAIN_PUDDLE_EVERY
var _grass_fires := 0


func _ready() -> void:
	add_to_group("world_surfaces")
	world = get_parent() as WorldManager


static func of(tree: SceneTree) -> WorldSurfaces:
	return tree.get_first_node_in_group("world_surfaces") as WorldSurfaces if tree != null else null


# ---------------------------------------------------------------- making surfaces

func add(kind: int, at: Vector3, radius: float, life: float) -> Surface:
	if surfaces.size() >= MAX:
		_remove(surfaces[0])
	var s := Surface.new()
	s.kind = kind
	s.at = at
	s.radius = radius
	s.life = life
	s.node = _disc(kind, radius)
	world.add_child(s.node)
	s.node.global_position = at + Vector3.UP * 0.03
	surfaces.append(s)
	return s


func _disc(kind: int, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Surface_%d" % kind
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 16
	mi.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[kind]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05 if kind in [Kind.OIL, Kind.WATER, Kind.ICE] else 0.9
	mat.metallic = 0.3 if kind == Kind.ICE else 0.0
	if kind == Kind.FIRE:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.05)
		mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if kind == Kind.FIRE:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.light_energy = 1.6
		l.omni_range = radius * 3.0
		l.position.y = 0.8
		l.distance_fade_enabled = true
		l.distance_fade_begin = 40.0
		root.add_child(l)
		var flames := CPUParticles3D.new()
		flames.amount = int(clampf(radius * 10.0, 8, 40))
		flames.lifetime = 0.8
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		flames.emission_sphere_radius = radius * 0.8
		flames.direction = Vector3.UP
		flames.initial_velocity_min = 1.0
		flames.initial_velocity_max = 2.4
		flames.gravity = Vector3(0, 1.0, 0)
		flames.scale_amount_min = 0.3
		flames.scale_amount_max = 0.7
		flames.color = Color(1.0, 0.55, 0.15)
		var q := QuadMesh.new()
		q.size = Vector2(0.4, 0.4)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		q.material = qm
		flames.mesh = q
		root.add_child(flames)
	if kind == Kind.ICE:
		var body := StaticBody3D.new()  # ice you can stand on
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 0.3
		cs.shape = cyl
		cs.position.y = -0.12
		body.add_child(cs)
		root.add_child(body)
	return root


func _remove(s: Surface) -> void:
	if s.grass:
		_grass_fires -= 1
	if is_instance_valid(s.node):
		s.node.queue_free()
	surfaces.erase(s)


## The surfaces touching a point
func at_point(p: Vector3, extra: float = 0.0) -> Array[Surface]:
	var out: Array[Surface] = []
	for s in surfaces:
		if Vector2(s.at.x - p.x, s.at.z - p.z).length() <= s.radius + extra and absf(s.at.y - p.y) < 2.5:
			out.append(s)
	return out


# ---------------------------------------------------------------- the elements meet the world

## An element arrives at a point (a spell bursting, a fire arrow): what happens to what is there
func react(p: Vector3, element: StringName, power: float = 1.0, source: Node = null, area: float = 1.0) -> void:
	var here := at_point(p, maxf(area, 0.5))
	match element:
		&"fire":
			var lit := false
			for s in here:
				if s.kind == Kind.OIL:
					_ignite(s, true)
					lit = true
				elif s.kind == Kind.ICE:
					_melt(s)
			if not lit and _dry_grass(p):
				var f := add(Kind.FIRE, _ground(p), 1.6, 9.0)
				f.grass = true
				_grass_fires += 1
		&"frost":
			for s in here:
				if s.kind == Kind.WATER:
					_freeze(s)
				elif s.kind == Kind.FIRE:
					_remove(s)
			if here.is_empty() and _over_water(p):
				add(Kind.ICE, Vector3(p.x, world.map.get_water_level(p.x, p.z), p.z), 2.6 * maxf(area, 1.0), ICE_SECONDS)
		&"shock":
			var wet: Array[Surface] = []
			for s in here:
				if s.kind == Kind.WATER:
					wet.append(s)
			for s in wet:
				for e in ActorRegistry.near(s.at, s.radius + 0.5):
					_zap(e, 12.0 * power, source)
				if _player_in(s):
					_zap(get_tree().get_first_node_in_group("player"), 12.0 * power, source)
			# metal armour carries it on to whoever is close
			for e in ActorRegistry.near(p, SHOCK_ARC):
				if _metal(e):
					_zap(e, 8.0 * power, source)


func _ignite(s: Surface, oil: bool) -> void:
	var at := s.at
	var r := s.radius
	_remove(s)
	var f := add(Kind.FIRE, at, r * (1.3 if oil else 1.0), 12.0 if oil else 8.0)
	f.oily = oil
	SoundFX.at(get_tree(), at, "boom", 60.0, 0.7)


func _freeze(s: Surface) -> void:
	var at := s.at
	var r := s.radius
	_remove(s)
	add(Kind.ICE, at, r, ICE_SECONDS)


func _melt(s: Surface) -> void:
	var at := s.at
	var r := s.radius
	_remove(s)
	add(Kind.WATER, at, r, 40.0)


func _zap(target: Node, amount: float, source: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var m := ActiveMagic.of(target)
	if m != null:
		m.apply_list([{"id": &"shock_damage", "mag": amount, "dur": 0.0}], source, "Shock", "spell", 1.0)


static func _metal(e: Node) -> bool:
	var en := e as Enemy
	if en == null or en.equipment == null:
		return false
	var chest: ItemData = en.equipment.get_equipped(ItemData.EquipSlot.CHEST)
	return chest != null and chest.governing_skill == "heavy_armor"


# ---------------------------------------------------------------- every tick

func _process(delta: float) -> void:
	if world == null or get_tree().paused:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var raining := world.weather != null and world.weather.current in [Weather.Kind.RAIN, Weather.Kind.STORM]
	var inside := world.dungeons != null and world.dungeons.is_inside()
	for s in surfaces.duplicate():
		s.life -= TICK * (3.0 if raining and s.kind == Kind.FIRE and not inside else 1.0)  # rain puts fires out
		if s.life <= 0.0:
			if s.kind == Kind.ICE:
				_melt(s)
			else:
				_remove(s)
			continue
		if s.kind == Kind.FIRE:
			_burn(s)
			# water puts it out
			for o in at_point(s.at, s.radius):
				if o != s and o.kind == Kind.WATER:
					_remove(s)
					break
			if s.grass and not raining:
				s.spread_t -= TICK
				if s.spread_t <= 0.0:
					s.spread_t = SPREAD_EVERY
					_spread(s)
	if raining and not inside:
		_rain_t -= TICK
		if _rain_t <= 0.0:
			_rain_t = RAIN_PUDDLE_EVERY
			_rain_puddle()


# Whoever stands in a fire burns
func _burn(s: Surface) -> void:
	var dps := OIL_FIRE_DPS if s.oily else FIRE_DPS
	for e in ActorRegistry.near(s.at, s.radius):
		_scorch(e, dps * TICK)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and _player_in(s):
		_scorch(p, dps * TICK)


func _scorch(target: Node, amount: float) -> void:
	var m := ActiveMagic.of(target)
	if m != null:
		m.apply_list([{"id": &"fire_damage", "mag": amount, "dur": 0.0}], null, "Fire", "spell", 1.0)


func _player_in(s: Surface) -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p != null and Vector2(p.global_position.x - s.at.x, p.global_position.z - s.at.z).length() <= s.radius and absf(p.global_position.y - s.at.y) < 2.0


# A grass fire creeps on with the wind (a few patches at most)
func _spread(s: Surface) -> void:
	if _grass_fires >= GRASS_FIRE_LIMIT:
		return
	var wind := Vector2(1, 0)
	var wl := get_tree().get_first_node_in_group("wild_life") as WildLife
	if wl != null:
		wind = wl.wind_dir()
	var ang := atan2(wind.y, wind.x) + randf_range(-0.9, 0.9)
	var to := s.at + Vector3(cos(ang), 0, sin(ang)) * s.radius * 1.6
	if not _dry_grass(to) or not at_point(to, 0.5).filter(func(o): return o.kind == Kind.FIRE).is_empty():
		return
	var f := add(Kind.FIRE, _ground(to), 1.6, 9.0)
	f.grass = true
	_grass_fires += 1


func _rain_puddle() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var at := p.global_position + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
	var g := _ground(at)
	if g.y < world.map.get_water_level(g.x, g.z):
		return
	add(Kind.WATER, g, randf_range(0.8, 1.6), 90.0)


# ---------------------------------------------------------------- the ground

func _ground(p: Vector3) -> Vector3:
	if world.dungeons != null and world.dungeons.is_inside():
		return Vector3(p.x, p.y, p.z)
	return Vector3(p.x, world.get_height_at(p.x, p.z), p.z)


func _dry_grass(p: Vector3) -> bool:
	if world.dungeons != null and world.dungeons.is_inside():
		return false
	if world.weather != null and world.weather.current in [Weather.Kind.RAIN, Weather.Kind.STORM, Weather.Kind.SNOW, Weather.Kind.BLIZZARD]:
		return false
	var b := world.get_biome_at(p.x, p.z)
	return b != null and String(b.id) in ["plains", "forest", "highlands", "badlands", "lakeland"] and world.get_town_at(p, 0.0) == null


func _over_water(p: Vector3) -> bool:
	if world.dungeons != null and world.dungeons.is_inside() or world.map == null:
		return false
	return world.get_height_at(p.x, p.z) < world.map.get_water_level(p.x, p.z) - 0.2
