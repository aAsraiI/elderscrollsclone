class_name MwImport
extends RefCounted
## Turns your own copy of Morrowind into the game's people: each look below (villagers, fighters,
## knights, archers, mages, brutes) is built by MwCharacter from Morrowind's races, clothes and
## armour, and saved into your models folder (user://models) with a models.json entry, so
## ModelLibrary uses it instead of the built-in model. Nothing is copied into the project or a
## release; delete the files (or press Remove) to go back.

## Game look -> Morrowind person. Change these to dress people differently (item ids from the .esm).
const CAST := {
	"people/man_1": {"race": "imperial", "female": false, "head": 1, "hair": 1, "wear": ["common_shirt_02", "common_pants_02", "common_shoes_01"]},
	"people/man_2": {"race": "nord", "female": false, "head": 2, "hair": 2, "wear": ["common_shirt_01", "common_pants_01", "common_shoes_02"]},
	"people/man_3": {"race": "dark elf", "female": false, "head": 3, "hair": 3, "wear": ["common_shirt_03", "common_pants_03", "common_shoes_01"]},
	"people/woman_1": {"race": "breton", "female": true, "head": 1, "hair": 1, "wear": ["common_shirt_01", "common_skirt_01", "common_shoes_01"]},
	"people/woman_2": {"race": "imperial", "female": true, "head": 2, "hair": 2, "wear": ["common_shirt_02", "common_skirt_02", "common_shoes_02"]},
	"people/woman_3": {"race": "dark elf", "female": true, "head": 3, "hair": 3, "wear": ["common_shirt_01", "common_skirt_03", "common_shoes_01"]},
	"people/fighter_a": {"race": "nord", "female": false, "head": 4, "hair": 4, "wear": ["fur_cuirass", "fur_greaves", "fur_boots", "iron_gauntlet_left", "iron_gauntlet_right"]},
	"people/fighter_b": {"race": "redguard", "female": false, "head": 1, "hair": 1, "wear": ["netch_leather_boiled_cuirass", "chitin greaves", "netch_leather_boots"]},
	"people/knight": {"race": "imperial", "female": false, "head": 3, "hair": 3, "wear": ["imperial cuirass_armor", "imperial_greaves", "imperial boots", "imperial left gauntlet", "imperial right gauntlet", "imperial left pauldron", "imperial right pauldron", "imperial helmet armor"]},
	"people/archer": {"race": "wood elf", "female": false, "head": 1, "hair": 1, "wear": ["chitin cuirass", "chitin greaves", "chitin boots", "chitin pauldron - left", "chitin pauldron - right"]},
	"people/mage": {"race": "high elf", "female": false, "head": 1, "hair": 1, "wear": ["common_pants_01", "common_shoes_01", "common_robe_02"]},
	"people/brute": {"race": "orc", "female": false, "head": 1, "hair": 1, "wear": ["iron_cuirass", "iron_greaves", "fur_boots", "iron_pauldron_left", "iron_pauldron_right"]},
}

## Which Morrowind clip plays for each of ModelBody's roles
const CLIPS := {"idle": "Idle", "idle_combat": "Idle1h", "idle_combat_2h": "Idle2c", "walk": "WalkForward", "run": "RunForward",
	"attack": "WeaponOneHand_Chop", "attack_alt": "WeaponOneHand_Slash", "attack2h": "WeaponTwoHand_Chop",
	"attack_unarmed": "HandToHand_Chop", "bash": "HandToHand_Slash", "block": "Shield_Block", "hit": "Hit1",
	"death": "Death1", "cast": "SpellCast_Target", "aim": "BowAndArrow_Shoot", "sit": "Idle9", "kneel": "Idle9",
	"lie": "Knockout", "work": "Idle8", "chop": "WeaponOneHand_Chop", "talk": "Idle2", "drink": "Idle3", "stun": "Hit2"}

## The same for Morrowind's creatures (their clips are named Attack1..3)
const CREATURE_CLIPS := {"idle": "Idle", "idle_combat": "Idle", "idle_combat_2h": "Idle", "walk": "WalkForward",
	"run": "RunForward", "attack": "Attack1", "attack_alt": "Attack2", "attack2h": "Attack3", "attack_unarmed": "Attack1",
	"bash": "Attack2", "block": "Idle", "hit": "Hit1", "death": "Death1", "cast": "SpellCast_Target", "aim": "Attack1",
	"sit": "Idle", "kneel": "Idle", "lie": "Knockout", "work": "Idle2", "chop": "Attack1", "talk": "Idle2", "drink": "Idle3",
	"stun": "Hit2"}

const TAG := "morrowind"


## How many looks each person in CAST comes in (the first is CAST's own): the rest mix Morrowind's
## races, faces and hair at random, so a town is not full of twins (CreatureBody picks one by the person)
const VARIANTS := 6
const VARIANT_RACES := ["imperial", "nord", "breton", "redguard", "dark elf", "wood elf", "high elf", "orc"]
## The game's races -> Morrowind's, for your first-person hands
const FP_RACES := {"northlander": "nord", "heartlander": "imperial", "sandwalker": "redguard", "marchborn": "breton",
	"highborn": "high elf", "ashborn": "dark elf", "woodborn": "wood elf", "sandcat": "khajiit", "marshfolk": "argonian",
	"ironblood": "orc"}


# CAST, and each look again in VARIANTS - 1 other races, faces and hair: "people/man_1~v2"...
static func _cast_with_variants() -> Dictionary:
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1160
	for key in CAST:
		out[key] = CAST[key]
		for v in range(2, VARIANTS + 1):
			var spec: Dictionary = (CAST[key] as Dictionary).duplicate(true)
			if key != "people/brute":  # the brute stays an orc
				spec["race"] = VARIANT_RACES[rng.randi() % VARIANT_RACES.size()]
			spec["head"] = rng.randi_range(1, 9)
			spec["hair"] = rng.randi_range(1, 9)
			out["%s~v%d" % [key, v]] = spec
	return out


# One person built and saved, with its models.json entry
static func _build_person(data: MwData, key: String, spec: Dictionary, dir: String, manifest: Dictionary, out: Dictionary) -> void:
	var builder := MwCharacter.new(data)
	var node := builder.build(spec)
	for p in builder.problems:
		out["problems"].append("%s: %s" % [key, p])
	if node == null:
		return
	var file := String(key).replace("/", "__") + ".scn"
	_own(node, node)
	var ps := PackedScene.new()
	if ps.pack(node) != OK or ResourceSaver.save(ps, dir.path_join(file), ResourceSaver.FLAG_COMPRESS) != OK:
		out["problems"].append("%s: could not save" % key)
		node.free()
		return
	var height: float = data.esm.races.get(String(spec["race"]), {}).get("female_height" if spec["female"] else "male_height", 1.0)
	var s := MwCharacter.SCALE * height
	manifest[key] = {"path": file, "source": TAG, "fit": "height",
		"hands": {"r": "Bip01 R Hand", "l": "Bip01 L Hand"}, "grip": "auto",
		"clips": CLIPS,
		"walk_speed": maxf(builder.speeds.get("WalkForward", 100.0) * s, 0.5),
		"run_speed": maxf(builder.speeds.get("RunForward", 300.0) * s, 1.5)}
	out["made"].append(key)
	node.free()


static func models_dir() -> String:
	return ProjectSettings.globalize_path("user://models")


## Builds every look in CAST from the Data Files folder. progress(done, total, key) is called as it
## goes (await-able by the caller between looks). Returns {"made": [...], "problems": [...]}.
static func run(data_files: String, progress: Callable = Callable()) -> Dictionary:
	var out := {"made": [], "problems": []}
	var data := MwData.open(data_files)
	if data == null:
		out["problems"].append("No Morrowind.esm in " + data_files)
		return out
	var dir := models_dir()
	DirAccess.make_dir_recursive_absolute(dir.path_join("textures"))
	data.texture_dir = dir.path_join("textures")
	var manifest := _read_manifest(dir)
	var statics := MwCatalog.statics(data)
	var total := CAST.size() + MwCatalog.CREATURES.size() + statics.size()
	var i := 0
	var people := _cast_with_variants()
	total += people.size() - CAST.size()
	for key in people:
		if progress.is_valid():
			progress.call(i, total, key)
		i += 1
		_build_person(data, String(key), people[key], dir, manifest, out)
	# Your own arms in first person, for every race and both sexes ("fp/<race>_m", "fp/<race>_f")
	for race in FP_RACES:
		for female in [false, true]:
			var key := "fp/%s_%s" % [race, "f" if female else "m"]
			var builder := MwCharacter.new(data)
			var node := builder.build_first_person({"race": FP_RACES[race], "female": female, "wear": ["common_shirt_01"]})
			if node == null:
				out["problems"].append_array(Array(builder.problems).map(func(p): return "%s: %s" % [key, p]))
				continue
			if _save(node, dir, key, out):
				manifest[key] = {"path": _file(key), "source": TAG, "fit": "real"}
				out["made"].append(key)
	# Skies: the clouds for each weather and the night sky
	MwSky.convert(data, dir.path_join("textures"))
	MwSurfaces.convert(data, dir.path_join("textures"))
	# Creatures, with their own animations
	for key in MwCatalog.CREATURES:
		if progress.is_valid():
			progress.call(i, total, key)
		i += 1
		var pair: Array = MwCatalog.CREATURES[key]
		var nif_path := data.find(["meshes/" + String(pair[0])])
		if nif_path == "":
			continue  # Tribunal or Bloodmoon not installed
		var builder := MwCharacter.new(data)
		var node := builder.build_creature(nif_path, data.find(["meshes/" + String(pair[1])]))
		if node == null:
			out["problems"].append_array(Array(builder.problems).map(func(p): return "%s: %s" % [key, p]))
			continue
		if not _save(node, dir, key, out):
			continue
		var e := {"path": _file(key), "source": TAG, "fit": "creature", "clips": CREATURE_CLIPS,
			"scale": MwCatalog.CREATURE_SCALE.get(key, 1.0),
			"walk_speed": maxf(builder.speeds.get("WalkForward", 120.0) * MwCharacter.SCALE, 0.5),
			"run_speed": maxf(builder.speeds.get("RunForward", 300.0) * MwCharacter.SCALE, 1.5)}
		if key in MwCatalog.ARMED:
			e["hands"] = {"r": "Bip01 R Hand", "l": "Bip01 L Hand"}
			e["grip"] = "auto"
		manifest[key] = e
		out["made"].append(key)
	# Everything that does not move: furniture, clutter, items, weapons, armour, trees, rocks
	for key in statics:
		if progress.is_valid():
			progress.call(i, total, key)
		i += 1
		var builder := MwCharacter.new(data)
		var node := builder.build_static(String(statics[key]["file"]))
		if node == null:
			out["problems"].append_array(Array(builder.problems).map(func(p): return "%s: %s" % [key, p]))
			continue
		if not _save(node, dir, key, out):
			continue
		manifest[key] = {"path": _file(key), "source": TAG, "fit": statics[key]["fit"]}
		for extra in ["rot", "scale", "align", "anchor"]:
			if statics[key].has(extra):
				manifest[key][extra] = statics[key][extra]
		out["made"].append(key)
	_write_manifest(dir, manifest)
	ModelLibrary.reload()
	return out


static func _file(key: String) -> String:
	return key.replace("/", "__") + ".scn"


# Saves a built model into the models folder (and frees it); false if it could not be saved
static func _save(node: Node3D, dir: String, key: String, out: Dictionary) -> bool:
	_own(node, node)
	var ps := PackedScene.new()
	var ok := ps.pack(node) == OK and ResourceSaver.save(ps, dir.path_join(_file(key)), ResourceSaver.FLAG_COMPRESS) == OK
	if not ok:
		out["problems"].append("%s: could not save" % key)
	node.free()
	return ok


## Takes the imported Morrowind people back out of the models folder
static func remove() -> int:
	var dir := models_dir()
	var manifest := _read_manifest(dir)
	var n := 0
	for key in manifest.keys():
		var e = manifest[key]
		if e is Dictionary and e.get("source", "") == TAG:
			DirAccess.remove_absolute(dir.path_join(String(e["path"])))
			manifest.erase(key)
			n += 1
	var tex_dir := dir.path_join("textures")
	if DirAccess.dir_exists_absolute(tex_dir):
		for f in DirAccess.get_files_at(tex_dir):
			DirAccess.remove_absolute(tex_dir.path_join(f))
	MwSky.forget()
	MwSurfaces.forget()
	_write_manifest(dir, manifest)
	ModelLibrary.reload()
	return n


## How many imported Morrowind people are in the models folder
static func count() -> int:
	var n := 0
	for e in _read_manifest(models_dir()).values():
		if e is Dictionary and e.get("source", "") == TAG and FileAccess.file_exists(models_dir().path_join(String(e["path"]))):
			n += 1
	return n


static func _read_manifest(dir: String) -> Dictionary:
	var p := dir.path_join("models.json")
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


static func _write_manifest(dir: String, manifest: Dictionary) -> void:
	var f := FileAccess.open(dir.path_join("models.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "\t"))


static func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)
