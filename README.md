# Elder Scrolls Clone

A first-person open-world fantasy RPG made in Godot 4.7.

- Design document: https://claude.ai/artifact/UZ2YYR8dLMP1BBjy1oxzqc
- Roadmap (tick a box to ask for a feature): https://claude.ai/artifact/7m4SoQtEDYF7piXhfHCUvK
- Lore and quest bible: https://claude.ai/artifact/MTJCmu1Cw3eBg5D7cYoPje

## Playing

Open the project in Godot and press F5. The main menu is `scenes/game/main_menu.tscn`;
New Game goes through world and character creation. To jump straight into the world with a
test sword and a practice enemy, open `scenes/game/game.tscn` and press F6.

## Folders

| Folder | Holds |
| --- | --- |
| `scenes/game/` | Main menu and the game world scene (with its sky, fog and sun) |
| `scenes/player/` | The player, with every HUD, menu and ability as a node you can select |
| `scenes/actors/` | `enemy.tscn`: every creature and NPC starts as a copy of it |
| `scripts/<area>/` | Code by area: `actors`, `audio`, `character`, `combat`, `core`, `crafting`, `dialogue`, `dungeons`, `factions`, `items`, `magic`, `player`, `quests`, `realms`, `save`, `towns`, `trade`, `ui`, `world` |
| `data/` | Content as `.tres` resources: items, enemies, factions, merchants, spawns, world settings; `data/models/models.json` says which 3D model each thing uses |
| `assets/models/` | The 3D models (all CC0, see `assets/models/CREDITS.md`); how they are used and how to add your own: `MODELS.md` |
| `ui/` | The UI theme |
| `tools/` | Editor tools that generate content (`generate_*.gd`, `build_*.gd`) `check_scripts.gd`, and `run_tests.ps1` |
| `test/` | Gameplay test suites (run headless) |
| `tests/` | Content checks (run in the editor) |
| `addons/godot_ai/` | Godot AI editor plugin |

## Tests

- `tests/` holds quick content checks that run inside the editor through the Godot AI test runner
  (every quest, faction, book and data file points at things that exist). They take about 2 seconds.
- `test/` holds the gameplay suites, which run the game headless. `test_playtest.gd` plays a short
  game end to end: spawn, a fight, a town, a dungeon, save and load.

Run every gameplay suite, 4 at a time (about 20 minutes), or only some of them:

    powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
    powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -Only playtest,stage1

Check that every script compiles:

    godot --headless --path . -s res://tools/check_scripts.gd

## Performance (Alpha 1.23)

`tools/perf_probe.gd` runs the real game with a window (vsync off) and prints frame times, draw calls,
what is drawn, and which scripts cost the most, at the start, in a city and in a dungeon:

    godot --path . -s res://tools/perf_probe.gd                     (about 2 minutes)
    godot --path . -s res://tools/perf_probe.gd -- quick            (no per-script costs)
    godot --path . -s res://tools/perf_probe.gd -- ride             (rides 450 m at horse speed: hitches)
    godot --path . -s res://tools/perf_probe.gd -- quick set:view_distance=6   (a setting for this run only)

What keeps the game fast, and what new code should follow:
- **ActorLOD** (`scripts/core/actor_lod.gd`): people and creatures past 150 m (55 m inside), or on the
  other side of a dungeon door, are hidden and stop processing; past 35 m they cast no shadow.
- **SpawnQueue** (`scripts/core/spawn_queue.gd`): the people of a place streaming in join a few per frame
  (3 ms), never all in one frame. Wrap streaming code in `SpawnQueue.defer = true / false`.
- **Far trees** (`Flora._build_far`): past 230 m a tree is one cheap shape, all of a chunk's in one draw.
- **Inside**, the outside world is not drawn (`WorldManager.set_outdoors_shown`).
- **Stats** caches worked-out stats (call `stats.invalidate()` after editing `base_stats` by hand);
  enemies only look for you a few times a second.
- Merging boxes (`StaticBatch`) and fitting models (`ModelLibrary.fitted`) reuse their measurements.
- New per-frame code: throttle it (a timer), look things up once, and never build meshes or spawn
  several creatures in one frame while the world streams.
