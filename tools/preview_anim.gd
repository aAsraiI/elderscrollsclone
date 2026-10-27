extends Node3D
## On the model preview scene: plays the clip ModelBody would use for `role` on every model.

@export var role := "idle"


func _ready() -> void:
	for ap in find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		var names := p.get_animation_list()
		for want in ModelBody.ROLE_CLIPS.get(role, ["Idle"]):
			var clip := ModelBody._match(names, String(want))
			if clip != "":
				p.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				p.play(clip)
				break
