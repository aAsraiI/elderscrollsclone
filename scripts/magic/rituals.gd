class_name Rituals
extends Node
## Alpha 1.28.3: rituals and research.
##
## RITUALS: a ritual book (Mages Guild halls sell them) teaches nothing by itself: you perform it,
## standing in a ritual circle, by using the book (E in the inventory). It takes RITUAL_SECONDS of
## channelling: move, or get hurt, and it breaks. It costs magicka and a filled soul gem.
##   Call the Storm      a thunderstorm; everything hostile within 40 m is struck by lightning
##   Raise the Fallen    every body within 20 m rises to fight for you for 3 minutes
##   Dawn's Blessing     +25% health, magicka and stamina for half an hour
##   Ward of Ages        a ward of 400 points on you and everyone who follows you
## A circle: Ritual Chalk draws one where you stand (it fades after an hour); Altars of Spellmaking
## are circles too.
##
## RESEARCH: Mages Guild members can ask a guild mage about "magical research": for gold and a day's
## work, the guild works out an effect you don't know yet, and the spellmaker can use it (Spellbook.
## known_effects). Kept in WorldState "research" {"ids"}.
##
## Lives under the Player (player.gd adds it).

const RITUAL_SECONDS := 6.0
const MAGICKA := 120.0
const CIRCLE_REACH := 3.0
const CIRCLE_HOURS := 1.0
## id -> [name, what it does]
const LIST := {
	"storm": ["Call the Storm", "A thunderstorm; everything hostile within 40 m is struck by lightning."],
	"raise": ["Raise the Fallen", "Every body within 20 m rises to fight for you for 3 minutes."],
	"dawn": ["Dawn's Blessing", "+25% health, magicka and stamina for half an hour."],
	"ward": ["Ward of Ages", "A 400-point ward on you and everyone who follows you."],
}
const RESEARCH_DAYS := 1.0
## Dawn's Blessing lasts this many real seconds (about a game day at the usual speed)
const DAWN_SECONDS := 1800.0

var _player: CharacterBody3D
var _channel := ""
var _left := 0.0
var _start := Vector3.ZERO
var _hp := 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D


static func of(player: Node) -> Rituals:
	return player.get_node_or_null("Rituals") as Rituals if player != null else null


static func ritual_of(item: ItemData) -> String:
	if item == null or not String(item.id).begins_with("ritual_book_"):
		return ""
	return String(item.id).trim_prefix("ritual_book_")


static func in_circle(player: Node3D) -> bool:
	for c in player.get_tree().get_nodes_in_group("ritual_circles"):
		if (c as Node3D).global_position.distance_to(player.global_position) <= CIRCLE_REACH:
			return true
	return false


## Ritual Chalk: a circle on the ground where you stand
static func draw_circle(player: Node3D, chalk: ItemData) -> String:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.1
	tm.outer_radius = 2.3
	tm.rings = 32
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.05, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.5, 0.9)
	mat.emission_energy_multiplier = 0.6
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_to_group("ritual_circles")
	player.get_tree().current_scene.add_child(ring)
	ring.global_position = player.global_position + Vector3.UP * 0.03
	player.get_tree().create_timer(CIRCLE_HOURS * 60.0, false).timeout.connect(func() -> void:
		if is_instance_valid(ring):
			ring.queue_free())
	(player.get_node("Inventory") as Inventory).remove_item(chalk, 1)
	return "You draw a ritual circle in chalk."


## Starts the ritual (the book stays). "" = channelling.
func perform(id: String) -> String:
	if not LIST.has(id):
		return "The words make no sense."
	if _channel != "":
		return "You are already in a ritual."
	if not in_circle(_player):
		return "A ritual needs a circle: draw one with Ritual Chalk, or use an Altar of Spellmaking."
	var stats := _player.get_node("Stats") as Stats
	if stats.magicka < MAGICKA:
		return "You need %d magicka." % MAGICKA
	var inv := _player.get_node("Inventory") as Inventory
	var gem := _filled_gem(inv)
	if gem == null:
		return "A ritual needs a filled soul gem to feed it."
	inv.remove_item(gem, 1)
	stats.modify_vital("magicka", -MAGICKA)
	_channel = id
	_left = RITUAL_SECONDS
	_start = _player.global_position
	_hp = stats.health
	Locks.toast(get_tree(), "You begin %s. Stand still..." % LIST[id][0])
	return ""


func is_channelling() -> bool:
	return _channel != ""


func _filled_gem(inv: Inventory) -> ItemData:
	for s in inv.stacks:
		if s.item != null and s.item.soul_filled:
			return s.item
	return null


func _process(delta: float) -> void:
	if _channel == "" or get_tree().paused:
		return
	var stats := _player.get_node("Stats") as Stats
	if _player.global_position.distance_to(_start) > 1.0 or stats.health < _hp - 0.5:
		Locks.toast(get_tree(), "The ritual breaks.", true)
		_channel = ""
		return
	_left -= delta
	if _left > 0.0:
		return
	var id := _channel
	_channel = ""
	Locks.toast(get_tree(), finish(id))


## The ritual's effect (tests call it directly)
func finish(id: String) -> String:
	var sk := _player.get_node_or_null("Skills") as Skills
	if sk != null:
		sk.add_xp(&"mysticism", 25.0)
		sk.add_xp(&"conjuration" if id == "raise" else &"alteration", 15.0)
	Achievements.note("ritual")
	match id:
		"storm":
			var w := Weather.get_instance(get_tree())
			if w != null:
				w.set_weather(Weather.Kind.STORM, 3.0)
			var n := 0
			for e in ActorRegistry.near(_player.global_position, 40.0):
				var foe := e as Enemy
				if foe != null and not foe.is_dead() and foe.disposition == Enemy.Disposition.HOSTILE:
					var m := ActiveMagic.of(foe)
					if m != null:
						m.apply_one({"id": "shock_damage", "mag": 60.0 + (float(sk.get_level(&"destruction")) if sk != null else 0.0) * 1.5, "dur": 0.0}, _player, "Call the Storm", "spell")
						n += 1
			return "The sky splits. Lightning finds %d foe%s." % [n, "" if n == 1 else "s"]
		"raise":
			var n := 0
			for e in ActorRegistry.near(_player.global_position, 20.0):
				var body := e as Enemy
				if body != null and body.is_dead() and not body.has_meta("npc_id"):
					body.reanimate(_player, 180.0)
					n += 1
			return "%d of the dead rise to serve you." % n if n > 0 else "There are no dead here to answer."
		"dawn":
			var stats := _player.get_node("Stats") as Stats
			var m := ActiveMagic.of(_player)
			if m != null:
				for v in [["fortify_health", "max_health"], ["fortify_magicka", "max_magicka"], ["fortify_stamina", "max_stamina"]]:
					m.apply_one({"id": v[0], "mag": roundf(stats.get_stat(v[1]) * 0.25), "dur": DAWN_SECONDS}, _player, "Dawn's Blessing", "ritual")
			return "Dawn's light fills you."
		"ward":
			var who: Array[Node3D] = [_player]
			var f := _player.get_node_or_null("Followers") as Followers
			if f != null:
				for e in f.followers:
					if is_instance_valid(e):
						who.append(e)
			for n in who:
				var m := ActiveMagic.of(n)
				if m != null:
					m.apply_one({"id": "ward", "mag": 400.0, "dur": 120.0}, _player, "Ward of Ages", "spell")
			return "A ward of ages settles over %d of you." % who.size()
	return ""


# ---------------------------------------------------------------- research

static func researched() -> Array:
	return (WorldState.get_record("research").get("ids", []) as Array)


## Effects the guild could still work out: in some premade spell, not yet known or researched
static func open_research(player: Node) -> Array[StringName]:
	var book := player.get_node_or_null("Spellbook") as Spellbook
	var known := book.known_effects() if book != null else []
	var out: Array[StringName] = []
	for id in SpellCatalog.all_ids():
		if SpellCatalog.rank_of(id) > 6:
			continue
		for e in SpellCatalog.get_spell(id).effects:
			var eid := StringName(e["id"])
			if not known.has(eid) and not out.has(eid) and not String(eid).begins_with("summon_") and not String(eid).begins_with("bound_"):
				out.append(eid)
	return out


static func research_cost(eid: StringName) -> int:
	var d := MagicEffects.get_def(eid)
	return 250 + roundi(float(d.get("cost", 1.0)) * 120.0)


static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s != null and not s.asleep and s.faction == "mages" and Factions.is_member("mages"):
		out.append("magical research")
	return out


static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, world: WorldManager) -> Dictionary:
	if topic != "magical research" or not topics_for(s).has(topic):
		return {}
	var open := open_research(player)
	if open.is_empty():
		return {"text": "There is nothing left that we could teach you. You know as much as the guild.", "journal": "", "learn": []}
	open.sort_custom(func(a: StringName, b: StringName) -> bool: return research_cost(a) < research_cost(b))
	var eid := open[0]
	var cost := research_cost(eid)
	var inv := player.get_node("Inventory") as Inventory
	var name := String(MagicEffects.get_def(eid).get("name", eid))
	if Currency.get_gold(inv) < cost:
		return {"text": "We could work out %s for you next: %d gold for the reagents and a day of our time. Come back with the gold." % [name, cost], "journal": "", "learn": []}
	Currency.spend_gold(inv, cost)
	var ids := researched().duplicate()
	ids.append(String(eid))
	WorldState.set_record("research", {"ids": ids})
	if world != null and world.clock != null:
		world.clock.advance_hours(24.0 * RESEARCH_DAYS)
	Achievements.note("research")
	return {"text": "A day of candles and old books, and %d gold. But it is done: %s is yours to use at the Altar of Spellmaking." % [cost, name],
		"journal": "The Mages Guild researched %s for me; I can use it at the Altar of Spellmaking." % name, "learn": []}
