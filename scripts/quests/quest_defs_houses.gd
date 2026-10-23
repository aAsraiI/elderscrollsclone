class_name QuestDefsHouses
extends RefCounted
## The eight noble houses (H-..). Quest 01 is the trial: finishing it swears you to the house
## (and closes the other seven). 04 is the mid gate (needed for rank 3), 07 the final gate (rank 5),
## 08 the house's ending for the regency.

const W := "res://data/weapons/"
const A := "res://data/armor/"
const J := "res://data/jewelry/"
const R := "res://data/ranged/"
const RANKS := [0, 1, 1, 2, 3, 3, 4, 5]


# One house quest: n = its number (1..8); the trial joins, the rest need the house rank
static func _h(f: String, code: String, n: int, name: String, group: String, giver: Dictionary, level: int, hook: String, intro: String, steps: Array, reward: Dictionary) -> Dictionary:
	var id := "H-%s%02d" % [code, n]
	var after: Array = [] if n == 1 else ["H-%s%02d" % [code, n - 1]]
	if n == 1:
		reward["join"] = f
	return QD.q(id, name, group, giver, level, hook, intro, steps, reward, QD.fac(f, RANKS[n - 1], after))


static func list() -> Array:
	var out: Array = []
	out.append_array(_valcourt())
	out.append_array(_tidewell())
	out.append_array(_ashgrove())
	out.append_array(_morvaine())
	out.append_array(_brannoch())
	out.append_array(_sahrim())
	out.append_array(_kjellvar())
	out.append_array(_vyrel())
	return out


static func _valcourt() -> Array:
	var f := "valcourt"
	var g := "House Valcourt"
	var duke := QD.lord("Merewater")
	return [
		_h(f, "VA", 1, "The Duke's Test", g, duke, 10, "serving house valcourt", "A thief stole a deed from my castle and fled to Reedholm. Bring it back. Kill no one.",
			[QD.fetch(QD.camp("Reedholm"), "Stillmere Land Deed", "Recover the stolen deed in the Reedholm reed-maze."),
			QD.talk(duke, "the deed", "Cleanly done. Kneel, and swear to House Valcourt.", "Return the deed to the Duke.")], QD.reward(300)),
		_h(f, "VA", 2, "The Precedent of 97", g, duke, 12, "the precedent of 97", "A regency was granted to a royal uncle once, in 97. Copy that record from the royal library.",
			[QD.fetch(QD.dun("Kingsreach", 5), "Record of 97 CA", "Get into the restricted stacks and copy the record before a Tidewell agent burns it."),
			QD.talk(duke, "the record", "This wins the case. Well done.", "Bring the record to the Duke.")], QD.reward(400)),
		_h(f, "VA", 3, "A Witness in the Fog", g, duke, 14, "the hidden witness", "A clerk who witnessed the King's first will hides in Stillwater. Assassins hunt him.",
			[QD.fight(QD.town("Stillwater"), [QD.f("cutthroat", 3, "")], "Hold off the night attack in the fog."),
			QD.talk(duke, "the witness is safe", "Safe in Merewater. Our case grows.", "Report to the Duke.")], QD.reward(400)),
		_h(f, "VA", 4, "The Heron's Claim", g, duke, 16, "the three seals", "The law needs three lesser lords to endorse a guardian. Win their seals.",
			[QD.talk(QD.lord("Reedholm"), "your seal for valcourt", "My son's debts paid? Then my seal is Valcourt's.", "Win Baroness Marrow's seal."),
			QD.talk(QD.lord("Harrowford"), "your seal for valcourt", "You returned my stallion. My seal, gladly.", "Win Baron Fenn's seal."),
			QD.talk(QD.lord("Elmwick"), "your seal for valcourt", "The border suit in my favour? Done. My seal.", "Win Baron Larkin's seal."),
			QD.talk(duke, "the three seals", "Three seals. Rise, Banneret of Valcourt.", "Bring the seals to the Duke.")],
			QD.reward(600, {"named": [QD.named("Valcourt Blue-Steel Cuirass", W + "steel_chestplate.tres", [["resist_magic", 6]])]})),
		_h(f, "VA", 5, "The Brannoch Match", g, duke, 20, "the brannoch match", "Brannoch's vote is sealed by Aveline's marriage. Guard the wedding party on the road.",
			[QD.fight(QD.wild("Cragmoor", 900.0, 200.0), [QD.f("bandit", 3), QD.f("bandit_brute", 1, "Ashgrove's Hireling")], "Guard the wedding party from bandits."),
			QD.talk(duke, "the wedding party", "Brannoch's vote is ours.", "Report to the Duke.")], QD.reward(500)),
		_h(f, "VA", 6, "Ink and Poison", g, duke, 24, "the forged will", "A second will names Tidewell. Prove it a forgery.",
			[QD.fetch(QD.dun("Saltmere", 2), "Forger's Plates", "Find the forger's workshop in Saltmere."),
			QD.talk(duke, "the forger", "A forgery, proven. Tidewell is shamed.", "Bring the plates to the Duke.")], QD.reward(700)),
		_h(f, "VA", 7, "The Council of Ten", g, duke, 28, "the council of ten", "Three days of council at Castle Dawnhold. Argue, win votes, guard my life.",
			[QD.talk(QD.cast("Lord Chancellor Edric Haverly", "Kingsreach"), "the precedent of 97", "A fair precedent. The council will weigh it.", "Argue the precedent before the council."),
			QD.talk(QD.lord("Kingsreach"), "valcourt's claim", "My nephew-by-marriage would rule well. You have my nod.", "Win the King's nod."),
			QD.fight(QD.town("Kingsreach"), [QD.f("cutthroat", 2), QD.f("cutthroat", 1, "Adrien's Assassin")], "Stop the assassin in the council chamber."),
			QD.talk(duke, "adrien's letter", "My son... plotted a marriage behind my back. Take the Heron Seal; you are my Hand.", "Show the Duke the assassin's letter.")],
			QD.reward(1500, {"named": [QD.named("The Heron Seal", J + "gold_ring_insight.tres", [["fortify_speech", 15], ["fortify_lockpicking", 10]])], "home": "Merewater"})),
		_h(f, "VA", 8, "The Lord Regent", g, duke, 32, "the investiture", "I am named Lord Regent tonight. Stand with me.",
			[QD.choice(duke, "About Elowen's marriage...", [QD.opt("back him fully", "Then she weds Adrien. It is decided.", "full"), QD.opt("demand her freedom", "...You are right. I will sign it.", "guarantee"), QD.opt("expose him", "You would... Guards!", "exposed")]),
			QD.fight(QD.town("Merewater"), [QD.f("vampire", 2), QD.f("vampire", 1, "Velvet Court Envoy")], "Defend the investiture feast from the Velvet Court.")],
			QD.reward(2500, {"title": "Hand of the Regent"})),
	]


static func _tidewell() -> Array:
	var f := "tidewell"
	var g := "House Tidewell"
	var isra := QD.lord("Saltmere")
	return [
		_h(f, "TW", 1, "The Debt Collector", g, isra, 12, "serving house tidewell", "Collect three overdue debts for me, and you may swear to the tide.",
			[QD.fight(QD.wild("Harrowford", 150.0, 0.0), [QD.f("caravan_guard", 1, "Sir Brannan the Debtor")], "Collect from the drunk knight in Harrowford."),
			QD.talk(QD.lord("Gullhaven"), "a tidewell debt", "My cargo, then. Take it.", "Collect from the ruined merchant in Gullhaven."),
			QD.talk(isra, "the debts", "Collected. Swear to the tide.", "Report to the Duchess.")], QD.reward(300)),
		_h(f, "TW", 2, "Cargo of Secrets", g, isra, 14, "the cargo", "Guard a cog to Merewater. Thieves want one crate.",
			[QD.fight(QD.wild("Merewater", 400.0, 270.0), [QD.f("cutthroat", 3, "Guild Boarders")], "Fight off the boarders."),
			QD.talk(isra, "the crate", "Blackmail on half the council. You didn't read it, of course.", "Report to the Duchess.")], QD.reward(400)),
		_h(f, "TW", 3, "Letter of Marque", g, isra, 16, "the gannet", "Capture the pirate sloop Gannet off the Teeth.",
			[QD.fight(QD.wild("Saltmere", 300.0, 200.0), [QD.f("raider", 3), QD.f("raider_marauder", 1, "Captain of the Gannet")], "Board the Gannet."),
			QD.talk(isra, "the prize", "Prize money for the house. Excellent.", "Report to the Duchess.")], QD.reward(600)),
		_h(f, "TW", 4, "The Royal Loan", g, isra, 18, "the royal loan", "Make my cousin Benedek sign the Crown's new loan. Find leverage.",
			[QD.fetch(QD.dun("Kingsreach", 6), "Benedek's IOUs", "Steal Benedek's gambling debts from a Kingsreach counting house."),
			QD.talk(QD.cast("Lord Treasurer Benedek Tidewell", "Saltmere"), "your debts", "...You win. I'll sign.", "Confront the Lord Treasurer."),
			QD.talk(isra, "the signed loan", "Signed. Rise, Banneret of Tidewell.", "Bring the loan to the Duchess.")],
			QD.reward(800, {"named": [QD.named("Tidewell Sea-Green Mail", A + "silverweave_cuirass.tres", [["resist_frost", 15]])]})),
		_h(f, "TW", 5, "Cornering the Grain", g, isra, 22, "the plains harvest", "Buy up the Plains harvest before winter.",
			[QD.choice(QD.lord("Wheatley"), "The reeves beg for seed grain.", [QD.opt("buy it all", "...Then we'll go hungry this spring.", "all"), QD.opt("leave them seed", "Bless you. We won't forget.", "seed")]),
			QD.talk(isra, "the harvest", "The bread price is ours.", "Report to the Duchess.")], QD.reward(900)),
		_h(f, "TW", 6, "Lanterns on the Water", g, isra, 26, "the duchess's secret", "You followed me to the sea cave. Then you know: the Drowned King will take my son.",
			[QD.visit(QD.wild("Saltmere", 350.0, 120.0), "Follow the Duchess to the sea cave at the new moon.", 30.0),
			QD.talk(isra, "the drowned contract", "Three months. Help me, and I'll owe you everything.", "Speak with the Duchess.")], QD.reward(500)),
		_h(f, "TW", 7, "The Drowned Contract", g, isra, 30, "breaking the contract", "Dive into the Drowned Kingdom and break the contract.",
			[QD.realm("R11", "Find the Tidewell contract in the Drowned King's Treasury."),
			QD.choice(isra, "What became of the contract?", [QD.opt("i broke it", "Tobiah is free. The fortune halves. Worth it.", "broken"), QD.opt("i renegotiated it", "A relic instead of my son. Clever.", "renegotiated")])],
			QD.reward(2000, {"named": [QD.named("The Drowned Compass", J + "gemmed_amulet_wind.tres", [["night_eye", 1], ["fortify_lockpicking", 15]])], "home": "Saltmere"})),
		_h(f, "TW", 8, "The Golden Regency", g, isra, 34, "the golden regency", "I call in the Crown's debts. They will riot. Defend the Keep.",
			[QD.fight(QD.town("Saltmere"), [QD.f("bandit_brute", 3), QD.f("deserter_captain", 1, "Indebted Lord's Captain")], "Defend Tidewell Keep."),
			QD.talk(isra, "the vote", "Regent Isra Tidewell. It has a ring to it.", "Escort the Duchess to the vote.")], QD.reward(3000, {"title": "Hand of the Golden Regency"})),
	]


static func _ashgrove() -> Array:
	var f := "ashgrove"
	var g := "House Ashgrove"
	var earl := QD.lord("Thornhaven")
	var maren := QD.cast("Lady Maren Ashgrove", "Thornhaven")
	return [
		_h(f, "AG", 1, "The Ranger's Trial", g, earl, 10, "serving house ashgrove", "Three days in the deep forest, a bow and a knife. Bring a royal stag's antlers.",
			[QD.wait(72.0, "Survive three days in the deep Forest."),
			QD.fight(QD.wild("Thornhaven", 700.0, 100.0), [QD.f("frost_bear", 1, "Royal Stag")], "Bring down a royal stag."),
			QD.talk(earl, "the antlers", "You survived the wood. Swear under the Greenspire.", "Bring the antlers to the Earl.")], QD.reward(300)),
		_h(f, "AG", 2, "Clearing the Name", g, earl, 13, "the royal investigator", "A royal investigator judges us. A lying witness was paid by Brannoch.",
			[QD.fight(QD.wild("Briarwatch", 300.0, 100.0), [QD.f("cutthroat", 1, "The Lying Witness")], "Hunt down the lying witness."),
			QD.talk(earl, "the hearing", "The investigator clears us. Thank you.", "Speak at the hearing.")], QD.reward(400)),
		_h(f, "AG", 3, "The Woodborn Pact", g, earl, 15, "the woodborn pact", "Carry my acorn to the hidden Elder Grove.",
			[QD.visit(QD.wild("Fernhollow", 600.0, 300.0), "Plant the acorn in the hidden Elder Grove.", 30.0),
			QD.talk(QD.lord("Fernhollow"), "the pact", "Renewed for fifty years. Our archers fight for Ashgrove.", "Tell Elder Hesper.")], QD.reward(400)),
		_h(f, "AG", 4, "Full Moon, Full House", g, earl, 18, "the inquisitor", "A Hunters' Lodge inquisitor stays here during the full moon. Keep Garrick's secret.",
			[QD.visit(QD.wild("Thornhaven", 380.0, 220.0), "Lock Ser Garrick in the old hunting lodge.", 30.0),
			QD.visit(QD.wild("Thornhaven", 600.0, 0.0), "Lead the inquisitor on a false trail.", 40.0),
			QD.talk(earl, "the inquisitor is gone", "He left with nothing. Rise, Banneret.", "Report to the Earl.")],
			QD.reward(600, {"named": [QD.named("Ashgrove Leaf-Mail", A + "leather_cuirass.tres", [["fortify_sneak", 10]])]})),
		_h(f, "AG", 5, "The Elder Line", g, maren, 22, "the elder line", "Find Princess Aelis's tomb. Tell no one, not even my husband.",
			[QD.fetch(QD.dun("Pinewatch"), "Aelis's Marriage Record", "Find the record in the border barrow."),
			QD.talk(maren, "the record", "The elder line. Ashgrove's crown. Our secret.", "Bring it to Lady Maren.")], QD.reward(600)),
		_h(f, "AG", 6, "Border Fires", g, earl, 25, "the border war", "Brannoch soldiers mass at Pinewatch.",
			[QD.choice(QD.lord("Pinewatch"), "Meet the Brannoch commander under truce.", [QD.opt("show the paymaster's proof", "...Brannoch paid them? Stand down, all of you.", "peace"), QD.opt("strike first", "Then it's war.", "war")]),
			QD.talk(earl, "the border", "Settled, one way or another.", "Report to the Earl.")], QD.reward(700)),
		_h(f, "AG", 7, "The Wild Hunt", g, earl, 30, "the wild hunt", "Win Varrow's blessing in the Hunting Grounds, as the first Ashgrove did.",
			[QD.realm("R6", "Survive the Wild Hunt and take the Green Hunter's crown."),
			QD.talk(earl, "the antler crown", "Varrow's blessing. You are my Hand. Take the Greenspire Bow.", "Return to the Earl.")],
			QD.reward(2000, {"named": [QD.named("The Greenspire Bow", R + "ebon_bow.tres", [["paralyze", 0, 3]])], "home": "Thornhaven"})),
		_h(f, "AG", 8, "The Green Regency", g, earl, 34, "the green regency", "At the council Maren reveals the elder line. Choose.",
			[QD.choice(earl, "Back whom?", [QD.opt("rowan as guardian", "Elowen will grow up in the green. Good.", "guardian"), QD.opt("maren's claim", "Then it's war. Hold the bridges!", "crown")]),
			QD.fight(QD.town("Thornhaven"), [QD.f("deserter", 3), QD.f("deserter_captain", 1, "Brannoch Raid Captain")], "Hold the tree-bridges.")], QD.reward(3000, {"title": "Hand of the Green Regency"})),
	]


static func _morvaine() -> Array:
	var f := "morvaine"
	var g := "House Morvaine"
	var odile := QD.cast("Lady Odile Morvaine", "Blackfen")
	return [
		_h(f, "MO", 1, "The Swan's Errand", g, odile, 17, "serving house morvaine", "Carry this black casket to a knight in Gravenhold. By night. Don't open it.",
			[QD.talk(QD.lord("Gravenhold"), "the black casket", "...Morvaine sends gifts? Tell her I received it.", "Deliver the casket to Gravenhold.", {"carry": "Black Casket"}),
			QD.talk(odile, "the casket is delivered", "Unopened? Then swear, at midnight, in the chapel.", "Return to Lady Odile.")], QD.reward(400)),
		_h(f, "MO", 2, "The Stolen Cousin", g, odile, 19, "the stolen cousin", "My cousin's body vanished before his funeral. A necromancer sells noble corpses.",
			[QD.fight(QD.dun("Blackfen", 2), [QD.f("cave_dweller", 2), QD.f("ashen_priest", 1, "Corpse-Seller Morg")], "Find the necromancer in the undercity."),
			QD.talk(odile, "my cousin", "Home before the bells. Thank you.", "Return to Odile.")], QD.reward(400)),
		_h(f, "MO", 3, "Bog Iron", g, odile, 21, "the iron strike", "The Marshfolk diggers stopped work. The overseer beats them.",
			[QD.choice(QD.lord("Murkwater"), "Settle the strike.", [QD.opt("raise their pay", "Fair pay and a fair overseer? We dig again.", "fair"), QD.opt("break the strike", "...We dig. For now.", "broken")]),
			QD.talk(odile, "the strike", "The iron flows. Good.", "Report to Odile.")], QD.reward(500)),
		_h(f, "MO", 4, "The Daughter's Plan", g, odile, 23, "my mother's ledger", "My mother is a Velvet Court elder. Steal her blood-ledger by day.",
			[QD.fetch(QD.dun("Blackfen", 3), "The Blood-Ledger", "Steal Lady Mireille's blood-ledger from the undercroft."),
			QD.talk(odile, "the blood-ledger", "Every noble the Court owns. Rise, Banneret.", "Bring the ledger to Odile.")],
			QD.reward(700, {"named": [QD.named("Morvaine Raven-Black Armour", A + "ebonweave_cuirass.tres", [["fortify_sneak", 10]])]})),
		_h(f, "MO", 5, "The Plague Cure", g, odile, 26, "the plague cure", "Our plague was a failed cure for vampirism. Brew it properly.",
			[QD.collect("res://data/ingredients/nightshade.tres", 2, "Gather two nightshade."),
			QD.collect("res://data/ingredients/bloodmoss.tres", 2, "Gather two bloodmoss."),
			QD.talk(odile, "the reagents", "It works. Slowly, but it works.", "Bring the reagents to Odile.")], QD.reward(700)),
		_h(f, "MO", 6, "The Poisoner's Shadow", g, odile, 28, "the poisoner", "The Whisper closes in on our steward. Bury it.",
			[QD.choice(QD.cast("Royal Taster Pell", "Kingsreach", "inn"), "Deal with the steward's trail.", [QD.opt("send him into exile", "Gone by morning. No one will find him.", "exile"), QD.opt("let him confess", "Then it's out. Odile will weather it.", "confess")]),
			QD.talk(odile, "the steward", "Handled. Good.", "Report to Odile.")], QD.reward(800)),
		_h(f, "MO", 7, "Dawn in the Gloaming", g, odile, 32, "the heart-stone", "The Court's hold is anchored in the Gloaming. Shatter it.",
			[QD.realm("R5", "Shatter the heart-stone at the Tomb of Vaelith in the Gloaming."),
			QD.talk(odile, "the heart-stone", "Father is free! You are my Hand. Take the Veil.", "Return to Odile.")],
			QD.reward(2000, {"named": [QD.named("The Mourning Veil", A + "shadowscale_cuirass.tres", [["fortify_sneak", 25], ["muffle", 1]])], "home": "Blackfen"})),
		_h(f, "MO", 8, "The Shadow Regency", g, odile, 36, "the shadow regency", "I go before the council with the ledger and the cure. My mother will strike.",
			[QD.fight(QD.town("Kingsreach"), [QD.f("vampire", 3), QD.f("vampire", 1, "Lady Mireille Morvaine")], "Defend the council chamber from Mireille."),
			QD.talk(odile, "the council", "The Shadow Regency. A realm that knows its monsters.", "Speak with Odile.")], QD.reward(3000, {"title": "Hand of the Shadow Regency"})),
	]


static func _brannoch() -> Array:
	var f := "brannoch"
	var g := "House Brannoch"
	var duke := QD.lord("Cragmoor")
	return [
		_h(f, "BR", 1, "Blood and Heather", g, duke, 27, "serving house brannoch", "Win three duels in my circle: sword, axe, fists.",
			[QD.fight(QD.wild("Cragmoor", 80.0, 0.0), [QD.f("caravan_guard", 1, "Champion of the Sword")], "Win the sword duel."),
			QD.fight(QD.wild("Cragmoor", 80.0, 0.0), [QD.f("raider_marauder", 1, "Champion of the Axe")], "Win the axe duel."),
			QD.fight(QD.wild("Cragmoor", 80.0, 0.0), [QD.f("bandit_brute", 1, "Champion of the Fist")], "Win the fist fight."),
			QD.talk(duke, "the three duels", "Three for three! Swear on my claymore.", "Report to the Duke.")], QD.reward(400)),
		_h(f, "BR", 2, "Muster the Clans", g, duke, 29, "muster the clans", "Bring the levies of Dunmore, Reay and Aird.",
			[QD.talk(QD.lord("Heathwick"), "brannoch's muster", "Reay rides with Brannoch.", "Win Clan Reay at Heathwick."),
			QD.fight(QD.dun("Stonebrook"), [QD.f("barrow_wight", 3, "")], "Clear the barrow troubling Clan Aird."),
			QD.talk(duke, "the levies", "The clans march!", "Report to the Duke.")], QD.reward(500)),
		_h(f, "BR", 3, "Iron for the Host", g, duke, 31, "the ore convoy", "Guard the ore convoy from Dustgate.",
			[QD.fight(QD.wild("Dustgate", 500.0, 270.0), [QD.f("bandit", 2), QD.f("cave_troll", 1, "Rock Troll")], "Guard the convoy through the canyons."),
			QD.talk(duke, "the convoy", "Iron for the forges. Good.", "Report to the Duke.")], QD.reward(600)),
		_h(f, "BR", 4, "The Border Lie", g, duke, 33, "the border raiders", "Punish Ashgrove for the border raids.",
			[QD.fight(QD.camp("Pinewatch", 1), [QD.f("deserter", 2), QD.f("deserter_captain", 1, "Raider Who Talks")], "Capture a border raider."),
			QD.choice(duke, "The raider names your quartermaster. On your order.", [QD.opt("confront the duke", "...Aye. I did it. You've a spine. Keep quiet, and rise.", "confronted"), QD.opt("bury the truth", "Good. Rise, Banneret.", "buried")])],
			QD.reward(800, {"named": [QD.named("Brannoch Red-Plate", W + "steel_chestplate.tres", [["fortify_health", 20]])]})),
		_h(f, "BR", 5, "The Hostage Heir", g, duke, 36, "my son callum", "Woodborn rangers took my son as payment for the raids.",
			[QD.fight(QD.camp("Fernhollow"), [QD.f("hunter", 3, "Woodborn Ranger")], "Rescue Callum from the tree-fort."),
			QD.talk(duke, "callum is free", "My boy. ...He says the raids shame us. He may be right.", "Bring Callum home.")], QD.reward(800)),
		_h(f, "BR", 6, "Engines of War", g, duke, 38, "the siege engines", "I need siege engines. Ironblood engineers and imperial plans.",
			[QD.fetch(QD.dun("Rustfield", 3), "Imperial Siege Plans", "Steal the siege plans from a ruined fort."),
			QD.fight(QD.town("Cragmoor"), [QD.f("cutthroat", 1, "Valcourt Saboteur")], "Protect the workshop from a saboteur."),
			QD.talk(duke, "the engines", "Trebuchets! Now we march.", "Report to the Duke.")], QD.reward(900)),
		_h(f, "BR", 7, "The Field of Stones", g, duke, 42, "the field of stones", "A coalition blocks the road south. Lead a wing.",
			[QD.fight(QD.wild("Kingsreach", 1500.0, 0.0), [QD.f("caravan_guard", 4), QD.f("deserter_captain", 1, "Coalition Champion")], "Win the battle at the Field of Stones."),
			QD.talk(duke, "the field is won", "You are my Hand. The Red Stag Claymore is yours.", "Report to the Duke.")],
			QD.reward(2500, {"named": [QD.named("Red Stag Claymore", W + "dragonbone_greatsword.tres", [["fortify_attack", 12], ["fire_damage", 10]])], "home": "Cragmoor"})),
		_h(f, "BR", 8, "Lord Protector", g, duke, 46, "lord protector", "We camp outside Kingsreach. How does it end?",
			[QD.choice(duke, "Decide the end.", [QD.opt("storm the castle", "Through the Old Keep! For Brannoch!", "storm"), QD.opt("negotiate the surrender", "No blood. Good.", "terms"), QD.opt("make callum protector", "...My son, then. Perhaps that's best.", "callum")]),
			QD.fight(QD.town("Kingsreach"), [QD.f("caravan_guard", 3, "Sunguard"), QD.f("deserter_captain", 1, "Sunguard Captain")], "Take Castle Dawnhold.")], QD.reward(3500, {"title": "Hand of the Protectorate"})),
	]


static func _sahrim() -> Array:
	var f := "sahrim"
	var g := "House Sahrim"
	var leyla := QD.cast("Princess Leyla al-Sahrim", "Sunhold")
	return [
		_h(f, "SA", 1, "The Desert Oath", g, leyla, 20, "serving house sahrim", "Walk the Glass Flats to our ancestors' shrine with only the water you carry.",
			[QD.visit(QD.wild("Sunhold", 1200.0, 300.0), "Reach the shrine of the Sahrim ancestors.", 30.0),
			QD.talk(leyla, "the oath", "You swore at sunrise. Welcome, sworn of the Sun.", "Return to Leyla.")], QD.reward(300)),
		_h(f, "SA", 2, "Gifts for a Princess", g, leyla, 22, "gifts for elowen", "Three gifts worthy of Elowen.",
			[QD.collect("res://data/treasure/jeweled_circlet.tres", 1, "Find a jeweled circlet for the princess."),
			QD.talk(QD.cast("Princess Elowen Aurelane", "Kingsreach"), "gifts from sahrim", "For me? From Sahrim? ...Tell them thank you.", "Deliver the gifts to Elowen in Kingsreach."),
			QD.talk(leyla, "elowen's thanks", "She liked them? Good.", "Report to Leyla.")], QD.reward(400)),
		_h(f, "SA", 3, "The Caravan Wars", g, leyla, 24, "the caravan wars", "Tidewell pays raiders to hit our caravans.",
			[QD.fight(QD.camp("Dune's Rest"), [QD.f("raider", 3), QD.f("raider_marauder", 1, "Tidewell's Raider")], "Burn the Tidewell-paid raiders' post."),
			QD.talk(leyla, "the raiders", "The routes are ours again.", "Report to Leyla.")], QD.reward(500)),
		_h(f, "SA", 4, "The Sun Disc", g, leyla, 26, "the sun disc", "The Sun Disc proves our descent. It lies in a sand-swallowed temple.",
			[QD.fetch(QD.dun("Sunhold", 3), "The Sun Disc", "Dig into the temple and take the Sun Disc from its golems."),
			QD.talk(leyla, "the sun disc", "Proof of the Sun! Rise, Banneret.", "Bring the Disc to Leyla.")],
			QD.reward(700, {"named": [QD.named("Sahrim Gilded Scale", W + "silver_chestplate.tres", [["resist_fire", 15]])]})),
		_h(f, "SA", 5, "The Prince's Journey", g, leyla, 29, "rashid's journey", "Escort Prince Rashid to Kingsreach.",
			[QD.fight(QD.wild("Kingsreach", 1200.0, 200.0), [QD.f("cutthroat", 2, "Brannoch Hireling")], "Fight off the first ambush."),
			QD.fight(QD.wild("Kingsreach", 500.0, 200.0), [QD.f("vampire", 2, "Velvet Thrall")], "Fight off the second ambush."),
			QD.talk(QD.cast("Princess Elowen Aurelane", "Kingsreach"), "prince rashid", "He's... nice. Shy. I like him, I think.", "Bring Rashid to meet Elowen.")], QD.reward(800)),
		_h(f, "SA", 6, "Whispers in Kingsreach", g, leyla, 32, "the pamphlets", "Pamphlets say we keep slaves. Find the press.",
			[QD.fight(QD.dun("Kingsreach", 7), [QD.f("bandit", 2, "Pamphleteer")], "Find the printing press."),
			QD.talk(leyla, "the press", "Smashed, and its patron named. Good.", "Report to Leyla.")], QD.reward(800)),
		_h(f, "SA", 7, "The Buried Codex", g, leyla, 36, "the buried codex", "The Marriage Codex lies in Kar-Aurel. It makes our match a reunion of the empire.",
			[QD.realm("R3", "Bring back the Imperial Marriage Codex from the Sun Vault of Kar-Aurel."),
			QD.talk(leyla, "the codex", "Empire and Sun, one blood. You are my Hand. Take the Disc.", "Return to Leyla.")],
			QD.reward(2500, {"named": [QD.named("Sun Disc of Sahr", W + "starforged_shield.tres", [["reflect", 15]])], "home": "Sunhold"})),
		_h(f, "SA", 8, "The Sun Throne", g, leyla, 40, "the betrothal", "The betrothal ceremony. Assassins will come.",
			[QD.fight(QD.town("Kingsreach"), [QD.f("cutthroat", 3), QD.f("cutthroat", 1, "Leyla's Assassin")], "Save Prince Rashid."),
			QD.choice(leyla, "The assassin was hers.", [QD.opt("expose her", "...You have ruined me. Rashid will wed.", "exposed"), QD.opt("join her", "Then I am Regent. You chose well.", "joined")])], QD.reward(3500, {"title": "Hand of the Sun Throne"})),
	]


static func _kjellvar() -> Array:
	var f := "kjellvar"
	var g := "House Kjellvar"
	var jarl := QD.lord("Wintergate")
	return [
		_h(f, "KJ", 1, "The Holmgang", g, jarl, 45, "serving house kjellvar", "A thane says outsiders are unworthy. Meet him on the island ring.",
			[QD.fight(QD.wild("Wintergate", 200.0, 270.0), [QD.f("frost_raider", 1, "Thane Brynjolf")], "Win the holmgang."),
			QD.talk(jarl, "the holmgang", "He yields! Drink with us, sworn of the Bear.", "Report to the Jarl.")], QD.reward(500)),
		_h(f, "KJ", 2, "Furs for the South", g, jarl, 47, "the fur caravan", "Guard the sled caravan from Northwatch to Frosthelm.",
			[QD.fight(QD.wild("Northwatch", 800.0, 200.0), [QD.f("cave_troll", 2), QD.f("frost_raider", 2)], "Guard the sleds through the blizzard."),
			QD.talk(jarl, "the furs", "The furs reached the south. Good.", "Report to the Jarl.")], QD.reward(600)),
		_h(f, "KJ", 3, "The Skald's Insult", g, jarl, 48, "the mocking song", "A Kingsreach bard mocks me. Restore my honour.",
			[QD.choice(QD.cast("Bard Lucan Fey", "Kingsreach", "inn"), "Answer the bard.", [QD.opt("win the flyting", "...A fair hit. I'll sing a better song.", "flyting"), QD.opt("challenge his patron", "No need for blood! I'll stop!", "duel")]),
			QD.talk(jarl, "the bard", "My honour stands. Good.", "Report to the Jarl.")], QD.reward(600)),
		_h(f, "KJ", 4, "The Oathstone", g, jarl, 50, "the oathstone", "Bring the oathstone from the first Jarl's barrow.",
			[QD.fetch(QD.dun("Wintergate", 4), "The Oathstone", "Clear the first Jarl's barrow and take the oathstone."),
			QD.talk(jarl, "the oathstone", "The oath, in my hall. Rise, Banneret.", "Bring the stone to the Jarl.")],
			QD.reward(900, {"named": [QD.named("Kjellvar Bear-Fur Plate", W + "steel_chestplate.tres", [["resist_frost", 25]])]})),
		_h(f, "KJ", 5, "Astrid's Dreams", g, jarl, 53, "astrid's dreams", "My daughter sleepwalks to the shore every night.",
			[QD.visit(QD.wild("Wintergate", 500.0, 0.0), "Follow Astrid to the frozen shore.", 30.0),
			QD.talk(jarl, "the winter queen's call", "She wants an heir of the first blood. My Astrid.", "Tell the Jarl.")], QD.reward(800)),
		_h(f, "KJ", 6, "By the Crown's Fire", g, jarl, 55, "guarding elowen", "Take twelve huscarls south and guard the princess.",
			[QD.fight(QD.town("Kingsreach"), [QD.f("vampire", 3, "Velvet Thrall")], "Hold the princess's tower."),
			QD.talk(QD.cast("Princess Elowen Aurelane", "Kingsreach"), "the north", "Tell me about the north. Is it really always winter?", "Speak with Elowen.")], QD.reward(900)),
		_h(f, "KJ", 7, "The Queen Under Ice", g, jarl, 60, "astrid is gone", "Astrid crossed the sea ice. Bring her home.",
			[QD.realm("R7", "Break the ice-coffin around Astrid in the Hall of the Bear."),
			QD.talk(jarl, "astrid is home", "My daughter! You are my Hand. The Bearclaw Gauntlets are yours.", "Bring Astrid home.")],
			QD.reward(3000, {"named": [QD.named("Bearclaw Gauntlets", A + "dragonscale_gauntlets.tres", [["fortify_strength", 6], ["resist_frost", 20]])], "home": "Wintergate"})),
		_h(f, "KJ", 8, "The Bear by the Fire", g, jarl, 64, "the bear by the fire", "I sail to Kingsreach with the oathstone. A Kjellvar Regent, or the north leaves.",
			[QD.fight(QD.town("Kingsreach"), [QD.f("caravan_guard", 3), QD.f("deserter_captain", 1, "Brannoch Ambusher")], "Defend the Jarl at the council."),
			QD.choice(jarl, "Advise the Jarl.", [QD.opt("take the regency", "The Northern Regency. So be it.", "regency"), QD.opt("go free", "Then the Northmarch is free, and I its queen.", "free")])], QD.reward(4000, {"title": "Hand of the White Bear"})),
	]


static func _vyrel() -> Array:
	var f := "vyrel"
	var g := "House Vyrel"
	var archon := QD.lord("Cinderhold")
	return [
		_h(f, "VY", 1, "Trial by Fire", g, archon, 55, "serving house vyrel", "Walk the Ember Path. Only those who reach its end serve a Vyrel.",
			[QD.clear(QD.dun("Cinderhold", 2), "Walk the Ember Path to its end."),
			QD.talk(archon, "the ember path", "You walked it. Swear at the summit forge.", "Report to the Archon.")], QD.reward(600)),
		_h(f, "VY", 2, "The Debt of 251", g, archon, 56, "the blood-price", "Escort our yearly blood-price to Kjellvar.",
			[QD.talk(QD.lord("Wintergate"), "vyrel's tribute", "Tribute from the ash-folk. Leave it and go.", "Deliver the tribute to Wintergate.", {"carry": "Vyrel Tribute Chest"}),
			QD.talk(archon, "the tribute", "Paid. For another year.", "Report to the Archon.")], QD.reward(700)),
		_h(f, "VY", 3, "Glass Ambassadors", g, archon, 57, "the obsidian gifts", "Deliver obsidian gifts to three houses.",
			[QD.talk(QD.lord("Merewater"), "a gift from vyrel", "Obsidian? Lovely. My nod, then.", "Deliver a gift to Valcourt."),
			QD.talk(QD.lord("Saltmere"), "a gift from vyrel", "Fine work. Tidewell remembers.", "Deliver a gift to Tidewell."),
			QD.talk(QD.lord("Sunhold"), "a gift from vyrel", "Fire-folk to fire-folk. Gladly.", "Deliver a gift to Sahrim."),
			QD.talk(archon, "the three nods", "Three houses lean our way.", "Report to the Archon.")], QD.reward(800)),
		_h(f, "VY", 4, "The Archon's Bargain", g, archon, 60, "the quiet volcano", "...You followed me. Then you know of the Choir pact. Bring the scroll.",
			[QD.fetch(QD.dun("Cinderhold", 3), "The Choir Pact", "Take the pact scroll from the hidden Choir chapel."),
			QD.talk(archon, "the pact scroll", "Keep my secret until we are strong. Rise, Banneret.", "Bring the scroll to the Archon.")],
			QD.reward(1000, {"named": [QD.named("Vyrel Obsidian Plate", W + "obsidian_chestplate.tres", [["resist_fire", 25]])]})),
		_h(f, "VY", 5, "The Penitent Son", g, archon, 62, "my son caelan", "Find Caelan before my guards do.",
			[QD.fight(QD.dun("Emberwick", 1), [QD.f("ash_cultist", 3), QD.f("ashen_priest", 1, "Lord Caelan Vyrel")], "Corner Caelan in the ash-buried temple."),
			QD.talk(archon, "caelan", "...It is done, then. Thank you.", "Report to the Archon.")], QD.reward(1000)),
		_h(f, "VY", 6, "The Sun-Lens", g, archon, 64, "the sun-lens", "Build a great sun-lens on the Spire.",
			[QD.collect("res://data/ingredients/storm_crystal.tres", 2, "Bring two storm crystals for the lens."),
			QD.collect("res://data/ingredients/fire_salts.tres", 2, "Bring two fire salts for its heart."),
			QD.talk(archon, "the lens", "It burns shadow. Vyrel guards the sun now.", "Bring the parts to the Archon.")], QD.reward(1200)),
		_h(f, "VY", 7, "The Ash Moot", g, archon, 67, "the ash moot", "Win the Ashborn families, then break the Choir pact.",
			[QD.fight(QD.wild("Cinderhold", 100.0, 0.0), [QD.f("ashen_priest", 1, "Rival Fire-Mage Dreveth")], "Win the fire-mage duel at the moot."),
			QD.fight(QD.wild("Cinderhold", 900.0, 40.0), [QD.f("vampire", 2), QD.f("ashen_priest", 1, "Choirmaster's Voice")], "Face the Choir in the caldera."),
			QD.talk(archon, "the pact is broken", "Free of them. You are my Hand. Take the Cinderglass Staff.", "Report to the Archon.")],
			QD.reward(3000, {"named": [QD.named("Cinderglass Staff", W + "obsidian_spear.tres", [["fire_damage", 22]])], "home": "Cinderhold"})),
		_h(f, "VY", 8, "The Ashen Regency", g, archon, 72, "the ashen regency", "Vyrel betrayed the sun once and saved it twice. Kjellvar will refuse.",
			[QD.choice(QD.lord("Wintergate"), "Kjellvar refuses to sit under a Vyrel.", [QD.opt("duel their champion", "...You win. We sit.", "duel"), QD.opt("reconcile the houses", "Old debts... paid. We sit.", "peace")]),
			QD.talk(archon, "the regency", "The Ashen Regency. From ash, glass.", "Report to the Archon.")], QD.reward(4000, {"title": "Hand of the Ashen Regency"})),
	]
