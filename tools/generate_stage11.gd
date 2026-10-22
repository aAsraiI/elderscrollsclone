extends SceneTree
## Makes the item and creature files of stage 11. Run with:
##   godot --headless --path . -s res://tools/generate_stage11.gd
## Writes:
##   scripts/Resources/Ranged/      a bow and arrows for every tier
##   scripts/Resources/Misc/        empty bottle, bottle of blood, horse deed, sellsword contract
##   scripts/Resources/Enemies/     vampire, werewolf
##   scripts/Resources/Spawns/      vampires in crypts and barrows, werewolves in caves (added once)
##   scripts/Resources/Encounters/  night_werewolf, night_vampire (added to the temperate biomes once)
## Like the other generators, an existing file is loaded and only these fields are set.

const RES := "res://scripts/Resources/"
const DAMAGE_MULT := [1.0, 1.5, 2.1, 2.9, 3.9, 5.2, 7.4]
const VALUE_MULT := [1.0, 2.5, 6.0, 14.0, 32.0, 75.0, 170.0]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(RES + "Ranged")
	_bows()
	_misc()
	var vamp := _enemy("vampire", "Vampire", Color(0.75, 0.72, 0.78), 1.15, 1.2, EnemyData.Kit.DAGGER, 3.6)
	var wolf := _enemy("werewolf", "Werewolf", Color(0.25, 0.2, 0.17), 1.6, 1.4, EnemyData.Kit.UNARMED, 4.6)
	wolf.body_scale = 1.3
	wolf.poise_mult = 1.8
	ResourceSaver.save(wolf, wolf.resource_path)
	_add_to_table("dungeon_crypt", vamp, 8)
	_add_to_table("dungeon_barrow", vamp, 8)
	_add_to_table("dungeon_cave", wolf, 12)
	var t1 := _table("enc_night_werewolf", wolf)
	var t2 := _table("enc_night_vampire", vamp)
	var e1 := _encounter("night_werewolf", "Werewolf", t1, "A howl rises from the dark...", 10)
	var e2 := _encounter("night_vampire", "Vampire", t2, "Something pale moves between the trees...", 8)
	for b in ["forest", "highlands", "lakeland", "swamp", "coast", "deadlands", "tundra"]:
		_add_encounter(b, e1)
		_add_encounter(b, e2)
	print("stage 11 content written")
	quit()


func _item(path: String) -> ItemData:
	if ResourceLoader.exists(path):
		var it := load(path) as ItemData
		if it != null:
			return it
	return ItemData.new()


func _bows() -> void:
	for t in 7:
		var key: String = "hunting" if t == 0 else LevelCurve.TIER_KEYS[t]
		var path := RES + "Ranged/%s_bow.tres" % key
		var b := _item(path)
		b.id = StringName(key + "_bow")
		b.display_name = "Hunting Bow" if t == 0 else "%s Bow" % LevelCurve.TIER_NAMES[t]
		b.description = "Hold left click to draw, let go to shoot. Right click zooms. Uses the best arrows you carry."
		b.item_type = ItemData.ItemType.WEAPON
		b.equip_slot = ItemData.EquipSlot.MAIN_HAND
		b.governing_skill = "archery"
		b.two_handed = true
		b.is_bow = true
		b.weapon_damage = snappedf(7.0 * DAMAGE_MULT[t], 0.5)
		b.draw_time = 0.95 - 0.04 * t
		b.arrow_speed = 46.0 + 3.0 * t
		b.reach = 1.6
		b.attack_cooldown = 0.8
		b.poise_damage = 6.0
		b.weight = 6.0 + t * 0.5
		b.value = roundi(30.0 * VALUE_MULT[t])
		b.tier = t + 1
		b.min_level = LevelCurve.TIER_MIN_LEVEL[t]
		b.animation_set = &"bow"
		b.loot_tags = PackedStringArray(["smithy", "hunter", "weapons"])
		ResourceSaver.save(b, path)
		var apath := RES + "Ranged/%s_arrow.tres" % LevelCurve.TIER_KEYS[t]
		var a := _item(apath)
		a.id = StringName(LevelCurve.TIER_KEYS[t] + "_arrow")
		a.display_name = "%s Arrow" % LevelCurve.TIER_NAMES[t]
		a.description = "Shot from a bow. Better arrows hit harder."
		a.item_type = ItemData.ItemType.MISC
		a.is_arrow = true
		a.arrow_damage = snappedf(6.0 * DAMAGE_MULT[t], 0.5)
		a.stackable = true
		a.max_stack = 999
		a.weight = 0.0
		a.value = maxi(1, roundi(1.0 * VALUE_MULT[t]))
		a.tier = t + 1
		a.min_level = LevelCurve.TIER_MIN_LEVEL[t]
		a.loot_tags = PackedStringArray(["smithy", "hunter", "weapons"])
		ResourceSaver.save(a, apath)


func _misc_item(id: String, name: String, desc: String, value: int, type: int = ItemData.ItemType.MISC) -> ItemData:
	var path := RES + "Misc/%s.tres" % id
	var it := _item(path)
	it.id = StringName(id)
	it.display_name = name
	it.description = desc
	it.item_type = type
	it.value = value
	it.weight = 0.5
	it.stackable = true
	it.max_stack = 99
	return it


func _misc() -> void:
	var e := _misc_item("empty_bottle", "Empty Bottle", "A stoppered glass bottle.", 3)
	e.loot_tags = PackedStringArray(["kitchen", "tavern", "alchemy"])
	ResourceSaver.save(e, e.resource_path if e.resource_path != "" else RES + "Misc/empty_bottle.tres")
	var b := _misc_item("bottle_of_blood", "Bottle of Blood", "Fresh blood. Only a vampire would drink it.", 30, ItemData.ItemType.CONSUMABLE)
	b.use_verb = "Drink"
	b.effect_group = "potion"
	b.effect_duration = 1.0
	var fx: Array[Dictionary] = [{"id": &"restore_health", "mag": 10.0, "dur": 0.0}]
	b.magic_effects = fx
	ResourceSaver.save(b, b.resource_path if b.resource_path != "" else RES + "Misc/bottle_of_blood.tres")
	var h := _misc_item("horse_deed", "Horse Deed", "Proof that a horse is yours. Use it to call your horse to you.", 1500)
	h.stackable = false
	h.max_stack = 1
	ResourceSaver.save(h, h.resource_path if h.resource_path != "" else RES + "Misc/horse_deed.tres")
	var c := _misc_item("sellsword_contract", "Sellsword Contract", "Use it to hire a sellsword who follows and fights for you.", 500)
	ResourceSaver.save(c, c.resource_path if c.resource_path != "" else RES + "Misc/sellsword_contract.tres")


func _enemy(id: String, name: String, color: Color, health: float, damage: float, kit: int, speed: float) -> EnemyData:
	var path := RES + "Enemies/%s.tres" % id
	var d: EnemyData = load(path) as EnemyData if ResourceLoader.exists(path) else EnemyData.new()
	d.id = StringName(id)
	d.display_name = name
	d.color = color
	d.health_mult = health
	d.damage_mult = damage
	d.kit = kit
	d.move_speed = speed
	d.detection_range = 20.0
	d.telegraph_time = 0.25
	d.heavy_chance = 0.3
	d.chain_chance = 0.5
	d.loot_quality = 1.5
	ResourceSaver.save(d, path)
	d.take_over_path(path)
	return d


func _add_to_table(table_id: String, who: EnemyData, min_level: int) -> void:
	var path := RES + "Spawns/%s.tres" % table_id
	if not ResourceLoader.exists(path):
		return
	var t := load(path) as SpawnTable
	for e in t.entries:
		if e != null and e.members.has(who):
			return
	var entry := SpawnEntry.new()
	entry.members = [who]
	entry.weight = 0.6
	entry.min_level = min_level
	t.entries.append(entry)
	ResourceSaver.save(t, path)


func _table(id: String, who: EnemyData) -> SpawnTable:
	var path := RES + "Spawns/%s.tres" % id
	var t: SpawnTable = load(path) as SpawnTable if ResourceLoader.exists(path) else SpawnTable.new()
	t.entries.clear()
	var entry := SpawnEntry.new()
	entry.members = [who]
	t.entries.append(entry)
	ResourceSaver.save(t, path)
	t.take_over_path(path)
	return t


func _encounter(id: String, name: String, table: SpawnTable, msg: String, min_level: int) -> EncounterData:
	var path := RES + "Encounters/%s.tres" % id
	var e: EncounterData = load(path) as EncounterData if ResourceLoader.exists(path) else EncounterData.new()
	e.id = StringName(id)
	e.display_name = name
	e.table = table
	e.weight = 0.7
	e.aggro = true
	e.night_only = true
	e.min_player_level = min_level
	e.message = msg
	e.cooldown = 600.0
	ResourceSaver.save(e, path)
	e.take_over_path(path)
	return e


func _add_encounter(biome_id: String, enc: EncounterData) -> void:
	var path := RES + "World/%s.tres" % biome_id
	if not ResourceLoader.exists(path):
		return
	var b := load(path) as BiomeData
	for x in b.encounters:
		if x != null and x.id == enc.id:
			return
	b.encounters.append(enc)
	ResourceSaver.save(b, path)
