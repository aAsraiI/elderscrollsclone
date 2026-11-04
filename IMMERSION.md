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
