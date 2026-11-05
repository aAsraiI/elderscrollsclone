class_name PuzzleSite
extends Node3D
## Alpha 1.31.2: an old place shut with a puzzle (a site of WorldSites). A stone plinth holds a chest
## under a stone cage; solve the puzzle and the cage sinks. The plaque (E) gives the clue.
##   levers   four levers, pulled in the right order. A wrong one and they all reset.
##   pillars  three pillars with a sign on each face (Sun, Moon, Star, Flame). E turns one.
##   mirrors  a sunstone throws a beam; turn two mirrors until the light reaches the lens.
## Solved ones stay open (WorldState "site/<id>/solved"). Lore 25 reads a clue more plainly.

const FORMS := ["levers", "pillars", "mirrors"]
const NAMES := {"levers": "The Lever Vault", "pillars": "The Turning Pillars", "mirrors": "The Sunstone Lens"}
const SIGNS := ["Sun", "Moon", "Star", "Flame"]
const DIRS := ["north", "east", "south", "west"]
const STONE := Color(0.4, 0.39, 0.36)

var site_id := ""
var form := "levers"
var order: Array = []   # levers: the order; pillars: the sign each must show; mirrors: the turn each must have
var state: Array = []   # levers: [how many right so far]; pillars, mirrors: what each shows
var _cage: Node3D
var _beams: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


static func make(root: Node3D, s: Dictionary) -> PuzzleSite:
	var p := PuzzleSite.new()
	p.site_id = String(s["id"])
	p.form = String(s["form"])
	root.add_child(p)
	p._make(root, s)
	return p


static func solved(id: String) -> bool:
	return WorldState.has_record("site/%s/solved" % id)


func _make(root: Node3D, s: Dictionary) -> void:
	_rng.seed = site_id.hash()
	POIBuilder.add_box(self, Vector3(16, 0.5, 16), Vector3(0, 0.1, 0), STONE.darkened(0.2))
	for c in [Vector3(-7.5, 0, -7.5), Vector3(7.5, 0, -7.5), Vector3(-7.5, 0, 7.5), Vector3(7.5, 0, 7.5)]:
		POIBuilder.add_box(self, Vector3(1.1, 4.0, 1.1), c + Vector3(0, 2.2, 0), STONE)
	# the chest and its cage
	var level := LevelCurve.place_level((get_tree().get_first_node_in_group("world_manager") as WorldManager).map, s["pos"])
	var chest := POIBuilder.make_chest("Sealed Chest", ItemCatalog.enemy_loot(level, 2.5), "site/%s/chest" % site_id, absi(site_id.hash()))
	add_child(chest)
	chest.position = Vector3(0, 0.75, -4.0)
	if not solved(site_id):
		_cage = Node3D.new()
		add_child(_cage)
		POIBuilder.add_box(_cage, Vector3(2.4, 2.4, 2.4), Vector3(0, 1.4, -4.0), STONE.lightened(0.05))
	_piece("plaque", 0, Vector3(0, 0.9, 6.5), Vector3(1.6, 1.3, 0.3))
	match form:
		"levers":
			order = [0, 1, 2, 3]
			_shuffle(order)
			state = [0]
			for i in 4:
				_piece("lever", i, [Vector3(0, 0.8, -6.5), Vector3(6.5, 0.8, 0), Vector3(0, 0.8, 3.5), Vector3(-6.5, 0.8, 0)][i], Vector3(0.3, 1.3, 0.3))
		"pillars":
			for i in 3:
				order.append(_rng.randi() % SIGNS.size())
				var start: int = (int(order[i]) + 1 + _rng.randi() % 3) % SIGNS.size()
				state.append(start)
				_piece("pillar", i, Vector3(-4.0 + i * 4.0, 1.2, 1.5), Vector3(1.2, 2.2, 1.2))
		"mirrors":
			order = [1, 2]  # the turn that sends the beam on
			state = [(1 + 1 + _rng.randi() % 3) % 4, (2 + 1 + _rng.randi() % 3) % 4]
			POIBuilder.add_box(self, Vector3(0.8, 1.6, 0.8), Vector3(-5, 0.9, 3), Color(0.9, 0.75, 0.3), 0.0, Vector3.ZERO, true, true)  # the sunstone
			POIBuilder.add_box(self, Vector3(0.8, 1.6, 0.3), Vector3(5, 1.0, -2), Color(0.5, 0.7, 0.9), 0.0, Vector3.ZERO, true, true)  # the lens
			_piece("mirror", 0, Vector3(5, 0.9, 3), Vector3(1.0, 1.6, 0.25))
			_piece("mirror", 1, Vector3(5, 0.9, 0.5), Vector3(1.0, 1.6, 0.25))
			_beam(Vector3(-5, 1.2, 3), Vector3(5, 1.2, 3), true)
			_beam(Vector3(5, 1.2, 3), Vector3(5, 1.2, 0.5), false)
			_beam(Vector3(5, 1.2, 0.5), Vector3(5, 1.2, -2), false)
			_update_beams()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func _beam(from: Vector3, to: Vector3, always: bool) -> void:
	var b := POIBuilder.add_box(self, Vector3(0.1, 0.1, from.distance_to(to)), (from + to) * 0.5, Color(1.0, 0.9, 0.5), 0.0, Vector3.ZERO, false, true)
	b.look_at_from_position(global_transform * ((from + to) * 0.5), global_transform * to, Vector3.UP)
	if not always:
		_beams.append(b)


func _update_beams() -> void:
	if _beams.size() < 2:
		return
	_beams[0].visible = int(state[0]) == int(order[0]) or solved(site_id)
	_beams[1].visible = _beams[0].visible and (int(state[1]) == int(order[1]) or solved(site_id))


func _piece(what: String, index: int, at: Vector3, size: Vector3) -> void:
	var col := {"plaque": Color(0.6, 0.55, 0.42), "lever": Color(0.3, 0.26, 0.2), "pillar": STONE.lightened(0.1), "mirror": Color(0.7, 0.75, 0.8)}[what] as Color
	var p := Piece.new()
	p.site = self
	p.what = what
	p.index = index
	add_child(p)
	p.position = at
	p.make(size, col)


func clue() -> String:
	var lore := 0
	var pl := get_tree().get_first_node_in_group("player")
	var sk := pl.get_node_or_null("Skills") as Skills if pl != null else null
	if sk != null:
		lore = sk.get_level(&"lore")
	match form:
		"levers":
			var a := PackedStringArray()
			for i in order:
				a.append(DIRS[int(i)])
			if lore >= 25:
				return "The old words are plain to you: %s." % ", then ".join(a)
			return "Worn letters: \"First %s... and last %s.\" The middle is worn away." % [a[0], a[3]]
		"pillars":
			var a := PackedStringArray()
			for i in order:
				a.append(SIGNS[int(i)])
			return "\"From left to right, let them show: %s.\"" % ", ".join(a)
		"mirrors":
			return "\"Bring the sun to the lens.\" Turn the mirrors until the beam reaches it."
	return ""


func use(what: String, index: int) -> String:
	if what == "plaque":
		return clue() if not solved(site_id) else "The cage has sunk. The puzzle is done."
	if solved(site_id):
		return "It no longer moves."
	match what:
		"lever":
			if int(order[int(state[0])]) == index:
				state[0] = int(state[0]) + 1
				if int(state[0]) >= order.size():
					return _solve()
				return "The lever falls with a heavy clunk. Something shifts below."
			state[0] = 0
			return "A grinding sound, and every lever snaps back."
		"pillar", "mirror":
			state[index] = (int(state[index]) + 1) % 4
			_update_beams()
			var done := true
			for i in state.size():
				if int(state[i]) != int(order[i]):
					done = false
			if done:
				return _solve()
			return "The pillar turns: it shows the %s." % SIGNS[int(state[index])] if what == "pillar" else "The mirror turns with a scrape of stone."
	return ""


func _solve() -> String:
	WorldState.set_record("site/%s/solved" % site_id, {})
	if _cage != null:
		_cage.queue_free()
	_update_beams()
	Achievements.note("puzzle")
	var sk := get_tree().get_first_node_in_group("player").get_node_or_null("Skills") as Skills
	if sk != null:
		sk.add_xp(&"lore", 15.0)
		sk.add_deed_xp(SkillDatabase.deed_xp(sk.get_player_level(), 1.0))
	return "Stone grinds on stone, and the cage sinks into the floor."


## What's shown when you look at it
func prompt_for(what: String, index: int) -> String:
	match what:
		"plaque":
			return "Read the plaque"
		"lever":
			return "Pull the %s lever" % DIRS[index]
		"pillar":
			return "Turn the pillar (it shows the %s)" % SIGNS[int(state[index])]
		"mirror":
			return "Turn the mirror"
	return ""


class Piece extends StaticBody3D:
	var site: PuzzleSite
	var what := ""
	var index := 0

	func make(size: Vector3, col: Color) -> void:
		collision_layer = 4 | 1
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		m.material_override = mat
		add_child(m)

	func get_prompt() -> String:
		return site.prompt_for(what, index) if site != null else ""

	func interact(_actor: Inventory) -> void:
		if site != null:
			Locks.toast(get_tree(), site.use(what, index))
