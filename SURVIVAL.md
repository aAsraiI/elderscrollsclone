# Survival (Alpha 1.25)

What the survival sandbox adds, on top of the Survival mode that was there before (hunger, fatigue and
cold, World Creation option). Test suite: `test/test_alpha125.gd`.

## The body (1.25.1)

- **Meals as buffs** (with or without Survival mode): eating gives a buff to max health and max stamina
  for a while. Better food, better cooks (Cooking) and cooked dishes give bigger, longer buffs (1 to 8
  hours). Three meals at most: a fourth pushes out the oldest; the same dish again just refreshes it.
- **Heat**: deserts and summer middays heat you, more in heavy armour or furs; water and wet clothes cool
  you. Warm, Hot, Heatstroke (which hurts).
- **Wet**: swimming soaks you, rain wets you, you dry off in the dry and fast by a fire. Damp, Wet,
  Soaked: wet clothes chill you and tire you.
- **Fires**: a campfire, hearth, brazier, forge or a fire on the ground within 5 m keeps the cold off and
  dries you (group `heat_sources`).
- **Clothing warmth**: each piece has its own warmth: furs, pelts and wool the most, plate more than
  leather, linen and robes little (and they keep you cooler).
- **Tiredness**: weary and exhausted, your skills improve more slowly.
- **Comfort**: sleeping in a house or inn, by a fire, among furnishings makes your Well Rested longer
  (4 to 12 hours) and stronger.

## Gathering and tools (1.25.2)

- **Things to gather** on every stretch of land, a few per 64 m: rocks (stone, sometimes flint: needs any
  pickaxe), fallen branches (firewood), fibre plants (plant fibre) and clay at the water's edge. E gathers;
  they grow back in two or three days. New materials: Stone, Flint, Firewood, Plant Fibre, Clay.
- **Pickaxe tiers**: Stone Pickaxe (stone, firewood and fibre at a workbench), Pickaxe (iron), Steel, Ebon,
  Astral (at the forge). Iron and corundum need any pick; silver and gold an iron one; obsidian and
  ebony steel; dragonstone and star-metal ebon; the island ores astral. Your best pick in the pack counts.
- **Rope** from plant fibre at a workbench.
- **Salvage** (a new tab at the forge): break weapons and armour down for their ingots or leather, and a
  strip of leather. Not what you are wearing, and not legendaries.
- **Recipes you discover**: a crafting recipe shows once you have held everything it needs (whatever is
  in your pack counts the moment you open a station).

## Settlers and taming (1.25.3)

- **Settlers** (needs a homestead): free a prisoner from a dungeon's cells, or ask a traveller on the road
  about **a place to live**, and they come to live there. Room: the hall sleeps one, a bedroom two, the
  storeroom and the garden one each.
- **Work**: farmer (vegetables), hunter (meat, hides), woodcutter (firewood), guard (fewer raids), smith
  (now and then an ingot). Ask your steward for **the settlers' goods**.
- **Needs and moods**: each day everyone eats; farmers, hunters and the garden feed the household. Short of
  food, short of beds, or after a raid their mood falls; fed and housed it rises. Below 15 they pack up
  and leave (the journal says why). Unhappy settlers do half the work.
- You find them about the plot when you are near it.
- **Taming**: walk up to a calm wolf, boar, fox, bear, hound, rat or stalker with raw meat and press E.
  It eats from your hand, and sometimes (better with Hunting and Survival) it becomes yours: it follows you
  like a companion and is saved with your game. Fail and it may turn on you. Two beasts at most.

## Raids and the blood moon (1.25.4)

- **Raids**: a homestead with three parts or two settlers draws raiders every week or two: the hostile side
  nearest it. Word comes a day ahead (the journal). Be there after dark and they come (your guards fight
  with you); be away and your guards hold them off or not: a lost raid empties the settlers' store and
  frightens them.
- **The blood moon** (Interface > Blood moon, on by default): on the last night of every month the moon
  rises red, and the dead come at the gates of the towns near you and at your homestead.

## Rafts and breath (1.25.5)

- **Raft Kit** (8 firewood and 2 rope at a workbench): use it facing open water at its edge and it
  becomes a raft: slower than a rowboat and no sail, but yours and anywhere. It is your boat from then
  on (saved like one).
- **Air Bladder** (a hide and fibre at a tanning rack): use it under water for 20 more seconds of breath.
