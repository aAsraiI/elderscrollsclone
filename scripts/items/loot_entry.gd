class_name LootEntry
extends Resource
## One line of a container's contents. Fill the container's "Contents" array with these.
## Create in the editor: in the Inspector, click the Contents array > add element > New LootEntry.

@export var item: ItemData
@export var min_count: int = 1
@export var max_count: int = 1
## 1.0 = always present, 0.25 = a 25% chance
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
