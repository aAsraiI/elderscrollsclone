class_name Locks
extends RefCounted
## Locks on doors (and later chests). A lock has a level from 1 to 100:
##   1-19 Novice, 20-39 Apprentice, 40-59 Adept, 60-79 Expert, 80-99 Master, 100 = only a key opens it.
## Whether a lock is locked is saved in WorldState under "lock/<id>", so a door you picked stays
## open, and a door someone locked stays locked.
##
## Opening a locked door: the right key (KeyRing) always works. Otherwise every try uses up a
## lockpick on a failure; the chance comes from the Security skill against the lock level.
## Picking a lock trains Security. (A lockpicking minigame can replace try_pick later.)

enum PickResult { OPENED, FAILED, NO_PICKS, KEY_ONLY }

const LOCKPICK_PATH := "res://data/misc/lockpick.tres"


static func tier_name(level: int) -> String:
	if level <= 0:
		return "Unlocked"
	if level >= 100:
		return "Requires a key"
	return ["Novice", "Apprentice", "Adept", "Expert", "Master"][clampi(level / 20, 0, 4)]


static func is_locked(lock_id: String, default_locked: bool) -> bool:
	var rec := WorldState.get_record("lock/" + lock_id)
	if rec.has("locked"):
		return bool(rec["locked"])
	return default_locked


static func set_locked(lock_id: String, locked: bool) -> void:
	WorldState.set_record("lock/" + lock_id, {"locked": locked})


## Chance (0..1) that one try opens a lock. security_bonus is the Stats value from the skill.
static func pick_chance(security_level: int, security_bonus: float, lock_level: int) -> float:
	if lock_level >= 100:
		return 0.0
	return clampf(0.55 + float(security_level - lock_level) / 60.0 + security_bonus, 0.05, 0.95)


static func get_lockpick() -> ItemData:
	return load(LOCKPICK_PATH) as ItemData if ResourceLoader.exists(LOCKPICK_PATH) else null


## One attempt at a lock by whoever owns `inventory` (the player). Breaks a lockpick on a failure,
## trains Security either way (more for a success).
static func try_pick(inventory: Inventory, lock_level: int, rng: RandomNumberGenerator = null) -> PickResult:
	if lock_level >= 100:
		return PickResult.KEY_ONLY
	var pick := get_lockpick()
	if inventory == null or pick == null or not inventory.has_item(pick):
		return PickResult.NO_PICKS
	var owner := inventory.get_parent()
	var skills := owner.get_node_or_null("Skills") as Skills if owner != null else null
	var stats := owner.get_node_or_null("Stats") as Stats if owner != null else null
	var level := skills.get_level(&"security") if skills != null else SkillDatabase.START_LEVEL
	var bonus := stats.get_stat("security_bonus") if stats != null else 0.0
	var roll := rng.randf() if rng != null else randf()
	if roll < pick_chance(level, bonus, lock_level):
		if skills != null:
			skills.add_xp(&"security", 4.0 + float(lock_level) * 0.1)
		return PickResult.OPENED
	inventory.remove_item(pick, 1)
	if skills != null:
		skills.add_xp(&"security", 1.0)
	return PickResult.FAILED


## Short message at the top of the screen (through the save menu's toast)
static func toast(tree: SceneTree, text: String, is_error: bool = false) -> void:
	if tree == null:
		return
	var sm := tree.get_first_node_in_group("save_manager") as SaveManager
	if sm != null and sm.menu != null:
		sm.menu.show_toast(text, is_error)
