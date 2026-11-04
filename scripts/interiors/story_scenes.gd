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


# ---------------------------------------------------------------- 1.26: rare events in a dungeon

const EVENT_CHANCE := 0.12


## Now and then a dungeon holds someone else: a lost adventurer to lead out (they reward you at the
## door), a rival party of delvers who got here first, or a pedlar camped in a quiet room
static func add_event(root: Node3D, dungeon_id: String, dungeon_seed: int, level: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|event|%s|%d" % [dungeon_seed, dungeon_id, Rumors._day() / 7]).hash()  # a new roll each week
	if rng.randf() > EVENT_CHANCE:
		return ""
	var rooms: Array[RoomModule] = []
	for c in root.get_children():
		if c is RoomModule:
			rooms.append(c)
	if rooms.size() < 3:
		return ""
	var room: RoomModule = rooms[rng.randi_range(1, rooms.size() - 1)]
	var spot := RoomFiller.free_spot(RoomFiller.furniture_in(room), room, Vector3.ZERO)
	if not spot.is_finite():
		return ""
	var kind: String = ["lost", "rivals", "pedlar"][rng.randi() % 3]
	match kind:
		"lost":
			var e := Population.spawn_enemy(load("res://data/npcs/townsfolk.tres"), level, room, spot, rng, {"persist_mode": Enemy.PersistMode.NEVER})
			e.display_name = "Lost Adventurer"
			e.talk_name = e.display_name
			e.disposition = Enemy.Disposition.FRIENDLY
			e.talk_lines = PackedStringArray(["Thank the gods. My torch went out two days ago. Get me out of here and I'll make it worth your while."])
			e.set_meta("lost_adventurer", true)
			e.set_meta("lod_keep", true)
		"rivals":
			var data := load("res://data/enemies/cutthroat.tres") as EnemyData
			for i in 3:
				var r := Population.spawn_enemy(data, level, room, spot + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), rng, {"persist_mode": Enemy.PersistMode.NEVER})
				r.display_name = "Rival Delver"
				r.faction = "bandits"
		"pedlar":
			var m := Population.spawn_enemy(load("res://data/npcs/townsfolk.tres"), level, room, spot, rng, {"persist_mode": Enemy.PersistMode.NEVER})
			m.display_name = "Grubb, a Pedlar"
			m.talk_name = m.display_name
			m.disposition = Enemy.Disposition.FRIENDLY
			m.set_meta("merchant", "peddler")
			m.set_meta("shop_id", "dungeon/%s" % dungeon_id)
			m.talk_lines = PackedStringArray(["Down here, nobody asks where the goods came from. Have a look."])
	return kind


## A lost adventurer you came near follows you out, and pays you at the door
static func tick_lost(tree: SceneTree) -> void:
	var p := tree.get_first_node_in_group("player") as Node3D
	if p == null:
		return
	for e in ActorRegistry.near(p.global_position, 4.0):
		if e.has_meta("lost_adventurer") and not e.has_meta("player_ally") and not e.is_dead():
			var f := p.get_node_or_null("Followers") as Followers
			if f == null:
				return
			f._make_follower(e)
			Locks.toast(tree, "The lost adventurer stays close behind you.")
			var dm := tree.get_first_node_in_group("dungeon_manager") as DungeonManager
			if dm != null:
				dm.exited.connect(func(_id: String) -> void:
					if is_instance_valid(e) and not e.is_dead():
						var inv := p.get_node("Inventory") as Inventory
						var gold := 60 + e.level * 15 if "level" in e else 120
						Currency.add_gold(inv, gold)
						Locks.toast(tree, "\"Daylight! Here, take this. %d gold, all I have.\"" % gold)
						f.dismiss(e), CONNECT_ONE_SHOT)
