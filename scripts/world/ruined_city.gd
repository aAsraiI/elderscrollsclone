class_name RuinedCity
extends Node3D
## Alpha 1.31.2: a ruined city on the far islands (a site of WorldSites). Its dead still hold it:
## kill them all, and the charter stone wakes. For RESETTLE_GOLD you can call settlers back: the
## ruin gets roofs, a market and a watch, and pays you TAX_PER_DAY gold for each day you were away
## (at most TAX_DAYS days), collected at the stone. Kills are saved like any others
## (WorldState "kill/<key>"); the state of the city is in "city/<id>" {"settled", "paid"}.

const NAMES := ["Old Veyr", "Hollowmere", "Ashgate"]
const GUARDS := 10
const RESETTLE_GOLD := 15000
const TAX_PER_DAY := 300
const TAX_DAYS := 10
const STONE := Color(0.38, 0.37, 0.35)
const WOOD := Color(0.36, 0.26, 0.17)

var site_id := ""
var city_name := ""
var world: WorldManager
var _foes: Array[Enemy] = []


static func make(root: Node3D, s: Dictionary, w: WorldManager) -> RuinedCity:
	var c := RuinedCity.new()
	c.site_id = String(s["id"])
	c.city_name = String(s["name"])
	c.world = w
	root.add_child(c)
	c._make(s)
	return c


static func settled(id: String) -> bool:
	return bool(WorldState.get_record("city/" + id).get("settled", false))


func kill_key(i: int) -> String:
	return "site/%s/foe_%d" % [site_id, i]


func foes_left() -> int:
	var n := 0
	for i in GUARDS:
		if not WorldState.has_record("kill/" + kill_key(i)):
			n += 1
	return n


func _make(s: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = site_id.hash()
	var live := settled(site_id)
	# houses in rings: broken walls, or whole ones with roofs once it is settled
	for i in 14:
		var a := float(i) / 14.0 * TAU + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(16.0, 34.0)
		var at := Vector3(cos(a) * r, 0, sin(a) * r)
		var at_y := world.get_height_at(global_position.x + at.x, global_position.z + at.z) - global_position.y
		at.y = at_y
		var size := Vector3(rng.randf_range(5, 8), rng.randf_range(1.5, 3.5) if not live else 3.4, rng.randf_range(5, 8))
		POIBuilder.add_box(self, size, at + Vector3(0, size.y * 0.5, 0), STONE.darkened(rng.randf_range(0.0, 0.2)), a)
		if live:
			POIBuilder.add_box(self, Vector3(size.x + 0.8, 0.5, size.z + 0.8), at + Vector3(0, size.y + 0.25, 0), WOOD, a)
	POIBuilder.add_box(self, Vector3(4, 7, 4), Vector3(0, 3.5, 12), STONE)  # a broken tower
	var charter := Charter.new()
	charter.city = self
	add_child(charter)
	charter.position = Vector3(0, 0, -3)
	charter.make()
	if live:
		_people(rng)
		return
	var level := LevelCurve.place_level(world.map, s["pos"])
	var data := load("res://data/enemies/skeleton_knight.tres") as EnemyData
	for i in GUARDS:
		if WorldState.has_record("kill/" + kill_key(i)):
			continue
		var a := float(i) / float(GUARDS) * TAU
		var r := rng.randf_range(8.0, 28.0)
		var at := global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		at.y = world.get_height_at(at.x, at.z) + 0.6
		var e := Population.spawn_enemy(data, level, world, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
		if e != null:
			e.spawn_key = kill_key(i)
			_foes.append(e)


func _people(rng: RandomNumberGenerator) -> void:
	var data := load("res://data/enemies/caravan_guard.tres") as EnemyData
	for i in 4:
		var at := global_position + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
		at.y = world.get_height_at(at.x, at.z) + 0.6
		var e := Population.spawn_enemy(data, 20, world, at, rng, {"persist_mode": Enemy.PersistMode.NEVER})
		if e != null:
			e.disposition = Enemy.Disposition.FRIENDLY
			e.display_name = "Settler of %s" % city_name
			_foes.append(e)


func _exit_tree() -> void:
	for e in _foes:
		if is_instance_valid(e) and not e.is_dead():
			e.queue_free()


func prompt() -> String:
	if settled(site_id):
		return "%s's charter stone (collect the taxes)" % city_name
	var left := foes_left()
	if left > 0:
		return "A charter stone, cold (%d of the dead still walk)" % left
	return "Resettle %s (%d gold)" % [city_name, RESETTLE_GOLD]


func use(player: Node) -> String:
	var inv := player.get_node("Inventory") as Inventory
	var today := world.clock.day if world.clock != null else 1
	if settled(site_id):
		var rec := WorldState.get_record("city/" + site_id).duplicate()
		var days := clampi(today - int(rec.get("paid", today)), 0, TAX_DAYS)
		if days <= 0:
			return "Nothing owed yet. %s is doing well." % city_name
		rec["paid"] = today
		WorldState.set_record("city/" + site_id, rec)
		Currency.add_gold(inv, days * TAX_PER_DAY)
		return "The elders of %s pay you %d gold." % [city_name, days * TAX_PER_DAY]
	if foes_left() > 0:
		return "Nothing can be done here until the dead are gone."
	if Currency.get_gold(inv) < RESETTLE_GOLD:
		return "It would take %d gold to bring people back." % RESETTLE_GOLD
	Currency.spend_gold(inv, RESETTLE_GOLD)
	WorldState.set_record("city/" + site_id, {"settled": true, "paid": today})
	Achievements.note("resettle")
	DialogueState.system_entry("Place", "I called the settlers back to %s. It pays taxes to me now." % city_name, "")
	Notices.quest(get_tree(), "City Resettled", city_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = site_id.hash() + 1
	_people(rng)
	return "Word goes out. Within the week, %s has people in it again." % city_name


class Charter extends StaticBody3D:
	var city: RuinedCity

	func make() -> void:
		collision_layer = 4 | 1
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 2.2, 0.6)
		shape.shape = box
		shape.position.y = 1.1
		add_child(shape)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, 2.2, 0.6)
		m.mesh = bm
		m.position.y = 1.1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.48, 0.42)
		m.material_override = mat
		add_child(m)

	func get_prompt() -> String:
		return city.prompt() if city != null else ""

	func interact(actor: Inventory) -> void:
		if city != null and actor != null:
			Locks.toast(get_tree(), city.use(actor.get_parent()))
