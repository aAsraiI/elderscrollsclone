class_name Taming
extends RefCounted
## Alpha 1.25: winning over a wild beast. Walk up to a wolf, boar, fox, bear or hound that hasn't turned
## on you, with raw meat in your pack, and press E: it eats from your hand, and sometimes (better with
## Hunting and Survival) it decides you are its pack. A tamed beast follows you like a companion
## (Followers: it fights for you, waits when told, comes through doors, is saved with your game).
## Fail and it may go for you. At most MAX_PETS at once.

const REACH := 2.6
const MAX_PETS := 2
const TAMEABLE := ["wolf", "boar", "fox", "frost_bear", "ash_hound", "hound", "giant_rat", "dune_stalker"]
const MEAT := "res://data/materials/raw_meat.tres"


static func candidate(player: Node3D) -> Enemy:
	if player == null:
		return null
	var inv := player.get_node_or_null("Inventory") as Inventory
	var meat := load(MEAT) as ItemData if ResourceLoader.exists(MEAT) else null
	if inv == null or meat == null or not inv.has_item(meat):
		return null
	for e in ActorRegistry.near(player.global_position, REACH):
		if e.is_dead() or e.has_meta("player_ally") or not (String(e.enemy_id) in TAMEABLE) or e.has_meta("legend"):
			continue
		if e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK or e._provoked:
			continue
		if e.global_position.distance_to(player.global_position) <= REACH:
			return e
	return null


static func pets(player: Node) -> int:
	var f := player.get_node_or_null("Followers") as Followers if player != null else null
	if f == null:
		return 0
	return f._alive().filter(func(e: Enemy) -> bool: return e.has_meta("pet")).size()


## Tries to tame it. Returns what happened, for a toast.
static func tame(player: Node3D, e: Enemy) -> String:
	var inv := player.get_node_or_null("Inventory") as Inventory
	var meat := load(MEAT) as ItemData
	var f := player.get_node_or_null("Followers") as Followers
	if inv == null or f == null or e == null:
		return ""
	if pets(player) >= MAX_PETS:
		return "You already have all the beasts you can keep."
	inv.remove_item(meat, 1)
	var skills := player.get_node_or_null("Skills") as Skills
	var hunting := skills.get_level(&"hunting") if skills != null else 5
	var survival := skills.get_level(&"survival") if skills != null else 5
	var chance := clampf(0.25 + float(hunting) / 150.0 + float(survival) / 300.0 - (0.2 if e.enemy_id == "frost_bear" else 0.0), 0.1, 0.95)
	if skills != null:
		skills.add_xp(&"hunting", 4.0)
	if randf() > chance:
		if randf() < 0.4:
			e._provoked = true
			e.aggro(player)
			return "The %s snaps the meat away and turns on you!" % e.display_name.to_lower()
		return "The %s takes the meat and backs off. Not yet." % e.display_name.to_lower()
	e.stop_fighting()
	e.disposition = Enemy.Disposition.FRIENDLY
	e.persist_mode = Enemy.PersistMode.NEVER
	e.remove_meta("wild")
	e.set_meta("pet", true)
	var wl := player.get_tree().get_first_node_in_group("wild_life") as WildLife
	if wl != null:
		for g in wl.groups:
			(g["members"] as Array).erase(e)  # no longer part of the wild: never let go
	f._make_follower(e)
	return "The %s eats from your hand. It is yours now." % e.display_name.to_lower()
