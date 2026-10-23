class_name QuestDefsNight
extends RefCounted
## The vampire clans (V-..) and the werewolf pack (W-GF..). Only the afflicted can start them;
## 01 is the trial that swears you in (and closes the rival clans for good), 00 is the penance
## that lets a cured-and-turned-again member back in. 04 and 07 are the rank gates.

const W := "res://scripts/Resources/Weapons/"
const A := "res://scripts/Resources/Armor/"
const J := "res://scripts/Resources/Jewelry/"
const RANKS := [0, 1, 1, 2, 3, 3, 4, 5]


static func _n(f: String, code: String, n: int, aff: String, name: String, group: String, giver: Dictionary, level: int, hook: String, intro: String, steps: Array, reward: Dictionary) -> Dictionary:
	var id := "%s%02d" % [code, n]
	var extra := QD.fac(f, RANKS[n - 1] if n > 0 else 0, [] if n <= 1 else ["%s%02d" % [code, n - 1]])
	extra["affliction"] = aff
	if n <= 1:
		reward["join"] = f
	if n == 0:
		extra["penance"] = true
	return QD.q(id, name, group, giver, level, hook, intro, steps, reward, extra)


static func list() -> Array:
	var out: Array = []
	out.append_array(_velvet())
	out.append_array(_hollow())
	out.append_array(_choir())
	out.append_array(_pack())
	return out


static func _velvet() -> Array:
	var f := "velvet_court"
	var c := "V-VC"
	var g := "The Velvet Court"
	var m := QD.cast("Lady Mireille Morvaine", "Blackfen")
	return [
		_n(f, c, 0, "vampire", "Penance: The Returning Guest", g, m, 15, "my return", "You were cured, and turned again. Bring me three noble thralls and kneel.",
			[QD.talk(QD.lord("Harrowford"), "a quiet word", "...Yes, mistress. Whatever you ask.", "Make a thrall of the Baron of Harrowford."),
			QD.talk(QD.lord("Reedholm"), "a quiet word", "...I hear the Court.", "Make a thrall of the Baroness of Reedholm."),
			QD.talk(QD.lord("Elmwick"), "a quiet word", "...I am yours.", "Make a thrall of the Baron of Elmwick."),
			QD.talk(m, "my penance", "Kneel. You are ours again.", "Kneel before Mireille.")], QD.reward(0)),
		_n(f, c, 1, "vampire", "The Masked Ball", g, m, 15, "the black swan invitation", "Our masquerade. Feed on the marked guest, and let no one notice.",
			[QD.fight(QD.town("Blackfen"), [QD.f("merchant", 1, "The Marked Guest")], "Feed on the marked guest during the ball."),
			QD.talk(m, "the embrace", "Unseen. You are of the Court now, Neonate.", "Return to Mireille for the Embrace.")], QD.reward(300)),
		_n(f, c, 2, "vampire", "A Thrall in the Magistrate's Chair", g, m, 17, "the magistrate", "Bind a Kingsreach magistrate. Three nights, and never kill him.",
			[QD.wait(72.0, "Feed on the magistrate three nights in a row."),
			QD.talk(m, "the magistrate", "He is ours. Our bounties vanish in Kingsreach.", "Report to Mireille.")], QD.reward(400)),
		_n(f, c, 3, "vampire", "The Hunter's List", g, m, 19, "the order's list", "The Knightly Order keeps a list of us at Gravenhold. Steal it.",
			[QD.fetch(QD.dun("Gravenhold", 1), "The Hunter's List", "Steal the list from the Gravenhold archive."),
			QD.talk(m, "the list", "Our names crossed out. The Kin's added. Delicious.", "Bring the list to Mireille.")], QD.reward(500)),
		_n(f, c, 4, "vampire", "The Nightglass Harvest", g, m, 22, "the nightglass", "Our poison needs a black flower from the Kin's barrows.",
			[QD.fight(QD.dun("Stonebrook", 1), [QD.f("vampire", 2, "Hollow Kin"), QD.f("vampire", 1, "Kin Elder")], "Raid a Hollow Kin feeding ground."),
			QD.collect("res://scripts/Resources/Ingredients/nightshade.tres", 3, "Harvest three nightglass flowers (nightshade)."),
			QD.talk(m, "the black flowers", "Enough for a king. You are Kindred now.", "Bring the flowers to Mireille.")], QD.reward(700, {"spell": "charm_spell"})),
		_n(f, c, 5, "vampire", "The Choir in the Fog", g, m, 25, "the choir singer", "A Choir blood-singer feeds in Merewater's fog.",
			[QD.fight(QD.dun("Merewater", 3), [QD.f("vampire", 1, "Choir Blood-Singer")], "Destroy her in the cisterns."),
			QD.talk(m, "the singer", "One less Choir voice.", "Report to Mireille.")], QD.reward(800)),
		_n(f, c, 6, "vampire", "The Princess's Tutor", g, m, 28, "elowen's tutor", "Put a thrall at Elowen's side as her tutor.",
			[QD.choice(m, "Will you do it?", [QD.opt("place the thrall", "Now we have the princess's ear.", "placed"), QD.opt("refuse", "...Disappointing. The Court remembers.", "refused")])], QD.reward(800)),
		_n(f, c, 7, "vampire", "The Sleeping Prince", g, m, 32, "prince vaelith", "Wake Prince Vaelith in the Gloaming.",
			[QD.realm("R5", "Wake Prince Vaelith at his tomb in the Gloaming."),
			QD.talk(m, "vaelith wakes", "He wakes! You are Sire. Wear the Mask.", "Return to Mireille.")],
			QD.reward(2500, {"named": [QD.named("The Velvet Mask", A + "ebonweave_helmet.tres", [["fortify_speech", 15], ["night_eye", 1]])]})),
		_n(f, c, 8, "vampire", "The Velvet Crown", g, m, 36, "the night of masks", "The Night of Masks. Three councillors in one night.",
			[QD.fight(QD.town("Kingsreach"), [QD.f("caravan_guard", 3, "Sunguard")], "Reach your councillor past the Sunguard."),
			QD.choice(m, "And then?", [QD.opt("give vaelith the council", "The Velvet Regency. Night rules.", "regency"), QD.opt("betray vaelith", "You... traitor!", "betrayed"), QD.opt("strike vaelith down", "Then the Court is yours, Sire.", "master")])], QD.reward(4000, {"title": "Sire of the Velvet Court"})),
	]


static func _hollow() -> Array:
	var f := "hollow_kin"
	var c := "V-HK"
	var g := "The Hollow Kin"
	var m := QD.cast("The Hollow Mother", "Stonebrook")
	return [
		_n(f, c, 0, "vampire", "Penance: The Hunt Returns", g, m, 15, "my return", "Kill a Lodge hunter with your teeth and claws, and lay his blade at my feet.",
			[QD.fight(QD.wild("Stonebrook", 600.0, 120.0), [QD.f("hunter", 1, "Lodge Hunter Breck")], "Kill a Hunters' Lodge hunter."),
			QD.talk(m, "my penance", "Welcome home, child.", "Return to the Hollow Mother.")], QD.reward(0)),
		_n(f, c, 1, "vampire", "The Starving Night", g, m, 15, "the warren", "Starve three days. Then kill a cave bear with your hands.",
			[QD.wait(72.0, "Go three days without feeding."),
			QD.fight(QD.wild("Stonebrook", 500.0, 300.0), [QD.f("frost_bear", 1, "Cave Bear")], "Kill a cave bear bare-handed."),
			QD.talk(m, "the embrace", "Kin. Family. Welcome, Neonate.", "Return to the Warren for the Embrace.")], QD.reward(300)),
		_n(f, c, 2, "vampire", "Bones in the Barrow", g, m, 17, "a new haven", "Clear a barrow so the Kin can move in.",
			[QD.clear(QD.dun("Heathwick", 2), "Clear the barrow of wights and bandits."),
			QD.talk(m, "the barrow", "A new home. Good.", "Report to the Mother.")], QD.reward(400)),
		_n(f, c, 3, "vampire", "Silver in the Glen", g, m, 20, "the captive kin", "Lodge hunters will burn three of our young at dawn.",
			[QD.fight(QD.camp("Heathwick"), [QD.f("hunter", 3), QD.f("hunter", 1, "Lodge Captain")], "Raid the hunters' camp."),
			QD.talk(m, "the young", "They live. Thank you.", "Bring the young home.")], QD.reward(500)),
		_n(f, c, 4, "vampire", "The Red Winter's Debt", g, m, 23, "the red winter", "Kill the Court elder who sold us out in 188.",
			[QD.fight(QD.dun("Stillwater", 3), [QD.f("vampire", 2), QD.f("vampire", 1, "Velvet Elder Ormand")], "Destroy the Velvet haven in Lakeland."),
			QD.talk(m, "the debt", "Paid in blood. You are Kindred.", "Return to the Mother.")], QD.reward(700, {"perk": {"damage_pct": 0.05}})),
		_n(f, c, 5, "vampire", "The Deep Bargain", g, m, 26, "the ironblood bargain", "Offer the Dustgate miners a deal: we guard the deep tunnels.",
			[QD.fight(QD.dun("Dustgate", 2), [QD.f("deep_crawler", 3), QD.f("crawler_queen", 1)], "Clear a crawler nest in the deep tunnels."),
			QD.talk(QD.lord("Dustgate"), "the kin's bargain", "...You guard the deep, we leave out the livestock. Done.", "Make the bargain with Baron Ironjaw.")], QD.reward(700)),
		_n(f, c, 6, "vampire", "The Mother's Hunger", g, m, 29, "the mother's hunger", "Only an elder's blood can feed me now. A Choir elder.",
			[QD.fight(QD.dun("Frosthelm"), [QD.f("vampire", 2), QD.f("ashen_priest", 1, "Choir Elder Vashti")], "Hunt the Choir elder in the Snow Mountain monastery."),
			QD.talk(m, "the elder's blood", "Strong again. Thank you, child.", "Bring the blood to the Mother.")], QD.reward(800)),
		_n(f, c, 7, "vampire", "The Starving Prince", g, m, 34, "prince ghaur", "Wake Prince Ghaur in the Barrowdeep.",
			[QD.realm("R4", "Wake Prince Ghaur in his bone cocoon in the Barrowdeep."),
			QD.talk(m, "ghaur wakes", "Father wakes! You are Sire. Take his Fang.", "Return to the Mother.")],
			QD.reward(2500, {"named": [QD.named("Ghaur's Fang", W + "dragonbone_dagger.tres", [["absorb_health", 10]])]})),
		_n(f, c, 8, "vampire", "The Long Night Hunt", g, m, 38, "the long night hunt", "Ghaur leads us into the Gloaming. And his hunger spills into the villages.",
			[QD.realm("R5", "Take the Gloaming for the Kin."),
			QD.choice(m, "Ghaur hungers for the villages.", [QD.opt("let him feed", "The Kin rule the night openly.", "fed"), QD.opt("put him down", "Then you lead us now.", "leader")])], QD.reward(4000, {"title": "Sire of the Hollow Kin"})),
	]


static func _choir() -> Array:
	var f := "ashen_choir"
	var c := "V-AC"
	var g := "The Ashen Choir"
	var m := QD.cast("Choirmaster Somnir", "Cinderhold")
	return [
		_n(f, c, 0, "vampire", "Penance: Sing Again", g, m, 15, "my return", "Bring the blood of three priests of the Dawn, and sing the penitent's verse.",
			[QD.fight(QD.town("Kingsreach"), [QD.f("pilgrim", 3, "Dawn Priest")], "Take the blood of three Dawn priests."),
			QD.talk(m, "my penance", "Sing again, then. You are welcome.", "Return to Somnir.")], QD.reward(0)),
		_n(f, c, 1, "vampire", "The Audition", g, m, 20, "the blood-candle", "Carry a blood-candle up the Ember Path by night, and sing before me.",
			[QD.visit(QD.wild("Cinderhold", 900.0, 40.0), "Carry the blood-candle to the dead volcano.", 40.0),
			QD.talk(m, "my first verse", "A voice for the Choir. Neonate.", "Sing your first verse before Somnir.")], QD.reward(300)),
		_n(f, c, 2, "vampire", "The Lost Congregation", g, m, 22, "the scattered cult", "The Ash Cult is scattered. Bring three cells under us.",
			[QD.fight(QD.camp("Reedholm", 1), [QD.f("ash_cultist", 2, ""), QD.f("ashen_priest", 1, "Cell-Leader Ost")], "Bring the Reedholm cell in line."),
			QD.fight(QD.camp("Emberwick"), [QD.f("ash_cultist", 2, ""), QD.f("ashen_priest", 1, "Cell-Leader Venn")], "Bring the Emberwick cell in line."),
			QD.talk(m, "the congregation", "Our flock returns.", "Report to Somnir.")], QD.reward(500)),
		_n(f, c, 3, "vampire", "The Sunpriest's Relic", g, m, 24, "the lamp of first light", "Steal the Lamp of First Light from the Temple of the Dawn.",
			[QD.fetch(QD.dun("Kingsreach", 8), "Lamp of First Light", "Steal the lamp; carry it wrapped."),
			QD.talk(m, "the lamp", "Quenched in blood. Lovely.", "Bring the lamp to the Choir Vault.")], QD.reward(600)),
		_n(f, c, 4, "vampire", "The Blood Hymn", g, m, 27, "the blood hymn", "Three verses frozen in the martyrs' tombs.",
			[QD.clear(QD.dun("Frosthelm", 1), "Recover the first verse."),
			QD.clear(QD.dun("Highpass"), "Recover the second verse."),
			QD.talk(m, "the verses", "The Blood-Song is yours. Kindred.", "Bring the verses to Somnir.")], QD.reward(800, {"spell": "vampiric_drain"})),
		_n(f, c, 5, "vampire", "The Monastery of Silence", g, m, 30, "the silent monastery", "Take the monastery of Vey for a haven.",
			[QD.choice(QD.lord("Frosthelm"), "The monks of Vey.", [QD.opt("convert the monks", "...They kneel to the Choir now.", "converted"), QD.opt("drive them out", "They flee down the mountain.", "driven")]),
			QD.talk(m, "the monastery", "A haven in the snow.", "Report to Somnir.")], QD.reward(800)),
		_n(f, c, 6, "vampire", "The Volcano's Song", g, m, 33, "the volcano stirs", "Lead the singers in the caldera through the night.",
			[QD.fight(QD.wild("Cinderhold", 900.0, 40.0), [QD.f("fire_spirit", 3), QD.f("caravan_guard", 1, "Vyrel Captain")], "Hold the rite in the caldera."),
			QD.talk(m, "the mountain sleeps", "Quiet again. The pact holds.", "Report to Somnir.")], QD.reward(900)),
		_n(f, c, 7, "vampire", "Somnir's Requiem", g, m, 38, "the shard", "The Shard of the First Eclipse lies in the Gloaming. Bring it.",
			[QD.realm("R5", "Take the Shard of the First Eclipse from the Gloaming."),
			QD.talk(m, "the shard", "The Requiem can begin. You are Sire. The Censer.", "Return to Somnir.")],
			QD.reward(2500, {"named": [QD.named("The Requiem Censer", J + "gemmed_amulet_insight.tres", [["fortify_magic", 15], ["regenerate_magicka", 40]])]})),
		_n(f, c, 8, "vampire", "The Long Dusk", g, m, 60, "the long dusk", "Through the Umbral Eclipse, we anchor the dusk.",
			[QD.realm("R10", "Anchor the dusk at the Heart of the Black Sun."),
			QD.choice(m, "Where does the dusk fall?", [QD.opt("the north only", "Dusk over the Ashlands and the North.", "north"), QD.opt("the whole realm", "Night forever. As it was meant to be.", "realm"), QD.opt("betray somnir", "You... take my place?", "choirmaster")])], QD.reward(5000, {"title": "Sire of the Ashen Choir"})),
	]


static func _pack() -> Array:
	var f := "greyfang"
	var c := "W-GF"
	var g := "The Greyfang Pack"
	var m := QD.cast("Alpha Brenna Greyfang", "Fernhollow")
	return [
		_n(f, c, 0, "werewolf", "Penance: The Prodigal Howl", g, m, 12, "my return", "Fight Fenris in beast form until one of you yields.",
			[QD.fight(QD.wild("Fernhollow", 700.0, 200.0), [QD.f("werewolf", 1, "Fenris Greyfang")], "Fight Fenris at the meeting stone."),
			QD.talk(m, "my penance", "Welcome back to the pack.", "Return to Brenna.")], QD.reward(0)),
		_n(f, c, 1, "werewolf", "Run with the Pack", g, m, 12, "the howl", "Run with us tonight. Bring down a stag. Kill no human.",
			[QD.fight(QD.wild("Fernhollow", 600.0, 100.0), [QD.f("frost_bear", 1, "Great Stag")], "Bring down a stag with the pack."),
			QD.talk(m, "the howling", "No human blood. Good. Howl with us, Pup.", "Return to the moonlit pool.")], QD.reward(300)),
		_n(f, c, 2, "werewolf", "The Silver Traps", g, m, 14, "the silver traps", "A young wolf is caught in silver. Free her before dawn.",
			[QD.fight(QD.wild("Fernhollow", 400.0, 60.0), [QD.f("trapper", 3, "Silver-Trapper")], "Free the wolf and deal with the trappers."),
			QD.talk(m, "the trap line", "She's free. Good hunting.", "Report to Brenna.")], QD.reward(400)),
		_n(f, c, 3, "werewolf", "Totem of the Hunt", g, m, 17, "the stolen totem", "Our totem hangs in a Lodge hall.",
			[QD.fetch(QD.dun("Thornhaven"), "The Hunt Totem", "Take the totem from the Lodge trophy hall."),
			QD.talk(m, "the totem", "Raised again! The first totem is yours.", "Bring the totem home.")], QD.reward(500, {"perk": {"stealth": 3.0}})),
		_n(f, c, 4, "werewolf", "The Lost Wolf", g, m, 20, "my son ronan", "My son Ronan vanished a year ago.",
			[QD.visit(QD.town("Mossgate"), "Follow Ronan's trail of blood-sigils.", 60.0),
			QD.talk(m, "ronan's trail", "The Velvet Court... collared my son. You are Packmate now.", "Tell Brenna what you found.")], QD.reward(700, {"perk": {"max_stamina": 10.0}})),
		_n(f, c, 5, "werewolf", "Garrick's Choice", g, m, 23, "the lone wolf", "Ser Garrick Ashgrove has been a lone wolf all his life. Bring him to us.",
			[QD.talk(QD.cast("Ser Garrick Ashgrove", "Thornhaven"), "the pack", "A pack? ...I'll come, on the full moon.", "Invite Ser Garrick."),
			QD.talk(m, "garrick joins", "Welcome, brother. Ashgrove is our friend now.", "Bring Garrick to the den.")], QD.reward(700)),
		_n(f, c, 6, "werewolf", "The Lodge Burns", g, m, 27, "the second long hunt", "The Lodge plans a second Long Hunt.",
			[QD.fight(QD.camp("Thornhaven", 2), [QD.f("hunter", 3), QD.f("hunter", 1, "Lodge Master Vance")], "Strike the Lodge's hall first."),
			QD.talk(m, "the lodge", "No Long Hunt this year.", "Report to Brenna.")], QD.reward(900)),
		_n(f, c, 7, "werewolf", "The Hunter's Moon", g, m, 32, "the hunter's moon", "Hunt beside the ancestors in the Hunting Grounds.",
			[QD.realm("R6", "Hunt the Great Stag and face the Moon's Champion."),
			QD.talk(m, "the moon's champion", "Moon-Sworn! The pelt of the moon is yours.", "Return to Brenna.")],
			QD.reward(2500, {"named": [QD.named("Moonfang Pelt", A + "dragonscale_cuirass.tres", [["fortify_health", 30], ["fortify_stamina", 30]])]})),
		_n(f, c, 8, "werewolf", "The Alpha's Challenge", g, m, 36, "the alpha's challenge", "The Court comes with collars. Then Fenris challenges me.",
			[QD.fight(QD.wild("Fernhollow", 700.0, 200.0), [QD.f("vampire", 3), QD.f("vampire", 1, "Collar-Bearer")], "Defend Greyfang Hollow."),
			QD.choice(m, "Fenris challenges Brenna.", [QD.opt("fight for brenna", "Peace with the forest, then.", "brenna"), QD.opt("let fenris win", "War on the villages.", "fenris"), QD.opt("become alpha", "Then lead us, Alpha.", "alpha")])], QD.reward(4000, {"title": "Alpha of the Greyfang"})),
	]
