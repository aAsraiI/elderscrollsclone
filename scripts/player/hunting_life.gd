class_name HuntingLife
extends RefCounted
## Alpha 1.30.1: skinning, snares and tracks (the Hunting skill).
##
## SKINNING: F on a dead beast, with a blade in your pack (any dagger or sword will do), skins
## and butchers it: more pelts and meat the better your Hunting (one more every 25 levels), once
## per body. Trains Hunting.
##
## SNARES: set a Snare on the ground outside (E in the inventory). Every few hours it may catch
## small game (a hare, a fox, a grouse); come back and E takes what it caught. Snares are saved
## (WorldState "snares") and stay where you set them until you take them up.
##
## TRACKS: with Hunting 15 or more you see the tracks beasts leave in snow, sand and swamp mud
## (WorldMarks draws them), so you can follow them.

const TRACK_SKILL := 15
const SNARE_HOURS := 3.0
const SNARE_CHANCE := 0.55
## what a snare catches: [item path, count]
const SNARE_CATCH := [["res://data/materials/raw_meat.tres", 1], ["res://data/materials/animal_hide.tres", 1],
	["res://data/materials/animal_hide.tres", 2], ["res://data/ingredients/hawk_feather.tres", 2]]


# ---------------------------------------------------------------- skinning

static func skin_target(target: Object) -> Enemy:
	var e: Enemy = null
	if target is ContainerComponent:
		e = (target as ContainerComponent).get_parent() as Enemy
	elif target is Enemy:
		e = target as Enemy
	if e == null or not e.is_dead() or e.body_kind == CreatureBody.Kind.HUMANOID or e.has_meta("skinned"):
		return null
	if CraftStock.creature_drops(e.enemy_id, e.level).is_empty():
		return null  # nothing to skin (spirits, constructs...)
	return e


static func has_blade(player: Node) -> bool:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null:
		return false
	for s in inv.stacks:
		var it: ItemData = s.item
		if it != null and it.item_type == ItemData.ItemType.WEAPON and not it.is_bow and not it.is_thrown and it.animation_set in [&"dagger", &"sword", &"waraxe", &""]:
			return true
	return false


static func prompt(player: Node, target: Object) -> String:
	if skin_target(target) == null:
		return ""
	return "F: Skin and butcher" if has_blade(player) else "(a blade would let you skin it)"


## Skins it. Returns what was said ("" = nothing to skin)
static func skin(player: Node, target: Object) -> String:
	var e := skin_target(target)
	if e == null:
		return ""
	if not has_blade(player):
		return "You need a blade to skin it."
	var sk := player.get_node_or_null("Skills") as Skills
	var extra := 1 + (sk.get_level(&"hunting") / 25 if sk != null else 0)
	var inv := player.get_node("Inventory") as Inventory
	var got := 0
	for le in CraftStock.creature_drops(e.enemy_id, e.level):
		if le.item != null:
			inv.add_item(le.item, extra)
			got += extra
	e.set_meta("skinned", true)
	if sk != null:
		sk.add_xp(&"hunting", 6.0 + float(e.level) * 0.3)
	Achievements.note("skin")
	return "You skin and butcher the %s (%d things)." % [e.display_name.to_lower(), got]


# ---------------------------------------------------------------- snares

static func set_snare(player: Node3D, snare: ItemData) -> String:
	var w := player.get_tree().get_first_node_in_group("world_manager") as WorldManager
	if w == null or (w.dungeons != null and w.dungeons.is_inside()):
		return "Set snares outside, where small game runs."
	var t := w.get_nearest_town(player.global_position)
	if t != null and t.position.distance_to(player.global_position) < t.poi.footprint_radius + 20.0:
		return "Nothing runs wild this close to town."
	var at := player.global_position - player.global_transform.basis.z * 1.2
	at.y = w.get_height_at(at.x, at.z)
	var list: Array = (WorldState.get_record("snares").get("list", []) as Array).duplicate(true)
	var id := "snare/%d" % (Time.get_ticks_msec() + list.size())
	list.append({"id": id, "pos": [at.x, at.y, at.z], "set": _hours(player.get_tree()), "caught": false})
	WorldState.set_record("snares", {"list": list})
	(player.get_node("Inventory") as Inventory).remove_item(snare, 1)
	_build(player.get_tree(), id, at)
	return "You set the snare. Come back in a few hours."


static func _hours(tree: SceneTree) -> float:
	var c := tree.get_first_node_in_group("world_clock") as WorldClock
	return float(c.day) * 24.0 + c.hour if c != null else 0.0


## Every snare saved: built again as the world loads (WorldManager calls this)
static func restore(tree: SceneTree) -> void:
	for s in WorldState.get_record("snares").get("list", []):
		var p: Array = s["pos"]
		_build(tree, String(s["id"]), Vector3(p[0], p[1], p[2]))


static func _build(tree: SceneTree, id: String, at: Vector3) -> Node3D:
	var w := tree.get_first_node_in_group("world_manager") as WorldManager
	if w == null:
		return null
	for n in tree.get_nodes_in_group("snares"):
		if String(n.get_meta("snare_id", "")) == id:
			return n
	var s := SnareNode.new()
	s.snare_id = id
	s.add_to_group("snares")
	s.set_meta("snare_id", id)
	w.add_child(s)
	s.global_position = at
	return s


static func _rec(id: String) -> Dictionary:
	for s in WorldState.get_record("snares").get("list", []):
		if String(s["id"]) == id:
			return s
	return {}


## Has it caught something by now? (rolled once per SNARE_HOURS since it was set)
static func check_snare(tree: SceneTree, id: String) -> bool:
	var rec := _rec(id)
	if rec.is_empty():
		return false
	if bool(rec.get("caught", false)):
		return true
	var waited := _hours(tree) - float(rec.get("set", 0.0))
	var tries := int(waited / SNARE_HOURS)
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	for i in tries:
		if rng.randf() < SNARE_CHANCE:
			_update(id, {"caught": true})
			return true
	return false


static func _update(id: String, changes: Dictionary) -> void:
	var list: Array = (WorldState.get_record("snares").get("list", []) as Array).duplicate(true)
	for s in list:
		if String(s["id"]) == id:
			s.merge(changes, true)
	WorldState.set_record("snares", {"list": list})


## E on a snare: take the catch and set it again, or take it up if empty
static func use_snare(player: Node, id: String) -> String:
	var tree := player.get_tree()
	var inv := player.get_node("Inventory") as Inventory
	if check_snare(tree, id):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var c: Array = SNARE_CATCH[rng.randi() % SNARE_CATCH.size()]
		var it := load(String(c[0])) as ItemData if ResourceLoader.exists(String(c[0])) else load(SNARE_CATCH[0][0]) as ItemData
		inv.add_item(it, int(c[1]))
		var meat := load("res://data/materials/raw_meat.tres") as ItemData
		if meat != it:
			inv.add_item(meat, 1)
		_update(id, {"caught": false, "set": _hours(tree)})
		var sk := player.get_node_or_null("Skills") as Skills
		if sk != null:
			sk.add_xp(&"hunting", 8.0)
		Achievements.note("snare")
		return "Your snare caught something: %s. You set it again." % it.display_name
	# nothing yet: take it up
	var list: Array = (WorldState.get_record("snares").get("list", []) as Array).filter(func(s) -> bool: return String(s["id"]) != id)
	WorldState.set_record("snares", {"list": list})
	inv.add_item(load("res://data/misc/snare.tres") as ItemData, 1)
	for n in tree.get_nodes_in_group("snares"):
		if String(n.get_meta("snare_id", "")) == id:
			n.queue_free()
	return "Nothing yet. You take up the snare."


static func can_track(player: Node) -> bool:
	var sk := player.get_node_or_null("Skills") as Skills if player != null else null
	return sk != null and sk.get_level(&"hunting") >= TRACK_SKILL


class SnareNode extends StaticBody3D:
	var snare_id := ""

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 0.5, 0.8)
		shape.shape = box
		shape.position.y = 0.25
		add_child(shape)
		var loop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.22
		tm.outer_radius = 0.26
		loop.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.36, 0.22)
		loop.material_override = mat
		loop.position.y = 0.05
		add_child(loop)
		var stake := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.45, 0.05)
		stake.mesh = bm
		stake.material_override = mat
		stake.position = Vector3(0.3, 0.22, 0.0)
		add_child(stake)

	func get_prompt() -> String:
		return "Snare (something is caught!)" if HuntingLife.check_snare(get_tree(), snare_id) else "Snare (take it up)"

	func interact(actor: Inventory) -> void:
		if actor != null:
			Locks.toast(get_tree(), HuntingLife.use_snare(actor.get_parent(), snare_id))


# ---------------------------------------------------------------- 1.30.4: companions that fetch

const FETCH_RANGE := 15.0


## A tamed beast brings you something from a body it finds near (Tutorial calls this every second;
## a pet fetches at most once every FETCH_SECONDS)
const FETCH_SECONDS := 20.0
static var _fetch_t := 0.0
## Bodies of the last minutes (the dead leave the ActorRegistry): Enemy._on_died notes them
static var _recent_dead: Array = []


static func note_dead(e: Enemy) -> void:
	_recent_dead.append(weakref(e))
	if _recent_dead.size() > 24:
		_recent_dead.pop_front()


static func pet_fetch(player: Node, dt: float) -> String:
	_fetch_t -= dt
	if _fetch_t > 0.0:
		return ""
	_fetch_t = FETCH_SECONDS
	var f := player.get_node_or_null("Followers") as Followers
	if f == null:
		return ""
	for pet in f._alive():
		if not pet.has_meta("pet"):
			continue
		for n in _recent_dead:
			var body := (n as WeakRef).get_ref() as Enemy
			if body == null or not is_instance_valid(body) or body.global_position.distance_to(pet.global_position) > FETCH_RANGE or not body.is_dead() or body.has_meta("fetched") or body.inventory == null or body.inventory.stacks.is_empty():
				continue
			var stack = body.inventory.stacks[randi() % body.inventory.stacks.size()]
			var it: ItemData = stack.item
			body.inventory.remove_item(it, 1)
			(player.get_node("Inventory") as Inventory).add_item(it, 1)
			body.set_meta("fetched", true)
			Achievements.note("fetch")
			var said := "Your %s brings you %s." % [pet.display_name.to_lower(), it.display_name]
			Locks.toast(player.get_tree(), said)
			return said
	return ""


# ---------------------------------------------------------------- 1.30.4: the hawk

## A Falconer's Glove (Hunting 50): loose your hawk. It shows what lives around you (Detect Life,
## 120 m, 30 s) and often brings back small game. Once an hour.
const HAWK_SKILL := 50
const HAWK_HOURS := 1.0


static func loose_hawk(player: Node, glove: ItemData) -> String:
	var sk := player.get_node_or_null("Skills") as Skills
	if sk == null or sk.get_level(&"hunting") < HAWK_SKILL:
		return "The hawk won't come to your fist yet (Hunting %d)." % HAWK_SKILL
	var w := player.get_tree().get_first_node_in_group("world_manager") as WorldManager
	if w != null and w.dungeons != null and w.dungeons.is_inside():
		return "Not under a roof."
	var now := _hours(player.get_tree())
	if now - float(WorldState.get_record("hawk").get("at", -99.0)) < HAWK_HOURS:
		return "Your hawk is still resting."
	WorldState.set_record("hawk", {"at": now})
	var m := ActiveMagic.of(player)
	if m != null:
		m.apply_one({"id": "detect_life", "mag": 120.0, "dur": 30.0}, player, "Hawk", "power")
	sk.add_xp(&"hunting", 6.0)
	Achievements.note("hawk")
	if randf() < 0.6:
		(player.get_node("Inventory") as Inventory).add_item(load("res://data/materials/raw_meat.tres") as ItemData, 1)
		return "Your hawk circles high, shows you what moves below, and comes back with a hare."
	return "Your hawk circles high and shows you what moves below."
