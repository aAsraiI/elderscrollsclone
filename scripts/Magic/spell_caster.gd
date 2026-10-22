class_name SpellCaster
extends Node
## Casts spells for the player AND for enemy mages. It never reads input: PlayerCombat (right mouse
## button with a spell in the off hand) or Enemy (AI) call begin_cast() / release_cast().
##
## Hold the button to charge (a short moment), let go to cast. Spray spells start at once and
## cost magicka every second while you hold. A cast that you can't pay for fizzles.
## Spell power = 1 + the school's skill bonus + Fortify Spell Power, times the weather (rain
## dampens fire and helps lightning). Casting trains the spell's school (XP = magicka spent).

signal cast_started(spell: SpellData)
signal spell_cast(spell: SpellData)
signal cast_cancelled
## reason: &"magicka", &"stunned", &"invalid"
signal cast_failed(reason: StringName)

const XP_PER_MAGICKA := 0.25
const SPRAY_TICK := 0.2
const PROJECTILE_SPEED := 30.0
const MAX_RUNES := 3

var host: Node3D
var stats: Stats
var skills: Skills
var magic: ActiveMagic
var combat: MeleeCombat
## Where spells come out of (the camera for the player, the head for an enemy)
var aim_origin: Node3D
## Enemies set this: where to aim (null = straight ahead of aim_origin)
var aim_target: Node3D
var is_player := false

var _spell: SpellData
var _charge := 0.0
var _charging := false
var _channeling := false
var _spray_timer := 0.0
var _spray_fx: GPUParticles3D
var _runes: Array[Node] = []
var _summons: Array[Node] = []


func _ready() -> void:
	host = get_parent() as Node3D
	stats = host.get_node_or_null("Stats") as Stats
	skills = host.get_node_or_null("Skills") as Skills
	combat = host.get_node_or_null("MeleeCombat") as MeleeCombat
	magic = ActiveMagic.attach(host)
	is_player = host.is_in_group("player")
	if aim_origin == null:
		aim_origin = host.get_node_or_null("Head/Camera3D") as Node3D
	if aim_origin == null:
		aim_origin = host.get_node_or_null("Head") as Node3D
	if aim_origin == null:
		aim_origin = host


# ---------------------------------------------------------------- public API

## Starts charging (or spraying) a spell. Returns false if it can't be cast at all right now.
func begin_cast(spell: SpellData) -> bool:
	if spell == null or stats == null or stats.is_dead:
		return false
	if combat != null and combat.is_stunned():
		cast_failed.emit(&"stunned")
		return false
	if _charging or _channeling:
		return true
	var cost := get_cost(spell)
	var need := cost * (0.3 if spell.form == SpellData.Form.SPRAY else 1.0)
	if stats.magicka < need:
		cast_failed.emit(&"magicka")
		return false
	_spell = spell
	_charge = 0.0
	if spell.form == SpellData.Form.SPRAY:
		_channeling = true
		_spray_timer = 0.0
		_set_spray_visual(true)
		_break_invisibility()
	else:
		_charging = true
	cast_started.emit(spell)
	return true


## Lets go of the button: a charged spell goes off, a spray stops
func release_cast() -> void:
	if _channeling:
		_stop_channel()
		return
	if not _charging:
		return
	_charging = false
	if _charge < _spell.get_charge_time():
		cast_cancelled.emit()
		return
	_cast_now(_spell)


func cancel() -> void:
	if _channeling:
		_stop_channel()
	if _charging:
		_charging = false
		cast_cancelled.emit()


## Casts right away (enemies, after their own wind-up). Returns false if it fizzled.
func cast_now(spell: SpellData, free: bool = false) -> bool:
	if spell == null or stats == null or stats.is_dead:
		return false
	_spell = spell
	return _cast_now(spell, free)


func is_charging() -> bool:
	return _charging


func is_channeling() -> bool:
	return _channeling


func is_busy() -> bool:
	return _charging or _channeling


## 0..1 while charging (1 = ready to go off)
func get_charge_ratio() -> float:
	if not _charging or _spell == null:
		return 0.0
	return clampf(_charge / maxf(_spell.get_charge_time(), 0.01), 0.0, 1.0)


func get_current_spell() -> SpellData:
	return _spell if is_busy() else null


func get_cost(spell: SpellData) -> float:
	var level := skills.get_level(spell.get_school()) if skills != null else 0
	return spell.get_cost(level)


## Spell strength multiplier for this caster
func get_power(spell: SpellData) -> float:
	var p := 1.0
	if stats != null:
		p += stats.get_stat("spell_power") + stats.get_stat("power_" + String(spell.get_school()))
	if not is_player and host is Enemy:
		p += float((host as Enemy).level) * 0.0  # enemy spells are scaled when they are made
	return maxf(p, 0.1)


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if _charging:
		if combat != null and combat.is_stunned():
			cancel()
			return
		_charge += delta
	if _channeling:
		if stats.is_dead or (combat != null and combat.is_stunned()):
			_stop_channel()
			return
		var cost := get_cost(_spell) * delta
		if stats.magicka < cost:
			_stop_channel()
			cast_failed.emit(&"magicka")
			return
		stats.modify_vital("magicka", -cost)
		_train(_spell, cost)
		_spray_timer -= delta
		if _spray_timer <= 0.0:
			_spray_timer = SPRAY_TICK
			_spray_tick()


func _stop_channel() -> void:
	_channeling = false
	_set_spray_visual(false)
	cast_cancelled.emit()


# ---------------------------------------------------------------- casting

func _cast_now(spell: SpellData, free: bool = false) -> bool:
	var cost := 0.0 if free else get_cost(spell)
	if stats.magicka < cost:
		cast_failed.emit(&"magicka")
		return false
	if spell.validate() != "":
		cast_failed.emit(&"invalid")
		return false
	stats.modify_vital("magicka", -cost)
	_train(spell, cost)
	var power := get_power(spell)
	if spell.form != SpellData.Form.SELF:
		_break_invisibility()
	match spell.form:
		SpellData.Form.SELF:
			_apply_self(spell, power)
		SpellData.Form.TOUCH:
			var hit := _ray(SpellData.TOUCH_RANGE, true)
			if not hit.is_empty():
				apply_at(spell, power, hit.get("collider"), hit["position"])
		SpellData.Form.TARGET:
			SpellProjectile.launch(self, spell, power, _origin(), _aim_dir(), PROJECTILE_SPEED)
		SpellData.Form.BEAM:
			var hit := _ray(SpellData.BEAM_RANGE, true)
			var end := _origin() + _aim_dir() * SpellData.BEAM_RANGE
			if not hit.is_empty():
				end = hit["position"]
				apply_at(spell, power, hit.get("collider"), end)
			SpellFX.beam(host, _origin() + _aim_dir() * 0.6, end, spell.get_color())
		SpellData.Form.RUNE:
			_place_rune(spell, power)
		SpellData.Form.NOVA:
			var center := host.global_position + Vector3.UP * 0.8
			SpellFX.burst(host, center, spell.get_area(), spell.get_color())
			apply_area(spell, power, center, spell.get_area(), null)
	spell_cast.emit(spell)
	return true


# Self: everything lands on the caster (summons and bound weapons start through ActiveMagic)
func _apply_self(spell: SpellData, power: float) -> void:
	magic.apply_list(spell.effects, host, spell.display_name, "spell", power)
	SpellFX.burst(host, host.global_position + Vector3.UP * 1.0, 1.2, spell.get_color())


## A spell arrives at a point, having hit `collider` (may be null = it just went off there):
## the creature hit gets every effect, then the burst (area) hits everyone around who should be hit
func apply_at(spell: SpellData, power: float, collider: Object, point: Vector3) -> void:
	var direct := MagicHit.creature_of(collider)
	var others_list: Array = []
	for e in spell.effects:
		var id := StringName(e["id"])
		if id == &"open_lock":
			_magic_unlock(collider, float(e["mag"]))
		elif id == &"reanimate":
			_reanimate(collider, float(e["mag"]) * power, float(e["dur"]))
		else:
			others_list.append(e)
	if direct != null and direct != host and not others_list.is_empty():
		var m := ActiveMagic.of(direct)
		if m != null and not (m.enemy != null and m.enemy.is_dead()):
			m.apply_list(others_list, host, spell.display_name, "spell", power)
	if spell.get_area() > 0.0 and not others_list.is_empty():
		SpellFX.burst(host, point, spell.get_area(), spell.get_color())
		apply_area(spell, power, point, spell.get_area(), direct, others_list)


## Every creature in the burst: foes for a harmful spell, friends (and you) for a helpful one
func apply_area(spell: SpellData, power: float, center: Vector3, radius: float, skip: Node3D, list: Array = []) -> void:
	if list.is_empty():
		list = spell.effects
	var harmful := spell.is_harmful()
	var exclude: Array = [skip] if skip != null else []
	for c in MagicHit.creatures_in(host.get_world_3d(), center, radius, exclude):
		var ally := MagicHit.friendly(host, c)
		if harmful == ally:
			continue
		var m := ActiveMagic.of(c)
		if m != null:
			m.apply_list(list, host, spell.display_name, "spell", power)


func _spray_tick() -> void:
	var origin := _origin()
	var dir := _aim_dir()
	var hit_bodies: Array[Node3D] = []
	var right := dir.cross(Vector3.UP).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	for yaw in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(yaw)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * SpellData.SPRAY_RANGE, MagicHit.LAYER_WORLD | MagicHit.LAYER_ENEMY, _exclude())
		var hit := host.get_world_3d().direct_space_state.intersect_ray(q)
		var c := MagicHit.creature_of(hit.get("collider")) if not hit.is_empty() else null
		if c != null and c != host and not hit_bodies.has(c):
			hit_bodies.append(c)
	if hit_bodies.is_empty():
		return
	var power := get_power(_spell)
	# Spray magnitudes are per second: each tick lands a fifth of it
	var tick_list: Array = []
	for e in _spell.effects:
		var d := MagicEffects.get_def(StringName(e["id"]))
		if int(d.get("kind", -1)) == MagicEffects.Kind.INSTANT:
			tick_list.append({"id": e["id"], "mag": float(e["mag"]) * SPRAY_TICK, "dur": 0.0})
		else:
			tick_list.append(e)
	for c in hit_bodies:
		var m := ActiveMagic.of(c)
		if m != null:
			m.apply_list(tick_list, host, _spell.display_name, "spell", power)


func _place_rune(spell: SpellData, power: float) -> void:
	var origin := _origin()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + _aim_dir() * SpellData.RUNE_RANGE, MagicHit.LAYER_WORLD, _exclude())
	var hit := host.get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit["position"] if not hit.is_empty() else origin + _aim_dir() * SpellData.RUNE_RANGE
	# Drop it to the ground below the point
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 8.0, MagicHit.LAYER_WORLD, _exclude())
	var g := host.get_world_3d().direct_space_state.intersect_ray(down)
	if not g.is_empty():
		at = g["position"]
	_runes = _runes.filter(func(r: Node) -> bool: return is_instance_valid(r))
	while _runes.size() >= MAX_RUNES:
		var old: Node = _runes.pop_front()
		old.queue_free()
	_runes.append(SpellRune.place(self, spell, power, at))


# ---------------------------------------------------------------- specials (summons, bound weapons...)

## Starts a special effect on the caster. Returns a Callable that ends it, true / false for
## instant ones (Mark, Recall), or false if it failed.
func start_special(id: StringName, mag: float, dur: float) -> Variant:
	var sid := String(id)
	if sid.begins_with("summon_"):
		return _summon(sid.trim_prefix("summon_"), dur)
	if sid.begins_with("bound_"):
		return _bound(sid.trim_prefix("bound_"))
	match id:
		&"mark":
			return _mark()
		&"recall":
			return _recall()
	return false


const SUMMON_KINDS := {
	"wolf": "wolf", "skeleton": "skeleton", "ember": "fire_spirit", "frost": "ice_wraith",
	"bear": "frost_bear", "troll": "cave_troll",
}


func _summon(kind: String, dur: float) -> Variant:
	var data := load("res://scripts/Resources/Enemies/%s.tres" % SUMMON_KINDS.get(kind, "wolf")) as EnemyData
	if data == null:
		return false
	_summons = _summons.filter(func(s: Node) -> bool: return is_instance_valid(s) and not (s as Enemy).is_dead())
	var limit := 2 if skills != null and skills.get_level(&"conjuration") >= 50 else 1
	while _summons.size() >= limit:
		var old := _summons.pop_front() as Enemy
		_unsummon(old)
	var level := skills.get_player_level() if skills != null else 5
	var e := Enemy.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	data.apply(e, maxi(level, 3), rng)
	e.disposition = Enemy.Disposition.FRIENDLY
	e.display_name = "Summoned " + data.display_name
	e.persist_mode = Enemy.PersistMode.NEVER
	e.talk_lines = PackedStringArray()
	e.set_meta("player_ally", true)
	e.set_meta("summoned", true)
	e.loot = []
	var fwd := -host.global_transform.basis.z
	fwd.y = 0.0
	var pos := host.global_position + fwd.normalized() * 2.5 + Vector3.UP * 0.5
	e.position = pos
	host.get_tree().current_scene.add_child(e)
	e.global_position = pos
	AllyBrain.attach(e, host)
	SpellFX.burst(e, pos + Vector3.UP, 1.5, MagicEffects.SCHOOL_COLORS[&"conjuration"])
	_summons.append(e)
	return func() -> void: _unsummon(e)


func _unsummon(e: Enemy) -> void:
	if e == null or not is_instance_valid(e):
		return
	SpellFX.burst(e, e.global_position + Vector3.UP, 1.5, MagicEffects.SCHOOL_COLORS[&"conjuration"])
	e.queue_free()


const BOUND_KINDS := {"dagger": ItemCatalog.Weapon.DAGGER, "sword": ItemCatalog.Weapon.SWORD,
	"waraxe": ItemCatalog.Weapon.WAR_AXE, "greatsword": ItemCatalog.Weapon.GREATSWORD}


func _bound(kind: String) -> Variant:
	var inv := host.get_node_or_null("Inventory") as Inventory
	var eq := host.get_node_or_null("Equipment") as Equipment
	if inv == null or eq == null:
		return false
	var conj := skills.get_level(&"conjuration") if skills != null else 20
	var tier := clampi(2 + conj / 25, 2, LevelCurve.MAX_TIER)
	var base := ItemCatalog.get_weapon(BOUND_KINDS.get(kind, ItemCatalog.Weapon.SWORD), tier)
	if base == null:
		return false
	var item := base.duplicate() as ItemData
	item.display_name = "Bound " + base.display_name.get_slice(" ", base.display_name.get_slice_count(" ") - 1)
	item.weight = 0.0
	item.value = 0
	item.set_meta("bound", true)
	inv.add_item(item)
	eq.equip(item)
	return func() -> void:
		if is_instance_valid(eq):
			eq.unequip_item(item)
		if is_instance_valid(inv):
			inv.remove_item(item, inv.get_count(item))


func _mark() -> bool:
	var dm := host.get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		if is_player:
			Locks.toast(host.get_tree(), "Mark only works outdoors", true)
		return false
	var book := host.get_node_or_null("Spellbook") as Spellbook
	if book == null:
		return false
	book.mark = SaveUtil.vec3_to_array(host.global_position)
	if is_player:
		Locks.toast(host.get_tree(), "This place is marked")
	return true


func _recall() -> bool:
	var book := host.get_node_or_null("Spellbook") as Spellbook
	if book == null or book.mark.is_empty():
		if is_player:
			Locks.toast(host.get_tree(), "Nothing is marked: cast Mark first", true)
		return false
	var dm := host.get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager
	if dm != null and dm.is_inside():
		if is_player:
			Locks.toast(host.get_tree(), "Recall only works outdoors", true)
		return false
	var pos := SaveUtil.array_to_vec3(book.mark)
	var world := host.get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world != null:
		world.ensure_area_loaded(pos)
	host.global_position = pos + Vector3.UP * 0.3
	if host is CharacterBody3D:
		(host as CharacterBody3D).velocity = Vector3.ZERO
	SpellFX.burst(host, pos + Vector3.UP, 2.0, MagicEffects.SCHOOL_COLORS[&"mysticism"])
	return true


func _magic_unlock(collider: Object, level: float) -> void:
	var target: Object = collider
	if target != null and target.has_meta("interactable"):
		target = target.get_meta("interactable")
	if target == null or not is_instance_valid(target) or not target.has_method("magic_unlock"):
		return
	var ok: bool = target.magic_unlock(roundi(level))
	if is_player:
		Locks.toast(host.get_tree(), "The lock clicks open" if ok else "This lock is too hard for that spell", not ok)


func _reanimate(collider: Object, level: float, dur: float) -> void:
	var corpse := MagicHit.creature_of(collider) as Enemy
	if corpse == null or not corpse.is_dead():
		return
	if corpse.level > roundi(level):
		if is_player:
			Locks.toast(host.get_tree(), "That corpse is too powerful to raise", true)
		return
	corpse.reanimate(host, dur)


# ---------------------------------------------------------------- helpers

func _origin() -> Vector3:
	return aim_origin.global_position


func _aim_dir() -> Vector3:
	if aim_target != null and is_instance_valid(aim_target):
		var at := aim_target.global_position + Vector3.UP * (1.1 if aim_target.is_in_group("player") else 0.9)
		return (at - _origin()).normalized()
	return -aim_origin.global_transform.basis.z


func _ray(dist: float, include_items: bool) -> Dictionary:
	var origin := _origin()
	var mask := MagicHit.LAYER_WORLD | MagicHit.LAYER_ENEMY | (MagicHit.LAYER_ITEMS if include_items else 0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + _aim_dir() * dist, mask, _exclude())
	q.collide_with_areas = false
	return host.get_world_3d().direct_space_state.intersect_ray(q)


func _exclude() -> Array[RID]:
	var out: Array[RID] = []
	if host is CollisionObject3D:
		out.append((host as CollisionObject3D).get_rid())
	return out


func _train(spell: SpellData, magicka: float) -> void:
	if skills != null:
		skills.add_xp(spell.get_school(), magicka * XP_PER_MAGICKA)


func _break_invisibility() -> void:
	if magic != null and magic.has_effect(&"invisibility"):
		magic.remove_effect(&"invisibility")


func _set_spray_visual(on: bool) -> void:
	if is_player:
		return  # the player's hand (SpellHandView) draws its own spray
	if on and _spray_fx == null:
		_spray_fx = SpellFX.make_spray(_spell.get_color())
		aim_origin.add_child(_spray_fx)
		_spray_fx.position = Vector3(0.2, -0.2, -0.5)
	if _spray_fx != null:
		_spray_fx.emitting = on
