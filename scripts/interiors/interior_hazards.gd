class_name InteriorHazards
extends RefCounted
## Small dangers and obstacles placed in stitched interiors (InteriorFeatures makes them):
##   Barricade   planks across a passage: E (with a weapon in hand) breaks it, three blows
##   GasCloud    poison hanging in a room: it hurts while you stand in it (Restoration resists)
##   LeverPuzzle three levers in a room; pulled in the right order (hinted by their marks) they
##               open a gate to a treasure chest, the wrong order sets off a dart trap
## Each remembers what happened in WorldState under its id.


class Barricade extends StaticBody3D:
	var save_id := ""
	var hits := 0

	func _ready() -> void:
		if WorldState.has_record(save_id):
			queue_free()
			return
		collision_layer = 1 | 4
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.4, 2.4, 0.3)
		shape.shape = box
		shape.position = Vector3(0, 1.2, 0)
		add_child(shape)
		for i in 4:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.6, 0.25, 0.12)
			mi.mesh = bm
			mi.material_override = InteriorKit.material("wood")
			mi.position = Vector3(0, 0.4 + i * 0.6, 0)
			mi.rotation.z = 0.12 * (1 if i % 2 == 0 else -1)
			add_child(mi)

	func get_prompt() -> String:
		return "Break the barricade (%d/3)" % hits

	func interact(_actor: Inventory) -> void:
		var p := get_tree().get_first_node_in_group("player")
		var eq := p.get_node_or_null("Equipment") as Equipment if p != null else null
		if eq == null or eq.get_main_hand() == null:
			Locks.toast(get_tree(), "You need a weapon in hand to break it.", true)
			return
		hits += 1
		if hits >= 3:
			WorldState.set_record(save_id, {"broken": true})
			Locks.toast(get_tree(), "The barricade gives way")
			queue_free()


class GasCloud extends Area3D:
	var save_id := ""
	var damage_per_second := 3.0
	var size := Vector3(6, 3, 6)
	var _inside: Node3D

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1 | 2
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = Vector3(0, size.y * 0.5, 0)
		add_child(shape)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.6, 0.25, 0.18)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = shape.position
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		body_entered.connect(func(b: Node3D) -> void:
			if b.is_in_group("player"):
				_inside = b
				Locks.toast(get_tree(), "The air here burns your lungs", true))
		body_exited.connect(func(b: Node3D) -> void:
			if b == _inside:
				_inside = null)

	func _physics_process(delta: float) -> void:
		if _inside == null or not is_instance_valid(_inside):
			return
		var stats := _inside.get_node_or_null("Stats") as Stats
		if stats != null and not stats.is_dead:
			stats.modify_vital("health", -damage_per_second * delta)


class LeverPuzzle extends Node3D:
	var save_id := ""
	var order: Array = []   # which lever must be pulled first, second, third
	var pulled: Array = []
	var gate_name := ""
	var damage := 10.0

	func lever_pulled(i: int) -> void:
		if WorldState.has_record(save_id):
			return
		pulled.append(i)
		if order.slice(0, pulled.size()) != pulled:
			pulled.clear()
			var p := get_tree().get_first_node_in_group("player")
			var stats := p.get_node_or_null("Stats") as Stats if p != null else null
			if stats != null:
				stats.modify_vital("health", -damage)
			Locks.toast(get_tree(), "Click... darts fly from the walls. The levers reset.", true)
			return
		Locks.toast(get_tree(), "A heavy clunk somewhere in the walls")
		if pulled.size() == order.size():
			WorldState.set_record(save_id, {"solved": true})
			var gate := get_parent().get_node_or_null(gate_name)
			if gate != null:
				gate.queue_free()
			Locks.toast(get_tree(), "The gate grinds open")


class PuzzleLever extends StaticBody3D:
	var puzzle: LeverPuzzle
	var index := 0
	var mark := ""

	func _ready() -> void:
		collision_layer = 1 | 4
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.5, 1.2, 0.4)
		shape.shape = box
		shape.position = Vector3(0, 0.6, 0)
		add_child(shape)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.5, 0.4)
		base.mesh = bm
		base.material_override = InteriorKit.material("stone")
		base.position = Vector3(0, 0.25, 0)
		add_child(base)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.08, 0.8, 0.08)
		arm.mesh = am
		arm.material_override = InteriorKit.material("iron")
		arm.position = Vector3(0, 0.8, 0)
		add_child(arm)

	func get_prompt() -> String:
		return "Pull the lever marked with %s" % mark

	func interact(_actor: Inventory) -> void:
		if puzzle != null:
			puzzle.lever_pulled(index)
