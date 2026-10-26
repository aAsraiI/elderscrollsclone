class_name SiteLife
extends Node
## The people and animals of an outdoor place getting on with things (Alpha 1.14): in a camp the
## sleepers lie in their bedrolls, whoever is near the fire sits by it cooking and eating, the
## guards and archers stand watch looking out, the rest wander a little; farms and camps keep
## animals (sheep, cows, a hunting dog). SitePOIData adds one to every site it builds.

## What kind of place keeps which animals
const ANIMALS := {"farmstead": ["sheep", "sheep", "cow"], "hunters_camp": ["hound"], "mill": ["cow"], "wayside_inn": ["hound"]}


static func attach(site: ExteriorSite) -> SiteLife:
	var n := SiteLife.new()
	n.name = "Life"
	site.add_child(n)
	return n


## A friendly animal (sheep, cow, hound) that grazes or trots about its spot
static func animal(parent: Node3D, kind: String, at: Vector3, key: String) -> Enemy:
	var path := "res://data/npcs/%s.tres" % kind
	if not ResourceLoader.exists(path):
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	var e := Enemy.create()
	(load(path) as EnemyData).apply(e, 1, rng)
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.spawn_key = key
	e.wander_radius = 5.0
	e.set_meta("animal", kind)
	e.talk_name = ""  # nothing to say
	parent.add_child(e)
	e.position = at + Vector3(0, 0.3, 0)
	e.rotation.y = rng.randf() * TAU
	return e


func _ready() -> void:
	_settle.call_deferred()  # the people's bodies are made after this


func _settle() -> void:
	var site := get_parent() as ExteriorSite
	if site == null:
		return
	var fires: Array[Vector3] = []
	for p in site.find_children("*", "InteriorProp", true, false):
		if (p as InteriorProp).tags.has("campfire"):
			fires.append((p as Node3D).position)
	for n in site.find_children("*", "Enemy", true, false):
		var e := n as Enemy
		if e.has_meta("animal") or e.disposition != Enemy.Disposition.HOSTILE:
			continue
		var tags := _tags(site, e)
		var near_fire := fires.any(func(f: Vector3) -> bool: return f.distance_to(e.position) < 4.5)
		if tags.has("sleeper") and e.body_kind == CreatureBody.Kind.HUMANOID:
			e.sleep()
		elif near_fire and e.body != null:
			e.body.pose = &"sit"  # cooking, eating, warming their hands
			e.wander_radius = 0.0
		elif tags.has("guard") or tags.has("archer"):
			e.wander_radius = 0.0
			var out := Vector3(e.position.x, 0, e.position.z)
			if out.length() > 0.5:
				e.rotation.y = atan2(-out.x, -out.z) + PI  # looking out from the middle
		else:
			e.wander_radius = 4.0


# The tags of the spawn point a person came from ("<place>/<socket>/<n>")
static func _tags(site: ExteriorSite, e: Enemy) -> PackedStringArray:
	var parts := e.spawn_key.split("/")
	if parts.size() < 2:
		return PackedStringArray()
	var s := site.get_node_or_null(NodePath(parts[parts.size() - 2])) as SpawnSocket
	return s.tags if s != null else PackedStringArray()
