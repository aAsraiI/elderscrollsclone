class_name MagicHit
extends RefCounted
## Small helpers shared by every spell, enchantment and poison: who counts as a target, finding
## targets in an area, and what happens after the player hurts someone (crimes, like a sword hit).

const LAYER_WORLD := 1
const LAYER_ITEMS := 4
const LAYER_ENEMY := 16


## The creature body a collider belongs to (with an ActiveMagic), or null
static func creature_of(collider: Object) -> Node3D:
	if collider == null or not is_instance_valid(collider):
		return null
	if collider.has_meta("magic"):
		return collider as Node3D
	if collider.has_meta("ragdoll_owner"):
		var owner: Variant = collider.get_meta("ragdoll_owner")
		return owner as Node3D if is_instance_valid(owner) else null
	return null


## Are these two on the same side? (the player and their summons, or two hostile creatures)
static func friendly(a: Node, b: Node) -> bool:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	if a == b:
		return true
	var a_player := a.is_in_group("player") or a.has_meta("player_ally")
	var b_player := b.is_in_group("player") or b.has_meta("player_ally")
	if a_player and b_player:
		return true
	var ea := a as Enemy
	var eb := b as Enemy
	if ea != null and eb != null and not a_player and not b_player:
		return ea.disposition == Enemy.Disposition.HOSTILE and eb.disposition == Enemy.Disposition.HOSTILE
	return false


## Every living creature within radius of a point (bodies with an ActiveMagic)
static func creatures_in(world: World3D, center: Vector3, radius: float, exclude: Array = []) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = LAYER_WORLD | LAYER_ENEMY
	q.collide_with_areas = false
	for hit in world.direct_space_state.intersect_shape(q, 64):
		var c := creature_of(hit.get("collider"))
		if c != null and not out.has(c) and not exclude.has(c):
			var m := ActiveMagic.of(c)
			if m != null and m.stats != null and not m.stats.is_dead:
				out.append(c)
	return out


## After the player's magic hurt someone who wasn't hostile: that is a crime, like a sword hit
static func after_hit(caster: Node, victim: Node3D, info: DamageInfo) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_in_group("player"):
		return
	var e := victim as Enemy
	if e == null or e.has_meta("player_ally"):
		return
	var wronged: bool = e.disposition != Enemy.Disposition.HOSTILE or e.get_meta("wronged_by_player", false)
	if not wronged:
		return
	e.set_meta("wronged_by_player", true)
	var crime := caster.get_tree().get_first_node_in_group("crime")
	if crime != null:
		crime.on_player_hurt(e, info.killed)


## Floating text over a creature (Resisted, Absorbed, ...)
static func popup(host: Node3D, text: String, color: Color) -> void:
	return  # no floating text over creatures (1.17)
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var scene := host.get_tree().current_scene
	if scene == null:
		return
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = 0.005
	label.outline_size = 10
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	scene.add_child(label)
	label.global_position = host.global_position + Vector3.UP * 2.2
	var tw := label.create_tween().set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y + 0.7, 0.8)
	tw.tween_property(label, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(label.queue_free)
