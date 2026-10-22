WORLD POPULATION: copy this folder's contents over your project (the folders match: scripts/, scripts/World/,
scripts/Resources/). Then Project > Reload Current Project. No scene changes are needed.

If you edited the biome / POI / dungeon .tres files since you uploaded them, DON'T copy
scripts/Resources/World/. Run the tool instead, it only adds lines to your files:
    python3 tools/generate_content.py <folder that contains scripts/>
(it also regenerates every item, enemy, spawn table and encounter, so you can rebalance in one place).

test/ holds the automated tests (optional): godot --headless --fixed-fps 60 -s res://test/test_population.gd
