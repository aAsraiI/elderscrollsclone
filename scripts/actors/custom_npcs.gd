class_name CustomNpcs
extends Node
## Puts the hand-made people of data/npcs/custom/ (CustomNpcData) into the world. Created by
## WorldManager. Each appears when the player comes within NEAR meters of their spot and goes
## away beyond FAR. A killed one stays dead (WorldState "kill/custom/<id>").

const DIR := "res://data/npcs/custom"
const TOWNSFOLK := "res://data/npcs/townsfolk.tres"
const NEAR := 120.0
const FAR := 180.0

static var _list: Array[CustomNpcData] = []
static var _loaded := false

var world: WorldManager
var _timer := 0.0
var _spawned := {}  # save id -> Enemy


## Every CustomNpcData in data/npcs/custom/
static func all() -> Array[CustomNpcData]:
	if not _loaded:
		_loaded = true
		var names := PackedStringArray()
		for f in DirAccess.get_files_at(DIR):
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres") and not names.has(file):
				names.append(file)
		names.sort()
		for file in names:
			var d := load(DIR + "/" + file) as CustomNpcData
			if d != null:
				_list.append(d)
	return _list


func _ready() -> void:
	world = get_parent() as WorldManager


## Where this person stands in the world (Vector3.INF if their town doesn't exist)
func spot_of(d: CustomNpcData) -> Vector3:
	var at := d.world_position
	if d.town != "":
		at = Vector3.INF
		for t in world.towns:
			if t.town != null and t.town.display_name == d.town:
				at = t.position + d.offset
	if at.is_finite() and world != null:
		at.y = world.get_height_at(at.x, at.z)
	return at


func _process(delta: float) -> void:
	if world == null or get_tree().paused:
		return
	_timer += delta
	if _timer < 0.5:
		return
	_timer = 0.0
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or (world.dungeons != null and world.dungeons.is_inside()):
		return
	for d in all():
		var key := d.save_id()
		var at := spot_of(d)
		var e: Enemy = _spawned.get(key)
		if e != null and not is_instance_valid(e):
			_spawned.erase(key)
			e = null
		var dist := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() if at.is_finite() else INF
		if e == null and dist < NEAR and not WorldState.has_record("kill/" + key):
			_spawned[key] = spawn(d, world, at)
		elif e != null and dist > FAR and not e.is_dead():
			e.queue_free()
			_spawned.erase(key)


## Makes the person's body at a world position under `parent` (CustomNpcSpot uses this too)
static func spawn(d: CustomNpcData, parent: Node, at: Vector3) -> Enemy:
	var body := d.body if d.body != null else load(TOWNSFOLK) as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.seed = d.save_id().hash()
	var e := Enemy.create()
	body.apply(e, d.level, rng)
	e.display_name = d.display_name
	e.talk_name = d.display_name
	e.talk_lines = PackedStringArray([d.greeting]) if d.greeting != "" else PackedStringArray(["..."])
	e.disposition = Enemy.Disposition.FRIENDLY
	e.placeholder_color = d.color
	e.wander_radius = 0.0
	e.persist_mode = Enemy.PersistMode.NEVER
	e.spawn_key = d.save_id()
	e.set_meta("custom_npc", d)
	if d.greeting != "":
		e.set_meta("greeting", d.greeting)
	var host := parent as Node3D
	e.position = host.to_local(at + Vector3.UP * 0.6) if host != null and host.is_inside_tree() else at + Vector3.UP * 0.6
	e.rotation.y = rng.randf() * TAU
	parent.add_child(e)
	return e
