#!/usr/bin/env python3
"""Generates the game's content files (.tres) from the tables below.

  python3 tools/generate_content.py [project_root]

project_root is the folder that contains scripts/ (default: the folder above this tool).
It writes:
  scripts/Resources/Weapons/    7 tiers of sword, dagger, greatsword, warhammer, shield and armor
  scripts/Resources/Enemies/    every EnemyData (bandits, wolves, skeletons, bosses, NPCs)
  scripts/Resources/Spawns/     SpawnTables (garrisons, dungeon rooms, encounters)
  scripts/Resources/Encounters/ EncounterData (random events)
and hooks them up by adding lines to the existing biome, point-of-interest and dungeon files
(only if they are not hooked up yet, so running it twice is safe).
Everything it makes can be edited by hand afterwards in the Godot inspector.
To rebalance: change the numbers here and run it again (it overwrites the files it owns).
"""
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RES = os.path.join(ROOT, "scripts", "Resources")

ITEM_SCRIPT_UID = "uid://dd71arb7pvb2r"   # ItemData.gd in the project

# ------------------------------------------------------------------ the level curve (tiers)
TIER_KEYS = ["iron", "steel", "silver", "obsidian", "ebon", "dragonbone", "starforged"]
TIER_NAMES = ["Iron", "Steel", "Silver", "Obsidian", "Ebon", "Dragonbone", "Starforged"]
TIER_MIN_LEVEL = [1, 6, 12, 18, 25, 33, 42]
DAMAGE_MULT = [1.0, 1.5, 2.1, 2.9, 3.9, 5.2, 6.8]
VALUE_MULT = [1, 2.5, 6, 14, 32, 75, 170]
WEIGHT_MULT = [1.0, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25]
POISE_MULT = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6]
STAMINA_MULT = [1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3]
SHIELD_ARMOR = [10, 13, 17, 21, 26, 31, 37]
CHEST_ARMOR = [25, 33, 42, 52, 62, 71, 78]
TIER_FLAVOR = [
    "Plain, sturdy iron.",
    "Well-forged steel with a keen edge.",
    "Silvered steel that gleams even in the dark.",
    "Volcanic glass ground to a razor edge, tougher than it looks.",
    "Blackened ebon steel, cold to the touch.",
    "Carved from the bones of great wyrms.",
    "Forged from fallen star-metal that hums faintly.",
]

# Iron-tier numbers. Everything else is scaled from these by the tier tables above.
WEAPONS = {
    "sword": dict(
        name="Sword", desc="A balanced blade. Swings in an arc and can hit several enemies. Tap to chain a combo, hold to charge a heavy attack.",
        item_type=1, slot=6, weight=5.0, value=25, skill="one_handed", aset="sword",
        damage=10.0, reach=2.2, style=1, arc=100.0, cooldown=0.7, windup=0.12, active=0.14,
        stamina=6.0, knock=2.5, poise=15.0, combo=3,
        heavy=(0.45, 0.18, 1.7, 2.0, 2.0, 0.3)),
    "dagger": dict(
        name="Dagger", desc="Quick and light. Carry two and wield one in each hand. Low stagger, but long combos.",
        item_type=1, slot=6, weight=1.5, value=15, skill="one_handed", aset="dagger",
        damage=6.0, reach=1.6, style=0, cooldown=0.35, windup=0.05, active=0.12,
        stamina=3.0, knock=1.0, poise=8.0, combo=4, dual=True,
        heavy=(0.4, 0.12, 1.5, 2.0, 1.5, 0.2)),
    "greatsword": dict(
        name="Greatsword", desc="Two-handed. Slow, with a long reach and a wide swing. One clean hit staggers most foes.",
        item_type=1, slot=6, weight=14.0, value=70, skill="two_handed", aset="greatsword",
        damage=18.0, reach=3.2, style=1, arc=130.0, cooldown=1.4, windup=0.35, active=0.22,
        stamina=14.0, knock=4.0, poise=40.0, combo=2, two_handed=True,
        heavy=(0.6, 0.25, 1.7, 2.0, 1.6, 0.4)),
    "warhammer": dict(
        name="Warhammer", desc="Two-handed. Strikes one target and staggers hard. Right click to slam the ground and hurt everything nearby.",
        item_type=1, slot=6, weight=18.0, value=60, skill="two_handed", aset="hammer",
        damage=16.0, reach=2.4, style=0, cooldown=1.1, windup=0.3, active=0.16,
        stamina=12.0, knock=5.0, poise=35.0, combo=2, two_handed=True,
        heavy=(0.55, 0.22, 1.8, 2.0, 1.8, 0.3),
        slam=dict(cooldown=4.0, windup=0.5, stamina=25.0, mult=1.6, radius=3.5)),
}

# Items that already exist in the project keep their file names (other files point at them)
LEGACY = {
    "iron_sword": "iron_sword.tres", "iron_dagger": "iron_dagger.tres", "iron_warhammer": "iron_warhammer.tres",
    "iron_shield": "iron_shield.tres", "iron_chestplate": "iron_chestplate.tres", "steel_greatsword": "steel_greatsword.tres",
}
LEGACY_UID = {"iron_sword": "uid://ccs0i8i2yls70", "iron_chestplate": "uid://bu7yro4jl28nt"}


def f(x):
    """A float the way Godot writes it"""
    x = round(float(x), 2)
    return str(int(x)) + ".0" if x == int(x) else str(x)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as fh:
        fh.write(text)


def item_path(tier, kind):
    key = "%s_%s" % (TIER_KEYS[tier], kind)
    if key in LEGACY:
        return key, os.path.join(RES, LEGACY[key])
    return key, os.path.join(RES, "Weapons", key + ".tres")


def item_file(key, lines):
    uid = LEGACY_UID.get(key)
    head = '[gd_resource type="Resource" script_class="ItemData" format=3%s]' % (' uid="%s"' % uid if uid else "")
    return "\n".join([head, "",
                      '[ext_resource type="Script" uid="%s" path="res://scripts/ItemData.gd" id="1_item"]' % ITEM_SCRIPT_UID, "",
                      "[resource]", 'script = ExtResource("1_item")'] + lines + ['metadata/_custom_type_script = "%s"' % ITEM_SCRIPT_UID, ""])


def weapon_item(kind, tier):
    w = WEAPONS[kind]
    key, path = item_path(tier, kind)
    hc, hw, hd, hs, hp, hr = w["heavy"]
    L = [
        'display_name = "%s %s"' % (TIER_NAMES[tier], w["name"]),
        'description = "%s %s"' % (TIER_FLAVOR[tier], w["desc"]),
        "item_type = %d" % w["item_type"], "equip_slot = %d" % w["slot"],
        "weight = %s" % f(w["weight"] * WEIGHT_MULT[tier]), "value = %d" % round(w["value"] * VALUE_MULT[tier]),
        'governing_skill = "%s"' % w["skill"],
        "tier = %d" % (tier + 1), "min_level = %d" % TIER_MIN_LEVEL[tier],
        "weapon_damage = %s" % f(w["damage"] * DAMAGE_MULT[tier]),
        "reach = %s" % f(w["reach"]), "attack_style = %d" % w["style"],
    ]
    if w["style"] == 1:
        L.append("arc_degrees = %s" % f(w["arc"]))
    L += [
        "attack_cooldown = %s" % f(w["cooldown"]), "attack_windup = %s" % f(w["windup"]), "attack_active = %s" % f(w["active"]),
        "stamina_cost = %s" % f(w["stamina"] * STAMINA_MULT[tier]),
        "knockback = %s" % f(w["knock"] * (1 + 0.05 * tier)),
        "poise_damage = %s" % f(w["poise"] * POISE_MULT[tier]),
        "combo_length = %d" % w["combo"],
    ]
    if w.get("two_handed"):
        L.append("two_handed = true")
    if w.get("dual"):
        L.append("can_dual_wield = true")
    L += ["heavy_charge_time = %s" % f(hc), "heavy_windup = %s" % f(hw), "heavy_damage_mult = %s" % f(hd),
          "heavy_stamina_mult = %s" % f(hs), "heavy_poise_mult = %s" % f(hp), "heavy_reach_bonus = %s" % f(hr)]
    if "slam" in w:
        s = w["slam"]
        L += ["secondary_action = 2", "secondary_cooldown = %s" % f(s["cooldown"]), "secondary_windup = %s" % f(s["windup"]),
              "secondary_stamina_cost = %s" % f(s["stamina"]), "secondary_damage_mult = %s" % f(s["mult"]),
              "secondary_radius = %s" % f(s["radius"])]
    L.append('animation_set = &"%s"' % w["aset"])
    write(path, item_file(key, L))


def shield_item(tier):
    key, path = item_path(tier, "shield")
    L = [
        'display_name = "%s Shield"' % TIER_NAMES[tier],
        'description = "%s Hold right click to block. Raise it just before a hit lands to parry. Left click while blocking to bash."' % TIER_FLAVOR[tier],
        "item_type = 2", "equip_slot = 7", "weight = %s" % f(8.0 * WEIGHT_MULT[tier]), "value = %d" % round(30 * VALUE_MULT[tier]),
        'governing_skill = "block"', "tier = %d" % (tier + 1), "min_level = %d" % TIER_MIN_LEVEL[tier],
        "stat_modifiers = {\n\"armor\": %s\n}" % f(SHIELD_ARMOR[tier]),
        "secondary_action = 1", "block_reduction = %s" % f(0.6 + 0.02 * tier), "block_angle = 120.0", "parry_window = 0.2",
        "bash_damage = %s" % f(3.0 * DAMAGE_MULT[tier]), "bash_poise = %s" % f(30.0 * POISE_MULT[tier]), "bash_stamina_cost = 8.0",
        'animation_set = &"shield"',
    ]
    write(path, item_file(key, L))


def chest_item(tier):
    key, path = item_path(tier, "chestplate")
    L = [
        'display_name = "%s Armor"' % TIER_NAMES[tier],
        'description = "%s Heavy armor for the chest."' % TIER_FLAVOR[tier],
        "item_type = 2", "equip_slot = 2", "weight = %s" % f(15.0 * WEIGHT_MULT[tier]), "value = %d" % round(40 * VALUE_MULT[tier]),
        'governing_skill = "heavy_armor"', "tier = %d" % (tier + 1), "min_level = %d" % TIER_MIN_LEVEL[tier],
        "stat_modifiers = {\n\"armor\": %s\n}" % f(CHEST_ARMOR[tier]),
    ]
    write(path, item_file(key, L))


# ------------------------------------------------------------------ creatures
# kit: 0 unarmed, 1 sword, 2 sword+shield, 3 dagger, 4 two daggers, 5 greatsword, 6 warhammer
# disposition: 0 hostile, 1 neutral, 2 friendly
H, N, F = 0, 1, 2
ENEMY_DEFAULTS = dict(disposition=H, color=(0.7, 0.2, 0.2), scale=1.0, health=1.0, damage=1.0, poise=1.0, loot=1.0,
                      weapon_tier=0, armor_tier=-1, kit=1, speed=3.2, detect=14.0, telegraph=0.3, heavy=0.2, chain=0.3,
                      pause_min=0.3, pause_max=1.0, kb_res=0.0, wander=0.0, lines=[])
ENEMIES = {
    # --- bandits and raiders
    "bandit": dict(name="Bandit", color=(0.62, 0.22, 0.18), kit=1),
    "bandit_thug": dict(name="Bandit Thug", color=(0.55, 0.30, 0.20), kit=2, health=1.25, damage=0.9, poise=1.2, armor_tier=0),
    "bandit_brute": dict(name="Bandit Brute", color=(0.50, 0.15, 0.15), kit=5, health=1.7, poise=1.8, scale=1.15, speed=2.8,
                         telegraph=0.45, heavy=0.4, chain=0.1, armor_tier=0, loot=1.3),
    "cutthroat": dict(name="Cutthroat", color=(0.40, 0.25, 0.35), kit=4, health=0.8, damage=0.9, poise=0.7, speed=4.0,
                      telegraph=0.18, heavy=0.05, chain=0.7, pause_min=0.15, pause_max=0.5, armor_tier=-2),
    "raider": dict(name="Desert Raider", color=(0.75, 0.55, 0.25), kit=1, health=1.1, detect=16.0),
    "raider_marauder": dict(name="Raider Marauder", color=(0.70, 0.40, 0.20), kit=6, health=1.6, poise=1.6, scale=1.1,
                            speed=2.9, telegraph=0.5, heavy=0.35, chain=0.1, armor_tier=0, loot=1.3),
    "frost_raider": dict(name="Frost Raider", color=(0.50, 0.60, 0.75), kit=2, health=1.3, poise=1.2, armor_tier=0),
    "reaver": dict(name="Mountain Reaver", color=(0.40, 0.45, 0.60), kit=5, health=1.5, poise=1.6, scale=1.1, speed=3.0,
                   telegraph=0.45, heavy=0.35, chain=0.15, armor_tier=0, kb_res=0.2, loot=1.3),
    # --- beasts (no weapon: their damage comes from the level curve)
    "wolf": dict(name="Wolf", color=(0.45, 0.45, 0.48), kit=0, health=0.6, poise=0.5, scale=0.75, speed=5.2, detect=18.0,
                 telegraph=0.12, heavy=0.0, chain=0.6, pause_min=0.2, pause_max=0.7, armor_tier=-9, loot=0.0),
    "dune_stalker": dict(name="Dune Stalker", color=(0.80, 0.65, 0.40), kit=0, health=0.9, poise=0.7, scale=0.85, speed=4.8,
                         detect=18.0, telegraph=0.15, heavy=0.0, chain=0.5, pause_min=0.2, pause_max=0.8, armor_tier=-9, loot=0.0),
    "frost_bear": dict(name="Frost Bear", color=(0.88, 0.90, 0.95), kit=0, health=2.2, damage=1.4, poise=2.5, scale=1.3,
                       speed=3.6, telegraph=0.5, heavy=0.35, chain=0.2, kb_res=0.4, armor_tier=-9, loot=0.0),
    "cave_dweller": dict(name="Cave Dweller", color=(0.35, 0.40, 0.30), kit=0, health=1.0, poise=0.9, scale=0.9, speed=3.5,
                         telegraph=0.25, heavy=0.1, chain=0.5, armor_tier=-9, loot=0.0),
    # --- the dead
    "skeleton": dict(name="Skeleton", color=(0.85, 0.84, 0.78), kit=1, health=0.9, armor_tier=-2),
    "skeleton_knight": dict(name="Skeleton Knight", color=(0.70, 0.72, 0.78), kit=2, health=1.3, poise=1.3, armor_tier=0),
    # --- bosses
    "crypt_warden": dict(name="Crypt Warden", color=(0.50, 0.55, 0.80), kit=5, health=5.0, damage=1.2, poise=3.0, scale=1.35,
                         speed=3.0, telegraph=0.5, heavy=0.35, chain=0.2, kb_res=0.6, armor_tier=1, loot=2.5),
    "cave_troll": dict(name="Cave Troll", color=(0.35, 0.50, 0.35), kit=0, health=5.5, damage=1.5, poise=3.0, scale=1.5,
                       speed=3.0, telegraph=0.55, heavy=0.4, chain=0.2, kb_res=0.6, armor_tier=-9, loot=0.0),
    # --- NPCs
    "wanderer": dict(name="Wanderer", disposition=F, color=(0.30, 0.55, 0.75), kit=3, health=0.8, wander=14.0, armor_tier=-9,
                     lines=["Safe travels, friend. The roads are not what they were.",
                            "Bandits have been seen near the old camps. Keep your blade close.",
                            "Fine weather for walking, if you don't mind the company of wolves."]),
    "pilgrim": dict(name="Pilgrim", disposition=F, color=(0.92, 0.88, 0.62), kit=0, health=0.7, wander=6.0, armor_tier=-9, loot=0.0,
                    lines=["The shrines remember those who come in peace.",
                           "I walk from shrine to shrine. Each one hums a different note.",
                           "Mind the ruins at night. Not everything buried stays buried."]),
    "merchant": dict(name="Merchant", disposition=F, color=(0.85, 0.70, 0.20), kit=3, health=1.0, wander=5.0, armor_tier=-9,
                     lines=["Fine wares, fair prices... when the road lets me reach a town.",
                            "I would sell you something, but my cart has seen better days. Another time?"]),
    "hunter": dict(name="Hunter", disposition=N, color=(0.35, 0.50, 0.30), kit=1, health=1.1, wander=12.0, armor_tier=-1,
                   lines=["Tracks everywhere. Wolves, mostly.",
                          "Keep your voice down. You will spook the game.",
                          "I have no quarrel with you, so let's keep it that way."]),
    "prospector": dict(name="Prospector", disposition=F, color=(0.72, 0.57, 0.36), kit=3, health=0.9, wander=8.0, armor_tier=-9,
                       lines=["Sand gets in everything. But there is gold out here somewhere.",
                              "Found a strange old door in the rocks. Not going near it, mind you."]),
    "trapper": dict(name="Trapper", disposition=N, color=(0.50, 0.40, 0.30), kit=1, health=1.2, wander=10.0, armor_tier=-1,
                    lines=["Cold enough to freeze your breath mid-air up here.",
                           "Keep clear of the bears if you can. They are bigger than they look.",
                           "Good furs fetch a fair price, if you live to sell them."]),
    "caravan_guard": dict(name="Caravan Guard", disposition=N, color=(0.30, 0.40, 0.62), kit=2, health=1.3, poise=1.2, wander=5.0,
                          armor_tier=0, lines=["Move along. Nothing to see here.",
                                               "We guard the merchant, not the road."]),
}


def color(c):
    return "Color(%s, %s, %s, 1)" % (f(c[0]), f(c[1]), f(c[2]))


def enemy_file(key, d):
    d = {**ENEMY_DEFAULTS, **d}
    L = ['[gd_resource type="Resource" script_class="EnemyData" format=3]', "",
         '[ext_resource type="Script" path="res://scripts/enemy_data.gd" id="1_ed"]', "",
         "[resource]", 'script = ExtResource("1_ed")', 'id = &"%s"' % key, 'display_name = "%s"' % d["name"],
         "disposition = %d" % d["disposition"], "color = %s" % color(d["color"]), "body_scale = %s" % f(d["scale"]),
         "health_mult = %s" % f(d["health"]), "damage_mult = %s" % f(d["damage"]), "poise_mult = %s" % f(d["poise"]),
         "loot_quality = %s" % f(d["loot"]), "weapon_tier_offset = %d" % d["weapon_tier"], "armor_tier_offset = %d" % d["armor_tier"],
         "kit = %d" % d["kit"], "move_speed = %s" % f(d["speed"]), "detection_range = %s" % f(d["detect"]),
         "telegraph_time = %s" % f(d["telegraph"]), "heavy_chance = %s" % f(d["heavy"]), "chain_chance = %s" % f(d["chain"]),
         "attack_pause_min = %s" % f(d["pause_min"]), "attack_pause_max = %s" % f(d["pause_max"]),
         "knockback_resistance = %s" % f(d["kb_res"]), "wander_radius = %s" % f(d["wander"]), 'talk_name = "%s"' % d["name"]]
    if d["lines"]:
        L.append("talk_lines = PackedStringArray(%s)" % ", ".join('"%s"' % x.replace('"', '\\"') for x in d["lines"]))
    L.append("")
    return "\n".join(L)


# ------------------------------------------------------------------ spawn tables
# entry: (members, weight, count_min, count_max, min_level, max_level)
def E(members, w=1.0, cmin=1, cmax=1, lmin=1, lmax=100):
    return (members if isinstance(members, list) else [members], w, cmin, cmax, lmin, lmax)


TABLES = {
    # garrisons of points of interest
    "garrison_camp": [E("bandit", 3, 2, 3), E("bandit_thug", 2, 1, 2), E("cutthroat", 2, 2, 2, 2), E("bandit_brute", 1, 1, 1, 4)],
    "garrison_tower": [E("bandit", 3, 2, 2), E("bandit_thug", 2, 1, 2), E("cutthroat", 1, 1, 1, 2)],
    "garrison_ruins": [E("skeleton", 3, 2, 3), E("skeleton_knight", 1, 1, 1, 5), E("pilgrim", 1)],
    "garrison_shrine": [E("pilgrim", 3, 1, 2), E("wanderer", 1)],
    "garrison_stones": [E("wolf", 2, 2, 3), E("hunter", 1)],
    "garrison_cave_mouth": [E("wolf", 2, 2, 2), E("cutthroat", 2, 2, 2), E("cave_dweller", 1, 1, 2, 3)],
    "garrison_crypt_mouth": [E("skeleton", 3, 2, 2), E("skeleton_knight", 2, 1, 1, 6)],
    # dungeon rooms
    "dungeon_cave": [E("cutthroat", 3, 2, 3), E("bandit", 2, 2, 2), E("cave_dweller", 3, 2, 3), E("wolf", 1, 2, 2), E("bandit_brute", 1, 1, 1, 4)],
    "dungeon_crypt": [E("skeleton", 4, 2, 4), E("skeleton_knight", 2, 1, 2, 5)],
    # random encounters
    "enc_plains_ambush": [E("bandit", 3, 2, 3), E("cutthroat", 2, 2, 2, 3), E("bandit_brute", 1, 1, 1, 5), E("bandit_thug", 1, 2, 2)],
    "enc_wolves": [E("wolf", 1, 2, 4)],
    "enc_wanderer": [E("wanderer")],
    "enc_hunter": [E("hunter")],
    "enc_caravan": [E(["merchant", "caravan_guard", "caravan_guard"])],
    "enc_desert_raiders": [E("raider", 3, 2, 3), E("raider_marauder", 1, 1, 1, 8), E("cutthroat", 1, 2, 2)],
    "enc_desert_beasts": [E("dune_stalker", 1, 2, 3)],
    "enc_prospector": [E("prospector")],
    "enc_snow_reavers": [E("reaver", 2, 1, 2), E("frost_raider", 2, 2, 2)],
    "enc_snow_beasts": [E("frost_bear", 2, 1, 1), E("wolf", 3, 3, 4)],
    "enc_trapper": [E("trapper")],
}


def table_file(entries):
    keys = []
    for e in entries:
        for m in e[0]:
            if m not in keys:
                keys.append(m)
    L = ['[gd_resource type="Resource" script_class="SpawnTable" format=3]', "",
         '[ext_resource type="Script" path="res://scripts/spawn_table.gd" id="t"]',
         '[ext_resource type="Script" path="res://scripts/spawn_entry.gd" id="s"]',
         '[ext_resource type="Script" path="res://scripts/enemy_data.gd" id="ed"]']
    for k in keys:
        L.append('[ext_resource type="Resource" path="res://scripts/Resources/Enemies/%s.tres" id="e_%s"]' % (k, k))
    L.append("")
    for i, (members, w, cmin, cmax, lmin, lmax) in enumerate(entries):
        L += ['[sub_resource type="Resource" id="entry_%d"]' % i, 'script = ExtResource("s")',
              'members = Array[ExtResource("ed")]([%s])' % ", ".join('ExtResource("e_%s")' % m for m in members),
              "weight = %s" % f(w), "count_min = %d" % cmin, "count_max = %d" % cmax,
              "min_level = %d" % lmin, "max_level = %d" % lmax, ""]
    L += ["[resource]", 'script = ExtResource("t")',
          'entries = Array[ExtResource("s")]([%s])' % ", ".join('SubResource("entry_%d")' % i for i in range(len(entries))), ""]
    return "\n".join(L)


# ------------------------------------------------------------------ encounters
ENC_DEFAULTS = dict(weight=1.0, aggro=False, avoid_view=True, dmin=40.0, dmax=75.0, spread=3.0, cooldown=120.0, message="")
ENCOUNTERS = {
    "plains_ambush": dict(name="Bandit Ambush", table="enc_plains_ambush", weight=3, aggro=True, message="Bandits spring an ambush!"),
    "plains_wolves": dict(name="Wolf Pack", table="enc_wolves", weight=2, aggro=True, dmin=45, dmax=80, message="You hear wolves closing in..."),
    "plains_wanderer": dict(name="Wanderer", table="enc_wanderer", weight=3, dmin=30, dmax=60),
    "plains_hunter": dict(name="Hunter", table="enc_hunter", weight=2, dmin=30, dmax=60),
    "plains_caravan": dict(name="Merchant Caravan", table="enc_caravan", weight=1, dmin=35, dmax=65, spread=4.0, message="A merchant caravan is on the road."),
    "desert_raiders": dict(name="Raider Ambush", table="enc_desert_raiders", weight=3, aggro=True, message="Raiders emerge from the dunes!"),
    "desert_beasts": dict(name="Dune Stalkers", table="enc_desert_beasts", weight=2, aggro=True, dmin=45, dmax=80, message="Something moves beneath the sand..."),
    "desert_prospector": dict(name="Prospector", table="enc_prospector", weight=2, dmin=30, dmax=60),
    "desert_caravan": dict(name="Merchant Caravan", table="enc_caravan", weight=1, dmin=35, dmax=65, spread=4.0, message="A merchant caravan is on the road."),
    "snow_reavers": dict(name="Reaver Raid", table="enc_snow_reavers", weight=3, aggro=True, message="Reavers charge out of the snow!"),
    "snow_beasts": dict(name="Hungry Beasts", table="enc_snow_beasts", weight=3, aggro=True, dmin=45, dmax=80, message="Something is stalking you through the snow."),
    "snow_trapper": dict(name="Trapper", table="enc_trapper", weight=2, dmin=30, dmax=60),
}


def encounter_file(key, d):
    d = {**ENC_DEFAULTS, **d}
    return "\n".join([
        '[gd_resource type="Resource" script_class="EncounterData" format=3]', "",
        '[ext_resource type="Script" path="res://scripts/World/encounter_data.gd" id="1_enc"]',
        '[ext_resource type="Resource" path="res://scripts/Resources/Spawns/%s.tres" id="2_table"]' % d["table"], "",
        "[resource]", 'script = ExtResource("1_enc")', 'id = &"%s"' % key, 'display_name = "%s"' % d["name"],
        'table = ExtResource("2_table")', "weight = %s" % f(d["weight"]), "aggro = %s" % str(d["aggro"]).lower(),
        "avoid_view = %s" % str(d["avoid_view"]).lower(), "distance_min = %s" % f(d["dmin"]), "distance_max = %s" % f(d["dmax"]),
        "group_spread = %s" % f(d["spread"]), "cooldown = %s" % f(d["cooldown"]), 'message = "%s"' % d["message"], ""])


# ------------------------------------------------------------------ hooking up existing files
BIOMES = {  # file -> (level_min, level_max, encounters)
    "plains": (1, 10, ["plains_ambush", "plains_wolves", "plains_wanderer", "plains_hunter", "plains_caravan"]),
    "desert": (6, 18, ["desert_raiders", "desert_beasts", "desert_prospector", "desert_caravan"]),
    "snow_mountains": (12, 28, ["snow_reavers", "snow_beasts", "snow_trapper"]),
}
POIS = {  # file -> (table, groups_min, groups_max, level_offset)
    "bandit_camp": ("garrison_camp", 2, 3, 0), "watchtower": ("garrison_tower", 1, 2, 0),
    "ruined_shrine": ("garrison_ruins", 1, 1, 1), "glowing_shrine": ("garrison_shrine", 1, 1, 0),
    "standing_stones": ("garrison_stones", 1, 1, 0), "cave_entrance": ("garrison_cave_mouth", 1, 1, 0),
    "crypt_entrance": ("garrison_crypt_mouth", 1, 1, 1),
}
DUNGEONS = {  # file -> (table, per_room_min, per_room_max, boss, level_offset)
    "dark_cave": ("dungeon_cave", 0, 1, "cave_troll", 0),
    "crypt": ("dungeon_crypt", 0, 1, "crypt_warden", 2),
}


def hook(path, marker, ext_lines, prop_lines):
    """Adds ext_resource lines and properties to a hand-written .tres, once"""
    if not os.path.exists(path):
        print("  (skipped, not found: %s)" % path)
        return
    text = open(path).read()
    if marker in text:
        return
    lines = text.rstrip("\n").split("\n")
    last_ext = max(i for i, l in enumerate(lines) if l.startswith("[ext_resource"))
    lines[last_ext + 1:last_ext + 1] = ext_lines
    lines += prop_lines
    write(path, "\n".join(lines) + "\n")


def main():
    for t in range(7):
        for kind in WEAPONS:
            weapon_item(kind, t)
        shield_item(t)
        chest_item(t)
    for k, d in ENEMIES.items():
        write(os.path.join(RES, "Enemies", k + ".tres"), enemy_file(k, d))
    for k, e in TABLES.items():
        write(os.path.join(RES, "Spawns", k + ".tres"), table_file(e))
    for k, d in ENCOUNTERS.items():
        write(os.path.join(RES, "Encounters", k + ".tres"), encounter_file(k, d))

    for name, (lmin, lmax, encs) in BIOMES.items():
        ext = ['[ext_resource type="Script" path="res://scripts/World/encounter_data.gd" id="enc_script"]']
        ext += ['[ext_resource type="Resource" path="res://scripts/Resources/Encounters/%s.tres" id="enc_%d"]' % (e, i) for i, e in enumerate(encs)]
        props = ["level_min = %d" % lmin, "level_max = %d" % lmax,
                 'encounters = Array[ExtResource("enc_script")]([%s])' % ", ".join('ExtResource("enc_%d")' % i for i in range(len(encs)))]
        hook(os.path.join(RES, "World", name + ".tres"), "encounters =", ext, props)
    for name, (table, gmin, gmax, off) in POIS.items():
        ext = ['[ext_resource type="Resource" path="res://scripts/Resources/Spawns/%s.tres" id="garrison_table"]' % table]
        props = ['garrison = ExtResource("garrison_table")', "garrison_groups_min = %d" % gmin, "garrison_groups_max = %d" % gmax]
        if off:
            props.append("garrison_level_offset = %d" % off)
        hook(os.path.join(RES, "World", "POIs", name + ".tres"), "garrison =", ext, props)
    for name, (table, rmin, rmax, boss, off) in DUNGEONS.items():
        ext = ['[ext_resource type="Resource" path="res://scripts/Resources/Spawns/%s.tres" id="spawn_table"]' % table,
               '[ext_resource type="Resource" path="res://scripts/Resources/Enemies/%s.tres" id="boss"]' % boss]
        props = ['spawn_table = ExtResource("spawn_table")', "enemies_per_room_min = %d" % rmin, "enemies_per_room_max = %d" % rmax,
                 'boss = ExtResource("boss")']
        if off:
            props.append("level_offset = %d" % off)
        hook(os.path.join(RES, "World", "Dungeons", name + ".tres"), "spawn_table =", ext, props)
    print("done: %d items, %d enemies, %d spawn tables, %d encounters" % (7 * (len(WEAPONS) + 2), len(ENEMIES), len(TABLES), len(ENCOUNTERS)))


if __name__ == "__main__":
    main()
