class_name LoreBooks
extends RefCounted
## The 72 lorebooks of Caldreth (see the design bible). Each is made at runtime like a quest item
## (saved as "lore://<id>"), sits on a bookshelf in the building of its town listed below, and is
## read with ItemUse ("Read") in the BookUI. A skill book raises its skill by a level the first
## time it is read (WorldState "lore_read/<id>").
##
## Entry: [id, title, author, town (whose seat, temple or guild hall shelves it), skill id or "", text]

const PREFIX := "lore://"
const READ := "lore_read/"

const LIST := [
	# ---- History
	["crowned_1", "The Crowned Age, Vol. 1: The Sundering", "Master Aldous Penhale", "Kingsreach", "", "When the last emperor of Aurel died without an heir, twelve governors each believed the empire was theirs. For eight years they proved otherwise to one another. Roads became borders, forts became prisons, and the old law fell silent. This volume records the first four years: the burning of the Senate, the March of Twelve Banners, and the winter when no harvest was gathered anywhere."],
	["crowned_2", "The Crowned Age, Vol. 2: Caedmon's War", "Master Aldous Penhale", "Harrowford", "", "Caedmon Aurelane was a Plains warlord with three hundred horse and no claim to anything. He won because he paid his soldiers, fed the villages he took, and never broke a sworn word. At the ford of Harrowford he beat two governors in one day. Four years later he was crowned at Kingsreach, on the hill where Castle Dawnhold now stands."],
	["crowned_3", "The Crowned Age, Vol. 3: The Thirteen Stones", "Master Aldous Penhale", "Kingsreach", "", "Thirteen lords swore to Caedmon, each laying a hand on a stone carried from their own land. The stones still stand in the Council Chamber. By the Oath, the Crown keeps the peace and the roads; the great lords keep their lands and their law. Any lord who breaks the Oath forfeits their stone, and the realm may take their land."],
	["crowned_4", "The Crowned Age, Vol. 4: Salt, Ash and Winter", "Master Aldous Penhale", "Saltmere", "", "Three wars tested the Oath. In 97 the Tidewells rebelled over sea taxes and lost. In 188 the Red Winter came out of Fenmoor and the Knightly Order was born to end it. In 251 House Vyrel allied with the Ash Cult to darken the sun, and the Kjellvar host broke them at the Obsidian Gate. The realm survived each, a little more scarred."],
	["sky_towers", "Fall of the Sky-Towers", "an unknown elven scribe", "Skyfall", "destruction", "The sun went out at the hour of the third bell. Our towers fell silent, for they drank light and there was none to drink. Below, the slaves rose with torches. Above, three princes went down into the dark to bargain, and came back hungry. I write this by the last lamp. If anyone reads it, know that we were proud, and that pride is a poor candle."],
	["barrow_folk", "The Barrow Folk", "Brother Tobin of Gravenhold", "Stonebrook", "", "The first people of this land buried their kings under hills, with crowns of stone and swords of bronze. They believed the honest dead go on living below, in a country of blue fire. Every barrow in the Highlands is a door to that country, and every wight a guard who never stopped guarding. Leave them be, and they leave you be."],
	["roads_aurel", "Roads of Aurel", "Imperial Surveyor Varo Tull", "Brindle Cross", "", "A road must be straight, so that a legion may see its end. A road must be wide, so that two carts pass without slowing. A road must be paved, so that rain does not unmake it. Every main road of Caldreth follows a line I or my fathers drew. Kings come and go; the road stays."],
	["long_hunt", "The Long Hunt of 330", "Hunt-master Corran Vance", "Thornhaven", "", "We burned them out of the Highland glens, den by den, with silver and fire. Forty wolves we killed that autumn, and lost twelve good hunters. The survivors fled south into the deep forest. I do not regret it. A beast that wears a man's face is still a beast."],
	["grey_plague", "The Grey Plague: A Report", "Sir Halvard Greaves", "Gravenhold", "", "The sickness began in the spring of 380 in the villages east of Blackfen. The sick turned grey, then still, then rose. Within a year the land itself turned grey and the dead walked it. We built the wall from the marsh to the hills. It has held for thirty-two years. It must hold for thirty-two more."],
	["desert_accord", "The Desert Accord", "Vizier Hamid Sahl", "Sunhold", "", "Article One: the Emirate of the Sunward Sands is a fief of the Crown, and its Emir a great lord of the Council. Article Two: the Emir keeps his own courts and his own faith. Article Three: slavery is ended in all the sands. Signed in the year 403, at the Palace of Mirrors, in the presence of the Dawn."],
	["child_history", "A Child's History of Caldreth", "Mistress Wren Larkin", "Wheatley", "", "Once there were elves who lived in towers in the sky. Then the sun went out and they fell down! Then came the emperors, who built very straight roads. Then the emperors ran out of emperors. Then King Caedmon came, who was brave and fair, and now we have kings. The end. (Be good, or a vampire will get you.)"],
	["sundering_took", "What the Sundering Took", "Anonymous", "Heathwick", "", "On the field below Heathwick, they say, you can still hear the horns on misty nights. A shepherd once followed the sound and found a whole legion marching in the fog, their faces grey, their eyes on the road ahead. He asked where they were going. 'Home,' said the last of them. 'We are always going home.'"],
	# ---- The gods
	["book_eight", "The Book of the Eight", "The Temple of the Dawn", "Kingsreach", "", "Solenne the Dawn, who crowns the day. Maela the Hearth Mother, who keeps the home. Vey the Silent Watcher, who keeps the honest grave. Oshra of the Tides. Korrund the Smith. Elis the Wanderer. Isenne the Lantern. Varrow the Green Hunter. Honour the Eight, and the Eight will not forget you."],
	["morning_hymns", "Solenne's Morning Hymns", "High Priestess Amara", "Kingsreach", "restoration", "Rise, light, and find us waiting. Rise, light, and find us whole. What the night has taken, return; what the night has wounded, mend. We hold out our hands to you, and they are full of you."],
	["hearth_almanac", "The Hearth Mother's Almanac", "the priests of Oakrest", "Oakrest", "cooking", "Frostwane: mend tools, bless the seed. Thawmoon: plough when the frost leaves the ground. Seedfall: sow, and feast. Bloomtide: weed. Midyear: hay. Sunheight: the first grain. Harvestmoon: the Hearth Feast. Hearthfire: preserve and smoke. Leaffall: remember the dead. Duskmoon and Deepwinter: stew, and stories."],
	["closed_eye", "The Closed Eye", "the Silent Monks of Vey", "Gravenhold", "", "Death is not a punishment. It is a ferry. The honest dead wait on an island far out at sea, where the Silent Watcher weighs them, and then they pass on. Only those with unfinished business linger. Help them finish it, and they go gladly."],
	["oshra_moods", "Oshra's Moods", "Captain Lira Gale", "Saltmere", "", "Red sky at dusk, Oshra's at rest. Gulls flying inland, Oshra's in a temper. Fish near the surface, she's hungry. Still water and no wind on a moonless night: stay in port, for that is the Drowned King breathing."],
	["green_law", "The Green Hunter's Law", "Hesper Yew of Fernhollow", "Fernhollow", "archery", "Take what you need. Honour what you kill. Never kill the mother before her young can run. Never take the white beast. Thank the forest when you leave it. Break these and Varrow will turn his red face to you, and you will be the hunted."],
	["black_hymn", "Hymn of the Black Sun", "the Ash Cult", "Cinderhold", "", "Behind the sun there is a hunger, and the hunger is holy. It ate the sun once for forty days, and the world was cleansed. It will eat again. Sing to it, and be fed upon last. (Reading this aloud in any town of the realm is a crime.)"],
	["drowned_promise", "The Drowned King's Promise", "a Port Wrack priest", "Kelpstead", "", "He sleeps beneath the Isles, the old god of the sea, and he keeps every promise made to him, and makes you keep yours. Ask for fortune and he gives it. Then, one day, he asks for what is his. Never forget that he will ask."],
	# ---- Nobility and politics
	["great_houses", "The Great Houses of Caldreth", "Herald-Royal Bastian Crane", "Kingsreach", "", "Aurelane, gold sun on white. Valcourt, silver heron on blue. Tidewell, white ship on green. Ashgrove, silver oak on black. Morvaine, black swan on grey. Brannoch, red stag on grey. Sahrim, gold scorpion on red. Kjellvar, white bear on black. Vyrel, black flame on orange. Nine houses, one crown."],
	["on_regency", "On the Regency", "Lord Chancellor Edric Haverly", "Kingsreach", "", "When the heir is under sixteen, the realm is governed by a Regency Council of the great lords, the Chancellor and the Marshal, which names a Regent. In 97 the council named the heir's uncle. Precedent is not law, but it is the next best thing."],
	["lady_guide", "A Lady's Guide to Court", "Lady Aveline Valcourt", "Merewater", "speech", "Never speak first to a Duke. Never speak last to a Duchess. Always praise the food, even at Mirehold, where there is never any. Agree with everyone in public and no one in private. And if a Kjellvar offers you mead, drink it, all of it, or there will be a duel."],
	["tidewell_ledgers", "The Tidewell Ledgers (abridged)", "the Tidewell stewards", "Saltmere", "", "Income from the salt pans, from the fleet, from the loan to the Crown. Expenses: ships, wages, gifts to the Council. And every year since 112, one line in a different hand: 'Paid to the deep: one tithe.' No sum is written beside it."],
	["white_bear_sagas", "Sagas of the White Bear", "Skald Halla Bright-Tongue", "Wintergate", "two_handed", "Kjellvar the First walked into the ice to hunt a bear the size of a hall. She came back with its pelt and swore the Northmarch to Caedmon on it: 'While a Kjellvar sits by the Crown's fire, the north is the Crown's.' Then she walked back into the ice, and did not return."],
	["vyrel_penance", "The Penance of Vyrel", "Archon Seraphine Vyrel", "Cinderhold", "", "My grandmother's grandfather tried to put out the sun. For that, every Vyrel since has walked barefoot to the Smokefall shrine each Deepwinter, and paid a blood-price to the Kjellvar. I have walked it thirty times. My feet are scars. I am done being ashamed of a dead man."],
	["stag_stone", "Stag and Stone", "Duke Fergus Brannoch", "Cragmoor", "block", "A line holds because every man in it trusts the shield on his left. A realm holds the same way. Merchants and children make poor shields. Give me a soldier on the throne and I will give you a realm that stands."],
	["swans_silence", "The Swan's Silence", "a Morvaine housekeeper", "Blackfen", "", "The mistress never eats with us. The shutters never open by day. Last night I carried wine to the undercroft and there were coffins there, fine ones, and one had her crest on it. The Margrave saw me. He didn't say anything. He just looked so sad. I am leaving tonight."],
	["sun_scorpion", "The Sun and the Scorpion", "Princess Leyla al-Sahrim", "Sunhold", "", "We were free for a hundred years, and poor. We joined the realm, and grew rich, and were mocked at court for our accents. My brother thinks a royal marriage will end the mockery. I think it will only give them a new joke. We shall see which of us is right."],
	["prince_journal", "The Prince's Journal", "Prince Caedric Aurelane", "Kingsreach", "", "Father worsens. The council circles. A lady came to me tonight, pale and beautiful, and offered me the crown now, not in ten years. I told her to go. She smiled. I will ride to Briarwatch on the hunt and think. Elowen, if anything happens to me, be braver than I was."],
	# ---- Vampires and werewolves
	["three_princes", "Three Princes of the Black Blood", "Sister Ilse of the Dawn", "Kingsreach", "", "Vaelith the Gracious, who loved beauty, founded the Velvet Court. Ghaur the Starving, who loved the hunt, founded the Hollow Kin. Somnir the Cantor, who loved the dark, founded the Ashen Choir. All three drank the Black Sun's blood in the First Eclipse. All three are, as far as we know, still somewhere in the world."],
	["signs_blood", "Signs of the Blood", "the Knightly Order", "Gravenhold", "", "A vampire shuns the sun and grows weak in it. It casts a faint reflection or none. It does not eat. Fire and silver hurt it; garlic hurts only its temper. The young ones are hungry and careless. The old ones are patient. Fear the patient ones."],
	["velvet_rules", "The Velvet Rules", "an unknown Court elder", "Blackfen", "", "Never feed where you are seen. Never kill what you can own. Never let a thrall know your name. Always be invited. Always be beautiful. The Court does not hunt. The Court is served."],
	["teeth_dark", "Teeth in the Dark", "a Hollow Kin survivor", "Stonebrook", "", "The Court sold our havens to the knights in the Red Winter. They came with fire at noon, when we sleep. My mother carried me out through the bones. We remember. The Kin always remember."],
	["choir_hymnal", "Hymnal of the Choir", "Choirmaster Somnir", "Cinderhold", "alteration", "First verse: the blood is a song. Second verse: the song is a door. Third verse: the door opens onto the night that has no morning. Sing softly. The sun is listening."],
	["moon_sick", "Moon-Sick", "Dr. Fenn Merrow, physician", "Merewater", "", "Sanies Lupinus begins as a fever after a bite. On the first full moon the patient changes. The beast grows stronger with each feast of flesh. It can be cured by a priest of Varrow, or by rare draughts, at great cost. Most patients, in my experience, do not want to be cured."],
	["greyfang_songs", "The Greyfang Songs", "Alpha Brenna Greyfang", "Fernhollow", "", "Mother Moon, red and round, we run in your light. We hunt, we do not murder. We feast, we do not waste. When we die we run forever in your forest. Howl, little ones, howl, and she will hear."],
	["curing_curse", "Curing the Curse", "Brother Tobin of Gravenhold", "Gravenhold", "", "Vampirism can be cured by a priest of the Dawn, for a price, before the blood fully turns, or after, with greater cost. Lycanthropy can be lifted by the same. Know this: the clans and the pack do not forgive a cure. A cured member is cast out."],
	# ---- Places and realms
	["travellers_caldreth", "A Traveller's Caldreth", "Marta Fenwick", "Brindle Cross", "", "Thirteen lands, one crown. The Plains are gentle; the Lakeland is foggy; the Coast is salt and storm. The Forest has eyes. The Swamp has teeth. The Desert has secrets. The Highlands have ghosts. The North has winter, and the Ashlands have fire. Keep to the roads, and carry bread."],
	["isles_breakers", "Isles Beyond the Breakers", "Captain Lira Gale", "Saltmere", "", "Six islands, the wreck of an elven sea-kingdom. Port Wrack is a pirate town built on a reef of dead ships. The Tide Temple opens only at low tide. And below it all, they say, the Drowned King has a city of his own."],
	["under_sand", "Under the Sand", "Antiquarian Ysolde Dask", "Sunhold", "", "Kar-Aurel, the capital of the Old Empire, was not destroyed. It was swallowed. The sands took it in the last year of the Sundering. I believe it lies beneath the deep desert, intact, waiting for a shovel brave enough."],
	["mossgate_riddle", "The Mossgate Riddle", "Reeve Linnea Moss", "Mossgate", "", "Our gate glows at dusk, green as a firefly. The elves built it. Through it lies a forest that dreams. My grandmother walked in once and came back a week later, though she swore she'd been gone an hour."],
	["cairn_letters", "Letters from Cairn-Under", "the dead", "Stonebrook", "", "To my grandson: we are well. The blue fire is warm enough. The Stone King is a fair lord. Don't grieve for us. And don't let anyone dig up the hill, or we shall have to come up and complain."],
	["mirror_mirage", "The Mirror and the Mirage", "Amir Saleh, court poet", "Sunhold", "", "In the great mirror of the palace, I saw a city like ours, but backwards, where the sun set in the east and the fountains ran up. A woman there waved at me with her left hand. I waved back. I have not looked in a mirror since."],
	["winter_queen", "The Winter Queen", "a northern nursery tale", "Northwatch", "", "Hush, little bear. Out past the ice there's an island where it's always the longest night. The Winter Queen lives there, the first of the Kjellvars. She never died. She only got cold. And she's lonely, so don't sleepwalk to the shore."],
	["city_sky", "The City in the Sky", "Highborn star-priest Ilvaren", "Skyfall", "", "When the sun failed, the engines of Ilvaris tore the city from the ground and lifted it above the dark. We drift still, I think, above the clouds. Our gardens grow. Our caretakers grow old. If you read this, come up. The sky-gate needs only a navigation core."],
	["grey_lands", "The Grey Lands", "Sister Dorrit of Lastlight", "Lastlight", "", "Inside the wall, the grass is grey and the birds don't sing. We keep the Dawn-flame lit and the doors barred at dusk. The dead walk past our fences most nights. They don't come in. Not yet."],
	["gloaming_guide", "A Field Guide to the Gloaming", "Old Weir the Ferryman", "Blackfen", "", "The Gloaming is where the blood goes. A grey plain under a sun that never rises. The living sicken there, slowly. The undying thrive. If you must go, carry a light, pay your fare, and do not linger at the Prison of Souls."],
	# ---- Magic and craft
	["six_schools", "The Six Schools", "Archmage Ilsabet Corrow", "Kingsreach", "illusion", "Destruction harms. Restoration heals. Conjuration calls. Illusion bends the mind. Alteration bends the world. Mysticism, the oldest, binds them all. A mage who knows only one school knows only one sixth of magic."],
	["korrund_anvil", "Korrund's Anvil", "the Monastery of Korrund", "Frosthelm", "smithing", "Heat the metal until it speaks. Strike it until it agrees. Quench it until it remembers. A smith does not make a blade; a smith persuades the iron that it was always a blade."],
	["obsidian_glass", "Obsidian and Steel-Glass", "the master smith of Emberwick", "Emberwick", "smithing", "Volcanic glass shatters if you hurry it. Temper it slowly in ash, three days, turning it at each dawn. The result cuts like nothing else and weighs half of steel."],
	["alchemist_garden", "The Alchemist's Garden", "Fenwick Merrow", "Merewater", "alchemy", "Lavender for the mind. Blue mountain flower for the body. Nightshade for your enemies. Glowcap from the deep woods, wisp dust from the dark caves, fire salts from the Ashlands. Know where each grows and you will never want."],
	["binding_soul", "Binding the Soul", "an Unbound mage", "Reedholm", "enchanting", "A soul trapped in a gem is a battery and a tool. Release it into steel and the steel burns, freezes, or drinks. The Guild forbids the binding of human souls. The Guild is timid."],
	["fog_papers", "The Fog-Engine Papers", "an elven engineer, translated", "Merewater", "", "The engine draws lake-water, warms it with a crystal of bound mist, and breathes it out over the city. With the crystal, the fog obeys. Without it, the fog breeds wraiths. Never run the engine without its crystal."],
	["sword_sands", "Sword of the Sands", "Swordmaster Idris Kael", "Sunhold", "one_handed", "The sword is a river, not a rock. Flow around the strike. Cut where the enemy is about to be. The Sandwalker forms are six; master the first before you dream of the sixth."],
	["quiet_step", "The Quiet Step", "a friend of the Thieves Guild", "Gullhaven", "sneak", "Walk on the outside of your feet. Breathe through your mouth. Never run on stone. Stay in the dark, and if someone looks your way, stay still. Most people see only what moves."],
	# ---- Folk tales and fiction
	["scarecrow_bride", "The Scarecrow's Bride", "a Wheatley folk tale", "Wheatley", "", "A scarecrow fell in love with the farm girl who sewed its buttons. Every night it walked to her window and watched her sleep. She married a miller. The scarecrow stands in the field still, guarding her grandchildren's grain."],
	["fox_moon", "The Fox Who Stole the Moon", "a Woodborn tale", "Fernhollow", "", "Fox wanted the moon for a lantern, so he asked it three riddles, and it could not answer the last. So Fox took the moon home in his tail. That is why his tail is golden, and why some nights there is no moon."],
	["saltbones_gull", "Saltbones and the Gull", "a book of sea shanties", "Gullhaven", "", "Oh Saltbones Maura, queen of the bay, she sank twelve ships on a Seedfall day, she kissed a gull and she drank the sea, and the Drowned King gave her the Isles for free!"],
	["goat_king", "The Goat King of Highpass", "a northern children's book", "Highpass", "", "The Goat King had a fleece of gold and horns like a castle. He stole every goat in Highpass and took them to a meadow in the sky. Little Kari climbed after him with a basket of turnips, and the Goat King, who loved turnips, gave her all the goats back."],
	["lady_nightglass", "Lady Nightglass", "a Kingsreach penny novel", "Kingsreach", "", "Countess Nightglass was as pale as moonlight and as cold as a winter river, and every man at the ball wished to dance with her. 'Why do you never eat, my lady?' asked young Lord Ashby. She smiled, showing teeth like pearls. 'Perhaps I am waiting for something sweeter.'"],
	["black_dog", "The Black Dog", "a Highland ghost story", "Heathwick", "", "Before every death in Heathwick, the black dog is seen at the end of the street. Most say it brings the death. The old ones say it guards against something worse, and that if you see it, you should thank it."],
	["knight_moon", "The Knight Who Loved the Moon", "a ballad", "Thornhaven", "", "Sir Aldred loved a lady of the wood who came to him only when the moon was full. He followed her one night and found a wolf at the pool. He laid down his sword. They say he runs with her still."],
	["cats_caravan", "Cats of the Caravan", "the poet Rhaz'ka", "Sunhold", "", "Sand in the fur, sand in the bread, sand in the boots and sand in the bed. Camels complain and the merchants all moan, but a Sandcat is never in sand: we're home."],
	# ---- Letters and notes
	["courier_letter", "A Courier's Last Letter", "a courier of the Dawn", "Kingsreach", "", "If I don't reach the temple, whoever finds this: the Ash Cult hunts a book called the Eclipse Codex. They mean to put out the sun. Warn the priests. Warn everyone."],
	["hierophant_orders", "Orders from the Hierophant", "the Ash Hierophant", "Cinderhold", "", "The Choir says wait. The Choir has waited fourteen hundred years. We will not. Find the Codex. The dark moon comes."],
	["brenna_letter", "To My Son, If I Fall", "Alpha Brenna Greyfang", "Fernhollow", "", "Ronan, if you are reading this, I did not find you in time. Lead them gently. Hunt, never murder. And forgive your cousin Fenris; he is only afraid."],
	["nyssa_orders", "Nyssa's Instructions", "Lady Mireille Morvaine", "Blackfen", "", "The collar will hold the wolf for one night. Let him be seen. Let him be Ashgrove's. When the prince falls, the regency war begins, and every side will need our help."],
	["treasurer_ious", "The Treasurer's IOUs", "Lord Treasurer Benedek Tidewell", "Saltmere", "", "I owe the Consortium four thousand crowns, and the dice house on Silver Street another nine hundred. If Isra finds out, she will have my seat. If the King finds out, he will have my head."],
	["miner_journal", "A Miner's Journal", "an Ironblood miner of Rustfield", "Rustfield", "", "Day forty. The deep shaft broke into a hall. Hot as a forge. There's an anvil there, black and cold, with old words on it. Gorrak says it's Korrund's own. Something moves in the fire."],
	["vizier_notes", "The Vizier's Mirror Notes", "the Vizier of Sunhold", "Sunhold", "", "A reflection is a door with a person on the other side. Trap the person behind the glass, step a shade into their place, and none but those who love them will notice. Love is the weakness of the method."],
	["watch_report", "Kingsreach Watch Report", "Watch Captain Bertil Ames", "Kingsreach", "", "Third week of Seedfall: counterfeit crowns found at four market stalls. Too light by a tenth. The trail leads underground, toward the old cisterns. Requesting more men."],
]


static func count() -> int:
	return LIST.size()


static func entry(id: String) -> Array:
	for e: Array in LIST:
		if e[0] == id:
			return e
	return []


## The books that sit on the shelves of a town
static func for_town(town_name: String) -> Array[String]:
	var out: Array[String] = []
	for e: Array in LIST:
		if e[3] == town_name:
			out.append(String(e[0]))
	return out


static func is_path(path: String) -> bool:
	return path.begins_with(PREFIX)


static func from_path(path: String) -> ItemData:
	return get_item(path.trim_prefix(PREFIX))


static var _items := {}


static func get_item(id: String) -> ItemData:
	if _items.has(id):
		return _items[id]
	var e := entry(id)
	if e.is_empty():
		return null
	var it := ItemData.new()
	it.id = StringName("lore_" + id)
	it.display_name = String(e[1])
	it.description = "By %s.%s" % [e[2], " A skill book." if String(e[4]) != "" else ""]
	it.item_type = ItemData.ItemType.BOOK
	it.weight = 1.0
	it.value = 40 if String(e[4]) == "" else 120
	it.set_meta("lore_id", id)
	it.set_meta("save_path", PREFIX + id)
	_items[id] = it
	return it


static func is_book(item: ItemData) -> bool:
	return item != null and item.has_meta("lore_id")


## Reads a book: its text, and the first time, its skill (Returns the text to show)
static func read(player: Node, item: ItemData) -> String:
	var id := String(item.get_meta("lore_id", ""))
	var e := entry(id)
	if e.is_empty():
		return ""
	if not WorldState.has_record(READ + id):
		WorldState.set_record(READ + id, {"read": true})
		var skill := String(e[4])
		var skills := player.get_node_or_null("Skills") as Skills if player != null else null
		if skill != "" and skills != null and SkillDatabase.get_skill(StringName(skill)) != null:
			skills.debug_level_up(StringName(skill))
			var def := SkillDatabase.get_skill(StringName(skill))
			Locks.toast(player.get_tree(), "Reading %s improves your %s" % [e[1], def.display_name])
	return String(e[5])
