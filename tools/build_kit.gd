extends SceneTree
## Writes the builder kit's scenes (scenes/kit/): drop them into any scene you build by hand. Each is
## one kit node set up for a common use; change its settings in the Inspector.
##   godot --headless --path . -s res://tools/build_kit.gd
##   containers/leveled/  chests, sacks, barrels, crates, urns, wardrobes, drawers, desks... filled with loot
##                        for the place they stand in (KitContainer)
##   containers/empty/    the same, empty: storage, a stash
##   surfaces/            furniture with loot set on it: shelves, bookcases, tables, counters, altars, racks
##                        (KitLootShelf)
##   stations/            crafting stations, beds, a shrine, a planter (KitStation)
##   blocks/              walls, towers, corners, arches, palisades, stone blocks (KitBlock)
##   doors/exit_door      the way out (KitExitDoor)
##   model                any model by its key (KitModel)
## After the kit import (import_morrowind.gd -- kit) it also writes a scene for each Morrowind piece:
## scenes/kit/morrowind/<type>/<set>/<piece>.tscn (existing ones are left alone)

const DIR := "res://scenes/kit/"
## Piece types you walk inside or around closely: exact collision (KitModel.exact)
const EXACT := ["caves", "dungeons", "tombs", "castles", "towns", "rooms"]
const MW := "kit/containers/all/"

## Containers: [file, name shown, Morrowind model (MW + ...), loot tags (empty = what the place holds)].
## Without the Morrowind import each takes the built-in model for its name (POIBuilder.container_key).
const CONTAINERS := [
	["chest", "Chest", "contain_com_chest_01", []],
	["chest_small", "Small Chest", "contain_chest_small_01", []],
	["chest_large", "Large Chest", "contain_chest_large_01", []],
	["chest_ornate", "Ornate Chest", "contain_de_chest_01", ["rich_home", "jewelry"]],
	["strongbox", "Strongbox", "contain_de_chest_02", ["jewelry", "vault"]],
	["footlocker", "Footlocker", "contain_chest10", ["camp", "weapon", "armor"]],
	["dwemer_chest", "Dwemer Chest", "contain_dwrv_chest00", ["vault", "ruin"]],
	["daedric_chest", "Daedric Chest", "contain_daedric_chest_01", ["ashen", "vault"]],
	["sack", "Sack", "contain_com_sack_02", ["kitchen", "camp"]],
	["sack_pile", "Sacks", "contain_com_sack_01", ["kitchen", "home"]],
	["barrel", "Barrel", "contain_barrel_01", ["kitchen", "tavern"]],
	["barrel_old", "Old Barrel", "contain_barrel10", ["tavern", "camp"]],
	["dwemer_barrel", "Dwemer Barrel", "contain_dwrv_barrel00", ["ruin", "tools"]],
	["crate", "Crate", "contain_crate_01", ["tools", "camp"]],
	["crate_large", "Large Crate", "contain_crate_02", ["tools", "shop"]],
	["crate_trade", "Trade Crate", "contain_de_crate_logo", ["shop", "kitchen"]],
	["urn", "Burial Urn", "contain_urn_01", ["crypt"]],
	["urn_ornate", "Ornate Urn", "contain_urn_02", ["crypt", "jewelry"]],
	["pot", "Clay Pot", "contain_pot_redware_01", ["kitchen", "alchemist"]],
	["pot_glazed", "Glazed Pot", "contain_pot_blue_01", ["rich_home", "alchemist"]],
	["basket", "Basket", "contain_com_basket_01", ["kitchen", "home"]],
	["cupboard", "Cupboard", "contain_com_cupboard_01", ["kitchen", "home"]],
	["hutch", "Hutch Cupboard", "contain_com_hutch_01", ["kitchen", "rich_home"]],
	["wardrobe", "Wardrobe", "contain_com_closet_01", ["clothes", "home"]],
	["wardrobe_dunmer", "Wardrobe", "contain_de_closet_01", ["clothes", "rich_home"]],
	["drawers", "Chest of Drawers", "contain_com_drawers_01", ["clothes", "home"]],
	["drawers_dunmer", "Chest of Drawers", "contain_de_drawers_01", ["clothes", "jewelry"]],
	["desk", "Desk Drawer", "contain_de_desk_01", ["library", "jewelry"]],
	["dwemer_cabinet", "Dwemer Cabinet", "contain_dwrv_closet00", ["ruin", "tools"]],
	["dwemer_desk", "Dwemer Desk Drawer", "contain_dwrv_desk00", ["ruin", "library"]],
	["cauldron", "Cauldron", "contain_couldron10", ["alchemist", "kitchen"]],
	["remains", "Remains", "contain_corpse00", ["camp", "crypt"]],
	["remains_bones", "Old Bones", "contain_corpse10", ["crypt", "barrow"]],
]

## Furniture with loot on it: [file, model key, built-in model when that one is missing, loot tags (empty =
## what the place holds that suits this kind of surface)]
const SURFACES := [
	["shelf", "prop/shelf", "", []],
	["bookcase", "prop/bookcase", "", ["library"]],
	["bookshelf", "prop/bookshelf", "prop/bookcase", ["library"]],
	["bookcase_dunmer", "kit/furniture/dunmer/furn_de_bookshelf_02", "prop/bookcase", ["library"]],
	["wall_shelf", "kit/furniture/common/furn_com_shelf_01", "prop/shelf", []],
	["wall_shelf_long", "kit/furniture/common/furn_com_shelf_02", "prop/shelf", []],
	["wall_shelf_dunmer", "kit/furniture/dunmer/furn_de_shelf_01", "prop/shelf", []],
	["wall_shelf_nord", "kit/furniture/nord/furn_colony_shelf01", "prop/shelf", []],
	["shelf_redoran", "kit/furniture/dunmer/furn_redoran_shelf1_01", "prop/shelf", []],
	["table", "prop/table", "", []],
	["table_dining", "prop/table_meal", "prop/table", []],
	["table_small", "kit/furniture/common/furn_com_table_02", "prop/table", []],
	["table_dunmer", "kit/furniture/dunmer/furn_de_table_01", "prop/table", []],
	["table_dunmer_long", "kit/furniture/dunmer/furn_de_table_05", "prop/table", []],
	["table_stone", "kit/furniture/nord/furn_colony_stonetable01", "prop/table", []],
	["table_outdoor", "kit/furniture/dunmer/furn_de_ex_table_02", "prop/table", ["camp", "kitchen"]],
	["map_table", "prop/map_table", "prop/table", ["library", "weapon"]],
	["counter", "prop/counter", "", []],
	["bar_dunmer", "kit/furniture/dunmer/furn_de_bar_01", "prop/counter", ["tavern", "kitchen"]],
	["altar", "prop/altar", "", ["temple", "jewelry"]],
	["plinth", "prop/plinth", "", ["vault", "jewelry"]],
	["weapon_rack", "prop/rack", "", ["weapon"]],
	["keg_stand", "kit/furniture/common/furn_com_kegstand", "prop/keg_rack", ["tavern"]],
	["wine_rack", "kit/furniture/common/furn_com_winerack", "prop/drying_rack", ["tavern"]],
	["burial_niche", "prop/niche", "", ["crypt"]],
	["sarcophagus", "prop/sarcophagus", "", ["crypt", "jewelry"]],
	["cart", "prop/cart", "", ["mine", "tools"]],
]

const STATIONS := ["forge", "smelter", "tanning_rack", "workbench", "grindstone", "cooking_pot", "alchemy_lab", "enchanter", "spell_altar",
	"bed", "bed_rich", "bunk", "bedroll", "shrine", "planter"]

## The kit's scenes before Alpha 1.20 (all in scenes/kit/), removed when this runs
const OLD := ["block_arch", "block_corner", "block_palisade", "block_stone_block", "block_tower", "block_wall", "container_barrel",
	"container_chest", "container_crate", "container_cupboard", "container_rich_chest", "container_sack", "container_urn",
	"container_wardrobe", "exit_door", "loot_altar", "loot_bookcase", "loot_counter", "loot_shelf", "loot_table", "loot_weapon_rack"]


func _init() -> void:
	for d in ["containers/leveled", "containers/empty", "surfaces", "stations", "blocks", "doors"]:
		DirAccess.make_dir_recursive_absolute(DIR + d)
	for f: String in OLD:
		if FileAccess.file_exists(DIR + f + ".tscn"):
			DirAccess.remove_absolute(DIR + f + ".tscn")
	var n := 0
	# containers you can open: filled for the place, or empty
	for c: Array in CONTAINERS:
		for leveled in [true, false]:
			var k := KitContainer.new()
			k.display_name = c[1]
			k.model_key = MW + String(c[2])
			k.leveled = leveled
			if leveled:
				k.loot_tags = PackedStringArray(c[3])
			n += _save(k, ("containers/leveled/" if leveled else "containers/empty/") + String(c[0]))
	# furniture with loot on it
	for s: Array in SURFACES:
		var k := KitLootShelf.new()
		k.furniture = s[1]
		k.fallback = s[2]
		k.loot_tags = PackedStringArray(s[3])
		n += _save(k, "surfaces/" + String(s[0]))
	# things you use
	for kind: String in STATIONS:
		var k := KitStation.new()
		k.kind = kind
		n += _save(k, "stations/" + kind)
	# the way out
	n += _save(KitExitDoor.new(), "doors/exit_door")
	# building blocks
	for b in [["wall", "wall/city", Vector3(6, 6, 2.5)], ["tower", "wall/tower", Vector3(5, 10, 5)],
			["corner", "wall/corner", Vector3(3, 6, 3)], ["arch", "wall/arch", Vector3(6, 6, 2.5)],
			["palisade", "wall/palisade", Vector3(6, 3.4, 0.6)], ["stone_block", "prop/plinth", Vector3(1, 1, 1)]]:
		var k := KitBlock.new()
		k.look = b[1]
		k.size = b[2]
		n += _save(k, "blocks/" + b[0])
	# any model
	n += _save(KitModel.new(), "model")
	# every Morrowind building piece you imported (MwImport.run_kit), by type and set
	var pieces := 0
	for key: String in ModelLibrary.keys():
		if not key.begins_with("kit/"):
			continue
		var file := "morrowind/%s/%s/%s" % [key.get_slice("/", 1), key.get_slice("/", 2), key.get_slice("/", 3)]
		if FileAccess.file_exists(DIR + file + ".tscn"):
			continue
		var k := KitModel.new()
		k.key = key
		k.exact = key.get_slice("/", 1) in EXACT
		DirAccess.make_dir_recursive_absolute(DIR + file.get_base_dir())
		pieces += _save(k, file)
	print("kit scenes: ", n, ", new Morrowind pieces: ", pieces)
	quit()


func _save(node: Node, file: String) -> int:
	node.name = file.get_file().to_pascal_case()
	var ps := PackedScene.new()
	var ok := ps.pack(node) == OK and ResourceSaver.save(ps, DIR + file + ".tscn") == OK
	node.free()
	return 1 if ok else 0
