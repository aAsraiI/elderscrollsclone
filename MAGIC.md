# Alpha 1.28: Magic

## Spells, scrolls, flying and water (1.28.1)
- **Island ranks:** every school has two new ranks above Master:
  - **Grandmaster** (level 100): Meteor, Glacial Lance, Radiant Healing, Aegis, Starflesh, Time Slip, Dread Legion, Eternal Blade, Dominion, Veil of Night, Soul Rend and Spellbreaker.
  - **Ascendant** (level 150): Sunfire, Thunderstorm, Resurgence, Sanctuary, Astral Flesh, Stasis, Sovereign of the Dead, Conjure Elder Troll, Madness, Dread, Void Drain and Mirror of Ages.
  - Their tomes are sold only by Mages Guild shops on the far islands, and turn up in island vaults.
- **Levitate** (Alteration, Expert):
  - Double-tap Space to lift off or land. Space rises, Ctrl sinks.
  - It is slower than flying in the debug console.
  - Town wards pull you down.
- **Water Walking** (Alteration, Adept): walk across lakes and the sea.
- **Scrolls:** read one from the inventory and it casts its spell once, for free, whatever your skill. There are 15, from Healing Hands to Stasis, found in mage loot, libraries and vaults.

## Combos, wards and resistances (1.28.2)
- **Combos:** hit the same foe with two different elements within 4 s.

  | First, then | Combo | Effect |
  |---|---|---|
  | fire, frost (either order) | Thermal Shock | x1.5 |
  | frost, shock | Shatter | x1.4 and a stagger |
  | shock, frost | Conduction | x1.3 |
  | shock, fire | Overload | a burst that hits everyone within 4 m for 40% |
  | poison, fire (either order) | Ignite | x1.5 |

- **Wards** (Lesser, Steadfast and Greater, in Mysticism):
  - They soak up spell harm until the pool runs dry, then break.
  - Every point soaked trains Mysticism.
- **Counterspell** (Mysticism): the target can't cast spells for 8 s.
- **Health bars** show what a creature is immune to, resists, or is weak to.

## Rituals and research (1.28.3)
- **Ritual books** (Mages Guild halls, level 20+):
  - **Call the Storm:** a thunderstorm, with lightning on every foe within 40 m.
  - **Raise the Fallen:** every body within 20 m fights for you for 3 minutes.
  - **Dawn's Blessing:** +25% health, magicka and stamina.
  - **Ward of Ages:** a 400-point ward on you and your followers.
- **Performing one:**
  - Stand in a ritual circle. Ritual Chalk draws one, and an Altar of Spellmaking counts as one.
  - Use the book. It takes 6 s of standing still, 120 magicka and a filled soul gem. The book is kept.
  - Moving or getting hurt breaks the ritual.
- **Research:** Mages Guild members can ask a guild mage about "magical research".
  - For gold and a day, the guild works out a spell effect you don't know yet.
  - You can then use that effect at the Altar of Spellmaking.

## The shapeshifters (1.28.4)
- **Vampire tree:** Unholy Vigor, Blood Strength, Night Stalker, Cold Blood, Mistwalker, Drain Mastery, Dark Gift and Vampire Lord.
- **Werewolf tree:** Feral, Thick Hide, The Hunt, Frenzy, Regrowth, Terrible Howl and Alpha.
- **How they work:**
  - Both trees are bought with blood points: one per feeding, or one per body devoured.
  - They show on the Perks tab only while you carry the curse.
  - A vampire's perks always work. A werewolf's work only in beast form.

## The Patrons (1.28.5)
- **The eight Patrons:** Vael, Morrowgast, Ilsira, Kharn, Sythara, Dorun, the Hollow Choir and Mother Thornwood. Each glowing shrine in the wilds is sacred to one of them.
- **Their deeds:** kneel (E) and the Patron asks a deed:
  - cast 40 spells
  - kill 30 foes
  - pick 12 locks
  - parry 15 blows
  - set off 5 combos
  - gather 40 times
  - strike unseen 12 times
  - kill 20 beasts
- **Their gifts:** do the deed, kneel again at any of that Patron's shrines, and its artifact is yours: Emberheart, Rotfang, Moonveil Cowl, Maul of the Unbroken, Loom of Sythara, Heart of the Deep, Whisper of the Choir and Thornmother's Band.
- Each Patron answers only from a certain level (10 to 22).

Every new system has a Guide page and achievements. Tests: `test/test_alpha128.gd`.
