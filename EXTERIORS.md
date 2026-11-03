# Making the world, outdoor places and buildings (Alpha 1.21)

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
3. Build it from boxes, props, kit pieces (`scenes/kit/`) or anything else; the furniture stays where you put it (Alpha 1.20). Spawn points (**SpawnSocket**) add chests, loot, enemies (tags: `sleeper`, `guard`, `archer`, `ambush`) and the boss. Props, kit pieces and spawn points at ground level are set onto the land where it is built; ones up on a floor or a wall stay where you put them.
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

## The world (Alpha 1.21)

The world is an island of rounded lands in the open sea, with more islands out in the water. All of
it is set in `data/world/realm_world.tres` (a **WorldSettings**) and the biome files beside it; the tool
`tools/build_world.gd` wrote the starting values (run it again with `-- terrain`, `layout`, `flora`,
`ingredients` or `islands` to put a part back).

| What | Where |
|---|---|
| The main island's lands | `realm_world.tres` > **Placements** |
| The other islands | `data/world/Islands/<name>.tres` (**IslandData**), listed in **Islands** |
| How each land's ground is shaped, coloured, planted | `data/world/<biome>.tres` (**BiomeData**) |
| Rivers, lakes, coast, region borders | `realm_world.tres` > **Regions and coast**, **Rivers and lakes** |
| Dungeon kinds and their recipes | `data/world/Dungeons/`, `data/interiors/recipes/` (`tools/build_dungeons_121.gd`) |

### Lands and islands

Each **BiomePlacement** is a box (in 500 m cells) that only says roughly where a land is. A few seed
points are scattered inside it and every spot belongs to the nearest seed after the map is bent by
noise, so the lands come out as rounded blobs that meet without gaps. **Reach** makes one land push into
its neighbours (or give way); **Level Min / Max** set its levels. The same biome can be placed several
times (a big region and a small pocket).

An **IslandData** is a list of placements of its own, anywhere out in the sea: its boxes together give
the island's size, **Roundness** its outline, **Coast Warp** / **Region Warp** how far noise bends its
coast and borders (-1 = from its size), **Port** whether it gets a port town. Keep 2-3 km of sea between
islands. There are five to start with: Isle of Cinders (ashlands), Frosthold (tundra, frozen crown),
Saltmarsh Isles (swamp, coast), Greenisle (forest, plains, lakeland) and Sunreach (five lands).

### The shape of the ground

A biome's ground is built up in layers (BiomeData > Terrain), each 0 = off:

| Layer | What it makes |
|---|---|
| Base height, Hills | the land's height and its rolling hills |
| Mountains (+ Ridge Sharpness) | ridged ranges; 1 = rounded, 3 = knife-edged |
| Swirl | bends the hills and mountains into winding ridges and curving valleys |
| Valleys | branching vales and gullies cut into the land |
| Terraces | mesas and strata (badlands) |
| Dunes | wind-made sand ridges in fields (desert) |
| Pools | hollows that hold water where the land is low (lakeland meres, swamp pools) |
| Crags | tors, hoodoos and sea stacks |
| Cones | volcanic cones with a crater (ashlands) |

Big features only rise a blend distance inside a land, so borders are always gentle. The coast slopes to a
beach (or drops as sea cliffs where **Coast Width** is narrow) and the sea floor shelves into deep water.

### Water

`RiverPlanner` works out where water runs, the way the ground sends it: it floods every hollow up to
its spill point (deep, big hollows become lakes), lets rain (less in dry lands) run downhill, and starts a
stream where enough has gathered, a river where much more has. Streams run to the sea, a lake or the
river they join, never uphill. Their channels and banks are cut into the ground, the water surface is
drawn on each chunk, and you swim in deep water. Roads cross on bridges (stone over rivers, timber
over streams). Settings: **River Grid**, **Stream / River Catchment**, **Lake Min Depth**, **Lake Min / Max
Cells**, **Max Lakes**.

### Plants and herbs

BiomeData > **Flora** is a list of **FloraLayer**s, each scattered on its own: its **Models** (Morrowind
pieces like `kit/plants/trees/flora_tree_bm_01` after Settings > Models > Import building pieces, or
built-in keys; a plain **Shape** without them), **Size** (tree, shrub, plant, ground: how far it is
drawn), **Density** per hectare, **Clump Scale / Clumping**, **Max / Min Slope**, **Min / Max Height**,
**Water** (-1 keeps away, 1 only by the water), **In Water** (reeds, kelp), **Water Ok** (swamp trees),
**Floats** (lily pads), **Scale**, **Sink**, **Lean**, **Follow Ground** (logs, rocks) and **Solid**. Models
are planted on their foot, so a lopsided tree still stands on its roots. `tools/flora_sheet.gd` lays out
models side by side and marks in red any that grow at an angle.

**Herbs** lists what you can pick (`id:weight`); water herbs (HarvestNode.HERB_INFO) grow only at the
water's edge. **Herb Density** sets how many.

### Towns, ports and the ground they stand on

A town's ground is levelled at the slope it stands on before its streets and buildings are laid out, and
every building gets a footprint of ground levelled to its floor (the ground meets the walls). The steeper
the land round a town or a place, the wider the bank down to it. Every island has a port: the town
nearest the sea, or a new village on the shore, with a long pier and a ship to every other port
(**SeaPassage**, paid like the carriage). Coastal towns also keep a rowboat.

### Checking the world

- `tools/world_preview.gd -- out.png [settings] [size] [seed] [noplaces] [at=x,z,meters]`: the world
  from above (lands, borders, water, roads, places) and a count of everything in it.
- `tools/capture_world.gd -- out_dir "x,z,height,yaw,pitch,name" ...`: screenshots in the game.
- The map (M) shows each land's tint and border, its name, the sea, lakes and rivers.
