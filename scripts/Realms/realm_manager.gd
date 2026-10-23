class_name RealmManager
extends Node
## The instanced realms: open lands apart from the main world (like the Soul Cairn), reached by a
## gate, a ship or a ritual. Created by WorldManager.
##
## Each realm has a gate somewhere in the world (an arch, a ship's gangway, a crack in the
## ground). It stays sealed until a quest sends you there, then stays open. Going through works
## like a dungeon door: DungeonManager builds the realm far below the world (RealmBuilder) with
## its own sky, light and fog, and leaving puts you back at the gate. Inside: a hub with people,
## several guarded sites with treasure, and the realm's heart, whose master you must defeat
## (a "realm" quest step). Fall off the edge and you are put back at the hub.
##
## Saved in WorldState: "realm/<id>" (open), and the kills of its creatures ("kill/realm/...").

const ENTRANCE_PREFIX := "realm:"
const GATE_NEAR := 220.0
## How far below the world realms are built (below interiors and dungeons)
const REALM_Y := -9000.0

## id -> realm. look: ground, sky, fog, ambient, sun (light colour, or Color.BLACK for none),
## relief (meters of hills), islands (sea between land). foes: bodies of its creatures.
const REALMS := {
	"R1": {"name": "The Shattered Isles", "levels": [22, 45], "half": 900.0, "islands": true, "relief": 18.0,
		"ground": Color(0.76, 0.70, 0.52), "sky": Color(0.45, 0.62, 0.78), "fog": Color(0.55, 0.68, 0.78), "ambient": Color(0.45, 0.48, 0.52), "sun": Color(1.0, 0.95, 0.85),
		"foes": ["smuggler", "cutthroat", "raider"], "boss": ["smuggler_chief", "The Drowned King's Champion"],
		"hub": "Port Wrack", "npcs": ["Captain Maura Vey", "Shipwright Odo", "Port Wrack Fence"],
		"sites": ["Gull Rock Smugglers' Cave", "The Tower of Ondrel", "Saltbone Atoll", "The Tide Temple", "Wreck Isle"], "heart": "The Tidecrown",
		"gate": {"near": "Saltmere", "dist": 60.0, "ang": 90.0, "kind": "ship"}},
	"R2": {"name": "The Thornheart Dreamwood", "levels": [18, 30], "half": 650.0, "relief": 25.0,
		"ground": Color(0.20, 0.40, 0.25), "sky": Color(0.25, 0.20, 0.40), "fog": Color(0.40, 0.30, 0.55), "ambient": Color(0.40, 0.35, 0.55), "sun": Color(0.75, 0.65, 1.0),
		"foes": ["wolf", "werewolf", "cave_dweller"], "boss": ["vampire", "Lady Nyssa Varn"],
		"hub": "The Glade of Sleepers", "npcs": ["The Talking Fox", "A Sleeping Woodborn Child"],
		"sites": ["The Root Labyrinth", "The Hollow Moon Tree", "The Weeping Barrow"], "heart": "The Briar Throne",
		"gate": {"near": "Mossgate", "dist": 55.0, "ang": 30.0, "kind": "portal"}},
	"R3": {"name": "Kar-Aurel, the Buried City", "levels": [30, 50], "half": 750.0, "relief": 6.0,
		"ground": Color(0.70, 0.58, 0.38), "sky": Color(0.12, 0.10, 0.08), "fog": Color(0.35, 0.28, 0.18), "ambient": Color(0.45, 0.38, 0.28), "sun": Color(1.0, 0.85, 0.55),
		"foes": ["vault_guardian", "skeleton_knight", "dune_stalker"], "boss": ["vault_sentinel", "The Last Emperor's Sentinel"],
		"hub": "The Diggers' Camp", "npcs": ["Expedition Leader Ysolde Dask", "Digger Omar"],
		"sites": ["The Imperial Archive", "The Legion Barracks", "The Catacombs of Aurel", "The Emperor's Bath"], "heart": "The Sun Vault",
		"gate": {"near": "desert", "dist": 900.0, "ang": 200.0, "kind": "portal"}},
	"R4": {"name": "The Barrowdeep", "levels": [34, 55], "half": 700.0, "relief": 20.0,
		"ground": Color(0.30, 0.32, 0.34), "sky": Color(0.04, 0.06, 0.10), "fog": Color(0.20, 0.35, 0.55), "ambient": Color(0.25, 0.35, 0.55), "sun": Color(0.45, 0.65, 1.0),
		"foes": ["skeleton", "barrow_wight", "crypt_warden"], "boss": ["wight_lord", "The Stone King"],
		"hub": "Cairn-Under", "npcs": ["The Dead Mother", "Cairn-Under Bone-Merchant"],
		"sites": ["The Bone Mines", "The Drowned Ossuary", "Ghaur's Cocoon"], "heart": "The Stone King's Hall",
		"gate": {"near": "Cragmoor", "dist": 50.0, "ang": 300.0, "kind": "crack"}},
	"R5": {"name": "The Gloaming", "levels": [28, 50], "half": 750.0, "relief": 10.0,
		"ground": Color(0.42, 0.42, 0.44), "sky": Color(0.30, 0.30, 0.34), "fog": Color(0.45, 0.45, 0.50), "ambient": Color(0.45, 0.45, 0.50), "sun": Color.BLACK,
		"foes": ["vampire", "ice_wraith", "skeleton"], "boss": ["vampire", "The Gloaming's Warden"],
		"hub": "The Lantern Road", "npcs": ["Old Weir the Ferryman"],
		"sites": ["The Velvet Court's Drowned Sanctum", "The Hollow Kin Bone-Fort", "The Choir's Black Chapel", "The Prison of Souls"], "heart": "The Tomb of Vaelith",
		"gate": {"near": "Blackfen", "dist": 60.0, "ang": 150.0, "kind": "portal"}},
	"R6": {"name": "The Hunting Grounds", "levels": [30, 45], "half": 800.0, "relief": 30.0,
		"ground": Color(0.22, 0.34, 0.18), "sky": Color(0.30, 0.08, 0.06), "fog": Color(0.40, 0.18, 0.12), "ambient": Color(0.50, 0.32, 0.28), "sun": Color(1.0, 0.45, 0.35),
		"foes": ["wolf", "frost_bear", "werewolf"], "boss": ["werewolf", "The Moon's Champion"],
		"hub": "The Feast Hall of the Antlered", "npcs": ["The Dead Lodge Master", "Greyfang Ancestor"],
		"sites": ["The Den of the First Wolf", "The Stag Lord's Ring", "The Thorn Maze"], "heart": "The Moon's Champion's Crag",
		"gate": {"near": "forest", "dist": 700.0, "ang": 120.0, "kind": "portal"}},
	"R7": {"name": "The Isle of Winter", "levels": [55, 70], "half": 750.0, "islands": true, "relief": 35.0,
		"ground": Color(0.90, 0.92, 0.96), "sky": Color(0.10, 0.12, 0.20), "fog": Color(0.70, 0.75, 0.85), "ambient": Color(0.50, 0.55, 0.65), "sun": Color(0.70, 0.80, 1.0),
		"foes": ["ice_wraith", "frost_giant", "frost_raider"], "boss": ["frost_giant", "The Winter Queen"],
		"hub": "Thaw-Camp", "npcs": ["Exile Chief Ragnhild", "Frozen Captain Hakon"],
		"sites": ["The Frozen Fleet", "The Glacier Heart", "The Crypt of Frozen Jarls"], "heart": "The Hall of the Bear",
		"gate": {"near": "Northwatch", "dist": 70.0, "ang": 0.0, "kind": "ship"}},
	"R8": {"name": "The Sky Gardens of Ilvaris", "levels": [55, 75], "half": 600.0, "islands": true, "floating": true, "relief": 12.0,
		"ground": Color(0.80, 0.85, 0.75), "sky": Color(0.55, 0.75, 1.0), "fog": Color(0.75, 0.85, 1.0), "ambient": Color(0.65, 0.70, 0.80), "sun": Color(1.0, 1.0, 0.95),
		"foes": ["vault_guardian", "vault_sentinel", "fire_spirit"], "boss": ["vault_sentinel", "The Rogue Engine-Warden"],
		"hub": "The Gardeners' Terrace", "npcs": ["Caretaker Aelindra", "Caretaker Thessaly", "Caretaker Orin"],
		"sites": ["The Star Observatory", "The Hanging Library", "The Engine Spire"], "heart": "The Throne of Ilvaris",
		"gate": {"near": "Skyfall", "dist": 50.0, "ang": 210.0, "kind": "portal"}},
	"R9": {"name": "The Mirror Court", "levels": [28, 36], "half": 450.0, "relief": 3.0,
		"ground": Color(0.85, 0.85, 0.90), "sky": Color(0.70, 0.75, 0.90), "fog": Color(0.80, 0.82, 0.92), "ambient": Color(0.70, 0.70, 0.78), "sun": Color(1.0, 1.0, 1.0),
		"foes": ["dune_stalker", "cutthroat", "vault_guardian"], "boss": ["vault_sentinel", "The Mirror-Shade"],
		"hub": "The Reversed Bazaar", "npcs": ["Mirror-Merchant Lahsa"],
		"sites": ["The First Reflected Tower", "The Second Reflected Tower", "The Third Reflected Tower"], "heart": "The Glass Prison",
		"gate": {"near": "Sunhold", "dist": 45.0, "ang": 60.0, "kind": "portal"}},
	"R10": {"name": "The Umbral Eclipse", "levels": [65, 90], "half": 900.0, "relief": 28.0,
		"ground": Color(0.18, 0.17, 0.19), "sky": Color(0.02, 0.01, 0.03), "fog": Color(0.10, 0.06, 0.12), "ambient": Color(0.30, 0.22, 0.34), "sun": Color(0.40, 0.20, 0.55),
		"foes": ["ashen_priest", "ice_wraith", "vampire"], "boss": ["ashen_priest", "The Avatar of Umbraal"],
		"hub": "The Last Candle", "npcs": ["Sister Lumen"],
		"sites": ["Shadow Kingsreach", "The Spire of Hunger", "The Eaten Sea", "The Choir's Anchor"], "heart": "The Heart of the Black Sun",
		"gate": {"near": "ashlands", "dist": 900.0, "ang": 40.0, "kind": "portal"}},
	"R11": {"name": "The Drowned Kingdom", "levels": [28, 45], "half": 600.0, "relief": 14.0,
		"ground": Color(0.25, 0.40, 0.42), "sky": Color(0.02, 0.10, 0.16), "fog": Color(0.05, 0.25, 0.32), "ambient": Color(0.25, 0.45, 0.50), "sun": Color(0.35, 0.80, 0.80),
		"foes": ["deep_crawler", "crawler_queen", "skeleton"], "boss": ["crawler_queen", "The Drowned King"],
		"hub": "The Bell Market", "npcs": ["Drowned Merchant Ilse", "The Promise-Keeper"],
		"sites": ["The Coral Cathedral", "The Pressure Deeps", "The Kraken's Garden"], "heart": "The Drowned King's Treasury",
		"gate": {"near": "Kelpstead", "dist": 50.0, "ang": 180.0, "kind": "bell"}},
	"R12": {"name": "Vey's Rest", "levels": [40, 55], "half": 600.0, "islands": true, "relief": 16.0,
		"ground": Color(0.55, 0.56, 0.52), "sky": Color(0.55, 0.56, 0.58), "fog": Color(0.70, 0.71, 0.72), "ambient": Color(0.55, 0.55, 0.58), "sun": Color(0.80, 0.80, 0.82),
		"foes": ["skeleton", "barrow_wight", "ice_wraith"], "boss": ["wight_lord", "The Unquiet Captain"],
		"hub": "The Monastery of the Closed Eye", "npcs": ["Brother Silent", "The Ghost of Prince Caedric"],
		"sites": ["The Lighthouse of Last Sight", "The Shipwreck of the Unburied", "The Ferryman's Cave"], "heart": "The Hall of Weighing",
		"gate": {"near": "Heron's Wick", "dist": 60.0, "ang": 270.0, "kind": "ship"}},
}

var world: WorldManager
var _gates := {}  # id -> Node3D
var _timer := 0.0


func _ready() -> void:
	add_to_group("realm_manager")
	world = get_parent() as WorldManager


static func get_data(id: String) -> Dictionary:
	return REALMS.get(id, {})


static func display_name(id: String) -> String:
	return String(get_data(id).get("name", id))


## A quest has sent you there: the gate opens (and stays open)
static func open_gate(id: String) -> void:
	if REALMS.has(id) and not is_open(id):
		WorldState.set_record("realm/" + id, {"open": true})


static func is_open(id: String) -> bool:
	return bool(WorldState.get_record("realm/" + id).get("open", false))


## Has the master of the realm's heart been defeated?
static func is_conquered(id: String) -> bool:
	return WorldState.has_record("kill/" + heart_key(id))


static func heart_key(id: String) -> String:
	return "realm/%s/heart/0" % id


static func site_key(id: String, site: int, n: int) -> String:
	return "realm/%s/s%d/%d" % [id, site, n]


## How many guards each site has (the first is its named master)
static func site_guards(id: String, site: int) -> int:
	return 3 + (site % 3)


## Is every guard of a site dead?
static func is_site_cleared(id: String, site: int) -> bool:
	for n in site_guards(id, site):
		if not WorldState.has_record("kill/" + site_key(id, site, n)):
			return false
	return true


## Where the realm's gate stands in the world (INF if its place can't be found)
static func gate_position(w: WorldManager, id: String) -> Vector3:
	var d := get_data(id)
	if d.is_empty() or w == null:
		return Vector3.INF
	var g: Dictionary = d["gate"]
	var center := Vector3.INF
	for t in w.towns:
		if t.town != null and t.town.display_name == String(g["near"]):
			center = t.position
	if not center.is_finite() and w.map != null:
		var area := 0.0
		for i in w.map.placements.size():
			if w.map.placements[i].biome.get_key() == String(g["near"]):
				var a := w.map.get_placement_rect(i).get_area()
				if a > area:
					area = a
					var c := w.map.get_placement_rect(i).get_center()
					center = Vector3(c.x, 0.0, c.y)
	if not center.is_finite():
		return Vector3.INF
	var t := w.get_town_at(center, 0.0)
	var dist := float(g["dist"]) + (t.poi.footprint_radius if t != null else 0.0)
	var ang := deg_to_rad(float(g["ang"]))
	var p := center + Vector3(cos(ang), 0.0, sin(ang)) * dist
	p.y = w.get_height_at(p.x, p.z)
	return p


# ---------------------------------------------------------------- gates in the world

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0 or world == null:
		return
	_timer = 0.0
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	if world.dungeons != null and world.dungeons.is_inside():
		_rescue_fall(p)
		return
	for id: String in REALMS:
		var at := gate_position(world, id)
		var near := at.is_finite() and Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() < GATE_NEAR
		if near and not _gates.has(id):
			var gate := RealmGate.make(id, String(REALMS[id]["gate"]["kind"]))
			world.add_child(gate)
			gate.global_position = Vector3(at.x, world.get_height_at(at.x, at.z), at.z)
			_gates[id] = gate
		elif not near and _gates.has(id):
			if is_instance_valid(_gates[id]):
				_gates[id].queue_free()
			_gates.erase(id)


# Inside a realm and fallen off its edge (the Sky Gardens float over nothing): back to the hub
func _rescue_fall(p: Node3D) -> void:
	var root := world.dungeons.get_interior_root()
	if root == null or not root.has_meta("realm_id"):
		return
	if p.global_position.y < root.global_position.y - 70.0:
		p.global_position = root.to_global(root.get_meta("realm_start"))
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO
		Locks.toast(get_tree(), "You fall... and wake at %s." % String(REALMS[String(root.get_meta("realm_id"))]["hub"]))
