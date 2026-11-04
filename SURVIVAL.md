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
