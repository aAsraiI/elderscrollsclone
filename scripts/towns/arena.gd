class_name Arena
extends StaticBody3D
## The arena in every Fighters' Guild hall: a sand pit and a gong. Strike the gong (E) and the next
## ranked bout starts: the opponents come out on the far side of the pit. Win and you take the
## purse and the next rank; seven bouts make you Grand Champion, and after that you defend the
## title for gold. Your rank is in WorldState ("arena"), shared by every arena in the realm.
## Walking out mid-bout forfeits it (the fighters go when the hall unloads).

const INTERACTABLE_LAYER := 4

## [the rank it wins, opponents [[EnemyData id, count]], levels above the player, purse]
const BOUTS := [
	["Brawler", [["bandit", 1]], -2, 60],
	["Bloodied", [["bandit_thug", 1], ["bandit", 1]], -1, 100],
	["Myrmidon", [["cutthroat", 2]], 0, 160],
	["Warrior", [["raider_marauder", 1], ["raider", 1]], 1, 240],
	["Gladiator", [["frost_bear", 1]], 2, 320],
	["Hero", [["skeleton_knight", 2]], 3, 420],
	["Grand Champion", [["deserter_captain", 1], ["reaver", 2]], 4, 800],
]
const DEFENCES := [[["reaver", 2]], [["forest_troll", 1]], [["bandit_brute", 1], ["cutthroat", 2]], [["skeleton_knight", 1], ["wight_lord", 1]]]
const DEFENCE_PURSE := 300

## The middle of the pit, in the hall's local space
var pit := Vector3.ZERO
var _foes: Array[Enemy] = []
var _purse := 0


static func make(parent: Node3D, at: Vector3, pit_center: Vector3) -> Arena:
	var a := Arena.new()
	a.name = "ArenaGong"
	a.pit = pit_center
	parent.add_child(a)
	a.position = at
	return a


## The player's arena rank (0 = unranked, BOUTS.size() = Grand Champion)
static func rank() -> int:
	return int(WorldState.get_record("arena").get("rank", 0))


static func rank_name() -> String:
	var r := rank()
	return "Unranked" if r == 0 else String(BOUTS[r - 1][0])


static func is_champion() -> bool:
	return rank() >= BOUTS.size()


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER | 1
	var wood := POIBuilder.get_material(Color(0.22, 0.14, 0.08))
	var bronze := POIBuilder.get_material(Color(0.72, 0.5, 0.22))
	bronze.metallic = 0.7
	bronze.roughness = 0.35
	for x in [-0.8, 0.8]:
		_box(Vector3(0.14, 2.4, 0.14), Vector3(x, 1.2, 0), wood)
	_box(Vector3(1.8, 0.14, 0.14), Vector3(0, 2.35, 0), wood)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 0.06
	disc.mesh = cyl
	disc.material_override = bronze
	disc.rotation.x = PI * 0.5
	disc.position = Vector3(0, 1.5, 0)
	add_child(disc)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.4, 0.3)
	shape.shape = box
	shape.position = Vector3(0, 1.2, 0)
	add_child(shape)


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	add_child(mi)


func is_fighting() -> bool:
	return not _foes.is_empty()


func get_prompt() -> String:
	if is_fighting():
		return "The bout is on!"
	if is_champion():
		return "Strike the gong: defend your title (%d gold)" % DEFENCE_PURSE
	var b: Array = BOUTS[rank()]
	return "Strike the gong: bout %d of %d, for the rank of %s (%d gold)" % [rank() + 1, BOUTS.size(), b[0], b[3]]


func interact(_inv: Inventory) -> void:
	if is_fighting():
		Locks.toast(get_tree(), "Finish the bout first. The crowd wants blood.")
		return
	start_bout()


## Brings out the next opponents. Returns them (for tests).
func start_bout() -> Array[Enemy]:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var skills := player.get_node_or_null("Skills") as Skills if player != null else null
	var level := skills.get_player_level() if skills != null else 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fighters: Array
	var offset := 3
	if is_champion():
		fighters = DEFENCES[rng.randi_range(0, DEFENCES.size() - 1)]
		_purse = DEFENCE_PURSE
	else:
		var b: Array = BOUTS[rank()]
		fighters = b[1]
		offset = int(b[2])
		_purse = int(b[3])
	var root := get_parent() as Node3D
	var i := 0
	for f in fighters:
		var data := load("res://data/enemies/%s.tres" % f[0]) as EnemyData
		if data == null:
			continue
		for n in int(f[1]):
			var side := (float(i) - 0.5) * 2.2
			var at := root.to_global(pit + Vector3(side, 0.1, 2.6))
			var e := Population.spawn_enemy(data, maxi(level + offset, 1), root, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
			e.rotation.y = 0.0  # facing the gong, toward -Z
			e.died.connect(_on_foe_died)
			_foes.append(e)
			i += 1
	if not is_champion() and rank() == BOUTS.size() - 1 and not _foes.is_empty():
		_foes[0].display_name = "%s the Unbroken" % NameGen.FIRST[rng.randi_range(0, NameGen.FIRST.size() - 1)]
	Locks.toast(get_tree(), "The gong sounds. Fight!")
	return _foes


func _on_foe_died(e: Enemy) -> void:
	_foes.erase(e)
	if not _foes.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	Currency.add_gold(player.get_node("Inventory") as Inventory, _purse)
	if is_champion():
		Locks.toast(get_tree(), "The crowd roars. You keep your title, and %d gold." % _purse)
		return
	var r := rank() + 1
	WorldState.set_record("arena", {"rank": r})
	if r >= BOUTS.size():
		Locks.toast(get_tree(), "You are the Grand Champion of the arena! %d gold." % _purse)
	else:
		Locks.toast(get_tree(), "Victory! You are now a %s of the arena. %d gold." % [BOUTS[r - 1][0], _purse])
