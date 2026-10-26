# Making interiors (Alpha 1.13)

Every interior is a scene you can open and edit in the Godot editor. Dungeons are stitched together from room modules; town buildings use one module each; anything can be replaced by a hand-made scene.

## Where things are

| What | Where |
|---|---|
| Dungeon room modules, by theme | `scenes/interiors/modules/<theme>/` |
| A template per room role | `scenes/interiors/modules/templates/` |
| Props (furniture and decoration) | `scenes/interiors/props/` |
| Town building interiors | `scenes/interiors/houses/` |
| Set-pieces pinned into dungeons | `scenes/interiors/setpieces/` |
| Hand-made dungeons and halls | `scenes/interiors/handmade/` |
| Recipes | `data/interiors/recipes/` |
| Overrides (hand-made replaces generated) | `data/interiors/overrides.tres` |

The tools that made them (`tools/build_interiors.gd`, `tools/build_houses.gd`, `tools/build_handmade.gd`) never overwrite a scene that exists, so your edits are safe. Pass `-- --force` only to start over.

## A room module

1. Copy a template from `modules/templates/` into a theme folder (for example `modules/crypt/`).
2. On the root (RoomModule) set **Themes**, **Role** (room, corridor, stairs, boss...), **Kind** (what recipes ask for: `barracks`, `ossuary`...), **Cells** (4 m squares, 5 m storeys), **Weight** and the level range.
3. Doorways are **DoorwayMarker** nodes on the room's edge, facing out (blue arrow). Width and tags decide what they join.
4. Spawn points are **SpawnSocket** nodes: pick a **Kind** (furniture, decoration, wall decoration, light, ceiling, chest, loot, enemy, boss, NPC, quest item), **Tags** that say what fits (`table`, `bed`, `sleeper`, `ambush`, `captive`...), a **Chance** and a **Count**. Tag a socket `set` when it sits right beside another prop on purpose.
5. The room's shell comes from `InteriorKit` (floor, walls with gaps at the doorways, ceiling). Add your own boxes with any name; anything in the group `interior_dynamic` is never merged (things that open or move).
6. Run the tests: the module checker (`RoomModule.problems()`) reports doorways off the edge, sockets outside the room and similar mistakes.

Enemy socket tags the AI uses: `sleeper` (lies in a bunk), `eating`/`cook` (sits), `guard`/`officer` (stands at a post facing the way in), `ambush` (waits until you come by). Corridors get patrols on their own.

## A prop

Copy a scene in `props/`, change its meshes, and set on the root (InteriorProp): **Tags**, **Socket Kinds**, **Themes** (empty = all), **Snap** (floor, wall, ceiling), **Radius**, wealth range and **Weight**. A child OmniLight3D makes it a light (candle, torch, brazier and hearth lights flicker).

## A recipe

A DungeonRecipe says how a dungeon is stitched: **Themes** (first is the main one, others mix in by **Mix**), room counts by level, **Required** room kinds, **Branching**, **Corridors**, **Extra Floors**, **Boss**, **Density**, **Light** and **Set Pieces** (hand-made rooms, one is placed about half way in). Give a DungeonData the recipe to use it.

To look at one: add a **DungeonPreview** node to any scene, pick a recipe, seed and level, tick **Generate**. Tick **Bake** to save it as a scene you can finish by hand; name that scene in the DungeonData's **Handmade** or in `overrides.tres` (`dungeons`, by dungeon id) to use it in the game. A baked scene keeps its joins, so locked doors, levers and the secret room still work.

## A building interior

Building modules are RoomModules whose **Kind** is `house`, `farm`, `manor`, `shop`, `smithy`, `inn`, `temple`, `guild` or `seat`. Markers tell the game where the working things go:

| Marker | Meaning |
|---|---|
| `Door`, `ExitSpot`, `Start` | the way out, where people leave from, where you arrive |
| `Bed<n>`, `Seat<n>`, `Work` | where the household sleeps, sits and works |
| `Chest<n>` | the owner's chests (`Chest0` is the one quests use) |
| `Station_<kind>` | a crafting station (`Station_trade`, `Station_guild<n>`: chosen by the shop's trade or the guild) |
| `Spare<n>` | room for what you add to a home you own |
| `Via_<spot>_<n>` | the way to a spot behind a wall or upstairs, in order |
| `Notice`, `Bounty`, `Lore`, `Shrine`, `Banner<n>`, `Case`, `Cell<n>` | inn board, bounty board, lore shelf, temple shrine, banners, museum case, cells |

A building over a cellar sits a storey up: the game puts its `Door` floor at ground level. To give one particular building its own interior, add it to `overrides.tres` under `buildings` as `<Town>/<Building name>`.
