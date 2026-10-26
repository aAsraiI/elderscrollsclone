@tool
class_name DungeonPreview
extends Node3D
## Look at a stitched interior in the editor: add a DungeonPreview node to any scene, pick a
## Recipe, a Seed and a Level, and tick Generate. Tick Bake to save what you see as a scene
## (Bake Path) that you can then finish by hand: a baked scene can replace a generated interior
## (see InteriorOverrides). The preview itself is never saved with the scene.

@export var recipe: DungeonRecipe
@export var seed_value := 1
@export var level := 10
## Leave the ceilings out, to look down into the rooms from above
@export var hide_ceilings := true
## Put furniture and decorations in the rooms (no enemies in the editor)
@export var fill_rooms := true
@export var generate := false:
	set(v):
		if v and Engine.is_editor_hint() and is_inside_tree():
			_generate()
@export var clear := false:
	set(v):
		if v and Engine.is_editor_hint():
			_clear()
@export_file("*.tscn") var bake_path := "res://scenes/interiors/baked/baked.tscn"
@export var bake := false:
	set(v):
		if v and Engine.is_editor_hint() and is_inside_tree():
			_bake()

var info := ""


func _clear() -> void:
	for c in get_children(true):
		if String(c.name).begins_with("Preview"):
			c.queue_free()


func _generate() -> Node3D:
	_clear()
	if recipe == null:
		push_warning("DungeonPreview: pick a Recipe first")
		return null
	ModuleLibrary.reload()
	var r := recipe
	if recipe.resource_path != "":
		r = ResourceLoader.load(recipe.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE) as DungeonRecipe  # the file as it is now
	var plan := DungeonAssembler.plan(r, seed_value, level)
	var built := plan.build("preview")
	built.name = "Preview"
	add_child(built, false, Node.INTERNAL_MODE_BACK)
	if fill_rooms:
		for room in built.get_children():
			if room is RoomModule:
				RoomFiller.fill(room, {"props_only": true, "dungeon_id": "preview", "level_min": level, "level_max": level + 2, "density": r.density, "seed": seed_value})
	if hide_ceilings:
		for c in built.find_children("Ceiling", "", true, false):
			(c as Node3D).visible = false
	info = plan.summary()
	print("DungeonPreview: ", info)
	return built


func _bake() -> void:
	if recipe == null:
		push_warning("DungeonPreview: pick a Recipe first")
		return
	var err := bake_to(recipe, seed_value, level, bake_path)
	if err == OK:
		print("DungeonPreview: baked to ", bake_path)
	else:
		push_error("DungeonPreview: can't bake (%d)" % err)


## Saves a planned interior as a scene of room modules: the rooms with their caps and spawn points
## (not filled: the game fills them), and the joins, so doors, levers and the secret room still
## work. Name the scene in a DungeonData's Handmade or in InteriorOverrides to use it.
static func bake_to(r: DungeonRecipe, seed_value: int, lvl: int, path: String) -> Error:
	ModuleLibrary.reload()
	var plan := DungeonAssembler.plan(r, seed_value, lvl)
	var built := plan.build("baked")
	built.name = String(path.get_file().get_basename()).to_pascal_case()
	_own(built, built)
	var ps := PackedScene.new()
	var err := ps.pack(built)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		err = ResourceSaver.save(ps, path)
	built.free()
	return err


# Everything added to the rooms (the caps) belongs to the baked scene; what is inside each room's
# own scene stays that scene's
static func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = owner_node
		_own(c, owner_node)
