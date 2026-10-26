class_name QuestCondition
extends Resource
## One check, shared by quests (QuestData.requirements), dialogue (DialogueResponse.conditions)
## and anything else that needs "only when...". Make one in the Inspector: pick a Kind, fill Key
## and Amount.
##
##   LEVEL          player level >= Amount
##   SKILL          skill Key (one_handed, speech, sneak...) >= Amount
##   GUILD_RANK     rank in guild Key (fighters, mages...) >= Amount (1 = just joined)
##   QUEST_DONE     quest Key finished (a QuestData id, a written quest like S-KR01, or "story")
##   ITEM_OWNED     carrying at least Amount of item Key (a res:// path or an item id)
##   TIME_OF_DAY    the hour is from Amount to Amount2 (21 to 5 wraps past midnight)
##   REPUTATION     reputation with Key (a guild id, or a town's name) >= Amount
##   FLAG           flag Key is set (dialogue or quest flags)
##   NOT_FLAG       flag Key is not set
##   DISPOSITION    the person spoken to likes you >= Amount
##   QUEST_ACTIVE   quest Key is in progress

enum Kind { LEVEL, SKILL, GUILD_RANK, QUEST_DONE, ITEM_OWNED, TIME_OF_DAY, REPUTATION, FLAG, NOT_FLAG, DISPOSITION, QUEST_ACTIVE }

@export var kind: Kind = Kind.LEVEL
@export var key := ""
@export var amount := 1
## Only for TIME_OF_DAY: the end hour
@export var amount2 := 24
## Turns the check around (true when it would be false)
@export var invert := false


## Does it pass? `disposition` is the person spoken to's (-1 = nobody)
func passes(tree: SceneTree, disposition: int = -1) -> bool:
	var ok := _check(tree, disposition)
	return ok != invert


func _check(tree: SceneTree, disposition: int) -> bool:
	var p := tree.get_first_node_in_group("player") if tree != null else null
	match kind:
		Kind.LEVEL:
			var sk := p.get_node_or_null("Skills") as Skills if p != null else null
			return sk != null and sk.get_player_level() >= amount
		Kind.SKILL:
			var sk := p.get_node_or_null("Skills") as Skills if p != null else null
			return sk != null and sk.get_level(StringName(key)) >= amount
		Kind.GUILD_RANK:
			return Factions.rank(key) >= amount
		Kind.QUEST_DONE:
			return QuestRunner.is_finished_anywhere(key)
		Kind.QUEST_ACTIVE:
			return QuestRunner.is_active_anywhere(key)
		Kind.ITEM_OWNED:
			var inv := p.get_node_or_null("Inventory") as Inventory if p != null else null
			if inv == null:
				return false
			var n := 0
			for s in inv.stacks:
				if s.item.resource_path == key or String(s.item.id) == key or s.item.display_name == key:
					n += s.count
			return n >= amount
		Kind.TIME_OF_DAY:
			var clock := tree.get_first_node_in_group("world_clock") as WorldClock if tree != null else null
			if clock == null:
				return true
			return WorldClock.hour_in_range(clock.hour, float(amount), float(amount2))
		Kind.REPUTATION:
			return Reputation.get_rep(key) >= amount
		Kind.FLAG:
			return DialogueState.has_flag(key) or QuestBook.flag(key)
		Kind.NOT_FLAG:
			return not DialogueState.has_flag(key) and not QuestBook.flag(key)
		Kind.DISPOSITION:
			return disposition < 0 or disposition >= amount
	return true


## Every condition in a list passes
static func all_pass(list: Array, tree: SceneTree, disposition: int = -1) -> bool:
	for c in list:
		if c != null and not (c as QuestCondition).passes(tree, disposition):
			return false
	return true


## "Level 5", "Speech 30"... what the player can read on a check
func describe() -> String:
	match kind:
		Kind.LEVEL: return "level %d" % amount
		Kind.SKILL: return "%s %d" % [key.capitalize(), amount]
		Kind.GUILD_RANK: return "rank %d in the %s" % [amount, Factions.display_name(key)]
		Kind.QUEST_DONE: return "finish %s" % key
		Kind.QUEST_ACTIVE: return "be on %s" % key
		Kind.ITEM_OWNED: return "carry %d %s" % [amount, key.get_file().get_basename()]
		Kind.TIME_OF_DAY: return "between %d:00 and %d:00" % [amount, amount2]
		Kind.REPUTATION: return "reputation %d with %s" % [amount, key]
		Kind.FLAG: return key
		Kind.NOT_FLAG: return "not " + key
		Kind.DISPOSITION: return "disposition %d" % amount
	return ""
