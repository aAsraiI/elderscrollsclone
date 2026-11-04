class_name StoryScenes
extends RefCounted
## Alpha 1.24: a small scene in some dungeons that tells what happened there, found in a room past the
## first few: bones, a few things left behind and a note. The same in every visit (seeded by the
## dungeon). StitchedInterior adds one to about two dungeons in three.

const CHANCE := 0.65
const BONES := "res://scenes/interiors/props/bones.tscn"
const SKULLS := "res://scenes/interiors/props/skull_pile.tscn"
const CANDLES := "res://scenes/interiors/props/candles.tscn"

## [kind, note title, note text]
const SCENES := [
	["last_stand", "A Last Entry", "Day four. The torches are nearly gone. Hollin and Brask are dead and Wenna will not wake. They come up from below every time the light gutters. If anyone finds this, we held the door. We held it."],
	["lovers", "Two Names Scratched in the Stone", "IDRA + COLM. Under it, in another hand: 'We came down to be alone. We will be.'"],
	["ritual", "A Page of Instructions", "Five candles at the points. Speak the words without stopping, whatever answers. DO NOT break the circle until the light goes out on its own. (The circle is broken. The light went out a long time ago.)"],
	["expedition", "A Surveyor's Notebook", "Third level reached. Air foul but breathable. The deeper passages are older than the rest: different stone, different hands. Goran wants to turn back. I said one more room."],
	["prisoner", "Scratches on the Wall", "Marks in rows of five, a great many of them. At the end, smaller and shakier than the rest: 'They forgot me.'"],
]


static func add(root: Node3D, dungeon_id: String, dungeon_seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|story|%s" % [dungeon_seed, dungeon_id]).hash()
	if rng.randf() > CHANCE:
		return false
	var rooms: Array[RoomModule] = []
	for c in root.get_children():
		if c is RoomModule:
			rooms.append(c)
	if rooms.size() < 3:
		return false
	var room: RoomModule = rooms[rng.randi_range(1, rooms.size() - 1)]
	var scene: Array = SCENES[rng.randi() % SCENES.size()]
	var b := room.bounds()
	var spot := RoomFiller.free_spot(RoomFiller.furniture_in(room), room, Vector3(rng.randf_range(-0.25, 0.25) * b.size.x, 0.0, rng.randf_range(-0.25, 0.25) * b.size.z))
	if not spot.is_finite():
		return false
	var holder := Node3D.new()
	holder.name = "StoryScene_" + String(scene[0])
	room.add_child(holder)
	holder.position = spot
	holder.rotation.y = rng.randf() * TAU
	match String(scene[0]):
		"last_stand":
			for i in 3:
				_prop(holder, BONES, Vector3(cos(i * 2.1) * 1.3, 0, sin(i * 2.1) * 1.3), rng)
		"lovers":
			_prop(holder, BONES, Vector3(-0.35, 0, 0), rng)
			_prop(holder, BONES, Vector3(0.35, 0, 0), rng)
		"ritual":
			_prop(holder, BONES, Vector3.ZERO, rng)
			for i in 5:
				_prop(holder, CANDLES, Vector3(cos(i * TAU / 5.0) * 1.8, 0, sin(i * TAU / 5.0) * 1.8), rng)
		"expedition":
			_prop(holder, BONES, Vector3.ZERO, rng)
			_prop(holder, BONES, Vector3(1.4, 0, 0.6), rng)
		"prisoner":
			_prop(holder, SKULLS, Vector3.ZERO, rng)
	var note := Readable.make(holder, Vector3(0.6, 0.0, -0.6), rng.randf() * TAU, String(scene[1]), String(scene[2]), "note")
	note.name = "StoryNote"
	return true


static func _prop(parent: Node3D, path: String, at: Vector3, rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(path):
		return
	var n := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(n)
	n.position = at
	n.rotation.y = rng.randf() * TAU
