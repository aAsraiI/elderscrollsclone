class_name Fishing
extends Node
## Alpha 1.30.1: fishing. Use a Fishing Pole (E in the inventory, or a favourite key) while facing
## water close by: from a pier, a boat or a bank. After a wait (shorter with the Fishing skill) a
## fish bites: press E within a moment to land it. Miss it, move, or put the pole away and it's off.
## What bites depends on where (sea, river and lake, swamp, the frozen north, the far islands) and
## when (dawn and dusk are best; some only at night). Rare fish are worth a lot to collectors, and
## every species you land is written in the journal. Trains Fishing. Lives under the Player.

const POLE := "res://data/clutter/fishing_pole.tres"
const REACH := 7.0
const BITE_WINDOW := 1.6
## species -> [name, where ("sea", "fresh", "swamp", "cold", "far", "any"), when ("any", "day", "night", "dawn"), rarity 0-3, value]
const FISH := {
	"silverfin_trout": ["Silverfin Trout", "fresh", "any", 0, 6],
	"river_perch": ["River Perch", "fresh", "day", 0, 5],
	"sea_bass": ["Sea Bass", "sea", "any", 0, 7],
	"saltcod": ["Saltcod", "sea", "day", 0, 6],
	"marsh_eel": ["Marsh Eel", "swamp", "any", 1, 14],
	"ice_pike": ["Ice Pike", "cold", "any", 1, 16],
	"moonscale": ["Moonscale", "any", "night", 2, 120],
	"golden_koi": ["Golden Koi", "fresh", "dawn", 2, 150],
	"gloomfin": ["Gloomfin", "swamp", "night", 2, 110],
	"abyssal_angler": ["Abyssal Angler", "far", "night", 3, 900],
	"leviathan_scale": ["Leviathan Scale", "sea", "any", 3, 1400],
}

var _player: CharacterBody3D
var _state := ""   # "", "waiting", "bite"
var _left := 0.0
var _where := ""
var _at := Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as CharacterBody3D


static func of(player: Node) -> Fishing:
	return player.get_node_or_null("Fishing") as Fishing if player != null else null


static func is_pole(item: ItemData) -> bool:
	return item != null and String(item.id) == "fishing_pole"


func is_fishing() -> bool:
	return _state != ""


## The water the player faces within REACH, as a kind ("sea", "fresh", "swamp", "cold", "far"), or ""
func water_ahead() -> String:
	var w := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if w == null or w.map == null or (w.dungeons != null and w.dungeons.is_inside()):
		return ""
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for d: float in [2.0, 4.0, REACH]:
		var p := _player.global_position + fwd * d
		var level := w.map.get_water_level(p.x, p.z)
		if w.get_height_at(p.x, p.z) < level - 0.4:
			return _kind_at(w, p, level)
	if _player.has_meta("boat"):
		return _kind_at(w, _player.global_position, w.map.get_water_level(_player.global_position.x, _player.global_position.z))
	return ""


func _kind_at(w: WorldManager, p: Vector3, level: float) -> String:
	var band := w.map.get_level_band(p.x, p.z)
	if band.x >= 100.0:
		return "far"
	var b := w.get_biome_at(p.x, p.z)
	var id := String(b.id) if b != null else ""
	if id in ["tundra", "snow_mountains", "frozen_crown"]:
		return "cold"
	if id == "swamp":
		return "swamp"
	return "sea" if level <= w.map.settings.sea_level + 0.05 else "fresh"


## Casts a line. "" = cast, or why not.
func cast() -> String:
	if _state != "":
		_stop("You reel in your line.")
		return ""
	_where = water_ahead()
	if _where == "":
		return "Face open water close by: from a pier, a boat or a bank."
	_state = "waiting"
	_at = _player.global_position
	var st := _player.get_node_or_null("Stats") as Stats
	var bonus := st.get_stat("fishing_bonus") if st != null else 0.0
	_left = randf_range(4.0, 11.0) * clampf(1.0 - bonus, 0.35, 1.0) * Seasons.bite_mult()  # 1.30: winter is slow
	Locks.toast(get_tree(), "You cast your line... (E on the pole again reels in)")
	return ""


func _stop(why: String) -> void:
	_state = ""
	if why != "":
		Locks.toast(get_tree(), why)


func _process(delta: float) -> void:
	if _state == "" or get_tree().paused:
		return
	if _player.global_position.distance_to(_at) > 1.5:
		_stop("You moved: the line goes slack.")
		return
	_left -= delta
	if _state == "waiting" and _left <= 0.0:
		_state = "bite"
		_left = BITE_WINDOW
		Locks.toast(get_tree(), "A bite! Press E!")
	elif _state == "bite" and _left <= 0.0:
		_stop("It got away.")


func _unhandled_input(event: InputEvent) -> void:
	if _state == "bite" and event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		land()


## The bite is struck: what comes up (tests call it). Returns the species id, or "".
func land() -> String:
	if _state != "bite":
		return ""
	_state = ""
	var id := pick(_where, _time_of_day(), _player)
	var sk := _player.get_node_or_null("Skills") as Skills
	if sk != null:
		sk.add_xp(&"fishing", 5.0 + float(FISH[id][3]) * 10.0)
	give(id, _player)
	return id


func _time_of_day() -> String:
	var c := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if c == null:
		return "day"
	var h := c.hour
	if (h >= 5.0 and h < 7.5) or (h >= 18.0 and h < 20.0):
		return "dawn"
	return "night" if c.is_night() else "day"


## Which fish bites: rarer ones by skill and the hour; only those of this water and time
static func pick(where: String, tod: String, player: Node) -> String:
	var st := player.get_node_or_null("Stats") as Stats
	var bonus := st.get_stat("fishing_bonus") if st != null else 0.0
	var pool: Array = []
	for id in FISH:
		var f: Array = FISH[id]
		if f[1] != "any" and f[1] != where and not (where == "far" and f[1] == "sea"):
			continue
		if f[2] != "any" and f[2] != tod and not (f[2] == "night" and tod == "dawn"):
			continue
		var weight: float = float([10.0, 3.0, 0.6, 0.12][int(f[3])]) * (1.0 + bonus * float(f[3]) * 3.0)
		if tod == "dawn":
			weight *= 1.3
		pool.append([id, weight])
	if pool.is_empty():
		return "silverfin_trout"
	var total := 0.0
	for p in pool:
		total += float(p[1])
	var r := randf() * total
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			return String(p[0])
	return String(pool[-1][0])


static func give(id: String, player: Node) -> void:
	var inv := player.get_node("Inventory") as Inventory
	var f: Array = FISH[id]
	var it := load("res://data/materials/fish_%s.tres" % id) as ItemData
	if it == null:
		it = load("res://data/materials/raw_fish.tres") as ItemData
	var n := 1
	var st := player.get_node_or_null("Stats") as Stats
	if int(f[3]) == 0 and st != null and randf() < st.get_stat("fishing_bonus"):
		n = 2
	inv.add_item(it, n)
	Achievements.note("fish")
	var caught: Array = (WorldState.get_record("fish_caught").get("ids", []) as Array).duplicate()
	if not caught.has(id):
		caught.append(id)
		WorldState.set_record("fish_caught", {"ids": caught})
		DialogueState.system_entry("Knowledge", "I caught my first %s.%s" % [f[0], " A rare fish: collectors will pay well for it." if int(f[3]) >= 2 else ""], "")
	Locks.toast(player.get_tree(), "You land %s%s!" % ["two " if n == 2 else "a ", f[0] if n == 1 else f[0] + "s"])
