class_name Afflictions
extends Node
## Diseases, vampirism and lycanthropy on the player. Lives under the Player (player.gd adds it).
## Turned off entirely when the World Creation rule "afflictions" is off.
##
## DISEASES  caught from the bite or blow of some creatures (rats, wolves, the dead, crawlers...).
##           Each weakens a stat until cured: a Cure Disease potion or spell, or praying at a shrine.
## VAMPIRISM caught from a vampire (Sanguine Vampiris: you turn after 3 days unless cured).
##   Age:    Fledgling -> Blooded (30 days) -> Elder (90) -> Ancient (240): stronger, faster,
##           harder to kill, with new powers (spells) at each age.
##   Hunger: Sated -> Hungry (24 h without blood) -> Starving (48 h) -> Ravenous (72 h). Hungrier
##           vampires hit harder but burn in the sun; a Ravenous vampire can no longer pass for
##           mortal: villagers who see you raise the alarm and attack.
##   Feeding: F on a sleeping person (once a night each, a crime if someone awake sees it) or on a
##           fresh humanoid corpse (once each). Shift+F fills an Empty Bottle instead (Bottle of
##           Blood, drink later). Vampires can't eat mortal food. Fire burns them worse.
## LYCANTHROPY caught from a werewolf (Sanies Lupinus, 3 days). On the night of the full moon you
##   change whether you want to or not (and now and then on another night). B changes you at will
##   once a day. In beast form you fight with claws, run faster, can't use weapons, spells or items,
##   and can neither rest nor fast travel. F on a corpse devours it: it heals you, keeps you in
##   beast form longer, and every body makes the beast stronger.
## Cures for the curses: a shrine in any temple lifts them for a large offering.

signal changed

const DISEASES := {
	"rattle_fever": {"name": "Rattle Fever", "stats": {"stamina_regen_mult": -0.3}},
	"bone_break_fever": {"name": "Bone Break Fever", "stats": {"max_stamina": -25.0}},
	"rockjoint": {"name": "Rockjoint", "stats": {"damage_pct": -0.1}},
	"ash_cough": {"name": "Ash Cough", "stats": {"max_health": -15.0}},
	"witbane": {"name": "Witbane", "stats": {"max_magicka": -25.0}},
	"swamp_rot": {"name": "Swamp Rot", "stats": {"carry_capacity": -40.0}},
	"sanguine_vampiris": {"name": "Sanguine Vampiris", "stats": {"max_health": -5.0}},
	"sanies_lupinus": {"name": "Sanies Lupinus", "stats": {"max_stamina": -5.0}},
}
## Who carries what, and the chance per hit
const CARRIERS := {
	"giant_rat": ["rattle_fever", 0.12], "wolf": ["rockjoint", 0.06], "skeleton": ["bone_break_fever", 0.06],
	"skeleton_knight": ["bone_break_fever", 0.06], "barrow_wight": ["ash_cough", 0.08], "wight_lord": ["ash_cough", 0.08],
	"crypt_warden": ["ash_cough", 0.06], "deep_crawler": ["witbane", 0.08], "crawler_queen": ["swamp_rot", 0.1],
	"cave_troll": ["swamp_rot", 0.05], "vampire": ["sanguine_vampiris", 0.12], "werewolf": ["sanies_lupinus", 0.12],
}
const INCUBATION_HOURS := 72.0
const VAMPIRE_AGES: Array[String] = ["Fledgling", "Blooded", "Elder", "Ancient"]
const VAMPIRE_AGE_DAYS: Array[int] = [0, 30, 90, 240]
const HUNGER_NAMES: Array[String] = ["Sated", "Hungry", "Starving", "Ravenous"]
const WEREWOLF_TIERS: Array[int] = [0, 5, 15, 30, 60]
const CURSE_COST := 2500
const BEAST_SECONDS := 150.0
const BLOOD := "res://scripts/Resources/Misc/bottle_of_blood.tres"
const BOTTLE := "res://scripts/Resources/Misc/empty_bottle.tres"

var diseases: Dictionary = {}           # id -> hour caught (absolute)
var vampire := false
var vampire_since := 0.0                # absolute hour
var last_fed := 0.0                     # absolute hour
var werewolf := false
var bodies_eaten := 0
var beast := false
var beast_forced := false
var beast_left := 0.0
var beast_used_day := -1
var _forced_night := -1
var _rolled_night := -1
var _tick := 0.0
var _player: CharacterBody3D
var _stats: Stats
var _alarm_cd := 0.0
var _stored_gear: Dictionary = {}
var _tint: CanvasLayer


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_stats = _player.get_node_or_null("Stats") as Stats
	var combat := _player.get_node_or_null("MeleeCombat") as MeleeCombat
	if combat != null:
		combat.damaged.connect(_on_damaged)


static func of(tree: SceneTree) -> Afflictions:
	var p := tree.get_first_node_in_group("player") if tree != null else null
	return p.get_node_or_null("Afflictions") as Afflictions if p != null else null


## Hours since the game began (day 1, 00:00)
func now() -> float:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	return float(clock.day) * 24.0 + clock.hour if clock != null else 0.0


# ---------------------------------------------------------------- catching

func _on_damaged(info: DamageInfo, amount: float) -> void:
	if not GameRules.afflictions() or amount <= 0.0 or info.source == null or not is_instance_valid(info.source):
		return
	var e := info.source as Enemy
	if e == null or not CARRIERS.has(e.enemy_id):
		return
	var c: Array = CARRIERS[e.enemy_id]
	var resist := clampf(_stats.get_stat("resist_disease"), 0.0, 1.0)
	if randf() < float(c[1]) * (1.0 - resist):
		catch(String(c[0]))


func catch(id: String) -> void:
	if diseases.has(id) or not DISEASES.has(id):
		return
	if (id == "sanguine_vampiris" and (vampire or werewolf)) or (id == "sanies_lupinus" and (werewolf or vampire)):
		return
	if vampire or werewolf:
		return  # the cursed don't fall ill
	diseases[id] = now()
	_apply_disease_mods()
	Locks.toast(get_tree(), "You have contracted %s" % DISEASES[id]["name"], true)
	changed.emit()


func cure_diseases() -> int:
	var n := diseases.size()
	diseases.clear()
	_apply_disease_mods()
	changed.emit()
	return n


func _apply_disease_mods() -> void:
	var mods := {}
	for id in diseases:
		for k in DISEASES[id]["stats"]:
			mods[k] = float(mods.get(k, 0.0)) + float(DISEASES[id]["stats"][k])
	if mods.is_empty():
		_stats.remove_modifiers("disease")
	else:
		_stats.add_modifiers("disease", mods)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_alarm_cd -= delta
	if beast:
		_tick_beast(delta)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	var t := now()
	# Incubating curses
	for id in ["sanguine_vampiris", "sanies_lupinus"]:
		if diseases.has(id) and t - float(diseases[id]) >= INCUBATION_HOURS:
			diseases.erase(id)
			_apply_disease_mods()
			if id == "sanguine_vampiris":
				become_vampire()
			else:
				become_werewolf()
	if vampire:
		_tick_vampire(t)
	if werewolf:
		_tick_werewolf()


# ---------------------------------------------------------------- vampires

func become_vampire() -> void:
	if vampire:
		return
	if werewolf:
		cure_werewolf()
	vampire = true
	vampire_since = now()
	last_fed = now()
	cure_diseases()
	_grant_vampire_spells()
	_apply_vampire_mods()
	Locks.toast(get_tree(), "You have become a vampire. You hunger for blood.", true)
	changed.emit()


func cure_vampire() -> void:
	if not vampire:
		return
	vampire = false
	_stats.remove_modifiers("vampire")
	_stats.remove_modifiers("vampire_sun")
	var book := _player.get_node_or_null("Spellbook") as Spellbook
	if book != null:
		for id in ["vampiric_drain", "vampires_sight", "mesmerize", "embrace_of_shadows"]:
			book.forget(id)
	changed.emit()


func vampire_age() -> int:
	var days := (now() - vampire_since) / 24.0
	var age := 0
	for i in VAMPIRE_AGE_DAYS.size():
		if days >= float(VAMPIRE_AGE_DAYS[i]):
			age = i
	return age


func hunger_stage() -> int:
	if not vampire:
		return 0
	return clampi(int((now() - last_fed) / 24.0), 0, 3)


func _grant_vampire_spells() -> void:
	var book := _player.get_node_or_null("Spellbook") as Spellbook
	if book == null:
		return
	var age := vampire_age()
	book.learn(SpellCatalog.get_spell("vampiric_drain"), true)
	book.learn(SpellCatalog.get_spell("vampires_sight"), true)
	if age >= 2:
		book.learn(SpellCatalog.get_spell("mesmerize"), age == 2)
	if age >= 3:
		book.learn(SpellCatalog.get_spell("embrace_of_shadows"), age == 3)


var _last_vamp_key := ""


func _apply_vampire_mods() -> void:
	var age := vampire_age()
	var hunger := hunger_stage()
	var key := "%d|%d" % [age, hunger]
	if key == _last_vamp_key:
		return
	if _last_vamp_key != "" and int(_last_vamp_key.get_slice("|", 0)) < age:
		Locks.toast(get_tree(), "Your vampirism grows stronger: you are now %s" % VAMPIRE_AGES[age])
		_grant_vampire_spells()
	if _last_vamp_key != "" and int(_last_vamp_key.get_slice("|", 1)) < hunger:
		Locks.toast(get_tree(), "You are %s for blood" % HUNGER_NAMES[hunger].to_lower(), hunger >= 2)
	_last_vamp_key = key
	_stats.add_modifiers("vampire", {
		"resist_frost": 0.3 + 0.1 * age, "resist_poison": 1.0, "resist_disease": 1.0,
		"resist_fire": -0.25 - 0.1 * hunger, "damage_pct": 0.05 * age + 0.06 * hunger,
		"move_speed_mult": 0.03 * age, "max_health": 15.0 * age, "max_magicka": 15.0 * age,
		"sneak_attack_bonus": 0.1 + 0.05 * age, "night_eye": 1.0,
	})


func _tick_vampire(t: float) -> void:
	_apply_vampire_mods()
	var hunger := hunger_stage()
	# The sun: no regeneration, and the starving burn
	var sun := _in_sunlight()
	if sun:
		_stats.add_modifiers("vampire_sun", {"health_regen": -_stats.get_stat("health_regen") - 0.0001, "max_stamina": -15.0, "max_magicka": -15.0})
		if hunger >= 2:
			_stats.modify_vital("health", -float(hunger - 1) * 1.5)
	else:
		_stats.remove_modifiers("vampire_sun")
	if hunger >= 3 and _alarm_cd <= 0.0:
		_raise_alarm("A vampire! Kill it!")


func _in_sunlight() -> bool:
	var dm := get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		return false
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock == null or clock.get_daylight() < 0.45:
		return false
	var w := Weather.get_instance(get_tree())
	return w == null or not w.is_precipitating()


# Townsfolk who can see you turn on you (vampire gone ravenous, a werewolf in the street)
func _raise_alarm(shout: String) -> void:
	_alarm_cd = 2.0
	var any := false
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or e.has_meta("player_ally") or e.disposition == Enemy.Disposition.HOSTILE:
			continue
		if e.has_meta("asleep") or e.global_position.distance_to(_player.global_position) > 18.0 or not _sees(e):
			continue
		any = true
		e.disposition = Enemy.Disposition.HOSTILE
		e.set_meta("wronged_by_player", false)
		e.aggro(_player)
	if any:
		Locks.toast(get_tree(), shout, true)


func _sees(e: Enemy) -> bool:
	var q := PhysicsRayQueryParameters3D.create(e.head.global_position, _player.global_position + Vector3.UP * 1.4, 1, [e.get_rid(), _player.get_rid()])
	return _player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Food is no use to a vampire (blood bottles are drunk through here instead)
func refuses_food(item: ItemData) -> bool:
	if item == null:
		return false
	if item.resource_path == BLOOD or String(item.id) == "bottle_of_blood":
		return false
	return vampire and item.item_type == ItemData.ItemType.CONSUMABLE and item.effect_group == "food"


func drink_blood() -> bool:
	if not vampire:
		Locks.toast(get_tree(), "The thought turns your stomach", true)
		return false
	_fed(25.0)
	return true


func _fed(heal: float) -> void:
	last_fed = now()
	_stats.modify_vital("health", heal)
	_apply_vampire_mods()
	changed.emit()


# ---------------------------------------------------------------- feeding (F) and bottling (Shift+F)

## What F would do to this thing ("" = nothing): shown in the interaction prompt
func feed_prompt(target: Object) -> String:
	var kind := _feed_kind(target)
	if kind == "":
		return ""
	if beast:
		return "F: Devour"
	var bottle := ""
	var inv := _player.get_node_or_null("Inventory") as Inventory
	var empty := load(BOTTLE) as ItemData if ResourceLoader.exists(BOTTLE) else null
	if inv != null and empty != null and inv.has_item(empty):
		bottle = "   Shift+F: Fill a bottle"
	return ("F: Feed" if vampire else "") + bottle if (vampire or bottle != "") else ""


# "sleeper", "corpse" or ""
func _feed_kind(target: Object) -> String:
	var e: Enemy = null
	if target is ContainerComponent:
		e = (target as ContainerComponent).get_parent() as Enemy
	elif target is NpcTalk:
		e = (target as NpcTalk).get_parent() as Enemy
	elif target is Enemy:
		e = target as Enemy
	if e == null or e.body_kind != CreatureBody.Kind.HUMANOID or e.enemy_id.contains("skeleton") or e.enemy_id.contains("wight") or e.enemy_id == "vampire":
		return ""
	if e.is_dead():
		if e.has_meta("drained") or (beast and e.has_meta("devoured")):
			return ""
		return "corpse"
	if e.has_meta("asleep") and not e.has_meta("summoned"):
		var night := (get_tree().get_first_node_in_group("world_clock") as WorldClock).get_night_index()
		if int(WorldState.get_record("blood/" + String(e.get_meta("npc_id", e.name))).get("night", -1)) == night:
			return ""
		return "sleeper" if not beast else ""
	return ""


func _victim(target: Object) -> Enemy:
	if target is ContainerComponent:
		return (target as ContainerComponent).get_parent() as Enemy
	if target is NpcTalk:
		return (target as NpcTalk).get_parent() as Enemy
	return target as Enemy


## F (bottle = Shift+F). Returns true if something happened.
func feed(target: Object, bottle: bool) -> bool:
	var kind := _feed_kind(target)
	if kind == "":
		return false
	var e := _victim(target)
	if beast:
		if kind != "corpse":
			return false
		e.set_meta("devoured", true)
		bodies_eaten += 1
		_stats.modify_vital("health", 60.0)
		beast_left += 30.0
		_apply_beast_mods()
		Locks.toast(get_tree(), "You devour the body (%d eaten)" % bodies_eaten)
		changed.emit()
		return true
	var inv := _player.get_node_or_null("Inventory") as Inventory
	if bottle:
		var empty := load(BOTTLE) as ItemData
		if inv == null or empty == null or not inv.has_item(empty):
			return false
		inv.remove_item(empty, 1)
		inv.add_item(load(BLOOD) as ItemData, 1)
		Locks.toast(get_tree(), "You fill a bottle with blood")
	elif vampire:
		_fed(40.0 if kind == "sleeper" else 25.0)
		Locks.toast(get_tree(), "You feed. The hunger fades.")
	else:
		return false
	if kind == "corpse":
		e.set_meta("drained", true)
	else:
		var night := (get_tree().get_first_node_in_group("world_clock") as WorldClock).get_night_index()
		WorldState.set_record("blood/" + String(e.get_meta("npc_id", e.name)), {"night": night})
		_witnessed(e)
	return true


# Feeding on a sleeper is an assault if anyone awake sees it
func _witnessed(victim: Enemy) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == victim or e.is_dead() or e.has_meta("asleep") or e.disposition == Enemy.Disposition.HOSTILE:
			continue
		if e.global_position.distance_to(_player.global_position) < 12.0 and _sees(e):
			var crime := get_tree().get_first_node_in_group("crime")
			if crime != null:
				crime.on_player_hurt(victim, false)
			return


# ---------------------------------------------------------------- werewolves

func become_werewolf() -> void:
	if werewolf:
		return
	if vampire:
		cure_vampire()
	werewolf = true
	cure_diseases()
	_stats.add_modifiers("lycanthrope", {"resist_disease": 1.0, "max_stamina": 10.0})
	Locks.toast(get_tree(), "The blood of the beast runs in you. Press B to change.", true)
	changed.emit()


func cure_werewolf() -> void:
	if not werewolf:
		return
	if beast:
		end_beast_form()
	werewolf = false
	_stats.remove_modifiers("lycanthrope")
	changed.emit()


func beast_tier() -> int:
	var t := 0
	for i in WEREWOLF_TIERS.size():
		if bodies_eaten >= WEREWOLF_TIERS[i]:
			t = i
	return t


## No resting, waiting or fast travel during a forced change (or in beast form at all)
func blocks_rest() -> bool:
	return beast


func _tick_werewolf() -> void:
	var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
	if clock == null:
		return
	var night := clock.get_night_index()
	var late := clock.hour >= 21.0 or clock.hour < 5.0
	if beast or not late:
		return
	if clock.is_full_moon_night() and _forced_night != night:
		_forced_night = night
		start_beast_form(true)
		Locks.toast(get_tree(), "The full moon takes you!", true)
	elif _rolled_night != night:
		_rolled_night = night
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d|beast" % night).hash()
		if rng.randf() < 0.04:
			_forced_night = night
			start_beast_form(true)
			Locks.toast(get_tree(), "The beast breaks free!", true)


func toggle_beast_form() -> void:
	if beast:
		if beast_forced:
			Locks.toast(get_tree(), "The moon will not let you go", true)
		else:
			end_beast_form()
		return
	var today := (get_tree().get_first_node_in_group("world_clock") as WorldClock).day
	if beast_used_day == today:
		Locks.toast(get_tree(), "You can change only once a day", true)
		return
	beast_used_day = today
	start_beast_form(false)


func start_beast_form(forced: bool) -> void:
	if beast or not werewolf:
		return
	beast = true
	beast_forced = forced
	beast_left = BEAST_SECONDS
	# Weapons and spells are dropped from the hands (put back when you change back)
	var eq := _player.get_node_or_null("Equipment") as Equipment
	var book := _player.get_node_or_null("Spellbook") as Spellbook
	_stored_gear = {}
	if eq != null:
		for slot in [ItemData.EquipSlot.MAIN_HAND, ItemData.EquipSlot.OFF_HAND]:
			var it: ItemData = eq.get_equipped(slot)
			if it != null:
				_stored_gear[slot] = it
				eq.unequip(slot)
	if book != null and book.equipped_id != "":
		_stored_gear["spell"] = book.equipped_id
		book.unequip_spell()
	_player.set_meta("beast_form", true)
	_apply_beast_mods()
	_stats.modify_vital("health", _stats.get_stat("max_health"))
	_show_tint(true)
	SpellFX.burst(_player, _player.global_position + Vector3.UP, 2.0, Color(0.5, 0.1, 0.1))
	changed.emit()


func _apply_beast_mods() -> void:
	var t := beast_tier()
	_stats.add_modifiers("beast", {"max_health": 80.0 + 30.0 * t, "unarmed_damage": 22.0 + 10.0 * t, "move_speed_mult": 0.35,
		"armor": 30.0 + 8.0 * t, "max_stamina": 60.0, "stamina_regen_mult": 0.5, "resist_frost": 0.3})


func end_beast_form() -> void:
	if not beast:
		return
	beast = false
	beast_forced = false
	_player.remove_meta("beast_form")
	_stats.remove_modifiers("beast")
	var eq := _player.get_node_or_null("Equipment") as Equipment
	for slot in _stored_gear:
		if slot is int and eq != null:
			eq.equip(_stored_gear[slot])
	if _stored_gear.has("spell"):
		var book := _player.get_node_or_null("Spellbook") as Spellbook
		if book != null:
			book.equip_spell(String(_stored_gear["spell"]))
	_stored_gear = {}
	_show_tint(false)
	Locks.toast(get_tree(), "You change back")
	changed.emit()


func _tick_beast(delta: float) -> void:
	if _alarm_cd <= 0.0:
		_raise_alarm("A werewolf!")
	if beast_forced:
		var clock := get_tree().get_first_node_in_group("world_clock") as WorldClock
		if clock != null and clock.hour >= 6.0 and clock.hour < 12.0:
			end_beast_form()
		return
	beast_left -= delta
	if beast_left <= 0.0:
		end_beast_form()


func _show_tint(on: bool) -> void:
	if on and _tint == null:
		_tint = CanvasLayer.new()
		_tint.layer = 1
		var r := ColorRect.new()
		r.color = Color(0.5, 0.05, 0.02, 0.18)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tint.add_child(r)
		add_child(_tint)
	elif not on and _tint != null:
		_tint.queue_free()
		_tint = null


# ---------------------------------------------------------------- text and saving

## Lines for the HUD
func status_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for id in diseases:
		out.append("✖ " + String(DISEASES[id]["name"]))
	if vampire:
		out.append("Vampire (%s), %s" % [VAMPIRE_AGES[vampire_age()], HUNGER_NAMES[hunger_stage()]])
	if werewolf:
		out.append("Beast form %s" % ("(until dawn)" if beast_forced else "%ds" % int(beast_left)) if beast else "Werewolf (%d bodies)" % bodies_eaten)
	return out


func to_dict() -> Dictionary:
	return {"diseases": diseases.duplicate(), "vampire": vampire, "vampire_since": vampire_since, "last_fed": last_fed,
		"werewolf": werewolf, "bodies": bodies_eaten, "beast_used_day": beast_used_day, "forced_night": _forced_night}


func from_dict(d: Dictionary) -> void:
	if beast:
		end_beast_form()
	diseases = (d.get("diseases", {}) as Dictionary).duplicate()
	_apply_disease_mods()
	vampire = bool(d.get("vampire", false))
	vampire_since = float(d.get("vampire_since", 0.0))
	last_fed = float(d.get("last_fed", 0.0))
	_last_vamp_key = ""
	_stats.remove_modifiers("vampire")
	if vampire:
		_apply_vampire_mods()
	werewolf = bool(d.get("werewolf", false))
	bodies_eaten = int(d.get("bodies", 0))
	beast_used_day = int(d.get("beast_used_day", -1))
	_forced_night = int(d.get("forced_night", -1))
	if werewolf:
		_stats.add_modifiers("lycanthrope", {"resist_disease": 1.0, "max_stamina": 10.0})
	else:
		_stats.remove_modifiers("lycanthrope")
	changed.emit()
