@tool
class_name KitContainer
extends Node3D
## The builder kit: a container you can open (chest, sack, barrel, crate, urn, wardrobe, drawers, desk...),
## drawn as its model at its own size with collision that fits it (scenes/kit/containers/).
##   Leveled: filled when the game runs with loot for the place it stands in (KitPlace): a dungeon's
##            level and theme, a house's trade, else the player's level. Its own Loot Tags win when set.
##   Empty:   nothing in it; anything you put in stays (a stash, your home's storage).
## It remembers what was taken or stored: its save id is the room (or building) and its node name, so
## give two containers in one scene different names.

@export var display_name := "Chest":
	set(v):
		display_name = v
		_preview()
## Its model (ModelLibrary key: kit/containers/all/... from your Morrowind import, or prop/...); empty or
## missing = the built-in one for its name (POIBuilder.container_key)
@export var model_key := "":
	set(v):
		model_key = v
		_preview()
## Filled with loot when the game runs; off = an empty container
@export var leveled := true
## What kind of things are in it (ItemCatalog tags: weapon, armor, jewelry, alchemist, kitchen, crypt...);
## empty = what the place holds (the dungeon's or building's theme)
@export var loot_tags: PackedStringArray = []
## Levels above (or below) the place's
@export var level_bonus := 0
## How much is in it (1 = a normal chest, 2 = a boss chest)
@export_range(0.2, 3.0) var richness := 1.0
## Who it belongs to ("" = whoever owns the building it stands in; free to take outdoors and in dungeons)
@export var owner_id := ""
## Never anyone's, even inside a building (a public crate, a shrine's offering box)
@export var free_to_take := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		return
	var loot: Array[LootEntry] = []
	if leveled:
		var level := KitPlace.level(self) + level_bonus
		loot = ItemCatalog.tag_loot(KitPlace.tags(self, loot_tags), level, 1.5 * richness)
		loot.append(ItemCatalog.gold_loot(level, 0.6 * richness))
	var save := KitPlace.save_prefix(self)
	var chest := POIBuilder.make_container(display_name, model_key, loot, save, absi(save.hash()) | 1)
	var who := "" if free_to_take else KitPlace.owner_of(self, owner_id)
	if who != "":
		(chest.get_node("ContainerComponent") as ContainerComponent).owner_id = who
	add_child(chest)


func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var m := ModelLibrary.instance(ModelLibrary.first([model_key, POIBuilder.container_key(display_name)]))
	if m != null:
		m.position.y -= ModelLibrary.bounds(m).position.y
	EditorPreview.show_model(self, m)
