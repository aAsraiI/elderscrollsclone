class_name PatronShrine
extends StaticBody3D
## Alpha 1.28.5: the altar of a glowing shrine in the wilds, sacred to one of the eight Patrons
## (picked from the place's id). Press E to kneel (see Patrons).

const INTERACTABLE_LAYER := 4

var patron := "vael"


static func make(root: Node3D, at: Vector3, poi_id: String) -> PatronShrine:
	var s := PatronShrine.new()
	s.patron = Patrons.for_place(poi_id)
	root.add_child(s)
	s.position = at
	return s


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	add_to_group("patron_shrines")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 4.5, 1.6)
	shape.shape = box
	shape.position.y = 2.4
	add_child(shape)


func get_prompt() -> String:
	return Patrons.prompt(patron)


func interact(actor: Inventory) -> void:
	var p := actor.get_parent() if actor != null else null
	if p != null:
		Locks.toast(get_tree(), Patrons.kneel(patron, p))
