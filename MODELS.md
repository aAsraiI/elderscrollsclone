# Models

From 1.15.3 people, creatures, weapons, items, furniture, rocks and trees use real 3D models
instead of boxes. Anything without a model keeps its old box shape, so nothing goes missing.

- Code: `scripts/core/model_library.gd` (`ModelLibrary`), `scripts/actors/model_body.gd` (`ModelBody`)
- Which model each thing uses: `data/models/models.json`
- The model files: `assets/models/` (credits in `assets/models/CREDITS.md`)

## How it works

Every look has a **key**. The game asks for keys from most to least specific and uses the first one
that has a model:

| Thing | Keys asked for (in order) |
| --- | --- |
| Enemy or creature | `creature/<enemy id>` (e.g. `creature/wolf`), then for people: `people/skeleton…`, `people/zombie`, `people/brute`, `people/mage`, `people/knight`, `people/archer`, `people/fighter_a/b`, `people/man_1..3` / `people/woman_1..3` |
| You (third person) | `player/<any people key>`, `player/body`, then the people keys |
| Horse | `creature/horse` |
| Item | `item/<item id>`, then by kind: `weapon/<animation set>` (`sword`, `greatsword`, `dagger`, `axe`, `battleaxe`, `hammer`, `mace`, `spear`, `bow`, `shield`), `item/potion_health/magicka/stamina`, `item/potion`, `item/gold`, `food/apple`…, `item/book`, `item/scroll`, `item/gem`, `item/goblet`, `item/tankard`… |
| Furniture prop scene | `prop/<scene file name>` (e.g. `prop/barrel` for `barrel.tscn`), then `prop/<each tag>` |
| Room decoration | `prop/<kind>` (`shelf`, `bookcase`, `cupboard`, `wardrobe`, `table`, `bench`, `display`, `urn`, `plinth`…) |
| Trees | `tree/broadleaf`, `tree/pine`, `tree/dead`, `tree/cactus` |
| Scattered rocks | `nature/rock_0`, `nature/rock_1`, `nature/rock_2` |

A model is scaled to fill the space the old box shape took, so it stands in the same place at the same
size. Its collision is built from the model's own shape (convex hulls), and an enemy's standing capsule
and eye height are fitted to its model (long four-legged creatures get a capsule lying along the body).

People and creatures play their model's own animations. Clips are found by name (Idle, Walk,
Running_A, 1H_Melee_Attack_Chop, Block, Spellcasting, Sit_Chair_Idle, Lie_Idle, Death_A…), chosen each
frame from what the old box animator read: speed, the swing, blocking, a drawn bow, a spell charging,
a stagger, and the calm poses (sit, sleep, pray, work, chop, talk, drink). On death the model plays its
death clip and lies as one piece, still searchable and draggable. Weapons and shields hang from the
model's hand bones.

## An entry in models.json

```json
"creature/wolf": {"path": "creatures/Wolf.fbx", "rot": [0, 90, 0], "fit": "long", "walk_speed": 1.5, "run_speed": 4.0}
```

| Field | Meaning |
| --- | --- |
| `path` | The file, relative to `assets/models` (or to the folder of your own models.json) |
| `rot` | Degrees to turn it first. The game's forward is -Z; most glTF/FBX models face +Z, so `[0, 180, 0]` |
| `fit` | `fill` (props: as tall as the old piece, not much wider), `height`, `long` (longest side), `contain`, `width` |
| `scale` | Extra size after fitting |
| `anchor` | `center` to centre it on the old shape instead of standing it on the floor |
| `align` | `false` stops props being turned a quarter to match the old footprint |
| `hide` | Parts of the model not drawn (built-in weapons, mugs) |
| `hands` | `{"r": "bone", "l": "bone"}`: the bones weapons and shields hang from |
| `grip_rot_r`, `grip_rot_l` | Degrees to turn what hangs from each hand |
| `clips` | Your own clip names by role, e.g. `{"walk": "MyWalk"}` (roles: idle, idle_combat, walk, run, attack, attack_alt, attack2h, attack_unarmed, bash, block, hit, death, cast, aim, sit, kneel, lie, work, chop, talk, drink, stun) |
| `walk_speed`, `run_speed` | The speed (m/s) the walk and run clips were made for |
| `tint` | `[r, g, b]` multiplied into its colours |
| `texture` | An image to put on every part (for older files whose texture did not come along) |

A key can also be just a path: `"weapon/sword": "weapons/Sword.fbx"`.

## Your own models

Put them in a **models** folder; they win over the built-in ones, and the game reads them when it starts:

- next to the game: `ElderScrollsClone1.15.3.exe` and a `models` folder beside it, or
- in the game's data folder: `%APPDATA%\Godot\app_userdata\ELDERSCROLLSCLONE\models`

Name each file after its key with `/` written as `__`: `prop__barrel.glb`, `creature__wolf.glb`,
`weapon__sword.gltf`, `people__knight.glb`. Formats: `.glb`, `.gltf` or `.fbx`. To turn, fit, hide parts or
name clips, add a `models.json` in that folder in the same format as `data/models/models.json`
(paths relative to that folder).

### Models from a game you own (for example Morrowind)

Morrowind's models belong to Bethesda, so they are **not** included and must never be put into this
project or a release. You can use your own copy for yourself:

1. Install [Blender](https://www.blender.org/) and the
   [NifTools Blender add-on](https://github.com/niftools/blender_niftools_addon), which opens `.nif` files.
2. Get the `.nif` files out of your own copy's `Data Files/Morrowind.bsa` with a BSA tool
   (for example BSA Browser) or use loose meshes from `Data Files/Meshes`.
3. Open one in Blender (File > Import > NetImmerse/Gamebryo), check it stands upright, and export it
   as glTF (File > Export > glTF 2.0, `.glb`) with its textures (convert the `.dds` textures to `.png`
   if Blender cannot read them).
4. Save it into your models folder named after the key it should replace, for example
   `prop__barrel.glb` or `creature__wolf.glb`.

Static models (furniture, rocks, weapons, items) work straight away. Creatures and people need a model
with its own animations; Morrowind keeps those in separate `x*.nif` / `.kf` files, so they need to be
merged in Blender first.

## Adding a built-in model

1. Copy the file (and its textures) into `assets/models/<folder>/` and let the editor import it.
2. Add its key to `data/models/models.json`.
3. Check it: `godot --headless --path . -s res://tools/measure_keys.gd -- <key prefix> [role]` prints its
   size after turning and which way its toes and head point; `tools/build_model_preview.gd` lays models
   out in `tools/model_preview.tscn`, and `tools/capture.gd` saves a screenshot of a scene.
4. Add its source and licence to `assets/models/CREDITS.md`. Use only models you may share (CC0 is best).

## Still boxes

Armour worn on bodies (people use whole-body models that show their own clothes and armour), worn
armour lying on the ground except shields, keys, ingots, ore, pelts, rings and amulets, buildings and
walls (made by the building kit), and these props: anvil, armour stand, bedroll, brazier, cage, cart,
chain, crop rows, crystal, drying rack, flower box, fountain, fungus, gravestone, grave cross, hay,
hearth, keg rack, lamp post, log pile, market stall, mine cart, pickaxes, rails, ritual circle, rope,
rowboat, sarcophagus, shield wall, stalactite, stalagmite, stone bench, support beams, tapestry, tent,
throne, training dummy, weapon heap, well. Also pine, dead and cactus trees, bushes, frost bears,
and fire and ice spirits. Give any of them a key in models.json (or your models folder) and it changes.
