@tool
class_name KitContainer
extends Node3D
## The builder kit: a container you can loot (chest, rich chest, sack, barrel, crate, urn, cupboard...),
## drawn as its model (POIBuilder.container_key, by its name) and filled when the game runs, from the
## loot tags at the player's level. It remembers what was taken: its save id is the scene and its name.

@export var display_name := "Chest":
	set(v):
		display_name = v
		_preview()
## What kind of things are in it (ItemCatalog tags: weapon, armor, jewelry, alchemist, kitchen, crypt...)
@export var loot_tags: PackedStringArray = ["camp"]
## Levels above (or below) the player's
@export var level_bonus := 0
## Who it belongs to ("" = free to take)
@export var owner_id := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		return
	var level := _level() + level_bonus
	var loot := ItemCatalog.tag_loot(loot_tags, level, 1.5)
	loot.append(ItemCatalog.gold_loot(level, 0.6))
	var save := "kit/%s/%s" % [_where(), name]
	var chest := POIBuilder.make_chest(display_name, loot, save, absi(save.hash()) | 1)
	if owner_id != "":
		(chest.get_node("ContainerComponent") as ContainerComponent).owner_id = owner_id
	add_child(chest)
	chest.position = Vector3(0, 0.35, 0)


func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for c in get_children():
		remove_child(c)
		c.free()
	var m := ModelLibrary.instance(POIBuilder.container_key(display_name))
	if m != null:
		add_child(m)


func _level() -> int:
	var p := get_tree().get_first_node_in_group("player")
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	return skills.get_player_level() if skills != null else 5


# Where it is: the dungeon or interior the player is in, else the scene it was placed in
func _where() -> String:
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.current_entrance_id != "":
		return dm.current_entrance_id
	return owner.scene_file_path.get_file().get_basename() if owner != null else "world"
