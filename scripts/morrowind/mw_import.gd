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

const TAG := "morrowind"


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
	DirAccess.make_dir_recursive_absolute(dir)
	var manifest := _read_manifest(dir)
	var i := 0
	for key in CAST:
		if progress.is_valid():
			progress.call(i, CAST.size(), key)
		i += 1
		var builder := MwCharacter.new(data)
		var spec: Dictionary = CAST[key]
		var node := builder.build(spec)
		for p in builder.problems:
			out["problems"].append("%s: %s" % [key, p])
		if node == null:
			continue
		var file := String(key).replace("/", "__") + ".scn"
		_own(node, node)
		var ps := PackedScene.new()
		if ps.pack(node) != OK or ResourceSaver.save(ps, dir.path_join(file), ResourceSaver.FLAG_COMPRESS) != OK:
			out["problems"].append("%s: could not save" % key)
			node.free()
			continue
		var height: float = data.esm.races.get(String(spec["race"]), {}).get("female_height" if spec["female"] else "male_height", 1.0)
		var s := MwCharacter.SCALE * height
		manifest[key] = {"path": file, "source": TAG, "fit": "height",
			"hands": {"r": "Bip01 R Hand", "l": "Bip01 L Hand"}, "grip": "auto",
			"clips": CLIPS,
			"walk_speed": maxf(builder.speeds.get("WalkForward", 100.0) * s, 0.5),
			"run_speed": maxf(builder.speeds.get("RunForward", 300.0) * s, 1.5)}
		out["made"].append(key)
		node.free()
	_write_manifest(dir, manifest)
	ModelLibrary.reload()
	return out


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
