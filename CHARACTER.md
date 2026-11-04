# Character building and leveling (Alpha 1.22)

How skills, levels, perks, feats and the level-up points work, and where to change them.

## No caps

- Skills and the player level have **no maximum**. Level 100 is where the last named milestone sits, not a wall.
- Skill XP per level: `10 + 4·L + 0.05·L²` (level 100 needs 910 XP, level 200 needs 2810).
- Player XP per level: up to 100 each level costs 25 more than the last; past 100 the step grows by 10 a level, so leveling slows but never stops.
- Small life skills (Swimming, Farming, Herbalism...) count less toward the player level (`SkillData.weight`), so having more skills does not make you level faster.

## What a skill gives

Every skill gives three kinds of bonus (`scripts/character/skill_database.gd`):

| Kind | When | Example (Athletics) |
|---|---|---|
| Passive | every 5 levels, forever (half as much past 100) | +1% movement speed, +4 max stamina |
| Milestones | levels **10, 25, 50, 75, 100** | 25 Long Stride: +3% speed · 100 Windrunner: +6% speed, +30% stamina regen |
| Mastery | every 25 levels past 100 (125, 150, ...) | +1% speed, +10 stamina |

Some skills only count in the right situation (the Stats screen says which, in green when it is on):
weapon skills with that weapon in hand, Hand-to-Hand with empty hands, Unarmored with no armor on,
Dual Wielding with a weapon in each hand.

Rank names: Novice, Apprentice (10), Journeyman (25), Adept (50), Expert (75), Master (100),
Grandmaster (150), Legend (200), Mythic (300), Ascendant (500).

## The skills (34)

| Group | Skills |
|---|---|
| Weapons | One-Handed, Two-Handed, Archery, **Hand-to-Hand**, **Dual Wielding** |
| Defense | Heavy Armor, Light Armor, Block, **Unarmored** |
| Magic | Destruction, Restoration, Alteration, Conjuration, Illusion, Mysticism |
| Stealth | Sneak, Security |
| Movement | Athletics (speed), **Acrobatics** (jump height, less falling damage), **Swimming**, **Riding** |
| Social | Speech (persuasion), **Mercantile** (prices), **Leadership** (followers and summons), **Devotion** (shrines, the undead), **Lore** (books, places, faster learning) |
| Crafting | Smithing, Alchemy, Enchanting, Tinkering, Cooking |
| Wilderness | **Survival**, **Hunting**, **Herbalism**, **Mining**, **Farming**, **Medicine** |

How the new ones train:

| Skill | Trains by |
|---|---|
| Acrobatics | jumping, landing from falls (Athletics now trains only by sprinting) |
| Hand-to-Hand | hitting with bare hands |
| Dual Wielding | hitting with a weapon in each hand |
| Unarmored | taking hits with no armor on |
| Swimming / Riding | swimming / riding a horse |
| Mercantile | buying and selling (Speech now trains by persuasion) |
| Leadership | your followers and summons fighting |
| Devotion | praying at shrines, killing the undead |
| Lore | reading a lorebook for the first time, discovering places |
| Survival | time in the wild, far from towns |
| Hunting | killing beasts |
| Herbalism / Mining / Farming | picking herbs / mining ore / planting and harvesting |
| Medicine | healing yourself with potions and food while hurt |

Your class's **major** skills learn 20% faster, **minor** skills 10%, and your **specialization**'s group 15%.

## Level-up points (CharacterBuild)

Every player level gives **1 perk point, 1 attribute point (+2) and 1 vital point (+10 health, magicka or stamina)**.
Levels 10, 25, 50, 75, 100 and every 25 after give a **feat point**. Spend them on the Character screen (C):

- **Perks** tab: 8 trees (Warrior, Guardian, Marksman, Spellcaster, Shadow, Wanderer, Artisan, Leader), ~95 perks.
  Many have ranks; a rank needs a player level, some need a skill level or another perk.
  Each tree ends in an unlimited "Paragon" perk so a point is never wasted.
- **Feats** (top of the Perks tab): 33 strong, build-defining choices, some with a price
  (Juggernaut is slower, Glass Cannon is frail). Feats unlock at levels 10, 25, 50, 75, 100, 125, 150, 175 and 200.
- **Level Up** tab: spend attribute and vital points, see your build name (Spellsword, Nightblade, Ranger...)
  and best skills, and **Start over** (undo every perk, feat and point for 50 gold per level).

Points are worked out from your level, so they can never get out of step: what you have = what your level earned − what you spent.

Every attribute now does something: Strength (carry weight, damage), Agility (speed, crits),
Endurance (health, stamina), Wisdom (magicka, regen), Stealth (sneak attacks, noise), Charisma (prices, persuasion).

## Character creation

New on the Traits page of the new-game wizard:

- **Specialization**: Combat, Defense, Magic, Stealth, Movement, Social, Crafting or Wilderness (+15% XP for that group).
- **Background**: Soldier, Scholar, Street Urchin, Farmhand, Noble, Sailor, Hermit, Acolyte, Hunter's Child, Miner, Performer, Squire
  (a few skill levels, a lasting trait, gold and items).
- Six new classes: Monk, Scout, Crusader, Trader, Druid, Duelist.
- World option **Falling damage** (on by default).

## New stats and who reads them

All in `Stats.DEFAULT_BASE_STATS`; the rules live in `scripts/character/build_hooks.gd`.

| Stat | Effect |
|---|---|
| crit_chance / crit_mult | player hits (melee, arrows) can crit: big yellow "CRIT" number |
| power_attack_pct | heavy attacks hit harder |
| attack_cost_mult / block_cost_mult | stamina per swing / per blocked hit |
| armor_pen | ignore part of the foe's armor |
| damage_reduction | less damage from everything (max 75%) |
| execute_bonus | more damage to foes under 30% health |
| life_leech | melee damage heals you |
| poise_bonus | your hits stagger sooner |
| bow_damage | arrows hit harder |
| fall_resist | less falling damage |
| swim_speed_mult, breath_mult | swimming |
| horse_speed_mult, horse_stamina_mult, mounted_damage | riding |
| sneak_speed_mult | speed while sneaking |
| magicka_cost_mult, cost_&lt;school&gt; | spell cost |
| potion_mult | healing and restoring from potions and food |
| hunger_mult | hunger and tiredness (Survival mode) |
| harvest_bonus, mining_bonus, gem_find, farming_bonus, crop_growth | gathering |
| follower_damage, follower_health | followers and summons |
| persuade_bonus | persuasion chance |
| blessing_mult | shrine blessings |

## Levels 100-200: the islands

- The five outer islands are now levels **100-200**: Greenisle 100-120, Saltmarsh Isles 110-138,
  Sunreach 120-158, Isle of Cinders 150-185, Frosthold 165-200. Ship destinations show the level of the land.
- Four new gear tiers: **Voidsteel** (100), **Sunsteel** (125), **Astral** (150), **Primordial** (175),
  heavy and light (Voidweave, Sunsilk, Astralweave, Primeweave), every weapon, shield, bow and arrow.
  Island ores (void, sun, astral, primordial) are mined there, smelted and forged (Smithing 105-180).
- Voidstone (100) and Starstone (150) jewelry, Supreme potions, the Elixir of the Ancients, 8 island relics.
- 15 **legendary uniques** (orange names) that turn up very rarely in high-level chests, e.g. Worldsplitter,
  Starfall, Heartseeker, Boots of the Endless Road, Amulet of Ages.
- Spawn tables and room modules with a top level of 100 now mean "no top", so creatures and rooms keep appearing past 100.
- Items are made by `tools/generate_alpha122.gd` (run it headless like the other generators).

## Adding things

- **A skill**: add a `_add(SkillData.new(...))` block in `skill_database.gd` with `.effect`, `.at(10/25/50/75/100, ...)` and `.mastered`. Train it with `skills.add_xp(&"id", amount)` (or `BuildHooks.train(get_tree(), &"id", amount)`).
- **A perk or feat**: one `_p(...)` / `_f(...)` line in `scripts/character/perk_database.gd`.
- **A new stat**: add it to `Stats.DEFAULT_BASE_STATS`, make the system that should feel it read `stats.get_stat("...")`, and give it a label in `SkillData.LABELS`.

## Console (debug builds)

`setskill <skill> <level>` puts a skill straight at a level · `perkpoints [n]` gives perk points · `level [n]` raises every skill.

## Tests

`test/test_alpha122.gd` checks the tables, no cap, milestones, the new skills' effects, perks/feats/points/respec, creation choices, island levels and the island gear.
