class_name MwCatalog
extends RefCounted
## Which of Morrowind's meshes stands in for each look in the game (ModelLibrary keys), as file
## patterns tried in order: the first one your copy has is used. Paths are inside the archives,
## "meshes/" left out. MwImport converts every one it finds into your models folder.
##
## Props keep Morrowind's real size ("fit": "real"); items fill the space their placeholder took
## ("long"), so held weapons keep their reach.

## Furniture, containers, lights and decoration: prop scenes (prop/<scene>), room pieces (prop/<kind>)
const PROPS := {
	"prop/barrel": ["o/contain_barrel_01.nif"],
	"prop/barrels": ["o/contain_barrel10.nif", "o/contain_barrel_01.nif"],
	"prop/bed": ["f/furn_com_bed_01.nif"],
	"prop/bed_rich": ["f/furn_com_bed_05.nif", "f/furn_com_bed_03.nif"],
	"prop/bunk": ["f/furn_com_bunk_01.nif"],
	"prop/bedroll": ["f/active_de_bedroll.nif", "f/furn_bedmat_01.nif"],
	"prop/bedroll_out": ["f/active_de_bedroll.nif", "f/furn_bedmat_01.nif"],
	"prop/bench": ["f/furn_com_bench_01.nif", "f/furn_de_bench_01.nif"],
	"prop/stone_bench": ["f/furn_de_ex_bench_01.nif", "f/furn_de_bench_02.nif"],
	"prop/bones": ["f/furn_bone_01.nif"],
	"prop/skull_pile": ["f/furn_bone_skull_01.nif", "m/misc_skull00.nif"],
	"prop/bookshelf": ["f/furn_com_bookshelf_01.nif"],
	"prop/bookcase": ["f/furn_com_bookshelf_02.nif", "f/furn_com_bookshelf_01.nif"],
	"prop/shelf": ["f/furn_de_bookshelf_01.nif", "f/furn_com_bookshelf_01.nif"],  # standing shelves (furn_com_shelf is a small wall shelf)
	"prop/boulder": ["f/terrain_rock_wg_01.nif"],
	"prop/bucket": ["f/furn_bucket10.nif", "m/misc_com_bucket_01.nif"],
	"prop/cage": ["o/contain_ropecage_01.nif"],
	"prop/campfire": ["f/furn_de_firepit.nif", "f/furn_de_firepit_01.nif"],
	"prop/hearth": ["f/furn_de_firepit_f_01.nif", "f/furn_de_firepit.nif"],
	"prop/brazier": ["l/light_6th_brazier.nif", "l/light_dae_brazier00.nif"],
	"prop/candles": ["l/light_com_candle_06.nif", "l/light_com_candle_01.nif"],
	"prop/candle_stand": ["l/light_com_candle_16.nif", "l/light_com_candle_15.nif"],
	"prop/sconce": ["l/light_com_sconce_01.nif"],
	"prop/lamp_post": ["l/light_de_streetlight_01.nif"],
	"prop/cart": ["f/furn_cart00.nif"],
	"prop/broken_cart": ["f/furn_guarcart00.nif", "f/furn_cart00.nif"],
	"prop/broken_pillar": ["x/ex_dae_pillar_02_ruin.nif"],
	"prop/cauldron": ["f/furn_com_cauldron_01.nif", "o/contain_couldron10.nif"],
	"prop/chair": ["f/furn_com_chair_01.nif", "f/furn_de_chair_01.nif"],
	"prop/stool": ["f/furn_com_stool_01.nif", "f/furn_de_stool_01.nif"],
	"prop/throne": ["f/furn_de_chair_02.nif", "f/furn_com_chair_03.nif"],
	"prop/chest": ["o/contain_com_chest_01.nif"],
	"prop/cobweb": ["f/furn_web00.nif"],
	"prop/crate": ["o/contain_crate_01.nif"],
	"prop/crates": ["o/contain_crate_02.nif", "o/contain_crate_01.nif"],
	"prop/cupboard": ["o/contain_com_cupboard_01.nif"],
	"prop/wardrobe": ["o/contain_com_closet_01.nif"],
	"prop/display": ["o/contain_com_drawers_01.nif"],
	"prop/rack": ["f/furn_uni_weaponrack_01.nif"],
	"prop/counter": ["f/furn_com_bar_01.nif", "f/furn_de_bar_01.nif"],
	"door/building": ["d/ex_imp_loaddoor_01.nif", "d/ex_common_door_01.nif", "d/ex_nord_door_01.nif"],
	"door/dungeon": ["d/ex_cave_door_01.nif", "d/in_impsmall_d_cave_01.nif", "d/door_cavern_doors00.nif"],
	"prop/rope_coil": ["m/misc_ropecoil00.nif", "x/ex_coiled_rope.nif"],
	"prop/weapon_rack": ["f/furn_uni_weaponrack_01.nif"],
	"prop/keg_rack": ["f/furn_com_kegstand.nif", "f/furn_de_kegstand.nif"],
	"prop/log_pile": ["f/furn_logpile10.nif"],
	"prop/log_seat": ["f/furn_log_01.nif"],
	"prop/table": ["f/furn_com_table_01.nif"],
	"prop/table_meal": ["f/furn_com_table_03.nif", "f/furn_com_table_01.nif"],
	"prop/map_table": ["f/furn_com_table_02.nif", "f/furn_com_table_04.nif"],
	"prop/sacks": ["o/contain_com_sack_01.nif"],
	"prop/sack": ["o/contain_com_sack_02.nif", "o/contain_com_sack_01.nif"],
	"prop/urn": ["o/contain_urn_01.nif"],
	"prop/tapestry": ["f/furn_com_tapestry_01.nif"],
	"prop/banner": ["f/furn_banner_01.nif"],
	"prop/banner_blue": ["f/furn_banner_temple_01_in.nif", "f/furn_banner_01.nif"],
	"prop/banner_pole": ["f/furn_bannerpost_01.nif"],
	"prop/anvil": ["f/furn_anvil00.nif"],
	"prop/altar": ["f/furn_imp_altar_01.nif", "f/furn_velothi_altar_01.nif"],
	"prop/plinth": ["f/furn_imp_stoneblock_01.nif"],
	"prop/well": ["f/furn_well00.nif"],
	"prop/fountain": ["f/furn_well00.nif"],
	"prop/rubble": ["f/furn_dae_rubble_01a.nif"],
	"prop/training_dummy": ["f/furn_practice_dummy.nif"],
	"prop/armor_stand": ["f/furn_practice_dummy.nif"],
	"prop/fungus": ["f/flora_bc_mushroom_01.nif"],
	"prop/crystal": ["o/contain_rock_glass_01.nif"],
	"prop/rails": ["f/furn_rail_straight_00.nif"],
	"prop/pillar": ["i/in_c_pillar_stone.nif"],
	"prop/support_beams": ["i/in_c_pillar_wood_tall.nif", "i/in_c_pillar_wood.nif"],
	"prop/tent": ["i/in_ashl_tent_01.nif"],
	"prop/flower_box": ["f/furn_planter_01.nif", "f/furn_com_planter.nif"],
	"prop/drying_rack": ["f/furn_com_winerack.nif"],
	"prop/street_tree": ["f/flora_tree_wg_01.nif", "f/flora_tree_ai_05.nif"],
	"prop/sarcophagus": ["f/furn_burial00.nif"],
	"prop/niche": ["f/furn_burial10.nif"],
}

## Small things set on tables and shelves to make rooms lived-in (not taken; clutter/<name>)
const CLUTTER := {
	"clutter/plate": ["m/misc_com_plate_01.nif"],
	"clutter/plate_metal": ["m/misc_com_metal_plate_03.nif"],
	"clutter/bowl": ["m/misc_com_wood_bowl_01.nif"],
	"clutter/bowl_redware": ["m/misc_bowl_redware_01.nif"],
	"clutter/cup": ["m/misc_com_wood_cup_01.nif"],
	"clutter/goblet": ["m/misc_com_metal_goblet_01.nif"],
	"clutter/tankard": ["m/misc_com_tankard_01.nif"],
	"clutter/pitcher": ["m/misc_com_pitcher_metal_01.nif", "m/misc_de_pitcher_01.nif"],
	"clutter/bottle": ["m/misc_com_bottle_01.nif"],
	"clutter/bottle_2": ["m/misc_com_bottle_05.nif"],
	"clutter/bottle_3": ["m/misc_com_bottle_10.nif"],
	"clutter/flask": ["m/misc_flask_01.nif"],
	"clutter/fork": ["m/misc_com_wood_fork.nif"],
	"clutter/knife": ["m/misc_com_wood_knife.nif"],
	"clutter/spoon": ["m/misc_com_wood_spoon_01.nif"],
	"clutter/basket": ["m/misc_com_basket_01.nif"],
	"clutter/candle": ["l/light_com_candle_01.nif", "m/misc_candle_ivory_01.nif"],
	"clutter/book": ["m/text_octavo_01.nif"],
	"clutter/book_2": ["m/text_quarto_02.nif"],
	"clutter/book_3": ["m/text_folio_03.nif"],
	"clutter/book_open": ["m/text_octavo_open_01.nif"],
	"clutter/scroll": ["m/text_scroll_01.nif"],
	"clutter/paper": ["m/text_parchment_01.nif"],
	"clutter/inkwell": ["m/misc_inkwell.nif"],
	"clutter/quill": ["m/misc_quill.nif"],
	"clutter/skull": ["m/misc_skull00.nif"],
	"clutter/bone": ["f/furn_bone_rib_01.nif"],
	"clutter/cloth": ["m/misc_foldedcloth00.nif", "m/misc_cloth10.nif"],
	"clutter/urn": ["o/contain_pot_redware_01.nif", "o/contain_pot_01.nif"],
	"clutter/bread": ["n/ingred_bread_01.nif"],
	"clutter/hammer": ["m/misc_hammer10.nif"],
	"clutter/lute": ["m/misc_de_lute_01.nif"],
	"clutter/drum": ["m/misc_de_drum_01.nif"],
	"clutter/broom": ["m/misc_com_broom_01.nif"],
	"clutter/beaker": ["m/misc_beaker_01.nif"],
}

## Items by kind (the keys ItemModels.model_keys asks for)
const ITEMS := {
	"item/potion_health": ["m/misc_potion_standard_01.nif"],
	"item/potion_magicka": ["m/misc_potion_quality_01.nif"],
	"item/potion_stamina": ["m/misc_potion_fresh_01.nif"],
	"item/potion": ["m/misc_potion_cheap_01.nif"],
	"item/gold": ["m/misc_gold*.nif", "m/misc_dwrv_coin00.nif"],
	"item/book": ["m/text_octavo_02.nif"],
	"item/scroll": ["m/text_scroll_02.nif"],
	"item/gem": ["n/ingred_ruby_01.nif"],
	"item/goblet": ["m/misc_de_goblet_01.nif", "m/misc_com_metal_goblet_02.nif"],
	"item/tankard": ["m/misc_com_tankard_01.nif"],
	"item/plate": ["m/misc_com_plate_02.nif"],
	"item/bowl": ["m/misc_com_wood_bowl_02.nif"],
	"item/candlestick": ["l/light_com_candle_02.nif"],
	"item/lantern": ["l/light_com_lantern_01.nif"],
	"item/skull": ["m/misc_skull00.nif"],
	"item/bone": ["f/furn_bone_rib_01.nif"],
	"item/urn": ["o/contain_pot_01.nif"],
	"item/bucket": ["m/misc_com_bucket_01.nif"],
	"item/shovel": ["m/misc_shovel*.nif", "w/w_miner_pick.nif"],
	"item/pickaxe": ["w/w_miner_pick.nif"],
	"item/hammer": ["m/misc_hammer10.nif"],
	"item/broom": ["m/misc_com_broom_01.nif"],
	"item/sack": ["o/contain_com_sack_03.nif"],
	"item/idol": ["m/misc_dwrv_artifact00.nif"],
	"item/crown": ["m/misc_dwrv_artifact20.nif"],
	"item/pelt": ["n/ingred_guar_hide_01.nif"],
	"item/ore": ["n/ingred_rawebony_01.nif"],
	"item/ingot": ["m/misc_dwrv_gear00.nif"],
	"item/ring": ["c/c_ring_common*.nif", "c/c_ring*.nif"],
	"item/amulet": ["c/amulet*.nif", "c/c_amulet*.nif"],
	"item/key": ["m/misc_key*.nif"],
	"item/ingredient": ["n/ingred_heather_01.nif"],
	"item/food": ["n/ingred_comberry_01.nif"],
	"food/bread": ["n/ingred_bread_01.nif"],
	"food/meat": ["n/ingred_hound_meat_01.nif", "n/ingred_rat_meat_01.nif"],
	"food/fish": ["n/ingred_crabmeat_01.nif"],
	"food/apple": ["n/ingred_comberry_01.nif"],
	"weapon/staff": ["w/w_staff00.nif"],
	"weapon/bow": ["w/w_longbow.nif"],
	"weapon/shield": ["a/shield_iron.nif", "a/shield_steel.nif"],
	"item/arrow": ["w/w_iron_arrow.nif", "w/w_arrow01.nif"],
	"item/shirt": ["c/c_common_wool01shirtgnd.nif", "c/c_common_wool02shirtgnd.nif"],
	"item/fine_shirt": ["c/c_common_nordic01shirtgnd.nif", "c/c_common_wool02shirtgnd.nif"],
	"item/robe": ["c/c_common_wool01_robe_gnd.nif", "c/c_common_robe3blk_gnd.nif"],
	"item/shoes": ["c/c_shoes_common1_gnd.nif", "c/c_m_shoe_common01_gnd.nif"],
	"item/fine_shoes": ["c/c_m_shoe_expens_1_gnd.nif", "c/c_shoes_common2_gnd.nif"],
	"item/gloves": ["c/c_glove_common1_gnd.nif"],
	"item/cloth": ["m/misc_foldedcloth00.nif", "m/misc_cloth10.nif"],
	"item/hood": ["m/misc_foldedcloth00.nif"],
	"item/lockpick": ["m/pick_apprentice_01.nif", "m/probe_apprentice_01.nif"],
	"item/tongs": ["m/misc_prongs00.nif"],
	"item/rope": ["m/misc_ropecoil00.nif"],
	"item/lute": ["m/misc_de_lute_01.nif"],
	"item/inkwell": ["m/misc_inkwell.nif"],
	"item/bottle": ["m/misc_com_bottle_01.nif", "m/misc_com_bottle_02.nif"],
	"item/pitcher": ["m/misc_com_pitcher_metal_01.nif", "m/misc_redware_pitcher.nif"],
	"item/paper": ["m/misc_paper_plain_01.nif", "m/text_scroll_02.nif"],
	"item/pearl": ["n/ingred_pearl_01.nif"],
	"item/heart": ["n/ingred_daedra_heart_01.nif"],
	"item/mask": ["m/misc_vivec_ashmask_01.nif"],
	"item/lamp": ["m/misc_redware_lamp.nif"],
	"item/small_chest": ["m/misc_chest_small_01.nif"],
	"item/salt": ["n/ingred_ash_salts_01.nif"],
	"item/herb": ["n/ingred_stoneflower_01.nif", "n/ingred_heather_01.nif"],
	"item/root": ["n/ingred_trama_root_01.nif"],
	"item/mushroom": ["n/ingred_russula_01.nif", "n/ingred_coprinus_01.nif"],
	"item/egg": ["m/misc_kwamaegg_gold_01.nif"],
	"item/feather": ["n/ingred_racer_plumes_01.nif"],
	"item/cabbage": ["n/ingred_scrib_cabbage_01.nif"],
	"item/leek": ["n/ingred_marshmerrow_01.nif"],
	"food/potato": ["n/ingred_ash_yam_01.nif"],
	"food/onion": ["n/ingred_ash_yam_01.nif"],
}

## The game's ingredients and materials that have a close Morrowind match of their own
const ITEM_IDS := {
	"ash_salt": "n/ingred_ash_salts_01.nif", "fire_salts": "n/ingred_fire_salts_01.nif",
	"void_salt": "n/ingred_void_salts_01.nif", "storm_crystal": "n/ingred_raw_glass_01.nif",
	"bone_meal": "n/ingred_blonemeal_01.nif", "bear_claw": "n/ingred_lloramor_spines_01.nif",
	"wolf_fang": "n/ingred_lloramor_spines_01.nif", "hawk_feather": "n/ingred_racer_plumes_01.nif",
	"crawler_eye": "n/ingred_kwama_cuttle_01.nif", "spider_egg": "n/ingred_bc_ampoule_pod.nif",
	"venom_sac": "n/ingred_bc_spore_pod.nif", "river_scale": "n/ingred_scales_01.nif",
	"troll_fat": "n/ingred_dreugh_wax_01.nif", "wisp_dust": "n/ingred_vampire_dust_01.nif",
	"glowcap": "n/ingred_bc_hypha_facia.nif", "bloodmoss": "n/ingred_red_lichen_01.nif",
	"nightshade": "n/ingred_bm_belladonna_01.nif", "lavender": "n/ingred_heather_01.nif",
	"thistle": "n/ingred_bittergreen_01.nif", "blue_mountain_flower": "n/ingred_stoneflower_01.nif",
	"red_mountain_flower": "n/ingred_fire_petal_01.nif", "frost_mirriam": "n/ingred_bm_holly_01.nif",
	"cactus_flower": "n/ingred_bc_coda_flower.nif", "juniper_berries": "n/ingred_comberry_01.nif",
	"snowberries": "n/ingred_bm_holly_01.nif", "mandrake_root": "n/ingred_trama_root_01.nif",
	"sandroot": "n/ingred_corkbulb_root_01.nif", "swamp_lily": "n/ingred_horn_lily_bulb_01.nif",
	"wild_garlic": "n/ingred_marshmerrow_01.nif", "animal_hide": "n/ingred_guar_hide_01.nif",
	"leather": "n/ingred_netch_leather_01.nif", "leather_strips": "n/ingred_netch_leather_01.nif",
	"bear_pelt": "n/ingred_hide_brnbear.nif", "wolf_pelt": "n/ingred_hide_grywolf.nif",
	"cabbage": "n/ingred_scrib_cabbage_01.nif", "carrot": "n/ingred_ash_yam_01.nif",
	"potato": "n/ingred_ash_yam_01.nif", "leek": "n/ingred_marshmerrow_01.nif",
	"egg": "m/misc_kwamaegg_gold_01.nif", "honey": "m/misc_pot_redware_01.nif",
	"milk": "m/misc_redware_pitcher.nif", "butter": "m/misc_redware_bowl.nif",
	"salt": "m/misc_silverware_bowl.nif", "raw_fish": "n/ingred_crabmeat_01.nif",
	"raw_meat": "n/ingred_hound_meat_01.nif", "obsidian_shard": "n/ingred_raw_glass_01.nif",
	"glacier_pearl": "n/ingred_pearl_01.nif", "runed_mask": "m/misc_vivec_ashmask_01.nif",
	"quiet_ash_censer": "m/misc_redware_lamp.nif", "gilded_reliquary": "m/misc_chest_small_02.nif",
	"ember_heart": "n/ingred_daedra_heart_01.nif", "construct_heart": "m/misc_dwrv_gear00.nif",
	"bronze_sky_disc": "m/misc_dwrv_artifact40.nif", "drowned_astrolabe": "m/misc_dwrv_artifact30.nif",
	"vault_keystone": "m/misc_dwrv_ark_cube00.nif", "tongs": "m/misc_prongs00.nif",
	"rope": "m/misc_ropecoil00.nif", "inkwell": "m/misc_inkwell.nif", "lute": "m/misc_de_lute_01.nif",
	"empty_bottle": "m/misc_com_bottle_03.nif", "lockpick": "m/pick_apprentice_01.nif",
}

## Morrowind's weapons lie with the blade toward -Z and the grip at the origin: stood up, blade +Y, as the
## game holds them
const WEAPON_ROT := [90, 0, 0]

## The game's materials -> Morrowind's (weapons and armour)
const MATERIALS := {"iron": "iron", "steel": "steel", "silver": "silver", "obsidian": "glass", "ebon": "ebony",
	"dragonbone": "daedric", "starforged": "dwemer", "leather": "netch", "hide": "nordicfur", "dragonscale": "dragonscale",
	"shadowscale": "chitin", "silverweave": "bonemold", "ebonweave": "indoril", "starweave": "glass"}
## The game's weapon kinds -> Morrowind's names for them
const WEAPON_NAMES := {"sword": ["longsword", "broadsword", "shortsword"], "dagger": ["dagger", "knife", "shortsword"],
	"greatsword": ["claymore"], "warhammer": ["warhammer"], "waraxe": ["waraxe", "axe"], "mace": ["mace", "club"],
	"spear": ["spear", "longspear", "halberd"], "battleaxe": ["battleaxe"]}
## The game's armour pieces -> Morrowind's ground models
const ARMOR_NAMES := {"cuirass": ["cuirass_gnd", "cuir_gnd", "c_gnd"], "chestplate": ["cuirass_gnd", "cuir_gnd"],
	"greaves": ["greaves_gnd", "greave_gnd", "gr_gnd"], "boots": ["boot_gnd", "boots_gnd"],
	"gauntlets": ["gauntlet_gnd", "bracer_gnd"], "helmet": ["helm*", "helmet*"], "shield": ["shield*"]}

## Morrowind's creatures: [mesh, animation]. Several look-alikes share one where Morrowind has none.
const CREATURES := {
	"creature/wolf": ["r/wolf_red.nif", "r/xwolf_red.kf"],
	"creature/hound": ["r/wolf_black.nif", "r/xwolf_black.kf"],
	"creature/ash_hound": ["r/nixhound.nif", "r/xnixhound.kf"],
	"creature/dune_stalker": ["r/leastkagouti.nif", "r/xleastkagouti.kf"],
	"creature/giant_rat": ["r/rust rat.nif", "r/xrust rat.kf"],
	"creature/frost_bear": ["r/bear_blond_larger.nif", "r/xbear_blond_larger.kf"],
	"creature/bog_lurker": ["r/dreugh.nif", "r/xdreugh.kf"],
	"creature/harpy": ["r/cliffracer.nif", "r/xcliffracer.kf"],
	"creature/grave_ghoul": ["r/lame_corprus.nif", "r/xlame_corprus.kf"],
	"creature/sheep": ["r/guar.nif", "r/xguar.kf"],
	"creature/cow": ["r/guar_white.nif", "r/xguar_white.kf"],
	"creature/horse": ["r/guar_withpack.nif", "r/xguar_withpack.kf"],
	"creature/deep_crawler": ["r/kwama worker.nif", "r/xkwama worker.kf"],
	"creature/crawler_queen": ["r/kwama queen.nif", "r/xkwama queen.kf"],
	"creature/giant_spider": ["r/minescrib.nif", "r/xminescrib.kf"],
	"creature/sand_scorpion": ["r/shalk.nif", "r/xshalk.kf"],
	"creature/fire_spirit": ["r/atronach_fire.nif", "r/xatronach_fire.kf"],
	"creature/ice_wraith": ["r/atronach_frost.nif", "r/xatronach_frost.kf"],
	"creature/skeleton": ["r/skeleton.nif", "r/xskeleton.kf"],
	"creature/skeleton_knight": ["r/skeleton.nif", "r/xskeleton.kf"],
	"creature/crypt_warden": ["r/bonelord.nif", "r/xbonelord.kf"],
	"creature/barrow_wight": ["r/cr_draugr.nif", "r/xcr_draugr.kf"],
	"creature/wight_lord": ["r/draugrlord.nif", "r/xdraugrlord.kf"],
	"creature/drowned_sailor": ["r/cr_draugr.nif", "r/xcr_draugr.kf"],
	"creature/vault_guardian": ["r/steam_centurions.nif", "r/xsteam_centurions.kf"],
	"creature/vault_sentinel": ["r/sphere_centurions.nif", "r/xsphere_centurions.kf"],
	"creature/cave_troll": ["r/ice troll.nif", "r/xice troll.kf"],
	"creature/forest_troll": ["r/ice troll.nif", "r/xice troll.kf"],
	"creature/frost_giant": ["r/frostgiant.nif", "r/xfrostgiant.kf"],
	"creature/marsh_hag": ["r/spriggan.nif", "r/xspriggan.kf"],
	"creature/cave_dweller": ["r/goblin01.nif", "r/xgoblin01.kf"],
	"creature/dragon": ["r/cliffracer.nif", "r/xcliffracer.kf"],
}
## Creatures that walk on two legs and hold weapons in Morrowind's hand bones
const ARMED := ["creature/skeleton", "creature/skeleton_knight", "creature/barrow_wight", "creature/wight_lord",
	"creature/drowned_sailor", "creature/cave_dweller", "creature/crypt_warden", "creature/frost_giant"]
## How much bigger than Morrowind's own a few are
const CREATURE_SCALE := {"creature/dragon": 3.0, "creature/crawler_queen": 0.6, "creature/giant_spider": 2.6}

## Nature: trees by style, rocks for scatter (nature/rock_N), see TerrainChunk and NatureMeshes
const NATURE := {
	"tree/broadleaf": ["f/flora_tree_ai_05.nif", "f/flora_tree_wg_01.nif"],
	"tree/pine": ["f/flora_tree_ac_01.nif", "f/flora_tree_gl_01.nif"],
	"tree/dead": ["f/flora_tree_wg_05.nif", "f/flora_tree_ac_03.nif"],
	"tree/cactus": ["f/flora_tree_ac_04.nif"],
	"nature/rock_0": ["f/terrain_rock_wg_02.nif"],
	"nature/rock_1": ["f/terrain_rock_ai_03.nif"],
	"nature/rock_2": ["f/terrain_rock_gl_04.nif"],
}


## Every ModelLibrary key -> the mesh file in your copy (only those it has), plus how to fit it
static func statics(data: MwData) -> Dictionary:
	var out := {}
	for table: Dictionary in [PROPS, CLUTTER, NATURE]:
		for key in table:
			var f := data.find(_paths(table[key]))
			if f != "":
				out[key] = {"file": f, "fit": "real"}
	for key in ITEMS:
		var f := data.find(_paths(ITEMS[key]))
		if f != "":
			out[key] = {"file": f, "fit": "long" if key.begins_with("weapon/") else "real"}
			if key in ["weapon/staff", "weapon/bow"]:
				out[key]["rot"] = WEAPON_ROT
	for id in ITEM_IDS:
		var f := data.find(_paths([ITEM_IDS[id]]))
		if f != "":
			out["item/" + id] = {"file": f, "fit": "real"}
	# Every weapon and piece of armour, by its material
	for item in ItemCatalog.all_items():
		var f := _for_item(data, item)
		if f != "":
			var held := item.item_type == ItemData.ItemType.WEAPON or item.equip_slot == ItemData.EquipSlot.OFF_HAND
			out["item/" + String(item.id)] = {"file": f, "fit": "long" if held else "real"}
			if item.item_type == ItemData.ItemType.WEAPON and not String(item.id).ends_with("_shield"):
				out["item/" + String(item.id)]["rot"] = WEAPON_ROT
	return out


static func _paths(list: Array) -> Array:
	return list.map(func(p): return "meshes/" + String(p))


# A weapon or armour piece: its material and kind in Morrowind's names
static func _for_item(data: MwData, item: ItemData) -> String:
	var id := String(item.id)
	var mat := id.get_slice("_", 0)
	var kind := id.substr(mat.length() + 1)
	if not MATERIALS.has(mat):
		return ""
	var mw: String = MATERIALS[mat]
	var tries: Array = []
	if kind == "arrow":
		return data.find(["meshes/w/w_%s_arrow.nif" % mw, "meshes/w/w_iron_arrow.nif", "meshes/w/w_arrow01.nif"])
	if kind == "shield":
		tries = ["meshes/a/shield_%s.nif" % mw, "meshes/a/towershield_%s.nif" % mw, "meshes/a/shield_steel.nif", "meshes/a/shield_iron.nif"]
	elif WEAPON_NAMES.has(kind):
		for n in WEAPON_NAMES[kind]:
			tries.append("meshes/w/w_%s_%s.nif" % [mw, n])
			tries.append("meshes/w/w_%s_%s.nif" % [n, mw])
		for fallback in ["steel", "iron"]:
			for n in WEAPON_NAMES[kind]:
				tries.append("meshes/w/w_%s_%s.nif" % [fallback, n])
				tries.append("meshes/w/w_%s_%s.nif" % [n, fallback])
		tries.append("meshes/w/w_%s*.nif" % WEAPON_NAMES[kind][0])
	elif ARMOR_NAMES.has(kind):
		for n in ARMOR_NAMES[kind]:
			tries.append("meshes/a/a_%s_%s.nif" % [mw, n])
			tries.append("meshes/a/a_%s*_%s.nif" % [mw, n])
			tries.append("meshes/a/a_m_%s_%s.nif" % [mw, n])
		for n in ARMOR_NAMES[kind]:
			tries.append("meshes/a/a_iron_%s.nif" % n)
	else:
		return ""
	return data.find(tries)
