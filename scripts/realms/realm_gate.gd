class_name RealmGate
extends DungeonDoor
## The way into a realm, out in the world: a glowing arch, a ship's gangway, a crack in the
## ground or a diving bell (placeholder shapes). Sealed until a quest opens it (RealmManager).
## Made by RealmManager when you come near; going through works like a dungeon door.

var realm_id := ""
var kind := "portal"


static func make(id: String, p_kind: String) -> RealmGate:
	var g := RealmGate.new()
	g.name = "RealmGate_" + id
	g.realm_id = id
	g.kind = p_kind
	g.entrance_id = RealmManager.ENTRANCE_PREFIX + id
	g.return_offset = Vector3(0.0, 0.0, -4.0)
	g._build_look()
	return g


func get_prompt() -> String:
	var realm_name := RealmManager.display_name(realm_id)
	if not RealmManager.is_open(realm_id):
		return "%s (the way is sealed)" % realm_name
	match kind:
		"ship":
			return "Sail to %s" % realm_name
		"bell":
			return "Go down in the diving bell to %s" % realm_name
		"crack":
			return "Climb down into %s" % realm_name
	return "Enter %s" % realm_name


func interact(actor: Inventory) -> void:
	if not RealmManager.is_open(realm_id):
		Locks.toast(get_tree(), "The way to %s is sealed. Something must call you there first." % RealmManager.display_name(realm_id), true)
		return
	super.interact(actor)


func _build_look() -> void:
	var stone := Color(0.40, 0.38, 0.42)
	var glow := Color(0.55, 0.40, 0.95)
	match kind:
		"ship":
			POIBuilder.add_box(self, Vector3(3.0, 0.3, 8.0), Vector3(0.0, 0.6, 3.0), Color(0.42, 0.30, 0.18))
			POIBuilder.add_box(self, Vector3(0.3, 7.0, 0.3), Vector3(0.0, 3.5, 6.0), Color(0.30, 0.22, 0.14))
			POIBuilder.add_box(self, Vector3(3.6, 3.0, 0.08), Vector3(0.0, 4.5, 6.0), Color(0.88, 0.86, 0.80), 0.0, Vector3.ZERO, false)
			return
		"bell":
			POIBuilder.add_box(self, Vector3(2.4, 2.6, 2.4), Vector3(0.0, 1.3, 2.0), Color(0.55, 0.45, 0.25))
			POIBuilder.add_box(self, Vector3(0.2, 5.0, 0.2), Vector3(-1.6, 2.5, 2.0), Color(0.30, 0.22, 0.14))
			return
		"crack":
			POIBuilder.add_box(self, Vector3(4.0, 0.2, 2.0), Vector3(0.0, 0.05, 1.5), Color(0.05, 0.05, 0.08), 0.0, Vector3.ZERO, false)
			glow = Color(0.40, 0.60, 1.0)
	for side in [-1.0, 1.0]:
		POIBuilder.add_box(self, Vector3(0.8, 4.4, 0.8), Vector3(side * 1.8, 2.2, 0.0), stone)
	POIBuilder.add_box(self, Vector3(4.4, 0.8, 0.8), Vector3(0.0, 4.6, 0.0), stone)
	POIBuilder.add_box(self, Vector3(2.8, 4.0, 0.08), Vector3(0.0, 2.0, 0.0), glow, 0.0, Vector3.ZERO, false, true)
