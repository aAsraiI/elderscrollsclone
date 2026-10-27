@tool
class_name InteriorProp
extends StaticBody3D
## A piece of furniture or decoration as a scene (scenes/interiors/props/). Spawn points
## (SpawnSocket) pick props by their Tags, the room's theme and wealth (PropLibrary). Make a new
## one by copying a prop scene and changing its meshes; set what it is in the Inspector.

enum Snap { FLOOR, WALL, CEILING }

## What it is: "table", "chair", "bed", "barrel", "banner", "bones"... (sockets ask for these)
@export var tags: PackedStringArray = []
## Which socket kinds it suits (FURNITURE, DECORATION, WALL_DECORATION, LIGHT, CEILING)
@export var socket_kinds: PackedStringArray = ["DECORATION"]
## The themes it fits (empty = every theme)
@export var themes: PackedStringArray = []
@export var snap: Snap = Snap.FLOOR
## Its footprint, so two props don't land in each other
@export var radius := 0.5
@export_range(0, 2) var wealth_min := 0
@export_range(0, 2) var wealth_max := 2
@export var weight := 1.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# A real model for this prop (ModelLibrary "prop/<scene name>", then its first tag) replaces the
	# boxes, with collision from the model's own shape
	var keys: Array = []
	if scene_file_path != "":
		keys.append("prop/" + scene_file_path.get_file().get_basename())
	for t in tags:
		keys.append("prop/" + t)
	var key := ModelLibrary.first(keys)
	if key != "":
		ModelLibrary.replace_meshes(self, key)
