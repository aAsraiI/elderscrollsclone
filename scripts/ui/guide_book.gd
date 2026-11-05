class_name GuideBook
extends RefCounted
## Alpha 1.27: the tutorial, as pages in the journal (J > Guide) instead of pop-ups. Every page is
## there to read from the start; a page "comes up" (moves out of Not Yet Come Across, with a dot
## and a Journal Updated notice) the first time the game needs it: your first fight, first
## dungeon, first night... Kept in WorldState "tut/<id>" {"read"}. Older saves wrote "tut/<id>" {}
## for the old pop-up hints: those count as come up and read.
## Settings > Interface > Tutorial hints turns the notices off (the pages stay).

## [id, group, title, text]
const PAGES := [
	["welcome", "Getting Started", "Moving About",
		"WASD moves, the mouse looks. Space jumps, Shift sprints (it uses stamina), Ctrl sneaks. V switches between first and third person.\n\nE uses whatever you look at: talk to people, open doors, take things, sit, sleep. Hold E to grab and carry an object or drag a body.\n\nYour health, magicka and stamina are the bars at the bottom. Keys can be changed in Settings > Controls."],
	["menus", "Getting Started", "The Menus",
		"Tab opens the menu bar. Each page also has its own key:\n  I  Inventory\n  M  Map\n  C  Character (skills, perks, level up)\n  J  Journal (quests, topics, notes, this guide, achievements)\n  P  Magic\n  K  Council\n  T  Wait (or sleep, in a bed)\n  Q  Favorites: items and spells you marked with F, on keys 1-8\n\nEsc closes a page, or opens the pause menu."],
	["saving", "Getting Started", "Saving and Dying",
		"F5 quicksaves and F9 quickloads. F10 opens the saves: load, save to a slot, or delete. The game also saves itself as you go through doors and rest.\n\nWhat dying costs was chosen when the world was made (When you die): reload a save, lose a quarter of your gold and wake in the nearest town, or leave your pack in a grave where you fell (marked on the map until you dig it up). Ironman is one life."],
	["achievements", "Getting Started", "Achievements",
		"J > Achievements lists everything there is to do, from the first steps to the far islands, in five chapters. Each one says how to do it and which Guide page tells you more. The top of the page shows the next few to try: following them takes you through almost the whole game."],
	["health", "Getting Started", "Health and Healing",
		"When you are hurt, H drinks your best health potion. Food heals a little and a good meal gives a buff to your maximum health and stamina for a while. Resting (T) heals you too, but not with enemies near.\n\nHealers in temples cure you, and the Restoration school has healing spells."],
	["heavy", "Getting Started", "Carrying Too Much",
		"Everything has a weight. Carry more than your limit (shown in the inventory) and you slow to a walk and cannot sprint or fast travel. Drop things (Q drops one, Shift+Q all), sell them, or leave them in a chest you own. Strength raises the limit."],

	["combat", "Fighting", "Melee Combat",
		"Left click attacks; hold it for a heavy blow that staggers. Chain light attacks for a combo. A foe that glows is about to strike.\n\nRight click raises your shield or guard. Raise it just before a hit lands to parry: the attacker staggers and is open. Blocking and attacking use stamina."],
	["archery", "Fighting", "Bows, Crossbows and Throwing",
		"Equip a bow and hold left click to draw, let go to shoot: a full draw does the most. Arrows are taken from your pack (and can be picked out of bodies).

A crossbow shoots at full power with one click, then has to be wound again; its bolts pierce half of any armour. Throwing knives, axes and javelins: equip the stack and left click throws one. They can often be picked up again.

Where you hit matters: a head shot does half again as much, a leg hit slows them for a few seconds. All of these train Archery and are made at a forge.\n\nSneaking archers do extra damage to anyone who hasn't seen them."],
	["foes", "Fighting", "Foes and Factions",
		"Every creature belongs to a side. Wolves hunt deer, bandits fight the dead, and some sides leave each other be. Battles happen without you: wait for the winner, or join in.\n\nKilling a side's enemies raises your standing with it; at 25 it stops attacking you. Only what you kill stays dead: creatures killed by others come back.\n\nBosses have tricks: necromancers raise the dead, trolls heal unless burned, queens bring out their young.

Some people fight to answer how you fight: Shieldbearers turn arrows from the front (Chargers run at archers), Warded foes shrug off magic, Trackers spot sneaks quickly, and Duelists block and parry more. Their style shows by their name on the health bar."],
	["dungeons", "Fighting", "Dungeons",
		"Caves, crypts, mines and ruins are marked on the map once found. Each has a master in its deepest room: kill it and the dungeon is cleared, and its boss chest is yours. Cleared places fill up again after a few weeks (World settings).\n\nWatch for traps: sneak, or have Security 25, to see pressure plates. Levers open gates; a loose stone may hide a secret door. Fire sets off gas clouds. The deeper floors are darker: bring a torch or a light spell."],

	["magic", "Magic", "Casting Spells",
		"P opens the Magic page. E on a spell puts it in your off hand; right click casts it. Spells use magicka, which comes back over time.\n\nSchools: Destruction (fire, frost, shock), Restoration (healing, curing), Alteration (light, armour, water breathing), Illusion (calm, fear, invisibility), Conjuration (summons, bound weapons) and Mysticism (soul trap, detect life, telekinesis).\n\nLearn spells from tomes: mages sell them, dungeons hide them. Ranks run Novice, Apprentice, Adept, Expert and Master; the far islands' mages also sell Grandmaster (level 100) and Ascendant (150) tomes.\n\nScrolls cast their spell once, for free, whatever your skill: read one from the inventory.\n\nLevitate (Alteration) lets you fly for a while: double-tap Space to lift off or land, Space to rise, Ctrl to sink. Town wards pull you down. Water Walking lets you walk across lakes and the sea.\n\nElements combine: hit the same foe with two within 4 s. Fire then frost (or frost then fire): Thermal Shock, x1.5. Frost then shock: Shatter, x1.4 and a stagger. Shock then frost: Conduction. Shock then fire: Overload, a burst on everyone near. Poison and fire: Ignite.\n\nWards (Lesser, Steadfast, Greater) soak up spell damage until they break, and train Mysticism. Counterspell silences an enemy caster for a few seconds. A creature's health bar shows what it is immune to, resists, or is weak to."],
	["spellmaking", "Magic", "Making Spells",
		"An Altar of Spellmaking (in Mages Guild halls) lets you make your own spell from the effects of the spells you know: pick the effects, their strength, area and how long they last. The cost grows with all of them."],
	["enchanting", "Magic", "Enchanting and Soul Gems",
		"Soul Trap a creature just before it dies and its soul fills the smallest empty soul gem that holds it. At an arcane enchanter, a filled gem puts an effect you know on a weapon or a piece of armour. Enchanted weapons run down: recharge them with another filled gem."],

	["stealth", "Stealth and Crime", "Sneaking",
		"Ctrl sneaks. The eye on screen shows whether anyone has seen you. Darkness, sneaking, light armour and the Sneak skill help; running, torches and heavy armour hurt.\n\nAn attack on someone who hasn't seen you is a sneak attack: daggers and bows do the most. Sneak up behind someone unaware and press E to knock them out. Hide bodies in water or the dark.\n\nA foe who loses you searches where you were last seen, then gives up."],
	["locks", "Stealth and Crime", "Locks",
		"Locked doors and chests need a key or a lockpick. With lockpicks in your pack, E tries the lock: the chance depends on Security against the lock's level. A failed try breaks a pick. Some locks open only with their key.\n\nPicking a lock that isn't yours is a crime if someone sees."],
	["crime", "Stealth and Crime", "Crime and Bounty",
		"Taking what isn't yours (red text), attacking or killing people, trespassing after dark: anyone who sees it reports it, and the town puts a bounty on you. Witnesses tell their friends.\n\nGuards will stop you: pay, go to jail and serve the time, or fight. Someone who saw you might believe a lie (\"what you saw\"). The Thieves Guild fences stolen goods."],

	["leveling", "Your Character", "Skills and Levels",
		"Every skill rises by using it: swing a sword, cast a spell, pick a lock, haggle. There is no cap. Each skill gives a small bonus every 5 levels and a named milestone at 10, 25, 50, 75 and 100.\n\nSkill levels raise your character level. Each level brings a perk point, and some levels a feat. Trainers teach skills for gold (Train, in a conversation), up to their own rank: Journeymen to 50, Experts (guild officers, priests) to 75, Masters (guild leaders) to 100, and the Grandmasters of the far islands to 150. Being tired slows learning.\n\nWhen a skill reaches 50, and again at 100, a master of it sends word: raise it three more levels and their amulet, made for that skill, is yours. Past 100, a rare Tome of Mastery from the far islands raises your best skill to its next mastery step."],
	["perks", "Your Character", "Perks, Feats and Points",
		"C > Perks: eight trees (Warrior, Guardian, Marksman, Spellcaster, Shadow, Wanderer, Artisan, Leader). Spend a perk point to take one.\n\nSome perks give a move of your own: Shield Charge (Guardian), Whirlwind Sprint (Wanderer) and Shadow Step (Shadow). G uses it, Shift+G picks the next one you own. Two perks from different trees can unlock a hidden third, a synergy (Spellblade, Shadow Archer, Juggernaut...). From level 10 people give you a title by your build: the Unseen, Stormcaller...\n\nFeats (top of the page) are big build-defining choices, some with a price. C > Level Up spends attribute and vital points and shows your build's name. Its \"Start over\" button undoes every choice, for gold. You can also save two builds as loadouts A and B and take one up again at a temple shrine, for an offering."],
	["powers", "Your Character", "Powers and Standing Stones",
		"Z uses your race's power, once a day. Your birthsign gives a lasting gift. Every ring of standing stones keeps one sign: press E on the altar stone to take it as yours instead (once a day)."],

	["survival", "Body and Survival", "Food, Rest and Weather",
		"With Survival on (World settings), you grow hungry, tired and cold. Eat to stop hunger, sleep in a bed to rest, and dress warmly in the cold: each piece of clothing has its own warmth. A fire within a few metres keeps the cold off. Deserts and summer middays heat you, and rain and swimming soak you: dry off by a fire.\n\nMeals give buffs even with Survival off."],
	["rest", "Body and Survival", "Waiting and Sleeping",
		"T waits up to a day (not with enemies near). In a bed, it sleeps: rent a room from an innkeeper, or sleep in a bed you own. A comfortable sleep (a house, a fire, furnishings) leaves you Well Rested for longer, which speeds learning."],
	["night", "Body and Survival", "Night",
		"At night people go home and lock their doors, and the roads are more dangerous: ambushes wait for you. Some creatures only come out after dark. Carry a torch or a light spell, or wait (T) for dawn."],
	["disease", "Body and Survival", "Disease",
		"Bites and blows from rats, wolves and the dead can make you sick: the Character page shows what you have. Pray at a temple shrine, drink a Cure Disease potion or cast Cure Disease."],
	["vampire", "Body and Survival", "Vampirism",
		"You are a vampire. Food is useless: press F on sleeping people or fresh bodies to feed (Shift+F fills a bottle). The sun burns you when you are hungry, and a ravenous vampire is hunted in town. Priests know of a cure."],
	["werewolf", "Body and Survival", "Lycanthropy",
		"You are a werewolf. Press B to change, once a day; the full moon changes you anyway. In beast form, F on a body devours it. Being seen changing is a crime."],
	["swimming", "Body and Survival", "Water",
		"You can swim, slowly in armour. Under water your breath runs out: watch the bar and come up. An Air Bladder gives more. A Raft Kit (workbench) makes a raft at the water's edge."],

	["crafting", "Crafting", "Workstations and Recipes",
		"Press E on a workstation to craft: forges and anvils (smithing), workbenches, tanning racks, cooking pots and fires, alchemy labs, arcane enchanters. A recipe shows once you have held everything it needs. Your skill sets what you can make and how good it is."],
	["smithing", "Crafting", "Smithing",
		"At a forge, make weapons and armour from ingots and leather; smelt ore into ingots; and break old gear down for parts on the Salvage tab. Better metals need a higher Smithing skill.

Gear wears down as you use it (World settings: Gear wears down). Below half its condition a weapon hits softer and armour stops less; the inventory shows the condition. A smith's Repair button mends everything you have on for gold, and a Repair Hammer (workbench) mends it anywhere: more with Smithing."],
	["alchemy", "Crafting", "Alchemy",
		"At an alchemy lab, mix ingredients that share an effect into a potion. Eating an ingredient teaches you its first effect. Plants and parts are gathered in the wild and sold by apothecaries."],
	["cooking", "Crafting", "Cooking",
		"At a cooking pot or a campfire, cook raw meat, fish and vegetables into meals. Cooked food feeds you more and gives a buff for a while; raw meat can make you sick."],
	["gathering", "Crafting", "Gathering and Mining",
		"Pick plants (E), cut branches for firewood, pull plant fibre, dig clay and break rocks for stone and flint. Ore veins need a pickaxe: better pickaxes mine better ore. Fibre makes rope; stone, firewood and fibre make a stone pickaxe at a workbench."],
	["books", "Crafting", "Books and Notes",
		"Books are pages you turn (arrow keys or Back / Next). Skill books raise a skill the first time you read one. Notes on the dead and in dungeons tell what happened there, and sometimes lead to treasure."],

	["map", "Travel and the World", "The Map and Compass",
		"M opens the map. Places you have found are marked on it, and on the compass at the top of the screen when near. Quest targets show on both. Click the map to put down your own marker."],
	["travel", "Travel and the World", "Fast Travel and Roads",
		"On the map, pick a place you have found to travel there; time passes on the way (World settings may limit it to towns and inns). A long trip into the wilds may end in an ambush.\n\nRoads have highwaymen who want a toll, travellers in trouble and stranded carters. Carriages at town gates and ships at port piers take you further for gold."],
	["horses", "Travel and the World", "Horses",
		"Stables outside the bigger towns sell horses. E on your horse mounts it, E again dismounts; Shift gallops. Riding raises the Riding skill. Your horse waits where you left it.\n\nYou can fight from the saddle with more reach, and a gallop adds to every blow. A lance (forge) doubles that charge but is clumsy on foot. Horse barding (forge) gives you armour while you ride: use it from the inventory near your horse."],
	["islands", "Travel and the World", "The Far Islands",
		"The world is islands. The main island is for levels 1 to 100; across the sea lie islands of level 100 to 200 with harder foes, new metals (Voidsteel, Sunsteel, Astral, Primordial) and legendary arms. Ships sail from every port town. Going too far too soon is deadly: the map shows each island's level."],
	["realms", "Travel and the World", "Realms",
		"Some quests open a gate to another realm: a land apart with its own sky. Each has a hub with people, guarded sites with treasure, and a heart whose master you must defeat to conquer it. Leaving puts you back at the gate."],

	["talking", "Towns and People", "Talking",
		"E talks. Topics are on the right; highlighted words in what people say are topics too, and new ones have a dot. Along the bottom: Persuade (admire, intimidate, joke, bribe: each shows its chance), Gift, and services like Barter, Train and Rent Room.\n\nHow much someone likes you (disposition) changes prices and what they will tell you."],
	["trading", "Towns and People", "Buying and Selling",
		"Merchants buy and sell through Barter. Prices depend on Mercantile, disposition and the merchant's guild. Each merchant has limited gold, which comes back over a few days. Stolen goods sell only to fences."],
	["followers", "Towns and People", "Followers and Pets",
		"Sellswords in inns can be hired; others follow you after a quest. Talk to a follower to trade items with them, tell them to wait, or send them home. A tamed animal follows you too."],
	["taming", "Towns and People", "Taming",
		"Walk up to a calm wolf, boar, fox, bear, hound, rat or stalker with raw meat in your pack and press E. A tamed animal follows you and fights for you."],
	["marriage", "Towns and People", "Courting and Marriage",
		"Wear an Amulet of Mara (sold in temples) and talk to someone who likes you a lot (80): they may marry you. Court someone (\"spend time together\", once a day) and they will marry you sooner. A spouse moves into your home and shares a little of their earnings."],
	["guilds", "Quests and Guilds", "Guilds",
		"Eight guilds: Fighters, Mages, Knightly Order, Thieves, Assassins, Antiquarians, Hunters and Merchants. Ask a guild's leader about \"membership\" to join, \"duties\" for work and \"advancement\" to rise through its five ranks. Each rank gives a perk."],
	["council", "Quests and Guilds", "The Council of Houses",
		"K opens the Council. Eight noble houses vie to rule when the king dies. Their quests raise your standing and their influence; sworn to one, you can carry it to the throne."],
	["quests", "Quests and Guilds", "Quests and the Journal",
		"Quests come from people (ask about work and rumours), notice boards, bounty boards, guilds and the main quest, The Ashen Eclipse. J opens the journal: Quests shows what to do next. Track a quest to see it on the compass and the map."],
	["report_back", "Quests and Guilds", "Reporting Back",
		"When a job is done, go back to whoever gave it and ask about \"report back\". A ? over someone means they want to see you."],
	["journal_notes", "Quests and Guilds", "Your Own Notes",
		"The journal keeps one entry per topic. Write your own notes in the Notes tab (\"+ New note\"), or Shift+J from anywhere. A note can be pinned, coloured, and linked to a quest or place."],
	["arena", "Quests and Guilds", "The Arena",
		"Every Fighters Guild hall has an arena. Strike the gong (E) to start the next bout. Win seven to be Grand Champion; after that you defend the title for gold. Walking out forfeits."],
	["museum", "Quests and Guilds", "The Museum",
		"Antiquarian Museums take the artifacts you find (dig sites, dungeons, Antiquarian jobs). Each donation is paid in full and adds +2 to your maximum health, for good."],

	["homes", "Homes and Settlers", "Houses",
		"Houses for sale have a sign; ask a guard or the steward about homes. A house is yours to sleep in and store things in: chests in your own house never empty."],
	["homestead", "Homes and Settlers", "Your Homestead",
		"Buy a plot outside a town (ask the steward) and build it up part by part with materials: a hall, walls, a garden, a forge. Settlers can live there: free prisoners from dungeon cells or ask travellers. Give them jobs (farmer, hunter, woodcutter, guard, smith) and keep them fed."],
	["raids", "Homes and Settlers", "Raids and the Blood Moon",
		"A homestead that has grown draws raiders every week or two: guards and walls help. On the last night of every month the blood moon rises and hordes walk (Interface > Blood moon)."],
	["stations", "Homes and Settlers", "Workstations Nearby",
		"There are workstations in here. Press E on one to craft. See Crafting > Workstations and Recipes."],
]

## Old pop-up hint ids that now open another page
const ALIAS := {"low_health": "health", "dungeon": "dungeons"}

static var _by_id := {}


static func page(id: String) -> Array:
	if _by_id.is_empty():
		for p in PAGES:
			_by_id[p[0]] = p
	return _by_id.get(ALIAS.get(id, id), [])


static func groups() -> Array:
	var out := []
	for p in PAGES:
		if not out.has(p[1]):
			out.append(p[1])
	return out


static func has_come_up(id: String) -> bool:
	return WorldState.has_record("tut/" + String(ALIAS.get(id, id)))


static func is_unread(id: String) -> bool:
	var rec := WorldState.get_record("tut/" + id)
	return not rec.is_empty() and not bool(rec.get("read", true))


static func mark_read(id: String) -> void:
	if has_come_up(id):
		WorldState.set_record("tut/" + id, {"read": true})


static func unread_count() -> int:
	var n := 0
	for p in PAGES:
		n += 1 if is_unread(p[0]) else 0
	return n


## The page comes up (first time only). Returns true if it was new.
static func come_up(id: String) -> bool:
	id = String(ALIAS.get(id, id))
	if page(id).is_empty() or has_come_up(id):
		return false
	WorldState.set_record("tut/" + id, {"read": false})
	return true


## The page as BBCode for the journal
static func text_of(id: String) -> String:
	var p := page(id)
	if p.is_empty():
		return ""
	var out := "[color=#ffd95a][b][font_size=22]%s[/font_size][/b][/color]\n[color=#b8a47a]Guide  ·  %s[/color]\n\n%s\n" % [p[2], p[1], DialogueUI._esc(String(p[3]))]
	var tied := []
	for a in Achievements.LIST:
		if a[4] == p[0]:
			tied.append(a)
	if not tied.is_empty():
		out += "\n[b]Achievements[/b]\n"
		for a in tied:
			out += "%s %s\n" % ["[color=#8fd18f][lb]x][/color]" if Achievements.is_unlocked(a[0]) else "[lb] ]", a[2]]
	return out
