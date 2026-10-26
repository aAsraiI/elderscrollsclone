class_name Ladder
extends Area3D
## A ladder you climb: walk into it, then forward (W) climbs and back (S) goes down; jump lets go.
## At the top you step off forwards. Put it against a wall in a room module (the build tool does
## this for ladder rooms); its Height is how far it goes up. The player asks the ladder to move it
## while it is on one (player.gd, like a boat).

@export var height := 5.0
@export var speed := 2.6


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, height + 1.0, 0.9)
	shape.shape = box
	shape.position = Vector3(0, (height + 1.0) * 0.5, 0)
	add_child(shape)
	body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			b.set_meta("ladder", self))
	body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player") and b.get_meta("ladder", null) == self:
			b.remove_meta("ladder"))


## Moves the climbing player (called from the player's physics step)
func climb(p: CharacterBody3D, _delta: float, input_dir: Vector2) -> void:
	if Input.is_action_just_pressed("jump"):
		p.remove_meta("ladder")
		p.velocity = global_basis.z * 3.0  # push off, away from the wall
		return
	var up := -input_dir.y
	p.velocity = Vector3(0, up * speed, 0)
	var top := global_position.y + height
	if p.global_position.y > top - 0.2 and up > 0.0:
		p.velocity = -global_basis.z * 2.5 + Vector3(0, 1.5, 0)  # step off at the top
	p.move_and_slide()
