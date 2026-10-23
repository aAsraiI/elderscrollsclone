class_name DungeonFeature
extends StaticBody3D
## Things in a dungeon you can use, made by DungeonBuilder:
##   LEVER   pull it and the floor's gate opens (the gate is a sibling node named in `target`)
##   SECRET  a loose stone in a wall; push it and the wall opens onto a hidden room
##   TRAP    a pressure plate: stepping on it fires darts at you. Use it to try to disarm it
##           (Security skill improves the odds; failing sets it off)
## Each remembers what happened through WorldState under `save_id`, so a pulled lever stays pulled.

enum Kind { LEVER, SECRET, TRAP }

@export var kind: Kind = Kind.LEVER
@export var save_id := ""
## LEVER / SECRET: the node (sibling) this opens
@export var target := ""
## TRAP: damage when it goes off
@export var damage := 10.0

const INTERACTABLE_LAYER := 4

var _armed := true


static func is_done(id: String) -> bool:
	return WorldState.has_record(id)


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	match kind:
		Kind.LEVER:
			box.size = Vector3(0.6, 1.2, 0.6)
			_mesh(Vector3(0.3, 0.5, 0.2), Vector3.ZERO, Color(0.3, 0.3, 0.32))
			_mesh(Vector3(0.08, 0.6, 0.08), Vector3(0.0, 0.3, 0.12), Color(0.5, 0.35, 0.2), 0.5 if is_done(save_id) else -0.5)
		Kind.SECRET:
			box.size = Vector3(1.0, 1.0, 0.6)
		Kind.TRAP:
			box.size = Vector3(1.2, 0.3, 1.2)
			_mesh(Vector3(1.0, 0.06, 1.0), Vector3(0.0, 0.03, 0.0), Color(0.36, 0.33, 0.30))
			var area := Area3D.new()
			area.collision_layer = 0
			area.collision_mask = 1 | 2  # the player body
			var ashape := CollisionShape3D.new()
			var abox := BoxShape3D.new()
			abox.size = Vector3(1.0, 1.0, 1.0)
			ashape.shape = abox
			ashape.position = Vector3(0.0, 0.5, 0.0)
			area.add_child(ashape)
			add_child(area)
			area.body_entered.connect(_on_stepped)
			_armed = not is_done(save_id)
	shape.shape = box
	add_child(shape)


func _mesh(size: Vector3, pos: Vector3, color: Color, tilt: float = 0.0) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	m.rotation.x = tilt
	add_child(m)


func get_prompt() -> String:
	match kind:
		Kind.LEVER:
			return "" if is_done(save_id) else "Pull lever"
		Kind.SECRET:
			return "Push the loose stone"
		Kind.TRAP:
			return "Disarm trap" if _armed else ""
	return ""


func interact(_actor: Inventory) -> void:
	match kind:
		Kind.LEVER, Kind.SECRET:
			if is_done(save_id):
				return
			WorldState.set_record(save_id, {"open": true})
			var n := get_parent().get_node_or_null(target)
			if n != null:
				n.queue_free()
			if kind == Kind.SECRET:
				queue_free()
			else:
				for c in get_children():
					if c is MeshInstance3D and (c as MeshInstance3D).position.y > 0.2:
						(c as MeshInstance3D).rotation.x = 0.5  # the lever is down now
		Kind.TRAP:
			if not _armed:
				return
			var p := get_tree().get_first_node_in_group("player")
			var skills := p.get_node_or_null("Skills") as Skills if p != null else null
			var security := skills.get_level(&"security") if skills != null else 0
			if randf() < 0.45 + security * 0.01:
				_armed = false
				WorldState.set_record(save_id, {"disarmed": true})
				if skills != null:
					skills.add_xp(&"security", 4.0)
			else:
				_fire(p)


func _on_stepped(body: Node) -> void:
	if _armed and body.is_in_group("player"):
		_fire(body)


func _fire(target_body: Node) -> void:
	_armed = false
	WorldState.set_record(save_id, {"fired": true})
	if target_body == null:
		return
	var stats := target_body.get_node_or_null("Stats") as Stats
	if stats != null and not stats.is_dead:
		stats.modify_vital("health", -damage)
	var hud := target_body.get_node_or_null("CompassHUD") as CompassHUD
	if hud != null:
		hud.show_banner("A trap!", "Darts fly from the walls")
