class_name Achievements
extends RefCounted
## Alpha 1.27: achievements, in the journal (J > Achievements). Five chapters, from the first
## steps to the far islands, in about the order a game goes: finish them all and you have been
## through almost all of the game. Each one says how to do it and links its Guide page, so the
## list doubles as a tutorial path (the journal shows the next few to try).
##
## Two kinds of check:
##   counters  note("kill") from the game as things happen (WorldState "ach_n")
##   state     read from the game every few seconds (level, skills, gold, places, guilds...)
## Unlocked ones are kept in WorldState "ach/<id>" {"day"}, so they are per character and saved.
## Tutorial (under the Player) runs check() a few at a time, so it costs next to nothing.

const COUNTS := "ach_n"
const CHAPTERS := ["First Steps", "Making a Name", "Seasoned", "Master", "Beyond the Islands"]

## [id, chapter, name, how to do it, guide page, check, need]
## check: "n:<counter>" counts note() calls; anything else is a state check in _value()
const LIST := [
	# ---- 1 First Steps: the basics, in the first hour or two
	["first_blood", 0, "First Blood", "Kill a foe or a wild beast. Left click attacks; hold it for a heavy blow.", "combat", "n:kill", 1],
	["parry", 0, "Not Today", "Parry a blow: with a shield or weapon, raise your guard (right click) just before the hit lands.", "combat", "n:parry", 1],
	["archer", 0, "Loose!", "Shoot an arrow. Equip a bow, hold left click to draw and let go to shoot.", "combat", "n:shot", 1],
	["talk", 0, "A Word With You", "Talk to someone (E) and ask them about a topic.", "talking", "n:talk", 1],
	["first_quest", 0, "A Task at Hand", "Take on a quest. Ask people about their work, or read a town's notice board.", "quests", "quests_taken", 1],
	["explorer1", 0, "Off the Map", "Discover 3 places. Walking near a town, cave or ruin marks it on your map (M).", "map", "found", 3],
	["level2", 0, "Getting Stronger", "Reach level 2. Use skills to raise them; skill levels raise your level.", "leveling", "level", 2],
	["perk", 0, "A Knack For It", "Spend a perk point. Character (C) > Perks.", "perks", "perks", 1],
	["consume", 0, "A Bite to Eat", "Eat food or drink a potion from your inventory (I, then E on it).", "health", "n:use", 1],
	["rest", 0, "A Good Night's Sleep", "Sleep in a bed. Rent a room at an inn, or find a bed you own.", "rest", "n:sleep", 1],
	["trade", 0, "Coin Changes Hands", "Buy or sell something. Talk to a merchant and pick Barter.", "trading", "n:trade", 1],
	["sneak", 0, "Unseen", "Strike someone who hasn't seen you. Sneak (Ctrl) up behind them and attack.", "stealth", "n:sneak_attack", 1],
	["spell", 0, "Spark of Magic", "Cast a spell. Magic page (P), E puts a spell in your off hand, right click casts.", "magic", "n:cast", 1],
	["lockpick", 0, "Open Sesame", "Pick a lock. With lockpicks in your pack, press E on a locked door or chest.", "locks", "n:lockpick", 1],
	["reader", 0, "Bookworm", "Read a book or a note.", "books", "n:read", 1],
	["gather", 0, "From the Land", "Gather something: pick a plant, chop branches, mine a rock or a vein of ore.", "gathering", "n:harvest", 1],
	["crafter", 0, "Handiwork", "Make something at a workstation: a forge, a workbench, a cooking pot, an alchemy lab.", "crafting", "n:craft", 1],
	["delver", 0, "Into the Dark", "Go down into a dungeon. Caves, crypts and ruins are marked on the map.", "dungeons", "n:dungeon", 1],
	["saved", 0, "Safe Keeping", "Save your game (F5 quicksaves, F10 opens the saves).", "saving", "n:save", 1],

	# ---- 2 Making a Name: the first days
	["level10", 1, "Journeyman", "Reach level 10.", "leveling", "level", 10],
	["skill25", 1, "Apprentice", "Raise any skill to 25.", "leveling", "skill_max", 25],
	["kills25", 1, "Blooded", "Kill 25 foes or beasts.", "combat", "n:kill", 25],
	["explorer2", 1, "Wanderer", "Discover 15 places.", "map", "found", 15],
	["cleared1", 1, "Dungeon Delver", "Clear a dungeon: kill its master in the deepest room. Its boss chest is yours.", "dungeons", "cleared", 1],
	["quests5", 1, "Reliable", "Finish 5 quests.", "quests", "quests_done", 5],
	["guild", 1, "One of Us", "Join a guild. Ask a guild's leader about \"membership\".", "guilds", "guilds", 1],
	["persuade", 1, "Silver Tongue", "Persuade someone in a conversation (the buttons along the bottom).", "talking", "n:persuade", 1],
	["train", 1, "Lessons Paid For", "Pay a trainer to teach you a skill (Train, in a conversation).", "leveling", "n:train", 1],
	["smith", 1, "Hammer and Tongs", "Make a weapon or armour at a forge.", "smithing", "n:craft_smithing", 1],
	["alchemist", 1, "Brewer", "Brew a potion at an alchemy lab.", "alchemy", "n:craft_alchemy", 1],
	["cook", 1, "Home Cooking", "Cook a meal at a cooking pot or fire.", "cooking", "n:craft_cooking", 1],
	["travel", 1, "Long Road Short", "Fast travel: on the map (M), pick a place you have found.", "travel", "n:travel", 1],
	["horse", 1, "In the Saddle", "Own a horse. Stables outside the bigger towns sell them.", "horses", "horse", 1],
	["follower", 1, "Company", "Hire a follower. Sellswords wait in inns; some people join you after a quest.", "followers", "n:hire", 1],
	["knockout", 1, "Lights Out", "Knock someone out: sneak up behind them, unseen, and press E.", "stealth", "tally:knockouts", 1],
	["purse", 1, "A Full Purse", "Carry 1,000 gold.", "trading", "gold", 1000],
	["job", 1, "Odd Jobs", "Finish a job from a notice board or bounty board.", "quests", "jobs_done", 1],
	["headshot", 1, "Between the Eyes", "Hit someone in the head with an arrow, bolt or thrown weapon.", "archery", "n:headshot", 1],
	["repair", 1, "Good as New", "Mend worn gear: a Repair Hammer from the inventory, or a smith's Repair button.", "smithing", "n:repair", 1],
	["ability", 2, "A Move of Your Own", "Take Shield Charge, Whirlwind Sprint or Shadow Step (Perks) and use it with G.", "perks", "n:ability", 1],
	["synergy", 2, "Greater Than the Parts", "Earn a synergy: two perks from different trees that unlock a hidden third.", "perks", "n:synergy", 1],
	["scroll", 1, "Words on Paper", "Read a scroll: it casts its spell once, for free, whatever your skill.", "magic", "n:scroll", 1],
	["combo", 1, "Elemental", "Set off a spell combo: hit a foe with two different elements within 4 s (fire then frost...).", "magic", "n:combo", 1],
	["pickpocket", 1, "Light Touch", "Pick someone's pocket: sneak up unseen and press E.", "pickpocket", "n:pickpocket", 1],
	["fish", 1, "Gone Fishing", "Catch a fish: use a Fishing Pole facing water and press E when it bites.", "fishing", "n:fish", 1],
	["skin", 1, "Skin and Bone", "Skin a beast: F on its body with a blade in your pack.", "hunting", "n:skin", 1],
	["snare", 1, "Patient Hunter", "Catch something in a snare.", "hunting", "n:snare", 1],
	["camp", 1, "Under the Stars", "Pitch camp with a Camping Kit, anywhere outside.", "camping", "n:camp", 1],
	["treasure", 1, "X Marks the Spot", "Dig up the treasure from a Treasure Map (with a pickaxe or shovel).", "map", "n:treasure_dug", 1],
	["map_bought", 1, "Cartographer's Friend", "Buy a map of the land from an innkeeper.", "map", "n:map_bought", 1],
	["climb", 1, "Up the Rock", "Climb a cliff: hold Space and W against a steep rock face.", "climbing", "n:climb", 1],
	["arena", 1, "Blood on the Sand", "Win a bout at an arena (strike the gong in a Fighters Guild hall).", "arena", "arena", 1],
	["museum", 1, "For Posterity", "Donate an artifact to an Antiquarian Museum.", "museum", "museum", 1],
	["spells5", 1, "Spell Collector", "Know 5 spells. Spell tomes are sold by mages and found in dungeons.", "magic", "spells", 5],
	["main1", 1, "The Sealed Letter", "Follow the main quest, The Ashen Eclipse, to its second step.", "quests", "story", 2],

	# ---- 3 Seasoned: a settled life on the main island
	["level25", 2, "Seasoned", "Reach level 25.", "leveling", "level", 25],
	["skill50", 2, "Adept", "Raise any skill to 50.", "leveling", "skill_max", 50],
	["kills100", 2, "Veteran", "Kill 100 foes or beasts.", "combat", "n:kill", 100],
	["explorer3", 2, "Pathfinder", "Discover 40 places.", "map", "found", 40],
	["cleared5", 2, "Tomb Raider", "Clear 5 dungeons.", "dungeons", "cleared", 5],
	["quests20", 2, "Hero for Hire", "Finish 20 quests.", "quests", "quests_done", 20],
	["guild_rank", 2, "Rising Through the Ranks", "Reach the third rank in a guild. Ask about \"advancement\".", "guilds", "guild_rank", 3],
	["enchant", 2, "Bound in Light", "Enchant an item at an arcane enchanter, with a filled soul gem.", "enchanting", "n:enchant", 1],
	["spellmaker", 2, "Words of Your Own", "Make your own spell at an Altar of Spellmaking.", "magic", "custom_spell", 1],
	["home", 2, "A Roof of Your Own", "Buy a house in a town (ask the steward or a guard about homes for sale).", "homes", "home", 1],
	["homestead", 2, "Settling Down", "Buy a homestead plot and build its first part.", "homestead", "homestead", 1],
	["settler", 2, "Neighbours", "Bring a settler to your homestead (free a prisoner, or ask a traveller).", "homestead", "settlers", 1],
	["tame", 2, "Good Boy", "Tame an animal: walk up to a calm one with raw meat and press E.", "taming", "pets", 1],
	["marry", 2, "Till Death", "Marry someone who likes you (wear an Amulet of Mara, or court them).", "marriage", "married", 1],
	["dragon", 2, "Dragonslayer", "Kill a dragon.", "combat", "dragons", 1],
	["thief", 2, "Light Fingers", "Steal 10 times without being caught for it... or with.", "crime", "n:steal", 10],
	["purse2", 2, "Well Off", "Carry 10,000 gold.", "trading", "gold", 10000],
	["main3", 2, "The Eclipse Codex", "Follow the main quest to the Eclipse Codex.", "quests", "story", 3],
	["arena4", 2, "Crowd Favourite", "Reach the fourth arena rank.", "arena", "arena", 4],
	["levelup_build", 2, "Your Own Way", "Take a feat (Character > Perks, top of the page).", "perks", "feats", 1],

	# ---- 4 Master: the main island's great deeds
	["trial", 2, "Proven", "Finish a skill trial: at 50 a master sends word; raise the skill 3 more levels.", "leveling", "n:trial", 1],
	["loadout", 2, "Two Minds", "Save a build as a loadout (Character > Level Up) and take one up at a temple shrine.", "perks", "n:loadout", 1],
	["birthstone", 2, "Under a New Star", "Take a new birthsign at a ring of standing stones (E on the altar stone).", "powers", "n:birthstone", 1],
	["lancer", 2, "Lancer", "Put barding on your horse (use it from the inventory near your horse).", "horses", "n:barding", 1],
	["ward", 2, "Not Today, Mage", "Soak up a spell with a ward (Lesser Ward, Mysticism).", "magic", "n:ward", 1],
	["levitate", 2, "Into the Sky", "Levitate: cast Levitate (Alteration), then double-tap Space.", "magic", "n:levitate", 1],
	["ritual", 2, "The Old Ways", "Perform a ritual in a ritual circle (ritual books and chalk: Mages Guild halls).", "rituals", "n:ritual", 1],
	["research", 2, "Scholar", "Have the Mages Guild research a spell effect for you (ask a guild mage).", "rituals", "n:research", 1],
	["blood_perk", 2, "Children of the Night", "Take a Vampire or Werewolf perk, bought with blood points from feeding or devouring.", "vampire", "blood_perks", 1],
	["patron", 2, "Chosen", "Do a Patron's deed and receive its artifact (kneel at a glowing shrine in the wilds).", "patrons", "n:patron", 1],
	["pickpocket50", 2, "Cutpurse", "Pick 25 pockets.", "pickpocket", "n:pickpocket", 25],
	["disguise", 2, "One of Us", "Walk among a faction in its clothes (Bandit Leathers, Ash Cult Robes, Smuggler's Coat).", "stealth", "n:disguise", 1],
	["bribe", 2, "Hush Money", "Keep a witness quiet: bribe or threaten someone who saw your crime.", "crime", "n:bribe", 1],
	["launder", 2, "Clean Hands", "Have a fence launder your stolen goods.", "crime", "n:launder", 1],
	["hunter_kill", 2, "Not Today, Hunter", "Kill a bounty hunter (they come for you once your bounties pass 300).", "crime", "n:hunter_kill", 1],
	["heist", 2, "The Job", "Pull off a heist for the Thieves Guild (ask the fence about \"a heist\").", "heists", "n:heist", 1],
	["fish_species", 2, "Collector of the Deep", "Catch 6 different kinds of fish.", "fishing", "fish_species", 6],
	["remedy", 2, "Physician, Heal Thyself", "Cure a disease with an Herbal Remedy.", "disease", "n:remedy", 1],
	["bandage", 2, "Field Dressing", "Bind your wounds with a Bandage.", "health", "n:bandage", 1],
	["fetch", 2, "Good Boy, Good Find", "Have a tamed animal fetch you something from a body.", "taming", "n:fetch", 1],
	["explorer_fog", 2, "Off the Edge of the Map", "Clear 150 patches of map fog by exploring.", "map", "explored", 150],
	["landmark", 2, "Sightseer", "Find a great landmark: a giant statue, a fallen tower, a sunken temple or a titan's bones.", "sites", "n:site_landmark", 1],
	["puzzle", 2, "Clever", "Solve a puzzle at an old place (levers, pillars or mirrors).", "sites", "n:puzzle", 1],
	["drowned", 2, "Sunken Treasure", "Find a drowned ruin or sea cave under the sea.", "sites", "n:site_underwater", 1],
	["level50", 3, "Master", "Reach level 50.", "leveling", "level", 50],
	["skill100", 3, "Grandmaster", "Raise any skill to 100.", "leveling", "skill_max", 100],
	["skills50", 3, "Many Talents", "Have 5 skills at 50 or more.", "leveling", "skills50", 5],
	["kills500", 3, "Warlord", "Kill 500 foes or beasts.", "combat", "n:kill", 500],
	["explorer4", 3, "Cartographer", "Discover 100 places.", "map", "found", 100],
	["cleared15", 3, "Bane of the Deep", "Clear 15 dungeons.", "dungeons", "cleared", 15],
	["quests50", 3, "Legend of the Realm", "Finish 50 quests.", "quests", "quests_done", 50],
	["main_done", 3, "The Sun Restored", "Finish the main quest, The Ashen Eclipse.", "quests", "story", 6],
	["guild_master", 3, "Master of the Guild", "Reach the top rank of a guild.", "guilds", "guild_rank", 5],
	["champion", 3, "Grand Champion", "Win all seven arena bouts.", "arena", "arena", 7],
	["realm", 3, "Beyond the Veil", "Conquer a realm: defeat the master of its heart. Quests open the gates.", "realms", "realms", 1],
	["council", 3, "Kingmaker", "See the council settled: a house rules for Elowen (Council, K).", "council", "regency", 1],
	["dragons5", 3, "Dragonbane", "Kill 5 dragons.", "combat", "dragons", 5],
	["museum10", 3, "Curator", "Donate 10 artifacts to the museum.", "museum", "museum", 10],
	["purse3", 3, "Merchant Prince", "Carry 50,000 gold.", "trading", "gold", 50000],
	["level_all", 3, "Jack of All Trades", "Have 15 skills at 25 or more.", "leveling", "skills25", 15],

	# ---- 5 Beyond the Islands: the endgame, islands of level 100 to 200
	["patrons_all", 3, "Favoured of All", "Receive the artifacts of all eight Patrons.", "patrons", "n:patron", 8],
	["clean_heist", 3, "Ghost", "Pull off a heist without a single watchman seeing you.", "heists", "n:clean_heist", 1],
	["hawk", 3, "Eyes in the Sky", "Loose a hawk with a Falconer's Glove (Hunting 50).", "taming", "n:hawk", 1],
	["farm", 3, "Lord of the Land", "Build Beehives, an Orchard and a Livestock Pen at your homestead.", "homestead", "farm_parts", 3],
	["landmarks_all", 3, "Wonders of the Realm", "Find 10 great landmarks.", "sites", "n:site_landmark", 10],
	["ship", 3, "Captain", "Buy a Ship's Deed and launch your own ship.", "ships", "n:ship", 1],
	["sea_monster", 3, "Serpent Slayer", "Kill a sea serpent from your ship.", "ships", "n:sea_monster", 1],
	["far_isle", 4, "Over the Horizon", "Set foot on an island of level 100 or more. Ships sail from port towns.", "islands", "far_land", 100],
	["level100", 4, "Hundredfold", "Reach level 100.", "islands", "level", 100],
	["skill125", 4, "Beyond Mastery", "Raise any skill to 125.", "leveling", "skill_max", 125],
	["mastery_tome", 4, "Grandmaster's Lesson", "Study a Tome of Mastery, found in the vaults of the far islands.", "leveling", "n:mastery_tome", 1],
	["island_spell", 4, "Grandmaster of the Arts", "Learn a Grandmaster or Ascendant spell, sold only on the far islands.", "magic", "island_spells", 1],
	["resettle", 4, "City Founder", "Clear a ruined city on the far islands and resettle it.", "sites", "n:resettle", 1],
	["level150", 4, "Living Legend", "Reach level 150.", "islands", "level", 150],
	["far_isle2", 4, "The Last Shores", "Set foot on an island of level 175 or more.", "islands", "far_land", 175],
	["realms_all", 4, "Walker of Worlds", "Conquer every realm.", "realms", "realms", 10],
	["cleared40", 4, "Nothing Left Below", "Clear 40 dungeons.", "dungeons", "cleared", 40],
	["kills2000", 4, "Death Itself", "Kill 2,000 foes or beasts.", "combat", "n:kill", 2000],
	["dragons25", 4, "Sky Emptied", "Kill 25 dragons.", "combat", "dragons", 25],
	["level200", 4, "Ascended", "Reach level 200.", "islands", "level", 200],
]

static var _by_id := {}
static var _cache_ver := -1
static var _found := 0
static var _cleared := 0


static func get_def(id: String) -> Array:
	if _by_id.is_empty():
		for a in LIST:
			_by_id[a[0]] = a
	return _by_id.get(id, [])


static func is_unlocked(id: String) -> bool:
	return WorldState.has_record("ach/" + id)


static func unlocked_count() -> int:
	var n := 0
	for a in LIST:
		if is_unlocked(a[0]):
			n += 1
	return n


## Something happened that a counter wants (any part of the game may call this; it is cheap)
static func note(what: String, amount: int = 1) -> void:
	var t: Dictionary = WorldState.get_record(COUNTS).duplicate()
	t[what] = int(t.get(what, 0)) + amount
	WorldState.set_record(COUNTS, t)


static func count(what: String) -> int:
	return int(WorldState.get_record(COUNTS).get(what, 0))


## The quest event bus feeds the counters too (QuestEvents.emit)
static func on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"kill":
			var e := data.get("enemy") as Enemy
			if e != null and e._hurt_by_player:
				note("kill")
				if e.has_meta("bounty_hunter"):
					note("hunter_kill")
		"talk", "steal", "persuade", "use":
			note(kind)


## How far along one achievement is (a number to compare with its need)
static func value(a: Array, tree: SceneTree) -> int:
	var check := String(a[5])
	if check.begins_with("n:"):
		return count(check.substr(2))
	if check.begins_with("tally:"):
		return Takedowns.tally(check.substr(6))
	return _value(check, tree)


static func _value(check: String, tree: SceneTree) -> int:
	var player := tree.get_first_node_in_group("player") as Node3D if tree != null else null
	var world := tree.get_first_node_in_group("world_manager") as WorldManager if tree != null else null
	var skills := player.get_node_or_null("Skills") as Skills if player != null else null
	match check:
		"level":
			return skills.get_player_level() if skills != null else 1
		"skill_max", "skills50", "skills25":
			if skills == null:
				return 0
			var best := 0
			var n50 := 0
			var n25 := 0
			for id in skills.levels:
				var l := int(skills.levels[id])
				best = maxi(best, l)
				n50 += 1 if l >= 50 else 0
				n25 += 1 if l >= 25 else 0
			return {"skill_max": best, "skills50": n50, "skills25": n25}[check]
		"perks":
			return skills.build.perk_points_spent() if skills != null and skills.build != null else 0
		"feats":
			if skills == null or skills.build == null:
				return 0
			var f := 0
			for id in skills.build.owned:
				if bool(PerkDatabase.get_perk(String(id)).get("feat", false)):
					f += 1
			return f
		"found", "cleared":
			_count_places()
			return _found if check == "found" else _cleared
		"quests_taken", "quests_done", "jobs_done":
			if world == null:
				return 0
			var n := 0
			for q: Dictionary in QuestLog.all(world):
				if check == "quests_taken" or (q["status"] == "completed" and (check == "quests_done" or q["source"] == "job")):
					n += 1
			return n
		"guilds":
			var g := 0
			for id in Factions.GUILDS:
				g += 1 if Factions.is_member(id) else 0
			return g
		"guild_rank":
			var r := 0
			for id in Factions.GUILDS:
				r = maxi(r, Factions.rank(id))
			return r
		"gold":
			var inv := player.get_node_or_null("Inventory") as Inventory if player != null else null
			return Currency.get_gold(inv) if inv != null else 0
		"horse":
			return 1 if Rider.owns_horse() else 0
		"arena":
			return Arena.rank()
		"museum":
			return MuseumCase.donated().size()
		"spells", "custom_spell":
			var book := player.get_node_or_null("Spellbook") as Spellbook if player != null else null
			if book == null:
				return 0
			if check == "spells":
				return book.spells.size()
			var c := 0
			for id in book.spells:
				c += 1 if String(id).begins_with("custom_") else 0
			return c
		"story":
			return Story.stage()
		"home":
			return Homes.owned().size()
		"homestead":
			return Homestead.built().size()
		"settlers":
			return Settlers.all().size()
		"pets":
			return Taming.pets(player) if player != null else 0
		"married":
			return 1 if Marriage.is_married() else 0
		"dragons":
			return int(WorldState.get_record("dragons_slain").get("n", 0))
		"realms":
			var done := 0
			for id in RealmManager.REALMS:
				done += 1 if RealmManager.is_conquered(id) else 0
			return done
		"island_spells":
			var bk := player.get_node_or_null("Spellbook") as Spellbook if player != null else null
			var n := 0
			if bk != null:
				for id in bk.spells:
					n += 1 if SpellCatalog.rank_of(String(id)) in [5, 6] else 0
			return n
		"blood_perks":
			var bp := 0
			if skills != null and skills.build != null:
				for id in skills.build.owned:
					if PerkDatabase.SHIFT_TREES.has(String(PerkDatabase.get_perk(String(id)).get("tree", ""))):
						bp += 1
			return bp
		"fish_species":
			return (WorldState.get_record("fish_caught").get("ids", []) as Array).size()
		"farm_parts":
			var fp := 0
			for part in ["apiary", "orchard", "pen"]:
				fp += 1 if Homestead.has_part(part) else 0
			return fp
		"explored":
			return ExploredMap.count()
		"regency":
			return 1 if Regency.is_settled() else 0
		"far_land":
			return int(WorldState.get_record(COUNTS).get("far_land", 0))
	return 0


## found/ records: how many places are found and cleared (counted again only when the world changed)
static func _count_places() -> void:
	if _cache_ver == WorldState.version:
		return
	_cache_ver = WorldState.version
	_found = 0
	_cleared = 0
	for k: String in WorldState.records:
		if k.begins_with("found/"):
			_found += 1
			if bool(WorldState.records[k].get("cleared", false)):
				_cleared += 1


static func need(a: Array) -> int:
	return int(a[6])


## Unlocks it if it is done. Returns true the moment it unlocks.
static func check(a: Array, tree: SceneTree) -> bool:
	if is_unlocked(a[0]) or value(a, tree) < need(a):
		return false
	var clock := tree.get_first_node_in_group("world_clock") as WorldClock if tree != null else null
	WorldState.set_record("ach/" + String(a[0]), {"day": clock.day if clock != null else 1})
	Notices.quest(tree, "Achievement", "%s  (%d of %d)" % [a[2], unlocked_count(), LIST.size()])
	return true


## What to try next: the first few not done, in order (the journal shows them)
static func next_up(n: int = 5) -> Array:
	var out := []
	for a in LIST:
		if not is_unlocked(a[0]):
			out.append(a)
			if out.size() >= n:
				break
	return out


## "3 / 25" for a counter, "" when it is a yes or no
static func progress_text(a: Array, tree: SceneTree) -> String:
	var n := need(a)
	if n <= 1:
		return ""
	return "%d / %d" % [mini(value(a, tree), n), n]
