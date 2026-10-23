class_name GameState
extends RefCounted
## The one place that wipes what a game leaves behind, so a new game or a loaded save never
## inherits anything from the game played before it.
##
## Static variables live as long as the program runs, so anything a game keeps in one (the world's
## records, the rules, runtime-made keys and quest items...) must be cleared here. Caches of content
## that never changes (items, spells, meshes) are left alone. When you add a static variable that
## holds per-game state, clear it in reset().


## Called just before a new game starts or a save is loaded (the game scene reloads right after)
static func reset() -> void:
	WorldState.clear()
	GameRules.reset()
	CharacterSetup.pending = {}
	CraftedItems.clear_cache()
	DialogueState.clear_temp()
	KeyRing.clear()
	QuestItems.clear()
	ActorRegistry.clear()
	Engine.time_scale = 1.0  # a hit-stop can't outlive its game
