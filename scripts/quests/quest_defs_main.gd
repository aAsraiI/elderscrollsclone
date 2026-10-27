class_name QuestDefsMain
extends RefCounted
## The main quest after "The Ashen Eclipse" (Story, acts I): the long road from the Hierophant's ashes
## to the Hollow Sun beneath Cinderhold (1.17). Four acts, twenty-two quests across the whole land, each
## harder than the last (levels 12 to 56). They open one after another once the Story is over
## (QuestBook.is_done("story")).
##
## The lore: before the kingdoms, the First Kings bound Vhaal the Sun-Eater beneath the mountain at
## Cinderhold with five seals (Stone, Tide, Frost, Sand and Bone) and hid each at the edge of the world.
## The Ash Cult serves Vhaal. The Hierophant was only its herald; its master is Maeron Ashgrave, the
## Pale Regent, a court scholar of Kingsreach who drowned his own name to read the old texts.

const W := "res://data/weapons/"
const A := "res://data/armor/"
const J := "res://data/jewelry/"
const GROUP := "The Hollow Sun"


static func _m(n: int, name: String, who: Dictionary, level: int, hook: String, intro: String, steps: Array, reward: Dictionary) -> Dictionary:
	var after: Array = ["story"] if n == 1 else ["M-%02d" % (n - 1)]
	return QD.q("M-%02d" % n, name, GROUP, who, level, hook, intro, steps, reward, QD.req(after))


static func list() -> Array:
	# the people of the long road
	var aldric := QD.cast("Brother Aldric Venn", "Kingsreach", "temple")
	var hale := QD.cast("Captain Doran Hale", "Kingsreach", "seat")
	var ysolde := QD.cast("Magister Ysolde Crane", "Merewater", "guild:mages")
	var keeper := QD.cast("Stonewarden Brannoc", "Cragmoor", "house")
	var osk := QD.cast("Osk the Ferryman", "Saltmere", "inn")
	var tamsin := QD.cast("Old Tamsin", "Blackfen", "house")
	var ulfrik := QD.cast("Thane Ulfrik Stormhand", "Wintergate", "seat")
	var nadira := QD.cast("Sister Nadira", "Sunhold", "temple")
	var halvard := QD.cast("Barrow-Keeper Halvard", "Gravenhold", "house")
	var korrin := QD.cast("Korrin Emberhand", "Cinderhold", "smithy")
	return [
		# ================================================================ Act II: the Herald's ashes
		_m(1, "Ashes and a Name", aldric, 12, "the hierophant's ashes",
			"The Hierophant is dead, but his ashes would not cool. Brother Aldric has kept them in a sealed urn, and every night they whisper.",
			[QD.talk(aldric, "the whispering urn", "Listen. No, closer. Do you hear it? Not words. A name, said over and over by something that has forgotten how to say anything else. Vhaal. The Hierophant served someone, and that someone serves Vhaal. I have read every book in this temple and that name is in none of them. Which means it is older than the temple, older than the kingdom, older than the faith. I need you to go back to the ritual stones. Whatever he left there, he left in a hurry.", "Hear Brother Aldric out about the urn."),
			QD.fetch(QD.wild("Kingsreach", 420.0, 120.0), "Scorched Prayer-Book", "Search the old ritual stones outside Kingsreach for what the cult left behind."),
			QD.talk(aldric, "the scorched prayer-book", "Burned on purpose, but not well enough. See here, the margins: 'the Regent's will', 'the five doors', 'when the sun is eaten the night will have a king'. A regent rules in someone's place, until that someone returns. The Hierophant was a messenger. The book is written in the old court hand of Kingsreach. Our enemy learned to write in this city. I must think. Go to Merewater. The Mages Guild there has a scholar, Ysolde Crane, who reads dead languages for pleasure. Show her this.", "Bring the prayer-book to Brother Aldric.")],
			QD.reward(350)),
		_m(2, "The Scholar of Merewater", ysolde, 14, "the old court hand",
			"Magister Ysolde Crane of the Merewater Mages Guild reads the tongues nobody speaks anymore.",
			[QD.talk(ysolde, "the five doors", "Old court hand, yes, but the words are older still. 'Five doors' is a bad translation. Five seals. There is a children's rhyme in the lake towns: stone and tide and frost and sand, and bone to bind them hand in hand. My grandmother sang it. I never wondered what it bound. There is a drowned library under the lake, a chapterhouse of the First Kings. If the seals were written down anywhere, it was there. The cult will know it too.", "Ask Magister Crane about the prayer-book."),
			QD.clear(QD.dun("Merewater", 1), "Fight down to the drowned chapterhouse near Merewater."),
			QD.fetch(QD.dun("Merewater", 1), "Chapterhouse Codex", "Bring back the codex of the First Kings from the deepest room."),
			QD.talk(ysolde, "the chapterhouse codex", "Gods. It is all here. Vhaal the Sun-Eater, who came down out of a black sky and drank the light of the old world for a hundred years. The First Kings did not kill it. They could not. They bound it under the mountain where Cinderhold stands now, and they hid the five seals at the edges of the world so no single army could take them all. Stone at Cragmoor. Tide at Saltmere. Frost at Wintergate. Sand beyond Sunhold. Bone at Gravenhold. If the cult breaks four, the fifth will not hold.", "Bring the codex to Magister Crane.")],
			QD.reward(450, {"named": [QD.named("Crane's Reading Ring", J + "silver_ring_wind.tres", [["fortify_magicka", 20]])]})),
		_m(3, "Night of the Ash Herald", ysolde, 16, "the ash herald",
			"Someone has been asking after Magister Crane in every inn along the lake road.",
			[QD.talk(ysolde, "the questions on the road", "A man in a grey hood, asking which road I take home and when. I am not brave. I am an old woman who reads. But I am not stupid either. He will come tonight, on the lake road, and he will not come alone. Will you walk with me?", "Hear what worries Magister Crane."),
			QD.fight(QD.wild("Merewater", 300.0, 200.0), [QD.f("ash_cultist", 4), QD.f("ashen_priest", 1, "The Ash Herald")], "Guard Magister Crane on the lake road at night."),
			QD.fetch(QD.wild("Merewater", 300.0, 200.0), "Herald's Brand", "Take the iron brand the Herald carried."),
			QD.talk(ysolde, "the herald's brand", "A sun with a bite taken out of it. They brand their own. And look at the stamp on the handle: the Royal Smithy at Kingsreach. Whoever leads them can walk into the King's own forge. Go home. Tell the watch. Tell someone with soldiers.", "Show Magister Crane the brand.")],
			QD.reward(500)),
		_m(4, "The Captain's Doubt", hale, 18, "the royal smithy's mark",
			"Captain Doran Hale of the Kingsreach watch does not like being told that the enemy is inside his walls.",
			[QD.talk(hale, "the bitten sun", "The Royal Smithy. You understand what you are saying? Every brand that leaves that forge is signed for. If one went missing, it went missing on a ledger, and every ledger in this castle goes past the Chancellor's clerks. I will look. Quietly. Meanwhile do something useful: the Smithy keeps its old ledgers in the Old Keep under the castle. Nobody goes down there anymore.", "Tell Captain Hale about the brand."),
			QD.fetch(QD.dun("Kingsreach", 3), "Smithy Ledger of the Third Year", "Find the old smithy ledger in the Old Keep beneath Kingsreach."),
			QD.choice(hale, "Bring the ledger to Captain Hale.", [QD.opt("tell the king's court", "Then it is out in the open. The court will be furious, and whoever signed for that brand will run. But the King will know. I hope that is worth it.", "told_court"), QD.opt("keep it between us", "Good. A rat that does not know it is seen keeps using the same holes. The brand was signed for by a clerk named M. Ashgrave. There is no clerk by that name. There has not been for twenty years.", "kept_secret")])],
			QD.reward(550)),
		# ================================================================ Act III: the five seals
		_m(5, "The Stone Seal", keeper, 20, "the stone seal",
			"Stonewarden Brannoc's family has kept a stone under Cragmoor's quarry for forty generations without knowing why.",
			[QD.talk(keeper, "the warden's stone", "My father's father's father was told: keep the stone dry and keep strangers off it. That was all. Three nights ago strangers came, and they were not lost. They went down into the old workings with hammers and incense. I am a quarryman. I know when a mountain is being cut wrong. Go down. Please.", "Speak with Stonewarden Brannoc."),
			QD.clear(QD.dun("Cragmoor", 1), "Stop the cult in the old quarry workings beneath Cragmoor."),
			QD.fight(QD.dun("Cragmoor", 1), [QD.f("ash_cultist", 3), QD.f("ashen_priest", 1, "Stonebreaker Voss")], "Defeat the stonebreaker at the seal."),
			QD.talk(keeper, "the seal holds", "It is cracked. I can see it from here, a hair's width, but it is whole. Forty generations and I am the one who nearly lost it. Take this. My grandmother said it was cut from the same rock. I think now she knew more than she told.", "Tell Brannoc the seal holds.")],
			QD.reward(650, {"named": [QD.named("Quarrystone Amulet", J + "gold_amulet_endurance.tres", [["fortify_health", 30]])]})),
		_m(6, "The Tide Seal", osk, 23, "the tide seal",
			"Osk the Ferryman says the sea at Saltmere has been pulling the wrong way for a month.",
			[QD.talk(osk, "the wrong tide", "Thirty years I've run the ferry. Tide comes in, tide goes out. This month it comes in and it doesn't go out, not all the way. There's a shrine on the rocks past the point, drowned at high water. My father said it was older than the harbour and to row wide of it. Now there's lights on it at low tide. Men in grey.", "Hear Osk out about the tide."),
			QD.visit(QD.wild("Saltmere", 380.0, 300.0), "Reach the drowned shrine on the rocks past the point at low tide."),
			QD.fight(QD.wild("Saltmere", 380.0, 300.0), [QD.f("ash_cultist", 3), QD.f("smuggler", 2), QD.f("ashen_priest", 1, "Tidecaller Imre")], "Drive the cult from the drowned shrine."),
			QD.fetch(QD.wild("Saltmere", 380.0, 300.0), "Pearl of the Tide Seal", "Lift the seal-pearl from the shrine before the water returns."),
			QD.talk(osk, "the pearl of the seal", "Felt it, didn't you? The sea let go. Keep that thing out of salt water and keep it away from me. I'm a ferryman. I don't want to know what the deep things are afraid of.", "Return to Osk.")],
			QD.reward(700)),
		_m(7, "The Witch of Blackfen", tamsin, 26, "the witch of blackfen",
			"Everyone in Blackfen knows Old Tamsin. Nobody admits to visiting her.",
			[QD.talk(tamsin, "the frost seal's road", "You smell of salt and old stone, dearie. Two seals already, and in a hurry for the third. Frost. Oh yes, I know where. But nothing's free in the fen. There's a beast in the reeds that took my goats and my sister's boy. Bring me its heart and I'll tell you the way the cult doesn't know.", "Ask Old Tamsin about the Frost Seal."),
			QD.fight(QD.wild("Blackfen", 320.0, 60.0), [QD.f("werewolf", 1, "The Reed-Beast"), QD.f("wolf", 3)], "Hunt the Reed-Beast in the fen."),
			QD.fetch(QD.wild("Blackfen", 320.0, 60.0), "Heart of the Reed-Beast", "Take the beast's heart."),
			QD.talk(tamsin, "the reed-beast's heart", "Good. Good. The Frost Seal isn't in Wintergate, whatever the Thane's songs say. It's under the glacier north of it, in a hall the old kings dug, and the door only opens for someone the Thane trusts. So go and make him trust you. Oh, and dearie? The grey ones have a woman of their own up there. Cold as the ice. Watch your fingers.", "Bring the heart to Old Tamsin.")],
			QD.reward(700)),
		_m(8, "The Frost Seal", ulfrik, 29, "the frost seal",
			"Thane Ulfrik Stormhand of Wintergate trusts no one from the south.",
			[QD.choice(ulfrik, "Ask Thane Ulfrik for the way to the glacier hall.", [QD.opt("tell him the truth", "A sun-eater under a southern mountain. My grandmother told that story to frighten us. If it is true, it is my hall the cold will reach first. I will open the door.", "truth"), QD.opt("offer him gold", "Gold. You southerners think everything has a price. It does. Fine. The door will be open, and my men will remember who paid.", "gold")]),
			QD.clear(QD.dun("Wintergate", 1), "Descend into the glacier hall north of Wintergate."),
			QD.fight(QD.dun("Wintergate", 1), [QD.f("ice_wraith", 2), QD.f("frost_raider", 2), QD.f("ice_wraith", 1, "Sigrun the Frost Witch")], "Defeat the Frost Witch before she breaks the seal."),
			QD.talk(ulfrik, "the frost witch is dead", "Sigrun. She was from this hall, you know. A thane's daughter. They promised her the winter would never end, and she wanted that more than anything. Take her cloak-pin. I do not want it in my hall.", "Report to Thane Ulfrik.")],
			QD.reward(800, {"named": [QD.named("Sigrun's Frost-Pin", J + "silver_amulet_insight.tres", [["resist_frost", 40]])]})),
		_m(9, "The Oracle of Sunhold", nadira, 32, "the oracle of sunhold",
			"Sister Nadira of the Sunhold temple sees what the desert will not say.",
			[QD.talk(nadira, "the sand seal", "I saw you coming three nights ago. You walked out of the sea with a pearl and out of the ice with a dead woman's pin. The Sand Seal has no door. It moves. It sleeps under the dunes and wakes where the wind tells it. I can find it, but I must dream to do it, and you must sit with me while I dream. The cult will try to wake me.", "Ask Sister Nadira about the Sand Seal."),
			QD.wait(8.0, "Keep watch while Sister Nadira dreams."),
			QD.fight(QD.town("Sunhold"), [QD.f("ash_cultist", 3), QD.f("dune_stalker", 2)], "Guard the temple while the oracle sleeps."),
			QD.talk(nadira, "what the oracle dreamed", "I saw it. A buried city of the First Kings near Dustgate, under the bones of a great beast. And I saw something else. A man, pale as salt, with a crown of ash, standing in Cinderhold's crater, counting. He is counting the days to the eclipse, and there are not many left.", "Hear what Sister Nadira saw.")],
			QD.reward(800)),
		_m(10, "The Sand Seal", nadira, 35, "the buried city",
			"The Sand Seal lies in a buried city near Dustgate. The cult has sent its best knife.",
			[QD.clear(QD.dun("Dustgate", 1), "Find the buried city of the First Kings near Dustgate."),
			QD.fight(QD.dun("Dustgate", 1), [QD.f("cutthroat", 3), QD.f("cutthroat", 1, "Sable Vey, the Regent's Knife")], "Stop Sable Vey at the Sand Seal."),
			QD.fetch(QD.dun("Dustgate", 1), "Sable Vey's Orders", "Take the orders Sable Vey carried."),
			QD.talk(nadira, "the regent's orders", "In his own hand: 'The Bone Seal is already ours. Delay the stranger at the sand. By the eclipse, it will not matter.' Already theirs. Gravenhold. Go, now.", "Bring the orders to Sister Nadira.")],
			QD.reward(900, {"named": [QD.named("The Regent's Knife", W + "ebon_dagger.tres", [["fortify_sneak", 15]])]})),
		_m(11, "The Bone Seal", halvard, 38, "the bone seal",
			"Barrow-Keeper Halvard of Gravenhold has not slept since the barrows opened.",
			[QD.talk(halvard, "the open barrows", "Nine nights ago the old barrow on the hill opened from the inside. Not dug. Opened. The dead walk the ridge at night and they all walk the same way, east, toward the mountain. The seal was under the barrow-king's bier. I went in. It is gone. The barrow-king's crown is gone too, and whoever wears it commands the dead.", "Speak with Barrow-Keeper Halvard."),
			QD.clear(QD.dun("Gravenhold", 1), "Go down into the barrow-king's tomb near Gravenhold."),
			QD.fight(QD.dun("Gravenhold", 1), [QD.f("barrow_wight", 3), QD.f("wight_lord", 1, "The Crowned Dead")], "Destroy the dead thing wearing the barrow-king's crown."),
			QD.fetch(QD.dun("Gravenhold", 1), "Barrow-King's Crown", "Take back the barrow-king's crown."),
			QD.talk(halvard, "the barrow-king's crown", "The seal was the crown. All this time. The Regent did not break the Bone Seal; he wore it. Four of five, and you have put them back in their beds. But you understand: he does not need all five. Once the sun is eaten, the last one will crack on its own. He is waiting for the eclipse.", "Bring the crown to Halvard.")],
			QD.reward(1000)),
		_m(12, "Betrayal at Merewater", ysolde, 40, "the scholar taken",
			"A runner from Merewater: the Mages Guild hall was broken into in the night and Magister Crane is gone.",
			[QD.visit(QD.town("Merewater"), "Hurry to the Merewater Mages Guild."),
			QD.clear(QD.dun("Merewater", 2), "Follow the kidnappers to their hideout near Merewater."),
			QD.fight(QD.dun("Merewater", 2), [QD.f("ash_cultist", 4), QD.f("ashen_priest", 1, "Herald Corwen")], "Free Magister Crane from the cult."),
			QD.choice(ysolde, "Speak with Magister Crane.", [QD.opt("ask why they took her", "They wanted me to read something. The last page of the chapterhouse codex, the one I told you was missing. I lied. I tore it out. It says how the First Kings made the seals: they gave up their names to them. The Regent wants to undo that. He wants the names. He wants to be a First King.", "the_page"), QD.opt("ask if she told them anything", "Everything, eventually. I am sorry. They know the eclipse comes over Cinderhold in seven days. They know the seals you mended. And they know your name.", "she_broke")])],
			QD.reward(1000)),
		# ================================================================ Act IV: the Pale Regent
		_m(13, "The Regent's Name", aldric, 42, "maeron ashgrave",
			"Brother Aldric has found the name behind the Regent's title in the temple's oldest registers.",
			[QD.talk(aldric, "who the regent was", "Maeron Ashgrave. A court scholar, twenty years ago, tutor to the late prince. He was dismissed for 'unlawful study' and drowned himself in the lake. They found his robes. They never found him. He did not drown. He gave his name away the way the First Kings did, and something took it gladly. His old study is in a camp now, by the ash fields east of Cinderhold, where he hides his books.", "Hear what Brother Aldric found."),
			QD.fetch(QD.camp("Cinderhold", 1), "Ashgrave's Journal", "Take Ashgrave's journal from his camp by the ash fields."),
			QD.talk(aldric, "ashgrave's journal", "'I will be the first of the new kings, and the sun will be my first subject.' Pride. Always pride. He means to stand in the crater when the moon covers the sun and call Vhaal by the names he stole. We need a weapon that can stand in that light. There is a smith in Cinderhold who forges for the temple: Korrin Emberhand.", "Bring the journal to Brother Aldric.")],
			QD.reward(1100)),
		_m(14, "Sunsteel", korrin, 44, "sunsteel",
			"Korrin Emberhand of Cinderhold forges the temple's blades. She has never forged one for a war.",
			[QD.talk(korrin, "a blade for the eclipse", "Sunsteel. My mother's mother made one, for a priest who went into the mountain and did not come back. It needs ore from the old seam under the mountain, the one the miners abandoned, and fire salts from the ash fields. And it needs a day and a night in my forge with nobody touching it.", "Ask Korrin about a weapon for the eclipse."),
			QD.fetch(QD.dun("Cinderhold", 1), "Seam-Ore of the First Forge", "Bring ore from the abandoned seam under the mountain."),
			QD.fetch(QD.wild("Cinderhold", 360.0, 240.0), "Ash-Field Fire Salts", "Gather fire salts from the ash fields."),
			QD.wait(24.0, "Wait while Korrin forges the sunsteel."),
			QD.talk(korrin, "the sunsteel blade", "There. It hums when the sun's on it. I don't know what you're walking into, and I don't want to. Bring it back if you can. If you can't, make it count.", "Collect the blade from Korrin.")],
			QD.reward(1200, {"named": [QD.named("Sunsteel", W + "dragonbone_sword.tres", [["fortify_attack", 15], ["resist_fire", 30]], 4)]})),
		_m(15, "The Gathering", aldric, 46, "the gathering of allies",
			"The eclipse is close. Brother Aldric asks who will stand with you in the crater.",
			[QD.talk(ulfrik, "the thane's answer", "My hall's cold. The Frost Witch was one of mine. I owe the world one less Sigrun. My axemen will hold the north rim of the crater. Tell your priest.", "Ask Thane Ulfrik to stand with you."),
			QD.talk(nadira, "the oracle's answer", "I have already seen myself there. I do not know what happens next; the dream ends. I will come.", "Ask Sister Nadira to stand with you."),
			QD.talk(osk, "the ferryman's answer", "Me? I'm a ferryman. ...Fine. I'll bring the boats round to the lake shore below the mountain. If it goes bad, somebody has to row you out.", "Ask Osk to stand with you."),
			QD.choice(aldric, "Tell Brother Aldric who will come.", [QD.opt("all of them", "Then we go together. Whatever happens, the Regent will not stand alone in that crater with his god. Neither will you.", "all_allies"), QD.opt("go alone", "Alone. I understand. You do not want them to die for this. Neither do I. Very well. But I am coming, and you cannot forbid a priest.", "alone")])],
			QD.reward(1200)),
		_m(16, "The Road of Ash", aldric, 48, "the road of ash",
			"The way to Cinderhold's crater runs across the ash fields, and the cult has burned everything on it.",
			[QD.fight(QD.wild("Cinderhold", 420.0, 90.0), [QD.f("ash_cultist", 4), QD.f("fire_spirit", 2)], "Break the cult's first line on the ash road."),
			QD.fight(QD.wild("Cinderhold", 260.0, 60.0), [QD.f("raider_marauder", 3), QD.f("fire_spirit", 2), QD.f("ashen_priest", 1, "Herald of the Burned Road")], "Fight through to the foot of the mountain."),
			QD.talk(aldric, "the foot of the mountain", "I can feel it. The ground is warm. He has started. The gate is under the old temple ruins, inside the mountain. Whatever is down there, we go down together.", "Meet Brother Aldric at the foot of the mountain.")],
			QD.reward(1300)),
		_m(17, "The Gate Beneath Cinderhold", aldric, 50, "the gate beneath the mountain",
			"Under the mountain the First Kings left a gate, and the Regent's faithful hold it.",
			[QD.clear(QD.dun("Cinderhold", 2), "Fight through the halls beneath Cinderhold to the crater gate."),
			QD.fight(QD.dun("Cinderhold", 2), [QD.f("skeleton_knight", 2), QD.f("ashen_priest", 2), QD.f("vault_guardian", 1, "Warden of the Crater Gate")], "Defeat the warden of the gate."),
			QD.talk(aldric, "the crater gate", "Above us. The crater. And the sky is already going dark at the edges. This is the last of it.", "Speak with Brother Aldric at the gate.")],
			QD.reward(1400)),
		_m(18, "The Pale Regent", aldric, 52, "the pale regent",
			"Maeron Ashgrave stands in the crater with the stolen names of the First Kings, waiting for the moon.",
			[QD.visit(QD.wild("Cinderhold", 120.0, 0.0), "Climb into the crater as the eclipse begins."),
			QD.fight(QD.wild("Cinderhold", 120.0, 0.0), [QD.f("ash_cultist", 3), QD.f("ashen_priest", 1, "Maeron Ashgrave, the Pale Regent")], "Defeat the Pale Regent."),
			QD.talk(aldric, "the regent falls", "He's dead. He is dead and the sun is still going out. He started it, and it does not need him anymore. Look at the crater floor. It's opening.", "Go to Brother Aldric.")],
			QD.reward(1500, {"named": [QD.named("Ashgrave's Crown of Names", J + "gemmed_amulet_insight.tres", [["fortify_magicka", 50], ["spell_absorption", 15]], 4)]})),
		# ================================================================ Act V: the Hollow Sun
		_m(19, "The Sun-Eater Wakes", aldric, 53, "the sun-eater wakes",
			"The eclipse is total. Something vast is climbing out of the crater.",
			[QD.fight(QD.wild("Cinderhold", 90.0, 180.0), [QD.f("fire_spirit", 3), QD.f("dragon", 1, "The Herald of Vhaal")], "Kill the Herald of Vhaal before it calls its master up."),
			QD.talk(aldric, "the herald of vhaal", "That was only its herald. I can hear Vhaal now. It is asking for the names. It is asking for yours.", "Speak with Brother Aldric.")],
			QD.reward(1600)),
		_m(20, "The Last Seal", aldric, 55, "the last seal",
			"The First Kings bound Vhaal by giving their names to the seals. There is one seal left to make.",
			[QD.talk(aldric, "how the kings bound it", "Ysolde's missing page. The kings gave their names to the seals, and the seals held because something remembered them. The Regent stole their names. So the seals need new ones. One will do, the page says, if it is given freely. Mine is a priest's name; nobody will miss it. Or... the crown. Ashgrave's crown holds all five of the old kings' names. Break it in the crater and give them back.", "Ask Brother Aldric how Vhaal can be bound."),
			QD.choice(aldric, "Decide how to bind the Sun-Eater.", [QD.opt("give back the old kings' names", "The crown shatters. Five voices, very old and very tired, say their own names once, and the crater closes like a hand. The sun comes back. Somewhere a quarryman's stone, a fisherman's pearl and a barrow-king's bones grow warm again.", "kings_names"), QD.opt("let Aldric give his name", "He smiles. 'Remember me, then, since nobody else will be able to.' He says his name into the dark and it does not come back. The sun returns. A man in a priest's robe stands beside you and cannot tell you who he is.", "aldric_name"), QD.opt("give your own name", "You say it once, the way you've said it all your life, and then you can't. The sun comes back over Cinderhold. Everyone calls you by what you did. Nobody remembers what you were called.", "own_name")]),
			QD.visit(QD.wild("Cinderhold", 120.0, 0.0), "Watch the sun return over the crater.")],
			QD.reward(2000)),
		_m(21, "Dawn over Cinderhold", korrin, 56, "dawn over cinderhold",
			"The eclipse has passed. Cinderhold wakes to a sky it thought it would never see again.",
			[QD.talk(korrin, "the blade came back", "You brought it back. I didn't think anyone would. Keep it. It knows you now, I think, or what's left of the name you used to have, or whatever the priest says. People are singing in the streets. Nobody here has ever sung.", "Return the sunsteel to Korrin."),
			QD.talk(ysolde, "the codex closed", "I have written it all down. Every word, every name we could recover. Somebody will need it again in a thousand years, and they should not have to drown a library to find it.", "Visit Magister Crane in Merewater."),
			QD.talk(hale, "the court's thanks", "The King wants to see you. He wants to give you a title. Take it. You've earned the right to be called something, since half the realm is calling you something already.", "Report to Captain Hale in Kingsreach.")],
			QD.reward(2500, {"named": [QD.named("Eclipse-Breaker's Ring", J + "gemmed_ring_vigor.tres", [["fortify_health", 40], ["fortify_stamina", 40]], 4)]})),
		_m(22, "The Hollow Sun", aldric, 56, "the hollow sun",
			"Brother Aldric has one more thing to say.",
			[QD.talk(aldric, "what remains", "Vhaal is bound again, as it was bound before, and one day it will wake again, as it woke before. That is not a defeat. That is what keeping the world means: doing it again, each time, for as long as anyone remembers how. The temple will keep the story now. You keep the scar. Go on. The world is bigger than this mountain, and it is all still there because of you.", "Speak with Brother Aldric one last time.")],
			QD.reward(3000)),
	]
