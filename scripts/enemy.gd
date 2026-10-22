class_name Enemy
extends CharacterBody3D
## A melee enemy with basic AI, its own Stats / Inventory / Equipment, and a lootable body.
## Everything it needs is built in code, so the quickest setup is:
##   Enemy.spawn(get_tree().current_scene, Vector3(0, 1, -8), iron_sword)
## or in the editor: add a CharacterBody3D to your world, attach this script, and drag a weapon
## into "Starting Weapon" in the Inspector. It adds the collision shape, a placeholder body,
## Stats, Inventory, Equipment and MeleeCombat itself if they are missing.
##
## Behavior: IDLE until it sees the player (range + field of view + line of sight), then CHASE.
## In reach it circles you and picks its moment to swing (ATTACK). Swings are TELEGRAPHED: the
## weapon rises and the body glows before the hit lands, red for a heavy swing, so you can
## react by blocking, parrying, dodging or hitting it first. A hit on an enemy that is winding
## up flinches it. Poise: enough hits in a row break it (STAGGER). A staggered enemy cannot
## attack at all (MeleeCombat enforces it) and takes bonus damage. A group never swings all at
## once: only `max_attackers` enemies commit to a swing at the same time, the rest circle.
## On death it falls over, stops being hittable, and becomes a container holding everything
## it carried.
##
## Not every Enemy is an enemy: `disposition` makes NPCs out of the same body. HOSTILE attacks on
## sight. NEUTRAL wanders and talks until you hit it, then fights back. FRIENDLY wanders, talks,
## and runs away if you hit it. All of them can be fought, killed and looted. EnemyData (a
## resource) fills in everything from a name and a level, see population.gd.
##
## Layers: it lives on physics layer 5 (value 16) so the player's attacks can find it. The
## player (layer 1) must have 16 in its collision mask, player.gd does that.
##
## Animations: see AnimationHooks. This script asks for idle / run / alert / hit_react / death,
## and MeleeCombat asks for the attacks. Nothing needs to exist for the game to work.

signal state_changed(new_state: int, old_state: int)
signal died(enemy: Enemy)
## The end of a route given to follow_route() was reached (never for a looping route)
signal route_finished

## PATROL = walking a list of waypoints (townsfolk going home, guards on their rounds), see follow_route()
enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD, WANDER, FLEE, PATROL }
enum Disposition { HOSTILE, NEUTRAL, FRIENDLY }
## ALWAYS = SaveManager saves it (and its corpse). CORPSE_ONLY = only the corpse is saved, a living
## one is rebuilt from the world seed (population). NEVER = never saved (random encounters).
enum PersistMode { ALWAYS, CORPSE_ONLY, NEVER }

const ENEMY_LAYER := 16
const WORLD_LAYER := 1
const GOLD := Color(1.0, 0.85, 0.35)

@export_group("Identity")
@export var display_name := "Bandit"

@export_group("Stats (used when this script creates the Stats node)")
@export var max_health := 60.0
## Added to the weapon's damage, like the player's base damage stat
@export var base_damage := 3.0

@export_group("Movement")
@export var move_speed := 3.2
@export var acceleration := 20.0
@export var turn_speed := 8.0

@export_group("Senses")
@export var detection_range := 14.0
## Gives up the chase when you get this far away
@export var lose_range := 25.0
## Cone it can notice you in. Once it has noticed you (or been hit) it sees all around.
@export_range(10.0, 360.0, 1.0) var field_of_view := 150.0

@export_group("Combat")
## Starts swinging this many meters beyond the weapon's reach
@export var attack_range_margin := 0.2
## It only swings when facing you within this many degrees
@export var attack_aim_tolerance := 20.0
## Extra windup on every swing: the readable "tell" before the hit lands. Bigger = easier to react to.
@export var telegraph_time := 0.3
## Breather between swings (a random time between these)
@export var attack_pause_min := 0.3
@export var attack_pause_max := 1.0
## Chance a swing is a slow, powerful heavy attack
@export_range(0.0, 1.0, 0.05) var heavy_chance := 0.2
## Chance to follow a light swing with another one straight away (a short combo)
@export_range(0.0, 1.0, 0.05) var chain_chance := 0.3
## Sideways speed while circling you
@export var circle_speed := 1.6
## Step forward when a swing becomes active (m/s)
@export var lunge_speed := 3.0
## How many enemies may be in the middle of a swing at the same time
@export var max_attackers := 2

@export_group("Poise")
## Hits chip at this. At 0 the enemy staggers. Weapons set how much each hit takes off.
@export var max_poise := 40.0
## How long a stagger lasts. It cannot act at all meanwhile.
@export var stagger_time := 0.8
## How long a hit on a winding-up enemy freezes it (cancels the swing)
@export var flinch_time := 0.35
## How quickly a knockback slide slows down during a stagger. Smaller = slides further.
@export var knockback_friction := 6.0
## 0 = full knockback, 1 = can't be pushed (use for bosses or heavy enemies)
@export_range(0.0, 1.0, 0.05) var knockback_resistance := 0.0

@export_group("Population")
@export var disposition: Disposition = Disposition.HOSTILE
## Shown on the health bar; EnemyData sets it
@export var level := 1
## 0 = stands still until it notices you. Bigger = strolls around its home point inside this radius.
@export var wander_radius := 0.0
## A friendly NPC runs this long (seconds) after being hit
@export var flee_time := 8.0
@export var persist_mode: PersistMode = PersistMode.ALWAYS
## A stable id (set by the population code). When set, killing it is remembered in WorldState so it
## does not respawn when the chunk or dungeon is loaded again.
@export var spawn_key := ""
## What an NPC says when you talk to it (hostile enemies ignore these)
@export var talk_name := ""
@export var talk_lines: PackedStringArray = []
## Size of the placeholder body (collision and mesh); 1.0 = human
@export_range(0.4, 2.5, 0.05) var body_scale := 1.0
## Multiplier on all damage dealt (EnemyData sets it from the level curve)
@export var damage_mult := 1.0

@export_group("Gear")
@export var starting_weapon: ItemData
@export var starting_off_hand: ItemData
## Worn armor (a cuirass, ...)
@export var starting_armor: Array[ItemData] = []
## Carried but not equipped
@export var extra_items: Array[ItemData] = []
## Extra loot rolled the first time the body is searched. Everything above is lootable too.
@export var loot: Array[LootEntry] = []

@export_group("Animation")
## Prefix for this enemy's idle / run / hit_react / death animation names
@export var animation_set: StringName = &""
## No death animation found? Tip the body over so it lies on the ground
@export var death_fall_placeholder := true
@export var placeholder_color := Color(0.7, 0.2, 0.2)

var state: State = State.IDLE
var stats: Stats
var inventory: Inventory
var equipment: Equipment
var combat: MeleeCombat
var animation: AnimationHooks
var head: Node3D

var _target: Node3D
var _alerted := false
var _state_time := 0.0
var _clock := 0.0
var _next_attack_at := 0.0
var _circle_dir := 1.0
var _circle_timer := 0.0
var _was_busy := false
var _chain_count := 0
var _last_swing_heavy := false
var _material: StandardMaterial3D
var _weapon_pivot: Node3D
var _weapon_tilt := 25.0
var _tint := 0.0
var _home := Vector3.ZERO
var _home_set := false
var _next_wander_at := 0.0
var _wander_target := Vector3.ZERO
var _flee_until := 0.0
var _talk: NpcTalk
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## The waypoints of the current route (world positions), see follow_route()
var route := PackedVector3Array()
var route_loop := false
## Walking speed on a route, as a part of move_speed
var route_speed := 0.45
var _route_i := 0
var _route_check_pos := Vector3.ZERO
var _route_check_time := 0.0
## Optional: func(from: Vector3, to: Vector3) -> PackedVector3Array, a walking route between two
## world positions (a town's streets, see TownLife). A chase that gets stuck on a wall uses it.
var path_provider: Callable
var _chase_path := PackedVector3Array()
var _chase_check_pos := Vector3.ZERO
var _chase_check_time := 0.0

## Fighting style, decides which tricks it uses (EnemyData sets it):
##   DUELIST  blocks, parries, sidesteps and feints (anyone with a shield or a one-hander)
##   BRUTE    heavy two-handers: guard-breaking kicks, wide sweeps, rarely backs off
##   MAGE     keeps its distance and casts; draws a weapon when you get close
##   BEAST    pounces from range, circles fast, snaps; big beasts roar to knock you back
##   SPIRIT   floats at range and casts its element
##   ARCHER   keeps its distance and shoots; backs off when you close in
enum Style { DUELIST, BRUTE, MAGE, BEAST, SPIRIT, ARCHER }

@export_group("Body and tricks")
@export var body_kind: CreatureBody.Kind = CreatureBody.Kind.HUMANOID
@export var style: Style = Style.DUELIST
## Which EnemyData made it ("wolf", "bandit"...)
@export var enemy_id := ""
## 0..1 how sharp it is: chance to dodge, block, parry and feint (EnemyData sets it from the level)
@export_range(0.0, 1.0, 0.05) var cunning := 0.3
## Healing potions it can drink when hurt (humanoids)
@export var potions := 0
## Spells it casts (MAGE and SPIRIT styles, some others). Magnitudes already fit its level.
var spells: Array[SpellData] = []
var body: CreatureBody
var magic: ActiveMagic
var caster: SpellCaster
var ranged: RangedCombat
var _draw_left := 0.0
var _shot_cd := 1.0
var _dodge_cd := 0.0
var _block_until := 0.0
var _lunge_cd := 3.0
var _kick_cd := 4.0
var _roar_cd := 6.0
var _cast_cd := 1.5
var _casting: SpellData
var _cast_left := 0.0
var _drinking := 0.0
var _feinted := false
var _flank_angle := 0.0
var _calm_until := -1.0
var _fear_until := -1.0
var _frenzy_until := -1.0
var _far_accum := 0.0
var _lying_restore := false
var _killing_push := Vector3.ZERO


static func spawn(parent: Node, pos: Vector3, weapon: ItemData = null, off_hand: ItemData = null) -> Enemy:
	var e := Enemy.new()
	e.starting_weapon = weapon
	e.starting_off_hand = off_hand
	# Set the position BEFORE entering the tree, otherwise the physics engine briefly sees the
	# enemy at the world origin and shoves whatever is standing there (like the player)
	e.position = pos
	parent.add_child(e)
	e.global_position = pos  # corrects for a parent that isn't at the origin
	return e


func _ready() -> void:
	add_to_group("enemies")
	if persist_mode == PersistMode.ALWAYS:
		add_to_group("persistent")  # SaveManager saves everything in this group (corpses included)
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER  # enemies also bump into each other instead of stacking
	_build_body()
	_build_systems()
	_equip_starting_gear()
	stats.died.connect(_on_died)
	combat.damaged.connect(_on_damaged)
	combat.stunned.connect(_on_stunned)
	combat.staggered.connect(_on_staggered)
	equipment.equipped.connect(func(_slot, _item): _refresh_weapon_visual())
	equipment.unequipped.connect(func(_slot, _item): _refresh_weapon_visual())
	_refresh_weapon_visual()
	_flank_angle = randf_range(-1.0, 1.0)
	magic.notice.connect(func(text: String, color: Color) -> void: _popup(text, global_position + Vector3.UP * 2.2, color, 36))
	_next_wander_at = randf_range(0.5, 4.0)
	if disposition != Disposition.HOSTILE and not talk_lines.is_empty():
		_talk = NpcTalk.attach(self, talk_name if talk_name != "" else display_name, talk_lines)
	_enter_state(State.IDLE)


func is_dead() -> bool:
	return state == State.DEAD


## Has it noticed a target (or been hit)? Then it sees all around, not just ahead.
func is_alerted() -> bool:
	return _alerted


## Attacks another creature (guards defending their town). Its swings can then hit creatures.
func fight(target: Node3D) -> void:
	if state == State.DEAD or target == null or target == self:
		return
	_target = target
	_alerted = true
	lose_range = maxf(lose_range, global_position.distance_to(target.global_position) + 25.0)  # don't give up at once
	combat.hit_mask = WORLD_LAYER | ENEMY_LAYER
	if state == State.IDLE or state == State.WANDER or state == State.PATROL:
		_enter_state(State.CHASE)


## Runs from `source` for a while (a frightened witness)
func flee_from(source: Node3D, seconds: float = 8.0) -> void:
	if state == State.DEAD or disposition == Disposition.HOSTILE:
		return
	_target = source
	_flee_until = _clock + seconds
	if state != State.STAGGER:
		_enter_state(State.FLEE)


## In the middle of a swing (winding up or hurting things). Other enemies check this so a
## group doesn't all swing at once.
func is_attack_committed() -> bool:
	return state == State.ATTACK and combat != null and combat.is_attacking()


# ---------------------------------------------------------------- building

func _build_body() -> void:
	head = get_node_or_null("Head") as Node3D
	if head == null:
		head = Node3D.new()
		head.name = "Head"
		head.position = Vector3(0, 1.4 * body_scale, 0)
		add_child(head)

	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4 * body_scale
		capsule.height = 1.8 * body_scale
		shape.shape = capsule
		shape.position = Vector3(0, 0.9 * body_scale, 0)
		add_child(shape)

	if find_children("*", "MeshInstance3D", true, false).is_empty() and body == null:
		# A jointed, animated body (people, beasts, crawlers, spirits), see CreatureBody
		var seed_value := (spawn_key if spawn_key != "" else display_name + str(get_instance_id())).hash()
		body = CreatureBody.build_for(self, body_kind, seed_value)
		add_child(body)
		return
	if find_children("*", "MeshInstance3D", true, false).is_empty():
		_material = StandardMaterial3D.new()
		_material.albedo_color = placeholder_color
		_material.emission_enabled = true
		_material.emission = Color(1.0, 0.5, 0.1)
		_material.emission_energy_multiplier = 0.0
		var body_mesh := MeshInstance3D.new()
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = 0.4 * body_scale
		capsule_mesh.height = 1.8 * body_scale
		body_mesh.mesh = capsule_mesh
		body_mesh.material_override = _material
		body_mesh.position = Vector3(0, 0.9 * body_scale, 0)
		add_child(body_mesh)
		# A "nose" so you can see which way it is facing
		var nose := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 0.15, 0.4) * body_scale
		nose.mesh = box
		nose.position = Vector3(0, 0, -0.45 * body_scale)
		head.add_child(nose)
		# A placeholder weapon that rises and falls with the swing, so attacks can be read
		_weapon_pivot = Node3D.new()
		_weapon_pivot.name = "WeaponPivot"
		_weapon_pivot.position = Vector3(0.5, 1.15, -0.1) * body_scale
		add_child(_weapon_pivot)


func _build_systems() -> void:
	stats = get_node_or_null("Stats") as Stats
	if stats == null:
		stats = Stats.new()
		stats.name = "Stats"
		stats.base_stats = Stats.DEFAULT_BASE_STATS.duplicate()
		stats.base_stats["max_health"] = max_health
		stats.base_stats["damage"] = base_damage
		if not spells.is_empty():
			stats.base_stats["max_magicka"] = 80.0 + float(level) * 4.0
			stats.base_stats["magicka_regen"] = 3.0 + float(level) * 0.1
		add_child(stats)
		if not is_equal_approx(damage_mult, 1.0):
			stats.add_modifiers("level", {"damage_pct": damage_mult - 1.0})
		if has_meta("resists"):
			stats.add_modifiers("innate", get_meta("resists"))

	inventory = get_node_or_null("Inventory") as Inventory
	if inventory == null:
		inventory = Inventory.new()
		inventory.name = "Inventory"
		inventory.stats = stats
		add_child(inventory)

	equipment = get_node_or_null("Equipment") as Equipment
	if equipment == null:
		equipment = Equipment.new()
		equipment.name = "Equipment"
		equipment.inventory = inventory
		equipment.stats = stats
		add_child(equipment)

	combat = get_node_or_null("MeleeCombat") as MeleeCombat
	if combat == null:
		combat = MeleeCombat.new()
		combat.name = "MeleeCombat"
		combat.stats = stats
		combat.equipment = equipment
		combat.max_poise = max_poise
		combat.stagger_time = stagger_time
		combat.flinch_time = flinch_time
		combat.interruptible_windup = true  # hit it while it winds up and the swing is cancelled
		combat.windup_add = telegraph_time
		combat.lunge_speed = lunge_speed
		add_child(combat)
	combat.hit_mask = WORLD_LAYER  # enemies hit the world and the player (layer 1), never each other
	animation = combat.animation
	magic = ActiveMagic.attach(self)
	if starting_weapon != null and starting_weapon.is_bow:
		ranged = RangedCombat.new()
		ranged.name = "RangedCombat"
		ranged.aim_origin = head
		ranged.npc_arrow = ItemCatalog.get_arrow(maxi(starting_weapon.tier - 1, 0))
		add_child(ranged)
		style = Style.ARCHER
	if not spells.is_empty():
		caster = SpellCaster.new()
		caster.name = "SpellCaster"
		caster.aim_origin = head
		add_child(caster)


func _equip_starting_gear() -> void:
	if starting_weapon != null:
		inventory.add_item(starting_weapon)
		equipment.equip(starting_weapon)
	if starting_off_hand != null:
		inventory.add_item(starting_off_hand)
		equipment.equip(starting_off_hand)
	for armor in starting_armor:
		if armor != null:
			inventory.add_item(armor)
			equipment.equip(armor)
	for item in extra_items:
		inventory.add_item(item)


# The placeholder weapon follows whatever is in the main hand
func _refresh_weapon_visual() -> void:
	if body != null and equipment != null:
		var main := equipment.get_main_hand()
		var off: ItemData = equipment.get_equipped(ItemData.EquipSlot.OFF_HAND)
		body.set_weapons(main, off)
		body.dress(equipment)
	if _weapon_pivot == null:
		return
	for c in _weapon_pivot.get_children():
		c.queue_free()
	var w := equipment.get_main_hand() if equipment != null else null
	if w == null:
		return
	var length := clampf(w.reach * 0.38, 0.45, 1.3)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.7, 0.72, 0.78)
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, length)
	blade.mesh = box
	blade.material_override = metal
	blade.position = Vector3(0, 0, -length * 0.5)
	_weapon_pivot.add_child(blade)
	if w.animation_set == &"hammer":
		var head_mesh := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.25, 0.2, 0.2)
		head_mesh.mesh = hb
		head_mesh.material_override = metal
		head_mesh.position = Vector3(0, 0, -length)
		_weapon_pivot.add_child(head_mesh)


# ---------------------------------------------------------------- AI

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Far from the player and calm: think a few times a second instead of every frame
	if (state == State.IDLE or state == State.WANDER or state == State.PATROL) and not has_meta("player_ally"):
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null and p.global_position.distance_squared_to(global_position) > 70.0 * 70.0:
			_far_accum += delta
			if _far_accum < 0.2:
				return
			delta = _far_accum
		_far_accum = 0.0
	_clock += delta
	_state_time += delta
	_dodge_cd -= delta
	_lunge_cd -= delta
	_kick_cd -= delta
	_roar_cd -= delta
	_cast_cd -= delta
	if not _home_set:
		_home = global_position  # where it was put: wandering stays around here
		_home_set = true
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _frenzy_until > _clock:
		_tick_frenzy()
	elif _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node3D
	# Calmed: no fighting while it lasts
	if _calm_until > _clock and (state == State.CHASE or state == State.ATTACK):
		_alerted = false
		_enter_state(State.IDLE)
	if _fear_until > _clock and state != State.STAGGER and state != State.FLEE:
		_flee_until = _fear_until
		_enter_state(State.FLEE)
	_tick_special(delta)
	if _casting != null:
		_tick_cast(delta)
	if _drinking > 0.0:
		_drinking -= delta
		_slow_down(delta, acceleration)
		if body != null:
			body.pose = &"drink" if _drinking > 0.0 else &""
		if _drinking <= 0.0:
			stats.modify_vital("health", stats.get_stat("max_health") * 0.4)
			_popup("+%d" % roundi(stats.get_stat("max_health") * 0.4), global_position + Vector3.UP * 2.0, Color(0.4, 1.0, 0.4), 40)
		move_and_slide()
		return

	match state:
		State.IDLE:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.STAGGER:
			_tick_stagger(delta)
		State.WANDER:
			_tick_wander(delta)
		State.FLEE:
			_tick_flee(delta)
		State.PATROL:
			_tick_patrol(delta)
	_aim_head()
	move_and_slide()


# Swings go out from the head. Against another creature (a guard against a wolf) the head tilts
# toward its body so the swing doesn't pass over it; against the player it stays level.
func _aim_head() -> void:
	if head == null:
		return
	var other := _target as Enemy
	if other == null or not is_instance_valid(other) or (state != State.CHASE and state != State.ATTACK):
		head.rotation.x = 0.0
		return
	var center := other.global_position + Vector3.UP * 0.8 * other.body_scale
	var flat := Vector2(center.x - head.global_position.x, center.z - head.global_position.z).length()
	head.rotation.x = atan2(center.y - head.global_position.y, maxf(flat, 0.3))


## Walks along these world positions, one after the other (calmly, at speed_mult x move_speed).
## loop = start over at the end (a guard's rounds); otherwise route_finished fires at the end.
## A hostile one still notices you on the way; a fight or a hit interrupts the route.
func follow_route(points: PackedVector3Array, loop: bool = false, speed_mult: float = 0.45) -> void:
	if state == State.DEAD or points.is_empty():
		return
	route = points
	route_loop = loop
	route_speed = speed_mult
	_route_i = 0
	_route_check_pos = global_position
	_route_check_time = 0.0
	_enter_state(State.PATROL)


func stop_route() -> void:
	route = PackedVector3Array()
	if state == State.PATROL:
		_enter_state(State.IDLE)


func is_on_route() -> bool:
	return state == State.PATROL


## Where wandering stays around (normally the spot it was placed)
func set_home(pos: Vector3) -> void:
	_home = pos
	_home_set = true


func _tick_patrol(delta: float) -> void:
	if disposition == Disposition.HOSTILE and _can_see_target():
		_alerted = true
		animation.trigger(AnimationHooks.ALERT, animation_set)
		_enter_state(State.CHASE)
		return
	if _route_i >= route.size():
		_end_route()
		return
	var to := route[_route_i] - global_position
	to.y = 0.0
	if to.length() < 0.7:
		_route_i += 1
		if _route_i >= route.size():
			if route_loop:
				_route_i = 0
			else:
				_end_route()
		return
	# Stuck on something (another NPC, a corner) for a while: hop to the waypoint
	_route_check_time += delta
	if _route_check_time >= 2.0:
		if global_position.distance_to(_route_check_pos) < 0.4:
			global_position = route[_route_i] + Vector3.UP * 0.3
			velocity = Vector3.ZERO
		_route_check_pos = global_position
		_route_check_time = 0.0
	var dir := to.normalized()
	var speed := move_speed * route_speed
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	_face(to, delta)


func _end_route() -> void:
	route = PackedVector3Array()
	set_home(global_position)
	_next_wander_at = _clock + randf_range(2.0, 6.0)
	_enter_state(State.IDLE)
	route_finished.emit()


func _tick_idle(delta: float) -> void:
	_slow_down(delta, acceleration)
	if disposition == Disposition.HOSTILE and _can_see_target():
		_alerted = true
		animation.trigger(AnimationHooks.ALERT, animation_set)
		_enter_state(State.CHASE)
	elif wander_radius > 0.0 and _clock >= _next_wander_at:
		_start_wander()


func _start_wander() -> void:
	var angle := randf() * TAU
	_wander_target = _home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(minf(2.0, wander_radius), wander_radius)
	_enter_state(State.WANDER)


# Strolls to a point near home, then stands for a while. A hostile one still notices you on the way.
func _tick_wander(delta: float) -> void:
	if disposition == Disposition.HOSTILE and _can_see_target():
		_alerted = true
		animation.trigger(AnimationHooks.ALERT, animation_set)
		_enter_state(State.CHASE)
		return
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 0.8 or _state_time > 12.0 or (is_on_wall() and _state_time > 0.6):
		_next_wander_at = _clock + randf_range(2.0, 7.0)
		_enter_state(State.IDLE)
		return
	var dir := to.normalized()
	var speed := move_speed * 0.45
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	_face(to, delta)


# A friendly NPC that was hit runs away from whoever hit it
func _tick_flee(delta: float) -> void:
	if not _target_usable() or _clock >= _flee_until:
		_next_wander_at = _clock + 3.0
		_enter_state(State.IDLE)
		return
	var away := -_flat_to_target()
	if away.length() > 40.0:
		_enter_state(State.IDLE)
		return
	if away.length() < 0.01:
		away = Vector3.FORWARD
	var dir := away.normalized()
	velocity.x = move_toward(velocity.x, dir.x * move_speed * 1.15, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * move_speed * 1.15, acceleration * delta)
	_face(away, delta)


## Makes a hostile enemy come for `target` right away (random encounters use it). Does nothing
## for friendly and neutral NPCs.
func aggro(target: Node3D = null) -> void:
	if state == State.DEAD or disposition != Disposition.HOSTILE:
		return
	if target != null:
		_target = target
	_alerted = true
	if _target != null and is_instance_valid(_target):
		lose_range = maxf(lose_range, _flat_to_target().length() + 25.0)  # started far away: don't give up at once
	if state == State.IDLE or state == State.WANDER or state == State.PATROL:
		_enter_state(State.CHASE)


func _tick_chase(delta: float) -> void:
	if not _target_usable():
		_lose_target()
		return
	var to_target := _flat_to_target()
	if to_target.length() > lose_range:
		_lose_target()
		return
	_face(to_target, delta)
	if _casting != null:
		_slow_down(delta, acceleration)
		return
	var dist := to_target.length()
	if style == Style.ARCHER and ranged != null and ranged.has_bow():
		_tick_archer(delta, to_target, dist)
		return
	if _try_cast(dist):
		return
	# Mages and spirits hold their distance while they can still cast
	if (style == Style.MAGE or style == Style.SPIRIT) and not spells.is_empty() and dist < 16.0 and dist > 5.0 \
			and stats.magicka > 15.0 and _can_see_target_simple():
		_slow_down(delta, acceleration)
		var side := Vector3(-to_target.z, 0.0, to_target.x).normalized() * _circle_dir * circle_speed
		velocity.x = move_toward(velocity.x, side.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, side.z, acceleration * delta)
		return
	if dist <= _attack_start_distance():
		_enter_state(State.ATTACK)
		return
	if _lunge_cd <= 0.0 and dist > 3.2 and dist < 7.5 and (style == Style.BEAST or (style == Style.DUELIST and cunning >= 0.45)) \
			and is_on_floor() and _facing_error(to_target) < 0.3:
		_lunge(to_target)
		return
	var goal := to_target.normalized()
	# Stuck behind a house for a second: take the streets (when there is a route to follow)
	_chase_check_time += delta
	if _chase_check_time >= 1.0:
		if global_position.distance_to(_chase_check_pos) < 0.6 and path_provider.is_valid() and _chase_path.is_empty():
			_chase_path = path_provider.call(global_position, _target.global_position)
		_chase_check_pos = global_position
		_chase_check_time = 0.0
	if not _chase_path.is_empty():
		var to_wp := _chase_path[0] - global_position
		to_wp.y = 0.0
		if to_target.length() < 3.0:
			_chase_path.clear()
		elif to_wp.length() < 1.0:
			_chase_path.remove_at(0)
		else:
			goal = to_wp.normalized()
	var dir := _around_walls(goal)
	velocity.x = move_toward(velocity.x, dir.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * move_speed, acceleration * delta)


# Running into a wall (a house between it and its target): slide along the wall toward the side
# the target is on, so it goes round the corner instead of pushing into the wall forever
func _around_walls(dir: Vector3) -> Vector3:
	if not is_on_wall():
		return dir
	var n := get_wall_normal()
	n.y = 0.0
	if n.length() < 0.1 or n.normalized().dot(dir) > -0.2:
		return dir
	n = n.normalized()
	var along := Vector3(-n.z, 0.0, n.x)
	if along.dot(dir) < 0.0:
		along = -along
	return (along + n * 0.15).normalized()


# In reach: circle and look for a moment to swing. Once a swing starts the enemy is COMMITTED:
# it keeps turning a little during the windup, then locks its aim (the "dodge window").
func _tick_attack(delta: float) -> void:
	if not _target_usable():
		_lose_target()
		return
	var to_target := _flat_to_target()
	var dist := to_target.length()
	var phase := combat.get_phase()
	var busy := phase != MeleeCombat.Phase.IDLE
	if _was_busy and not busy:
		_on_swing_finished()
	_was_busy = busy

	match phase:
		MeleeCombat.Phase.WINDUP:
			_face(to_target, delta * 0.5)
			_slow_down(delta, acceleration)
		MeleeCombat.Phase.ACTIVE, MeleeCombat.Phase.RECOVERY:
			_slow_down(delta, acceleration)  # committed: no turning, no walking
		_:
			_face(to_target, delta)
			if _casting != null:
				_slow_down(delta, acceleration)
				return
			if combat.is_blocking():
				_slow_down(delta, acceleration)
				if _clock >= _block_until:
					combat.secondary_release()
				return
			if dist > _attack_start_distance() + 0.8:
				_enter_state(State.CHASE)
				return
			if _react_to_target(dist, to_target):
				return
			_circle(to_target, dist, delta)
			if _clock >= _next_attack_at and dist <= _attack_start_distance() \
					and _facing_error(to_target) <= deg_to_rad(attack_aim_tolerance) and _attack_slot_free():
				_start_swing()
	if phase == MeleeCombat.Phase.WINDUP and _feint_at > 0.0 and _clock >= _feint_at:
		# A feint: the swing stops short, then the real one comes a moment later
		_feint_at = -1.0
		combat.interrupt()
		_next_attack_at = _clock + randf_range(0.1, 0.25)


# Stunned: can't do anything. The MeleeCombat is what decides when it is over.
func _tick_stagger(delta: float) -> void:
	_slow_down(delta, knockback_friction)
	if not combat.is_stunned() and _state_time >= 0.05:
		_next_attack_at = maxf(_next_attack_at, _clock + 0.3)  # a beat to recover before swinging again
		if disposition == Disposition.FRIENDLY and _clock < _flee_until:
			_enter_state(State.FLEE)
		elif disposition == Disposition.HOSTILE and _target_usable():
			_enter_state(State.CHASE)
		else:
			_enter_state(State.IDLE)


func _enter_state(new_state: State) -> void:
	var old := state
	state = new_state
	_state_time = 0.0
	match new_state:
		State.IDLE:
			animation.trigger(AnimationHooks.IDLE, animation_set)
		State.CHASE:
			animation.trigger(AnimationHooks.RUN, animation_set)
		State.ATTACK:
			animation.trigger(AnimationHooks.IDLE, animation_set)  # MeleeCombat plays the attack itself
			_circle_dir = 1.0 if randf() < 0.5 else -1.0
			_circle_timer = randf_range(1.0, 2.5)
			_chain_count = 0
			_was_busy = false
			_next_attack_at = maxf(_next_attack_at, _clock + randf_range(0.2, 0.5))
		State.STAGGER:
			animation.trigger(AnimationHooks.HIT_REACT, animation_set)
		State.WANDER:
			animation.trigger(AnimationHooks.WALK, animation_set)
		State.FLEE:
			animation.trigger(AnimationHooks.RUN, animation_set)
		State.PATROL:
			animation.trigger(AnimationHooks.WALK, animation_set)
	state_changed.emit(new_state, old)


func _lose_target() -> void:
	_alerted = false
	if _target != null and not (is_instance_valid(_target) and _target.is_in_group("player")):
		_target = null  # done with a creature: back to watching the player
		combat.hit_mask = WORLD_LAYER
	_enter_state(State.IDLE)


func _start_swing() -> void:
	var heavy := _chain_count == 0 and randf() < heavy_chance
	_last_swing_heavy = heavy
	# The tell is never quite the same length twice, so a parry has to be read, not counted
	combat.windup_add = telegraph_time * randf_range(0.75, 1.45)
	var ok := combat.heavy_attack(true) if heavy else combat.light_attack(true)
	if not ok:
		_next_attack_at = _clock + 0.3
		return
	_feint_at = -1.0
	if not heavy and _chain_count == 0 and cunning >= 0.35 and randf() < cunning * 0.3:
		_feint_at = _clock + combat.windup_add * 0.55


var _feint_at := -1.0


# ---------------------------------------------------------------- tricks

# Reads what the player is doing: blocks or sidesteps a coming swing, kicks through a guard that
# stays up, roars, drinks a potion when badly hurt. Returns true if it did something this frame.
func _react_to_target(dist: float, to_target: Vector3) -> bool:
	var pc: Variant = _target.get_meta("damageable", null) if _target != null else null
	var target_combat := pc as MeleeCombat
	# Badly hurt: step back and drink
	if potions > 0 and stats.health < stats.get_stat("max_health") * 0.33 and _dodge_cd <= 0.0 and randf() < 0.5:
		potions -= 1
		_dodge_cd = 3.0
		velocity += -to_target.normalized() * 6.0
		_drinking = 1.3
		return true
	if target_combat == null:
		return false
	var swinging := target_combat.get_phase() == MeleeCombat.Phase.WINDUP or target_combat.is_charging()
	if swinging and _dodge_cd <= 0.0 and dist < 4.0:
		_dodge_cd = 1.8 - cunning * 0.8
		var shield: ItemData = equipment.get_equipped(ItemData.EquipSlot.OFF_HAND)
		var can_block := shield != null and shield.secondary_action == ItemData.SecondaryAction.BLOCK
		if can_block and randf() < 0.25 + cunning * 0.55:
			if combat.secondary_press(true):
				_block_until = _clock + randf_range(0.6, 1.1)
				return true
		if randf() < cunning * 0.6 and style != Style.BRUTE:
			_dodge(to_target, target_combat.is_heavy_action() or target_combat.is_charging())
			return true
	# A guard held up too long gets kicked open
	if target_combat.is_blocking() and target_combat.get_block_age() > 0.7 and _kick_cd <= 0.0 and dist < 2.4 \
			and (style == Style.BRUTE or (style == Style.DUELIST and cunning >= 0.3)):
		_kick_cd = 5.0 - cunning * 2.0
		_start_special(&"kick", 0.35)
		return true
	# Big beasts and brutes roar or stomp: everything close is thrown back
	if _roar_cd <= 0.0 and dist < 3.5 and (body_scale >= 1.3 or (style == Style.BEAST and body_scale >= 1.1)) and randf() < 0.02:
		_roar_cd = 9.0
		_start_special(&"roar", 0.6)
		return true
	return false


func _dodge(to_target: Vector3, back: bool) -> void:
	var fwd := to_target.normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x) * (1.0 if randf() < 0.5 else -1.0)
	var push := (-fwd * 7.0) if back else (side * 7.5 - fwd * 1.5)
	velocity.x = push.x
	velocity.z = push.z
	_next_attack_at = maxf(_next_attack_at, _clock + 0.35)  # and swings back right after
	if randf() < cunning:
		_next_attack_at = _clock + 0.3


func _lunge(to_target: Vector3) -> void:
	_lunge_cd = randf_range(4.0, 7.0)
	var dir := to_target.normalized()
	var speed := 10.0 if style == Style.BEAST else 7.5
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if style == Style.BEAST:
		velocity.y = 3.0  # a pounce
	_enter_state(State.ATTACK)
	combat.windup_add = 0.05
	combat.light_attack(true)


var _special: StringName = &""
var _special_left := 0.0


func _start_special(what: StringName, windup: float) -> void:
	_special = what
	_special_left = windup


# Kick / roar: a short tell (yellow glow), then it lands if the target is still close
func _tick_special(delta: float) -> void:
	if _special == &"":
		return
	_special_left -= delta
	if body != null:
		body.set_glow(1.0, Color(1.0, 0.85, 0.2))
	if _special_left > 0.0:
		return
	var what := _special
	_special = &""
	if not _target_usable():
		return
	var to := _flat_to_target()
	var reach := 2.6 if what == &"kick" else 4.5
	if to.length() > reach:
		return
	var pc: Variant = _target.get_meta("damageable", null)
	var tc := pc as MeleeCombat
	if tc == null:
		return
	var info := DamageInfo.new(stats.get_stat("damage") * (0.5 if what == &"kick" else 0.8), self, what)
	info.ignores_block = true
	info.parryable = false
	info.poise_damage = 80.0
	info.knockback = 7.0 if what == &"kick" else 9.0
	info.direction = to.normalized()
	info.hit_position = _target.global_position + Vector3.UP
	if tc.is_blocking():
		tc.stop_block()
	tc.take_damage(info)
	tc.stun(0.55 if what == &"kick" else 0.8)
	_popup("GUARD BREAK" if what == &"kick" else "ROAR", global_position + Vector3.UP * 2.3, Color(1.0, 0.8, 0.2), 40)


# ---------------------------------------------------------------- spells

# Archers: keep 8-22 m away, draw (a visible tell), shoot, step back when you come close
func _tick_archer(delta: float, to_target: Vector3, dist: float) -> void:
	_shot_cd -= delta
	var fwd := to_target.normalized()
	if ranged.is_drawing():
		_slow_down(delta, acceleration)
		_draw_left -= delta
		if body != null:
			body.bow_draw = ranged.get_draw_ratio()
		if _draw_left <= 0.0:
			ranged.aim_target = _target
			ranged.release()
			if body != null:
				body.bow_draw = 0.0
			_shot_cd = randf_range(1.2, 2.4) - cunning * 0.6
		return
	if dist > 24.0 or not _can_see_target_simple():
		var dir := _around_walls(fwd)
		velocity.x = move_toward(velocity.x, dir.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, dir.z * move_speed, acceleration * delta)
		return
	if dist < 6.0:
		velocity.x = move_toward(velocity.x, -fwd.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, -fwd.z * move_speed, acceleration * delta)
		if dist < 2.0:
			_enter_state(State.ATTACK)
		return
	_slow_down(delta, acceleration)
	if _shot_cd <= 0.0 and ranged.begin_draw():
		_draw_left = ranged.get_bow().draw_time * randf_range(0.9, 1.4)


func _try_cast(dist: float) -> bool:
	if spells.is_empty() or caster == null or _casting != null or _cast_cd > 0.0 or dist > 24.0:
		return false
	if _calm_until > _clock:
		return false
	var pick: SpellData = null
	var hurt := stats.health < stats.get_stat("max_health") * 0.4
	for s in spells:
		var harmful := s.is_harmful()
		if s.form == SpellData.Form.SELF:
			if hurt and s.effects[0]["id"] == &"restore_health":
				pick = s
				break
			if not harmful and not magic.has_effect(StringName(s.effects[0]["id"])) and randf() < 0.25:
				pick = s
				break
	if pick == null:
		var attacks := spells.filter(func(s: SpellData) -> bool: return s.is_harmful())
		if attacks.is_empty() or (dist < 3.0 and style != Style.SPIRIT and equipment.get_main_hand() != null):
			return false
		if not _can_see_target_simple():
			return false
		pick = attacks[randi() % attacks.size()]
	if stats.magicka < caster.get_cost(pick):
		_cast_cd = 2.0
		return false
	_casting = pick
	_cast_left = maxf(0.75 - cunning * 0.3, 0.35)
	if body != null:
		body.cast_color = pick.get_color()
	return true


func _tick_cast(delta: float) -> void:
	_cast_left -= delta
	var total := maxf(0.75 - cunning * 0.3, 0.35)
	if body != null:
		body.cast_charge = clampf(1.0 - _cast_left / total, 0.05, 1.0)
	if _cast_left > 0.0:
		return
	var s := _casting
	_casting = null
	if body != null:
		body.cast_charge = 0.0
	if state == State.DEAD or combat.is_stunned() or not _target_usable():
		return
	caster.aim_target = _target if s.form != SpellData.Form.SELF else null
	caster.cast_now(s)
	_cast_cd = (1.4 if style == Style.MAGE or style == Style.SPIRIT else 4.5) * randf_range(0.8, 1.4)


func _cancel_cast() -> void:
	_casting = null
	if body != null:
		body.cast_charge = 0.0


func _can_see_target_simple() -> bool:
	if not _target_usable():
		return false
	var query := PhysicsRayQueryParameters3D.create(head.global_position, _target.global_position + Vector3.UP * 1.2, WORLD_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or not (hit["collider"] is StaticBody3D)


# ---------------------------------------------------------------- magic on it

func paralyze(seconds: float) -> void:
	if state == State.DEAD:
		return
	_cancel_cast()
	combat.stun(seconds)
	if body != null:
		body.pose = &"paralyzed"
		get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
			if is_instance_valid(body) and body.pose == &"paralyzed":
				body.pose = &"")
	if state != State.STAGGER:
		_enter_state(State.STAGGER)


func calm(seconds: float) -> void:
	_calm_until = _clock + seconds
	_cancel_cast()
	if state == State.CHASE or state == State.ATTACK:
		_alerted = false
		_enter_state(State.IDLE)


func frighten(source: Node3D, seconds: float) -> void:
	if state == State.DEAD:
		return
	_fear_until = _clock + seconds
	if source != null:
		_target = source
	_flee_until = _fear_until
	_cancel_cast()
	if state != State.STAGGER:
		_enter_state(State.FLEE)


func frenzy(seconds: float) -> void:
	_frenzy_until = _clock + seconds
	_tick_frenzy()


# Frenzied: attacks the nearest creature, friend or foe
func _tick_frenzy() -> void:
	var best: Node3D = null
	var best_d := 18.0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == self or e.is_dead():
			continue
		var d := e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and p.global_position.distance_to(global_position) < best_d:
		best = p
	if best != null and best != _target:
		if best is Enemy:
			fight(best)
		else:
			_target = best
			_alerted = true
			if state == State.IDLE or state == State.WANDER or state == State.PATROL:
				_enter_state(State.CHASE)


## A harmful spell from someone: like being hit (it notices, gets angry or runs)
func on_hostile_magic(source: Node3D) -> void:
	if state == State.DEAD or source == null or source == self:
		return
	_calm_until = -1.0
	_alerted = true
	if source is Enemy and disposition == Disposition.HOSTILE:
		fight(source as Enemy)
		return
	if source is Enemy and has_meta("player_ally"):
		fight(source as Enemy)
		return
	match disposition:
		Disposition.NEUTRAL:
			if source.is_in_group("player") and not has_meta("player_ally"):
				disposition = Disposition.HOSTILE
				_drop_talk()
		Disposition.FRIENDLY:
			if has_meta("player_ally"):
				return
			_target = source
			_flee_until = _clock + flee_time
			_drop_talk()
			if state != State.STAGGER:
				_enter_state(State.FLEE)
			return
	if source.is_in_group("player"):
		_target = source
	if state == State.IDLE or state == State.WANDER or state == State.PATROL:
		_enter_state(State.CHASE)


## Who it is fighting (null for none)
func get_fight_target() -> Node3D:
	return _target if (state == State.CHASE or state == State.ATTACK) else null


func stop_fighting() -> void:
	if state == State.CHASE or state == State.ATTACK:
		_lose_target()


## Reanimate Corpse: gets back up and fights for `leader` for a while, then crumbles again
func reanimate(leader: Node3D, seconds: float) -> void:
	if state != State.DEAD:
		return
	var rag := get_node_or_null("Ragdoll") as Ragdoll
	var at := global_position
	if rag != null:
		rag.dismantle()
	if body != null:
		body.queue_free()
		body = null
	for c in get_children():
		if c is ContainerComponent:
			c.queue_free()
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = false
	if has_meta("interactable"):
		remove_meta("interactable")
	rotation = Vector3(0.0, rotation.y, 0.0)
	global_position = at + Vector3.UP * 0.4
	stats.revive()
	stats.modify_vital("health", -stats.health * 0.4)
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER
	disposition = Disposition.FRIENDLY
	display_name = "Risen " + display_name.trim_prefix("Risen ")
	placeholder_color = placeholder_color.lerp(Color(0.4, 0.45, 0.4), 0.5)
	add_to_group("enemies")
	remove_from_group("persistent")
	persist_mode = PersistMode.NEVER
	set_physics_process(true)
	set_process(true)
	_build_body()
	_refresh_weapon_visual()
	_enter_state(State.IDLE)
	AllyBrain.attach(self, leader)
	SpellFX.burst(self, global_position + Vector3.UP, 1.5, MagicEffects.SCHOOL_COLORS[&"conjuration"])
	get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and state != State.DEAD:
			stats.modify_vital("health", -stats.health - 1.0))


func _on_swing_finished() -> void:
	var w := equipment.get_main_hand() if equipment != null else null
	var combo_len := w.combo_length if w != null else 2
	if not _last_swing_heavy and _chain_count < mini(combo_len, 3) - 1 and randf() < chain_chance:
		_chain_count += 1
		_next_attack_at = _clock + 0.05  # straight into the next swing of the combo
	else:
		_chain_count = 0
		var pause := randf_range(attack_pause_min, attack_pause_max)
		_next_attack_at = _clock + pause * (1.5 if _last_swing_heavy else 1.0)


# Strafes around the player and keeps a sensible distance while waiting to swing
func _circle(to_target: Vector3, dist: float, delta: float) -> void:
	if to_target.length() < 0.01:
		return
	var forward := to_target.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var reach := _attack_start_distance()
	var want := right * _circle_dir * circle_speed
	if dist > reach * 0.9:
		want += forward * move_speed * 0.6
	elif dist < reach * 0.45:
		want -= forward * move_speed * 0.5
	velocity.x = move_toward(velocity.x, want.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, want.z, acceleration * delta)
	_circle_timer -= delta
	if _circle_timer <= 0.0:
		_circle_dir = -_circle_dir if randf() < 0.6 else _circle_dir
		_circle_timer = randf_range(1.0, 2.5)


# Only a couple of enemies swing at the same time; the others circle and wait their turn
func _attack_slot_free() -> bool:
	var committed := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var other := e as Enemy
		if other != null and other != self and other.is_attack_committed():
			committed += 1
	return committed < max_attackers


# ---------------------------------------------------------------- senses and helpers

func _target_usable() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	# Anything with a MeleeCombat (the player) tells us whether it is still alive
	var damageable: Variant = _target.get_meta("damageable", null)
	return damageable == null or damageable.is_alive()


func _can_see_target() -> bool:
	if not _target_usable():
		return false
	if _calm_until > _clock:
		return false
	# The player's Stealth decides when an unalerted creature has really seen them (darkness,
	# sneaking, Sneak skill). Once alerted it keeps track the simple way below.
	if not _alerted and _target.has_meta("stealth"):
		var stealth: Variant = _target.get_meta("stealth")
		if is_instance_valid(stealth):
			return stealth.is_detected_by(self) and _flat_to_target().length() <= maxf(detection_range, 6.0) * 1.5
	var flat := _flat_to_target()
	if flat.length() > detection_range:
		return false
	if not _alerted and field_of_view < 360.0 and flat.length() > 0.01:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		if forward.normalized().angle_to(flat.normalized()) > deg_to_rad(field_of_view * 0.5):
			return false
	# Only solid scenery blocks the view
	var query := PhysicsRayQueryParameters3D.create(head.global_position, _target.global_position + Vector3.UP * 1.2, WORLD_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or not (hit["collider"] is StaticBody3D)


func _flat_to_target() -> Vector3:
	var d := _target.global_position - global_position
	d.y = 0.0
	return d


func _attack_start_distance() -> float:
	return combat.get_main_reach() + attack_range_margin


func _face(to_target: Vector3, delta: float) -> void:
	if to_target.length() < 0.01:
		return
	var yaw := atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _facing_error(to_target: Vector3) -> float:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001 or to_target.length() < 0.001:
		return 0.0
	return forward.normalized().angle_to(to_target.normalized())


func _slow_down(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


# ---------------------------------------------------------------- telegraph visuals

# The placeholder weapon rises during the windup, drops through the hit window and returns; the
# body glows orange (red for a heavy swing) as the hit gets closer.
func _process(delta: float) -> void:
	if combat == null or state == State.DEAD:
		return
	var phase := combat.get_phase()
	var t := combat.get_phase_progress()
	var tilt := 25.0
	var glow := 0.0
	match phase:
		MeleeCombat.Phase.WINDUP:
			tilt = lerpf(25.0, 115.0, 1.0 - pow(1.0 - t, 2.0))
			glow = t
		MeleeCombat.Phase.ACTIVE:
			tilt = lerpf(115.0, -45.0, t * t)
			glow = 1.0
		MeleeCombat.Phase.RECOVERY:
			tilt = lerpf(-45.0, 25.0, t)
			glow = 1.0 - t
	if combat.is_stunned():
		tilt = 70.0  # arms flung up
	_weapon_tilt = lerpf(_weapon_tilt, tilt, clampf(delta * (35.0 if phase == MeleeCombat.Phase.ACTIVE else 16.0), 0.0, 1.0))
	if _weapon_pivot != null:
		_weapon_pivot.rotation_degrees.x = _weapon_tilt
	_tint = lerpf(_tint, glow, clampf(delta * 20.0, 0.0, 1.0))
	if _material != null:
		_material.emission = Color(1.0, 0.15, 0.1) if combat.is_heavy_action() else Color(1.0, 0.5, 0.1)
		_material.emission_energy_multiplier = _tint * 1.6
	if body != null and _special == &"":
		body.set_glow(_tint, Color(1.0, 0.15, 0.1) if combat.is_heavy_action() else Color(1.0, 0.5, 0.1))


# ---------------------------------------------------------------- getting hurt and dying

func _on_damaged(info: DamageInfo, amount: float) -> void:
	_flash()
	var color := GOLD
	var size := 48
	if info.heavy or info.kind == &"slam":
		color = Color(1.0, 0.55, 0.15)
		size = 64
	if info.punish:
		color = Color(1.0, 0.3, 0.25)
	_popup(str(roundi(amount)) + ("!" if info.punish else ""), info.hit_position, color, size)
	if state != State.DEAD and info.kind != &"magic" or (info.kind == &"magic" and not info.dot):
		if _casting != null and randf() > cunning * 0.6:
			_cancel_cast()
		if _drinking > 0.0 and randf() < 0.6:
			_drinking = 0.0
		_calm_until = -1.0
	if info.killed or stats.is_dead:
		_killing_push = info.direction * (2.5 + info.knockback)
		var rag_now := get_node_or_null("Ragdoll") as Ragdoll
		if rag_now != null:
			rag_now._push(_killing_push)
	if state == State.DEAD:
		return
	_alerted = true
	# Hit by another creature (a guard, or a guard hit by a bandit): fight back against it. That
	# doesn't make a guard or a townsperson hostile to the player.
	var by_creature := info.source is Enemy and info.source != self and is_instance_valid(info.source)
	if by_creature and (disposition == Disposition.HOSTILE or (info.source as Enemy).disposition == Disposition.HOSTILE):
		fight(info.source as Enemy)
	if info.knockback > 0.0:
		var push := Vector3(info.direction.x, 0.0, info.direction.z)
		if push.length() > 0.001:
			velocity += push.normalized() * info.knockback * (1.0 - knockback_resistance)
	match disposition:
		Disposition.NEUTRAL:
			if by_creature:
				return  # busy fighting the creature (see fight())
			disposition = Disposition.HOSTILE  # provoked: it fights back from now on
			_drop_talk()
		Disposition.FRIENDLY:
			if by_creature:
				_target = info.source as Enemy  # run from what hit it
			_flee_until = _clock + flee_time
			_drop_talk()
			if state != State.STAGGER:
				_enter_state(State.FLEE)
			return
	if state == State.IDLE or state == State.WANDER or state == State.PATROL:
		_enter_state(State.CHASE)


func _drop_talk() -> void:
	if _talk != null and is_instance_valid(_talk):
		_talk.queue_free()
	_talk = null
	if has_meta("interactable") and not (get_meta("interactable") is ContainerComponent):
		remove_meta("interactable")


# The MeleeCombat stunned us (poise broke, a flinch, or a parry): stop whatever we were doing.
# It already cancelled the swing; this only switches the AI to its reeling state.
func _on_stunned(_duration: float) -> void:
	if state == State.DEAD or state == State.STAGGER:
		return
	_enter_state(State.STAGGER)


func _on_staggered(info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	if info != null:
		var push := Vector3(info.direction.x, 0.0, info.direction.z)
		if push.length() > 0.001:
			velocity += push.normalized() * 2.0 * (1.0 - knockback_resistance)
	_popup("STAGGERED", global_position + Vector3.UP * 2.1, Color(1.0, 0.7, 0.2), 40)


func _on_died() -> void:
	if state == State.DEAD:
		return
	_enter_state(State.DEAD)
	remove_from_group("enemies")
	if persist_mode == PersistMode.CORPSE_ONLY:
		add_to_group("persistent")  # its corpse (and what is still in it) is saved
	if spawn_key != "":
		WorldState.set_record("kill/" + spawn_key, {"dead": true})
	_drop_talk()
	set_physics_process(false)
	set_process(false)
	velocity = Vector3.ZERO
	combat.interrupt()
	combat.stop_block()
	if _material != null:
		_material.emission_energy_multiplier = 0.0
	# Out of the enemy layer: no more hits land on the body, and the player walks through it
	collision_layer = 0
	collision_mask = 0
	_cancel_cast()
	_drinking = 0.0
	var animated := animation.trigger(AnimationHooks.DEATH, animation_set)
	var rag: Ragdoll = null
	if body != null:
		body.set_glow(0.0, Color.BLACK)
		body.pose = &""
		if death_fall_placeholder or _lying_restore:
			rag = Ragdoll.create(self, body, _killing_push, _lying_restore)
	elif not animated and death_fall_placeholder:
		_fall_over()
	# Becomes a container (layer 3) holding this enemy's own inventory
	var container := ContainerComponent.attach(self, "%s's Body" % display_name, "Search", inventory, loot)
	if rag != null:
		# Only the limbs can be aimed at: the standing capsule is switched off
		collision_layer = 0
		for c in get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
		rag.set_interactable(container)
	died.emit(self)


func _fall_over() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "rotation:x", PI / 2.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", position.y + 0.4, 0.6)


func _flash() -> void:
	if body != null:
		body.flash()
	if _material == null:
		return
	_material.albedo_color = Color.WHITE
	create_tween().tween_property(_material, "albedo_color", placeholder_color, 0.2)


# Floating damage number
func _popup(text: String, pos: Vector3, color: Color, size: int = 48) -> void:
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		return
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	host.add_child(label)
	label.global_position = pos
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", pos.y + 0.8, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(label.queue_free)


# ---------------------------------------------------------------- saving

## What SaveManager stores for this enemy (alive or a corpse). A loaded enemy is calm again
## (idle), but keeps its health, gear, loot and position.
func get_persist_data() -> Dictionary:
	var loot_list: Array = []
	for entry in loot:
		var path := SaveUtil.item_to_path(entry.item) if entry != null else ""
		if path != "":
			loot_list.append({"item": path, "min": entry.min_count, "max": entry.max_count, "chance": entry.chance})
	var rolled := false
	for c in get_children():
		if c is ContainerComponent:
			rolled = (c as ContainerComponent).to_dict()["rolled"]
	return {
		"type": "enemy",
		"name": display_name,
		"body_kind": int(body_kind),
		"enemy_id": enemy_id,
		"level": level,
		"body_scale": body_scale,
		"color": placeholder_color.to_html(),
		"max_health": max_health,
		"base_damage": base_damage,
		"pos": SaveUtil.vec3_to_array(global_position),
		"rot": SaveUtil.vec3_to_array(rotation),
		"health": stats.health,
		"dead": state == State.DEAD,
		"inventory": inventory.to_dict(),
		"equipment": equipment.to_dict(),
		"loot": loot_list,
		"loot_rolled": rolled,
	}


static func restore(data: Dictionary, parent: Node) -> Enemy:
	var e := Enemy.new()
	e.display_name = String(data.get("name", "Bandit"))
	e.level = int(data.get("level", 1))
	e.body_scale = float(data.get("body_scale", 1.0))
	e.body_kind = clampi(int(data.get("body_kind", CreatureBody.kind_for(String(data.get("enemy_id", ""))))), 0, 3) as CreatureBody.Kind
	e.enemy_id = String(data.get("enemy_id", ""))
	e.placeholder_color = Color.html(String(data.get("color", "b33333ff")))
	e.max_health = float(data.get("max_health", 60.0))
	e.base_damage = float(data.get("base_damage", 3.0))
	for entry in data.get("loot", []):
		var item := SaveUtil.path_to_item(String(entry.get("item", "")))
		if item == null:
			continue
		var l := LootEntry.new()
		l.item = item
		l.min_count = int(entry.get("min", 1))
		l.max_count = int(entry.get("max", 1))
		l.chance = float(entry.get("chance", 1.0))
		e.loot.append(l)

	var pos := SaveUtil.array_to_vec3(data.get("pos"))
	var rot := SaveUtil.array_to_vec3(data.get("rot"))
	e.position = pos  # before entering the tree, see spawn()
	parent.add_child(e)  # _ready builds Stats / Inventory / Equipment / MeleeCombat
	e.global_position = pos
	e.rotation = rot
	e.inventory.from_dict(data.get("inventory", {}))
	e.equipment.from_dict(data.get("equipment", {}))

	if bool(data.get("dead", false)):
		# Die without the fall-over animation: the saved pose already IS the fallen pose
		e.death_fall_placeholder = false
		e._lying_restore = true
		e.stats.modify_vital("health", -e.stats.health)
		e._lying_restore = false
		e.death_fall_placeholder = true
		e.global_position = pos
		e.rotation = rot
		for c in e.get_children():
			if c is ContainerComponent:
				(c as ContainerComponent).from_dict({"rolled": bool(data.get("loot_rolled", false))})
	else:
		e.stats.modify_vital("health", float(data.get("health", e.max_health)) - e.stats.health)
	return e
