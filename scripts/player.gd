extends CharacterBody3D
## Simple first-person controller (Godot 4.x)
## Expected node layout:
##   Player (CharacterBody3D)  <- this script
##   ├── CollisionShape3D      (CapsuleShape3D, height 1.8, radius 0.4, y = 0.9)
##   └── Head (Node3D)         (y = 1.6)
##       └── Camera3D
## It adds StatusEffects (food / potions, H = quick potion) and PauseMenu (Esc) itself if missing.
## Optional sibling nodes it uses if present: Stats (move speed from Agility), Skills (Athletics XP),
## MeleeCombat (slower while blocking), Grabber (slower while dragging, made by the Interactor). Combat nodes: MeleeCombat + PlayerCombat, see melee_combat.gd.

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var ground_accel: float = 12.0
@export var air_accel: float = 3.0
## Athletics XP per second of sprinting, and per jump (scaled by the skill's own XP rate)
@export var sprint_xp_per_second: float = 1.0
@export var jump_xp: float = 0.5
## Testing helpers: put the example weapons in your inventory and spawn one enemy in front of you.
## Turn both off when you start building the real world.
@export var give_test_loadout := true
@export var spawn_test_enemy := true
## When you die: show "YOU DIED" and reload the scene after a few seconds (no save system yet)
@export var reload_on_death := true

const ENEMY_LAYER := 16  # physics layer 5, see Enemy
const TEST_ITEMS := [
	["res://scripts/Resources/iron_dagger.tres", 2],
	["res://scripts/Resources/iron_shield.tres", 1],
	["res://scripts/Resources/iron_warhammer.tres", 1],
	["res://scripts/Resources/steel_greatsword.tres", 1],
	["res://scripts/Resources/Consumables/gold.tres", 150],
	["res://scripts/Resources/Consumables/apple.tres", 4],
	["res://scripts/Resources/Consumables/bread.tres", 3],
	["res://scripts/Resources/Consumables/hearty_stew.tres", 2],
	["res://scripts/Resources/Consumables/minor_health_potion.tres", 3],
	["res://scripts/Resources/Consumables/health_potion.tres", 2],
	["res://scripts/Resources/Misc/lockpick.tres", 10],
]

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var _stats: Stats = get_node_or_null("Stats") as Stats
@onready var _skills: Skills = get_node_or_null("Skills") as Skills
@onready var _combat: MeleeCombat = get_node_or_null("MeleeCombat") as MeleeCombat

var _sprint_timer := 0.0
var _dead := false

func _ready() -> void:
	add_to_group("player")  # enemies look for this group
	collision_mask |= ENEMY_LAYER  # so you can't walk through enemies
	# Registered first so the physics loop never asks for an action that doesn't exist yet
	_register_input_actions()
	_ensure_helpers()

	var sword: ItemData = load("res://scripts/Resources/iron_sword.tres")
	var armor: ItemData = load("res://scripts/Resources/iron_chestplate.tres")

	$Inventory.add_item(sword)
	$Inventory.add_item(armor)
	$Equipment.equip(sword)

	if give_test_loadout:
		for entry in TEST_ITEMS:
			var item := load(entry[0]) as ItemData
			if item == null:
				push_warning("Test loadout: %s not found. Copy the weapon .tres files into scripts/Resources." % entry[0])
				continue
			$Inventory.add_item(item, entry[1])

	if _stats != null:
		_stats.died.connect(_on_died)

	await get_tree().process_frame

	var spawn_pos := global_position - global_transform.basis.z * 2.0 + Vector3.UP
	var w := WorldItem.spawn(sword, 1, get_tree().current_scene, spawn_pos)
	print("spawned at: ", w.global_position)

	if spawn_test_enemy:
		var enemy_pos := global_position - global_transform.basis.z * 7.0 + Vector3.UP * 0.5
		var enemy := Enemy.spawn(get_tree().current_scene, enemy_pos, sword)
		enemy.rotation.y = rotation.y + PI  # face the player, it only notices you inside its view cone
		var drop := LootEntry.new()
		drop.item = load("res://scripts/Resources/iron_dagger.tres") as ItemData
		if drop.item != null:
			enemy.loot.append(drop)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	# Mouse look: yaw rotates the body, pitch rotates only the head
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	# Esc opens the pause screen (PauseMenu). A click captures the mouse again if it got loose.
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	# Gravity and jumping
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		if _skills != null:
			_skills.add_xp(&"athletics", jump_xp)

	# Horizontal movement relative to where the player is facing
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var sprinting: bool = Input.is_action_pressed("sprint")
	var speed: float = (sprint_speed if sprinting else walk_speed) * _get_speed_multiplier()
	var accel: float = ground_accel if is_on_floor() else air_accel

	velocity.x = lerpf(velocity.x, direction.x * speed, accel * delta)
	velocity.z = lerpf(velocity.z, direction.z * speed, accel * delta)

	move_and_slide()

	# Sprinting trains Athletics. XP is handed over once per second instead of every frame.
	if _skills != null and sprinting and input_dir != Vector2.ZERO and is_on_floor():
		_sprint_timer += delta
		if _sprint_timer >= 1.0:
			_sprint_timer -= 1.0
			_skills.add_xp(&"athletics", sprint_xp_per_second)


# Agility raises this above 1.0 (see Stats.ATTRIBUTE_EFFECTS); blocking and heavy loads slow you down
func _get_speed_multiplier() -> float:
	var m := 1.0
	if _stats != null:
		m = _stats.get_stat("move_speed_mult")
		m = m if m > 0.0 else 1.0
	if _combat != null:
		m *= _combat.get_move_speed_multiplier()
	# Holding something with the Grabber (items barely, corpses a lot)
	var grabber: Variant = get_meta("grabber", null)
	if grabber != null and is_instance_valid(grabber):
		m *= grabber.get_move_speed_multiplier()
	var stealth := get_node_or_null("Stealth") as Stealth
	if stealth != null:
		m *= stealth.get_speed_mult()
	return m


# Nodes the player needs that older scenes don't have yet: eating / drinking and the pause screen
func _ensure_helpers() -> void:
	if get_node_or_null("StatusEffects") == null:
		var fx := StatusEffects.new()
		fx.name = "StatusEffects"
		add_child(fx)
	if get_node_or_null("PauseMenu") == null:
		var pm := PauseMenu.new()
		pm.name = "PauseMenu"
		add_child(pm)
	if get_node_or_null("CompassHUD") == null:
		var compass := CompassHUD.new()
		compass.name = "CompassHUD"
		add_child(compass)
	if get_node_or_null("Stealth") == null:
		var stealth := Stealth.new()
		stealth.name = "Stealth"
		add_child(stealth)
	if get_node_or_null("DialogueUI") == null:
		var dlg := DialogueUI.new()
		dlg.name = "DialogueUI"
		add_child(dlg)
	if get_node_or_null("BarterUI") == null:
		var barter := BarterUI.new()
		barter.name = "BarterUI"
		add_child(barter)
	if get_node_or_null("JournalUI") == null:
		var journal := JournalUI.new()
		journal.name = "JournalUI"
		add_child(journal)


func _on_died() -> void:
	_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 20
	var label := Label.new()
	label.text = "YOU DIED"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(0.75, 0.1, 0.1))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)
	add_child(layer)
	if reload_on_death:
		await get_tree().create_timer(3.0).timeout
		get_tree().paused = false
		get_tree().reload_current_scene()


## Adds WASD / Space / Shift actions in code so no Input Map setup is needed.
## Later, you can move these into Project Settings > Input Map and delete this.
func _register_input_actions() -> void:
	var bindings := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = bindings[action]
		InputMap.action_add_event(action, ev)
