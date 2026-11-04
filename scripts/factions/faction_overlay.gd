class_name FactionOverlay
extends Node3D
## Alpha 1.24, debug console "factions": a label over every creature within RANGE m with its side
## and who it is fighting, coloured by side. Refreshed twice a second.

const RANGE := 60.0
const COLORS := {"bandits": Color(0.95, 0.5, 0.3), "smugglers": Color(0.9, 0.75, 0.3), "undead": Color(0.7, 0.85, 0.7),
	"vampires": Color(0.8, 0.2, 0.3), "werewolves": Color(0.6, 0.45, 0.3), "cultists": Color(0.75, 0.55, 0.9),
	"beasts": Color(0.6, 0.8, 0.4), "town": Color(0.4, 0.7, 1.0), "livestock": Color(0.9, 0.9, 0.85),
	"spirits": Color(0.5, 0.9, 1.0), "constructs": Color(0.7, 0.7, 0.7), "giants": Color(0.8, 0.65, 0.5)}

var _labels := {}  # Enemy id -> Label3D
var _timer := 0.0


## Switches the overlay on or off; returns what the console prints (your standing with each side)
static func toggle(tree: SceneTree) -> String:
	var old := tree.get_first_node_in_group("faction_overlay")
	if old != null:
		old.queue_free()
		return "Faction overlay off."
	var o := FactionOverlay.new()
	o.name = "FactionOverlay"
	tree.current_scene.add_child(o)
	var lines := PackedStringArray(["Faction overlay on. Your standing:"])
	for f in CreatureFactions.all():
		lines.append("  %-12s %4d%s" % [f, CreatureFactions.standing(f), "  (they leave you be)" if CreatureFactions.tolerates_player(f) else ""])
	return "\n".join(lines)


func _ready() -> void:
	add_to_group("faction_overlay")


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var seen := {}
	for e in ActorRegistry.near(p.global_position, RANGE):
		if e.is_dead() or not e.is_inside_tree():
			continue
		var id := e.get_instance_id()
		seen[id] = true
		var l: Label3D = _labels.get(id)
		if l == null or not is_instance_valid(l):
			l = Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.font_size = 40
			l.pixel_size = 0.004
			l.outline_size = 8
			add_child(l)
			_labels[id] = l
		var f := CreatureFactions.of(e)
		var t := e.get_fight_target()
		var vs := ""
		if t != null and is_instance_valid(t):
			vs = "  > " + ("YOU" if t.is_in_group("player") else CreatureFactions.of(t))
		l.text = f + vs + ("  (frozen)" if ActorLOD.is_frozen(e) else "")
		l.modulate = COLORS.get(f, Color.WHITE)
		l.global_position = e.global_position + Vector3.UP * (2.3 * e.body_scale)
	for id in _labels.keys():
		if not seen.has(id):
			if is_instance_valid(_labels[id]):
				_labels[id].queue_free()
			_labels.erase(id)
