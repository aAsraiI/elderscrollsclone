@tool
class_name KitStation
extends Node3D
## The builder kit: something you use with E (scenes/kit/stations/), drawn in the editor as it looks in game.
##   Crafting: forge, smelter, tanning rack, workbench, grindstone, cooking pot, alchemy lab, arcane
##             enchanter, altar of spellmaking (CraftingStation; opens the crafting screen)
##   Rest:     bed, rich bed, bunk, bedroll (sleep; in a building only its owner's, an inn's for gold,
##             anywhere else free) and shrine (pray: cures diseases)
##   Planter:  grows what you plant in it (Planter)
## It faces the way its model does: turn it in the editor until it looks right.

const CRAFTING := ["forge", "smelter", "tanning_rack", "workbench", "grindstone", "cooking_pot", "alchemy_lab", "enchanter", "spell_altar"]
## Rest spots: their model
const BEDS := {"bed": "prop/bed", "bed_rich": "prop/bed_rich", "bunk": "prop/bunk", "bedroll": "prop/bedroll", "shrine": "prop/altar"}

@export_enum("forge", "smelter", "tanning_rack", "workbench", "grindstone", "cooking_pot", "alchemy_lab", "enchanter", "spell_altar",
	"bed", "bed_rich", "bunk", "bedroll", "shrine", "planter")
var kind := "workbench":
	set(v):
		kind = v
		_preview()


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		return
	if kind in CRAFTING:
		CraftingStation.place(self, kind, Vector3.ZERO)
	elif kind == "planter":
		Planter.place(self, Vector3.ZERO, KitPlace.save_prefix(self).replace("kit/", "planter/"))
	else:
		_rest()


# A bed or shrine: its model (solid, a hull that fits it) and the spot you use with E
func _rest() -> void:
	var body := StaticBody3D.new()
	body.name = "Furniture"
	add_child(body)
	var key := String(BEDS[kind])
	var m := ModelLibrary.instance(key)
	if m != null:
		body.add_child(m)
		m.position.y -= ModelLibrary.bounds(m).position.y
		ModelLibrary.add_collision(body, m, key + "|kit")
	var spot := RestSpot.new()
	spot.kind = "shrine" if kind == "shrine" else "bed"
	var n := get_parent()
	while n != null:
		if n.has_meta("building_id"):
			spot.building_id = String(n.get_meta("building_id"))
			spot.building_kind = int(n.get_meta("building_kind", -1))
			break
		n = n.get_parent()
	add_child(spot)


func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	EditorPreview.clear(self)
	var holder := Node3D.new()
	if kind in CRAFTING:
		CraftingStation.add_look(holder, kind)
	elif kind == "planter":
		var m := ModelLibrary.instance("prop/flower_box")
		if m != null:
			holder.add_child(m, false, Node.INTERNAL_MODE_BACK)
	else:
		var m := ModelLibrary.instance(String(BEDS[kind]))
		if m != null:
			m.position.y -= ModelLibrary.bounds(m).position.y
			holder.add_child(m, false, Node.INTERNAL_MODE_BACK)
	if holder.get_child_count(true) == 0:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, 0.9, 0.7)
		box.mesh = bm
		box.position.y = 0.45
		holder.add_child(box, false, Node.INTERNAL_MODE_BACK)  # no model for it yet: where it stands
	EditorPreview.show_model(self, holder)
