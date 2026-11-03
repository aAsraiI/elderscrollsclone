# Making interiors (Alpha 1.13)

Every interior is a scene you can open and edit in the Godot editor. Dungeons are stitched together from room modules; town buildings use one module each; anything can be replaced by a hand-made scene.

## Where things are

| What | Where |
|---|---|
| Dungeon room modules, by theme | `scenes/interiors/modules/<theme>/` |
| A template per room role | `scenes/interiors/modules/templates/` |
| Props (furniture and decoration) | `scenes/interiors/props/` |
| Builder kit: containers, loot furniture, stations | `scenes/kit/` |
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
4. Furniture is placed by hand: props from `props/` and kit pieces from `scenes/kit/`, saved in the scene, so the room looks the same every time (see "Hand-made rooms" below).
5. Spawn points are **SpawnSocket** nodes for what changes: pick a **Kind** (chest, loot, enemy, boss, NPC, quest item), **Tags** (`sleeper`, `ambush`, `captive`, `boss`...), a **Chance** and a **Count**. The furniture kinds (furniture, decoration, wall decoration, light, ceiling) are no longer filled.
6. The room's shell comes from `InteriorKit` (floor, walls with gaps at the doorways, ceiling). Add your own boxes with any name; anything in the group `interior_dynamic` is never merged (things that open or move).
7. Run the tests: the module checker (`RoomModule.problems()`) reports doorways off the edge, sockets outside the room and similar mistakes.

Enemy socket tags the AI uses: `sleeper` (lies in a bunk), `eating`/`cook` (sits), `guard`/`officer` (stands at a post facing the way in), `ambush` (waits until you come by). Corridors get patrols on their own.

## A prop

Copy a scene in `props/`, change its meshes, and set on the root (InteriorProp): **Tags**, **Socket Kinds**, **Themes** (empty = all), **Snap** (floor, wall, ceiling), **Radius**, wealth range and **Weight**. A child OmniLight3D makes it a light (candle, torch, brazier and hearth lights flicker).

## Hand-made rooms (Alpha 1.20)

No furniture is picked when the game runs. Every room, house, hall, set-piece and outdoor site holds its
furniture as nodes in its scene (the old furniture spawn points were turned into the props the game used
to pick by `tools/bake_room_props.gd`). Move, delete or add props and kit pieces and save; every place
using the scene changes. Only the loot is rolled: on the room's tables, shelves, counters and altars
(`RoomDecorator.decorate`, per building or dungeon room, restocked in towns after 3 days) and in containers.

The builder kit (`scenes/kit/`, written by `tools/build_kit.gd`):

| Folder | What | Script |
|---|---|---|
| `containers/leveled/` | 33 containers filled with loot for the place (chests, sacks, barrels, crates, urns, pots, wardrobes, drawers, desks, Dwemer and Daedric chests, remains...) | `KitContainer` |
| `containers/empty/` | the same, empty (storage) | `KitContainer` (Leveled off) |
| `surfaces/` | 27 pieces of furniture with loot on them (shelves, bookcases, tables, counters, bar, altar, plinth, racks, niche, sarcophagus, cart) | `KitLootShelf` |
| `stations/` | forge, smelter, tanning rack, workbench, grindstone, cooking pot, alchemy lab, enchanter, spell altar, beds, bunk, bedroll, shrine, planter | `KitStation` |
| `blocks/`, `doors/`, `model` | wall blocks, the exit door, any model | `KitBlock`, `KitExitDoor`, `KitModel` |

Kit pieces read where they stand from the interior they are built into (`KitPlace`): the dungeon's level
and room theme, or the building's owner, level and kind. Leave **Loot Tags** empty to take what the place
holds; set **Owner Id** or **Free To Take** to change whose things they are. A container's save id is its
room and its node name, so give containers in one scene different names.

Shelving (bookcases, shelves, racks, niches, wine racks, keg stands: `ModelLibrary.OPEN`) has exact
collision, so things can be put back on its planks, and loot is laid along a plank only where it fits
(`RoomDecorator.set_on`). Containers stand at their model's size with a hull that fits it
(`POIBuilder.make_container`).

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
