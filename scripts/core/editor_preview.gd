@tool
class_name EditorPreview
extends RefCounted
## The game's look in the editor: room and site scenes, prop scenes and spawn points show the models
## and Morrowind textures the game gives them when it runs. Nothing here is ever saved into a scene:
## models are internal children, and boxes are hidden and walls retextured on the rendering server
## only (the nodes' own properties are untouched).

const MATERIALS := "res://data/interiors/materials/"
const PREVIEW := "_EditorPreview"

static var _dressed := {}  # material name -> its Morrowind-textured copy (null when not imported)


## `model` drawn in place of `node`'s own box meshes (flames and glows stay)
static func show_model(node: Node3D, model: Node3D) -> void:
	clear(node)
	if model == null:
		return
	for mi in node.find_children("*", "MeshInstance3D", true, true):
		if not ModelLibrary._glows(mi as MeshInstance3D):
			RenderingServer.instance_set_visible((mi as MeshInstance3D).get_instance(), false)
	model.name = PREVIEW
	node.add_child(model, false, Node.INTERNAL_MODE_BACK)


## A scene (a prop) previewed under `node`, e.g. what a spawn point would hold
static func show_scene(node: Node3D, path: String) -> void:
	clear(node)
	var ps := load(path) as PackedScene
	if ps == null:
		return
	var n := ps.instantiate()
	n.name = PREVIEW
	node.add_child(n, false, Node.INTERNAL_MODE_BACK)


static func clear(node: Node) -> void:
	for c in node.get_children(true):
		if c.name == PREVIEW:
			node.remove_child(c)
			c.free()


## Walls, floors and rock under `root` take Morrowind's textures, as MwSurfaces gives them in game
static func dress_room(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.material_override != null:
			# the override wins over every surface, so it is the one swapped
			var over := _dressed_for(mi.material_override)
			if over != null:
				RenderingServer.instance_geometry_set_material_override(mi.get_instance(), over.get_rid())
			continue
		for s in mi.mesh.get_surface_count():
			var mat := _dressed_for(mi.get_active_material(s))
			if mat != null:
				RenderingServer.instance_set_surface_override_material(mi.get_instance(), s, mat.get_rid())


static func _dressed_for(m: Material) -> Material:
	if m == null or not m.resource_path.begins_with(MATERIALS):
		return null
	var name := m.resource_path.get_file().get_basename()
	if not MwSurfaces.KIT.has(name) or not m is StandardMaterial3D:
		return null
	if not _dressed.has(name):
		var copy: StandardMaterial3D = null
		if MwSurfaces.texture(name) != null:
			copy = m.duplicate() as StandardMaterial3D
			MwSurfaces.dress_material(name, copy)
		_dressed[name] = copy
	return _dressed[name]
