class_name ItemUse
extends RefCounted
## What "use" means for the stage 10 item kinds (the inventory's E button and the favorites menu):
## read a spell tome, eat a raw ingredient, put a poison on your blade, recharge an enchanted weapon.


## The button text, or "" when the item has no such use
static func verb(_player: Node, item: ItemData) -> String:
	if item == null:
		return ""
	if item.scroll_spell != "":
		return "Read the scroll"  # 1.28: casts it once, for free
	if String(item.id) == "tome_of_mastery":
		return "Study the tome"  # 1.27
	if item.teaches_spell != "":
		return "Read"
	if LoreBooks.is_book(item):
		return "Read book"
	if Notes.is_note(item):
		return "Read note"
	if String(item.id) == "raft_kit":
		return "Build a raft"
	if String(item.id) == "air_bladder":
		return "Breathe from the bladder"
	if String(item.id).ends_with("_barding"):
		return "Put it on your horse"  # 1.27
	if String(item.id) == "repair_hammer":
		return "Mend your gear"  # 1.27
	if String(item.id) == "horse_deed":
		return "Call your horse"
	if String(item.id) == "sellsword_contract":
		return "Hire a sellsword"
	if item.is_poison:
		return "Apply poison"
	if item.item_type == ItemData.ItemType.INGREDIENT and Alchemy.is_ingredient(item):
		return "Eat"
	if item.item_type == ItemData.ItemType.WEAPON and not item.enchant_effects.is_empty() and CraftedItems.is_crafted(item) \
			and CraftedItems.get_charge(item) < CraftedItems.get_max_charge(item) - 0.5:
		return "Recharge"
	return ""


static func use(player: Node, item: ItemData) -> void:
	var tree := player.get_tree()
	QuestEvents.use(tree, item)
	match verb(player, item):
		"Read book":
			BookUI.open(tree, item.display_name, LoreBooks.read(player, item))
		"Build a raft":
			var why := _build_raft(player, item)
			if why != "":
				Locks.toast(tree, why, true)
		"Breathe from the bladder":
			var sw := player.get_node_or_null("Swimming")
			var inv2 := player.get_node_or_null("Inventory") as Inventory
			if sw == null or not bool(sw.get("_under")):
				Locks.toast(tree, "Save it for under the water.", true)
			elif inv2 != null:
				sw.set("breath", float(sw.get("breath")) + 20.0)
				inv2.remove_item(item, 1)
				Locks.toast(tree, "A long breath of stale air.")
		"Read note":
			BookUI.open(tree, item.display_name, String(item.get_meta("note_text", "")))
		"Read":
			var book := player.get_node_or_null("Spellbook") as Spellbook
			var spell := SpellCatalog.get_spell(item.teaches_spell)
			var inv := player.get_node_or_null("Inventory") as Inventory
			if book == null or spell == null or inv == null:
				return
			if book.knows(spell.id):
				Locks.toast(tree, "You already know %s" % spell.display_name, true)
				return
			inv.remove_item(item, 1)
			book.learn(spell)
			Locks.toast(tree, "You learned the spell %s. Equip it from the Magic menu." % spell.display_name)
		"Hire a sellsword":
			var f := player.get_node_or_null("Followers") as Followers
			if f != null:
				var why := f.hire()
				if why == "":
					(player.get_node("Inventory") as Inventory).remove_item(item, 1)
					Locks.toast(tree, "A sellsword joins you")
				else:
					Locks.toast(tree, why, true)
		"Read the scroll":
			var why := read_scroll(player, item)
			if why != "":
				Locks.toast(tree, why, true)
		"Study the tome":
			Locks.toast(tree, mastery_tome(player, item))
		"Put it on your horse":
			Locks.toast(tree, Rider.put_on_barding(player, item))
		"Mend your gear":
			Locks.toast(tree, Durability.use_hammer(player, item))
		"Call your horse":
			var rider := player.get_node_or_null("Rider") as Rider
			if rider != null:
				rider.use_deed()
		"Apply poison":
			var why := WeaponMagic.apply_poison(player, item)
			Locks.toast(tree, why if why != "" else "Your weapon is poisoned (%s)" % item.display_name, why != "")
		"Eat":
			var learned := Alchemy.eat(player, item)
			if learned != "":
				Locks.toast(tree, learned)
		"Recharge":
			var why := WeaponMagic.recharge(player, item)
			Locks.toast(tree, why if why != "" else "%s is recharged" % item.display_name, why != "")


# 1.25: a raft at the water's edge in front of you (it is your boat from now on)
static func _build_raft(player: Node, item: ItemData) -> String:
	var p := player as Node3D
	var world := player.get_tree().get_first_node_in_group("world_manager") as WorldManager
	var inv := player.get_node_or_null("Inventory") as Inventory
	if world == null or world.map == null or inv == null or (world.dungeons != null and world.dungeons.is_inside()):
		return "There is no water here to float it on."
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for d in [3.0, 5.0, 7.0, 9.0]:
		var at: Vector3 = p.global_position + fwd * d
		var sea := world.map.get_water_level(at.x, at.z)
		if world.get_height_at(at.x, at.z) < sea - 0.8:
			var old := player.get_tree().current_scene.find_children("Boat", "", true, false)
			for b in old:
				if b is Boat and not (b as Boat).is_boarded() and (b as Boat).from_town == "":
					b.queue_free()  # your old raft or boat, left behind somewhere
			var raft := Boat.make(player.get_tree().current_scene, Vector3(at.x, sea, at.z), atan2(-fwd.x, -fwd.z), "", true)
			WorldState.set_record("boat", {"pos": SaveUtil.vec3_to_array(raft.global_position), "yaw": raft.rotation.y, "from": "", "raft": true})
			inv.remove_item(item, 1)
			Locks.toast(player.get_tree(), "You lash the logs together. Your raft floats.")
			return ""
	return "Face open water, at its edge, to build a raft."


## 1.27: a Tome of Mastery raises your best skill of 100 or more to its next mastery step (125, 150...)
static func mastery_tome(player: Node, item: ItemData) -> String:
	var sk := player.get_node_or_null("Skills") as Skills
	if sk == null:
		return ""
	var best := &""
	for id in sk.levels:
		if int(sk.levels[id]) >= SkillDatabase.MASTERY_START and (best == &"" or int(sk.levels[id]) > int(sk.levels[best])):
			best = id
	if best == &"":
		return "The tome is beyond you. Come back when a skill is at 100."
	var lvl := int(sk.levels[best])
	var step := SkillDatabase.MASTERY_STEP
	var next := SkillDatabase.MASTERY_START + ((lvl - SkillDatabase.MASTERY_START) / step + 1) * step
	sk.set_level(best, next)
	(player.get_node("Inventory") as Inventory).remove_item(item, 1)
	Achievements.note("mastery_tome")
	var def := SkillDatabase.get_skill(best)
	return "You study the tome for days. %s rises to %d." % [def.display_name if def != null else String(best).capitalize(), next]


## 1.28: a scroll casts its spell once, for free and at full strength, whatever your skill. "" = cast.
static func read_scroll(player: Node, item: ItemData) -> String:
	var spell := SpellCatalog.get_spell(item.scroll_spell)
	var caster := player.get_node_or_null("SpellCaster") as SpellCaster
	if spell == null or caster == null:
		return "The words fade as you read them."
	if not caster.cast_now(spell, true):
		return "You can't cast now."
	(player.get_node("Inventory") as Inventory).remove_item(item, 1)
	Achievements.note("scroll")
	return ""
