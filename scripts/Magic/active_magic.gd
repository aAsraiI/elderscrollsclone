class_name ActiveMagic
extends Node
## The magic effects on one creature (the player or any Enemy): spells that hit it, potions it drank,
## poisons on a blade that cut it, the food it ate. Added automatically (player.gd and Enemy).
## Found from the body with ActiveMagic.of(body).
##
## Effects come in as lists of {"id", "mag", "dur"} (see MagicEffects):
##   instant with dur 0   happens at once (damage, healing)
##   instant with dur > 0 happens a bit every half second (burning, regeneration, poison)
##   buff                 a Stats modifier for the duration (fortify, resist, weakness, shield)
##   control              paralyze / calm / fear / frenzy / charm / soul trap
##   special              light, invisibility, summons... (summons and bound weapons go through
##                        the creature's SpellCaster)
## Harmful effects from someone else can be absorbed (Spell Absorption), reflected (Reflect) and
## weakened by Resist Magic; elemental damage is weakened by the matching resistance instead
## (MeleeCombat.take_damage does that part).

signal changed
## A short message for the HUD ("Resisted", "Absorbed"...)
signal notice(text: String, color: Color)

const TICK := 0.5
const SOURCE_PREFIX := "magic_"
## Groups: where an effect came from. Food replaces food; the rest stack.
const SAVED_GROUPS := ["spell", "potion", "food", "enchant", "poison"]

var host: Node3D
var stats: Stats
var combat: MeleeCombat
var enemy: Enemy
var is_player := false
## Each: {"uid", "id", "mag", "dur", "left", "group", "source", "caster": WeakRef, "acc", "end": Callable}
var effects: Array[Dictionary] = []

var _uid := 1
var _tick := 0.0


static func of(node: Object) -> ActiveMagic:
	if node == null or not is_instance_valid(node) or not node.has_meta("magic"):
		return null
	var m: Variant = node.get_meta("magic")
	return m as ActiveMagic if is_instance_valid(m) else null


static func attach(body: Node3D) -> ActiveMagic:
	var existing := body.get_node_or_null("ActiveMagic") as ActiveMagic
	if existing != null:
		return existing
	var m := ActiveMagic.new()
	m.name = "ActiveMagic"
	body.add_child(m)
	return m


func _ready() -> void:
	host = get_parent() as Node3D
	stats = host.get_node_or_null("Stats") as Stats
	combat = host.get_node_or_null("MeleeCombat") as MeleeCombat
	enemy = host as Enemy
	is_player = host.is_in_group("player")
	host.set_meta("magic", self)
	if stats != null:
		stats.died.connect(_on_died)


# ---------------------------------------------------------------- applying

## Puts a list of effects on this creature. power multiplies the magnitudes (skill, potency).
## group: "spell", "potion", "food", "poison", "enchant". Returns how many took hold.
func apply_list(list: Array, caster: Node = null, source: String = "", group: String = "spell", power: float = 1.0) -> int:
	if stats == null or stats.is_dead:
		return 0
	if group == "food":
		remove_group("food")
	var landed := 0
	for e in list:
		if apply_one(e, caster, source, group, power):
			landed += 1
	if landed > 0:
		changed.emit()
	return landed


func apply_one(e: Dictionary, caster: Node, source: String, group: String, power: float = 1.0, may_reflect: bool = true) -> bool:
	var id := StringName(e.get("id", ""))
	var d := MagicEffects.get_def(id)
	if d.is_empty() or stats == null or stats.is_dead:
		return false
	var mag := float(e.get("mag", 0.0)) * (power if d["mag"] else 1.0)
	var dur := float(e.get("dur", 0.0))
	var foreign := caster != null and is_instance_valid(caster) and caster != host
	if d["harm"] and foreign and group != "food":
		# Spell Absorption: the spell is soaked up as magicka
		if group == "spell" and randf() < clampf(stats.get_stat("spell_absorb"), 0.0, MagicEffects.MAX_REFLECT):
			stats.modify_vital("magicka", maxf(mag, 10.0))
			notice.emit("Absorbed", Color(0.5, 0.8, 1.0))
			return false
		# Reflect: it goes back to whoever cast it
		if may_reflect and group == "spell" and randf() < clampf(stats.get_stat("reflect"), 0.0, MagicEffects.MAX_REFLECT):
			var back := ActiveMagic.of(caster)
			if back != null:
				notice.emit("Reflected", Color(0.8, 0.6, 1.0))
				back.apply_one(e, host, source, group, power, false)
				return false
		if d["element"] == &"":
			var resist := clampf(stats.get_stat("resist_magic"), -1.0, MagicEffects.MAX_RESIST)
			mag *= 1.0 - resist
			dur *= 1.0 - maxf(resist, 0.0) * 0.5
		_provoke(caster)
	match int(d["kind"]):
		MagicEffects.Kind.INSTANT:
			if dur <= 0.0:
				_instant(d, mag, caster, false)
				return true
			_add_fx(id, mag, dur, group, source, caster)
			return true
		MagicEffects.Kind.BUFF:
			mag = minf(mag, float(d["max"]))
			var fx := _add_fx(id, mag, maxf(dur, 1.0), group, source, caster)
			stats.add_modifiers(SOURCE_PREFIX + str(fx["uid"]), {String(d["stat"]): mag * float(d["per"])})
			return true
		MagicEffects.Kind.CONTROL:
			return _control(d, mag, minf(maxf(dur, 1.0), float(d["max_dur"])), caster, group, source)
		MagicEffects.Kind.SPECIAL:
			return _special(d, mag, dur, caster, group, source)
	return false


func _add_fx(id: StringName, mag: float, dur: float, group: String, source: String, caster: Node) -> Dictionary:
	var fx := {
		"uid": _uid, "id": id, "mag": mag, "dur": dur, "left": dur, "group": group, "source": source,
		"caster": weakref(caster) if caster != null else null, "acc": 0.0, "end": Callable(),
	}
	_uid += 1
	effects.append(fx)
	return fx


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if effects.is_empty():
		return
	_tick += delta
	var ticking := _tick >= TICK
	if ticking:
		_tick -= TICK
	var any_ended := false
	for i in range(effects.size() - 1, -1, -1):
		if i >= effects.size():
			continue
		var fx := effects[i]
		var step := minf(delta, float(fx["left"]))
		fx["left"] = float(fx["left"]) - delta
		var d := MagicEffects.get_def(fx["id"])
		if int(d.get("kind", -1)) == MagicEffects.Kind.INSTANT:
			fx["acc"] = float(fx["acc"]) + step
			if ticking or float(fx["left"]) <= 0.0:
				var amount := float(fx["mag"]) * float(fx["acc"])
				fx["acc"] = 0.0
				var c: WeakRef = fx["caster"]
				_instant(d, amount, c.get_ref() if c != null else null, true)
				if stats == null or stats.is_dead:
					return
		if float(fx["left"]) <= 0.0 and i < effects.size() and effects[i] == fx:
			_end_at(i)
			any_ended = true
	if any_ended:
		changed.emit()


# ---------------------------------------------------------------- the kinds

func _instant(d: Dictionary, amount: float, caster: Node, dot: bool) -> void:
	if amount <= 0.0:
		return
	var vital: String = d["vital"]
	var absorb: String = d["absorb"]
	if not d["harm"]:
		stats.modify_vital(vital if vital != "" else "health", amount)
		return
	var taken := amount
	if vital == "health" or d["element"] != &"":
		taken = _hurt(amount, d["element"] if d["element"] != &"" else &"magic", caster, dot)
	else:
		var before: float = stats.get(vital) if vital != "" else 0.0
		stats.modify_vital(vital, -amount)
		taken = before - float(stats.get(vital))
	# Element side effects
	match d["element"]:
		&"frost":
			stats.modify_vital("stamina", -amount * 0.5)
			if not dot:
				_frost_slow()
		&"shock":
			stats.modify_vital("magicka", -amount * 0.5)
	if absorb != "" and caster != null and is_instance_valid(caster):
		var cm := ActiveMagic.of(caster)
		if cm != null and cm.stats != null:
			cm.stats.modify_vital(absorb, maxf(taken, 0.0))


# Health damage goes through MeleeCombat like a weapon hit, so blocking, resistances, the hit
# reaction, the damage number and death all work the same way
func _hurt(amount: float, element: StringName, caster: Node, dot: bool) -> float:
	if combat == null:
		var before := stats.health
		stats.modify_vital("health", -amount)
		return before - stats.health
	var info := DamageInfo.new(amount, caster if caster != null and is_instance_valid(caster) else null, &"magic")
	info.element = element
	info.dot = dot
	info.parryable = false
	info.poise_damage = 0.0 if dot else amount * 0.6
	info.hit_position = host.global_position + Vector3.UP * 1.2
	if caster is Node3D and is_instance_valid(caster):
		info.direction = (host.global_position - (caster as Node3D).global_position).normalized()
	var final := combat.take_damage(info)
	MagicHit.after_hit(caster, host, info)
	return final


func _frost_slow() -> void:
	for fx in effects:
		if fx["id"] == &"slow" and fx["source"] == "_frost":
			fx["left"] = 2.0
			return
	var fx := _add_fx(&"slow", 25.0, 2.0, "spell", "_frost", null)
	stats.add_modifiers(SOURCE_PREFIX + str(fx["uid"]), {"move_speed_mult": -0.25})


func _control(d: Dictionary, mag: float, dur: float, caster: Node, group: String, source: String) -> bool:
	var id: StringName = d["id"]
	# Mind spells only work on creatures up to their magnitude's level
	if id in [&"calm", &"fear", &"frenzy"]:
		if enemy == null or enemy.level > roundi(mag):
			notice.emit("Resisted", Color(0.8, 0.8, 0.8))
			return false
	var fx := _add_fx(id, mag, dur, group, source, caster)
	match id:
		&"paralyze":
			if combat != null:
				combat.stun(dur)
			if enemy != null:
				enemy.paralyze(dur)
			elif is_player:
				host.set_meta("paralyzed_until", Time.get_ticks_msec() + int(dur * 1000.0))
			fx["end"] = func() -> void:
				if is_instance_valid(host) and host.has_meta("paralyzed_until"):
					host.remove_meta("paralyzed_until")
		&"calm":
			enemy.calm(dur)
		&"fear":
			enemy.frighten(caster as Node3D, dur)
		&"frenzy":
			enemy.frenzy(dur)
		&"charm":
			host.set_meta("charm", roundi(mag))
			fx["end"] = func() -> void:
				if is_instance_valid(host):
					host.remove_meta("charm")
		&"soul_trap":
			pass  # checked when the creature dies, see _on_died
	return true


func _special(d: Dictionary, mag: float, dur: float, caster: Node, group: String, source: String) -> bool:
	var id: StringName = d["id"]
	match id:
		&"cure_poison":
			for i in range(effects.size() - 1, -1, -1):
				if effects[i]["id"] == &"poison_damage":
					_end_at(i)
			notice.emit("Poison cured", Color(0.5, 1.0, 0.5))
			return true
		&"cure_disease":
			var aff := host.get_node_or_null("Afflictions") as Afflictions
			if aff != null and aff.cure_diseases() > 0:
				notice.emit("Disease cured", Color(0.5, 1.0, 0.5))
			return true
		&"dispel":
			for i in range(effects.size() - 1, -1, -1):
				var g: String = effects[i]["group"]
				if (g == "spell" or g == "poison") and float(effects[i]["mag"]) <= mag + 0.5:
					_end_at(i)
			return true
	if dur <= 0.0 and not id in [&"mark", &"recall", &"open_lock", &"reanimate"]:
		dur = 30.0
	# Summons, bound weapons, Mark and Recall need the caster's hands: the SpellCaster does them
	var caster_node := host.get_node_or_null("SpellCaster") as SpellCaster
	if id in [&"mark", &"recall", &"reanimate", &"open_lock"] or String(id).begins_with("summon_") or String(id).begins_with("bound_"):
		if caster_node == null:
			return false
		var end: Variant = caster_node.start_special(id, mag, dur)
		if end is bool:
			return end
		var fx := _add_fx(id, mag, dur, group, source, caster)
		fx["end"] = end
		return true
	var fx := _add_fx(id, mag, maxf(dur, 1.0), group, source, caster)
	var key := SOURCE_PREFIX + str(fx["uid"])
	match id:
		&"invisibility":
			host.set_meta("invisible", true)
			fx["end"] = func() -> void:
				if is_instance_valid(host) and not _has_other(&"invisibility", fx):
					host.remove_meta("invisible")
		&"muffle":
			stats.add_modifiers(key, {"noise_mult": -0.8})
		&"slowfall":
			stats.add_modifiers(key, {"fall_mult": -0.75})
		&"telekinesis":
			host.set_meta("telekinesis", true)
			fx["end"] = func() -> void:
				if is_instance_valid(host) and not _has_other(&"telekinesis", fx):
					host.remove_meta("telekinesis")
		&"night_eye":
			host.set_meta("night_eye", true)
			fx["end"] = func() -> void:
				if is_instance_valid(host) and not _has_other(&"night_eye", fx):
					host.remove_meta("night_eye")
		&"light":
			var lamp := OmniLight3D.new()
			lamp.name = "MagicLight%d" % fx["uid"]
			lamp.light_color = Color(0.85, 0.9, 1.0)
			lamp.light_energy = 1.4
			lamp.omni_range = clampf(mag, 4.0, 30.0)
			lamp.shadow_enabled = false
			lamp.position = Vector3(0.0, 2.2, 0.0)
			host.add_child(lamp)
			fx["end"] = func() -> void:
				if is_instance_valid(lamp):
					lamp.queue_free()
		&"detect_life":
			var det := DetectLife.new()
			det.radius = mag
			host.add_child(det)
			fx["end"] = func() -> void:
				if is_instance_valid(det):
					det.queue_free()
	return true


func _has_other(id: StringName, except: Dictionary) -> bool:
	for fx in effects:
		if fx["id"] == id and fx != except:
			return true
	return false


# Hit by a hostile spell: it notices, gets angry, or runs (like being hit by a weapon)
func _provoke(caster: Node) -> void:
	if enemy == null or caster == null or not is_instance_valid(caster):
		return
	enemy.on_hostile_magic(caster as Node3D)


# ---------------------------------------------------------------- ending

func _end_at(index: int) -> void:
	var fx := effects[index]
	effects.remove_at(index)
	if stats != null:
		stats.remove_modifiers(SOURCE_PREFIX + str(fx["uid"]))
	var end: Callable = fx["end"]
	if end.is_valid():
		end.call()


func remove_group(group: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i]["group"] == group:
			_end_at(i)
	changed.emit()


func remove_effect(id: StringName) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i]["id"] == id:
			_end_at(i)
	changed.emit()


func clear() -> void:
	for i in range(effects.size() - 1, -1, -1):
		_end_at(i)
	changed.emit()


func has_effect(id: StringName) -> bool:
	for fx in effects:
		if fx["id"] == id:
			return true
	return false


func get_effect(id: StringName) -> Dictionary:
	for fx in effects:
		if fx["id"] == id:
			return fx
	return {}


func _on_died() -> void:
	# Soul Trap: the soul of a creature that dies inside it fills the caster's soul gem
	var trap := get_effect(&"soul_trap")
	if not trap.is_empty() and enemy != null:
		var c: WeakRef = trap["caster"]
		var caster: Node = c.get_ref() if c != null else null
		if caster != null and is_instance_valid(caster):
			SoulGems.capture(caster, enemy)
	clear()


# ---------------------------------------------------------------- saving (the player's)

func to_dict() -> Dictionary:
	var out: Array = []
	for fx in effects:
		var id: StringName = fx["id"]
		if not SAVED_GROUPS.has(fx["group"]) or String(id).begins_with("summon_") or String(id).begins_with("bound_") or fx["source"] == "_frost":
			continue
		out.append({"id": String(id), "mag": fx["mag"], "left": fx["left"], "group": fx["group"], "source": fx["source"]})
	return {"effects": out}


func from_dict(data: Dictionary) -> void:
	clear()
	for e in data.get("effects", []):
		apply_one({"id": StringName(e.get("id", "")), "mag": float(e.get("mag", 0.0)), "dur": maxf(float(e.get("left", 1.0)), 0.5)},
			null, String(e.get("source", "")), String(e.get("group", "spell")), 1.0, false)
	changed.emit()
