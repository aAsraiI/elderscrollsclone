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
| `scenes/game/` | Main menu and the game world scene |
| `scenes/player/` | The player |
| `scripts/<area>/` | Code by area: `actors`, `audio`, `character`, `combat`, `core`, `crafting`, `dialogue`, `dungeons`, `factions`, `items`, `magic`, `player`, `quests`, `realms`, `save`, `towns`, `trade`, `ui`, `world` |
| `data/` | Content as `.tres` resources: items, enemies, factions, merchants, spawns, world settings |
| `ui/` | The UI theme |
| `tools/` | Editor tools that generate content (`generate_*.gd`, `build_*.gd`) and `check_scripts.gd` |
| `test/` | Automated test suites |
| `addons/godot_ai/` | Godot AI editor plugin |

## Tests

Check that every script compiles:

    godot --headless --path . -s res://tools/check_scripts.gd

Run one suite (each prints PASS / FAIL lines and a total):

    godot --headless --fixed-fps 60 --path . -s res://test/test_stage1.gd
