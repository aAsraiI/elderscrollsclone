class_name Barks
extends Node
## Ambient lines: people you walk past say something now and then, over their heads (guards,
## merchants, townsfolk), depending on their job, the hour, and what their town thinks of you.
## Each person speaks at most once a minute. Created by WorldManager. Every line also goes through
## the voice hook (Barks.voice), silent until voice audio exists.

const RANGE := 7.0
const EVERY := 3.0
const QUIET := 60.0

var world: WorldManager
var _timer := 0.0
var _last := {}  # npc key -> time they last spoke (seconds)


func _ready() -> void:
	world = get_parent() as WorldManager


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or world == null or get_tree().paused:
		return
	_timer = EVERY
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for e in ActorRegistry.near(p.global_position, RANGE):
		if e.is_dead() or e.disposition == Enemy.Disposition.HOSTILE or e.talk_name == "" or e.state == Enemy.State.CHASE:
			continue
		var key := String(e.get_meta("npc_id", e.spawn_key))
		if now - float(_last.get(key, -999.0)) < QUIET:
			continue
		var talk := e.get_node_or_null("NpcTalk") as NpcTalk
		if talk == null:
			continue
		var line := bark_for(DialogueEngine.speaker_for(e, world))
		if line == "":
			continue
		_last[key] = now
		talk.say(line)
		voice(get_tree(), e.display_name, line)
		return  # one at a time


## A passing line for this person ("" = they say nothing)
func bark_for(s: DialogueEngine.Speaker) -> String:
	if s == null or s.asleep:
		return ""
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	var night := world.clock != null and world.clock.is_night()
	var k := absi(("%s|bark|%d" % [s.id, Time.get_ticks_msec() / 60000]).hash())
	if town != "" and Reputation.infamy(town) >= 20:
		return ["That's the one. Watch your purse.", "Keep walking.", "Guards should've hanged that one."][k % 3]
	if town != "" and Reputation.fame(town) >= 25:
		return ["Look, it's them! The one who helped us.", "Thank you, friend.", "%s owes you, you know." % town][k % 3]
	match s.role:
		NpcData.Role.GUARD:
			return (["Stay out of the shadows.", "Quiet night. Keep it that way."] if night else ["Move along.", "No trouble, now.", "I've got my eye on you."])[k % (2 if night else 3)]
		NpcData.Role.MERCHANT, NpcData.Role.SMITH:
			return "" if night else ["Fine wares, fair prices!", "Need anything? Come in, come in.", "Best goods in %s." % town][k % 3]
		NpcData.Role.INNKEEPER:
			return ["Warm beds and cold ale inside!", "Hungry? The stew's on."][k % 2]
	if k % 3 != 0:
		return ""  # most people just walk by
	return (["Late to be about.", "Can't sleep either?"] if night else ["Fine day.", "Mind the mud.", "Have you heard the news?"])[k % (2 if night else 3)]


## The voice hook: every spoken line passes here. Silent until voice audio exists (a SoundFX
## node with play_voice(who, text) would speak it).
static func voice(tree: SceneTree, who: String, text: String) -> void:
	var sfx := tree.get_first_node_in_group("sound_fx") if tree != null else null
	if sfx != null and sfx.has_method("play_voice"):
		sfx.call("play_voice", who, text)
