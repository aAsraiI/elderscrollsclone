class_name QuestMarkers
extends Node
## Small marks in the world, each switchable in Settings > Interface:
##   ?  over someone you can hand a quest in to, or must talk to next (gold; blue when
##      colourblind-safe markers are on)
##   !  over someone with a quest to offer (faint; off by default)
##   quest items on the ground glow, and containers holding one say so in their prompt
## Created by WorldManager. Looks at the people near you twice a second.

const RANGE := 45.0
const READY_COLOR := Color(1.0, 0.82, 0.3)
const OFFER_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const SAFE_READY := Color(0.4, 0.7, 1.0)

var world: WorldManager
var _timer := 0.0


func _ready() -> void:
	world = get_parent() as WorldManager


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or world == null:
		return
	_timer = 0.5
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var show_ready := bool(GameSettings.get_value("quest_npc_markers"))
	var show_offer := bool(GameSettings.get_value("quest_offer_markers"))
	for e in ActorRegistry.near(p.global_position, RANGE):
		if e.is_dead() or e.disposition == Enemy.Disposition.HOSTILE or e.talk_name == "":
			_set_mark(e, "")
			continue
		var kind := mark_for(DialogueEngine.speaker_for(e, world)) if show_ready or show_offer else ""
		if (kind == "ready" and not show_ready) or (kind == "offer" and not show_offer):
			kind = ""
		_set_mark(e, kind)
	if bool(GameSettings.get_value("quest_item_glow")):
		for it in get_tree().get_nodes_in_group("world_items"):
			var wi := it as WorldItem
			if wi != null and QuestItems.is_quest_item(wi.item) and not wi.has_meta("quest_glow"):
				_glow(wi)


## "ready" (hand in, or talk to them next), "offer" (has a quest for you) or ""
func mark_for(s: DialogueEngine.Speaker) -> String:
	if s == null or s.asleep or world.quests == null:
		return ""
	var topics := world.quests.extra_topics(s)
	var hooks := {}
	for id in QuestBook.ids():
		hooks[String(QuestBook.get_def(id)["hook"])] = true
	for d in QuestRunner.all():
		hooks[d.hook] = true
	var offer := false
	for t in topics:
		if t == QuestManager.REPORT or t.begins_with("take the ") or t == "a delivery":
			return "ready"
		if hooks.has(t):
			offer = true
		elif not QuestManager.TOPICS.has(t) and not Marriage.topics_for(s).has(t) and not Homestead.topics_for(s).has(t):
			return "ready"  # the next step of a quest is to talk to them
	return "offer" if offer else ""


func _set_mark(e: Enemy, kind: String) -> void:
	var label := e.get_node_or_null("QuestMark") as Label3D
	if kind == "":
		if label != null:
			label.queue_free()
		return
	if label == null:
		label = Label3D.new()
		label.name = "QuestMark"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 64
		label.outline_size = 12
		label.position = Vector3(0, 2.45, 0)
		e.add_child(label)
	var safe := bool(GameSettings.get_value("colorblind_markers"))
	label.text = "?" if kind == "ready" else "!"
	label.modulate = (SAFE_READY if safe else READY_COLOR) if kind == "ready" else OFFER_COLOR
	label.pixel_size = 0.004 if kind == "ready" else 0.003


func _glow(wi: WorldItem) -> void:
	wi.set_meta("quest_glow", true)
	var light := OmniLight3D.new()
	light.light_color = SAFE_READY if bool(GameSettings.get_value("colorblind_markers")) else READY_COLOR
	light.light_energy = 0.8
	light.omni_range = 1.6
	light.position = Vector3(0, 0.3, 0)
	wi.add_child(light)
