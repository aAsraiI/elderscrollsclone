# Alpha 1.26: Dungeons, Roads and Talk

## Dungeons (1.26.1)
- **Bosses fight with a trick** (`scripts/dungeons/boss_mechanics.gd`):
  - Necromancers, priests and wight lords raise the dead every 14 s. Below a third of their health the power fails.
  - Trolls regrow 2% a second unless fire touched them in the last 6 s.
  - Crawler queens and giant spiders bring out their brood.
  - Every other boss becomes enraged when badly hurt.
- **Tells:** sneak (or have Security 25) and you see a trap's pressure plate. Lore or Security 25, or sneaking, shows a loose stone where a secret door is.
- **Gas explodes:** fire in a gas cloud sets it off, for good.
- **Deeper floors are darker.**
- **Rare events (12% a week per dungeon):**
  - A lost adventurer follows you out and pays at the door.
  - Rival delvers got there first.
  - A pedlar has set up shop.

## Roads (1.26.2)
- **Road events** (`scripts/world/road_events.gd`) are staged 70–120 m ahead of you, one at a time:
  - **Highwaymen** block the road. Talk to the leader:
    - *pay the toll* and they let you by.
    - *refuse the toll* tries an Intimidate check. The answer shows the chance (Strength, Speech, level).
    - Walk through without a word and they draw steel.
  - **Beset traveller:** someone fighting wolves. Kill the wolves and they pay you.
  - **Ambush (night only):** bandits wait off the road and rise when you come within 16 m.
  - **Wreck:** a stranded carter. Bring 2 firewood (or 1 firewood and 2 plant fibre) for pay and a tip, which marks an unfound dungeon on your map.
- **Wayside inns:** the keeper sells food and drink (innkeeper shop), and there is a straw bed for 10 gold a night.
- **Fast travel:**
  - New world-creation option *Towns and inns only*.
  - A long trip into the wild may be waylaid: an ambush when you arrive, with a chance of 3% per hour of travel (at most 30%).

## Talk (1.26.3)
- **Who you are:** about a third of people add a line about your race, class or background to their greeting.
- **Lying:** anyone who remembers seeing you steal, assault or trespass has *what you saw*.
  - The chance comes from Speech, charisma, disposition and personality, and the answer shows it.
  - Believed: they forget it.
  - Not believed: −10 disposition and a 20 gold bounty.
  - One try a day.
- **Vows:** priests have *take a vow* (peace or poverty) and later *my vow*.
  - Keep it three days for a blessing (+25 health and magicka for an hour) and Devotion.
  - Break it and it is gone.
- **Courting:** anyone you could marry who likes you 60+ has *spend time together*, once a day (+6 disposition). After three days they will marry you at 65 instead of 80.
- **Leads:** *latest rumors* sometimes ends with a treasure lead. The dungeon goes on your map and in the journal, and the treasure is in its boss chest.
- **Alternate starts** (world creation, *Start*):
  - Outside a town gate
  - At a wayside inn
  - Shipwrecked on a shore (wet through, with a journal entry)
  - Alone in the wilds
- Persuasion buttons already show their chance. Lie and Intimidate answers now show theirs too.

Tests: `test/test_alpha126.gd`.

## World settings (1.26.4)
- **Presets** on World Creation: Story, Adventurer, Survivor and Hardcore. Each sets the options below, and you can still change any of them afterwards.
- **When you die** (`scripts/core/death_rules.gd`):
  - *Reload a save* (the old way).
  - *Lose some gold:* a quarter of it, and you wake at the nearest town.
  - *Leave a grave:* everything you carried but didn't wear stays in a marked grave where you fell (at the door if you fell in a dungeon), saved until you empty it. You wake at the nearest town.
  - Ironman is still permadeath.
- **Creatures** slider: scales dungeon rooms, wild animal groups and encounter caps.
- **Dungeons fill again after** slider: 3–90 days (21 by default).
- **Raids and hordes** slider: 0 turns them off. Higher values mean shorter gaps between raids and bigger blood-moon hordes.
