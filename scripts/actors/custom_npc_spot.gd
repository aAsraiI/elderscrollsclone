class_name CustomNpcSpot
extends Marker3D
## Puts one hand-made person (CustomNpcData) right here, in any scene: add a CustomNpcSpot node,
## move it where they should stand, and drag their .tres into Npc in the Inspector. They appear
## when the scene starts (unless they were killed in this game).

@export var npc: CustomNpcData


func _ready() -> void:
	if Engine.is_editor_hint() or npc == null or WorldState.has_record("kill/" + npc.save_id()):
		return
	_place.call_deferred()


func _place() -> void:
	CustomNpcs.spawn(npc, get_parent(), global_position)
