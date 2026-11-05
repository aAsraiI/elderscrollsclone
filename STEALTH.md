# Alpha 1.29: Stealth, Thievery and Crime

## Pockets and locks (1.29.1)
- **Pickpocket** is a new Stealth skill.
- **Picking a pocket:**
  - Sneak up on someone who hasn't noticed you and press E (the prompt reads "Pick X's pockets"). Their pockets open in the container window.
  - Every take is a roll. You start at 55%. Your skill raises the chance; the weight and worth of what you take, and how aware they are, lower it. Sleepers are easy.
  - Fail and they feel it: the window closes, they turn on you, and it is reported as a crime.
  - What you take is marked stolen.
- **Milestones:** at 25 (Plant) you can slip things into pockets. At 100 (Master Thief) you can lift what they wear and wield.
- **Lockpicking minigame** (Settings > Interface, off by default):
  - Locks have 1–5 pins, more for harder locks. For each pin a marker sweeps along a bar; press E, Space or click while it is in the bright gap.
  - A miss breaks a pick and drops a pin.
  - Security widens the gap. Harder locks narrow it and move the marker faster.

## Light, noise and disguises (1.29.2)
- **Light gem:** a gem under the sneak eye shows how lit you are.
  - Your own lit lantern gives you away.
  - A full moon lights the night and a new moon hides you.
- **Noise:**
  - Heavy armour is louder, and it clanks even when you sneak.
  - Floors are loud indoors, and a town's cobbles are louder than grass and earth.
- **Disguises:**
  - The three disguises are Bandit Leathers, Ash Cult Robes and a Smuggler's Coat. A quarter of the bandits, cultists and smugglers you kill carry one.
  - Worn, that faction takes you for one of its own.
  - It ends early if one of them looks closely (within 3.5 m for 4 s) or you attack one. The whole faction is then on to you for two minutes.

## The law (1.29.3)
- **Bounty hunters:** once your bounties add up to 300 or more, a party comes for you in the wilds every couple of days. They never come in town, and there are more of them the higher your bounty.
- **Jail:**
  - Each day behind bars, one skill slips a level. If none is above its starting level, its progress toward the next level is lost instead.
  - Every other day, your cellmates teach you a level of Sneak, Security, Pickpocket, Hand to Hand or Speech.
- **Witnesses:** anyone who saw your crime has "keep quiet" topics.
  - *Bribe* costs gold, more for more crimes.
  - *Threaten* is a roll on Strength and Speech. If it fails they call the guard and your bounty goes up.
  - If it works, they forget, and the town's bounty drops.
- **Stolen goods** cool off after 7 days and stop being known as stolen.
- **Fences:** a fence launders everything you carry at once for a quarter of its worth ("launder stolen goods").

## Heists (1.29.4)
- **Getting the job:** Thieves Guild members ask the guild's fence (a city pawnbroker) about "a heist". The fence names a rich house: a noble seat, or the house with the hardest lock.
- **Inside:**
  - The house holds a Strongbox with the Heist Prize, by the bed furthest from the door.
  - Two Night Watchmen walk their rounds between the door and the box.
- **The payout:** back at the fence, "the heist" pays 600 + 12 per level. You get half if a watchman saw you inside.
  - It counts as a Thieves Guild job.
  - You can do one heist a day.

Every new system has a Guide page and achievements. Tests: `test/test_alpha129.gd`.
