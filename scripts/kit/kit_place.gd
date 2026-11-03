class_name KitPlace
extends RefCounted
## Where a builder-kit piece stands when the game runs, so the same piece works in any scene you drop it
## into: a house (InteriorBuilder), a dungeon room (StitchedInterior), an outdoor site, or a scene of
## your own. The interior builders leave meta on their nodes, read here from the piece upwards:
##   room_id       a dungeon room or site ("<dungeon>/r3"): one template used twice keeps two save ids
##   building_id   a town building ("building/<id>"), with interior_owner (whose things these are,
##                 "" in your own home) and building_kind (beds: an inn's cost gold)
##   loot_level    the place's level (a dungeon's top level); else the player's level
##   loot_theme    RoomDecorator.THEMES name ("home", "smithy", "crypt"...); else a room's own theme


## The save id prefix for a piece: "kit/<place>/<piece name>"
static func save_prefix(piece: Node) -> String:
	return "kit/%s/%s" % [_place(piece), piece.name]


static func _place(piece: Node) -> String:
	var n := piece.get_parent()
	while n != null:
		if n.has_meta("room_id"):
			return String(n.get_meta("room_id"))
		if n.has_meta("building_id"):
			return "building/" + String(n.get_meta("building_id"))
		n = n.get_parent()
	if piece.owner != null and piece.owner.scene_file_path != "":
		return piece.owner.scene_file_path.get_file().get_basename()
	var dm := piece.get_tree().get_first_node_in_group("dungeon_manager") as DungeonManager if piece.is_inside_tree() else null
	return dm.current_entrance_id if dm != null and dm.current_entrance_id != "" else "world"


## Whose things these are: the piece's own owner_id when set, else the building's ("" = free to take)
static func owner_of(piece: Node, own: String) -> String:
	if own != "":
		return own
	var n := piece.get_parent()
	while n != null:
		if n.has_meta("interior_owner"):
			return String(n.get_meta("interior_owner"))
		n = n.get_parent()
	return ""


## The level loot is rolled at
static func level(piece: Node) -> int:
	var n := piece.get_parent()
	while n != null:
		if n.has_meta("loot_level"):
			return int(n.get_meta("loot_level"))
		n = n.get_parent()
	var p := piece.get_tree().get_first_node_in_group("player") if piece.is_inside_tree() else null
	var skills := p.get_node_or_null("Skills") as Skills if p != null else null
	return skills.get_player_level() if skills != null else 5


## The place's theme: the building's, else the room's own (RoomModule.themes), else "home"
static func theme(piece: Node) -> String:
	var n := piece.get_parent()
	while n != null:
		if n.has_meta("loot_theme"):
			return String(n.get_meta("loot_theme"))
		if n is RoomModule and not (n as RoomModule).themes.is_empty():
			return room_theme(n as RoomModule)
		n = n.get_parent()
	return "home"


## A room's theme as a RoomDecorator.THEMES name (a lair holds what a camp does)
static func room_theme(room: RoomModule) -> String:
	var t := String(room.themes[0]) if not room.themes.is_empty() else "fort"
	return t if RoomDecorator.THEMES.has(t) else {"lair": "camp", "house": "home"}.get(t, "camp")


## The loot tags a piece rolls from: its own when set, else what the place holds (crossed with what
## suits that kind of surface: books on a bookcase, food on a table)
static func tags(piece: Node, own: PackedStringArray, surface: String = "") -> PackedStringArray:
	if not own.is_empty():
		return own
	var place := PackedStringArray(RoomDecorator.THEMES.get(theme(piece), RoomDecorator.THEMES["home"])["tags"])
	return RoomDecorator.surface_tags(surface, place) if surface != "" else place


## Days before taken surface loot comes back: town buildings restock, dungeons and the wild never do
static func restock_days(piece: Node) -> int:
	var n := piece.get_parent()
	while n != null:
		if n.has_meta("building_id"):
			return 3
		n = n.get_parent()
	return 0
