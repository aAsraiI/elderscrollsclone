class_name SignpostPOIData
extends POIData
## A signpost where roads meet out in the wilds (Alpha 1.14): a post with an arm for each road,
## pointing the way it goes and naming the town at its end. POIPlanner puts one at every crossroads
## and fork outside the towns; its arms are in the placed point's named["arms"]: [[yaw, text], ...]
## (yaw in world space). E on it reads them all.

const WOOD := Color(0.36, 0.25, 0.15)


func _init() -> void:
	id = &"signpost"
	display_name = "Signpost"
	footprint_radius = 2.0
	discoverable = false
	random_rotation = false


func build(placed: PlacedPOI, _map: WorldMap) -> Node3D:
	var root := Node3D.new()
	if placed.named.has("milestone"):  # a milestone: a stone by the road with the distances on it
		Readable.make(root, Vector3.ZERO, 0.0, "the milestone", String(placed.named["milestone"]), "milestone")
		return root
	POIBuilder.add_box(root, Vector3(0.18, 3.0, 0.18), Vector3(0, 1.5, 0), WOOD)
	var lines := PackedStringArray()
	var arms: Array = placed.named.get("arms", [])
	for i in arms.size():
		var arm: Array = arms[i]
		var yaw := float(arm[0]) - placed.yaw
		var holder := Node3D.new()
		holder.position = Vector3(0, 2.6 - i * 0.3, 0)
		holder.rotation.y = yaw
		root.add_child(holder)
		POIBuilder.add_box(holder, Vector3(0.12, 0.22, 1.1), Vector3(0, 0, -0.6), WOOD.lightened(0.15), 0.0, Vector3.ZERO, false)
		POIBuilder.add_box(holder, Vector3(0.14, 0.12, 0.12), Vector3(0, 0, -1.2), WOOD.lightened(0.15), 0.0, Vector3(0, 0, 0.785), false)
		lines.append(String(arm[1]))
	Readable.make(root, Vector3.ZERO, 0.0, "the signpost", "\n".join(lines), "none")
	return root
