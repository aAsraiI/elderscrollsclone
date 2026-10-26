class_name Readable
extends StaticBody3D
## Something out in the world you can read with E (Alpha 1.14): a note on a body, a milestone, the
## inscription on a monument, a signpost's arms. Opens the book reader (BookUI).

## Notes found on the dead, the lost and the left behind (one is picked by the place's seed)
const NOTES := [
	["A Bloodstained Note", "Mara,\n\nThe road north is not safe. Three of us left the ford and only I am still walking. If you find this, do not wait for me at the crossroads. Go home.\n\n- T."],
	["A Torn Letter", "...and the toll-men at the bridge want twice what they wanted last spring. I paid. I did not like the way they looked at the cart after. Tell your father I will be late..."],
	["A Hunter's Tally", "Wolves: 4. Boar: 1. Deer: 0 (the wolves got them first).\nSomething big up by the old stones. Tracks as wide as a shield. Not going back alone."],
	["A Pilgrim's Prayer", "Keeper of the road, light my way.\nKeeper of the hearth, keep my house.\nKeeper of the grave, not yet. Not yet."],
	["An Unsent Message", "Captain,\n\nThe fort has gone quiet. No smoke for three days. I am going up to look. If I do not come back, send more than one next time."],
	["A Merchant's Ledger Page", "Salt: 12 sacks (2 wet).\nIron: 30 bars.\nOwed by the miller at the crossing: 40 gold, which I will never see.\nNote: buy a better lock."],
]

@export var title := "A Note"
@export_multiline var text := ""


static func make(parent: Node3D, at: Vector3, yaw: float, p_title: String, p_text: String, look: String = "note") -> Readable:
	var r := Readable.new()
	r.name = "Readable"
	r.title = p_title
	r.text = p_text
	parent.add_child(r)
	r.position = at
	r.rotation.y = yaw
	match look:
		"milestone":
			POIBuilder.add_box(r, Vector3(0.5, 1.0, 0.35), Vector3(0, 0.5, 0), Color(0.5, 0.49, 0.46))
		"note":
			POIBuilder.add_box(r, Vector3(0.22, 0.01, 0.3), Vector3(0, 0.01, 0), Color(0.85, 0.8, 0.68), 0.3, Vector3.ZERO, false)
	return r


func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.0, 0.7)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)


func get_prompt() -> String:
	var t := title
	if t.begins_with("A ") or t.begins_with("An "):
		t = t.to_lower()
	return "Read " + t


func interact(_actor: Inventory) -> void:
	BookUI.open(get_tree(), title, text)
