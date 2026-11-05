class_name Climbing
extends RefCounted
## Alpha 1.31.3: climbing cliffs. Against a steep rock face, hold Jump and walk forward to climb: it
## tires you (run out of stamina and you drop), and it trains Acrobatics, which also makes you
## faster and steadier. Built walls are too sheer. A Rope (E in the inventory) thrown up a cliff
## makes a line you climb like a ladder, for free, as long as you stay around.

const SPEED := 1.6
const SPEED_PER_LEVEL := 0.012
const STAMINA_PER_SEC := 9.0
const MIN_SLOPE_Y := 0.03  # a surface's normal must lean this far up: rock, not a sheer wall
const ROPE := "res://data/clutter/rope.tres"
const ROPE_MIN := 2.5
const ROPE_MAX := 28.0

static var _xp_t := 0.0


## player.gd asks each physics step: is the player climbing now? If so it moves them up.
static func step(p: CharacterBody3D, stats: Stats, skills: Skills, delta: float) -> bool:
	if not Input.is_action_pressed("jump") or not Input.is_action_pressed("move_forward"):
		return false
	if not p.is_on_wall() or p.get_slide_collision_count() == 0:
		return false
	if not rock_face(p.get_last_slide_collision().get_normal()):
		return false
	if stats != null and stats.stamina <= 1.0:
		return false
	var lvl := float(skills.get_level(&"acrobatics")) if skills != null else 15.0
	if stats != null:
		stats.modify_vital("stamina", -STAMINA_PER_SEC * clampf(1.0 - lvl / 250.0, 0.4, 1.0) * delta)
	p.velocity.y = SPEED + lvl * SPEED_PER_LEVEL
	_xp_t += delta
	if _xp_t >= 2.0:
		_xp_t = 0.0
		if skills != null:
			skills.add_xp(&"acrobatics", 2.0)
		Achievements.note("climb")
	return true


static func rock_face(normal: Vector3) -> bool:
	return normal.y >= MIN_SLOPE_Y


## A rope thrown up the cliff you face. Returns what was said.
static func throw_rope(player: Node3D, rope: ItemData) -> String:
	var w := player.get_tree().get_first_node_in_group("world_manager") as WorldManager
	if w == null or (w.dungeons != null and w.dungeons.is_inside()):
		return "Nothing to throw it over here."
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var base := player.global_position
	var top := base.y
	for d: float in [2.0, 3.0, 4.0, 6.0, 8.0]:
		var q := base + fwd * d
		top = maxf(top, w.get_height_at(q.x, q.z))
	var climb := top - base.y
	if climb < ROPE_MIN:
		return "There's no cliff to throw it up here."
	if climb > ROPE_MAX:
		return "Too high for your rope to reach."
	var l := Ladder.new()
	l.height = climb + 0.5
	l.add_to_group("thrown_ropes")
	player.get_tree().current_scene.add_child(l)
	l.global_position = base + fwd * 0.7
	l.look_at(l.global_position + fwd, Vector3.UP)
	var line := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, l.height, 0.06)
	line.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.3)
	line.material_override = mat
	line.position.y = l.height * 0.5
	l.add_child(line)
	(player.get_node("Inventory") as Inventory).remove_item(rope, 1)
	player.get_tree().create_timer(300.0, false).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())
	Achievements.note("rope")
	return "The rope catches above. W climbs it."
