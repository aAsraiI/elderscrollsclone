class_name Residents
extends RefCounted
## Makes the people of a town from its buildings, the same every time for the same world:
## one owner per building (the name on the door), plus guards. See NpcData and TownLife.

const TOWNSFOLK_PATH := "res://data/npcs/townsfolk.tres"
const GUARD_PATH := "res://data/npcs/town_guard.tres"
## Guards per kind of settlement (village, town, city). The first GATE_POSTS stand watch at the
## gates, the rest walk rounds.
const GUARDS := [3, 6, 10]
const GATE_POSTS := 2
const CLOTHES := [Color(0.45, 0.35, 0.25), Color(0.30, 0.42, 0.30), Color(0.50, 0.30, 0.28), Color(0.32, 0.36, 0.50),
	Color(0.55, 0.50, 0.38), Color(0.40, 0.30, 0.42), Color(0.28, 0.40, 0.42), Color(0.58, 0.45, 0.30)]
const GUILD_NAMES := {"fighters": "the Fighters Guild", "mages": "the Mages Guild", "knights": "the Knightly Order"}


static func generate(town: PlacedPOI, map: WorldMap) -> Array[NpcData]:
	var out: Array[NpcData] = []
	var layout := town.town
	if layout == null:
		return out
	var townsfolk := load(TOWNSFOLK_PATH) as EnemyData
	var guard_body := load(GUARD_PATH) as EnemyData
	var for_sale := Homes.for_sale_id(layout, int((town.poi as TownData).kind)) if town.poi is TownData else ""
	var zone := LevelCurve.zone_range(map, town.position) if map != null else Vector2i(1, 5)
	for b in layout.buildings:
		if b.id == for_sale:
			continue  # the empty house for sale (see Homes)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s|npc" % b.id).hash()
		var n := NpcData.new()
		n.id = "npc/" + b.id
		n.display_name = b.owner_name
		n.role = NpcData.role_for_plot(b)
		n.faction = b.guild if b.guild != "" else town.id
		n.personality = rng.randi_range(0, NpcData.Personality.size() - 1) as NpcData.Personality
		n.base_disposition = clampi(50 + rng.randi_range(-15, 15) + (10 if n.personality == NpcData.Personality.FRIENDLY or n.personality == NpcData.Personality.CHEERFUL else 0) - (15 if n.personality == NpcData.Personality.GRUMPY else 0), 0, 100)
		n.home_id = b.id
		n.work_id = b.id if b.is_public() else ""
		n.town_id = town.id
		n.body = townsfolk
		n.level = zone.x
		n.color = CLOTHES[rng.randi_range(0, CLOTHES.size() - 1)]
		n.wake_hour = snappedf(rng.randf_range(5.5, 6.75), 0.25)
		n.work_start = snappedf(rng.randf_range(7.5, 8.75), 0.25)
		n.work_end = snappedf(rng.randf_range(17.0, 18.75), 0.25)
		n.sleep_hour = snappedf(rng.randf_range(20.5, 22.0), 0.25)
		match n.role:
			NpcData.Role.INNKEEPER:
				n.work_start = 7.0
				n.work_end = 23.0
				n.sleep_hour = 23.25
				n.wake_hour = 6.5
			NpcData.Role.FARMER:
				n.work_start = snappedf(rng.randf_range(6.5, 7.25), 0.25)
			NpcData.Role.LORD:
				# The lord holds court from morning to evening, and is proud with strangers
				n.work_start = 8.0
				n.work_end = 19.0
				n.wake_hour = 7.0
				n.sleep_hour = 22.5
				n.personality = NpcData.Personality.PROUD
				n.base_disposition = 40 if b.seat_type == "castle" else 45
				n.level = zone.y
				n.color = NamedSettlements.house_color(b.house).darkened(0.1)
				n.faction = town.id
		out.append(n)
	# at least one guard for every six buildings, so big towns get more
	var guard_count: int = maxi(GUARDS[clampi(int((town.poi as TownData).kind), 0, 2)], layout.buildings.size() / 6)
	for i in guard_count:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s|guard|%d" % [town.id, i]).hash()
		var g := NpcData.new()
		g.id = "npc/%s/guard%d" % [town.id, i]
		g.display_name = "%s Guard" % layout.display_name
		g.role = NpcData.Role.GUARD
		g.faction = "guard"
		g.personality = [NpcData.Personality.PROUD, NpcData.Personality.GRUMPY, NpcData.Personality.FRIENDLY][rng.randi_range(0, 2)]
		g.town_id = town.id
		g.body = guard_body
		g.level = zone.y + 2
		g.color = Color(0.35, 0.40, 0.50)
		g.post = i if i < GATE_POSTS else -1
		out.append(g)
	for n in out:
		n.talk_lines = lines_for(n, layout, out)
	return out


## Talk lines from the person's job, personality and town (until stage 4's dialogue replaces them)
static func lines_for(n: NpcData, layout: TownLayout, everyone: Array[NpcData]) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = (n.id + "|lines").hash()
	var town := layout.display_name
	var out := PackedStringArray()
	match n.personality:
		NpcData.Personality.FRIENDLY:
			out.append("Welcome to %s, traveler!" % town)
		NpcData.Personality.CHEERFUL:
			out.append("Lovely day in %s, isn't it?" % town)
		NpcData.Personality.GRUMPY:
			out.append("What do you want? Make it quick.")
		NpcData.Personality.NERVOUS:
			out.append("Oh! You startled me. Sorry, strangers make me jumpy.")
		NpcData.Personality.PROUD:
			out.append("You're not from %s. I can always tell." % town)
		NpcData.Personality.PIOUS:
			out.append("Blessings on you, stranger.")
	var b: BuildingPlot = null
	for bp in layout.buildings:
		if bp.id == n.home_id:
			b = bp
	match n.role:
		NpcData.Role.MERCHANT:
			out.append("Come by %s. I'm open from %s to %s." % [b.display_name if b != null else "my shop", _hour(n.work_start), _hour(n.work_end)])
		NpcData.Role.INNKEEPER:
			out.append("Best ale in %s at %s. Rooms soon, once I've fixed the roof." % [town, b.display_name if b != null else "my inn"])
		NpcData.Role.SMITH:
			out.append("Need a blade sharpened? The forge is hot from %s." % _hour(n.work_start))
		NpcData.Role.PRIEST:
			out.append("The temple doors are open to all who need them.")
		NpcData.Role.GUILD_MEMBER:
			out.append("%s is always looking for able hands." % String(GUILD_NAMES.get(n.faction, "The guild")).capitalize())
		NpcData.Role.LORD:
			out.append("I hold %s and all its lands. Bring your petitions to %s by day." % [town, b.display_name if b != null else "my hall"])
		NpcData.Role.FARMER:
			out.append(["Crops are coming in well this year.", "Wolves took two of my sheep last week.", "Up before dawn, every day. That's farming."][rng.randi_range(0, 2)])
		NpcData.Role.GUARD:
			out.append(["Keep the peace, citizen.", "I've got my eye on you.", "Trouble on the roads lately. Watch yourself out there."][rng.randi_range(0, 2)])
		_:
			out.append(["I live just down the street.", "Not much happens in %s. That's how we like it." % town, "Mind the mud on the main street."][rng.randi_range(0, 2)])
	# a little gossip about a neighbor
	var others: Array[NpcData] = []
	for o in everyone:
		if o != n and o.role != NpcData.Role.GUARD:
			others.append(o)
	if not others.is_empty():
		var o := others[rng.randi_range(0, others.size() - 1)]
		out.append("Have you met %s? %s" % [o.display_name, ["Good sort.", "Keeps to themselves.", "Owes me money.", "Makes the best bread in town.", "Bit odd, if you ask me."][rng.randi_range(0, 4)]])
	return out


static func _hour(h: float) -> String:
	return "%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)]
