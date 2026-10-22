class_name Factions
extends RefCounted
## The player's guild memberships. Kept in WorldState ("faction/<id>": rank and finished jobs), so
## they are saved. The guilds themselves are FactionData files in scripts/Resources/Factions/.
##
## Who you talk to for each guild (see leader_of):
##   Fighters Guild, Mages Guild, Knightly Order   the owner of their hall (in cities and towns)
##   Thieves Guild                                 the pawnbroker of any city
##   Assassins Cult                                a hooded figure: one finds you after your first
##                                                 murder, and one sits in city inns at night
## Ask them about "membership" to join, "duties" for work, "advancement" for promotion.

const DIR := "res://scripts/Resources/Factions/"
const IDS: Array[String] = ["fighters", "mages", "knights", "thieves", "assassins"]
const HISTORY := "crime/history"

static var _cache := {}


static func get_data(id: String) -> FactionData:
	if not _cache.has(id):
		var path := DIR + id + ".tres"
		_cache[id] = load(path) as FactionData if ResourceLoader.exists(path) else null
	return _cache[id]


static func display_name(id: String) -> String:
	var d := get_data(id)
	return d.display_name if d != null else id


# ---------------------------------------------------------------- membership

## 0 = not a member, 1..5 = rank
static func rank(id: String) -> int:
	return int(WorldState.get_record("faction/" + id).get("rank", 0))


static func is_member(id: String) -> bool:
	return rank(id) > 0


static func quests_done(id: String) -> int:
	return int(WorldState.get_record("faction/" + id).get("quests", 0))


static func _store(id: String, r: int, quests: int) -> void:
	WorldState.set_record("faction/" + id, {"rank": r, "quests": quests})


## Why the player can't join ("" = they can)
static func join_problem(id: String, player: Node) -> String:
	var d := get_data(id)
	if d == null:
		return "There is no such guild."
	if is_member(id):
		return "You are already a member."
	var history := WorldState.get_record(HISTORY)
	match d.join_requirement:
		"no_bounty":
			if not CrimeManager.bounties().is_empty() or int(history.get("murders", 0)) > 0:
				return "The Order takes no one who is wanted, or who has killed in cold blood."
		"has_stolen":
			var skills := player.get_node_or_null("Skills") as Skills if player != null else null
			if int(history.get("thefts", 0)) <= 0 and (skills == null or skills.get_level(&"sneak") < 15):
				return "We don't know you. Steal something first, or learn to move quietly."
		"has_murdered":
			if int(history.get("murders", 0)) <= 0:
				return "You have no blood on your hands. Come back when you do."
	return ""


static func join(id: String, player: Node) -> bool:
	if join_problem(id, player) != "":
		return false
	_store(id, 1, 0)
	apply_perks(player)
	return true


## What the next rank needs: {"rank", "name", "quests_needed", "quests_have", "skill", "skill_needed",
## "skill_have", "ok", "why"} (ok = promotion can happen now)
static func next_rank(id: String, player: Node) -> Dictionary:
	var d := get_data(id)
	var r := rank(id)
	if d == null or r <= 0:
		return {"ok": false, "why": "You are not a member.", "rank": r}
	if r >= d.ranks.size():
		return {"ok": false, "why": "You can rise no higher.", "rank": r}
	var need_q := d.quests_for_rank[r]
	var have_q := quests_done(id)
	var skill_name := ""
	var need_s := 0
	var have_s := 0
	var skills := player.get_node_or_null("Skills") as Skills if player != null else null
	if d.skills.is_empty():
		skill_name = "player level"
		need_s = d.level_for_rank[r]
		have_s = skills.get_player_level() if skills != null else 1
	else:
		need_s = d.skill_for_rank[r]
		for sk in d.skills:
			var lv := skills.get_level(StringName(sk)) if skills != null else 0
			if lv >= have_s:
				have_s = lv
				var def := SkillDatabase.get_skill(StringName(sk))
				skill_name = def.display_name if def != null else sk
		if d.skills.size() > 1:
			var names := PackedStringArray()
			for sk in d.skills:
				var def := SkillDatabase.get_skill(StringName(sk))
				names.append(def.display_name if def != null else sk)
			skill_name = " or ".join(names)
	var why := ""
	if have_q < need_q:
		why = "%d more job%s" % [need_q - have_q, "" if need_q - have_q == 1 else "s"]
	if have_s < need_s:
		why += (" and " if why != "" else "") + "%s %d" % [skill_name, need_s]
	return {"rank": r + 1, "name": d.ranks[r], "quests_needed": need_q, "quests_have": have_q, "skill": skill_name,
		"skill_needed": need_s, "skill_have": have_s, "ok": why == "", "why": why}


## Promotes the player if they qualify. Returns the new rank name, or "" if not yet.
static func promote(id: String, player: Node) -> String:
	var n := next_rank(id, player)
	if not bool(n.get("ok", false)):
		return ""
	_store(id, int(n["rank"]), quests_done(id))
	apply_perks(player)
	return String(n["name"])


## A finished job for the guild
static func add_quest_done(id: String) -> void:
	_store(id, rank(id), quests_done(id) + 1)


# ---------------------------------------------------------------- perks

## Puts every guild's rank perk on the player's Stats (call after joining, promotion or loading)
static func apply_perks(player: Node) -> void:
	var stats := player.get_node_or_null("Stats") as Stats if player != null else null
	if stats == null:
		return
	for id in IDS:
		var d := get_data(id)
		var source := "faction_" + id
		if d == null or d.perk_stat == "" or rank(id) <= 0:
			stats.remove_modifiers(source)
		else:
			stats.add_modifiers(source, {d.perk_stat: d.perk_per_rank * rank(id)})


## Better prices with a merchant for guild members (0.06 = 6%)
static func discount_for(merchant: MerchantData) -> float:
	if merchant == null:
		return 0.0
	var best := 0.0
	for id in IDS:
		var d := get_data(id)
		if d != null and rank(id) > 0 and d.discount_merchants.has(String(merchant.id)):
			best = maxf(best, d.discount_per_rank * rank(id))
	return best


# ---------------------------------------------------------------- who leads what

## The guild this speaker hands out work for, or ""
static func leader_of(s: DialogueEngine.Speaker, world: WorldManager) -> String:
	if s == null:
		return ""
	if s.enemy != null and is_instance_valid(s.enemy) and s.enemy.has_meta("leader_of"):
		return String(s.enemy.get_meta("leader_of"))
	if s.data == null or s.home == null:
		return ""
	if s.role == NpcData.Role.GUILD_MEMBER and s.home.kind == BuildingPlot.Kind.GUILD_HALL and IDS.has(s.home.guild):
		return s.home.guild
	if s.role == NpcData.Role.MERCHANT and s.home.trade == "pawnbroker" and s.town != null and (s.town.poi as TownData).kind == TownData.Kind.CITY:
		return "thieves"
	return ""


## Crimes that guilds care about: murders and thefts committed (seen or not)
static func note_crime(kind: String) -> void:
	var h := WorldState.get_record(HISTORY).duplicate()
	h[kind] = int(h.get(kind, 0)) + 1
	WorldState.set_record(HISTORY, h)
