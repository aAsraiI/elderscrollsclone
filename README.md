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
| `data/` | Content as `.tres` resources: items, enemies, factions, merchants, spawns, world settings |
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
