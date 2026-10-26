# Making outdoor places and buildings (Alpha 1.14)

Outdoor places and town buildings are put together from scenes and resources you can edit in the Godot editor. The tools that made them (`tools/build_sites.gd`, `tools/build_buildings.gd`) never overwrite a file that exists; pass `-- --force` only to start over.

## Where things are

| What | Where |
|---|---|
| Site scenes (camps, towers, ruins, forts, farms...) | `scenes/sites/<kind>_<version>.tscn` |
| Site kinds (versions, occupants, dungeon, placement) | `data/world/Sites/<kind>.tres` |
| Outdoor and town props | `scenes/interiors/props/` |
| Building styles, one per kind of land | `data/buildings/styles/<name>.tres` |
| Building parts | `scenes/buildings/parts/` |
| Hand-made buildings and interiors | `data/interiors/overrides.tres` |

## A site

1. Copy a scene in `scenes/sites/` (or make a new scene with an **ExteriorSite** root).
2. On the root set **Site Kind**, **Biomes** (empty = any land), **Size Class**, **Min Distance**, **Map Icon** and, if it has a ruler, **Boss**. **Cells** is its footprint in 4 m squares.
3. Build it from boxes, props or anything else. Spawn points (**SpawnSocket**) fill it: furniture, decoration, lights, chests, loot, enemies (tags: `sleeper`, `guard`, `archer`, `ambush`) and the boss. Spawn points at ground level are set onto the land where it is built; ones up on a floor or a wall stay where you put them.
4. A **SiteLink** (door, cave mouth, hatch or trapdoor) is the way down into a dungeon. Its blue-purple arrow points the way in.
5. Markers that turn into things: `Note` (a note to read), `Inscription` (a monument's words), `Blessing` (a shrine), `Herb<n>` and `Ore<n>` (things to gather), `Keeper` (a wayside rest's keeper).
6. Add the scene to its kind's **Sites** list in `data/world/Sites/<kind>.tres`. Each place picks one version by its seed.
7. Run the tests: the site checker (`ExteriorSite.problems()`) reports spawn points outside the site, a link outside it, or more than one link.

## A kind of site

A **SitePOIData** (`data/world/Sites/<kind>.tres`) has the usual place settings (footprint, flatten radius, slope) plus:

- **Sites**: the versions.
- **Occupants**: who lives there (a SpawnTable); empty = nobody until bandits take it.
- **Dungeon**: the DungeonData its SiteLink leads into.
- **Prefer**: `high` (hilltops), `low` (hollows), `water` (by a lake, river or the sea), `road` (by a road), or `any`.
- **Min Same Distance**: places of this kind stay at least this far apart.
- **Path To Road**: lay a dirt path to the nearest road within this many meters.
- **Discoverable**: off for small things (a campfire, a lost pack) that are not places on the map.
- **Map Icon**: the symbol on the map.

List it in a biome's **Poi Rules** to put it in that land.

## A building

Town buildings are generated from their plot (kind, size, district) and the land's **BuildingStyle**: walls (`plaster`, `timber`, `stone`, `adobe`, `planks`), base (`none`, `stone`, `stilts`), roof (`gable`, `steep`, `flat`), tints, and the chances of a porch, a balcony and shutters. The parts in `scenes/buildings/parts/` (chimney, porch, balcony, shutters, door, sign bracket) are placed by their origin, as their scene notes say.

To replace one building with your own: make a scene whose origin is the middle of its floor with the front door on the -Z side, and add it to `data/interiors/overrides.tres` under **exteriors** as `<Town>/<Building name>`. The door is added for you. Its inside is a separate override under **buildings**, made the way INTERIORS.md describes.
