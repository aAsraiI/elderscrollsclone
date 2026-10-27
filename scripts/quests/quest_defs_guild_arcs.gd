class_name QuestDefsGuildArcs
extends RefCounted
## What comes after the top of each guild (1.17): once you lead a guild (its G-..07), a longer arc of four
## quests (08 to 11), the troubles only its head would face, levels 42 to 55, with a second-in-command who
## speaks for the guild and a choice at the end that decides what the guild becomes.

const W := "res://data/weapons/"
const A := "res://data/armor/"
const J := "res://data/jewelry/"


static func _a(f: String, code: String, n: int, who: Dictionary, name: String, level: int, hook: String, intro: String, steps: Array, reward: Dictionary) -> Dictionary:
	var prev := "G-%s%02d" % [code, n - 1]
	return QD.q("G-%s%02d" % [code, n], name, Factions.display_name(f), who, level, hook, intro, steps, reward, QD.fac(f, 5, [prev]))


static func list() -> Array:
	var out: Array = []
	out.append_array(_fighters())
	out.append_array(_mages())
	out.append_array(_knights())
	out.append_array(_thieves())
	out.append_array(_assassins())
	out.append_array(_antiquarians())
	out.append_array(_hunters())
	out.append_array(_merchants())
	return out


# ---------------------------------------------------------------- Fighters Guild: the Iron Company
static func _fighters() -> Array:
	var sel := QD.cast("Marshal Sela Brandt", "Kingsreach", "inn")
	return [
		_a("fighters", "FG", 8, sel, "The Iron Company", 42, "the iron company",
			"A sellsword army calling itself the Iron Company is buying up every contract in the south, and hiring every blade we turn away.",
			[QD.talk(sel, "who the iron company are", "Two hundred blades, maybe more, under a man called Garrow Vane. He fought in the Tourney the year before you won it and lost in the second round. He has not forgotten. He undercuts us, then does the work badly and lets the bandits go, so the work comes back. It is a business. Go and see it for yourself: the Company holds the old fort on the Harrowford road.", "Hear Marshal Brandt out about the Iron Company."),
			QD.visit(QD.camp("Harrowford", 2), "Scout the Iron Company's fort on the Harrowford road."),
			QD.fight(QD.camp("Harrowford", 2), [QD.f("deserter", 4, "Iron Company Blade")], "Break the Iron Company's outer camp."),
			QD.talk(sel, "what the fort holds", "So they are paid by the same houses who pay us. Both sides of every contract. Vane is not a soldier anymore. He is a merchant of trouble. We cannot outbid him. We can out-fight him.", "Report to Marshal Brandt.")],
			QD.reward(1500)),
		_a("fighters", "FG", 9, sel, "Turncoats", 45, "the turncoats",
			"Three of our own captains have gone over to the Iron Company, and they took the guild's war-chest ledger with them.",
			[QD.talk(sel, "the missing captains", "Henrik, Oda and old Fenn. Fenn taught me to hold a shield. They left in the night with the ledger: every contract we hold, every hall, every pay-day. Get the ledger back. As for them... you are the head of this guild. You decide.", "Hear Marshal Brandt about the turncoats."),
			QD.fetch(QD.dun("Kingsreach", 4), "Guild War-Chest Ledger", "Recover the guild ledger from the turncoats' hideout."),
			QD.choice(sel, "Decide what happens to the turncoat captains.", [QD.opt("bring them home", "Fenn wept when you told him. Oda spat. Henrik said nothing. They will march in the front rank until they have paid it back. A guild that cannot forgive is a guild that cannot grow.", "forgiven"), QD.opt("cast them out", "Out. Their names come off the hall wall tonight. Hard, but the others saw it. Nobody else will walk out with a ledger.", "cast_out")])],
			QD.reward(1600)),
		_a("fighters", "FG", 10, sel, "The Siege of Harrowford", 48, "the siege of harrowford",
			"Garrow Vane has taken Harrowford's walls by contract. He means to hold the town until the houses pay to have him leave.",
			[QD.talk(sel, "harrowford taken", "He has the gates. He has the granary. He says the town is under his protection, at a price. We have sixty swords and the town has four hundred hungry people. I will take the north gate. Take the south. Do not let him burn the granary.", "Plan the relief of Harrowford with Marshal Brandt."),
			QD.fight(QD.town("Harrowford"), [QD.f("deserter", 4, "Iron Company Blade"), QD.f("bandit_brute", 2)], "Take the south gate of Harrowford."),
			QD.fight(QD.town("Harrowford"), [QD.f("deserter_captain", 1, "Garrow Vane")], "Face Garrow Vane at the granary."),
			QD.talk(sel, "the town freed", "Vane is done. The Company scattered the moment he fell. Harrowford wants to give the guild the old fort. The houses want to know why we let a sellsword get that big. I want a drink.", "Meet Marshal Brandt in Harrowford.")],
			QD.reward(1800, {"named": [QD.named("Vane's Breaker", W + "dragonbone_warhammer.tres", [["fortify_attack", 12]], 4)]})),
		_a("fighters", "FG", 11, sel, "What the Guild Is For", 52, "what the guild is for",
			"After Harrowford, the houses offer the Fighters Guild a standing army's charter. It would make the guild rich, and make it a weapon.",
			[QD.talk(sel, "the charter", "A royal charter. Pay from the treasury, a hall in every town, the right to raise levies. We would never want for anything again. And we would answer to whoever holds the purse. The Guild has been a sword for hire for three hundred years. You are the one who decides whether it becomes the King's.", "Hear what the houses offer."),
			QD.choice(sel, "Decide what the Fighters Guild becomes.", [QD.opt("refuse the charter", "Free blades, then. Poorer, and our own. I will tell the houses. They will not like it, and they will still hire us, because nobody else can do what we do.", "free"), QD.opt("take the charter", "The King's Guild. We will be safe for a hundred years. Let's hope the kings are worth it.", "charter")])],
			QD.reward(2500, {"named": [QD.named("Marshal's Plate", W + "dragonbone_chestplate.tres", [["fortify_block", 15], ["fortify_health", 30]], 4)]})),
	]


# ---------------------------------------------------------------- Mages Guild: the Sealed Stacks
static func _mages() -> Array:
	var ren := QD.cast("Archivist Renn Holloway", "Merewater", "inn")
	return [
		_a("mages", "MG", 9, ren, "The Sealed Stacks", 43, "the sealed stacks",
			"Under the guild's oldest hall lie the Sealed Stacks, books the masters agreed never to read. Someone has been reading them.",
			[QD.talk(ren, "who opened the stacks", "The wards on the Stacks were broken from the inside. Which means whoever did it was already in. Three apprentices have stopped sleeping. They talk in their beds in a language I do not know. I am an archivist, Master. I catalogue things. I do not know what to do with a book that catalogues you back.", "Speak with Archivist Holloway."),
			QD.clear(QD.dun("Merewater", 3), "Go down into the Sealed Stacks beneath the guild's old hall."),
			QD.fetch(QD.dun("Merewater", 3), "The Unwritten Index", "Find the book that was taken from its shelf."),
			QD.talk(ren, "the unwritten index", "It is blank. And then it isn't: whatever you think about, it writes. It was in the Stacks because it does not stop. Somebody wanted it for a reason, and they are still in the guild.", "Bring the book to Archivist Holloway.")],
			QD.reward(1500)),
		_a("mages", "MG", 10, ren, "The Sleeping Apprentices", 46, "the sleeping apprentices",
			"The three apprentices have stopped waking up at all.",
			[QD.talk(ren, "the dreaming three", "Their eyes move under the lids as if they are reading. Whatever is in the Index has followed them into sleep. There is an old way in, through a dream-ward the guild founder made. It is in a ruin by the lake. Nobody has used it in a century.", "Hear what has become of the apprentices."),
			QD.visit(QD.wild("Merewater", 500.0, 260.0), "Find the founder's dream-ward by the lake."),
			QD.fight(QD.wild("Merewater", 500.0, 260.0), [QD.f("ice_wraith", 2, "Dream-Shade"), QD.f("fire_spirit", 2, "Dream-Shade")], "Drive the shades out of the apprentices' dream."),
			QD.talk(ren, "the apprentices wake", "They woke. All three. And they all said the same name: Master Corvane. He sat on the council that voted you in. He has been feeding the Index his own dreams, and theirs, to make it write him something.", "Return to Archivist Holloway.")],
			QD.reward(1600)),
		_a("mages", "MG", 11, ren, "Master Corvane", 49, "master corvane",
			"Master Corvane has left the guild with the Unwritten Index's twin, and a dozen loyal students.",
			[QD.talk(ren, "what corvane wants", "There were two books. One writes what you think. The other makes it true. He found the second in the Stacks years ago. He needed the first to learn how to use it. He has gone to the old observatory in the hills. If he finishes reading, the world is whatever Corvane imagines.", "Hear what Master Corvane took."),
			QD.clear(QD.dun("Merewater", 4), "Storm Corvane's observatory."),
			QD.fight(QD.dun("Merewater", 4), [QD.f("ashen_priest", 2, "Corvane's Student"), QD.f("ashen_priest", 1, "Master Corvane")], "Stop Master Corvane."),
			QD.fetch(QD.dun("Merewater", 4), "The Unmade Book", "Take the second book from Corvane."),
			QD.talk(ren, "the unmade book", "Do not open it. I mean it. Give it to me and do not even think near it.", "Bring the book to Archivist Holloway.")],
			QD.reward(1900, {"named": [QD.named("Corvane's Circlet", J + "gemmed_amulet_insight.tres", [["fortify_magicka", 40]], 4)]})),
		_a("mages", "MG", 12, ren, "The Two Books", 53, "the two books",
			"Two books, one that writes your thoughts and one that makes them true. The guild must decide what to do with them.",
			[QD.choice(ren, "Decide the fate of the two books.", [QD.opt("burn them both", "They burned for three days, and the smoke made pictures nobody wants to describe. The Stacks are emptier. The world is safer. Some of the masters will never forgive you.", "burned"), QD.opt("seal them apart", "One under Merewater, one under the mountain at Cinderhold, and a ward between them that only the guild's head can open. Wisdom, or a temptation for whoever comes after you. Time will tell.", "sealed"), QD.opt("study them", "Carefully. Slowly. With every ward the guild knows. Knowledge is never the danger, you said. The masters cheered. I hope you are right.", "studied")])],
			QD.reward(2500)),
	]


# ---------------------------------------------------------------- Knights: the Oath-Breaker
static func _knights() -> Array:
	var bel := QD.cast("Knight-Captain Bellamy Rook", "Kingsreach", "inn")
	return [
		_a("knights", "KO", 8, bel, "The Oath-Breaker", 43, "the oath-breaker",
			"Ser Aldous Crane, the Order's greatest champion, has renounced his oath and ridden south with forty knights.",
			[QD.talk(bel, "ser aldous", "He says the Order has grown fat guarding a princess while the borderlands burn. He is not wrong. That is the problem with him: he is rarely wrong, and never willing to wait. He has sworn a crusade against the raiders in the badlands. He will kill the guilty and the innocent alike, and call it duty.", "Speak with Knight-Captain Rook."),
			QD.visit(QD.camp("badlands", 1), "Ride to the badlands and find Ser Aldous's camp."),
			QD.talk(bel, "the crusade camp", "Burned villages behind him and a raider camp ahead. Some of the burned ones were raiders. Some were shepherds.", "Report what you found to Knight-Captain Rook.")],
			QD.reward(1500)),
		_a("knights", "KO", 9, bel, "The Shepherds of Redsand", 46, "the shepherds of redsand",
			"Ser Aldous means to burn Redsand next. Its people are not raiders, but the raiders shelter there.",
			[QD.fight(QD.camp("Redsand", 1), [QD.f("raider", 3), QD.f("raider_marauder", 2)], "Drive the raiders out of Redsand before Ser Aldous arrives."),
			QD.choice(bel, "Ser Aldous's knights are at the gate. Tell Knight-Captain Rook what to do.", [QD.opt("stand between them", "You stood in the gate in the Order's colours and dared him to ride through you. He didn't. Some of his knights wept. Redsand still stands.", "stood"), QD.opt("let him pass, under watch", "He rode in, saw the raiders already dead, and rode out again. Nobody died. But he knows you let him in.", "watched")])],
			QD.reward(1700)),
		_a("knights", "KO", 10, bel, "Trial by Combat", 49, "trial by combat",
			"Ser Aldous demands a trial by combat to settle whether the Order serves the throne or the realm.",
			[QD.talk(bel, "the trial", "Old law. If he wins, the Order rides with him. If you win, his knights come home. He wants it in the Tourney grounds outside Kingsreach, in front of everyone. He is better than any knight alive. Except, possibly, you.", "Hear Knight-Captain Rook about the trial."),
			QD.fight(QD.wild("Kingsreach", 260.0, 200.0), [QD.f("deserter_captain", 1, "Ser Aldous Crane")], "Face Ser Aldous in the trial by combat."),
			QD.talk(bel, "the trial won", "He yielded. He has never yielded in his life. He asked me to give you this: his old shield, the one with the burned lion. He said you carry it better than he did.", "Return to Knight-Captain Rook.")],
			QD.reward(2000, {"named": [QD.named("The Burned Lion", W + "dragonbone_shield.tres", [["fortify_block", 20]], 4)]})),
		_a("knights", "KO", 11, bel, "The Order and the Realm", 53, "the order and the realm",
			"Ser Aldous and his knights wait to hear the Order's new purpose from its head.",
			[QD.choice(bel, "Declare what the Order serves.", [QD.opt("the realm", "The borderlands will have knights again. Ser Aldous will lead them, under your banner and your law. The princess will still have her guard. Just a smaller one.", "realm"), QD.opt("the crown", "The crown, as it always has. Ser Aldous will go into exile with his honour. The Order will stand where it always stood. Some of the young ones will follow him anyway.", "crown")])],
			QD.reward(2500)),
	]


# ---------------------------------------------------------------- Thieves: the War of Fences
static func _thieves() -> Array:
	var mag := QD.cast("Magpie", "Saltmere", "inn")
	return [
		_a("thieves", "TG", 8, mag, "The War of Fences", 42, "the war of fences",
			"Someone is buying every fence in the south out from under the guild.",
			[QD.talk(mag, "the bought fences", "Twelve fences in a month. Paid in gold, not threats, which is worse. A fence you threaten comes back when you leave. A fence you buy stays bought. The money comes through a counting-house in Saltmere called the Tallow Lamp. It sells candles. It sells a great many candles.", "Speak with Magpie."),
			QD.fetch(QD.town("Saltmere"), "Tallow Lamp Account Book", "Steal the Tallow Lamp's account book."),
			QD.talk(mag, "the account book", "The Merchants Guild. Or someone inside it. They want the fences because they want the stolen goods back, so they can sell them again, legally, at twice the price. Honest thieves, robbed by dishonest merchants.", "Bring Magpie the account book.")],
			QD.reward(1500)),
		_a("thieves", "TG", 9, mag, "Burn the Lamp", 45, "burn the lamp",
			"The Tallow Lamp's owner has hired muscle to protect the warehouse where the bought goods are kept.",
			[QD.fight(QD.dun("Saltmere", 2), [QD.f("smuggler", 3), QD.f("smuggler_chief", 1, "Tallow Lamp Overseer")], "Break into the Tallow Lamp's warehouse."),
			QD.choice(mag, "The warehouse is full of stolen goods. Tell Magpie what to do with them.", [QD.opt("give them back", "Back to their owners, with a note: compliments of the Guild. People will talk about it for years. The guild has never been so popular, or so poor.", "returned"), QD.opt("keep them", "Ours again. A good night's work. The merchants will know exactly who did it, and they will not be able to say why.", "kept")])],
			QD.reward(1700)),
		_a("thieves", "TG", 10, mag, "The Grey Factor", 49, "the grey factor",
			"The man behind the Tallow Lamp is a factor of the Merchants Guild called Edric Morrow, and he has the city watch in his pocket.",
			[QD.talk(mag, "edric morrow", "He keeps every bribe in a strongbox in his own house, because he trusts nobody. Which is lucky for us, because it means every bribe is in one place.", "Hear Magpie about the factor."),
			QD.fetch(QD.town("Saltmere"), "Morrow's Bribe-Book", "Steal Edric Morrow's book of bribes from his house."),
			QD.talk(mag, "the bribe-book", "Every captain of the watch in Saltmere, the harbourmaster, two magistrates. We could hang him with this. Or we could own them all.", "Bring Magpie the bribe-book.")],
			QD.reward(1900)),
		_a("thieves", "TG", 11, mag, "The Shadow Ledger's Last Page", 53, "the last page",
			"With Morrow's book the guild could break the Merchants Guild's hold on the south, or take its place.",
			[QD.choice(mag, "Decide what the guild does with Morrow's book.", [QD.opt("give it to the magistrates", "Morrow hangs. Half the watch is replaced. The new watch is honest, and much harder on thieves. You have made Saltmere better and the guild's life worse. Magpie thinks you've gone soft.", "justice"), QD.opt("keep it", "The guild owns Saltmere's watch now. Nobody will ever know. Magpie calls you the best head the guild has had in a hundred years.", "owned")])],
			QD.reward(2500, {"named": [QD.named("Magpie's Gloves", A + "shadowscale_gauntlets.tres", [["fortify_lockpicking", 20], ["fortify_sneak", 15]], 4)]})),
	]


# ---------------------------------------------------------------- Assassins: the Contract on You
static func _assassins() -> Array:
	var wren := QD.cast("Wren the Quiet", "Blackfen", "inn")
	return [
		_a("assassins", "AS", 8, wren, "A Contract on the Head", 43, "the contract on you",
			"Someone has taken out a contract on the head of the Brotherhood. On you.",
			[QD.talk(wren, "who wants you dead", "It came through the old drop in the fen, written properly, paid in full. Three thousand crowns. Whoever wrote it knows our ways, which means they are, or were, one of us. The first of the knives is already in Blackfen.", "Speak with Wren."),
			QD.fight(QD.town("Blackfen"), [QD.f("cutthroat", 3, "Hired Knife")], "Survive the first attempt on your life."),
			QD.fetch(QD.town("Blackfen"), "Contract Seal", "Take the contract's seal from the leader of the knives."),
			QD.talk(wren, "the contract seal", "The seal of the Widow. The one who held your seat before you. The one we buried. We buried someone, anyway.", "Show Wren the seal.")],
			QD.reward(1500)),
		_a("assassins", "AS", 9, wren, "The Widow's Grave", 46, "the widow's grave",
			"If the Widow is alive, someone else is in her grave.",
			[QD.visit(QD.wild("Blackfen", 400.0, 140.0), "Go to the Widow's grave in the fen."),
			QD.fight(QD.wild("Blackfen", 400.0, 140.0), [QD.f("skeleton", 3), QD.f("barrow_wight", 1)], "Open the grave."),
			QD.talk(wren, "an empty grave", "Empty. Of course. She taught us that a death nobody can prove is the only clean one. She has been gone two years, waiting for the Brotherhood to grow fat under someone else, so she could take it back.", "Tell Wren what you found.")],
			QD.reward(1700)),
		_a("assassins", "AS", 10, wren, "The Widow", 50, "the widow returns",
			"The Widow has sent word: she will meet you at the old sanctuary, and one of you will leave.",
			[QD.clear(QD.dun("Blackfen", 2), "Enter the old sanctuary of the Brotherhood."),
			QD.fight(QD.dun("Blackfen", 2), [QD.f("cutthroat", 2, "Widow's Faithful"), QD.f("vampire", 1, "The Widow")], "Face the Widow."),
			QD.talk(wren, "the widow's end", "She took the dark gift. That was how she survived. She would have outlived all of us. Not anymore.", "Return to Wren.")],
			QD.reward(2000, {"named": [QD.named("The Widow's Veil", A + "shadowscale_helmet.tres", [["fortify_sneak", 20]], 4)]})),
		_a("assassins", "AS", 11, wren, "The Quiet Rule", 53, "the quiet rule",
			"The Brotherhood watched you kill its old master. Now it waits to see what kind of master you will be.",
			[QD.choice(wren, "Set the Brotherhood's rule.", [QD.opt("only the guilty", "No more contracts on the innocent. Fewer contracts, less gold, and every one of them you could explain to a priest. Some of the old hands will leave.", "guilty"), QD.opt("any contract, paid in full", "The old way. No questions. The gold flows. The Brotherhood is feared again, and so are you.", "any")])],
			QD.reward(2500)),
	]


# ---------------------------------------------------------------- Antiquarians: the Buried City
static func _antiquarians() -> Array:
	var tor := QD.cast("Curator Tobiah Lark", "Dustgate", "inn")
	return [
		_a("antiquarians", "AN", 8, tor, "The Map Under the Map", 42, "the map under the map",
			"Restoring an old map, the Society found a second map painted beneath it: a city that is on no chart.",
			[QD.talk(tor, "the hidden map", "Painted over on purpose, by someone who wanted it forgotten but couldn't bring themselves to destroy it. A city of the First Kings, under the deep desert past Dustgate. If it is real, it is the find of the age. If it is a trap, it is a very old one.", "Speak with Curator Lark."),
			QD.visit(QD.wild("Dustgate", 600.0, 200.0), "Find the place on the hidden map in the deep desert."),
			QD.talk(tor, "the city is real", "A dome under the sand, and a door with no handle. Writing on it in a language even the Society cannot read. We need someone who can.", "Report to Curator Lark.")],
			QD.reward(1500)),
		_a("antiquarians", "AN", 9, tor, "The Language of Doors", 46, "the language of doors",
			"Only one scholar alive reads the First Kings' tongue: Magister Ysolde Crane of Merewater.",
			[QD.talk(QD.cast("Magister Ysolde Crane", "Merewater", "guild:mages"), "the desert door", "'Speak your purpose and be weighed.' Not a lock. A judge. The door asks why you have come, and if it doesn't like your answer, it does not open. If it really doesn't like it, I imagine it does something else.", "Ask Magister Crane to read the door."),
			QD.clear(QD.dun("Dustgate", 3), "Enter the buried city."),
			QD.fight(QD.dun("Dustgate", 3), [QD.f("vault_guardian", 2, "Brass Sentinel")], "Get past the city's guardians.")],
			QD.reward(1700)),
		_a("antiquarians", "AN", 10, tor, "The King's Library", 50, "the buried library",
			"At the heart of the buried city lies a library the First Kings sealed when they left.",
			[QD.clear(QD.dun("Dustgate", 4), "Descend to the city's library."),
			QD.fight(QD.dun("Dustgate", 4), [QD.f("vault_guardian", 1, "The Librarian"), QD.f("dune_stalker", 2)], "Defeat the library's ancient keeper."),
			QD.fetch(QD.dun("Dustgate", 4), "Atlas of the First Kings", "Take the Atlas of the First Kings."),
			QD.talk(tor, "the atlas", "Every city they built. Seven of them. We know of one. Do you understand? There are six more.", "Bring the Atlas to Curator Lark.")],
			QD.reward(2000, {"named": [QD.named("Curator's Spectacles", J + "gold_amulet_insight.tres", [["fortify_magicka", 25], ["fortify_speech", 15]], 4)]})),
		_a("antiquarians", "AN", 11, tor, "Seven Cities", 53, "seven cities",
			"The Atlas shows six more lost cities. Whoever holds it decides who digs them up.",
			[QD.choice(tor, "Decide what becomes of the Atlas.", [QD.opt("publish it", "Copies for every university and every guild. Scholars from three kingdoms are already on the road. So are the tomb-robbers. History belongs to everyone, you said. Everyone is coming to collect.", "published"), QD.opt("keep it for the Society", "Locked in the Society's vault. The Society will dig them, slowly and properly, for the next hundred years. Some say you are hoarding the past.", "kept")])],
			QD.reward(2500)),
	]


# ---------------------------------------------------------------- Hunters: the Beast-God
static func _hunters() -> Array:
	var iva := QD.cast("Iva Thornback", "Thornhaven", "inn")
	return [
		_a("hunters", "HL", 8, iva, "Tracks Too Large", 42, "tracks too large",
			"Hunters in the deep forest have found tracks the size of a cart, and no one who followed them has come back.",
			[QD.talk(iva, "the great tracks", "Not a bear. Not a troll. Four toes, and the claw-marks are on trees thirty feet up. The old Lodge stories call it the Antlered Mother, the first beast, the one all the others came from. I thought they were stories. The White Stag was a story too, until you hunted it.", "Speak with Iva Thornback."),
			QD.fight(QD.wild("Thornhaven", 500.0, 80.0), [QD.f("frost_bear", 2), QD.f("werewolf", 1)], "Follow the tracks into the deep forest."),
			QD.talk(iva, "the beasts were fleeing", "They weren't hunting. They were running. Everything in that forest is running from something.", "Report to Iva Thornback.")],
			QD.reward(1500)),
		_a("hunters", "HL", 9, iva, "The Druid's Warning", 45, "the druid's warning",
			"An old druid who lives in a hollow oak says the Antlered Mother has woken because someone is hunting her children.",
			[QD.talk(QD.cast("Hollow-Oak Maera", "Thornhaven", "house"), "the antlered mother", "She sleeps a thousand years, and wakes when the balance tips. Someone has been killing her children for their pelts. Not for meat, not for need. Pelts by the cartload, sold in the south. Stop the poachers and she may sleep again. Or don't, and see what a mother does.", "Hear the druid's warning."),
			QD.fight(QD.camp("Thornhaven", 2), [QD.f("trapper", 3), QD.f("hunter", 2, "Poacher-Captain")], "Break the poachers' camp."),
			QD.fetch(QD.camp("Thornhaven", 2), "Poachers' Ledger", "Find out who buys the pelts.")],
			QD.reward(1700)),
		_a("hunters", "HL", 10, iva, "The Antlered Mother", 50, "the mother wakes",
			"The poachers are gone, but the Antlered Mother is still awake, and she is coming to Thornhaven.",
			[QD.choice(iva, "The Mother is at the edge of the forest. Tell Iva what the Lodge will do.", [QD.opt("let her pass", "You stood in her way with your bow lowered. She looked at you for a long time, then turned back into the trees. The forest is quiet. Some say they saw her bow her head.", "spared"), QD.opt("hunt her", "The greatest hunt of the Lodge's history.", "hunted")]),
			QD.fight(QD.wild("Thornhaven", 300.0, 0.0), [QD.f("frost_bear", 1, "The Antlered Mother")], "Face the Antlered Mother at the forest's edge."),
			QD.talk(iva, "after the mother", "Whatever happened out there, the forest is different now. Lighter, somehow. Or emptier. I can't tell.", "Return to Iva Thornback.")],
			QD.reward(2000, {"named": [QD.named("Mother's Antler Bow", "res://data/ranged/ebon_bow.tres", [["fortify_attack", 12]], 4)]})),
		_a("hunters", "HL", 11, iva, "The Lodge's Law", 53, "the lodge's law",
			"After the Mother, the Lodge must decide how it hunts from now on.",
			[QD.choice(iva, "Set the Lodge's law.", [QD.opt("hunt only for need", "Meat and hide, never sport. Fewer trophies on the Lodge walls. The forests will be fuller in your grandchildren's time.", "need"), QD.opt("the hunt is the hunt", "The Lodge hunts what it likes, as it always has. The trophies grow. So do the empty places in the woods.", "sport")])],
			QD.reward(2500)),
	]


# ---------------------------------------------------------------- Merchants: the Grain War
static func _merchants() -> Array:
	var hes := QD.cast("Factor Hesper Quill", "Kingsreach", "inn")
	return [
		_a("merchants", "MC", 8, hes, "The Grain War", 42, "the grain war",
			"A drought in the south, and someone is buying every sack of grain in the north to sell it back at ten times the price.",
			[QD.talk(hes, "the grain buyers", "A consortium out of Saltmere, the Iron Crown Trading House. They have bought the harvest of three valleys before it was sown. In a month there will be hunger in Dustgate and Sunhold. In two, riots. They will sell when people are desperate, and not before. It is legal. It is also monstrous.", "Speak with Factor Quill."),
			QD.fetch(QD.dun("Saltmere", 3), "Iron Crown Grain Contracts", "Steal the Iron Crown's grain contracts."),
			QD.talk(hes, "the contracts", "Signed by the Treasurer of Kingsreach himself, through a cousin. The court is in on it.", "Bring Factor Quill the contracts.")],
			QD.reward(1500)),
		_a("merchants", "MC", 9, hes, "Caravans South", 46, "caravans south",
			"The Guild means to break the price by running its own grain south, and the Iron Crown has hired raiders to stop it.",
			[QD.fight(QD.wild("Dustgate", 450.0, 0.0), [QD.f("raider", 3), QD.f("raider_marauder", 2)], "Guard the Guild's grain caravan on the desert road."),
			QD.visit(QD.town("Dustgate"), "See the caravan safely into Dustgate."),
			QD.talk(hes, "grain in dustgate", "They are lining up in the square. They brought their own sacks. A woman gave me a ring she had worn for forty years for a sack of flour, and I could not make her take it back. Go home and rest. Then we finish this.", "Meet Factor Quill in Dustgate.")],
			QD.reward(1800)),
		_a("merchants", "MC", 10, hes, "The Treasurer's Cousin", 50, "the treasurer's cousin",
			"The Iron Crown is the Treasurer's family business. Exposing it means taking on the court.",
			[QD.talk(hes, "the treasurer", "Lord Treasurer Aubrey Fane. Untouchable, they say. Nobody is untouchable if you hold their ledgers. His are in the counting-room at the top of the Iron Crown's tower in Saltmere.", "Hear Factor Quill's plan."),
			QD.fight(QD.dun("Saltmere", 4), [QD.f("caravan_guard", 3), QD.f("smuggler_chief", 1, "Iron Crown Steward")], "Take the Iron Crown's counting-room."),
			QD.fetch(QD.dun("Saltmere", 4), "The Treasurer's Ledgers", "Take the Treasurer's private ledgers.")],
			QD.reward(2000)),
		_a("merchants", "MC", 11, hes, "Fair Measure", 53, "fair measure",
			"With the Treasurer's ledgers, the Guild can bring down the Iron Crown, or buy it.",
			[QD.choice(hes, "Decide what the Guild does with the Treasurer's ledgers.", [QD.opt("bring them to the king", "Fane is stripped of office. The Iron Crown is broken up and its grain sold at a fair price. The Guild is the hero of the south. And it has a great many new enemies at court.", "exposed"), QD.opt("buy the Iron Crown", "The Guild owns the Iron Crown now, quietly. Grain flows south at a fair price, because you say so. The Guild is the richest power in the realm. Fane keeps his job, and does what you ask.", "bought")])],
			QD.reward(2500, {"named": [QD.named("Factor's Seal-Ring", J + "gold_ring_insight.tres", [["fortify_speech", 25]], 4)]})),
	]
