class_name SeaPassage
extends Carriage
## A ship moored at the end of a port town's pier (Alpha 1.21). E: pick another port, on this island
## or across the sea, pay the captain, and time passes at sea until you step off at that port's pier.
## Every island has a port (SettlementPlanner marks them: PlacedPOI.extra["port"]). Placed by
## TownBuilder._pier. Like the carriage it works even when fast travel is off: it is a paid voyage.

const SHIP_GOLD_PER_KM := 6.0
const SHIP_SPEED_KMH := 18.0


## Port towns in the world (any island)
static func ports(w: WorldManager) -> Array[PlacedPOI]:
	var out: Array[PlacedPOI] = []
	if w != null:
		for t in w.towns:
			if bool(t.extra.get("port", false)) and t.town != null and t.town.shore != Vector3.INF:
				out.append(t)
	return out


## Where you step ashore at a port: the land end of its pier
static func berth_for(t: PlacedPOI) -> Vector3:
	var layout := t.town
	if layout == null or layout.shore == Vector3.INF:
		return Carriage.stop_for(t)
	var out := Vector3(layout.shore.x, 0.0, layout.shore.z).normalized()
	return layout.to_world(layout.shore - out * 3.0)


func get_prompt() -> String:
	return "Book passage on the ship"


func _title() -> String:
	return "Ship"


func _destinations() -> Array[PlacedPOI]:
	var out: Array[PlacedPOI] = []
	for t in SeaPassage.ports(_world()):
		if t.id != town_id:
			out.append(t)
	return out


func _arrival(t: PlacedPOI) -> Vector3:
	return SeaPassage.berth_for(t)


func _speed() -> float:
	return SHIP_SPEED_KMH


func _gold_per_km() -> float:
	return SHIP_GOLD_PER_KM


# A two-masted trader: hull, deck, cabin, masts and furled sails, lying along local Z
func _build_look() -> void:
	var dark := POIBuilder.get_material(Color(0.28, 0.19, 0.11))
	var wood := POIBuilder.get_material(Color(0.42, 0.3, 0.18))
	var sail := POIBuilder.get_material(Color(0.78, 0.74, 0.62))
	_part(Vector3(4.2, 2.4, 15.0), Vector3(0, 0.2, 0), dark)
	_part(Vector3(3.0, 1.6, 3.0), Vector3(0, 0.0, 8.4), dark, PI * 0.25)  # the bow
	_part(Vector3(4.0, 0.2, 14.6), Vector3(0, 1.45, 0), wood)
	_part(Vector3(3.6, 1.8, 3.4), Vector3(0, 2.4, -5.2), wood)  # the cabin at the stern
	for z in [-1.5, 3.8]:
		_part(Vector3(0.35, 11.0, 0.35), Vector3(0, 6.9, z), dark)
		_part(Vector3(5.4, 0.25, 0.25), Vector3(0, 9.2, z), dark)
		_part(Vector3(5.0, 3.2, 0.12), Vector3(0, 7.5, z + 0.25), sail)
	# the hull is solid (the carriage-sized shape is where you press E)
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.2, 3.2, 15.0)
	hull.shape = box
	hull.position = Vector3(0, 0.6, 0)
	add_child(hull)


func _part(size: Vector3, at: Vector3, m: Material, yaw: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.rotation.y = yaw
	mi.material_override = m
	add_child(mi)
