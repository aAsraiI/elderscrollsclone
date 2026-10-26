class_name InteriorAtmosphere
extends Node3D
## The mood inside a stitched dungeon or a building: the theme's light and fog (PRESETS), fire
## lights that flicker, dust drifting in the air round the player, a sound hook per room (silent
## until the sound exists), and rooms far from you along the doorway graph hidden so big dungeons
## stay fast. DungeonManager adds one to every interior it builds and applies its fog and ambient.
##
## The preset's "dark" is how dark the place is for sneaking (Stealth.light_level's base).

## theme -> {ambient, fog (colour), density, dark, dust, sound}
const PRESETS := {
	"fort": {"ambient": Color(0.06, 0.05, 0.045), "fog": Color(0.10, 0.09, 0.08), "density": 0.02, "dark": 0.2, "dust": 0.6, "sound": "wind"},
	"crypt": {"ambient": Color(0.035, 0.035, 0.05), "fog": Color(0.06, 0.07, 0.09), "density": 0.04, "dark": 0.12, "dust": 1.0, "sound": "chant"},
	"cave": {"ambient": Color(0.03, 0.03, 0.035), "fog": Color(0.05, 0.06, 0.06), "density": 0.035, "dark": 0.1, "dust": 0.4, "sound": "drip"},
	"mine": {"ambient": Color(0.045, 0.035, 0.025), "fog": Color(0.08, 0.06, 0.04), "density": 0.03, "dark": 0.14, "dust": 1.0, "sound": "drip"},
	"sewer": {"ambient": Color(0.035, 0.045, 0.035), "fog": Color(0.07, 0.09, 0.06), "density": 0.05, "dark": 0.12, "dust": 0.2, "sound": "drip"},
	"ruin": {"ambient": Color(0.05, 0.055, 0.045), "fog": Color(0.09, 0.10, 0.08), "density": 0.025, "dark": 0.18, "dust": 0.8, "sound": "wind"},
	"lair": {"ambient": Color(0.05, 0.03, 0.03), "fog": Color(0.10, 0.05, 0.04), "density": 0.04, "dark": 0.14, "dust": 0.6, "sound": "chant"},
	"ice": {"ambient": Color(0.06, 0.07, 0.09), "fog": Color(0.18, 0.22, 0.26), "density": 0.03, "dark": 0.2, "dust": 0.3, "sound": "wind"},
	"house": {"ambient": Color(0.16, 0.13, 0.10), "fog": Color(0.0, 0.0, 0.0), "density": 0.0, "dark": 0.3, "dust": 0.35, "sound": "hearth"},
	"rich": {"ambient": Color(0.17, 0.14, 0.11), "fog": Color(0.0, 0.0, 0.0), "density": 0.0, "dark": 0.32, "dust": 0.2, "sound": "hearth"},
}
## Where each sound would come from (nothing plays until the file is there)
const SOUND_DIR := "res://audio/ambience/"
## Rooms more doorways than this from yours (and farther than NEAR_M) are hidden
const KEEP_LINKS := 3
const NEAR_M := 26.0

var theme := "fort"
var preset: Dictionary = {}
var plan: DungeonAssembler
var rooms: Array[RoomModule] = []
var _flames: Array = []  # [OmniLight3D, base energy, phase]
var _dust: CPUParticles3D
var _clock := 0.0
var _player_room := -1
var _adjacent := {}  # room index -> [room indices]
var hidden_rooms := 0
var _checked := false


## Makes the atmosphere for a built interior (call before it enters the tree)
static func make(root: Node3D, p_theme: String, p_plan: DungeonAssembler = null) -> InteriorAtmosphere:
	var a := InteriorAtmosphere.new()
	a.name = "Atmosphere"
	a.theme = p_theme if PRESETS.has(p_theme) else "fort"
	a.preset = PRESETS[a.theme]
	a.plan = p_plan
	for c in root.get_children():
		if c is RoomModule:
			a.rooms.append(c)
	root.add_child(a)
	a._find_flames(root)
	a._sound_hooks()
	a._make_dust()
	if p_plan != null:
		for l: Array in p_plan.links:
			a._adjacent[int(l[0])] = a._adjacent.get(int(l[0]), []) + [int(l[2])]
			a._adjacent[int(l[2])] = a._adjacent.get(int(l[2]), []) + [int(l[0])]
	return a


# Every fire light (the light of a candle, torch, brazier or hearth prop) flickers a little
func _find_flames(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for prop in root.find_children("*", "InteriorProp", true, false):
		var tags := (prop as InteriorProp).tags
		if not (tags.has("candle") or tags.has("torch") or tags.has("fire") or tags.has("brazier") or tags.has("hearth")):
			continue
		for l in prop.find_children("*", "OmniLight3D", true, false):
			_flames.append([l, (l as OmniLight3D).light_energy, rng.randf() * TAU])


# Each room gets a silent sound player named for what it would play (drip, wind, chant, hearth)
func _sound_hooks() -> void:
	for room in rooms:
		var t := String(room.themes[0]) if not room.themes.is_empty() else theme
		var key := String(PRESETS.get(t, preset).get("sound", ""))
		if key == "":
			continue
		var player := AudioStreamPlayer3D.new()
		player.name = "Ambience"
		player.set_meta("sound", key)
		player.unit_size = 6.0
		player.max_distance = 24.0
		var path := SOUND_DIR + key + ".ogg"
		if ResourceLoader.exists(path):
			player.stream = load(path) as AudioStream
			player.autoplay = true
		room.add_child(player)
		player.position = Vector3(0, 2.0, 0)


func _make_dust() -> void:
	var amount := int(48.0 * float(preset.get("dust", 0.0)))
	if amount <= 0:
		return
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = amount
	_dust.lifetime = 9.0
	_dust.preprocess = 9.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(7, 2.5, 7)
	_dust.direction = Vector3(0.3, 0.1, 0.2)
	_dust.spread = 180.0
	_dust.gravity = Vector3(0, -0.01, 0)
	_dust.initial_velocity_min = 0.02
	_dust.initial_velocity_max = 0.08
	_dust.scale_amount_min = 0.015
	_dust.scale_amount_max = 0.03
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.85, 0.7, 0.35)
	mesh.material = mat
	_dust.mesh = mesh
	_dust.local_coords = false
	add_child(_dust)


func _process(delta: float) -> void:
	_clock += delta
	for f: Array in _flames:
		var l := f[0] as OmniLight3D
		if is_instance_valid(l):
			var ph: float = f[2]
			l.light_energy = float(f[1]) * (0.88 + 0.08 * sin(_clock * 9.0 + ph) + 0.05 * sin(_clock * 23.0 + ph * 2.0))
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	if _dust != null:
		_dust.global_position = p.global_position + Vector3(0, 1.5, 0)
	if plan != null and int(_clock * 5.0) != int((_clock - delta) * 5.0):
		update_rooms(p.global_position)


## Shows the rooms near you along the doorway graph and hides the far ones (their walls, props and
## lights; anything living in them stays as it is)
func update_rooms(player_pos: Vector3) -> void:
	if plan == null or rooms.is_empty():
		return
	var root := get_parent() as Node3D
	var local := root.to_local(player_pos)
	var cell := Vector3i(floori(local.x / RoomModule.CELL), floori((local.y + 0.5) / RoomModule.LEVEL), floori(local.z / RoomModule.CELL))
	var here: int = plan.occupied.get(cell, _player_room)
	if here == _player_room and _checked:
		return
	_player_room = here
	_checked = true
	var dist := {here: 0}
	var queue := [here]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		if dist[r] >= KEEP_LINKS:
			continue
		for n: int in _adjacent.get(r, []):
			if not dist.has(n):
				dist[n] = dist[r] + 1
				queue.append(n)
	hidden_rooms = 0
	for i in rooms.size():
		var room := rooms[i]
		var near := dist.has(i) or room.global_position.distance_to(player_pos) < NEAR_M or here == -1
		_show_room(room, near)
		if not near:
			hidden_rooms += 1


# A room's drawing: its merged walls, its props and its lights (not its people)
func _show_room(room: RoomModule, on: bool) -> void:
	for c in room.get_children():
		if c is MeshInstance3D or c is InteriorProp or c is Light3D or c.name == "Shell":
			(c as Node3D).visible = on
