class_name Notes
extends RefCounted
## Alpha 1.24: notes and letters that tell small stories, carried by the dead and left in camps and
## dungeons. A note is an item you can read (ItemUse opens it in the book reader). Made at run time
## like quest items, saved as "note://<index>".

const PREFIX := "note://"
const DROP_CHANCE := 0.18

## [title, text]. Bandits, smugglers, cultists, soldiers, folk on the road.
const POOL := [
	["Orders, Creased", "Hit the carts at the ford after dark. Leave the drivers alive this time. The boss says dead men bring the guard, live ones bring ransom.\n\n- R."],
	["A Letter Home", "Ma,\n\nThe work is not what they said. We sleep in the open and the captain drinks. I have put eleven gold aside. When I have twenty I am coming home, whatever he says.\n\nYour son"],
	["A Fence's Price List", "Silver plate: a third of what it's worth.\nRings: half, if no crest.\nAnything with a crest: don't bring it here.\nAnything that glows: definitely don't bring it here."],
	["A Smuggler's Tide Table", "Low water at the second bell. The cove is clear of the customs boat on oddsdays. Lanterns: one red, wait; two red, run."],
	["A Cultist's Prayer Card", "The sun is a lid on the sky. When it is lifted we will see what waits behind it. Ash to ash, light to dark."],
	["A Soldier's Pass", "Bearer is on the business of the garrison and is not to be delayed at the gate. (The seal is smudged, as if copied by hand.)"],
	["A Debt Reminder", "You owe forty gold and the interest grows every week you hide. We know which inn you sleep in. Pay the man in the grey hood."],
	["A Map Fragment", "...past the split oak, then forty paces toward the hill with the stones. Dig at the foot of the second one. Don't tell your brother."],
	["Half a Love Letter", "...and when this is over I will buy a boat, and we will go where nobody knows either of our names. Wait for me at the lighthouse. Burn this."],
	["A Recruiter's Tally", "Signed this week: 6.\nRan off before the first pay: 4.\nDead: 1 (wolves).\nNote to self: stop recruiting in taverns."],
	["A Cook's Complaint", "If I am to feed twenty men on two sacks of turnips and a goat, I want a raise or I want a second goat."],
	["A Will, Unwitnessed", "Everything I have goes to whoever buries me properly. That's fair. Most of you would just leave me."],
]


static var _items := {}


## A note item (the same one for the same index)
static func get_item(index: int) -> ItemData:
	index = posmod(index, POOL.size())
	if _items.has(index):
		return _items[index]
	var it := ItemData.new()
	it.id = StringName("note_%d" % index)
	it.display_name = String(POOL[index][0])
	it.description = "A note. Read it from your pack."
	it.item_type = ItemData.ItemType.MISC
	it.weight = 0.05
	it.value = 1
	it.set_meta("note_text", String(POOL[index][1]))
	it.set_meta("save_path", "%s%d" % [PREFIX, index])
	_items[index] = it
	return it


static func is_note(item: ItemData) -> bool:
	return item != null and item.has_meta("note_text")


static func is_path(path: String) -> bool:
	return path.begins_with(PREFIX)


static func from_path(path: String) -> ItemData:
	return get_item(int(path.trim_prefix(PREFIX)))


## A person (not a beast) who dies may have been carrying one
static func maybe_carry(e: Enemy, rng: RandomNumberGenerator) -> void:
	if e == null or e.inventory == null or e.body_kind != CreatureBody.Kind.HUMANOID or e.has_meta("animal"):
		return
	if rng.randf() > DROP_CHANCE:
		return
	e.inventory.add_item(get_item(rng.randi()), 1)
