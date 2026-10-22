class_name Persuasion
extends RefCounted
## Admire, Intimidate, Joke and Bribe. Each try either raises or lowers how much the person likes
## the player (their disposition, 0-100) and trains Speech. The chance depends on Speech, how
## much they already like you, and their personality:
##   proud people love being admired       grumpy people hate jokes     cheerful people love them
##   nervous people fold when threatened   proud people and guards don't
##   bribes work better the bigger they are (the gold is only taken when it works)

enum Kind { ADMIRE, INTIMIDATE, JOKE, BRIBE_10, BRIBE_100, BRIBE_1000 }

const LABELS := ["Admire", "Intimidate", "Joke", "Bribe 10", "Bribe 100", "Bribe 1000"]
const BRIBES := {Kind.BRIBE_10: 10, Kind.BRIBE_100: 100, Kind.BRIBE_1000: 1000}
## Disposition change on success / failure
const GAIN := {Kind.ADMIRE: 7, Kind.INTIMIDATE: 6, Kind.JOKE: 6, Kind.BRIBE_10: 4, Kind.BRIBE_100: 9, Kind.BRIBE_1000: 18}
const LOSS := {Kind.ADMIRE: -3, Kind.INTIMIDATE: -8, Kind.JOKE: -4, Kind.BRIBE_10: -4, Kind.BRIBE_100: -4, Kind.BRIBE_1000: -4}


static func chance(kind: Kind, speech: int, disposition: int, personality: NpcData.Personality, role: NpcData.Role, level_gap: int = 0) -> float:
	var c := 0.32 + float(speech) / 200.0 + float(disposition - 50) / 250.0
	match kind:
		Kind.ADMIRE:
			c += {NpcData.Personality.PROUD: 0.15, NpcData.Personality.GRUMPY: -0.08, NpcData.Personality.PIOUS: -0.03}.get(personality, 0.0)
		Kind.INTIMIDATE:
			c += float(level_gap) * 0.02
			c += {NpcData.Personality.NERVOUS: 0.18, NpcData.Personality.PROUD: -0.15, NpcData.Personality.GRUMPY: -0.05}.get(personality, 0.0)
			if role == NpcData.Role.GUARD:
				c -= 0.2
		Kind.JOKE:
			c += 0.05
			c += {NpcData.Personality.CHEERFUL: 0.18, NpcData.Personality.GRUMPY: -0.2, NpcData.Personality.PIOUS: -0.08, NpcData.Personality.PROUD: -0.05}.get(personality, 0.0)
		_:
			c += log(float(BRIBES[kind])) / log(10.0) * 0.12 - 0.05
			if personality == NpcData.Personality.PIOUS:
				c -= 0.1
	return clampf(c, 0.05, 0.95)


## The chance for this speaker and player right now
static func chance_for(kind: Kind, s: DialogueEngine.Speaker, player: Node) -> float:
	var skills := player.get_node_or_null("Skills") as Skills if player != null else null
	var speech := skills.get_level(&"speech") if skills != null else SkillDatabase.START_LEVEL
	var gap := (skills.get_player_level() if skills != null else 1) - s.level
	return chance(kind, speech, DialogueEngine.get_disposition(s), s.personality, s.role, gap)


## Can the player try this at all? ("" = yes, else why not)
static func blocked(kind: Kind, player: Node) -> String:
	if BRIBES.has(kind):
		var inv := player.get_node_or_null("Inventory") as Inventory if player != null else null
		if inv == null or Currency.get_gold(inv) < int(BRIBES[kind]):
			return "Not enough gold"
	return ""


## One try. Returns {"success", "change", "disposition", "text"}
static func attempt(kind: Kind, s: DialogueEngine.Speaker, player: Node, rng: RandomNumberGenerator = null) -> Dictionary:
	if blocked(kind, player) != "":
		return {"success": false, "change": 0, "disposition": DialogueEngine.get_disposition(s), "text": "You don't have that much gold."}
	var p := chance_for(kind, s, player)
	var roll := rng.randf() if rng != null else randf()
	var ok := roll < p
	var change: int = GAIN[kind] if ok else LOSS[kind]
	if ok and BRIBES.has(kind):
		Currency.spend_gold(player.get_node("Inventory") as Inventory, int(BRIBES[kind]))
	var disp := DialogueState.change_disposition(s.id, s.base_disposition, change)
	var skills := player.get_node_or_null("Skills") as Skills if player != null else null
	if skills != null:
		skills.add_xp(&"speech", 3.0 if ok else 1.0)
	return {"success": ok, "change": change, "disposition": disp, "text": _reaction(kind, ok, s)}


static func _reaction(kind: Kind, ok: bool, s: DialogueEngine.Speaker) -> String:
	match kind:
		Kind.ADMIRE:
			return "Why, thank you. That's kind of you to say." if ok else "Flattery won't get you anywhere with me."
		Kind.INTIMIDATE:
			return "A-all right, all right! No need for that." if ok else "Is that supposed to scare me? Get lost."
		Kind.JOKE:
			return "Ha! That's a good one." if ok else "...Was that meant to be funny?"
	return "Well. That's very generous of you." if ok else "Are you trying to buy me? Keep your coin."
