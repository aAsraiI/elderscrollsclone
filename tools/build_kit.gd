extends SceneTree
## Writes the builder kit's scenes (scenes/kit/): drop them into any scene you build by hand. Each is
## one kit node set up for a common use; change its settings in the Inspector.
##   godot --headless --path . -s res://tools/build_kit.gd
## After the kit import (import_morrowind.gd -- kit) it also writes a scene for each Morrowind piece:
## scenes/kit/morrowind/<type>/<set>/<piece>.tscn

const DIR := "res://scenes/kit/"
## Piece types you walk inside or around closely: exact collision (KitModel.exact)
const EXACT := ["caves", "dungeons", "tombs", "castles", "towns", "rooms"]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var n := 0
	# containers you can loot
	for c in [["chest", "Chest", ["camp", "weapon"]], ["rich_chest", "Strongbox", ["jewelry", "vault"]],
			["sack", "Sack", ["camp", "kitchen"]], ["barrel", "Barrel", ["kitchen", "tavern"]],
			["crate", "Crate", ["camp", "tools"]], ["urn", "Burial Urn", ["crypt"]],
			["cupboard", "Cupboard", ["kitchen", "home"]], ["wardrobe", "Wardrobe", ["clothes", "home"]]]:
		var k := KitContainer.new()
		k.display_name = c[1]
		k.loot_tags = PackedStringArray(c[2])
		n += _save(k, "container_" + c[0])
	# furniture that fills its own surfaces with loot
	for s in [["shelf", "prop/shelf", ["library", "home"]], ["bookcase", "prop/bookcase", ["library"]],
			["table", "prop/table", ["kitchen", "tavern"]], ["altar", "prop/altar", ["temple", "jewelry"]],
			["counter", "prop/counter", ["shop"]], ["weapon_rack", "prop/rack", ["weapon"]]]:
		var k := KitLootShelf.new()
		k.furniture = s[1]
		k.loot_tags = PackedStringArray(s[2])
		n += _save(k, "loot_" + s[0])
	# the way out
	n += _save(KitExitDoor.new(), "exit_door")
	# building blocks
	for b in [["wall", "wall/city", Vector3(6, 6, 2.5)], ["tower", "wall/tower", Vector3(5, 10, 5)],
			["corner", "wall/corner", Vector3(3, 6, 3)], ["arch", "wall/arch", Vector3(6, 6, 2.5)],
			["palisade", "wall/palisade", Vector3(6, 3.4, 0.6)], ["stone_block", "prop/plinth", Vector3(1, 1, 1)]]:
		var k := KitBlock.new()
		k.look = b[1]
		k.size = b[2]
		n += _save(k, "block_" + b[0])
	# any model
	n += _save(KitModel.new(), "model")
	# every Morrowind building piece you imported (MwImport.run_kit), by type and set
	var pieces := 0
	for key: String in ModelLibrary.keys():
		if not key.begins_with("kit/"):
			continue
		var k := KitModel.new()
		k.key = key
		k.exact = key.get_slice("/", 1) in EXACT
		var dir := DIR + "morrowind/" + key.get_slice("/", 1) + "/" + key.get_slice("/", 2) + "/"
		DirAccess.make_dir_recursive_absolute(dir)
		pieces += _save(k, "morrowind/%s/%s/%s" % [key.get_slice("/", 1), key.get_slice("/", 2), key.get_slice("/", 3)])
	print("kit scenes: ", n, ", Morrowind pieces: ", pieces)
	quit()


func _save(node: Node, file: String) -> int:
	node.name = file.get_file().to_pascal_case()
	var ps := PackedScene.new()
	var ok := ps.pack(node) == OK and ResourceSaver.save(ps, DIR + file + ".tscn") == OK
	node.free()
	return 1 if ok else 0
