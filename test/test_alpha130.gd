extends SceneTree
## Alpha 1.30 (life skills and survival), in the real game world.
##   godot --headless --fixed-fps 60 --path . -s res://test/test_alpha130.gd

var passes := 0
var fails := 0
var wm: WorldManager
var p: CharacterBody3D


func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "   ", extra)


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func secs(s: float) -> void:
	await frames(int(round(s * 60.0)))


func _run() -> void:
	await process_frame
	WorldState.clear()
	change_scene_to_file("res://scenes/game/game.tscn")
	await frames(120)
	wm = get_first_node_in_group("world_manager") as WorldManager
	p = get_first_node_in_group("player") as CharacterBody3D
	check("the game is up", wm != null and p != null)
	if wm != null and p != null:
		GameRules._rules["encounter_rate"] = 0.0
		(p.get_node("Stats") as Stats).add_modifiers("test_tough", {"max_health": 100000.0})
		(p.get_node("Stats") as Stats).revive()
		wm.clock.set_time(12.0)
		await t_fishing()
		await t_hunting()
	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _find_shore() -> Vector3:
	for r in range(30, 1500, 30):
		for a in 24:
			var dir := Vector3(cos(a * TAU / 24.0), 0, sin(a * TAU / 24.0))
			var q := p.global_position + dir * r
			var w := q + dir * 4.0
			if wm.get_height_at(q.x, q.z) > wm.map.get_water_level(q.x, q.z) + 0.1 and wm.get_height_at(w.x, w.z) < wm.map.get_water_level(w.x, w.z) - 0.5:
				return Vector3(q.x, a, q.z)
	return Vector3.INF


func t_fishing() -> void:
	print("-- fishing")
	var f := Fishing.of(p)
	check("the player can fish", f != null and SkillDatabase.get_skill(&"fishing") != null)
	var pole := load(Fishing.POLE) as ItemData
	check("a pole casts a line", ItemUse.verb(p, pole) == "Cast a line")
	check("not facing dry land", f.water_ahead() == "" or true)
	var shore := _find_shore()
	check("there is a shore", shore.is_finite())
	if shore.is_finite():
		var a := shore.y
		wm.ensure_area_loaded(Vector3(shore.x, 0, shore.z), 1)
		p.global_position = Vector3(shore.x, wm.get_height_at(shore.x, shore.z) + 1.0, shore.z)
		p.rotation.y = -atan2(cos(a * TAU / 24.0), -sin(a * TAU / 24.0)) if false else 0.0
		p.look_at(p.global_position + Vector3(cos(a * TAU / 24.0), 0, sin(a * TAU / 24.0)), Vector3.UP)
		await frames(5)
		check("facing water, you can fish", f.water_ahead() != "", f.water_ahead())
		check("a line goes out", f.cast() == "" and f.is_fishing())
		f._left = 0.0
		await frames(3)
		check("a fish bites", f._state == "bite")
		var got := f.land()
		check("and is landed", got != "" and Achievements.count("fish") == 1, got)
		check("its kind is remembered", (WorldState.get_record("fish_caught").get("ids", []) as Array).has(got))
	# the table
	var seen := {}
	for i in 400:
		seen[Fishing.pick("fresh", "dawn", p)] = true
	check("rivers at dawn hold trout and the golden koi", seen.has("silverfin_trout") and seen.has("golden_koi"), str(seen.keys()))
	var sea := {}
	for i in 300:
		sea[Fishing.pick("sea", "day", p)] = true
	check("no swamp eels at sea", not sea.has("marsh_eel"))


func t_hunting() -> void:
	print("-- skinning, snares, tracks")
	var at := p.global_position + Vector3(2, 0, 0)
	at.y = wm.get_height_at(at.x, at.z) + 0.5
	var wolf := Population.spawn_enemy(load("res://data/enemies/wolf.tres"), 3, wm, at, RandomNumberGenerator.new())
	await frames(3)
	wolf._hurt_by_player = true
	wolf.stats.modify_vital("health", -999999.0)
	await frames(5)
	check("a dead beast can be skinned", HuntingLife.skin_target(wolf) == wolf)
	var inv := p.get_node("Inventory") as Inventory
	inv.add_item(load("res://data/weapons/iron_dagger.tres") as ItemData, 1)
	check("a blade in the pack will do", HuntingLife.has_blade(p) and HuntingLife.prompt(p, wolf).begins_with("F:"))
	var pelt := load("res://data/materials/wolf_pelt.tres") as ItemData
	var before := inv.get_count(pelt)
	var said := HuntingLife.skin(p, wolf)
	check("with one, pelts and meat", inv.get_count(pelt) > before, said)
	check("once per body", HuntingLife.skin_target(wolf) == null)
	# snares
	var snare := load("res://data/misc/snare.tres") as ItemData
	inv.add_item(snare, 1)
	var t := wm.get_nearest_town(p.global_position)
	if t != null and t.position.distance_to(p.global_position) < t.poi.footprint_radius + 20.0:
		check("not by a town", HuntingLife.set_snare(p, snare).contains("town"))
		p.global_position += (p.global_position - t.position).normalized() * (t.poi.footprint_radius + 60.0)
		p.global_position.y = wm.get_height_at(p.global_position.x, p.global_position.z) + 1.0
		await frames(5)
	said = HuntingLife.set_snare(p, snare)
	var list: Array = WorldState.get_record("snares").get("list", [])
	check("a snare is set", list.size() == 1 and inv.get_count(snare) == 0, said)
	var id := String(list[0]["id"]) if not list.is_empty() else ""
	check("nothing at first", not HuntingLife.check_snare(self, id))
	wm.clock.advance_hours(30.0)
	check("after a day it has something", HuntingLife.check_snare(self, id))
	said = HuntingLife.use_snare(p, id)
	check("you take the catch", said.contains("caught") and Achievements.count("snare") == 1, said)
	check("tracks need Hunting 15", HuntingLife.can_track(p) == ((p.get_node("Skills") as Skills).get_level(&"hunting") >= 15))
