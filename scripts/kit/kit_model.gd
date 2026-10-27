@tool
class_name KitModel
extends StaticBody3D
## The builder kit: any model by its ModelLibrary key (a Morrowind piece from your import, or a built-in
## one), with collision from its own shape. Drop it into a scene and set Key; it shows in the editor too.
## Keys: prop/... (furniture), clutter/..., wall/..., nature/..., tree/..., entrance/..., door/... (MODELS.md)

@export var key := "prop/barrel":
	set(v):
		key = v
		_rebuild()
## Its own size in metres (Morrowind's), or fitted into this box when it is set
@export var fit_size := Vector3.ZERO:
	set(v):
		fit_size = v
		_rebuild()
@export var solid := true


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("kit_built"):
			remove_child(c)
			c.free()
	if not ModelLibrary.has(key):
		return
	var m: Node3D = ModelLibrary.fitted(key, AABB(Vector3(-fit_size.x * 0.5, 0, -fit_size.z * 0.5), fit_size), "contain") if fit_size != Vector3.ZERO else ModelLibrary.instance(key)
	if m == null:
		return
	m.set_meta("kit_built", true)
	add_child(m)
	if solid:
		var before := get_child_count()
		ModelLibrary.add_collision(self, m, key + "|kit|" + str(fit_size))
		for i in range(before, get_child_count()):
			get_child(i).set_meta("kit_built", true)
