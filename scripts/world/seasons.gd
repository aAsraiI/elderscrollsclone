class_name Seasons
extends RefCounted
## Alpha 1.30.4: what the seasons change (WorldClock.get_season(): 0 winter, 1 spring, 2 summer,
## 3 autumn).
##   farms    the orchard bears most in autumn and nothing in winter; bees are busiest in summer
##            and sleep through winter; the pen gives the same all year
##   herbs    spring flowers (SPRING_HERBS) only bloom in spring and summer
##   fish     bite slower in winter, faster in spring
##   animals  bears sleep through the winter (WildLife leaves them out)

const WINTER := 0
const SPRING := 1
const SUMMER := 2
const AUTUMN := 3
const NAMES := ["winter", "spring", "summer", "autumn"]
## Herbs that only flower in spring and summer
const SPRING_HERBS := ["red_mountain_flower", "cactus_flower", "mandrake_root", "juniper_berries"]


static func now() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var c := tree.get_first_node_in_group("world_clock") as WorldClock if tree != null else null
	return c.get_season() if c != null else SPRING


static func farm_mult(part: String, season: int = -1) -> float:
	var s := now() if season < 0 else season
	match part:
		"orchard":
			return [0.0, 0.5, 1.0, 2.0][s]
		"apiary":
			return [0.0, 1.0, 1.5, 0.75][s]
	return 1.0


static func herb_in_season(item_id: String, season: int = -1) -> bool:
	var s := now() if season < 0 else season
	return not SPRING_HERBS.has(item_id) or s == SPRING or s == SUMMER


static func bite_mult(season: int = -1) -> float:
	var s := now() if season < 0 else season
	return [1.5, 0.8, 1.0, 1.1][s]


static func animal_awake(enemy_id: String, season: int = -1) -> bool:
	var s := now() if season < 0 else season
	return not (s == WINTER and enemy_id.contains("bear"))
