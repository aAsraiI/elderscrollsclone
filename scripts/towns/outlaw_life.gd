class_name OutlawLife
extends RefCounted
## Alpha 1.29.3: the life of a wanted thief.
##
## BOUNTY HUNTERS: once your bounties add up to HUNTER_BOUNTY or more, hunters come for you in
## the wilds (never in a town), a party every couple of days, more of them the higher the bounty.
## CrimeManager calls tick() every second.
##
## WITNESSES: anyone who remembers your crime has "keep quiet" topics:
##   bribe     gold (by how much they saw); they forget it, and the town's bounty drops
##   threaten  an Intimidate roll (Strength, Speech); they forget it, or call the guard (+bounty)
##
## STOLEN GOODS cool off: a thing stolen COOL_DAYS ago is no longer known as stolen (guards won't
## take it, and any merchant buys it). A fence (a merchant who buys stolen goods) can "launder"
## everything you carry at once for a share of its worth.

const HUNTER_BOUNTY := 300
const HUNTER_GAP_DAYS := 2
const COOL_DAYS := 7
const LAUNDER_SHARE := 0.25
const BRIBE_PER_CRIME := 60
const BOUNTY_CUT := 50


# ---------------------------------------------------------------- bounty hunters

static func total_bounty() -> int:
	var t := 0
	for k in CrimeManager.bounties():
		t += int(CrimeManager.bounties()[k])
	return t


static func tick(crime: CrimeManager, player: Node3D) -> void:
	if crime.world != null and crime.world.clock != null and int(WorldState.get_record("stolen_cool").get("day", -1)) != crime.world.clock.day:
		WorldState.set_record("stolen_cool", {"day": crime.world.clock.day})
		cool_off(crime.world.clock.day)
	var world := crime.world
	if world == null or world.clock == null or total_bounty() < HUNTER_BOUNTY:
		return
	if world.dungeons != null and world.dungeons.is_inside():
		return
	var today := world.clock.day
	if today - int(WorldState.get_record("hunters").get("day", -99)) < HUNTER_GAP_DAYS:
		return
	var town := world.get_nearest_town(player.global_position)
	if town != null and town.position.distance_to(player.global_position) < town.poi.footprint_radius + 80.0:
		return
	send_hunters(world, player, today)


static func send_hunters(world: WorldManager, player: Node3D, today: int) -> Array[Enemy]:
	WorldState.set_record("hunters", {"day": today})
	var bounty := total_bounty()
	var n := clampi(2 + bounty / 800, 2, 5)
	var data := load("res://data/enemies/cutthroat.tres") as EnemyData
	var sk := player.get_node_or_null("Skills") as Skills
	var level := maxi((sk.get_player_level() if sk != null else 5) + 2, 5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Array[Enemy] = []
	var dir := -player.global_transform.basis.z
	for i in n:
		var at := player.global_position + dir.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)) * rng.randf_range(28.0, 40.0)
		at.y = world.get_height_at(at.x, at.z) + 0.5
		var e := Population.spawn_enemy(data, level, world, at, rng)
		if e == null:
			continue
		e.display_name = "Bounty Hunter"
		e.persist_mode = Enemy.PersistMode.NEVER
		e.disposition = Enemy.Disposition.HOSTILE
		e.set_meta("bounty_hunter", true)
		e.aggro.call_deferred(player)
		out.append(e)
	Locks.toast(player.get_tree(), "Bounty hunters have tracked you down!", true)
	DialogueState.system_entry("Knowledge", "Bounty hunters came for me. The price on my head (%d gold) has gone far beyond the towns." % bounty, "")
	return out


# ---------------------------------------------------------------- witnesses

static func topics_for(s: DialogueEngine.Speaker) -> PackedStringArray:
	var out := PackedStringArray()
	if s != null and not s.asleep and not Roleplay._crimes_seen(s).is_empty():
		out.append("keep quiet (bribe)")
		out.append("keep quiet (threaten)")
	return out


static func bribe_price(s: DialogueEngine.Speaker) -> int:
	return BRIBE_PER_CRIME * maxi(Roleplay._crimes_seen(s).size(), 1)


static func threat_chance(player: Node) -> float:
	var sk := player.get_node_or_null("Skills") as Skills
	var st := player.get_node_or_null("Stats") as Stats
	var c := 0.25 + (float(sk.get_level(&"speech")) / 300.0 if sk != null else 0.0) + (st.get_stat("strength") / 250.0 if st != null else 0.0)
	return clampf(c, 0.05, 0.9)


static func _forget(s: DialogueEngine.Speaker, world: WorldManager) -> void:
	var town := s.town.town.display_name if s.town != null and s.town.town != null else ""
	var n := Roleplay._crimes_seen(s).size()
	var keep := (NpcMemory.memories(s.name, town) as Array).filter(func(m): return not String(m.get("kind", "")) in ["theft", "assault", "trespass"])
	WorldState.set_record("mem/%s|%s" % [s.name, town], {"list": keep})
	if world != null and world.crime != null and s.town != null:
		var b := CrimeManager.get_bounty(s.town.id)
		world.crime.set_bounty(s.town.id, maxi(b - BOUNTY_CUT * n, 0))


static func respond(s: DialogueEngine.Speaker, topic: String, player: Node, world: WorldManager) -> Dictionary:
	if not topics_for(s).has(topic):
		return {}
	var inv := player.get_node("Inventory") as Inventory
	match topic:
		"keep quiet (bribe)":
			var price := bribe_price(s)
			if Currency.get_gold(inv) < price:
				return Roleplay._say("[Bribe: %d gold] Come back when your purse matches your mouth." % price)
			Currency.spend_gold(inv, price)
			_forget(s, world)
			Achievements.note("bribe")
			BuildHooks.train(player.get_tree(), &"speech", 4.0)
			return Roleplay._say("[Bribe: %d gold] *pockets the coin* Saw what? I saw nothing. Nothing at all." % price)
		"keep quiet (threaten)":
			var c := threat_chance(player)
			BuildHooks.train(player.get_tree(), &"speech", 4.0)
			if randf() < c:
				_forget(s, world)
				Achievements.note("bribe")
				return Roleplay._say("[Threaten %d%%: it works] ...All right! All right. I never saw you. Please, just go." % int(c * 100.0))
			DialogueState.change_disposition(s.id, s.base_disposition, -15)
			if world != null and world.crime != null and s.town != null:
				world.crime.add_bounty(s.town.id, 40)
			return Roleplay._say("[Threaten %d%%: it fails] You'd threaten me? Guard! GUARD!" % int(c * 100.0))
	return {}


# ---------------------------------------------------------------- stolen goods

## The day each stolen thing was last taken (CrimeManager.add_stolen keeps it)
static func note_stolen_day(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var clock := tree.get_first_node_in_group("world_clock") as WorldClock if tree != null else null
	var rec: Dictionary = WorldState.get_record("stolen_days").duplicate()
	rec[path] = clock.day if clock != null else 0
	WorldState.set_record("stolen_days", rec)


## Things stolen COOL_DAYS ago or more stop being known as stolen (call once a day)
static func cool_off(today: int) -> int:
	var days: Dictionary = WorldState.get_record("stolen_days")
	var cooled := 0
	for path: String in days.keys():
		if today - int(days[path]) >= COOL_DAYS:
			var item := SaveUtil.path_to_item(path)
			if item != null:
				var n := int(CrimeManager.stolen_ledger().get(path, 0))
				CrimeManager.remove_stolen(item, n)
				cooled += n
			var rec: Dictionary = WorldState.get_record("stolen_days").duplicate()
			rec.erase(path)
			WorldState.set_record("stolen_days", rec)
	return cooled


## What a fence wants to launder everything stolen you carry
static func launder_price(inv: Inventory) -> int:
	var total := 0
	for path: String in CrimeManager.stolen_ledger():
		var item := SaveUtil.path_to_item(path)
		if item != null:
			total += item.value * CrimeManager.stolen_count(inv, item)
	return ceili(total * LAUNDER_SHARE)


static func fence_topics(s: DialogueEngine.Speaker, world: WorldManager) -> PackedStringArray:
	var out := PackedStringArray()
	var t := Barter.trade_status(s, world) if s != null else {}
	var m: MerchantData = t.get("merchant") if not t.is_empty() else null
	if m != null and m.buys_stolen:
		out.append("launder stolen goods")
	return out


static func launder(s: DialogueEngine.Speaker, player: Node) -> Dictionary:
	var inv := player.get_node("Inventory") as Inventory
	var price := launder_price(inv)
	if price <= 0:
		return Roleplay._say("You've nothing hot on you. Come back when you do.")
	if Currency.get_gold(inv) < price:
		return Roleplay._say("A quarter of what it's worth: %d gold. Come back with it." % price)
	Currency.spend_gold(inv, price)
	var n := 0
	for path: String in CrimeManager.stolen_ledger().keys():
		var item := SaveUtil.path_to_item(path)
		if item != null and inv.get_count(item) > 0:
			var c := CrimeManager.stolen_count(inv, item)
			CrimeManager.remove_stolen(item, c)
			n += c
	Achievements.note("launder")
	return Roleplay._say("%d gold, and the marks are gone. Nobody will know those %d things were ever anyone's but yours." % [price, n])
