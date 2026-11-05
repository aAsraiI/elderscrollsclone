class_name Pickpocket
extends RefCounted
## Alpha 1.29.1: picking pockets. Sneak up on someone who hasn't noticed you and press E: their
## pockets open (the container window). Each thing you take is a roll:
##   chance = 55% + Pickpocket bonus - weight x 4% - value / 40 (at most 30%) - how aware they are
## kept between 5% and 95%. Gold counts by its weight (light) and how much you lift.
## Fail and they feel it: the window closes, they turn on you and it is reported as a crime.
## Skill 25 (Plant) lets you put things in; skill 100 (Master Thief) lets you lift what they wear.
## Every lift trains Pickpocket; what you take is stolen (CrimeManager).

const BASE := 0.55
const REACH := 2.2


## Can the player pick this one's pockets right now?
static func can(player: Node3D, e: Enemy) -> bool:
	if player == null or e == null or e.is_dead() or e.body_kind != CreatureBody.Kind.HUMANOID:
		return false
	if e.disposition == Enemy.Disposition.HOSTILE or e.has_meta("player_ally") or e.inventory == null:
		return false
	var st: Variant = player.get_meta("stealth", null)
	if st == null or not is_instance_valid(st) or not bool(st.get("sneaking")):
		return false
	if e.global_position.distance_to(player.global_position) > REACH:
		return false
	return e.asleep or float(st.awareness_of(e)) < Stealth.NOTICED


static func chance(player: Node, e: Enemy, item: ItemData, count: int = 1) -> float:
	var st := player.get_node_or_null("Stats") as Stats
	var bonus := st.get_stat("pickpocket_bonus") if st != null else 0.0
	var aware := 0.0
	var stealth: Variant = player.get_meta("stealth", null)
	if stealth != null and is_instance_valid(stealth):
		aware = float(stealth.awareness_of(e))
	var c := BASE + bonus - item.weight * count * 0.04 - minf(float(item.value * count) / 4000.0, 0.3) - aware * 0.5
	if e.asleep:
		c += 0.2
	return clampf(c, 0.05, 0.95)


## Opens their pockets in the container window. Returns false if it could not.
static func open(player: Node3D, e: Enemy) -> bool:
	var ui := player.get_tree().get_first_node_in_group("container_ui") as ContainerUI
	if ui == null:
		return false
	var pockets := e.get_node_or_null("Pockets") as ContainerComponent
	if pockets == null:
		pockets = ContainerComponent.new()
		pockets.name = "Pockets"
		pockets.display_name = "%s's pockets" % e.display_name
		pockets.existing_inventory = e.inventory
		pockets.draggable = 2
		e.add_child(pockets)
	return ui.open_pockets(pockets, e)


## One lift. Returns true if it came away clean.
static func try_take(player: Node, e: Enemy, item: ItemData, count: int, rng: RandomNumberGenerator = null) -> bool:
	var roll := rng.randf() if rng != null else randf()
	var ok := roll < chance(player, e, item, count)
	var sk := player.get_node_or_null("Skills") as Skills
	if sk != null:
		sk.add_xp(&"pickpocket", 3.0 + item.value * count * 0.01 if ok else 1.0)
	if ok:
		Achievements.note("pickpocket")
		CrimeManager.add_stolen(item, count)
		QuestEvents.steal(player.get_tree(), item, count)
	return ok


## They felt it: they turn on you, and it is a crime (they are the witness)
static func caught(player: Node3D, e: Enemy) -> void:
	var stealth: Variant = player.get_meta("stealth", null)
	if stealth != null and is_instance_valid(stealth):
		stealth.awareness[e.get_instance_id()] = 1.2
	e.set_meta("wronged_by_player", true)
	var crime := player.get_tree().get_first_node_in_group("crime") as CrimeManager
	if crime != null:
		crime.report("pickpocket", 0, e)
	Locks.toast(player.get_tree(), "%s feels your hand in their pocket!" % e.display_name, true)


## Can the player put things into pockets (skill 25), or lift worn things (skill 100)?
static func can_plant(player: Node) -> bool:
	var sk := player.get_node_or_null("Skills") as Skills
	return sk != null and sk.get_level(&"pickpocket") >= 25


static func can_lift_worn(player: Node) -> bool:
	var sk := player.get_node_or_null("Skills") as Skills
	return sk != null and sk.get_level(&"pickpocket") >= 100
