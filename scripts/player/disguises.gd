class_name Disguises
extends RefCounted
## Alpha 1.29.2: disguises. Wear a faction's clothes (Bandit Leathers, Ash Cult Robes, a Smuggler's
## Coat) and its members take you for one of their own: they don't come for you. Until someone
## looks closely: one of them within LOOK_RANGE who can see you for LOOK_SECONDS knows you, and
## the whole faction is on to you for BLOWN_SECONDS. Attacking one of them gives you away at once.
## Disguises come off bandits, cultists and smugglers, and the Thieves Guild fences sell them.

const LOOK_RANGE := 3.5
const LOOK_SECONDS := 4.0
const BLOWN_SECONDS := 120.0


## The faction the player is dressed as ("" = none)
static func wearing(player: Node) -> String:
	var eq := player.get_node_or_null("Equipment") as Equipment if player != null else null
	if eq == null:
		return ""
	for slot in eq.slots:
		var it: ItemData = eq.slots[slot]
		if it != null and it.disguise_faction != "":
			return it.disguise_faction
	return ""


static func blown(faction: String) -> bool:
	return Time.get_ticks_msec() < int(WorldState.get_record("disguise_blown").get(faction, 0))


static func blow(faction: String, tree: SceneTree = null) -> void:
	var rec: Dictionary = WorldState.get_record("disguise_blown").duplicate()
	var was := blown(faction)
	rec[faction] = Time.get_ticks_msec() + int(BLOWN_SECONDS * 1000.0)
	WorldState.set_record("disguise_blown", rec)
	if not was and tree != null:
		Locks.toast(tree, "Your disguise is seen through!", true)


## Enemy._can_see_target asks: does this member take the player for one of their own?
## Called a few times a second per watcher; counts how long they have looked closely.
static func fools(e: Enemy, player: Node3D) -> bool:
	var f := wearing(player)
	if f == "" or f != CreatureFactions.of(e) or blown(f):
		return false
	if e.has_meta("wronged_by_player"):
		blow(f, e.get_tree())
		return false
	var now := Engine.get_physics_frames()  # game time, not the wall clock
	var dt := clampf(float(now - int(e.get_meta("look_at", now))) / float(Engine.physics_ticks_per_second), 0.0, 0.5)
	e.set_meta("look_at", now)
	var d := e.global_position.distance_to(player.global_position)
	if d < LOOK_RANGE:
		var look := float(e.get_meta("close_look", 0.0)) + dt
		e.set_meta("close_look", look)
		if look >= LOOK_SECONDS:
			blow(f, e.get_tree())
			return false
	elif e.has_meta("close_look"):
		e.set_meta("close_look", maxf(float(e.get_meta("close_look")) - dt, 0.0))
	if not WorldState.has_record("disguise_used"):
		WorldState.set_record("disguise_used", {})
		Achievements.note("disguise")
	return true


## faction -> the disguise's file
const ITEMS := {"bandits": "res://data/clothing/bandit_leathers.tres", "cultists": "res://data/clothing/ash_cult_robes.tres",
	"smugglers": "res://data/clothing/smuggler_coat.tres"}
const DROP_CHANCE := 0.25


## A member you killed may carry the clothes of their faction (Enemy._on_died)
static func maybe_drop(e: Enemy) -> void:
	if e == null or e.inventory == null or e.body_kind != CreatureBody.Kind.HUMANOID:
		return
	var f := CreatureFactions.of(e)
	if not ITEMS.has(f):
		return
	var h := absi((e.spawn_key if e.spawn_key != "" else str(e.get_instance_id()) + "|garb").hash())
	if float(h % 1000) / 1000.0 < DROP_CHANCE and ResourceLoader.exists(ITEMS[f]):
		e.inventory.add_item(load(ITEMS[f]) as ItemData, 1)
