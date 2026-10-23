class_name Spellbook
extends Node
## What the player knows: spells (premade and self-made), enchantments learned by disenchanting,
## alchemy effects discovered on each ingredient, the favorites list (Q) and the Mark spot.
## Also which spell sits in the off hand. Lives under the Player (player.gd adds it).
##
## Equipping a spell empties the off hand (a shield or second dagger goes back in the bag) and
## takes a two-handed weapon out of the main hand; equipping something in the off hand puts the
## spell away again. Right mouse button casts it (PlayerCombat).

signal changed
signal equipped_changed(spell: SpellData)
signal learned(spell: SpellData)

var spells: Dictionary = {}          # id -> SpellData
var equipped_id := ""
var enchantments: Dictionary = {}    # effect id (String) -> true
## Ingredient resource path -> Array of effect indices (0..3) you know
var alchemy_known: Dictionary = {}
## Favorites: item paths and "spell:<id>"
var favorites: Array[String] = []
## Mark spell: [x, y, z] or empty
var mark: Array = []

var _equipment: Equipment
var _custom_counter := 1


func _ready() -> void:
	_equipment = get_parent().get_node_or_null("Equipment") as Equipment
	if _equipment != null:
		_equipment.equipped.connect(_on_equipped)
	for id in SpellCatalog.STARTING:
		learn(SpellCatalog.get_spell(id), true)


# ---------------------------------------------------------------- spells

func learn(spell: SpellData, quiet: bool = false) -> bool:
	if spell == null or spell.id == "" or spells.has(spell.id):
		return false
	spells[spell.id] = spell
	if not quiet:
		learned.emit(spell)
	changed.emit()
	return true


func knows(id: String) -> bool:
	return spells.has(id)


func forget(id: String) -> void:
	if not spells.has(id):
		return
	if equipped_id == id:
		unequip_spell()
	spells.erase(id)
	favorites.erase("spell:" + id)
	changed.emit()


## A new id for a spell made at an altar
func new_custom_id() -> String:
	while spells.has("custom_%d" % _custom_counter):
		_custom_counter += 1
	return "custom_%d" % _custom_counter


## Every effect you could put into a new spell: the effects of the spells you know
func known_effects() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in spells:
		for e in (spells[id] as SpellData).effects:
			var eid := StringName(e["id"])
			if not out.has(eid):
				out.append(eid)
	return out


func get_spell(id: String) -> SpellData:
	return spells.get(id)


func sorted_spells() -> Array[SpellData]:
	var out: Array[SpellData] = []
	for id in spells:
		out.append(spells[id])
	out.sort_custom(func(a: SpellData, b: SpellData) -> bool:
		if a.get_school() != b.get_school():
			return MagicEffects.SCHOOLS.find(a.get_school()) < MagicEffects.SCHOOLS.find(b.get_school())
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return out


# ---------------------------------------------------------------- the off hand

func get_equipped() -> SpellData:
	return spells.get(equipped_id)


func equip_spell(id: String) -> bool:
	if not spells.has(id):
		return false
	if get_parent().has_meta("beast_form"):
		return false
	equipped_id = id
	if _equipment != null:
		# The off hand is the casting hand: it has to be empty
		_equipment.unequip(ItemData.EquipSlot.OFF_HAND)
		var main := _equipment.get_equipped(ItemData.EquipSlot.MAIN_HAND)
		if main != null and main.two_handed:
			_equipment.unequip(ItemData.EquipSlot.MAIN_HAND)
	equipped_changed.emit(get_equipped())
	changed.emit()
	return true


func unequip_spell() -> void:
	if equipped_id == "":
		return
	equipped_id = ""
	equipped_changed.emit(null)
	changed.emit()


func _on_equipped(slot: int, item: ItemData) -> void:
	if equipped_id == "":
		return
	if slot == ItemData.EquipSlot.OFF_HAND or (slot == ItemData.EquipSlot.MAIN_HAND and item != null and item.two_handed):
		unequip_spell()


# ---------------------------------------------------------------- enchantments and alchemy

func knows_enchantment(effect_id: StringName) -> bool:
	return enchantments.has(String(effect_id))


func learn_enchantment(effect_id: StringName) -> bool:
	if knows_enchantment(effect_id):
		return false
	enchantments[String(effect_id)] = true
	changed.emit()
	return true


func known_ingredient_effects(item: ItemData) -> Array:
	return alchemy_known.get(SaveUtil.item_to_path(item), [])


func learn_ingredient_effect(item: ItemData, index: int) -> bool:
	var path := SaveUtil.item_to_path(item)
	if path == "":
		return false
	var list: Array = alchemy_known.get(path, [])
	if list.has(index):
		return false
	list.append(index)
	alchemy_known[path] = list
	return true


# ---------------------------------------------------------------- favorites

func is_favorite(key: String) -> bool:
	return favorites.has(key)


func toggle_favorite(key: String) -> void:
	if favorites.has(key):
		favorites.erase(key)
	else:
		favorites.append(key)
	changed.emit()


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var list: Array = []
	for id in spells:
		list.append((spells[id] as SpellData).to_dict())
	return {"spells": list, "equipped": equipped_id, "enchantments": enchantments.keys(),
		"alchemy": alchemy_known.duplicate(true), "favorites": favorites.duplicate(), "mark": mark.duplicate()}


func from_dict(data: Dictionary) -> void:
	spells.clear()
	for d in data.get("spells", []):
		var s := SpellData.from_dict(d)
		if s.id != "" and not s.effects.is_empty():
			spells[s.id] = s
	if spells.is_empty():
		for id in SpellCatalog.STARTING:
			learn(SpellCatalog.get_spell(id), true)
	enchantments.clear()
	for e in data.get("enchantments", []):
		enchantments[String(e)] = true
	alchemy_known = (data.get("alchemy", {}) as Dictionary).duplicate(true)
	favorites.clear()
	for f in data.get("favorites", []):
		favorites.append(String(f))
	mark = data.get("mark", [])
	equipped_id = ""
	var eq := String(data.get("equipped", ""))
	if spells.has(eq):
		equipped_id = eq
	equipped_changed.emit(get_equipped())
	changed.emit()
