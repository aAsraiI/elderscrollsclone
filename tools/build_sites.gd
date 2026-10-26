extends "res://tools/build_interiors.gd"
## The outdoor places of Alpha 1.14, as scenes you can finish by hand:
##   outdoor props      tents, campfires, log seats, fences, gravestones... (scenes/interiors/props/)
##   site scenes        scenes/sites/<kind>_<version>.tscn (ExteriorSite)
##   site kinds         data/world/Sites/<kind>.tres (SitePOIData: versions, occupants, dungeon)
##   biome rules        each biome's Poi Rules get the kinds that suit it
## Scenes and kinds that exist are kept (hand edits are safe); pass --force to make them again.
##   godot --headless --path . -s res://tools/build_sites.gd [-- --force]

const SITE_DIR := "res://scenes/sites/"
const KIND_DIR := "res://data/world/Sites/"
const ENEMIES := "res://data/enemies/"
const SPAWNS := "res://data/spawns/"
const DUNGEONS := "res://data/world/Dungeons/"
const L := RoomModule.LEVEL
## Alpha 1.14.4: places about three times as close as before
const DENSITY := 3.0
## Small things: not discovered, not on the map
const SMALL := ["roadside_camp", "wrecked_cart", "dead_traveller", "lost_pack", "fishing_spot", "herb_patch", "ore_outcrop", "nest"]

## kind -> [display name, theme, icon, occupants table, boss, dungeon ("" = none), footprint, flatten,
##          biomes ([] = all), per km2 (times DENSITY), min distance, prefers, path to a road (m)]
const KINDS := {
	"bandit_camp": ["Bandit Camp", "camp", "camp", "garrison_camp", "bandit_brute", "", 20.0, 16.0, [], 0.10, 500.0, "any", 0.0],
	"bandit_hold": ["Bandit Hold", "camp", "camp", "garrison_camp", "deserter_captain", "fort_ruin", 30.0, 26.0, [], 0.04, 900.0, "high", 0.0],
	"hunters_camp": ["Hunters' Camp", "camp", "camp", "enc_hunter", "", "", 14.0, 10.0, ["forest", "tundra", "snow_mountains", "highlands", "lakeland", "swamp"], 0.06, 500.0, "any", 0.0],
	"giant_camp": ["Giant Camp", "camp", "camp", "enc_forest_troll", "frost_giant", "", 24.0, 18.0, ["highlands", "tundra", "snow_mountains", "frozen_crown", "badlands"], 0.03, 1200.0, "high", 0.0],
	"watchtower": ["Watchtower", "fort", "tower", "garrison_tower", "deserter_captain", "", 14.0, 10.0, [], 0.07, 600.0, "high", 200.0],
	"mage_tower": ["Mage Tower", "fort", "tower", "garrison_ruins", "ashen_priest", "crypt", 16.0, 12.0, [], 0.02, 1500.0, "high", 0.0],
	"lighthouse": ["Lighthouse", "fort", "lighthouse", "enc_coast_raiders", "", "", 14.0, 10.0, ["coast"], 0.04, 1200.0, "water", 250.0],
	"ruined_keep": ["Ruined Keep", "ruin", "ruin", "garrison_ruins", "skeleton_knight", "crypt", 26.0, 20.0, [], 0.05, 700.0, "high", 200.0],
	"ruined_temple": ["Ruined Temple", "ruin", "ruin", "garrison_shrine", "wight_lord", "", 20.0, 16.0, [], 0.04, 800.0, "any", 150.0],
	"ruined_village": ["Ruined Village", "ruin", "ruin", "enc_dead_ghouls", "", "", 30.0, 24.0, ["plains", "lakeland", "forest", "deadlands", "ashlands", "swamp"], 0.03, 1000.0, "any", 200.0],
	"aqueduct": ["Old Aqueduct", "ruin", "ruin", "", "", "", 26.0, 0.0, ["plains", "desert", "badlands", "lakeland"], 0.02, 1500.0, "any", 0.0],
	"fort": ["Fort", "fort", "fort", "dungeon_fort", "deserter_captain", "fort_ruin", 36.0, 32.0, [], 0.025, 1400.0, "high", 300.0],
	"farmstead": ["Farmstead", "house", "farm", "", "", "", 24.0, 20.0, ["plains", "lakeland", "forest", "highlands", "coast"], 0.08, 450.0, "road", 250.0],
	"mill": ["Mill", "house", "mill", "", "", "", 16.0, 12.0, ["plains", "lakeland", "forest", "coast"], 0.04, 700.0, "water", 250.0],
	"lumber_camp": ["Lumber Camp", "house", "camp", "", "", "", 18.0, 14.0, ["forest", "tundra", "swamp", "highlands"], 0.05, 600.0, "road", 200.0],
	"mine_entrance": ["Mine", "mine", "mine", "enc_prospector", "", "abandoned_mine", 18.0, 12.0, ["highlands", "snow_mountains", "badlands", "tundra", "ashlands"], 0.05, 700.0, "high", 250.0],
	"quarry": ["Quarry", "mine", "mine", "", "", "", 22.0, 16.0, ["highlands", "badlands", "plains", "desert"], 0.03, 900.0, "road", 250.0],
	"wayside_shrine": ["Shrine", "crypt", "shrine", "", "", "", 10.0, 8.0, [], 0.06, 500.0, "road", 120.0],
	"stone_circle": ["Standing Stones", "ruin", "stones", "garrison_stones", "", "", 16.0, 0.0, [], 0.03, 1000.0, "high", 0.0],
	"graveyard": ["Graveyard", "crypt", "grave", "enc_dead_ghouls", "grave_ghoul", "barrow", 22.0, 18.0, [], 0.04, 800.0, "low", 200.0],
	"battlefield": ["Old Battlefield", "ruin", "battle", "enc_dead_ghouls", "skeleton_knight", "", 30.0, 0.0, ["plains", "highlands", "deadlands", "ashlands", "badlands", "tundra"], 0.02, 1500.0, "low", 0.0],
	"monument": ["Monument", "ruin", "stones", "", "", "", 14.0, 10.0, [], 0.02, 1500.0, "high", 150.0],
	"shipwreck": ["Shipwreck", "house", "wreck", "enc_coast_drowned", "drowned_sailor", "", 18.0, 0.0, ["coast", "swamp", "lakeland"], 0.04, 900.0, "water", 0.0],
	"dock": ["Dock", "house", "dock", "", "", "", 18.0, 12.0, ["coast", "lakeland"], 0.04, 800.0, "water", 250.0],
	"ferry": ["Ferry", "house", "dock", "", "", "", 16.0, 10.0, ["lakeland", "swamp", "coast"], 0.02, 1500.0, "water", 250.0],
	"bridge": ["Old Bridge", "ruin", "bridge", "", "", "", 20.0, 0.0, ["lakeland", "forest", "highlands", "swamp", "plains"], 0.02, 1200.0, "water", 200.0],
	"ruined_bastion": ["Ruined Bastion", "ruin", "ruin", "garrison_ruins", "skeleton_knight", "crypt", 26.0, 20.0, [], 0.03, 900.0, "high", 0.0],
	"beast_den": ["Beast's Den", "camp", "camp", "enc_wolves", "cave_troll", "", 22.0, 18.0, ["forest", "highlands", "tundra", "snow_mountains", "swamp", "badlands"], 0.03, 1100.0, "low", 0.0],
	# small places between the big ones (not discovered, not on the map: SMALL)
	"roadside_camp": ["Campfire", "camp", "camp", "enc_wanderer", "", "", 6.0, 4.0, [], 0.15, 300.0, "road", 0.0],
	"wrecked_cart": ["Wrecked Cart", "camp", "camp", "enc_plains_ambush", "", "", 6.0, 4.0, [], 0.12, 400.0, "road", 0.0],
	"dead_traveller": ["Dead Traveller", "camp", "camp", "", "", "", 4.0, 0.0, [], 0.12, 400.0, "road", 0.0],
	"lost_pack": ["Lost Pack", "camp", "camp", "", "", "", 3.0, 0.0, [], 0.12, 400.0, "any", 0.0],
	"fishing_spot": ["Fishing Spot", "house", "dock", "", "", "", 6.0, 0.0, ["lakeland", "coast", "swamp", "forest", "plains"], 0.08, 500.0, "water", 0.0],
	"herb_patch": ["Herb Patch", "camp", "camp", "", "", "", 5.0, 0.0, [], 0.15, 300.0, "any", 0.0],
	"ore_outcrop": ["Ore Outcrop", "mine", "mine", "", "", "", 6.0, 0.0, ["highlands", "snow_mountains", "badlands", "tundra", "ashlands", "desert", "frozen_crown"], 0.12, 400.0, "high", 0.0],
	"nest": ["Nest", "camp", "camp", "enc_forest_spiders", "", "", 7.0, 0.0, ["forest", "swamp", "highlands", "badlands", "deadlands"], 0.08, 500.0, "low", 0.0],
	"wayside_inn": ["Wayside Rest", "house", "camp", "", "", "", 14.0, 10.0, ["plains", "lakeland", "forest", "highlands", "coast", "tundra", "desert"], 0.03, 1500.0, "road", 60.0],
}

var _n := 0
var _site: ExteriorSite


func _initialize() -> void:
	force = OS.get_cmdline_user_args().has("--force")
	InteriorKit.save_materials()
	_outdoor_props()
	_sites()
	_kinds()
	_biomes()
	print("build_sites: %d scenes made, %d kept as they were" % [made, kept])
	quit()


# ---------------------------------------------------------------- outdoor props

func _outdoor_props() -> void:
	var F := InteriorProp.Snap.FLOOR
	var out := ["camp", "house", "fort", "ruin", "mine", "crypt"]
	var fire := Color(1.0, 0.6, 0.3)
	_prop("tent", ["tent"], ["FURNITURE"], F, [["box", Vector3(2.6, 0.08, 3.0), Vector3(-0.62, 0.9, 0), "cloth", 0.0], ["box", Vector3(0.06, 1.9, 0.06), Vector3(0, 0.95, -1.4), "wood_dark"], ["box", Vector3(0.06, 1.9, 0.06), Vector3(0, 0.95, 1.4), "wood_dark"]],
		{"themes": ["camp"], "tent": true})
	_prop("campfire", ["campfire", "fire", "light"], ["LIGHT", "FURNITURE", "DECORATION"], F, [["cyl", Vector3(1.2, 0.15, 1.2), Vector3(0, 0.07, 0), "stone_dark"], ["box", Vector3(0.9, 0.12, 0.12), Vector3(0, 0.2, 0), "wood_dark", 0.6], ["box", Vector3(0.9, 0.12, 0.12), Vector3(0, 0.2, 0), "wood_dark", -0.6], ["box", Vector3(0.35, 0.3, 0.35), Vector3(0, 0.35, 0), "glow"]],
		{"themes": ["camp", "house", "ruin", "mine"], "light": fire, "range": 9.0, "energy": 1.6, "light_at": Vector3(0, 0.8, 0)})
	_prop("bedroll_out", ["bed", "bedroll"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.8, 0.08, 1.9), Vector3(0, 0.04, 0), "cloth"], ["box", Vector3(0.5, 0.12, 0.3), Vector3(0, 0.1, 0.75), "cloth_red"]], {"themes": ["camp"], "ghost": true})
	_prop("log_seat", ["seat", "log", "bench"], ["FURNITURE", "DECORATION"], F, [["cyl", Vector3(0.45, 1.8, 0.45), Vector3(0, 0.22, 0), "wood", 0.0]], {"themes": ["camp", "house"], "roll": true})
	_prop("drying_rack", ["rack", "pelts"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(0.08, 1.8, 0.08), Vector3(-0.9, 0.9, 0), "wood"], ["box", Vector3(0.08, 1.8, 0.08), Vector3(0.9, 0.9, 0), "wood"], ["box", Vector3(1.9, 0.08, 0.08), Vector3(0, 1.7, 0), "wood"], ["box", Vector3(0.7, 0.9, 0.04), Vector3(-0.4, 1.2, 0), "straw"], ["box", Vector3(0.6, 0.8, 0.04), Vector3(0.45, 1.25, 0), "cloth"]], {"themes": ["camp"]})
	_prop("log_pile", ["logs", "storage"], ["DECORATION", "FURNITURE"], F, [["cyl", Vector3(0.4, 2.4, 0.4), Vector3(0, 0.2, -0.35), "wood", 0.0], ["cyl", Vector3(0.4, 2.4, 0.4), Vector3(0, 0.2, 0.05), "wood", 0.0], ["cyl", Vector3(0.4, 2.4, 0.4), Vector3(0, 0.55, -0.15), "wood", 0.0]], {"themes": ["camp", "house"], "roll": true})
	_prop("cart", ["cart"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(1.4, 0.5, 2.4), Vector3(0, 0.75, 0), "wood"], ["cyl", Vector3(1.0, 0.1, 1.0), Vector3(-0.75, 0.5, 0.4), "wood_dark", 0.0], ["cyl", Vector3(1.0, 0.1, 1.0), Vector3(0.75, 0.5, 0.4), "wood_dark", 0.0], ["box", Vector3(0.08, 0.08, 1.6), Vector3(0, 0.55, -1.9), "wood"]], {"themes": out, "cart": true})
	_prop("fence", ["fence"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(3.8, 0.08, 0.06), Vector3(0, 0.5, 0), "wood"], ["box", Vector3(3.8, 0.08, 0.06), Vector3(0, 0.95, 0), "wood"], ["box", Vector3(0.1, 1.1, 0.1), Vector3(-1.8, 0.55, 0), "wood_dark"], ["box", Vector3(0.1, 1.1, 0.1), Vector3(1.8, 0.55, 0), "wood_dark"]], {"themes": out})
	_prop("gravestone", ["grave", "gravestone"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(0.7, 1.0, 0.18), Vector3(0, 0.5, 0), "stone"], ["box", Vector3(0.9, 0.06, 1.8), Vector3(0, 0.03, -1.0), "moss_stone"]], {"themes": ["crypt", "ruin"], "weight": 3.0})
	_prop("grave_cross", ["grave", "gravestone"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(0.12, 1.2, 0.12), Vector3(0, 0.6, 0), "wood_dark"], ["box", Vector3(0.6, 0.12, 0.12), Vector3(0, 0.9, 0), "wood_dark"]], {"themes": ["crypt", "ruin"]})
	_prop("broken_cart", ["cart", "wreck"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(1.4, 0.5, 2.4), Vector3(0, 0.45, 0), "wood_dark", 0.3], ["cyl", Vector3(1.0, 0.1, 1.0), Vector3(0.9, 0.1, 0.6), "wood_dark", 0.0]], {"themes": out})
	_prop("banner_pole", ["banner", "pole"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(0.1, 4.0, 0.1), Vector3(0, 2.0, 0), "wood_dark"], ["box", Vector3(0.9, 1.6, 0.04), Vector3(0.5, 3.0, 0), "cloth_red"]], {"themes": ["camp", "fort", "ruin"]})
	_prop("weapon_heap", ["weapons", "remains", "battle"], ["DECORATION"], F, [["box", Vector3(1.1, 0.05, 0.08), Vector3(0, 0.03, 0), "iron", 0.5], ["box", Vector3(0.9, 0.05, 0.08), Vector3(0.1, 0.06, 0.2), "iron", -0.7], ["cyl", Vector3(0.6, 0.05, 0.6), Vector3(-0.4, 0.04, -0.2), "iron", 0.0]], {"themes": ["ruin", "fort", "camp"], "ghost": true})
	_prop("well", ["well", "water"], ["FURNITURE"], F, [["cyl", Vector3(1.6, 0.9, 1.6), Vector3(0, 0.45, 0), "stone"], ["box", Vector3(0.1, 1.8, 0.1), Vector3(-0.7, 1.4, 0), "wood_dark"], ["box", Vector3(0.1, 1.8, 0.1), Vector3(0.7, 1.4, 0), "wood_dark"], ["box", Vector3(1.6, 0.1, 0.1), Vector3(0, 2.3, 0), "wood_dark"], ["cyl", Vector3(1.3, 0.04, 1.3), Vector3(0, 0.8, 0), "water"]], {"themes": ["house", "ruin", "camp"]})
	_prop("crop_row", ["crops", "field"], ["DECORATION"], F, [["box", Vector3(0.6, 0.15, 3.6), Vector3(0, 0.07, 0), "ash"], ["box", Vector3(0.4, 0.6, 3.4), Vector3(0, 0.45, 0), "moss_stone"]], {"themes": ["house"], "ghost": true, "weight": 2.0})
	_prop("rowboat", ["boat"], ["DECORATION", "FURNITURE"], F, [["box", Vector3(1.3, 0.5, 3.2), Vector3(0, 0.25, 0), "wood_dark"], ["box", Vector3(1.1, 0.08, 0.3), Vector3(0, 0.45, 0.2), "wood"]], {"themes": ["house"]})
	# town dressing (Alpha 1.14.10)
	var town := ["house", "camp", "fort", "ruin"]
	_prop("lamp_post", ["lamp", "light", "street"], ["LIGHT", "DECORATION"], F, [["box", Vector3(0.14, 3.2, 0.14), Vector3(0, 1.6, 0), "iron"], ["box", Vector3(0.5, 0.08, 0.08), Vector3(0.22, 3.1, 0), "iron"], ["box", Vector3(0.24, 0.32, 0.24), Vector3(0.42, 2.85, 0), "glow"]],
		{"themes": town, "light": fire, "range": 9.0, "energy": 1.3, "light_at": Vector3(0.42, 2.7, 0)})
	_prop("market_stall", ["stall", "market"], ["FURNITURE"], F, [["box", Vector3(2.4, 0.9, 1.1), Vector3(0, 0.45, 0), "wood"], ["box", Vector3(2.6, 0.06, 1.6), Vector3(0, 2.3, 0.1), "cloth_red", 0.0], ["box", Vector3(0.1, 2.3, 0.1), Vector3(-1.2, 1.15, -0.6), "wood_dark"], ["box", Vector3(0.1, 2.3, 0.1), Vector3(1.2, 1.15, -0.6), "wood_dark"], ["box", Vector3(0.1, 2.3, 0.1), Vector3(-1.2, 1.15, 0.6), "wood_dark"], ["box", Vector3(0.1, 2.3, 0.1), Vector3(1.2, 1.15, 0.6), "wood_dark"], ["box", Vector3(0.5, 0.25, 0.4), Vector3(-0.6, 1.02, 0), "straw"], ["box", Vector3(0.4, 0.3, 0.4), Vector3(0.5, 1.05, 0.1), "cloth"]],
		{"themes": town})
	_prop("fountain", ["fountain", "water"], ["FURNITURE"], F, [["cyl", Vector3(4.0, 0.7, 4.0), Vector3(0, 0.35, 0), "stone"], ["cyl", Vector3(3.4, 0.06, 3.4), Vector3(0, 0.62, 0), "water"], ["cyl", Vector3(0.6, 1.8, 0.6), Vector3(0, 1.2, 0), "stone"], ["cyl", Vector3(1.4, 0.3, 1.4), Vector3(0, 2.1, 0), "stone"]], {"themes": town})
	_prop("flower_box", ["flowers", "garden"], ["DECORATION"], F, [["box", Vector3(1.2, 0.35, 0.4), Vector3(0, 0.17, 0), "wood_dark"], ["box", Vector3(1.1, 0.25, 0.3), Vector3(0, 0.45, 0), "cloth_red"], ["box", Vector3(0.6, 0.2, 0.25), Vector3(0.2, 0.55, 0), "moss_stone"]], {"themes": town, "ghost": true})
	_prop("stone_bench", ["bench", "seat", "street"], ["FURNITURE", "DECORATION"], F, [["box", Vector3(1.8, 0.12, 0.5), Vector3(0, 0.45, 0), "stone"], ["box", Vector3(0.3, 0.4, 0.45), Vector3(-0.7, 0.2, 0), "stone_dark"], ["box", Vector3(0.3, 0.4, 0.45), Vector3(0.7, 0.2, 0), "stone_dark"]], {"themes": town})
	_prop("street_tree", ["tree", "garden"], ["DECORATION"], F, [["cyl", Vector3(0.35, 3.0, 0.35), Vector3(0, 1.5, 0), "wood_dark"], ["box", Vector3(2.4, 2.2, 2.4), Vector3(0, 3.8, 0), "moss_stone", 0.3], ["box", Vector3(1.8, 1.6, 1.8), Vector3(0.3, 4.9, -0.2), "moss_stone", 0.8]], {"themes": town})
	_prop("hay_bale", ["hay", "storage"], ["DECORATION"], F, [["cyl", Vector3(1.2, 1.1, 1.2), Vector3(0, 0.55, 0), "straw", 0.0]], {"themes": town})


# ---------------------------------------------------------------- the pieces

func _new(file: String, kind: String, cells: Vector3i) -> ExteriorSite:
	var s := ExteriorSite.new()
	s.name = file.to_pascal_case()
	var k: Array = KINDS[kind]
	s.site_kind = kind
	s.themes = PackedStringArray([k[1]])
	s.map_icon = k[2]
	s.biomes = PackedStringArray(k[8])
	s.min_distance = float(k[10])
	s.cells = cells
	s.size_class = ExteriorSite.Size.SMALL if cells.x <= 4 else (ExteriorSite.Size.MEDIUM if cells.x <= 7 else (ExteriorSite.Size.LARGE if cells.x <= 10 else ExteriorSite.Size.HUGE))
	_site = s
	_n = 0
	return s


func _done(file: String) -> void:
	# a peaceful place gets spots for whoever might take it one day (empty until then: SiteChanges)
	if SiteChanges.TAKEABLE.has(_site.site_kind) and not _site.sockets().any(func(s: SpawnSocket) -> bool: return s.kind == S.ENEMY):
		var r := _site.bounds().size.x * 0.3
		for i in 3:
			_s(S.ENEMY, [], Vector3(cos(TAU * i / 3.0 + 0.5) * r, 0, sin(TAU * i / 3.0 + 0.5) * r), 0.0, 1.0)
		_s(S.BOSS, [], Vector3(0, 0, r * 0.5), PI)
	_save(_site, SITE_DIR + file + ".tscn")


# A box of the site (solid unless told)
func _b(size: Vector3, at: Vector3, mat: String, solid: bool = true, yaw: float = 0.0) -> Node3D:
	_n += 1
	return InteriorKit.box(_site, "Part%d" % _n, size, at, mat, _site, solid, yaw)


func _s(kind: int, tags: Array, at: Vector3, yaw: float = 0.0, chance: float = 1.0, count: int = 1) -> void:
	_socket(_site, kind, tags, at, yaw, chance, count)


func _link(kind: int, at: Vector3, yaw: float, label: String) -> void:
	var l := SiteLink.new()
	l.name = "Link"
	l.kind = kind as SiteLink.Kind
	l.label = label
	_site.add_child(l)
	l.owner = _site
	l.position = at
	l.rotation.y = yaw


# A wall from a to b (x, z) of a height, on the ground or at y
func _wall(a: Vector2, b: Vector2, h: float, mat: String, thick: float = 0.6, y: float = 0.0) -> void:
	var d := b - a
	var mid := (a + b) * 0.5
	_b(Vector3(d.length(), h, thick), Vector3(mid.x, y + h * 0.5, mid.y), mat, true, -atan2(d.y, d.x))


# A ring of stakes (a palisade) round the middle, with a gap facing -Z
func _palisade(r: float, gap: float = 0.5) -> void:
	var n := int(TAU * r / 0.55)
	for i in n:
		var a := TAU * i / n
		if absf(wrapf(a - PI * 1.5, -PI, PI)) < gap:
			continue
		_b(Vector3(0.45, 2.6 + (i % 3) * 0.2, 0.45), Vector3(cos(a) * r, 1.3, sin(a) * r), "wood", true, -a)


# A square tower of storeys, each LEVEL high, with ramps up the inside and a hatch at the top; the
# floors are open where the ramp comes through. Returns nothing; sockets go on each floor.
func _tower(at: Vector3, w: float, storeys: int, mat: String, door_side: float = -1.0, top_glow: bool = false) -> void:
	var hw := w * 0.5
	var t := 0.5
	for f in storeys:
		var y := at.y + f * L
		# walls (a door in the front on the ground floor)
		for side in 4:
			var along := side % 2 == 0
			var sgn := -1.0 if side < 2 else 1.0
			var c := at + (Vector3(0, y - at.y, sgn * (hw - t * 0.5)) if along else Vector3(sgn * (hw - t * 0.5), y - at.y, 0))
			if f == 0 and side == (0 if door_side < 0 else 2):
				var piece := (w - 1.8) * 0.5
				for k in [-1.0, 1.0]:
					var off := Vector3(k * (0.9 + piece * 0.5), 0, 0)
					_b(Vector3(piece, L, t), c + off + Vector3(0, L * 0.5, 0), mat)
				_b(Vector3(1.8, L - 2.6, t), c + Vector3(0, 2.6 + (L - 2.6) * 0.5, 0), mat)
			else:
				_b(Vector3(w, L, t) if along else Vector3(t, L, w), c + Vector3(0, L * 0.5, 0), mat)
			# a window slit on every side above the ground
			if f > 0:
				_b(Vector3(0.3, 1.0, t + 0.04) if along else Vector3(t + 0.04, 1.0, 0.3), c + Vector3(0, 2.2, 0), "stone_dark", false)
		# the floor above, open over the ramp
		var top := y + L
		_b(Vector3(w - 2.6, InteriorKit.SLAB, w), Vector3(at.x + 1.3, top - InteriorKit.SLAB * 0.5, at.z), "wood_floor" if f < storeys - 1 else mat)
		_b(Vector3(2.6, InteriorKit.SLAB, 2.2), Vector3(at.x - hw + 1.3, top - InteriorKit.SLAB * 0.5, at.z + hw - 1.1), "wood_floor" if f < storeys - 1 else mat)
		# the ramp up the west wall (steps for the eye, a walkable slope underneath)
		var holder := Node3D.new()
		_n += 1
		holder.name = "Stairs%d" % f
		_site.add_child(holder)
		holder.owner = _site
		holder.position = Vector3(at.x - hw + 1.3, y, 0)
		var z0 := at.z - hw + t + 0.4
		var z1 := at.z + hw - 2.2
		for i in 10:
			var sh := L * (i + 1) / 10.0
			InteriorKit.box(holder, "Step%d" % i, Vector3(2.0, sh, (z1 - z0) / 10.0), Vector3(0, sh * 0.5, z0 + (z1 - z0) * (i + 0.5) / 10.0), "wood", _site, false)
		_ramp(holder, _site, 2.0, z0, 0.0, z1, L, "", false)
	# battlements on the roof
	var roof := at.y + storeys * L
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var p := Vector3(clampf(cos(a) * hw * 1.4, -hw + 0.3, hw - 0.3), roof + 0.6, clampf(sin(a) * hw * 1.4, -hw + 0.3, hw - 0.3))
		_b(Vector3(0.8, 1.2, 0.8), at + Vector3(p.x, 0, p.z) + Vector3(0, p.y - at.y, 0), mat)
	if top_glow:
		_b(Vector3(1.2, 1.2, 1.2), at + Vector3(0, storeys * L + 1.0, 0), "glow", false)


# A small house shell (four walls, a door gap, a pitched roof unless roofless)
func _house(at: Vector3, w: float, d: float, mat: String, roofless: bool = false, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var h := 3.2
	var pts := [Vector2(-w, -d), Vector2(w, -d), Vector2(w, d), Vector2(-w, d)]
	for i in 4:
		var a: Vector2 = pts[i] * 0.5
		var b: Vector2 = pts[(i + 1) % 4] * 0.5
		var wa := basis * Vector3(a.x, 0, a.y) + at
		var wb := basis * Vector3(b.x, 0, b.y) + at
		if i == 0:  # the front: a door in the middle
			var mid := (wa + wb) * 0.5
			var dir := (wb - wa).normalized()
			_wall(Vector2(wa.x, wa.z), Vector2((mid - dir * 0.7).x, (mid - dir * 0.7).z), h - (1.2 if roofless else 0.0), mat, 0.4)
			_wall(Vector2((mid + dir * 0.7).x, (mid + dir * 0.7).z), Vector2(wb.x, wb.z), h - (0.8 if roofless else 0.0), mat, 0.4)
		else:
			_wall(Vector2(wa.x, wa.z), Vector2(wb.x, wb.z), h - (0.4 * i if roofless else 0.0), mat, 0.4)
	if not roofless:
		for s in [-1.0, 1.0]:
			_b(Vector3(w + 0.6, 0.15, d * 0.62), at + basis * Vector3(0, h + d * 0.18, s * d * 0.25), "wood_dark", false, yaw).rotate_object_local(Vector3.RIGHT, -s * 0.6)


# ---------------------------------------------------------------- the sites

func _sites() -> void:
	for v in 2:
		_bandit_camp(v)
		_hunters_camp(v)
		_watchtower(v)
		_ruined_keep(v)
		_farmstead(v)
		_graveyard(v)
		_shrine(v)
		_fort(v)
	_bandit_hold()
	_giant_camp(0)
	_giant_camp(1)
	_mage_tower()
	_lighthouse()
	_ruined_temple()
	_ruined_village(0)
	_ruined_village(1)
	_aqueduct(0)
	_aqueduct(1)
	_mill()
	_lumber_camp()
	_mine_entrance()
	_quarry()
	_stone_circle(0)
	_stone_circle(1)
	_battlefield(0)
	_battlefield(1)
	_monument(0)
	_monument(1)
	_shipwreck()
	_dock(false)
	_dock(true)
	_bridge()
	_ruined_bastion()
	_beast_den()
	_small_places()


func _bandit_camp(v: int) -> void:
	var file := "bandit_camp_" + "ab"[v]
	_new(file, "bandit_camp", Vector3i(8, 1, 8))
	_s(S.LIGHT, ["campfire"], Vector3.ZERO)
	var tents := 3 + v
	for i in tents:
		var a := TAU * i / tents + 0.4
		_s(S.FURNITURE, ["tent"], Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), -a + PI * 0.5)
		_s(S.FURNITURE, ["bedroll", "set"], Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), -a, 0.9)
		_s(S.ENEMY, ["sleeper"] if i % 2 == 0 else [], Vector3(cos(a) * 6.0, 0, sin(a) * 6.0), 0.0, 0.9)
	for i in 4:
		var a := TAU * i / 4.0
		_s(S.FURNITURE, ["log", "seat"], Vector3(cos(a) * 2.2, 0, sin(a) * 2.2), -a, 0.9)
	_s(S.CHEST, [], Vector3(0, 0, 12.5), PI)
	_s(S.BOSS, [], Vector3(2.5, 0, 3.0))
	_s(S.DECORATION, ["crate", "barrel", "sack"], Vector3(-11.0, 0, 6.0), 0.0, 0.9, 1)
	_s(S.DECORATION, ["banner", "pole"], Vector3(0, 0, -8.0), 0.0, 0.8)
	if v == 1:
		for i in 7:
			var a := PI * 0.2 + i * 0.35
			_b(Vector3(0.5, 2.2, 0.5), Vector3(cos(a) * 14.5, 1.1, sin(a) * 14.5), "wood", true, -a)
	_done(file)


func _bandit_hold() -> void:
	var file := "bandit_hold_a"
	_new(file, "bandit_hold", Vector3i(12, 2, 12))
	_palisade(20.0, 0.25)
	# the gate posts and a watch platform by the gate
	_b(Vector3(0.8, 4.0, 0.8), Vector3(-3.0, 2.0, -20.0), "wood_dark")
	_b(Vector3(0.8, 4.0, 0.8), Vector3(3.0, 2.0, -20.0), "wood_dark")
	_b(Vector3(3.0, 0.3, 3.0), Vector3(6.0, 3.0, -16.0), "wood")
	for k in 4:
		_b(Vector3(0.25, 3.0, 0.25), Vector3(6.0 + (k % 2) * 2.6 - 1.3, 1.5, -16.0 + (k / 2) * 2.6 - 1.3), "wood_dark")
	_s(S.ENEMY, ["guard", "archer"], Vector3(6.0, 3.2, -16.0), PI)
	for i in 6:
		var a := TAU * i / 6.0 + 0.5
		_s(S.FURNITURE, ["tent"], Vector3(cos(a) * 12.0, 0, sin(a) * 12.0), -a + PI * 0.5)
		_s(S.ENEMY, ["sleeper"] if i % 3 == 0 else [], Vector3(cos(a) * 8.0, 0, sin(a) * 8.0), 0.0, 0.85)
	for p: Vector3 in [Vector3(-5, 0, 2), Vector3(5, 0, -2)]:
		_s(S.LIGHT, ["campfire"], p)
	# the cage with a captive, and the chief's tent over the hatch to the hideout below
	_s(S.FURNITURE, ["cage"], Vector3(-12.0, 0, -8.0), 0.0)
	_s(S.NPC, ["captive"], Vector3(-12.0, 0, -8.0), 0.0, 1.0)
	_s(S.FURNITURE, ["tent"], Vector3(0, 0, 14.0), 0.0)
	_s(S.CHEST, [], Vector3(2.0, 0, 15.5), PI)
	_s(S.BOSS, [], Vector3(0, 0, 10.0), PI)
	_link(SiteLink.Kind.HATCH, Vector3(-2.0, 0.05, 15.0), PI, "the hideout")
	_b(Vector3(1.4, 0.1, 1.4), Vector3(-2.0, 0.05, 15.0), "wood_dark", false)
	_done(file)


func _hunters_camp(v: int) -> void:
	var file := "hunters_camp_" + "ab"[v]
	_new(file, "hunters_camp", Vector3i(6, 1, 6))
	_s(S.LIGHT, ["campfire"], Vector3.ZERO)
	for i in 2 + v:
		var a := TAU * i / (2 + v) + 1.0
		_s(S.FURNITURE, ["tent"], Vector3(cos(a) * 6.0, 0, sin(a) * 6.0), -a + PI * 0.5)
	_s(S.FURNITURE, ["rack", "pelts"], Vector3(-6.0, 0, -4.0), 0.4)
	_s(S.FURNITURE, ["rack", "pelts"], Vector3(5.5, 0, -5.0), -0.3)
	_s(S.FURNITURE, ["log", "seat"], Vector3(2.0, 0, 0.5), 0.3)
	_s(S.ENEMY, ["eating"], Vector3(-2.0, 0, 1.0), 0.0, 1.0)
	_s(S.ENEMY, [], Vector3(3.0, 0, -3.0), 0.0, 0.7)
	_s(S.CHEST, [], Vector3(0, 0, 7.5), PI, 0.8)
	_done(file)


func _giant_camp(v: int) -> void:
	var file := "giant_camp_" + "ab"[v]
	_new(file, "giant_camp", Vector3i(10, 2, 10))
	_b(Vector3(2.4, 0.4, 2.4), Vector3(0, 0.2, 0), "stone_dark")
	_b(Vector3(1.6, 0.8, 1.6), Vector3(0, 0.8, 0), "glow", false)
	for i in 5 + v * 2:  # great bones arched over the fire
		var a := TAU * i / (5.0 + v * 2)
		_b(Vector3(0.5, 6.0, 0.5), Vector3(cos(a) * 7.0, 2.6, sin(a) * 7.0), "bone", true, 0.0).rotate_object_local(Vector3(sin(a), 0, -cos(a)), 0.35)
	_b(Vector3(3.2, 1.8, 2.6), Vector3(12.0 - v * 24.0, 0.9, 6.0), "bone")  # a skull of something huge
	_s(S.LIGHT, ["campfire"], Vector3(0, 0, -3.5))
	_s(S.DECORATION, ["bones", "remains"], Vector3(-8.0, 0, 5.0))
	_s(S.DECORATION, ["bones", "remains"], Vector3(6.0, 0, -9.0))
	_s(S.BOSS, [], Vector3(-4.0, 0, 4.0))
	_s(S.ENEMY, [], Vector3(5.0, 0, 2.0), 0.0, 0.8)
	_s(S.CHEST, [], Vector3(-12.0, 0, -6.0), 0.5)
	_done(file)


func _watchtower(v: int) -> void:
	var file := "watchtower_" + "ab"[v]
	_new(file, "watchtower", Vector3i(4, 4, 4))
	_tower(Vector3.ZERO, 8.0, 3, "stone")
	for f in 3:
		_s(S.ENEMY, ["guard"] if f == 0 else ["archer"], Vector3(2.0, f * L + (0.0 if f == 0 else 0.0), 1.0), PI, 0.85)
		_s(S.FURNITURE, ["crate", "barrel", "rack"], Vector3(2.8, f * L, -2.8), 0.0, 0.8)
	_s(S.CHEST, [], Vector3(1.5, 3 * L, 1.5), PI)  # the loot at the top
	_s(S.ENEMY, ["archer"], Vector3(-1.5, 3 * L, -1.5), 0.0, 0.9)
	_s(S.LIGHT, ["brazier"], Vector3(2.0, 3 * L, -2.0), 0.0, 0.9)
	if v == 1:  # a trapdoor in the floor: the tower stands over an old crypt
		_link(SiteLink.Kind.TRAPDOOR, Vector3(2.0, 0.05, 2.0), PI, "the trapdoor")
		_b(Vector3(1.4, 0.1, 1.4), Vector3(2.0, 0.05, 2.0), "wood_dark", false)
	_s(S.LIGHT, ["campfire"], Vector3(0, 0, -7.0), 0.0, 0.7)
	_done(file)


func _mage_tower() -> void:
	var file := "mage_tower_a"
	_new(file, "mage_tower", Vector3i(4, 5, 4))
	_tower(Vector3.ZERO, 8.0, 4, "stone_dark", -1.0, true)
	var tags := [["bookshelf", "books"], ["altar"], ["crystal", "light"], ["table"]]
	for f in 4:
		_s(S.FURNITURE, tags[f], Vector3(2.4, f * L, -2.4), 0.0, 1.0)
		_s(S.ENEMY, [], Vector3(1.5, f * L, 1.0), PI, 0.8)
	_s(S.BOSS, [], Vector3(1.0, 4 * L, 0.0), PI)
	_s(S.CHEST, [], Vector3(-2.0, 4 * L, -2.0), 0.0)
	_link(SiteLink.Kind.TRAPDOOR, Vector3(2.0, 0.05, 2.0), PI, "the cellars")
	_done(file)


func _lighthouse() -> void:
	var file := "lighthouse_a"
	_new(file, "lighthouse", Vector3i(4, 5, 4))
	_tower(Vector3.ZERO, 7.0, 4, "plaster", -1.0, true)
	_s(S.ENEMY, [], Vector3(1.5, 0, 1.0), PI, 0.7)
	_s(S.ENEMY, [], Vector3(1.5, 2 * L, 1.0), PI, 0.7)
	_s(S.CHEST, [], Vector3(1.5, 4 * L, 1.5), PI)
	_s(S.DECORATION, ["barrel", "crate", "rope"], Vector3(-6.0, 0, -5.0))
	for f in 4:
		_s(S.FURNITURE, ["crate", "barrel", "shelf", "storage"], Vector3(2.2, f * L, -2.2), 0.0, 1.0)
	_s(S.LIGHT, ["brazier", "candle"], Vector3(-1.5, 4 * L, 1.5))
	_done(file)


func _ruined_keep(v: int) -> void:
	var file := "ruined_keep_" + "ab"[v]
	_new(file, "ruined_keep", Vector3i(10, 3, 10))
	var r := 13.0
	var h := [6.0, 3.5, 7.5, 2.0]
	for i in 4:
		var a := Vector2(-r, -r).rotated(PI * 0.5 * i)
		var b := Vector2(-r, -r).rotated(PI * 0.5 * (i + 1))
		if i == 0:  # the broken front, a gap in the middle
			_wall(a, a.lerp(b, 0.38), h[i], "moss_stone", 1.0)
			_wall(a.lerp(b, 0.62), b, h[i] * 0.5, "moss_stone", 1.0)
		else:
			_wall(a, a.lerp(b, 0.55 + 0.15 * v), h[i], "moss_stone", 1.0)
	# a fallen tower in a corner
	_b(Vector3(5.0, 9.0, 5.0), Vector3(r - 1.0, 4.5, r - 1.0), "stone")
	_b(Vector3(5.0, 2.0, 9.0), Vector3(r - 6.0, 1.0, r - 6.0), "moss_stone", true, 0.6)
	for p: Vector3 in [Vector3(-6, 0, 4), Vector3(5, 0, -6), Vector3(-9, 0, -8), Vector3(8, 0, 8)]:
		_s(S.DECORATION, ["rubble", "broken_pillar"], p, p.x, 0.9)
	for p: Vector3 in [Vector3(-4, 0, -4), Vector3(4, 0, 2), Vector3(-8, 0, 6)]:
		_s(S.ENEMY, [], p, 0.0, 0.85)
	_s(S.BOSS, [], Vector3(0, 0, 6.0), PI)
	_s(S.CHEST, [], Vector3(r - 3.0, 0, -r + 3.0), PI * 0.75)
	_link(SiteLink.Kind.DOOR if v == 0 else SiteLink.Kind.HATCH, Vector3(-r + 3.0, 0.05, r - 3.0), PI, "the undercroft")
	if v == 0:
		_b(Vector3(2.4, 3.0, 0.5), Vector3(-r + 3.0, 1.5, r - 2.4), "stone_dark")
	_done(file)


func _ruined_temple() -> void:
	var file := "ruined_temple_a"
	_new(file, "ruined_temple", Vector3i(8, 2, 8))
	_b(Vector3(14.0, 0.6, 18.0), Vector3(0, 0.3, 0), "stone")
	_b(Vector3(10.0, 0.4, 2.0), Vector3(0, 0.2, -10.0), "stone")  # the steps up
	for i in 6:
		for s in [-1.0, 1.0]:
			var tall := 5.0 if (i + int(s)) % 3 != 0 else 2.0
			_b(Vector3(1.0, tall, 1.0), Vector3(s * 5.5, 0.6 + tall * 0.5, -7.0 + i * 2.8), "stone")
	_s(S.FURNITURE, ["altar"], Vector3(0, 0.6, 6.5), 0.0)
	_s(S.FURNITURE, ["statue"], Vector3(-3.0, 0.6, 7.5), 0.0, 0.9)
	_s(S.FURNITURE, ["statue"], Vector3(3.0, 0.6, 7.5), 0.0, 0.9)
	_s(S.LOOT, [], Vector3(0, 1.6, 6.5), 0.0)
	_s(S.BOSS, [], Vector3(0, 0.6, 3.0), PI)
	_s(S.ENEMY, ["undead"], Vector3(-3.0, 0.6, -2.0), 0.0, 0.8, 2)
	_s(S.DECORATION, ["rubble"], Vector3(4.0, 0.6, -4.0), 1.0)
	_done(file)


func _ruined_village(v: int) -> void:
	var file := "ruined_village_" + "ab"[v]
	_new(file, "ruined_village", Vector3i(12, 1, 12))
	var spots := [Vector3(-12, 0, -10), Vector3(10, 0, -12), Vector3(-14, 0, 9), Vector3(12, 0, 10), Vector3(0, 0, 16)] if v == 0 else [Vector3(-10, 0, -14), Vector3(13, 0, -6), Vector3(-6, 0, 12), Vector3(9, 0, 13)]
	for i in spots.size():
		_house(spots[i], 7.0, 6.0, "plaster" if i % 2 == 0 else "stone", true, i * 0.9)
		_s(S.DECORATION, ["rubble", "bones"], spots[i] + Vector3(0.5, 0, 0.5), i, 0.8)
		_s(S.ENEMY, ["undead"], spots[i] + Vector3(-1.5, 0, 0), 0.0, 0.7)
	_s(S.FURNITURE, ["well"], Vector3.ZERO)
	_s(S.CHEST, [], Vector3(0, 0, 13.5), PI, 0.8)
	_s(S.DECORATION, ["cart", "wreck"], Vector3(5.0, 0, -2.0), 0.7)
	_done(file)


func _aqueduct(v: int) -> void:
	var file := "aqueduct_" + "ab"[v]
	_new(file, "aqueduct", Vector3i(12, 3, 4))
	for i in 7:
		var x := -21.0 + i * 7.0
		if i == 4 - v * 2:
			continue  # fallen
		_b(Vector3(1.6, 10.0, 2.4), Vector3(x, 5.0, 0), "stone")
		if i < 6 and i != 3:
			_b(Vector3(7.0, 1.6, 2.4), Vector3(x + 3.5, 10.8, 0), "stone")
	_b(Vector3(6.0, 1.6, 2.4), Vector3(8.0, 0.8, 2.0), "moss_stone", true, 0.4)
	_s(S.DECORATION, ["rubble"], Vector3(7.0, 0, -2.0), 0.3)
	_s(S.LOOT, [], Vector3(14.0, 0, 1.5), 0.0, 0.6)
	for p: Vector3 in [Vector3(-14, 0, 2), Vector3(-2, 0, -2.5), Vector3(19, 0, 2)]:
		_s(S.DECORATION, ["rubble", "broken_pillar"], p, p.x, 0.9)
	_done(file)


func _fort(v: int) -> void:
	var file := "fort_" + "ab"[v]
	_new(file, "fort", Vector3i(16, 4, 16))
	var r := 24.0
	for i in 4:
		var a := Vector2(-r, -r).rotated(PI * 0.5 * i)
		var b := Vector2(-r, -r).rotated(PI * 0.5 * (i + 1))
		if i == 0:  # the gatehouse in the front wall
			_wall(a, Vector2(-4.0, -r), 7.0, "stone", 1.6)
			_wall(Vector2(4.0, -r), b, 7.0, "stone", 1.6)
			_b(Vector3(8.0, 3.0, 4.0), Vector3(0, 7.5, -r), "stone")
			for s in [-1.0, 1.0]:
				_b(Vector3(3.0, 10.0, 4.0), Vector3(s * 5.5, 5.0, -r), "stone")
		else:
			_wall(a, b, 7.0, "stone", 1.6)
		# a walkway along the inside of each wall, and a slope up to it
		_n += 1
		var walk := InteriorKit.box(_site, "Walk%d" % _n, Vector3(r * 2.0, 0.3, 2.0), Vector3(0, 6.0, -r + 1.8), "wood_floor", _site)
		walk.rotation.y = PI * 0.5 * i
		walk.position = Vector3(0, 6.0, -r + 1.8).rotated(Vector3.UP, -PI * 0.5 * i)
		# corner towers
		var c := Vector3(a.x, 0, a.y)
		_b(Vector3(5.0, 10.0, 5.0), c + Vector3(0, 5.0, 0), "stone")
		_s(S.ENEMY, ["guard", "archer"], (Vector3(0, 6.2, -r + 1.8)).rotated(Vector3.UP, -PI * 0.5 * i) + Vector3(4.0, 0, 0).rotated(Vector3.UP, -PI * 0.5 * i), 0.0, 0.8)
	# the slope up onto the walls
	var holder := Node3D.new()
	holder.name = "WallStairs"
	_site.add_child(holder)
	holder.owner = _site
	holder.position = Vector3(r - 3.4, 0, 0)
	_ramp(holder, _site, 2.4, -14.0, 0.0, -r + 3.0, 6.0, "wood", true)
	# the keep in the back of the courtyard, with the way down
	_house(Vector3(0, 0, 12.0), 14.0, 10.0, "stone", false)
	_link(SiteLink.Kind.DOOR, Vector3(0, 0.05, 15.5), PI, "the keep's cellars")
	_b(Vector3(2.0, 3.0, 0.4), Vector3(0, 1.5, 16.8), "wood_dark", false)
	# the courtyard: a well, a training ground, the garrison
	_s(S.FURNITURE, ["well"], Vector3(-8.0, 0, -4.0))
	_s(S.DECORATION, ["dummy", "training"], Vector3(10.0, 0, -8.0))
	_s(S.DECORATION, ["dummy", "training"], Vector3(12.0, 0, -10.0))
	_s(S.FURNITURE, ["rack", "weapons"], Vector3(13.0, 0, -4.0), PI * 0.5)
	for p: Vector3 in [Vector3(-6, 0, -12), Vector3(6, 0, -14), Vector3(-12, 0, 4), Vector3(8, 0, 2), Vector3(0, 0, -4)]:
		_s(S.ENEMY, [] if v == 0 else ["guard"], p, 0.0, 0.85)
	_s(S.BOSS, [], Vector3(0, 0, 9.0), PI)
	_s(S.CHEST, [], Vector3(5.0, 0, 15.0), PI)
	_s(S.LIGHT, ["brazier"], Vector3(-3.0, 0, -18.0))
	_s(S.LIGHT, ["brazier"], Vector3(3.0, 0, -18.0))
	_done(file)


func _farmstead(v: int) -> void:
	var file := "farmstead_" + "ab"[v]
	_new(file, "farmstead", Vector3i(10, 2, 10))
	_house(Vector3(-6.0, 0, 6.0), 8.0, 6.0, "plaster")
	_house(Vector3(8.0, 0, 8.0), 9.0 + v * 2.0, 7.0, "wood")  # the barn
	for i in 6:
		_s(S.DECORATION, ["crops", "field"], Vector3(-12.0 + i * 1.6, 0, -10.0), 0.0, 1.0)
		_s(S.DECORATION, ["crops", "field"], Vector3(4.0 + i * 1.6, 0, -10.0), 0.0, 1.0 if v == 0 else 0.0)
	for i in 4:
		_s(S.DECORATION, ["fence"], Vector3(-18.0, 0, -12.0 + i * 4.0), PI * 0.5)
	_s(S.FURNITURE, ["well"], Vector3(0, 0, 1.0))
	_s(S.DECORATION, ["hay"], Vector3(12.0, 0, 2.0))
	_s(S.DECORATION, ["cart"], Vector3(2.0, 0, 6.0), 0.4)
	_s(S.DECORATION, ["barrel", "crate", "sack"], Vector3(-2.0, 0, 9.0))
	_s(S.CHEST, [], Vector3(-6.0, 0, 7.5), PI, 0.8)
	_done(file)


func _mill() -> void:
	var file := "mill_a"
	_new(file, "mill", Vector3i(6, 3, 6))
	_tower(Vector3.ZERO, 7.0, 2, "plaster")
	# the sails
	for i in 4:
		var sail := _b(Vector3(1.2, 9.0, 0.15), Vector3(0, 9.0, -3.8), "cloth", false)
		sail.rotation.z = PI * 0.5 * i + 0.3
		sail.position += Vector3(sin(sail.rotation.z), -cos(sail.rotation.z), 0) * -4.5
	_s(S.DECORATION, ["sack", "barrel"], Vector3(5.0, 0, -4.0))
	_s(S.DECORATION, ["sack"], Vector3(6.0, 0, -2.0))
	_s(S.DECORATION, ["cart"], Vector3(-6.0, 0, -6.0), 0.5)
	_done(file)


func _lumber_camp() -> void:
	var file := "lumber_camp_a"
	_new(file, "lumber_camp", Vector3i(8, 1, 8))
	_house(Vector3(8.0, 0, 8.0), 6.0, 5.0, "wood")
	for p: Vector3 in [Vector3(-8, 0, -6), Vector3(-4, 0, -10), Vector3(6, 0, -8), Vector3(-10, 0, 4)]:
		_s(S.DECORATION, ["logs", "storage"], p, p.z)
	for i in 6:
		_b(Vector3(0.9, 0.5, 0.9), Vector3(-12.0 + i * 4.5, 0.25, 12.0 - (i % 2) * 3.0), "wood")  # stumps
	_s(S.LIGHT, ["campfire"], Vector3(0, 0, 2.0))
	_s(S.DECORATION, ["cart"], Vector3(3.0, 0, -3.0), 1.2)
	_s(S.CHEST, [], Vector3(8.0, 0, 9.5), PI, 0.7)
	_done(file)


func _mine_entrance() -> void:
	var file := "mine_entrance_a"
	_new(file, "mine_entrance", Vector3i(8, 2, 8))
	# a rock face with a timbered mouth
	_b(Vector3(20.0, 9.0, 6.0), Vector3(0, 4.5, 10.0), "rock")
	_b(Vector3(0.5, 3.6, 0.5), Vector3(-1.8, 1.8, 6.8), "wood")
	_b(Vector3(0.5, 3.6, 0.5), Vector3(1.8, 1.8, 6.8), "wood")
	_b(Vector3(4.2, 0.5, 0.6), Vector3(0, 3.8, 6.8), "wood")
	_b(Vector3(3.1, 3.4, 0.2), Vector3(0, 1.7, 7.2), "rock_dark", false)
	_link(SiteLink.Kind.CAVE, Vector3(0, 0.05, 6.4), PI, "the mine")
	_s(S.DECORATION, ["rails"], Vector3(0, 0, 2.0))
	_s(S.FURNITURE, ["cart", "mine"], Vector3(2.5, 0, 0.0), 0.2)
	_s(S.DECORATION, ["tools", "pickaxes"], Vector3(-5.0, 0, 6.5), PI)
	_s(S.DECORATION, ["crate", "barrel"], Vector3(-6.0, 0, 3.0))
	_s(S.ENEMY, [], Vector3(-3.0, 0, -3.0), 0.0, 0.6)
	_s(S.LIGHT, ["campfire"], Vector3(5.0, 0, -4.0), 0.0, 0.8)
	_done(file)


func _quarry() -> void:
	var file := "quarry_a"
	_new(file, "quarry", Vector3i(10, 2, 10))
	for i in 4:  # cut terraces
		_b(Vector3(18.0 - i * 3.0, 1.2, 4.0), Vector3(0, 0.6 + i * 1.2, 6.0 + i * 3.0), "stone")
	for p: Vector3 in [Vector3(-8, 0, -4), Vector3(-5, 0, -8), Vector3(6, 0, -6)]:
		_b(Vector3(1.6, 1.0, 1.0), p + Vector3(0, 0.5, 0), "stone", true, p.x * 0.2)
	_b(Vector3(0.4, 7.0, 0.4), Vector3(9.0, 3.5, 0), "wood_dark")  # the crane
	_b(Vector3(6.0, 0.4, 0.4), Vector3(7.0, 7.0, 0), "wood_dark")
	_s(S.DECORATION, ["tools", "pickaxes"], Vector3(-10.0, 0, 2.0))
	_s(S.DECORATION, ["cart"], Vector3(3.0, 0, -8.0), 0.8)
	_s(S.CHEST, [], Vector3(-12.0, 0, -10.0), 0.0, 0.6)
	_done(file)


func _shrine(v: int) -> void:
	var file := "wayside_shrine_" + "ab"[v]
	_new(file, "wayside_shrine", Vector3i(4, 1, 4))
	_b(Vector3(4.0, 0.3, 4.0), Vector3(0, 0.15, 0), "stone")
	if v == 0:
		_b(Vector3(0.5, 3.0, 0.5), Vector3(-1.5, 1.5, 1.5), "stone")
		_b(Vector3(0.5, 3.0, 0.5), Vector3(1.5, 1.5, 1.5), "stone")
		_b(Vector3(4.0, 0.4, 1.6), Vector3(0, 3.2, 1.5), "wood_dark")
	_s(S.FURNITURE, ["altar"], Vector3(0, 0.3, 1.0), 0.0)
	_s(S.LIGHT, ["candle"], Vector3(-1.2, 0.3, -0.4))
	_s(S.LIGHT, ["candle"], Vector3(1.2, 0.3, -0.4))
	_marker(_site, "Blessing", Vector3(0, 0.3, -0.6), 0.0)
	_done(file)


func _stone_circle(v: int) -> void:
	var file := "stone_circle_" + "ab"[v]
	_new(file, "stone_circle", Vector3i(8, 2, 8))
	for i in 9 - v * 2:
		var a := TAU * i / (9.0 - v * 2)
		var tall := 3.0 + (i % 3) * 0.8
		_b(Vector3(1.2, tall, 0.7), Vector3(cos(a) * (10.0 - v * 2.5), tall * 0.5, sin(a) * (10.0 - v * 2.5)), "stone", true, -a)
	_b(Vector3(3.0, 0.6, 2.0), Vector3(0, 0.3, 0), "stone_dark")
	_s(S.DECORATION, ["ritual"], Vector3(0, 0, 0))
	for i in 4:
		_s(S.LIGHT, ["candle"], Vector3(cos(TAU * i / 4.0) * 2.2, 0, sin(TAU * i / 4.0) * 2.2), 0.0, 1.0)
	_s(S.DECORATION, ["bones", "remains"], Vector3(-5.0, 0, -4.0), 0.0, 0.9)
	_s(S.ENEMY, [], Vector3(4.0, 0, 3.0), 0.0, 0.7)
	_s(S.LOOT, [], Vector3(0, 0.6, 0), 0.0, 0.7)
	_done(file)


func _graveyard(v: int) -> void:
	var file := "graveyard_" + "ab"[v]
	_new(file, "graveyard", Vector3i(10, 2, 10))
	for i in 4:  # a low stone wall round it, open at the front
		var a := Vector2(-17, -17).rotated(PI * 0.5 * i)
		var b := Vector2(-17, -17).rotated(PI * 0.5 * (i + 1))
		if i == 0:
			_wall(a, Vector2(-2.0, -17), 1.1, "moss_stone", 0.5)
			_wall(Vector2(2.0, -17), b, 1.1, "moss_stone", 0.5)
		else:
			_wall(a, b, 1.1, "moss_stone", 0.5)
	for row in 4:
		for col in 6:
			_s(S.DECORATION, ["gravestone"], Vector3(-12.5 + col * 5.0, 0, -11.0 + row * 5.0), 0.0, 0.85)
	# the mausoleum at the back, its door down to the barrow
	_house(Vector3(0, 0, 12.0), 7.0, 6.0, "stone_dark", false)
	_link(SiteLink.Kind.DOOR, Vector3(0, 0.05, 9.4), PI, "the mausoleum")
	for p: Vector3 in [Vector3(-8, 0, -4), Vector3(9, 0, 3)]:
		_s(S.ENEMY, ["undead"], p, 0.0, 0.7 + v * 0.2)
	_s(S.BOSS, [], Vector3(0, 0, 7.0), PI, 0.7)
	_s(S.LIGHT, ["candle", "brazier"], Vector3(-3.0, 0, 8.0))
	_done(file)


func _battlefield(v: int) -> void:
	var file := "battlefield_" + "ab"[v]
	_new(file, "battlefield", Vector3i(14, 1, 14))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1414 + v * 77
	for i in 18:
		var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24))
		_s(S.DECORATION, ["weapons", "battle"] if i % 2 == 0 else ["bones", "remains"], p, rng.randf() * TAU, 0.9)
	for i in 4:
		_s(S.DECORATION, ["banner", "pole"], Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), rng.randf() * TAU, 0.9)
	_s(S.DECORATION, ["cart", "wreck"], Vector3(6, 0, -4), 2.0)
	for i in 5:
		_s(S.ENEMY, ["undead"], Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-16, 16)), 0.0, 0.7)
	_s(S.BOSS, [], Vector3(0, 0, 4.0), 0.0, 0.8)
	_s(S.LOOT, [], Vector3(-3.0, 0, 6.0), 0.0, 0.8)
	_done(file)


func _monument(v: int) -> void:
	var file := "monument_" + "ab"[v]
	_new(file, "monument", Vector3i(4, 3, 4))
	_b(Vector3(7.0, 0.6, 7.0), Vector3(0, 0.3, 0), "stone")
	_b(Vector3(5.0, 0.6, 5.0), Vector3(0, 0.9, 0), "stone")
	_b(Vector3(2.4, 2.4, 2.4), Vector3(0, 2.4, 0), "stone_dark")
	if v == 0:  # a figure with its arms out
		_b(Vector3(1.0, 4.0, 0.8), Vector3(0, 5.6, 0), "stone")
		_b(Vector3(2.2, 0.5, 0.5), Vector3(0, 6.6, 0), "stone")
		_b(Vector3(0.7, 0.8, 0.7), Vector3(0, 8.0, 0), "stone")
	else:  # an obelisk
		_b(Vector3(1.2, 9.0, 1.2), Vector3(0, 8.1, 0), "stone_dark")
		_b(Vector3(0.8, 1.0, 0.8), Vector3(0, 13.1, 0), "stone_dark")
	_marker(_site, "Inscription", Vector3(0, 1.2, -2.5), PI)
	_s(S.LIGHT, ["candle"], Vector3(-1.6, 1.2, -1.9))
	_s(S.LIGHT, ["candle"], Vector3(1.6, 1.2, -1.9))
	_s(S.DECORATION, ["bucket", "crate"], Vector3(3.0, 0, -3.2), 0.0, 0.7)
	_s(S.LOOT, [], Vector3(0, 1.2, -1.9), 0.0, 0.5)
	_done(file)


func _shipwreck() -> void:
	var file := "shipwreck_a"
	_new(file, "shipwreck", Vector3i(8, 2, 8))
	var hull := _b(Vector3(6.0, 4.0, 22.0), Vector3(0, 1.2, 0), "wood_dark", true, 0.3)
	hull.rotation.z = 0.35
	var mast := _b(Vector3(0.5, 12.0, 0.5), Vector3(-3.0, 5.0, -2.0), "wood", true)  # the broken mast
	mast.rotation.z = 0.9
	_s(S.DECORATION, ["crate", "barrel"], Vector3(5.0, 0, 4.0))
	_s(S.DECORATION, ["crate", "barrel"], Vector3(6.0, 0, -6.0))
	_s(S.DECORATION, ["rope"], Vector3(-6.0, 0, 8.0))
	_s(S.CHEST, [], Vector3(4.5, 0, -1.0), 0.6)
	_s(S.ENEMY, [], Vector3(-4.0, 0, -9.0), 0.0, 1.0, 2)
	_s(S.BOSS, [], Vector3(5.0, 0, 9.0), PI, 0.6)
	_done(file)


func _dock(ferry: bool) -> void:
	var file := "ferry_a" if ferry else "dock_a"
	_new(file, "ferry" if ferry else "dock", Vector3i(6, 1, 8))
	_b(Vector3(3.0, 0.3, 16.0), Vector3(0, 0.6, -6.0), "wood")  # the pier
	for i in 5:
		for s in [-1.0, 1.0]:
			_b(Vector3(0.3, 2.4, 0.3), Vector3(s * 1.3, -0.4, -13.0 + i * 3.5), "wood_dark")
	_s(S.FURNITURE, ["boat"], Vector3(3.2, 0, -10.0), 0.1)
	_s(S.DECORATION, ["crate", "barrel"], Vector3(0, 0.75, -2.0))
	_s(S.DECORATION, ["rope"], Vector3(0.6, 0.75, -11.0))
	_house(Vector3(-6.0, 0, 8.0), 5.0, 4.0, "wood")
	if ferry:
		_b(Vector3(4.0, 0.3, 6.0), Vector3(4.5, 0.2, -16.0), "wood")  # the raft
		_marker(_site, "Ferryman", Vector3(-1.0, 0.75, -1.0), PI)
	_s(S.CHEST, [], Vector3(-6.0, 0, 9.5), PI, 0.6)
	_done(file)


func _bridge() -> void:
	var file := "bridge_a"
	_new(file, "bridge", Vector3i(4, 2, 10))
	_b(Vector3(4.0, 0.6, 30.0), Vector3(0, 3.0, 0), "stone")  # the deck
	for s in [-1.0, 1.0]:
		_b(Vector3(0.4, 0.9, 30.0), Vector3(s * 1.8, 3.75, 0), "moss_stone")
	for z in [-9.0, 0.0, 9.0]:
		_b(Vector3(3.6, 3.0, 2.0), Vector3(0, 1.2, z), "stone")
	# slopes up at each end
	for e in [-1.0, 1.0]:
		var holder := Node3D.new()
		_n += 1
		holder.name = "Approach%d" % _n
		_site.add_child(holder)
		holder.owner = _site
		_ramp(holder, _site, 4.0, e * 19.5, 0.0, e * 15.0, 3.3, "stone", true)
	_s(S.LOOT, [], Vector3(0.5, 3.3, 3.0), 0.0, 0.5)
	for e in [-1.0, 1.0]:
		_s(S.LIGHT, ["candle", "torch", "brazier"], Vector3(1.4, 3.3, e * 13.5), 0.0, 1.0)
		_s(S.DECORATION, ["rubble", "broken_pillar"], Vector3(-3.5, 0, e * 6.0), e, 0.9)
	_done(file)




# A ruined bastion: terraces climbing to a broken gate tower, joined by slopes and broken stairs, with a
# gap to jump near the top and the way down into its vaults from the highest ledge
func _ruined_bastion() -> void:
	var file := "ruined_bastion_a"
	_new(file, "ruined_bastion", Vector3i(10, 4, 10))
	var levels := [[Vector3(-8, 0, 8), Vector2(14, 10), 3.0], [Vector3(8, 0, 6), Vector2(12, 10), 6.0], [Vector3(4, 0, -9), Vector2(14, 8), 9.5], [Vector3(-10, 0, -8), Vector2(8, 8), 13.0]]
	for i in levels.size():
		var at: Vector3 = levels[i][0]
		var size: Vector2 = levels[i][1]
		var h: float = levels[i][2]
		_b(Vector3(size.x, h, size.y), at + Vector3(0, h * 0.5, 0), "moss_stone" if i % 2 == 0 else "stone")
		_s(S.ENEMY, ["guard"] if i == 0 else ([] if i < 3 else ["archer"]), at + Vector3(1.0, h, 0.5), 0.0, 0.85)
		_s(S.DECORATION, ["rubble", "broken_pillar"], at + Vector3(-size.x * 0.3, h, size.y * 0.25), i, 0.8)
	# slopes from the ground to the first terrace and from each terrace to the next (broken stairs)
	var joins := [[Vector3(-8, 0, -2.5), Vector3(-8, 3.0, 3.0)], [Vector3(-1.0, 3.0, 8), Vector3(2.0, 6.0, 8)], [Vector3(8, 6.0, 1.0), Vector3(8, 9.5, -5.0)]]
	for j in joins.size():
		var a: Vector3 = joins[j][0]
		var b: Vector3 = joins[j][1]
		var holder := Node3D.new()
		_n += 1
		holder.name = "Climb%d" % j
		_site.add_child(holder)
		holder.owner = _site
		var flat := Vector2(b.x - a.x, b.z - a.z)
		holder.position = Vector3(a.x, 0, a.z)
		holder.rotation.y = atan2(-flat.x, -flat.y) + PI
		_ramp(holder, _site, 2.6, 0.0, a.y, flat.length(), b.y, "stone", true)
	# the gap: the top ledge stands apart, a jump from the third terrace (a fallen block to land on)
	_b(Vector3(2.0, 11.0, 2.0), Vector3(-4.0, 5.5, -8.5), "stone")
	_s(S.CHEST, [], Vector3(-11.5, 13.0, -9.5), 0.0)
	_s(S.BOSS, [], Vector3(-9.0, 13.0, -7.0), PI)
	_link(SiteLink.Kind.HATCH, Vector3(-8.0, 13.05, -10.0), PI, "the vaults")
	_b(Vector3(1.4, 0.1, 1.4), Vector3(-8.0, 13.05, -10.0), "wood_dark", false)
	_done(file)


# A beast's den: a bowl of rock with one way in, bones everywhere, and the thing that lives there
# (the arena: rock walls all round, so the fight is in the bowl)
func _beast_den() -> void:
	var file := "beast_den_a"
	_new(file, "beast_den", Vector3i(10, 2, 10))
	var n := 22
	for i in n:
		var a := TAU * i / n
		if absf(wrapf(a - PI * 1.5, -PI, PI)) < 0.32:
			continue  # the way in
		var tall := 5.0 + (i % 4) * 1.2
		_b(Vector3(5.0, tall, 3.0), Vector3(cos(a) * 17.0, tall * 0.5 - 0.5, sin(a) * 17.0), "rock" if i % 2 == 0 else "rock_dark", true, -a + PI * 0.5)
	for i in 8:
		var a := TAU * i / 8.0 + 0.3
		_s(S.DECORATION, ["bones", "remains"], Vector3(cos(a) * (6.0 + i % 3 * 3.0), 0, sin(a) * (6.0 + i % 3 * 3.0)), a, 0.9)
	_s(S.BOSS, [], Vector3(0, 0, 4.0), PI)
	_s(S.ENEMY, [], Vector3(-6.0, 0, -4.0), 0.0, 0.8)
	_s(S.ENEMY, [], Vector3(6.0, 0, -2.0), 0.0, 0.8)
	_s(S.LOOT, [], Vector3(3.0, 0, 10.0), 0.0, 1.0)
	_s(S.DECORATION, ["rock", "boulder"], Vector3(-9.0, 0, 8.0), 0.4, 0.9)
	_marker(_site, "Arena", Vector3.ZERO, 0.0)
	_done(file)



# Little stories between the big places
func _small_places() -> void:
	for v in 2:
		var file := "roadside_camp_" + "ab"[v]
		_new(file, "roadside_camp", Vector3i(2, 1, 2))
		_s(S.LIGHT, ["campfire"], Vector3.ZERO)
		_s(S.FURNITURE, ["bedroll", "set"], Vector3(1.8, 0, 1.0 - v * 2.0), 0.6)
		_s(S.FURNITURE, ["log", "seat"], Vector3(-1.6, 0, 0.4), 0.4)
		_s(S.LOOT, ["pack"], Vector3(2.4, 0, -1.4 + v * 2.8), 0.0, 0.8)
		_s(S.ENEMY, [], Vector3(-1.0, 0, -1.6), 0.0, 0.5)
		_done(file)
	for v in 2:
		var file := "wrecked_cart_" + "ab"[v]
		_new(file, "wrecked_cart", Vector3i(2, 1, 2))
		_s(S.DECORATION, ["cart", "wreck"], Vector3.ZERO, 0.4 + v)
		_s(S.DECORATION, ["crate", "barrel", "sack"], Vector3(2.0, 0, 1.0), 0.3)
		_s(S.DECORATION, ["crate", "barrel", "sack"], Vector3(-1.8, 0, -1.2), 1.1, 0.8)
		_s(S.DECORATION, ["bones", "remains"], Vector3(1.2, 0, -2.0), 0.0, 0.6)
		_s(S.LOOT, [], Vector3(-0.8, 0, 1.8), 0.0, 0.9)
		for i in 2:
			_s(S.ENEMY, ["ambush"], Vector3(-3.0 + i * 6.0, 0, 3.0), PI, 0.55)
		_done(file)
	var file := "dead_traveller_a"
	_new(file, "dead_traveller", Vector3i(1, 1, 1))
	_s(S.DECORATION, ["bones", "remains"], Vector3.ZERO, 0.3)
	_s(S.LOOT, [], Vector3(0.8, 0, 0.4), 0.0, 1.0)
	_marker(_site, "Note", Vector3(-0.6, 0.05, 0.3), 0.4)
	_done(file)
	file = "lost_pack_a"
	_new(file, "lost_pack", Vector3i(1, 1, 1))
	_s(S.LOOT, ["pack"], Vector3.ZERO, 0.0, 1.0)
	_s(S.DECORATION, ["bucket", "rope"], Vector3(0.9, 0, 0.6), 0.0, 0.7)
	_done(file)
	file = "fishing_spot_a"
	_new(file, "fishing_spot", Vector3i(2, 1, 2))
	_b(Vector3(1.6, 0.2, 5.0), Vector3(0, 0.3, -2.5), "wood")
	for z in [-1.0, -4.5]:
		_b(Vector3(0.2, 1.4, 0.2), Vector3(0.7, -0.2, z), "wood_dark")
	_s(S.DECORATION, ["bucket"], Vector3(0.3, 0.4, -4.0))
	_s(S.FURNITURE, ["boat"], Vector3(2.0, 0, -3.0), 0.2, 0.6)
	_s(S.LOOT, [], Vector3(-0.5, 0.4, -1.5), 0.0, 0.6)
	_done(file)
	for v in 2:
		file = "herb_patch_" + "ab"[v]
		_new(file, "herb_patch", Vector3i(2, 1, 2))
		for i in 5 + v:
			var a := TAU * i / (5.0 + v)
			_marker(_site, "Herb%d" % i, Vector3(cos(a) * (1.4 + (i % 2) * 1.2), 0, sin(a) * (1.4 + (i % 2) * 1.2)), a)
		_s(S.DECORATION, ["rock", "boulder"], Vector3(0.3, 0, 0.2), 0.5, 0.5)
		_done(file)
	file = "ore_outcrop_a"
	_new(file, "ore_outcrop", Vector3i(2, 1, 2))
	_b(Vector3(3.0, 1.8, 2.4), Vector3(0, 0.7, 0.8), "rock", true, 0.4)
	_b(Vector3(1.8, 1.2, 1.6), Vector3(1.6, 0.5, -0.6), "rock_dark", true, 1.1)
	for i in 3:
		_marker(_site, "Ore%d" % i, Vector3(-1.8 + i * 1.8, 0, -1.6), 0.0)
	_s(S.DECORATION, ["tools", "pickaxes"], Vector3(-2.2, 0, 1.6), PI, 0.5)
	_done(file)
	file = "nest_a"
	_new(file, "nest", Vector3i(2, 1, 2))
	_b(Vector3(3.2, 0.5, 3.2), Vector3(0, 0.25, 0), "straw", false)
	for i in 3:
		_s(S.DECORATION, ["bones", "remains"], Vector3(cos(i * 2.1) * 2.4, 0, sin(i * 2.1) * 2.4), i, 0.9)
	_s(S.LOOT, ["eggs"], Vector3(0, 0.5, 0), 0.0, 1.0)
	_s(S.ENEMY, [], Vector3(2.0, 0, 1.0), 0.0, 0.9, 2)
	_done(file)
	# a wayside rest: a roof over a hearth and tables, straw beds, the keeper
	file = "wayside_inn_a"
	_new(file, "wayside_inn", Vector3i(6, 1, 6))
	_house(Vector3(0, 0, 2.0), 12.0, 9.0, "wood")
	_s(S.FURNITURE, ["hearth"], Vector3(0, 0, 6.05), 0.0, 1.0)
	_s(S.FURNITURE, ["table"], Vector3(-2.5, 0, 0.5), 0.0, 1.0)
	_s(S.FURNITURE, ["bench", "set"], Vector3(-2.5, 0, -0.3), 0.0, 1.0)
	_s(S.FURNITURE, ["table"], Vector3(2.5, 0, 0.5), 0.0, 1.0)
	_s(S.FURNITURE, ["bench", "set"], Vector3(2.5, 0, -0.3), 0.0, 1.0)
	for i in 3:
		_s(S.FURNITURE, ["bedroll", "hay"], Vector3(-4.6 + i * 2.0, 0, 4.6), 0.0, 1.0)
	_s(S.DECORATION, ["barrel", "crate"], Vector3(5.0, 0, 5.0))
	_s(S.DECORATION, ["cart"], Vector3(8.5, 0, -6.0), 0.4)
	_marker(_site, "Keeper", Vector3(1.0, 0, 3.5), PI)
	_done(file)

# ---------------------------------------------------------------- kinds and biomes

func _kinds() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(KIND_DIR))
	var scenes := DirAccess.get_files_at(ProjectSettings.globalize_path(SITE_DIR))
	for kind: String in KINDS:
		var path := KIND_DIR + kind + ".tres"
		if ResourceLoader.exists(path) and not force:
			continue
		var k: Array = KINDS[kind]
		var d := SitePOIData.new()
		d.id = StringName("site_" + kind)
		d.display_name = k[0]
		d.enter_name = k[0]
		d.footprint_radius = float(k[6])
		d.flatten_radius = float(k[7])
		d.max_slope_deg = 12.0 if float(k[7]) > 0.0 else 20.0
		d.map_icon = k[2]
		d.prefer = String(k[11])
		d.min_same_distance = float(k[10])
		d.path_to_road = float(k[12])
		d.discoverable = not SMALL.has(kind)
		d.map_color = {"camp": Color(0.8, 0.45, 0.3), "tower": Color(0.7, 0.7, 0.75), "ruin": Color(0.6, 0.65, 0.5), "fort": Color(0.75, 0.6, 0.5),
			"farm": Color(0.85, 0.8, 0.4), "mill": Color(0.85, 0.8, 0.5), "mine": Color(0.55, 0.45, 0.35), "shrine": Color(0.7, 0.8, 1.0),
			"stones": Color(0.65, 0.65, 0.7), "grave": Color(0.5, 0.55, 0.6), "battle": Color(0.7, 0.4, 0.35), "wreck": Color(0.5, 0.45, 0.4),
			"dock": Color(0.5, 0.6, 0.7), "bridge": Color(0.6, 0.6, 0.6), "lighthouse": Color(1.0, 0.9, 0.6)}.get(k[2], Color.WHITE)
		if String(k[3]) != "":
			d.occupants = load(SPAWNS + k[3] + ".tres") as SpawnTable
		if String(k[5]) != "":
			d.dungeon = load(DUNGEONS + k[5] + ".tres") as DungeonData
		var list: Array[PackedScene] = []
		for f in scenes:
			if f.ends_with(".tscn") and f.get_basename().trim_suffix("_" + f.get_basename().get_slice("_", f.get_basename().get_slice_count("_") - 1)) == kind:
				list.append(load(SITE_DIR + f) as PackedScene)
		d.sites = list
		ResourceSaver.save(d, path)
		print("build_sites: %s (%d versions)" % [kind, list.size()])


# Each biome's Poi Rules get the site kinds that suit it (kept if it has them already)
func _biomes() -> void:
	for f in DirAccess.get_files_at("res://data/world/"):
		if not f.ends_with(".tres"):
			continue
		var path := "res://data/world/" + f
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		var biome := res as BiomeData
		if biome == null:
			continue
		var key := f.get_basename()
		var have := {}
		var added := 0
		for r in biome.poi_rules:
			if r != null and r.poi != null:
				have[r.poi.resource_path] = true
				var kk := r.poi.resource_path.get_file().get_basename()
				if r.poi.resource_path.begins_with(KIND_DIR) and KINDS.has(kk) and not is_equal_approx(r.count_max, float(KINDS[kk][9]) * _density(kk) * 1.3):
					r.count_min = float(KINDS[kk][9]) * _density(kk) * 0.7
					r.count_max = float(KINDS[kk][9]) * _density(kk) * 1.3
					added += 1
		for kind: String in KINDS:
			var k: Array = KINDS[kind]
			var lands: Array = k[8]
			if not lands.is_empty() and not lands.has(key):
				continue
			var kp := KIND_DIR + kind + ".tres"
			if have.has(kp):
				continue
			var rule := POIRule.new()
			rule.poi = load(kp) as POIData
			rule.count_mode = POIRule.CountMode.PER_SQUARE_KM
			rule.count_min = float(k[9]) * _density(kind) * 0.7
			rule.count_max = float(k[9]) * _density(kind) * 1.3
			rule.extra_spacing = 40.0
			rule.border_margin = 40.0
			biome.poi_rules.append(rule)
			added += 1
		if added > 0:
			ResourceSaver.save(biome, path)
			print("build_sites: %s gets %d site kinds" % [key, added])


# The big places come three times as thick as before; the small things keep their own counts
func _density(kind: String) -> float:
	return 1.0 if SMALL.has(kind) else DENSITY
