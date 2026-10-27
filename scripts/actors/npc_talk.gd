class_name NpcTalk
extends Node
## Lets you talk to an NPC: add it under a body (the Enemy does this for friendly and neutral NPCs).
## It sets the body up like a chest: interactable meta + physics layer 3, so the interaction ray
## finds it and shows "[E] Talk to <name>". Talking opens the dialogue window; without one, each press
## moves on to the next line (no speech bubbles over heads since 1.17: the screen stays clear).

const INTERACTABLE_LAYER := 4  # physics layer 3

@export var speaker := "Stranger"
@export var lines: PackedStringArray = []
@export var bubble_seconds := 4.0

var _index := 0
var _bubble: Label3D
var _bubble_left := 0.0
## The last thing said (no longer shown over the head)
var last_line := ""


static func attach(body: Node, name_shown: String, line_list: PackedStringArray) -> NpcTalk:
	var t := NpcTalk.new()
	t.name = "NpcTalk"
	t.speaker = name_shown
	t.lines = line_list
	body.add_child(t)
	return t


func _ready() -> void:
	var body := get_parent() as CollisionObject3D
	if body == null:
		push_warning("NpcTalk: must be a child of a physics body.")
		return
	body.set_meta("interactable", self)
	body.collision_layer |= INTERACTABLE_LAYER


func get_prompt() -> String:
	return "Talk to %s" % speaker


func interact(_actor: Inventory) -> void:
	# The dialogue window (made by player.gd) when there is one, the speech bubble otherwise
	var ui := get_tree().get_first_node_in_group("dialogue_ui") as DialogueUI
	if ui != null and get_parent() is Enemy and ui.open_with(get_parent() as Enemy):
		return
	if lines.is_empty():
		return
	say(lines[_index % lines.size()])
	_index += 1


func say(text: String) -> void:
	last_line = "%s: %s" % [speaker, text]  # no bubble over the head (1.17); kept for whoever asks


func _process(delta: float) -> void:
	if _bubble != null and is_instance_valid(_bubble):
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.queue_free()
			_bubble = null


func _exit_tree() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		_bubble.queue_free()
