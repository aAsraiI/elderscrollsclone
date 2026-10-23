class_name DigSpot
extends StaticBody3D
## A patch of disturbed earth where an Antiquarian Society excavation job buried its artifact.
## Made by QuestManager when the place's area loads. Dig with a pickaxe or shovel in your pack:
## the artifact comes up, and so do the dead who guarded it.

@export var quest_id := ""
@export var item_name := ""
@export var level := 5

const INTERACTABLE_LAYER := 4
const GUARD := "res://data/enemies/skeleton.tres"
const TOOLS := ["res://data/clutter/pickaxe.tres", "res://data/clutter/shovel.tres"]


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.6, 1.6)
	shape.shape = box
	add_child(shape)
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 0.5
	mound.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.27, 0.18)
	mound.material_override = mat
	add_child(mound)


static func has_tool(inv: Inventory) -> bool:
	for p in TOOLS:
		if ResourceLoader.exists(p) and inv.has_item(load(p)):
			return true
	return false


func get_prompt() -> String:
	return "Dig here"


func interact(actor: Inventory) -> void:
	if actor == null:
		return
	var p := get_tree().get_first_node_in_group("player")
	if not has_tool(actor):
		var hud := p.get_node_or_null("CompassHUD") as CompassHUD if p != null else null
		if hud != null:
			hud.show_banner("You need a pickaxe or a shovel", "Smiths and general stores sell them")
		return
	actor.add_item(QuestItems.get_item(quest_id, item_name))
	WorldState.set_record("dig/" + quest_id, {"done": true})
	# the old dead do not like being disturbed
	var body := load(GUARD) as EnemyData
	if body != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("dig|" + quest_id).hash()
		for i in 2:
			var at := global_position + Vector3(rng.randf_range(-4, 4), 0.5, rng.randf_range(-4, 4))
			Population.spawn_enemy(body, level, get_parent(), at, rng, {"persist_mode": Enemy.PersistMode.CORPSE_ONLY})
	queue_free()
