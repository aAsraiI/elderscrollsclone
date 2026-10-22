class_name RestSpot
extends StaticBody3D
## Something you use with E in a building: a BED (sleep: opens the Wait screen in sleep mode) or a
## temple SHRINE (pray: cures diseases once a day; for a large offering it lifts vampirism and
## lycanthropy). Placed by InteriorBuilder.
##
## Beds: your own home's are free, an inn's cost a few gold a night, anyone else's are not yours.

const INTERACTABLE_LAYER := 4
const INN_PRICE := 10

var kind := "bed"
var building_id := ""
var building_kind := -1


static func make_bed(root: Node3D, at: Vector3, b: BuildingPlot) -> RestSpot:
	var s := RestSpot.new()
	s.kind = "bed"
	s.building_id = b.id
	s.building_kind = b.kind
	root.add_child(s)
	s.position = at
	return s


static func make_shrine(root: Node3D, at: Vector3) -> RestSpot:
	var s := RestSpot.new()
	s.kind = "shrine"
	root.add_child(s)
	s.position = at
	return s


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.7, 2.0) if kind == "bed" else Vector3(2.6, 1.6, 1.0)
	shape.shape = box
	shape.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(shape)


func _player() -> Node:
	return get_tree().get_first_node_in_group("player")


func is_own_home() -> bool:
	return Homes.owns(building_id)


func get_prompt() -> String:
	if kind == "shrine":
		var aff := _player().get_node_or_null("Afflictions") as Afflictions
		if aff != null and (aff.vampire or aff.werewolf):
			return "Pray at the Shrine  (lift your curse: %d gold)" % Afflictions.CURSE_COST
		return "Pray at the Shrine"
	if is_own_home():
		return "Sleep"
	if building_kind == BuildingPlot.Kind.INN:
		return "Sleep  (%d gold for the night)" % INN_PRICE
	return "Sleep  (not your bed)"


func interact(actor: Inventory) -> void:
	if kind == "shrine":
		_pray(actor)
		return
	if not is_own_home():
		if building_kind != BuildingPlot.Kind.INN:
			Locks.toast(get_tree(), "This isn't your bed", true)
			return
		if Currency.get_gold(actor) < INN_PRICE:
			Locks.toast(get_tree(), "You can't afford a bed here", true)
			return
	var wm := _player().get_node_or_null("WaitMenu") as WaitMenu
	if wm != null:
		wm.open_sleep(self)


## The sleep went through (WaitMenu): pay the inn
func on_slept() -> void:
	if not is_own_home() and building_kind == BuildingPlot.Kind.INN:
		Currency.spend_gold(_player().get_node("Inventory") as Inventory, INN_PRICE)


func _pray(actor: Inventory) -> void:
	var p := _player()
	var aff := p.get_node_or_null("Afflictions") as Afflictions
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if aff != null and (aff.vampire or aff.werewolf):
		if Currency.get_gold(actor) >= Afflictions.CURSE_COST:
			Currency.spend_gold(actor, Afflictions.CURSE_COST)
			if aff.vampire:
				aff.cure_vampire()
			if aff.werewolf:
				aff.cure_werewolf()
			Locks.toast(get_tree(), "The priests chant over you. The curse is lifted.")
			return
		Locks.toast(get_tree(), "The priests can lift your curse for an offering of %d gold" % Afflictions.CURSE_COST, true)
	var today := clock.day if clock != null else 1
	if int(WorldState.get_record("prayed").get("day", -1)) == today:
		Locks.toast(get_tree(), "You have already prayed today")
		return
	WorldState.set_record("prayed", {"day": today})
	var n := aff.cure_diseases() if aff != null else 0
	var m := ActiveMagic.of(p)
	if m != null:
		m.apply_list([{"id": &"fortify_health", "mag": 15, "dur": 600}], null, "Blessing", "spell")
	Locks.toast(get_tree(), "You pray. %s You feel blessed." % ("Your sickness is gone." if n > 0 else ""))
