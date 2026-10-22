class_name ItemData
extends Resource
## One of these per item type. Create in the editor: FileSystem > right-click >
## New Resource > ItemData, then save as e.g. res://items/iron_sword.tres

enum ItemType { MISC, WEAPON, ARMOR, CONSUMABLE, INGREDIENT, KEY }
enum EquipSlot { NONE, HEAD, CHEST, HANDS, LEGS, FEET, MAIN_HAND, OFF_HAND, RING, AMULET }
## SINGLE = one target (a few rays close together, nearest target wins).
## ARC = the swing sweeps a fan of rays across arc_degrees and hits everything it touches.
enum AttackStyle { SINGLE, ARC }
## What the right mouse button does while this item is equipped
enum SecondaryAction { NONE, BLOCK, SLAM }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var item_type: ItemType = ItemType.MISC
@export var equip_slot: EquipSlot = EquipSlot.NONE
@export var weight: float = 0.0
@export var value: int = 0
@export var stackable: bool = false
@export var max_stack: int = 1
## Which skill governs this item. A weapon in the main hand gets that skill's damage bonus,
## and hitting things with it (or blocking with a "block" item) trains that skill.
## "none" = no skill.
@export_enum("none", "one_handed", "two_handed", "archery", "light_armor", "heavy_armor", "block") var governing_skill: String = "none"
## Stat bonuses while equipped, e.g. {"armor": 10, "max_stamina": 15}.
## Weapons do NOT put their damage here any more, use weapon_damage below.
@export var stat_modifiers: Dictionary = {}
## Optional 3D model shown when the item is lying in the world
@export var world_scene: PackedScene

@export_group("Progression")
## 1 = Iron .. 7 = Starforged. Loot tables hand out gear by tier (see LevelCurve).
@export_range(1, 7) var tier: int = 1
## The level at which this tier of gear starts showing up in the world
@export var min_level: int = 1

@export_group("Trade")
## Gems, jewelry, relics: worth little to carry but a lot to sell. Jewelers and pawnbrokers pay
## close to full value for them (see MerchantData.treasure_rate).
@export var treasure: bool = false

@export_group("Consumable (food and potions)")
## Button text in the inventory: "Eat", "Drink", "Use"
@export var use_verb: String = "Use"
## food = slow regen, one meal at a time (a new meal replaces the old one).
## potion = quick heal, potions stack with each other.
@export_enum("food", "potion") var effect_group: String = "food"
## Health restored in total, spread evenly over effect_duration. 0 = none.
@export var heal_amount: float = 0.0
## Seconds the effect lasts. Food: a minute or more. Potions: a few seconds.
@export var effect_duration: float = 1.0
## Added to the stamina regen multiplier while the effect lasts (0.5 = stamina comes back 50% faster)
@export var stamina_regen_bonus: float = 0.0

@export_group("Weapon")
## Added to the wielder's base damage stat. Each hand hits with its own weapon's damage.
@export var weapon_damage: float = 0.0
## How far the attack rays reach, in meters, measured from the camera (or the enemy's head)
@export var reach: float = 2.0
@export var attack_style: AttackStyle = AttackStyle.SINGLE
## Width of the swing (ARC weapons only)
@export_range(10.0, 360.0, 1.0) var arc_degrees: float = 90.0
## Total seconds of one swing from click to being ready again (windup + hit window + recovery).
## Bigger = slower weapon.
@export var attack_cooldown: float = 0.6
## Seconds between the click and the weapon starting to hurt things (the wind-up).
## Enemies are told about the swing here, so a longer windup is easier to react to.
@export var attack_windup: float = 0.1
## Seconds the swing can hit things (the hit window). ARC weapons sweep their arc over this time.
@export var attack_active: float = 0.14
@export var stamina_cost: float = 0.0
## Push the target away on a hit (meters per second of velocity)
@export var knockback: float = 0.0
## How much one hit chips at the target's poise. When poise runs out the target staggers
## (can't act for a moment and takes bonus damage). Daggers low, hammers and greatswords high.
@export var poise_damage: float = 15.0
## Light swings in a combo chain. The last one is a finisher: more damage, poise and knockback.
@export_range(1, 5) var combo_length: int = 3
## Needs both hands: equipping it clears the off hand
@export var two_handed: bool = false
## Can be held in the off hand too (daggers). Needs two copies in the inventory to wield two.
@export var can_dual_wield: bool = false

@export_group("Heavy attack (hold left click)")
## Seconds you must hold left click before releasing makes a heavy attack
@export var heavy_charge_time: float = 0.45
## Windup AFTER releasing a charged attack (you already wound up while holding)
@export var heavy_windup: float = 0.18
@export var heavy_damage_mult: float = 1.7
@export var heavy_stamina_mult: float = 2.0
@export var heavy_poise_mult: float = 2.0
## Extra reach (m) of a heavy attack
@export var heavy_reach_bonus: float = 0.3

@export_group("Right click")
@export var secondary_action: SecondaryAction = SecondaryAction.NONE
## SLAM: seconds before the slam can be used again
@export var secondary_cooldown: float = 3.0
## SLAM: seconds between the click and the impact
@export var secondary_windup: float = 0.4
@export var secondary_stamina_cost: float = 20.0
## SLAM: damage multiplier on top of the normal damage
@export var secondary_damage_mult: float = 1.5
## SLAM: splash radius in meters
@export var secondary_radius: float = 3.0
## BLOCK: fraction of damage absorbed (0.6 = 60%)
@export_range(0.0, 1.0, 0.01) var block_reduction: float = 0.6
## BLOCK: only attacks from inside this cone in front of you are blocked
@export_range(10.0, 360.0, 1.0) var block_angle: float = 120.0
## BLOCK: raise the guard this many seconds before a hit lands and it is a PARRY:
## no damage, no stamina cost, and the attacker is staggered.
@export var parry_window: float = 0.2
## BLOCK: left click while blocking = shield bash. Small damage, big poise damage.
@export var bash_damage: float = 3.0
@export var bash_poise: float = 30.0
@export var bash_stamina_cost: float = 8.0

@export_group("Animation")
## Prefix for animation names, e.g. "sword" makes the combat code look for "sword_attack"
## first and plain "attack" second. Empty = only the plain names. Also picks the placeholder
## model shown in your hands (dagger, sword, greatsword, hammer, shield).
@export var animation_set: StringName = &""
## Optional model held in first person. Its origin is the grip; the blade points along +Y.
## Empty = a placeholder built from boxes. Any item worn in the main or off hand shows it.
@export var view_scene: PackedScene

@export_group("Models")
## Moves the first-person model from the grip point (meters: x right, y up along the blade, z back)
@export var view_offset := Vector3.ZERO
## Turns the first-person model (degrees). E.g. a model made lying down needs x = -90.
@export var view_rotation := Vector3.ZERO
## Makes the first-person model bigger or smaller
@export var view_scale := 1.0
## Makes the world model (World Scene, or View Scene if that is all there is) bigger or smaller
@export var world_scale := 1.0


## true for food and potions the player can eat or drink
func is_consumable() -> bool:
	return item_type == ItemType.CONSUMABLE and effect_duration > 0.0 and (heal_amount > 0.0 or stamina_regen_bonus > 0.0)


## The stat modifiers the effect holds while it is active (see StatusEffects)
func get_effect_mods() -> Dictionary:
	var mods := {}
	if heal_amount > 0.0 and effect_duration > 0.0:
		mods["health_regen"] = heal_amount / effect_duration
	if stamina_regen_bonus > 0.0:
		mods["stamina_regen_mult"] = stamina_regen_bonus
	return mods


## BBCode lines for the item screens: damage, reach, speed and what the mouse buttons do.
## Also describes what food and potions do.
func get_combat_description() -> String:
	var t := ""
	if is_consumable():
		if heal_amount > 0.0:
			t += "Restores %s health over %s s\n" % [String.num(heal_amount).trim_suffix(".0"), String.num(effect_duration).trim_suffix(".0")]
		if stamina_regen_bonus > 0.0:
			t += "Stamina regen +%d%% for %s s\n" % [roundi(stamina_regen_bonus * 100.0), String.num(effect_duration).trim_suffix(".0")]
		t += "Quick-drink with H\n" if effect_group == "potion" and heal_amount > 0.0 else "Only one meal works at a time\n"
	if item_type == ItemType.WEAPON:
		t += "Damage %s   Reach %.1f m   Swing %.2f s\n" % [String.num(weapon_damage).trim_suffix(".0"), reach, attack_cooldown]
		var style := "Swing arc %d°" % int(arc_degrees) if attack_style == AttackStyle.ARC else "Single target"
		if two_handed:
			style += "  ·  Two-handed"
		elif can_dual_wield:
			style += "  ·  Can dual wield"
		t += style + "\n"
		t += "Stagger %s   Combo x%d\n" % [String.num(poise_damage).trim_suffix(".0"), combo_length]
		t += "Hold left click: heavy attack  x%.1f damage, x%.1f stagger\n" % [heavy_damage_mult, heavy_poise_mult]
	match secondary_action:
		SecondaryAction.BLOCK:
			t += "Right click (hold): Block %d%% of damage. Raise it just before a hit to parry.\n" % roundi(block_reduction * 100.0)
			t += "Left click while blocking: Shield bash\n"
		SecondaryAction.SLAM:
			t += "Right click: Slam  x%.1f damage, %.1f m splash, %.0f s cooldown\n" % [secondary_damage_mult, secondary_radius, secondary_cooldown]
	return t
