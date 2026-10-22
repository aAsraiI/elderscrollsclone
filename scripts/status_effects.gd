class_name StatusEffects
extends Node
## Timed effects from food and potions. Lives under the Player (player.gd adds it if missing).
##
## An effect is a set of stat modifiers with a timer, so Stats does the actual work:
##   food    "health_regen" (HP per second, slow and long) and "stamina_regen_mult"
##   potion  a big "health_regen" for a few seconds, like drinking from an estus flask
## Rules: only ONE food works at a time (a new meal replaces the old one), potions STACK. A short
## cooldown stops you mashing the key. Press H to drink the best-fitting health potion.
## Effects freeze while a menu pauses the game.

signal effect_started(effect: Dictionary)
signal effect_ended(effect: Dictionary)
signal item_used(item: ItemData)
## reason: &"cooldown", &"missing", &"dead", &"not_usable", &"no_potion"
signal use_failed(reason: StringName)

const SOURCE_PREFIX := "effect_"
const ACTION := "quick_heal"

@export var stats: Stats
@export var inventory: Inventory
## Seconds between two uses
@export var use_cooldown := 0.8
## Creates the little top-left readout (clock and active effects)
@export var create_hud := true

# Each: {"id", "item", "group", "remaining", "total", "mods"}
var _effects: Array[Dictionary] = []
var _next_id := 1
var _cooldown := 0.0


func _ready() -> void:
	var parent := get_parent()
	if stats == null:
		stats = parent.get_node_or_null("Stats") as Stats
	if inventory == null:
		inventory = parent.get_node_or_null("Inventory") as Inventory
	if stats == null or inventory == null:
		push_error("StatusEffects: could not find Stats / Inventory next to it.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_H
		InputMap.action_add_event(ACTION, ev)
	stats.died.connect(clear_effects)
	if create_hud and get_node_or_null("StatusHUD") == null:
		var hud := StatusHUD.new()
		hud.name = "StatusHUD"
		hud.effects = self
		add_child(hud)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	for i in range(_effects.size() - 1, -1, -1):
		_effects[i]["remaining"] = float(_effects[i]["remaining"]) - delta
		if float(_effects[i]["remaining"]) <= 0.0:
			_end(i)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not get_tree().paused:
		quick_heal()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- using things

## Eats / drinks one of `item` from the inventory. Returns false (and says why) if it could not.
func use_item(item: ItemData) -> bool:
	if stats == null or stats.is_dead:
		return _fail(&"dead")
	if item == null or not item.is_consumable():
		return _fail(&"not_usable")
	if _cooldown > 0.0:
		return _fail(&"cooldown")
	if not inventory.has_item(item):
		return _fail(&"missing")
	inventory.remove_item(item, 1)
	apply_effect(item)
	_cooldown = use_cooldown
	item_used.emit(item)
	return true


## Starts the effect of an item without touching the inventory (rewards, loading a save)
func apply_effect(item: ItemData, remaining: float = -1.0) -> void:
	if item == null or not item.is_consumable():
		return
	if item.effect_group == "food":
		for i in range(_effects.size() - 1, -1, -1):
			if _effects[i]["group"] == "food":
				_end(i)
	var total := item.effect_duration
	var fx := {
		"id": _next_id,
		"item": item,
		"group": item.effect_group,
		"total": total,
		"remaining": total if remaining <= 0.0 else minf(remaining, total),
		"mods": item.get_effect_mods(),
	}
	_next_id += 1
	_effects.append(fx)
	stats.add_modifiers(SOURCE_PREFIX + str(fx["id"]), fx["mods"])
	effect_started.emit(fx)


## H key: drinks the smallest health potion that covers what you are missing, or the strongest
## if none does. Fails with use_failed(&"no_potion") if you carry none.
func quick_heal() -> bool:
	var missing := stats.get_stat("max_health") - stats.health
	var best: ItemData = null
	for s in inventory.stacks:
		var it: ItemData = s.item
		if not it.is_consumable() or it.effect_group != "potion" or it.heal_amount <= 0.0:
			continue
		if best == null:
			best = it
			continue
		var best_covers := best.heal_amount >= missing
		var it_covers := it.heal_amount >= missing
		if it_covers and not best_covers:
			best = it
		elif it_covers == best_covers:
			if (it_covers and it.heal_amount < best.heal_amount) or (not it_covers and it.heal_amount > best.heal_amount):
				best = it
	if best == null:
		return _fail(&"no_potion")
	return use_item(best)


func clear_effects() -> void:
	for i in range(_effects.size() - 1, -1, -1):
		_end(i)


func _end(index: int) -> void:
	var fx := _effects[index]
	_effects.remove_at(index)
	stats.remove_modifiers(SOURCE_PREFIX + str(fx["id"]))
	effect_ended.emit(fx)


func _fail(reason: StringName) -> bool:
	use_failed.emit(reason)
	return false


# ---------------------------------------------------------------- queries

func get_active() -> Array[Dictionary]:
	return _effects.duplicate()


func has_effect_from(item: ItemData) -> bool:
	for fx in _effects:
		if fx["item"] == item:
			return true
	return false


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var out: Array = []
	for fx in _effects:
		var path := SaveUtil.item_to_path(fx["item"])
		if path != "":
			out.append({"item": path, "remaining": fx["remaining"]})
	return {"effects": out}


## Load Stats (and gear) first so the modifiers land on the right numbers
func from_dict(data: Dictionary) -> void:
	clear_effects()
	for entry in data.get("effects", []):
		var item := SaveUtil.path_to_item(String(entry.get("item", "")))
		if item != null:
			apply_effect(item, maxf(float(entry.get("remaining", 1.0)), 0.05))
