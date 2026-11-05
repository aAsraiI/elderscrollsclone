class_name Tutorial
extends Node
## Alpha 1.27: the tutorial lives in the journal (J > Guide), not in pop-ups. The first time
## something comes up (your first fight, first body, first night, first spell...) its Guide page
## comes up there, with a dot and a "Journal Updated" notice (GuideBook). Settings > Interface >
## Tutorial hints turns the notices off; the pages are always there.
## It also checks the achievements (Achievements), a few each second, and listens for the things
## they count that have a signal (parries, sneak attacks, spells, arrows, fast travel).

const BASICS := ["welcome", "menus", "saving", "achievements"]
## Achievements checked per tick (one tick a second): the whole list every ~12 s
const CHECKS_PER_TICK := 8

var _check := 2.0
var _player: Node3D
var _next_ach := 0
var _hooked := false


func _ready() -> void:
	_player = get_parent() as Node3D


## The page comes up in the journal (once per character)
func hint(id: String, _old_text: String = "") -> void:
	if GuideBook.come_up(id) and bool(GameSettings.get_value("tutorial")):
		Notices.quest(get_tree(), "Journal Updated", "Guide: " + String(GuideBook.page(id)[2]))


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	for id in BASICS:
		GuideBook.come_up(id)  # quietly: the first pages are there from the start (after a load has filled WorldState)
	if not _hooked:
		_hook()
	_watch()
	_check_achievements()


func _check_achievements() -> void:
	var n := Achievements.LIST.size()
	for i in CHECKS_PER_TICK:
		var a: Array = Achievements.LIST[_next_ach % n]
		_next_ach = (_next_ach + 1) % n
		if Achievements.check(a, get_tree()):
			hint(String(a[4]))  # what you just did has a page: it comes up now if it hadn't


## The counters that come from signals
func _hook() -> void:
	var melee := _player.get_node_or_null("MeleeCombat") as MeleeCombat
	var stealth := _player.get_node_or_null("Stealth")
	var ranged := _player.get_node_or_null("RangedCombat")
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if melee == null or stealth == null or ranged == null or world == null or world.discovery == null:
		return
	_hooked = true
	melee.parried.connect(func(_i: DamageInfo) -> void: Achievements.note("parry"))
	stealth.sneak_attack.connect(func(_v: Node3D, _m: float) -> void: Achievements.note("sneak_attack"))
	ranged.shot.connect(func(_a: Arrow) -> void:
		Achievements.note("shot")
		hint("archery"))
	for c in ["SpellCaster", "SpellCasterRight"]:
		var caster := _player.get_node_or_null(c) as SpellCaster
		if caster != null:
			caster.spell_cast.connect(func(_s: SpellData) -> void: Achievements.note("cast"))
	world.discovery.travelled.connect(func(_p: PlacedPOI, _h: float) -> void: Achievements.note("travel"))
	world.discovery.discovered.connect(func(_p: PlacedPOI) -> void: hint("map"))
	var skills := _player.get_node_or_null("Skills") as Skills
	if skills != null:
		skills.skill_leveled_up.connect(func(id: StringName, l: int) -> void:
			hint("leveling")
			SignatureTrials.on_level(get_tree(), skills, id, l))  # 1.27.4: trials at 50 and 100
		skills.player_leveled_up.connect(func(_l: int) -> void: hint("perks"))


func _watch() -> void:
	var tree := get_tree()
	var stats := _player.get_node_or_null("Stats") as Stats
	if stats != null and stats.health < stats.get_stat("max_health") * 0.4:
		hint("health")
	for n in ActorRegistry.near(_player.global_position, 20.0):
		var e := n as Enemy
		if e != null and e.disposition == Enemy.Disposition.HOSTILE and e.is_alerted() and e.global_position.distance_to(_player.global_position) < 20.0:
			hint("combat")
			break
	if Achievements.count("kill") >= 1:
		hint("foes")
	var book := _player.get_node_or_null("Spellbook") as Spellbook
	if book != null and book.spells.size() > 0:
		hint("magic")
	var clock := tree.get_first_node_in_group("world_clock") as WorldClock
	if clock != null and clock.is_night():
		hint("night")
		hint("rest")
	var dm := tree.get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_in_building() and dm.get_interior_root() != null and not dm.get_interior_root().find_children("*", "CraftingStation", true, false).is_empty():
		hint("crafting")
	if dm != null and dm.is_inside() and not dm.is_in_building():
		hint("dungeons")
		if Achievements.count("dungeon") == 0:
			Achievements.note("dungeon")
	var inv := _player.get_node_or_null("Inventory") as Inventory
	if inv != null and stats != null and inv.get_total_weight() > stats.get_stat("carry_capacity"):
		hint("heavy")
	var stealth := _player.get_node_or_null("Stealth")
	if stealth != null and bool(stealth.get("sneaking")):
		hint("stealth")
	var swim := _player.get_node_or_null("Swimming") as Swimming
	if swim != null and swim.is_swimming():
		hint("swimming")
	if not CrimeManager.bounties().is_empty():
		hint("crime")
	if GameRules.survival():
		var s := _player.get_node_or_null("Survival") as Survival
		if s != null and (s.hunger >= 50.0 or s.cold >= 50.0 or s.fatigue >= 50.0):
			hint("survival")
	var aff := _player.get_node_or_null("Afflictions") as Afflictions
	if aff != null:
		if not aff.diseases.is_empty():
			hint("disease")
		if aff.vampire:
			hint("vampire")
		if aff.werewolf:
			hint("werewolf")
	var skills := _player.get_node_or_null("Skills") as Skills
	if skills != null:
		var lvl := skills.get_player_level()
		if lvl >= 2:
			hint("powers")
		if lvl >= 3:
			hint("guilds")
		if lvl >= 60:
			hint("islands")
	if Homestead.built().size() >= 3:
		hint("raids")
	_watch_world()
	_watch_quests()


## How far out you have been: the level of the land underfoot (the far-island achievements)
func _watch_world() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if wm == null or wm.map == null or (wm.dungeons != null and wm.dungeons.is_inside()):
		return
	var band := wm.map.get_level_band(_player.global_position.x, _player.global_position.z)
	var best := Achievements.count("far_land")
	if int(band.x) > best:
		Achievements.note("far_land", int(band.x) - best)
		if band.x >= 100.0:
			hint("islands")


# Quests, the journal and talking: the first time each comes up
func _watch_quests() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if wm == null:
		return
	var active := QuestLog.all(wm).filter(func(q: Dictionary) -> bool: return q["status"] == "active")
	if not active.is_empty():
		hint("quests")
	if active.any(func(q: Dictionary) -> bool: return q["source"] == "job" and String(q["next"]).begins_with("Report back")):
		hint("report_back")
	if DialogueState.journal().size() >= 5:
		hint("journal_notes")
	for e in ActorRegistry.near(_player.global_position, 6.0):
		if e.talk_name != "" and e.disposition != Enemy.Disposition.HOSTILE:
			hint("talking")
			break
	for id in RealmManager.REALMS:
		if RealmManager.is_open(id):
			hint("realms")
			break
