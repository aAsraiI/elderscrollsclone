class_name MwKitCatalog
extends RefCounted
## The builder kit's Morrowind pieces: every building set in your copy (cave, fort, tomb, castle, town,
## room, dock, door, light, furniture, rock and plant pieces), sorted by type and set as ModelLibrary
## keys "kit/<type>/<set>/<mesh name>" ("kit/caves/mold/in_moldcave_lroom3_00"). MwImport.run_kit
## converts each one your copy has into your models folder; tools/build_kit.gd then writes a scene for
## each under scenes/kit/morrowind/<type>/<set>/ to drag into a level. Pieces keep Morrowind's own
## size, so pieces of one set snap together on its grid.

## [type, set, file patterns (inside meshes/, * and ?)], most useful first. A file goes to the first
## set that matches it.
const SETS := [
	# Caves: rooms, halls, exits and loose rock for each kind of cave
	["caves", "mold", ["i/in_moldcave*", "i/in_mold_*"]],
	["caves", "mud", ["i/in_mudcave*", "i/in_mud_*"]],
	["caves", "bone", ["i/in_bonecave*", "i/in_bone_*"]],
	["caves", "lava", ["i/in_lavacave*", "i/in_lava_*"]],
	["caves", "ash", ["i/in_pycave*", "i/in_py_*"]],
	["caves", "ice", ["i/bm_ic_*", "i/in_glacier*"]],
	["caves", "cavern", ["i/in_cavern*", "i/in_velothicave*"]],
	# Dungeons built by hand: forts, strongholds, sewers
	["dungeons", "imperial_fort", ["i/in_impsmall*"]],
	["dungeons", "stronghold", ["i/in_strong_*", "i/in_stronghold*"]],
	["dungeons", "stronghold_ruin", ["i/in_strongruin*"]],
	["dungeons", "sewer", ["i/in_sewer*", "i/in_m_sewer*"]],
	["dungeons", "dwemer", ["i/in_dwrv*", "i/in_dwe_*", "i/in_dwe*"]],
	["dungeons", "daedric", ["i/in_dae*"]],
	["dungeons", "mournhold_ruin", ["i/in_om_*", "i/in_om*"]],
	["dungeons", "sixth_house", ["i/in_dagoth*"]],
	# Tombs and crypts
	["tombs", "velothi", ["i/in_velothismall*", "i/in_velothilarge*", "i/in_velothi_*", "i/in_velothi*", "i/in_vs*"]],
	["tombs", "barrow", ["i/in_bm_*", "i/in_bm*", "i/in_thirsk*"]],
	["tombs", "ancestral", ["i/in_ci_*"]],
	# Castles, walls and outdoor ruins
	["castles", "imperial", ["x/ex_imp_*"]],
	["castles", "stronghold", ["x/ex_stronghold_*", "x/ex_strongholdruin*", "x/ex_strongruin*"]],
	["castles", "redoran_wall", ["x/ex_redwall*"]],
	["castles", "ghostfence", ["x/ex_gg_*"]],
	["castles", "velothi", ["x/ex_velothi*"]],
	["castles", "daedric", ["x/ex_dae_*", "x/ex_daed*"]],
	["castles", "dwemer", ["x/ex_dwrv*"]],
	["castles", "ruin", ["x/ex_ruin*", "x/ex_drystonewall*"]],
	# Town buildings and their parts
	["towns", "common", ["x/ex_common*"]],
	["towns", "nord", ["x/ex_nord*"]],
	["towns", "skaal", ["x/ex_s_*"]],
	["towns", "colony", ["x/ex_colony*", "x/ex_bm_*"]],
	["towns", "hlaalu", ["x/ex_hlaalu*"]],
	["towns", "redoran", ["x/ex_redoran*"]],
	["towns", "dunmer", ["x/ex_de_*", "x/ex_scrapwood*", "x/ex_ropebridge*", "x/ex_longboat*"]],
	["towns", "ashlander", ["x/ex_ashl*"]],
	["towns", "mournhold", ["x/ex_mh*"]],
	["towns", "vivec", ["x/ex_vivec*", "x/ex_v_*"]],
	["towns", "telvanni", ["x/ex_t_*"]],
	["towns", "cave_mouths", ["x/ex_*cave*", "x/ex_*_entrance*"]],
	# Rooms inside buildings
	["rooms", "common", ["i/in_c_*", "i/in_common*"]],
	["rooms", "nord", ["i/in_nord*", "i/in_s_*"]],
	["rooms", "colony", ["i/bm_colony*", "i/bm_ka*"]],
	["rooms", "hlaalu", ["i/in_hlaalu*", "i/in_h_*"]],
	["rooms", "redoran", ["i/in_redoran*", "i/in_r_*"]],
	["rooms", "dunmer", ["i/in_de_*"]],
	["rooms", "ashlander", ["i/in_ashl*"]],
	["rooms", "mournhold", ["i/in_mh*"]],
	["rooms", "vivec", ["i/in_v_*", "i/in_v*"]],
	["rooms", "telvanni", ["i/in_t_*", "i/in_t*"]],
	["rooms", "arena", ["i/in_ar_*"]],
	["rooms", "sotha_sil", ["i/in_sotha*"]],
	# Doors and doorways
	["doors", "cave", ["d/*cave*", "d/*cavern*"]],
	["doors", "trapdoors", ["d/*trapdoor*", "d/*grate*"]],
	["doors", "jail", ["d/*jail*"]],
	["doors", "imperial", ["d/*imp*", "d/ex_emp_*"]],
	["doors", "nord", ["d/*nord*", "d/*colony*", "d/bm_*", "d/ex_bm_*", "d/ex_s_*", "d/in_s_*", "d/*thirsk*"]],
	["doors", "common", ["d/*_c_door*", "d/ex_common*"]],
	["doors", "dungeon", ["d/*strong*", "d/*dwrv*", "d/*dwe*", "d/*dae*", "d/*velothi*", "d/*sotha*", "d/in_db_*", "d/*_ci_*", "d/*om_*"]],
	["doors", "dunmer", ["d/*hlaalu*", "d/*redoran*", "d/*_r_*", "d/*_h_*", "d/*_de_*", "d/*_t_*", "d/*_v_*", "d/*vivec*", "d/*_mh_*", "d/*_m_*", "d/*_ar_*"]],
	["doors", "other", ["d/*"]],
	# Lights: candles, lanterns, sconces, braziers, chandeliers
	["lights", "candles", ["l/*candle*"]],
	["lights", "lanterns", ["l/*lantern*", "l/*paper*", "l/*lamp*"]],
	["lights", "sconces", ["l/*sconce*", "l/*torch*"]],
	["lights", "fires", ["l/*brazier*", "l/*fire*", "l/*pit*"]],
	["lights", "chandeliers", ["l/*chandelier*"]],
	["lights", "other", ["l/*"]],
	# Furniture beyond the props the game already uses
	["furniture", "common", ["f/furn_com*", "f/furn_c_*"]],
	["furniture", "imperial", ["f/furn_imp*"]],
	["furniture", "nord", ["f/furn_colony*", "f/furn_nord*", "f/furn_s_*", "f/bm_*furn*"]],
	["furniture", "dunmer", ["f/furn_de*", "f/furn_redoran*", "f/furn_hlaalu*"]],
	["furniture", "dwemer", ["f/furn_dwrv*"]],
	["furniture", "daedric", ["f/furn_dae*", "f/furn_6th*"]],
	["furniture", "banners", ["f/furn_banner*", "f/furn_bannerd*"]],
	["furniture", "rugs", ["f/furn_rug*", "f/furn_cushion*"]],
	["furniture", "shrines", ["f/furn_shrine*", "f/furn_imp_altar*"]],
	["furniture", "ashlander", ["f/furn_ashl*"]],
	["furniture", "other", ["f/furn_*"]],
	# Containers (static: KitContainer makes them lootable)
	["containers", "all", ["o/contain_*"]],
	# Rocks, boulders and cliffs
	["rocks", "ascadian", ["f/terrain_rock_ai*", "x/terrain_rock_ai*"]],
	["rocks", "west_gash", ["f/terrain_rock_wg*", "x/terrain_rock_wg*"]],
	["rocks", "grazelands", ["f/terrain_rock_gl*", "x/terrain_rock_gl*"]],
	["rocks", "bitter_coast", ["f/terrain_rock_bc*", "x/terrain_rock_bc*"]],
	["rocks", "ashlands", ["f/terrain_rock_ash*", "x/terrain_ashland*", "f/terrain_rock_rm*"]],
	["rocks", "molag_amur", ["f/terrain_rock_ma*", "x/terrain_rock_ma*", "x/terrain_ma*", "x/terrain_lava*"]],
	["rocks", "coast", ["f/terrain_rock_ac*", "f/terrain_rock_sc*", "x/terrain_rock_ac*"]],
	["rocks", "solstheim", ["f/terrain_bm*", "x/terrain_bm*", "x/bm_ex_*rock*", "x/ex_nord_rock*"]],
	["rocks", "other", ["f/terrain_*", "x/terrain_*"]],
	# Trees, bushes, flowers, mushrooms, grass
	["plants", "trees", ["f/flora_tree*", "f/flora_ashtree*", "x/flora_ashtree*", "f/flora_bm_tree*", "f/flora_bm_snow*tree*"]],
	["plants", "logs_roots", ["f/flora_*log*", "x/flora_*log*", "f/flora_root*", "f/flora_*stump*"]],
	["plants", "solstheim", ["f/flora_bm_*"]],
	["plants", "mushrooms", ["f/flora_bc_mushroom*", "f/flora_*mushroom*", "x/flora_*mushroom*", "f/flora_t_*"]],
	["plants", "bitter_coast", ["f/flora_bc_*"]],
	["plants", "grass", ["f/flora_grass*", "f/flora_kelp*"]],
	["plants", "other", ["f/flora_*", "x/flora_*"]],
	# Small things for set dressing
	["clutter", "all", ["m/misc_*"]],
]

## Never pieces: animation companions, moving parts, markers and creature parts
const SKIP := ["x*", "act_*", "*_anim*", "*marker*", "*collision*"]


## Every kit key -> {"file": archive path, "fit": "real"} for the pieces your copy has
static func statics(data: MwData) -> Dictionary:
	var out := {}
	var used := {}
	for s: Array in SETS:
		for pat in s[2]:
			for f in data.find_all("meshes/" + String(pat)):
				if used.has(f) or not f.ends_with(".nif") or _skipped(f.get_file()):
					continue
				used[f] = true
				out["kit/%s/%s/%s" % [s[0], s[1], f.get_file().get_basename()]] = {"file": f, "fit": "real"}
	return out


static func _skipped(file: String) -> bool:
	for p in SKIP:
		if file.match(p):
			return true
	return false
