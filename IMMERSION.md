# Immersion (Alpha 1.24)

How the world gets on without you: who sides with whom, the wildlife, and people living their lives.

## Factions

Every creature and person belongs to a side, listed in `data/world/creature_factions.json`:

| Side | Who |
|---|---|
| bandits | bandits, thugs, cutthroats, raiders, deserters |
| smugglers | smugglers |
| undead | skeletons, wights, ghouls, drowned sailors, crypt wardens |
| vampires, werewolves | their own sides |
| cultists | the Ash Cult, marsh hags |
| beasts | wolves, bears, trolls, spiders, rats, scorpions, harpies, dragons |
| town | guards, townsfolk, merchants, pilgrims, hunters |
| livestock | sheep, cows, hounds |
| spirits, constructs, giants | fire and ice spirits; vault guardians; frost giants |

A creature not in the list is worked out from what it is (friendly folk: town; beasts: beasts; the rest:
bandits). An EnemyData file can name its side with **Faction**.

**How two sides get on** (the `relations` table; a pair not listed is neutral):

| Relation | Start a fight? | Hit by the other side |
|---|---|---|
| same side | never | forgiven (an accident) |
| friendly | never | forgiven, and they help each other |
| neutral | no | the one hit fights back its attacker, even after an accident |
| hostile | on sight | already fighting |

- Swings and area spells pass through their own side and friends. Anyone else in the way is hit, so a
  bandit swinging at you can catch the troll beside you, and the troll goes after the bandit.
- When one of a side is hit, the others within 16 m join in (friendly sides half the time).
- **Only your kills last.** One creature killed by another comes back when its place loads again, so the
  factions fighting never empty the world.
- **Your standing** with each side: killing one of its enemies +1, killing one of its own -6. At 25 a
  hostile side stops attacking you on sight (it still fights back if you start it). The guards' town is
  left to the law (bounty).
- **Battles you come across** (`CreatureBattles`): every 4-7 minutes outside, away from towns, two groups
  of sides at war meet out ahead of you: at the border between two places held by hostile sides, or on
  the land. Their dead come back too.
- Relations can change in a game: `CreatureFactions.set_relation("bandits", "beasts", Rel.HOSTILE)`
  (kept in the save).

Debug console:

    factions                  a label over every creature: its side, who it is fighting; your standing
    faction <a> <b> <rel>     make two sides friendly, neutral or hostile
    standing <faction> <n>    set your standing with a side
    battle [a] [b]            two hostile groups fighting 25 m ahead (default bandits and undead)

Not yet: wearing a side's gear as a disguise (comes with the disguise system), and sides patrolling the
land they hold.

## Wildlife

`data/world/wildlife.json` lists the animals of each land: weight, group size, day or night, the
seasons they are about, herd (the others follow a lead animal) or pack (the lead is a bigger alpha;
on the islands a named one). **WildLife** keeps up to 3 groups 90-170 m around you, out of sight,
and lets them go 320 m behind you.

- New animals: deer, elk, fox, boar, shore crab, ash beetle; the legends the White Stag, the Old
  Tusker and the Ancient Bear (one of each in a game; hunters spread a rumour when one is about;
  each drops a trophy worth a lot).
- Deer and elk (side "prey") run from you when you come within their notice (22 m; less sneaking;
  further when the wind carries your scent to them, and the wind turns through the day), and from
  any predator near them. Wolves, bears and the undead hunt them.
- Bears sleep through the winter. A den or nest you clear keeps predators off its land for a week.
- A wild beast that spots you from a way off stands and growls for a moment first: back away and it
  lets you go; come closer or hit it and it charges.

**AmbientLife** keeps up to 8 small creatures near you: rabbits, squirrels, frogs (more in the rain,
none in winter), birds by day, bats and owls at night, crows that come down to a body left out, and
fireflies on warm clear nights. A hit kills one (a rabbit leaves meat or hide).

The animals reuse the CC0 models in `assets/models/creatures` (a tinted horse for deer, a tinted
wolf for foxes, the rat for boars and rabbits, the spider for crabs and beetles, the bat for birds).
