class_name WorldManager
extends Node3D
## Builds and streams the procedural world around the player.
##
## Setup: add a Node3D named World to your main scene and attach this script. That is all:
## with no Settings assigned it makes a small default world, finds the Player on its own, puts
## the player on the ground, and adds sky, fog and sun if your scene has none.
## Delete any old test floor, the terrain replaces it.
## To tinker: create a WorldSettings resource, drag it into "Settings" below.
##
## Population: points of interest with a Garrison get their creatures when their chunk loads (and
## lose them when it unloads), and an EncounterManager rolls random events around the player.
##
## Save compatibility: the world is rebuilt from the seed, so a save only needs to_dict() /
## from_dict(). Later systems (POIs, containers, ...) will key their saved changes by stable ids.

signal world_ready
## The world was regenerated (new seed). Anything that placed things in the old world must redo it.
signal world_rebuilt
signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
## A point of interest's structure was built (its chunk loaded) / removed (its chunk unloaded)
signal poi_spawned(placed: PlacedPOI, node: Node3D)
signal poi_removed(placed: PlacedPOI)

const TERRAIN_LAYER := 1  # physics layer 1 = world, same as everything else static

@export var settings: WorldSettings
## Optional. Found automatically (group "player", or a node named Player).
@export var player: Node3D
## Move the player to the spawn point when the world starts. Turn off when loading a save.
@export var move_player_to_spawn := true
## Adds a sky, fog and sun if the scene has no WorldEnvironment / DirectionalLight3D
@export var auto_environment := true
## Put the player back on the ground if they ever fall through the world
@export var rescue_fallen_player := true
## Creatures that live at points of interest (their Garrison)
@export var populate_pois := true
## Random events around the player, from the biome's Encounters
@export var encounters_enabled := true
## Day and night: the time of day (WorldClock), a moving sun, dark nights
@export var day_night_enabled := true
## Creates a SaveManager (F5 / F9 / F10 and the pause menu's Save / Load) if the scene has none
@export var auto_save_manager := true
## The people of the towns and their day (TownLife)
@export var town_life_enabled := true
## Travellers, merchants and road wardens on the roads near the player (RoadLife)
@export var road_life_enabled := true

var map: WorldMap
var world_seed := 0
## Every point of interest in the world (the plan: cheap data, not nodes). Towns are in here too.
var pois: Array[PlacedPOI] = []
## Just the villages, towns and cities (each has .town, its TownLayout)
var towns: Array[PlacedPOI] = []
var dungeons: DungeonManager
var encounters: EncounterManager
var clock: WorldClock
var life: TownLife
var crime: CrimeManager
var quests: QuestManager
var road_life: RoadLife
## Found places and fast travel
var discovery: Discovery

var _chunks := {}      # Vector2i -> TerrainChunk
var _inflight := {}    # Vector2i -> worker task id
var _finished: Array[Dictionary] = []
var _mutex := Mutex.new()
var _pending: Array[Vector2i] = []
var _wanted := {}
var _material: StandardMaterial3D
var _chunk_min := Vector2i.ZERO
var _chunk_max := Vector2i.ZERO
var _quads := 32
var _last_center := Vector2i(1 << 30, 1 << 30)
var _walls: Node3D
var _debug_map: WorldDebugMap
var _poi_by_id := {}      # String -> PlacedPOI
var _poi_by_chunk := {}   # Vector2i -> Array[PlacedPOI]
var _poi_nodes := {}      # String -> Node3D (only while the chunk is loaded)
var _poi_root: Node3D
var _garrisons := {}      # String -> Array[Enemy] (only while the POI's chunk is loaded)
var _garrison_root: Node3D
var _water: MeshInstance3D


func _ready() -> void:
	add_to_group("world_manager")
	if auto_save_manager and not _scene_has_save_manager():
		var sm := SaveManager.new()
		sm.name = "SaveManager"
		add_child(sm)
	if settings == null:
		settings = WorldSettings.create_default()
	# A loaded save (or a new game with a chosen seed) decides the seed, see SaveSession
	world_seed = SaveSession.get_seed(settings.world_seed)
	_make_material()
	_rebuild_map()
	_find_player()
	if player != null and move_player_to_spawn:
		if SaveSession.has_start_position():
			player.global_position = SaveSession.get_start_position()
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity = Vector3.ZERO
		else:
			_place_player_at_spawn()
	_load_initial()
	if auto_environment:
		_setup_environment()
	_make_water()
	dungeons = DungeonManager.new()
	dungeons.name = "DungeonManager"
	add_child(dungeons)
	encounters = EncounterManager.new()
	encounters.name = "EncounterManager"
	encounters.enabled = encounters_enabled
	add_child(encounters)
	clock = WorldClock.new()
	clock.name = "WorldClock"
	clock.control_environment = day_night_enabled
	add_child(clock)
	if town_life_enabled:
		life = TownLife.new()
		life.name = "TownLife"
		add_child(life)
	quests = QuestManager.new()
	quests.name = "QuestManager"
	add_child(quests)
	road_life = RoadLife.new()
	road_life.name = "RoadLife"
	road_life.enabled = road_life_enabled and settings.road_traffic
	add_child(road_life)
	crime = CrimeManager.new()
	crime.name = "CrimeManager"
	add_child(crime)
	discovery = Discovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	if settings.debug_map_enabled:
		_debug_map = WorldDebugMap.new()
		_debug_map.name = "WorldDebugMap"
		add_child(_debug_map)
	world_ready.emit()


func _exit_tree() -> void:
	_wait_for_tasks()


# ---------------------------------------------------------------- public API

func get_height_at(x: float, z: float) -> float:
	return map.get_height(x, z)


## The biome at a world position, or null outside the world
func get_biome_at(x: float, z: float) -> BiomeData:
	return map.get_biome_at(x, z)


## Builds the terrain around a position right now (no waiting for the background threads).
## Use before placing something that needs ground to land on, like loading a save.
func ensure_area_loaded(pos: Vector3, radius_chunks: int = 1) -> void:
	var center := _chunk_of(pos)
	for dz in range(-radius_chunks, radius_chunks + 1):
		for dx in range(-radius_chunks, radius_chunks + 1):
			_ensure_chunk(Vector2i(center.x + dx, center.y + dz))


func get_poi(id: String) -> PlacedPOI:
	return _poi_by_id.get(id)


## A town building by its id ("<town id>/b<n>"), or null
func get_building(id: String) -> BuildingPlot:
	var cut := id.rfind("/b")
	if cut < 0:
		return null
	var town := get_poi(id.substr(0, cut))
	if town == null or town.town == null or not id.substr(cut + 2).is_valid_int():
		return null
	return town.town.get_building(id.substr(cut + 2).to_int())


## The town whose ground this is (within `margin` meters of its edge), or null
func get_town_at(pos: Vector3, margin: float = 0.0) -> PlacedPOI:
	for t in towns:
		if t.town != null and t.town.contains(pos, margin):
			return t
	return null


## The town nearest to a position (null if there are no towns)
func get_nearest_town(pos: Vector3) -> PlacedPOI:
	var best: PlacedPOI = null
	for t in towns:
		if best == null or Vector2(t.position.x - pos.x, t.position.z - pos.z).length() < Vector2(best.position.x - pos.x, best.position.z - pos.z).length():
			best = t
	return best


## POIs within `radius` meters (flat distance) of a position, nearest first
func get_pois_near(pos: Vector3, radius: float) -> Array[PlacedPOI]:
	var found: Array[PlacedPOI] = []
	for p in pois:
		var dx := p.position.x - pos.x
		var dz := p.position.z - pos.z
		if dx * dx + dz * dz <= radius * radius:
			found.append(p)
	found.sort_custom(func(a: PlacedPOI, b: PlacedPOI) -> bool:
		return a.position.distance_squared_to(pos) < b.position.distance_squared_to(pos))
	return found


## The structure node of a POI, or null while its chunk is not loaded
func get_poi_node(id: String) -> Node3D:
	return _poi_nodes.get(id)


func get_loaded_chunk_count() -> int:
	return _chunks.size()


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)


## For the save file: the seed is the world. layout lets a load notice the layout was edited.
func to_dict() -> Dictionary:
	return {"seed": world_seed, "layout": settings.layout_hash()}


func from_dict(data: Dictionary) -> void:
	var saved_layout := int(data.get("layout", settings.layout_hash()))
	if saved_layout != settings.layout_hash():
		push_warning("World: this save was made with a different biome layout. Terrain may not match what you remember.")
	var saved_seed := int(data.get("seed", world_seed))
	if saved_seed != world_seed:
		rebuild(saved_seed)


## Throws the world away and generates it again, e.g. for a new seed or after loading a save
func rebuild(new_seed: int) -> void:
	_wait_for_tasks()
	for c in _chunks.keys():
		_remove_chunk(c)
	_clear_pois()
	world_seed = new_seed
	_rebuild_map()
	_last_center = Vector2i(1 << 30, 1 << 30)
	_find_player()
	if player != null:
		if move_player_to_spawn:
			_place_player_at_spawn()
		_load_initial()
	if _debug_map != null:
		_debug_map.invalidate()
	world_rebuilt.emit()


# ---------------------------------------------------------------- setup

func _make_material() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_material.metallic = 0.0


func _rebuild_map() -> void:
	for problem in settings.validate():
		push_warning("World: " + problem)
	map = WorldMap.new(settings, world_seed)
	_plan_pois()
	var cs := settings.chunk_size
	var b := map.get_bounds()
	_chunk_min = Vector2i(floori(b.position.x / cs), floori(b.position.y / cs))
	_chunk_max = Vector2i(ceili(b.end.x / cs) - 1, ceili(b.end.y / cs) - 1)
	_quads = clampi(roundi(cs / maxf(settings.vertex_spacing, 0.25)), 4, 128)
	_build_walls()


# Decides where every POI goes and levels the ground under them (before any terrain is built).
# Towns first (they need the most room), then the roads between them, then everything else, which
# keeps away from both.
func _plan_pois() -> void:
	var t0 := Time.get_ticks_msec()
	towns = SettlementPlanner.plan(map)
	map.set_pads(towns)
	SettlementPlanner.lay_out(map, towns)
	var t1 := Time.get_ticks_msec()
	map.set_roads(RoadPlanner.plan(map, towns))
	var t2 := Time.get_ticks_msec()
	pois = towns.duplicate()
	pois.append_array(POIPlanner.plan(map, towns))
	map.set_pads(pois)
	if not towns.is_empty():
		print("World: %d towns (%d ms), %d roads (%d ms)" % [towns.size(), t1 - t0, map.roads.get_roads().size(), t2 - t1])
	_poi_by_id.clear()
	_poi_by_chunk.clear()
	for p in pois:
		_poi_by_id[p.id] = p
		var c := p.get_anchor_chunk(settings.chunk_size)
		if not _poi_by_chunk.has(c):
			_poi_by_chunk[c] = []
		_poi_by_chunk[c].append(p)
	if _poi_root == null or not is_instance_valid(_poi_root):
		_poi_root = Node3D.new()
		_poi_root.name = "POIs"
		add_child(_poi_root)
	print("World: planned %d points of interest in %d ms" % [pois.size(), Time.get_ticks_msec() - t0])


func _spawn_pois_for_chunk(c: Vector2i) -> void:
	for p: PlacedPOI in _poi_by_chunk.get(c, []):
		if _poi_nodes.has(p.id):
			continue
		var node := p.poi.build(p, map)
		if node == null:
			continue
		node.name = "POI_%s" % p.poi.get_key()
		node.set_meta("poi_id", p.id)
		_poi_root.add_child(node)
		node.position = p.position
		node.rotation.y = p.yaw
		_poi_nodes[p.id] = node
		poi_spawned.emit(p, node)
		_spawn_garrison(p)


func _free_pois_for_chunk(c: Vector2i) -> void:
	for p: PlacedPOI in _poi_by_chunk.get(c, []):
		var node: Node3D = _poi_nodes.get(p.id)
		if node != null:
			_poi_nodes.erase(p.id)
			node.queue_free()
			_free_garrison(p.id)
			poi_removed.emit(p)


# The creatures of a point of interest, made when its chunk loads
func _spawn_garrison(p: PlacedPOI) -> void:
	if not populate_pois or p.poi.garrison == null or _garrisons.has(p.id):
		return
	if _garrison_root == null or not is_instance_valid(_garrison_root):
		_garrison_root = Node3D.new()
		_garrison_root.name = "Garrisons"
		add_child(_garrison_root)
	_garrisons[p.id] = Population.spawn_garrison(p, map, _garrison_root)
	if quests != null:
		for e in quests.on_garrison(p, _garrison_root):  # bandit chiefs wanted by guild jobs
			_garrisons[p.id].append(e)


## Adds a creature to a point of interest's garrison (it then comes and goes with its chunk)
func add_to_garrison(id: String, e: Enemy) -> void:
	if not _garrisons.has(id):
		_garrisons[id] = []
	_garrisons[id].append(e)


func _free_garrison(id: String) -> void:
	for e in _garrisons.get(id, []):
		if is_instance_valid(e) and not e.is_dead():
			e.queue_free()  # a living one is rebuilt when the chunk comes back; a corpse stays
	_garrisons.erase(id)


## The creatures currently standing at a point of interest (empty while its chunk is not loaded)
func get_garrison(id: String) -> Array:
	return _garrisons.get(id, [])


func _clear_pois() -> void:
	for id in _garrisons.keys():
		_free_garrison(id)
	for id in _poi_nodes.keys():
		var node: Node3D = _poi_nodes[id]
		if is_instance_valid(node):
			node.queue_free()
	_poi_nodes.clear()


func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null and get_parent() != null:
		player = get_parent().find_child("Player", true, false) as Node3D


func _place_player_at_spawn() -> void:
	var spawn := map.get_spawn_point()
	var town := get_nearest_town(spawn) if settings.start_in_town else null
	if town != null and town.town != null and not town.town.gates.is_empty():
		# On the road just outside the gate nearest the spawn point, looking into town
		var layout := town.town
		var gi := 0
		var gates := layout.get_gates_world()
		for i in gates.size():
			if gates[i].distance_squared_to(spawn) < gates[gi].distance_squared_to(spawn):
				gi = i
		var out := layout.get_gate_outward(gi)
		var at := gates[gi] + out * 10.0
		player.global_position = Vector3(at.x, map.get_height(at.x, at.z) + 1.5, at.z)
		player.rotation.y = atan2(out.x, out.z)  # -Z (forward) points back along -out, into town
	else:
		player.global_position = spawn + Vector3.UP * 1.5
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


# Invisible walls just outside the generated area. The cliff ring normally stops you long before.
func _build_walls() -> void:
	if _walls != null:
		_walls.queue_free()
	_walls = Node3D.new()
	_walls.name = "BorderWalls"
	add_child(_walls)
	var b := map.get_bounds()
	var t := 20.0
	var h := 4000.0
	var c := b.get_center()
	_add_wall(Vector3(c.x, 0.0, b.position.y - t * 0.5), Vector3(b.size.x + t * 2.0, h, t))
	_add_wall(Vector3(c.x, 0.0, b.end.y + t * 0.5), Vector3(b.size.x + t * 2.0, h, t))
	_add_wall(Vector3(b.position.x - t * 0.5, 0.0, c.y), Vector3(t, h, b.size.y))
	_add_wall(Vector3(b.end.x + t * 0.5, 0.0, c.y), Vector3(t, h, b.size.y))


func _add_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = TERRAIN_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_walls.add_child(body)
	body.position = pos


func _setup_environment() -> void:
	var host: Node = get_parent() if get_parent() != null else self
	if host.find_children("*", "WorldEnvironment", true, false).is_empty():
		var sky := Sky.new()
		sky.sky_material = ProceduralSkyMaterial.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		env.fog_light_color = Color(0.70, 0.78, 0.88)
		# Fog thick enough at the edge of the view distance to hide chunks appearing
		env.fog_density = 2.5 / (settings.view_distance_chunks * settings.chunk_size)
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
	if host.find_children("*", "DirectionalLight3D", true, false).is_empty():
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 200.0
		add_child(sun)


# ---------------------------------------------------------------- streaming

## The water surface: one big flat sheet at sea level that follows the player around
func _make_water() -> void:
	if _water != null:
		_water.queue_free()
		_water = null
	if not settings.water_enabled:
		return
	_water = MeshInstance3D.new()
	_water.name = "Water"
	var plane := PlaneMesh.new()
	var reach := settings.view_distance_chunks * settings.chunk_size * 2.4
	plane.size = Vector2(reach, reach)
	_water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.36, 0.52, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_water.position = Vector3(0.0, settings.sea_level, 0.0)


func _process(_delta: float) -> void:
	if map == null:
		return
	if _water != null and player != null and is_instance_valid(player):
		_water.position = Vector3(snappedf(player.global_position.x, 32.0), settings.sea_level, snappedf(player.global_position.z, 32.0))
	if player == null or not is_instance_valid(player):
		_find_player()
		if player == null:
			return
	var pos := player.global_position
	var center := _chunk_of(pos)
	if center != _last_center:
		_last_center = center
		_refresh_wanted(center)
	_ensure_ground_under(center)
	_dispatch_builds()
	_finalize_chunks()
	_rescue_player(pos, center)


func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / settings.chunk_size), floori(pos.z / settings.chunk_size))


func _in_range(c: Vector2i) -> bool:
	return c.x >= _chunk_min.x and c.x <= _chunk_max.x and c.y >= _chunk_min.y and c.y <= _chunk_max.y


# Decides which chunks should exist, queues missing ones nearest-first, drops far ones
func _refresh_wanted(center: Vector2i) -> void:
	var r := settings.view_distance_chunks
	_wanted.clear()
	var list: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			var c := Vector2i(center.x + dx, center.y + dz)
			if not _in_range(c):
				continue
			_wanted[c] = true
			if not _chunks.has(c) and not _inflight.has(c):
				list.append(c)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	_pending = list

	var keep := r + 1  # one chunk of slack so walking back and forth doesn't thrash
	for c in _chunks.keys():
		var d: Vector2i = c - center
		if d.x * d.x + d.y * d.y > keep * keep:
			_remove_chunk(c)


# Builds the player's chunk and its 8 neighbors right now if the background threads are late,
# so the player can never outrun the ground.
func _ensure_ground_under(center: Vector2i) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_ensure_chunk(Vector2i(center.x + dx, center.y + dz))


func _ensure_chunk(c: Vector2i) -> void:
	if not _in_range(c) or _chunks.has(c):
		return
	if _inflight.has(c):
		WorkerThreadPool.wait_for_task_completion(_inflight[c])
		_inflight.erase(c)
		_take_finished_for(c)
	else:
		_add_chunk(TerrainChunk.build_data(map, c, settings.chunk_size, _quads))


# A finished chunk may already be waiting in the queue; add it now
func _take_finished_for(c: Vector2i) -> void:
	_mutex.lock()
	var found := -1
	for i in _finished.size():
		if _finished[i]["coord"] == c:
			found = i
			break
	var data: Dictionary = {}
	if found >= 0:
		data = _finished[found]
		_finished.remove_at(found)
	_mutex.unlock()
	if not data.is_empty() and not _chunks.has(c):
		_add_chunk(data)


func _dispatch_builds() -> void:
	while not _pending.is_empty() and _inflight.size() < settings.max_build_tasks:
		var c: Vector2i = _pending.pop_front()
		if _chunks.has(c) or _inflight.has(c) or not _wanted.has(c):
			continue
		_inflight[c] = WorkerThreadPool.add_task(
			_build_task.bind(c, map, settings.chunk_size, _quads), false, "terrain chunk")


# Runs on a worker thread
func _build_task(c: Vector2i, m: WorldMap, chunk_size: float, quads: int) -> void:
	var data := TerrainChunk.build_data(m, c, chunk_size, quads)
	_mutex.lock()
	_finished.append(data)
	_mutex.unlock()


func _finalize_chunks() -> void:
	var budget := settings.max_chunks_per_frame
	while budget > 0:
		_mutex.lock()
		var data: Dictionary = {}
		if not _finished.is_empty():
			data = _finished.pop_front()
		_mutex.unlock()
		if data.is_empty():
			break
		var c: Vector2i = data["coord"]
		if _inflight.has(c):
			WorkerThreadPool.wait_for_task_completion(_inflight[c])  # already done, just cleans up
			_inflight.erase(c)
		if _wanted.has(c) and not _chunks.has(c):
			_add_chunk(data)
			budget -= 1


func _add_chunk(data: Dictionary) -> void:
	var c: Vector2i = data["coord"]
	var chunk := TerrainChunk.new()
	chunk.name = "Chunk_%d_%d" % [c.x, c.y]
	chunk.coord = c
	chunk.collision_layer = TERRAIN_LAYER
	chunk.collision_mask = 0
	chunk.position = Vector3(c.x * settings.chunk_size, 0.0, c.y * settings.chunk_size)
	add_child(chunk)
	chunk.apply(data, _material)
	_chunks[c] = chunk
	chunk_loaded.emit(c)
	_spawn_pois_for_chunk(c)


func _remove_chunk(c: Vector2i) -> void:
	var chunk: TerrainChunk = _chunks.get(c)
	if chunk == null:
		return
	_chunks.erase(c)
	chunk.queue_free()
	_free_pois_for_chunk(c)
	chunk_unloaded.emit(c)


func _load_initial() -> void:
	var start := map.get_spawn_point()
	if player != null:
		start = player.global_position
	var center := _chunk_of(start)
	var r := settings.spawn_radius_chunks
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := Vector2i(center.x + dx, center.y + dz)
			if _in_range(c) and not _chunks.has(c):
				_add_chunk(TerrainChunk.build_data(map, c, settings.chunk_size, _quads))
	_last_center = Vector2i(1 << 30, 1 << 30)  # makes the next frame queue the rest


func _wait_for_tasks() -> void:
	for c in _inflight.keys():
		WorkerThreadPool.wait_for_task_completion(_inflight[c])
	_inflight.clear()
	_mutex.lock()
	_finished.clear()
	_mutex.unlock()
	_pending.clear()


# Safety net: standing far below the ground on a loaded chunk means we fell through
func _rescue_player(pos: Vector3, center: Vector2i) -> void:
	if not rescue_fallen_player or not _chunks.has(center):
		return
	var ground := map.get_height(pos.x, pos.z)
	if pos.y < ground - 30.0 and pos.y > ground - 500.0:
		player.global_position = Vector3(pos.x, ground + 2.0, pos.z)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO


# A SaveManager placed in the scene by hand may not have run _ready yet, so look for it by type
func _scene_has_save_manager() -> bool:
	var top: Node = get_parent() if get_parent() != null else self
	for n in top.find_children("*", "", true, false):
		if n is SaveManager:
			return true
	return not get_tree().get_nodes_in_group("save_manager").is_empty()
