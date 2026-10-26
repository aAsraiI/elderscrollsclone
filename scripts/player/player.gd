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
	["res://data/weapons/iron_dagger.tres", 2],
	["res://data/weapons/iron_shield.tres", 1],
	["res://data/weapons/iron_warhammer.tres", 1],
	["res://data/weapons/steel_greatsword.tres", 1],
	["res://data/consumables/gold.tres", 150],
	["res://data/consumables/apple.tres", 4],
	["res://data/consumables/bread.tres", 3],
	["res://data/consumables/hearty_stew.tres", 2],
	["res://data/consumables/minor_health_potion.tres", 3],
	["res://data/consumables/health_potion.tres", 2],
	["res://data/misc/lockpick.tres", 10],
]

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var _stats: Stats = get_node_or_null("Stats") as Stats
@onready var _skills: Skills = get_node_or_null("Skills") as Skills
@onready var _combat: MeleeCombat = get_node_or_null("MeleeCombat") as MeleeCombat

## For the body you see in third person (CreatureBody reads the same fields an Enemy has)
var state := 0
var combat: MeleeCombat
var equipment: Equipment
var display_name := "You"
var body_scale := 1.0
var placeholder_color := Color(0.35, 0.3, 0.42)
var _sprint_timer := 0.0
var _dead := false
## Set from Settings (GameSettings): mouse_sensitivity, invert_y and the camera's field of view
var invert_y := false


## GameSettings changed: mouse and field of view
func apply_settings() -> void:
	mouse_sensitivity = float(GameSettings.get_value("mouse_sensitivity"))
	invert_y = bool(GameSettings.get_value("invert_y"))
	var cam := get_node_or_null("Head/Camera3D") as Camera3D
	if cam != null:
		cam.fov = float(GameSettings.get_value("fov"))

# Runs before any child's _ready (the HUDs and helpers in player.tscn look for these)
func _enter_tree() -> void:
	add_to_group("player")  # enemies look for this group
	combat = get_node_or_null("MeleeCombat") as MeleeCombat
	equipment = get_node_or_null("Equipment") as Equipment
	# Registered first so no child and no physics frame asks for an action that doesn't exist yet
	Bindings.apply()  # your keys (Settings > Controls) and the controller layout
	_register_input_actions()


func _ready() -> void:
	collision_mask |= ENEMY_LAYER  # so you can't walk through enemies
	_ensure_helpers()  # player.tscn has them all; this only fills in any that were removed
	add_to_group("settings_listener")
	GameSettings.apply(get_tree())  # also calls apply_settings() below

	var sword: ItemData = load("res://data/weapons/iron_sword.tres")
	var armor: ItemData = load("res://data/weapons/iron_chestplate.tres")
	# A character made on the Character Creation screen starts with its own class gear instead of
	# the test loadout (and without the test enemy and sword). An exported game never gets them either.
	if not OS.is_debug_build():
		give_test_loadout = false
		spawn_test_enemy = false
	var created := CharacterSetup.has_pending()
	if created:
		give_test_loadout = false
		spawn_test_enemy = false
		CharacterSetup.apply(self, CharacterSetup.pending, not SaveSession.has_pending())
	else:
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

	if not created:
		var spawn_pos := global_position - global_transform.basis.z * 2.0 + Vector3.UP
		WorldItem.spawn(sword, 1, get_tree().current_scene, spawn_pos)

	if spawn_test_enemy:
		var enemy_pos := global_position - global_transform.basis.z * 7.0 + Vector3.UP * 0.5
		var enemy := Enemy.spawn(get_tree().current_scene, enemy_pos, sword)
		enemy.rotation.y = rotation.y + PI  # face the player, it only notices you inside its view cone
		var drop := LootEntry.new()
		drop.item = load("res://data/weapons/iron_dagger.tres") as ItemData
		if drop.item != null:
			enemy.loot.append(drop)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	# Mouse look: yaw rotates the body, pitch rotates only the head
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	# Esc opens the pause screen (PauseMenu). A click captures the mouse again if it got loose.
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if combat != null:
		state = Enemy.State.ATTACK if (combat.is_busy() or combat.is_blocking() or (equipment != null and equipment.get_main_hand() != null)) else Enemy.State.IDLE
	if _dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	# Controller: the right stick looks around
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.15 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sp := float(GameSettings.get_value("controller_look")) * delta
		rotate_y(-look.x * sp)
		head.rotate_x(-look.y * sp * (-1.0 if invert_y else 1.0))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	# Gravity and jumping
	if not is_on_floor():
		var fall := clampf(_stats.get_stat("fall_mult"), 0.1, 1.0) if _stats != null and velocity.y < 0.0 else 1.0
		velocity.y -= gravity * delta * fall
	elif Input.is_action_just_pressed("jump") and not _is_paralyzed():
		velocity.y = jump_velocity * sqrt(maxf(_stats.get_stat("jump_mult"), 0.2) if _stats != null else 1.0)
		if _skills != null:
			_skills.add_xp(&"athletics", jump_xp)

	# Horizontal movement relative to where the player is facing
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _is_paralyzed():
		input_dir = Vector2.ZERO
	# In deep water you swim; on a horse the horse moves (see Swimming, Rider)
	var swim := get_node_or_null("Swimming") as Swimming
	if swim != null and swim.is_swimming():
		swim.swim_move(delta, input_dir, Input.is_action_pressed("sprint"))
		return
	if has_meta("ladder") and is_instance_valid(get_meta("ladder")):
		(get_meta("ladder") as Ladder).climb(self, delta, input_dir)
		return
	if has_meta("boat"):
		(get_meta("boat") as Boat).steer(delta, input_dir, Input.is_action_pressed("sprint"))
		return
	var rider := get_node_or_null("Rider") as Rider
	if rider != null and rider.is_riding():
		rider.ride(delta, input_dir, Input.is_action_pressed("sprint"))
		return
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


## Paralyze (a spell, a poison): you can't move for a moment
func _is_paralyzed() -> bool:
	return has_meta("paralyzed_until") and Time.get_ticks_msec() < int(get_meta("paralyzed_until"))


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
	# Stage 10: magic on you, your spells, the casting hand, the Magic page, waiting, favorites
	if get_node_or_null("ActiveMagic") == null:
		ActiveMagic.attach(self)
	if get_node_or_null("Spellbook") == null:
		var book := Spellbook.new()
		book.name = "Spellbook"
		add_child(book)
	if get_node_or_null("SpellCaster") == null:
		var caster := SpellCaster.new()
		caster.name = "SpellCaster"
		add_child(caster)
	for extra in [["Afflictions", Afflictions], ["Survival", Survival], ["Powers", Powers], ["NightVision", NightVision], ["ThirdPerson", ThirdPerson], ["Swimming", Swimming], ["Rider", Rider], ["SoundFX", SoundFX], ["Tutorial", Tutorial], ["Followers", Followers], ["RangedCombat", RangedCombat], ["CouncilUI", CouncilUI], ["DebugConsole", DebugConsole], ["Homestead", Homestead]]:
		if get_node_or_null(extra[0]) == null:
			var n: Node = extra[1].new()
			n.name = extra[0]
			add_child(n)
	if get_node_or_null("MagicUI") == null:
		var mui := MagicUI.new()
		mui.name = "MagicUI"
		add_child(mui)
	if get_node_or_null("CraftingUI") == null:
		var cui := CraftingUI.new()
		cui.name = "CraftingUI"
		add_child(cui)
	if get_node_or_null("WaitMenu") == null:
		var wm := WaitMenu.new()
		wm.name = "WaitMenu"
		add_child(wm)
	if get_node_or_null("FavoritesMenu") == null:
		var fav := FavoritesMenu.new()
		fav.name = "FavoritesMenu"
		add_child(fav)
	if get_node_or_null("MenuHub") == null:
		var hub := MenuHub.new()
		hub.name = "MenuHub"
		add_child(hub)


func _on_died() -> void:
	_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 20
	var label := Label.new()
	label.text = "YOU DIED"
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.75, 0.1, 0.1))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)
	add_child(layer)
	# With a save to go back to: Load Last Save / Main Menu buttons. Without one: start over.
	var sm := get_tree().get_first_node_in_group("save_manager") as SaveManager
	var last := sm.latest_slot() if sm != null else ""
	if GameRules.ironman():
		# Ironman: one life. The save is gone; only the main menu is left.
		if sm != null and SaveSession.current_slot != "":
			sm.delete_slot(SaveSession.current_slot)
		last = ""
		reload_on_death = false
		label.text = "YOUR STORY ENDS HERE"
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	buttons.offset_top = 50
	buttons.offset_bottom = 84
	buttons.offset_left = -200
	buttons.offset_right = 200
	buttons.modulate.a = 0.0
	layer.add_child(buttons)
	if last != "":
		var load_b := Button.new()
		load_b.text = "Load Last Save"
		load_b.pressed.connect(func() -> void: sm.load_game(last))
		buttons.add_child(load_b)
		# Any other save: the death screen steps aside for the save list, and comes back if it's closed
		if sm.menu != null:
			var pick_b := Button.new()
			pick_b.text = "Load Game..."
			pick_b.pressed.connect(func() -> void:
				layer.visible = false
				sm.menu.closed.connect(func() -> void: layer.visible = true, CONNECT_ONE_SHOT)
				sm.menu.open_menu("", true))
			buttons.add_child(pick_b)
			buttons.offset_left = -280
			buttons.offset_right = 280
	var menu_b := Button.new()
	menu_b.text = "Main Menu"
	menu_b.pressed.connect(func() -> void: SaveManager.go_to_main_menu(get_tree()))
	buttons.add_child(menu_b)
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(buttons, "modulate:a", 1.0, 0.6)
	if reload_on_death and last == "":
		await get_tree().create_timer(3.0).timeout
		if not is_inside_tree():
			return
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
