class_name BirthStone
extends StaticBody3D
## Alpha 1.27.5: the altar stone in the middle of every ring of standing stones. Each ring keeps
## one birthsign (picked from its place's seed and shown in the prompt); press E to take it as
## yours in place of the sign you were born under. Free, but only once a day.
## Your sign is kept in the character data (Player meta "character" "sign"), so it is saved.

const INTERACTABLE_LAYER := 4

var sign_id := "sword"


static func make(root: Node3D, at: Vector3, seed_value: int) -> BirthStone:
	var b := BirthStone.new()
	var keys := Classes.SIGNS.keys()
	b.sign_id = String(keys[absi(seed_value) % keys.size()])
	root.add_child(b)
	b.position = at
	return b


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.2, 1.6)
	shape.shape = box
	shape.position.y = 0.4
	add_child(shape)


func get_prompt() -> String:
	var s: Dictionary = Classes.SIGNS.get(sign_id, {})
	var p := get_tree().get_first_node_in_group("player")
	var mine := String((p.get_meta("character", {}) as Dictionary).get("sign", "")) if p != null else ""
	if mine == sign_id:
		return "%s stone (your sign)" % s.get("name", "")
	return "Take %s as your sign (%s)" % [s.get("name", ""), s.get("desc", "")]


func interact(actor: Inventory) -> void:
	var p := actor.get_parent() if actor != null else null
	if p != null:
		Locks.toast(get_tree(), take(p))


## Makes this stone's sign the player's. "" = done, or why not (as a message).
func take(player: Node) -> String:
	var ch: Dictionary = (player.get_meta("character", {}) as Dictionary).duplicate()
	var s: Dictionary = Classes.SIGNS.get(sign_id, {})
	if String(ch.get("sign", "")) == sign_id:
		return "%s is already your sign." % s.get("name", "")
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	var today := clock.day if clock != null else 0
	if int(WorldState.get_record("birthstone").get("day", -1)) == today:
		return "The stones are quiet. Come back tomorrow."
	WorldState.set_record("birthstone", {"day": today})
	ch["sign"] = sign_id
	player.set_meta("character", ch)
	var stats := player.get_node_or_null("Stats") as Stats
	if stats != null:
		stats.add_modifiers("sign", s.get("stats", {}))
	Achievements.note("birthstone")
	DialogueState.system_entry("Knowledge", "At the standing stones I took %s as my sign: %s." % [s.get("name", ""), s.get("desc", "")], "")
	return "You are under %s now: %s." % [s.get("name", ""), s.get("desc", "")]
