@tool
class_name KitBlock
extends StaticBody3D
## The builder kit: a building block of any size, drawn as a Morrowind piece stretched over it (an
## Imperial wall, a tower, a corner, an arch, a stone block) and solid as the box you set. For walls,
## towers, ruins and pillars. Look: wall/city, wall/tower, wall/corner, wall/arch, wall/palisade, prop/plinth...

@export var size := Vector3(6.0, 6.0, 2.5):
	set(v):
		size = v
		_rebuild()
@export var look := "wall/city":
	set(v):
		look = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("kit_built") or c.name == "Look":
			remove_child(c)
			c.free()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = Vector3(0, size.y * 0.5, 0)
	mesh.set_meta("kit_built", true)
	add_child(mesh)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = mesh.position
	cs.set_meta("kit_built", true)
	add_child(cs)
	ModelLibrary.dress_box(self, look)
