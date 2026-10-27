class_name CreatureBody
extends Node3D
## A jointed body built from simple shapes, animated in code. Every Enemy and townsperson gets one
## (Enemy._build_body), so nothing needs to be modeled or imported.
##
## Kinds:  HUMANOID (people, skeletons, trolls, giants), BEAST (wolves, bears, rats, stalkers),
##         CRAWLER (six legs), SPIRIT (floats, no legs)
## Bones are plain Node3Ds with box / capsule meshes under them. Each frame the animator looks at its
## Enemy (speed, AI state, the MeleeCombat swing phase, blocking, casting, `pose`) and turns the
## bones toward a target pose: walking and running cycles, guard, wind-up and swing (up-and-over
## for single-target weapons, a sweep for arcs, both hands for two-handers), block, shield bash,
## stagger, flinch, casting, and calm poses for townsfolk (sit, sleep, kneel to pray, hammer at the
## anvil, chop wood, work a field, chat with gestures, drink).
## On death Ragdoll.create() turns the bones into physics bodies joined at the joints.

enum Kind { HUMANOID, BEAST, CRAWLER, SPIRIT }

## Distance (m) beyond which the animation only updates a few times a second
const LOD_NEAR := 30.0
## Beyond this it stops animating altogether (it is just a statue in the distance)
const LOD_FAR := 90.0
## Past this the body is not drawn at all (fog hides it long before)
const DRAW_DISTANCE := 150.0

var kind: Kind = Kind.HUMANOID
## Whose body this is: an Enemy, or the player (player.gd has the same few fields: velocity,
## state, combat, equipment, display_name, body_scale, placeholder_color)
var enemy
## Calm activity pose, set by TownLife / the Enemy: &"" (normal), &"sit", &"sleep", &"pray",
## &"work", &"chop", &"farm", &"talk", &"drink", &"sweep", &"paralyzed"
var pose: StringName = &""
## 0..1 while a spell is charging in the left hand (Enemy casters)
var cast_charge := 0.0
var cast_color := Color(1.0, 0.5, 0.2)
## 0..1 how far a bow is drawn (enemy archers)
var bow_draw := 0.0

## Enemy types that are walking dead (skeleton bodies when there is no model for the type itself)
const UNDEAD := ["skeleton", "skeleton_knight", "crypt_warden", "barrow_wight", "wight_lord", "vault_guardian", "vault_sentinel"]

## A real model drawn instead of the boxes (ModelBody), when ModelLibrary has one
var model_body: ModelBody
var _model_checked := false

var bones: Dictionary = {}       # name -> Node3D
var grip: Node3D                 # right hand: weapons hang here (blade along -Z)
var off_grip: Node3D             # left forearm: shields hang here
var mats: Array[StandardMaterial3D] = []
var base_colors: Array[Color] = []

var _phase := 0.0
var _speed := 0.0
var _time := 0.0
var _flinch := 0.0
var _glow := 0.0
var _glow_color := Color(1.0, 0.5, 0.1)
var _flash := 0.0
var _last_emission := Color(0, 0, 0, 0)
var _lod_timer := 0.0
var _hand_orb: Node3D
var _gesture := 0.0
var _gesture_seed := 0.0
var _rng := RandomNumberGenerator.new()

# Materials (one set per body so glows and flashes are its own)
var m_skin: StandardMaterial3D
var m_cloth: StandardMaterial3D
var m_pants: StandardMaterial3D
var m_boots: StandardMaterial3D
var m_hair: StandardMaterial3D
var m_metal: StandardMaterial3D


## Builds the body for an Enemy. seed_value keeps the same person looking the same every time.
static func build_for(e: Node3D, p_kind: Kind, seed_value: int) -> CreatureBody:
	var b := CreatureBody.new()
	b.name = "Body"
	b.enemy = e
	b.kind = p_kind
	b._rng.seed = seed_value
	b._gesture_seed = float(seed_value % 1000) * 0.37
	b.scale = Vector3.ONE * e.body_scale
	match p_kind:
		Kind.HUMANOID:
			b._build_humanoid(e.placeholder_color)
		Kind.BEAST:
			b._build_beast(e.placeholder_color)
		Kind.CRAWLER:
			b._build_crawler(e.placeholder_color)
		Kind.SPIRIT:
			b._build_spirit(e.placeholder_color)
	if p_kind != Kind.HUMANOID:
		b._try_model()  # people wait for their gear (dress) to pick theirs
	return b


# ---------------------------------------------------------------- real models

## Picks a model for this body from ModelLibrary (its enemy type first, then by what it is).
## Without one the boxes stay.
func _try_model() -> void:
	if _model_checked:
		return
	_model_checked = true
	var key := ModelLibrary.first(model_keys())
	if key != "":
		model_body = ModelBody.attach(self, key)


## The ModelLibrary keys this body would use, best first
func model_keys() -> Array:
	var out: Array = []
	# A look chosen by hand (a quest NPC, a test): meta "model_key" on the owner
	if enemy != null and enemy.has_meta("model_key"):
		out.append(String(enemy.get_meta("model_key")))
	var id := ""
	if enemy is Enemy:
		id = (enemy as Enemy).enemy_id
		if id != "":
			out.append("creature/" + id)
	elif enemy is Horse:
		out.append("creature/horse")
	if kind != Kind.HUMANOID:
		return out
	var lower := String(enemy.display_name).to_lower() if enemy != null else ""
	var style := -1
	if enemy is Enemy:
		style = (enemy as Enemy).style
	var equipment: Equipment = enemy.equipment if enemy != null else null
	var heavy := false
	var has_weapon := false
	if equipment != null:
		var chest: ItemData = equipment.get_equipped(ItemData.EquipSlot.CHEST)
		heavy = chest != null and chest.governing_skill == "heavy_armor"
		has_weapon = equipment.get_main_hand() != null
	var hostile: bool = enemy is Enemy and (enemy as Enemy).disposition == Enemy.Disposition.HOSTILE
	var pick := _rng.randi()
	var is_player := not (enemy is Enemy) and not (enemy is Horse)
	var prefix := "people/"
	# Undead and monsters by what they are (their type), so a "Road Warden" or a "Guardian of the Gate" is
	# still a person; names only for those without a type
	var what := id if id != "" else lower
	if what in UNDEAD or (id == "" and (lower.contains("skeleton") or lower.contains("wight"))):
		if style == Enemy.Style.MAGE:
			out.append("people/skeleton_mage")
		elif style == Enemy.Style.ARCHER:
			out.append("people/skeleton_rogue")
		elif heavy or lower.contains("knight") or lower.contains("lord"):
			out.append("people/skeleton_warrior")
		out.append("people/skeleton")
	elif what in ["grave_ghoul", "drowned_sailor"] or lower.begins_with("risen ") or (id == "" and (lower.contains("ghoul") or lower.contains("zombie"))):
		out.append("people/zombie")
	elif what in ["cave_troll", "forest_troll", "frost_giant", "werewolf"]:
		out.append("people/brute")
	if style == Enemy.Style.MAGE or lower.contains("priest") or lower.contains("cultist") or lower.contains("hag") or lower.contains("mage"):
		out.append(prefix + "mage")
	if heavy:
		out.append(prefix + "knight")
	if style == Enemy.Style.ARCHER:
		out.append(prefix + "archer")
	if hostile or has_weapon or is_player:
		out.append(prefix + ("fighter_a" if pick % 2 == 0 else "fighter_b"))
	var first_name := String(enemy.display_name).get_slice(" ", 0) if enemy != null else ""
	var woman := first_name in NameGen.FEMININE if first_name in NameGen.FIRST else pick % 2 == 1
	if is_player:
		woman = int((enemy.get_meta("character", {}) as Dictionary).get("sex", 0)) == 1
	out.append(prefix + ("woman_%d" if woman else "man_%d") % (1 + (pick / 2) % 3))
	out.append(prefix + "man_1")
	out.append("people/man_1")
	if is_player:
		# "player/<look>" (your own model for yourself) before the shared people models
		var own: Array = []
		for k in out:
			if String(k).begins_with("people/"):
				own.append("player/" + String(k).trim_prefix("people/"))
		out = own + ["player/body"] + out
	return out


## Which kind of body an enemy type gets (by its EnemyData id)
static func kind_for(id: String) -> Kind:
	match id:
		"wolf", "giant_rat", "frost_bear", "dune_stalker", "bog_lurker", "ash_hound", "harpy", "grave_ghoul", "dragon", "sheep", "cow", "hound":
			return Kind.BEAST
		"deep_crawler", "crawler_queen", "giant_spider", "sand_scorpion":
			return Kind.CRAWLER
		"fire_spirit", "ice_wraith":
			return Kind.SPIRIT
	return Kind.HUMANOID


# ---------------------------------------------------------------- materials

func _mat(color: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = Color.BLACK
	mats.append(m)
	base_colors.append(color)
	return m


func _part(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.rotation = rot
	mi.material_override = mat
	mi.visibility_range_end = DRAW_DISTANCE
	parent.add_child(mi)
	return mi


func _bone(bone_name: String, parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = bone_name
	n.position = at
	parent.add_child(n)
	bones[bone_name] = n
	return n


static var _meshes := {}


static func _box(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "c%.3f|%.3f" % [radius, height]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		m.radial_segments = 8
		m.rings = 2
		_meshes[key] = m
	return _meshes[key]


static func _sphere(radius: float) -> SphereMesh:
	var key := "s%.3f" % radius
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 10
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


const SKIN_TONES: Array[Color] = [Color(0.93, 0.78, 0.65), Color(0.85, 0.66, 0.5), Color(0.68, 0.49, 0.35),
	Color(0.5, 0.35, 0.24), Color(0.36, 0.25, 0.18), Color(0.96, 0.84, 0.74)]
const HAIR_COLORS: Array[Color] = [Color(0.12, 0.09, 0.07), Color(0.32, 0.2, 0.1), Color(0.55, 0.38, 0.2),
	Color(0.78, 0.65, 0.4), Color(0.6, 0.6, 0.6), Color(0.45, 0.15, 0.08)]


# ---------------------------------------------------------------- humanoid

func _build_humanoid(cloth: Color) -> void:
	var undead: bool = enemy != null and (enemy.display_name.to_lower().contains("skeleton") or enemy.display_name.to_lower().contains("wight") or enemy.display_name.to_lower().contains("warden"))
	var troll: bool = enemy != null and (enemy.display_name.to_lower().contains("troll") or enemy.display_name.to_lower().contains("werewolf") or enemy.display_name.to_lower().contains("giant"))
	var skin_color := SKIN_TONES[_rng.randi() % SKIN_TONES.size()]
	var look: Dictionary = enemy.get_meta("look", {}) if enemy != null else {}
	if look.has("skin"):
		skin_color = look["skin"]
	if undead:
		skin_color = Color(0.82, 0.8, 0.72)
	elif troll:
		skin_color = cloth.lerp(Color(0.45, 0.5, 0.4), 0.6)
	m_skin = _mat(skin_color)
	m_cloth = _mat(cloth)
	m_pants = _mat(cloth.darkened(0.45).lerp(Color(0.3, 0.25, 0.2), 0.5))
	m_boots = _mat(Color(0.22, 0.15, 0.1))
	m_hair = _mat(look.get("hair", HAIR_COLORS[_rng.randi() % HAIR_COLORS.size()]))
	m_metal = _mat(Color(0.55, 0.56, 0.6), 0.45, 0.6)
	var limb_skin := m_skin if (undead or troll) else m_cloth
	var hips := _bone("hips", self, Vector3(0, 0.95, 0))
	_part(hips, _box(Vector3(0.36, 0.2, 0.22)), Vector3.ZERO, m_pants)
	var spine := _bone("spine", hips, Vector3(0, 0.08, 0))
	_part(spine, _box(Vector3(0.42 if not undead else 0.3, 0.55, 0.24)), Vector3(0, 0.3, 0), m_cloth if not undead else m_skin)
	_part(spine, _box(Vector3(0.44, 0.06, 0.26)), Vector3(0, 0.04, 0), m_boots)  # belt
	var neck := _bone("neck", spine, Vector3(0, 0.58, 0))
	_part(neck, _sphere(0.13), Vector3(0, 0.15, 0), m_skin)
	if not undead:
		_part(neck, _box(Vector3(0.26, 0.09, 0.26)), Vector3(0, 0.26, 0.02), m_hair)
		if _rng.randf() < 0.5:
			_part(neck, _box(Vector3(0.24, 0.16, 0.06)), Vector3(0, 0.2, 0.12), m_hair)  # long hair
	_part(neck, _box(Vector3(0.04, 0.05, 0.06)), Vector3(0, 0.13, -0.13), m_skin)  # nose
	var eye := _mat(Color(0.05, 0.05, 0.05) if not undead else Color(0.2, 0.8, 1.0))
	for side in [-1.0, 1.0]:
		_part(neck, _box(Vector3(0.04, 0.025, 0.02)), Vector3(side * 0.05, 0.18, -0.12), eye)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var shoulder := _bone(side + "_shoulder", spine, Vector3(sx * 0.27, 0.52, 0))
		_part(shoulder, _capsule(0.07, 0.34), Vector3(0, -0.15, 0), limb_skin)
		var elbow := _bone(side + "_elbow", shoulder, Vector3(0, -0.3, 0))
		_part(elbow, _capsule(0.06, 0.3), Vector3(0, -0.13, 0), m_skin)
		var hand := _bone(side + "_hand", elbow, Vector3(0, -0.29, 0))
		_part(hand, _box(Vector3(0.08, 0.1, 0.06)), Vector3(0, -0.03, 0), m_skin)
		var hip := _bone(side + "_hip", hips, Vector3(sx * 0.1, -0.06, 0))
		_part(hip, _capsule(0.085, 0.46), Vector3(0, -0.21, 0), m_pants if not undead else m_skin)
		var knee := _bone(side + "_knee", hip, Vector3(0, -0.43, 0))
		_part(knee, _capsule(0.07, 0.44), Vector3(0, -0.2, 0), m_pants if not undead else m_skin)
		var foot := _bone(side + "_foot", knee, Vector3(0, -0.42, 0))
		_part(foot, _box(Vector3(0.11, 0.08, 0.24)), Vector3(0, -0.02, -0.05), m_boots)
	grip = Node3D.new()
	grip.name = "Grip"
	grip.position = Vector3(0, -0.06, 0)
	bones["r_hand"].add_child(grip)
	off_grip = Node3D.new()
	off_grip.name = "OffGrip"
	off_grip.position = Vector3(-0.08, -0.15, 0)
	off_grip.rotation = Vector3(0, PI * 0.5, 0)
	bones["l_elbow"].add_child(off_grip)


## Armor on a humanoid: metal or leather over the right parts, a helmet. Called whenever gear changes.
func dress(equipment: Equipment) -> void:
	if kind != Kind.HUMANOID or equipment == null:
		return
	_try_model()
	for b in bones.values():
		for c in (b as Node3D).get_children():
			if c.has_meta("armor_piece"):
				c.queue_free()
	var pieces := {}
	for slot in equipment.slots:
		var item: ItemData = equipment.slots[slot]
		if item != null and item.item_type == ItemData.ItemType.ARMOR:
			pieces[slot] = item
	var chest: ItemData = pieces.get(ItemData.EquipSlot.CHEST)
	if chest != null:
		var m := _armor_mat(chest)
		_armor(bones["spine"], _box(Vector3(0.46, 0.5, 0.28)), Vector3(0, 0.32, 0), m)
		for side in ["l", "r"]:
			_armor(bones[side + "_shoulder"], _box(Vector3(0.17, 0.12, 0.17)), Vector3(0, 0.0, 0), m)
	var head: ItemData = pieces.get(ItemData.EquipSlot.HEAD)
	if head != null:
		var m := _armor_mat(head)
		_armor(bones["neck"], _box(Vector3(0.3, 0.2, 0.3)), Vector3(0, 0.25, 0.01), m)
		if head.governing_skill == "heavy_armor":
			_armor(bones["neck"], _box(Vector3(0.05, 0.14, 0.04)), Vector3(0, 0.15, -0.14), m)
	var legs: ItemData = pieces.get(ItemData.EquipSlot.LEGS)
	if legs != null:
		var m := _armor_mat(legs)
		for side in ["l", "r"]:
			_armor(bones[side + "_hip"], _box(Vector3(0.19, 0.4, 0.19)), Vector3(0, -0.2, 0), m)
			_armor(bones[side + "_knee"], _box(Vector3(0.16, 0.34, 0.16)), Vector3(0, -0.16, 0), m)
	var hands: ItemData = pieces.get(ItemData.EquipSlot.HANDS)
	if hands != null:
		var m := _armor_mat(hands)
		for side in ["l", "r"]:
			_armor(bones[side + "_elbow"], _box(Vector3(0.14, 0.2, 0.14)), Vector3(0, -0.2, 0), m)
	var feet: ItemData = pieces.get(ItemData.EquipSlot.FEET)
	if feet != null:
		var m := _armor_mat(feet)
		for side in ["l", "r"]:
			_armor(bones[side + "_foot"], _box(Vector3(0.14, 0.14, 0.28)), Vector3(0, 0.02, -0.05), m)


const HEAVY_TINTS: Array[Color] = [Color(0.45, 0.45, 0.48), Color(0.62, 0.64, 0.68), Color(0.82, 0.84, 0.88),
	Color(0.16, 0.13, 0.22), Color(0.11, 0.11, 0.13), Color(0.86, 0.82, 0.7), Color(0.5, 0.6, 0.92)]
const LIGHT_TINTS: Array[Color] = [Color(0.48, 0.35, 0.22), Color(0.35, 0.22, 0.12), Color(0.7, 0.7, 0.76),
	Color(0.2, 0.26, 0.22), Color(0.15, 0.15, 0.2), Color(0.55, 0.32, 0.22), Color(0.4, 0.45, 0.72)]
var _armor_mats := {}


func _armor_mat(item: ItemData) -> StandardMaterial3D:
	var heavy := item.governing_skill == "heavy_armor"
	var t := clampi(item.tier - 1, 0, 6)
	var key := "%s%d" % ["h" if heavy else "l", t]
	if not _armor_mats.has(key):
		var c: Color = HEAVY_TINTS[t] if heavy else LIGHT_TINTS[t]
		_armor_mats[key] = _mat(c, 0.4 if heavy else 0.8, 0.65 if heavy else 0.0)
	return _armor_mats[key]


func _armor(parent: Node3D, mesh: Mesh, at: Vector3, m: Material) -> void:
	var mi := _part(parent, mesh, at, m)
	mi.set_meta("armor_piece", true)


## The weapon in the right hand (and a shield / second weapon in the left)
func set_weapons(main: ItemData, off: ItemData) -> void:
	if grip != null:
		for c in grip.get_children():
			c.queue_free()
		if main != null:
			grip.add_child(_weapon_model(main))
	if off_grip != null:
		for c in off_grip.get_children():
			c.queue_free()
		for c in bones.get("l_hand", self).get_children():
			if c.has_meta("weapon_model"):
				c.queue_free()
		if off != null:
			if off.secondary_action == ItemData.SecondaryAction.BLOCK and off.item_type != ItemData.ItemType.WEAPON and ModelLibrary.first(ItemModels.model_keys(off)) != "":
				var held := ItemModels.build_view(off)
				held.set_meta("weapon_model", true)
				off_grip.add_child(held)
			elif off.secondary_action == ItemData.SecondaryAction.BLOCK and off.item_type != ItemData.ItemType.WEAPON:
				var shield := _part(off_grip, _box(Vector3(0.55, 0.65, 0.06)), Vector3.ZERO, _metal_for(off))
				shield.set_meta("weapon_model", true)
			elif model_body != null and model_body.left_holder() != null:
				var w := _weapon_model(off)
				model_body.left_holder().add_child(w)
			elif bones.has("l_hand"):
				var w := _weapon_model(off)
				w.position = Vector3(0, -0.06, 0)
				bones["l_hand"].add_child(w)


func _metal_for(item: ItemData) -> StandardMaterial3D:
	var key := "w%d" % item.tier
	if not _armor_mats.has(key):
		_armor_mats[key] = _mat(HEAVY_TINTS[clampi(item.tier - 1, 0, 6)], 0.35, 0.7)
	return _armor_mats[key]


func _weapon_model(w: ItemData) -> Node3D:
	var root := Node3D.new()
	root.set_meta("weapon_model", true)
	if w.view_scene != null or ModelLibrary.first(ItemModels.model_keys(w)) != "":
		# The same model the player holds: its blade runs up +Y from the grip, here it points along -Z
		var held := ItemModels.build_view(w)
		held.rotation.x = -PI * 0.5
		root.add_child(held)
		return root
	var metal := _metal_for(w)
	var wood := _mat(Color(0.35, 0.22, 0.12))
	var length := clampf(w.reach * 0.42, 0.35, 1.5)
	var handle := 0.18 if not w.two_handed else 0.4
	_part(root, _box(Vector3(0.04, 0.04, handle)), Vector3(0, 0, handle * 0.5 - 0.06), wood)
	if w.is_bow:
		for s in [-1.0, 1.0]:
			_part(root, _box(Vector3(0.03, 0.55, 0.035)), Vector3(0, s * 0.3, -0.05), wood, Vector3(-s * 0.35, 0, 0))
		_part(root, _box(Vector3(0.005, 1.0, 0.005)), Vector3(0, 0, 0.08), _mat(Color(0.9, 0.9, 0.85)))
		return root
	match w.animation_set:
		&"hammer", &"mace":
			_part(root, _box(Vector3(0.04, 0.04, length)), Vector3(0, 0, -length * 0.5), wood)
			var head_size := Vector3(0.28, 0.18, 0.18) if w.animation_set == &"hammer" else Vector3(0.14, 0.14, 0.18)
			_part(root, _box(head_size), Vector3(0, 0, -length), metal)
		&"axe":
			_part(root, _box(Vector3(0.04, 0.04, length)), Vector3(0, 0, -length * 0.5), wood)
			_part(root, _box(Vector3(0.03, 0.22, 0.16)), Vector3(0, 0.08, -length + 0.05), metal)
		&"spear":
			_part(root, _box(Vector3(0.035, 0.035, length)), Vector3(0, 0, -length * 0.5), wood)
			_part(root, _box(Vector3(0.05, 0.05, 0.22)), Vector3(0, 0, -length - 0.1), metal)
		_:
			_part(root, _box(Vector3(0.14, 0.03, 0.04)), Vector3(0, 0, -0.02), metal)  # crossguard
			_part(root, _box(Vector3(0.06, 0.015, length)), Vector3(0, 0, -length * 0.5 - 0.04), metal)
	return root


# ---------------------------------------------------------------- beasts

func _build_beast(fur: Color) -> void:
	if enemy != null and enemy.display_name.to_lower().contains("dragon"):
		_build_dragon(fur)
		return
	var big: bool = enemy != null and enemy.display_name.to_lower().contains("bear")
	m_cloth = _mat(fur)
	m_skin = _mat(fur.darkened(0.3))
	m_boots = _mat(fur.darkened(0.5))
	m_hair = _mat(Color(0.95, 0.92, 0.85))
	var height := 0.62 if not big else 0.8
	var length := 1.0 if not big else 1.3
	var width := 0.3 if not big else 0.6
	var torso := _bone("torso", self, Vector3(0, height, 0))
	_part(torso, _box(Vector3(width, width * (1.0 if not big else 0.9) + 0.05, length)), Vector3(0, 0.08, 0), m_cloth)
	var neck := _bone("neck", torso, Vector3(0, 0.15, -length * 0.5))
	_part(neck, _box(Vector3(width * 0.75, width * 0.75, 0.3)), Vector3(0, 0.05, -0.12), m_cloth)
	var head := _bone("head", neck, Vector3(0, 0.08, -0.28))
	_part(head, _box(Vector3(width * 0.8, width * 0.7, 0.26)), Vector3(0, 0, -0.08), m_cloth)
	_part(head, _box(Vector3(width * 0.45, width * 0.35, 0.22)), Vector3(0, -0.05, -0.3), m_skin)  # snout
	var jaw := _bone("jaw", head, Vector3(0, -0.1, -0.15))
	_part(jaw, _box(Vector3(width * 0.4, 0.05, 0.22)), Vector3(0, -0.02, -0.12), m_skin)
	for side in [-1.0, 1.0]:
		_part(head, _box(Vector3(0.06, 0.12, 0.04)), Vector3(side * width * 0.3, width * 0.4, -0.02), m_skin)  # ears
		_part(head, _box(Vector3(0.04, 0.03, 0.02)), Vector3(side * width * 0.22, 0.06, -0.21), _eye_mat())
	var legs := {"fl": Vector3(-width * 0.4, 0, -length * 0.38), "fr": Vector3(width * 0.4, 0, -length * 0.38),
		"bl": Vector3(-width * 0.4, 0, length * 0.38), "br": Vector3(width * 0.4, 0, length * 0.38)}
	var leg_len := height * 0.55
	for k in legs:
		var hip := _bone(k + "_hip", torso, legs[k])
		_part(hip, _capsule(0.07 if not big else 0.12, leg_len), Vector3(0, -leg_len * 0.45, 0), m_cloth)
		var knee := _bone(k + "_knee", hip, Vector3(0, -leg_len * 0.9, 0))
		_part(knee, _capsule(0.05 if not big else 0.09, leg_len), Vector3(0, -leg_len * 0.45, 0), m_skin)
		_part(knee, _box(Vector3(0.1, 0.05, 0.14) * (1.0 if not big else 1.6)), Vector3(0, -leg_len * 0.9, -0.03), m_boots)
	var tail := _bone("tail", torso, Vector3(0, 0.18, length * 0.5))
	_part(tail, _capsule(0.05, 0.45 if not big else 0.16), Vector3(0, 0, 0.18), m_cloth, Vector3(PI * 0.5, 0, 0))


# A dragon: the beast's bones (so it walks and bites like one) on a long scaled body, with horns,
# a spined tail and two great wings that beat slowly (see _animate_beast)
func _build_dragon(scales: Color) -> void:
	m_cloth = _mat(scales, 0.6)
	m_skin = _mat(scales.darkened(0.35), 0.7)
	m_boots = _mat(Color(0.15, 0.13, 0.12))
	m_hair = _mat(Color(0.82, 0.78, 0.66))  # horns and claws
	var height := 1.05
	var length := 2.4
	var width := 0.95
	var torso := _bone("torso", self, Vector3(0, height, 0))
	_part(torso, _box(Vector3(width, width * 0.85, length)), Vector3(0, 0.1, 0), m_cloth)
	_part(torso, _box(Vector3(width * 0.7, 0.2, length * 0.9)), Vector3(0, -0.32, 0), m_skin)  # pale belly plates
	for i in 6:
		_part(torso, _box(Vector3(0.08, 0.28, 0.2)), Vector3(0, width * 0.5 + 0.12, -length * 0.4 + i * length * 0.16), m_hair)
	var neck := _bone("neck", torso, Vector3(0, 0.3, -length * 0.5))
	_part(neck, _box(Vector3(width * 0.5, width * 0.5, 1.0)), Vector3(0, 0.25, -0.4), m_cloth, Vector3(0.45, 0, 0))
	var head := _bone("head", neck, Vector3(0, 0.55, -0.9))
	_part(head, _box(Vector3(width * 0.55, width * 0.45, 0.6)), Vector3(0, 0, -0.15), m_cloth)
	_part(head, _box(Vector3(width * 0.4, width * 0.25, 0.45)), Vector3(0, -0.05, -0.6), m_skin)  # snout
	var jaw := _bone("jaw", head, Vector3(0, -0.2, -0.3))
	_part(jaw, _box(Vector3(width * 0.35, 0.1, 0.55)), Vector3(0, -0.04, -0.25), m_skin)
	for side in [-1.0, 1.0]:
		_part(head, _box(Vector3(0.08, 0.08, 0.6)), Vector3(side * width * 0.2, 0.25, 0.25), m_hair, Vector3(0.6, side * 0.3, 0))  # horns
		_part(head, _box(Vector3(0.07, 0.05, 0.03)), Vector3(side * width * 0.2, 0.08, -0.45), _eye_mat())
	var legs := {"fl": Vector3(-width * 0.45, 0, -length * 0.35), "fr": Vector3(width * 0.45, 0, -length * 0.35),
		"bl": Vector3(-width * 0.45, 0, length * 0.35), "br": Vector3(width * 0.45, 0, length * 0.35)}
	var leg_len := height * 0.55
	for k in legs:
		var hip := _bone(k + "_hip", torso, legs[k])
		_part(hip, _capsule(0.17, leg_len), Vector3(0, -leg_len * 0.45, 0), m_cloth)
		var knee := _bone(k + "_knee", hip, Vector3(0, -leg_len * 0.9, 0))
		_part(knee, _capsule(0.13, leg_len), Vector3(0, -leg_len * 0.45, 0), m_skin)
		_part(knee, _box(Vector3(0.3, 0.08, 0.36)), Vector3(0, -leg_len * 0.9, -0.08), m_hair)
	var tail := _bone("tail", torso, Vector3(0, 0.15, length * 0.5))
	_part(tail, _box(Vector3(width * 0.45, width * 0.4, 1.4)), Vector3(0, 0, 0.7), m_cloth)
	var tip := _bone("tail_tip", tail, Vector3(0, 0, 1.4))
	_part(tip, _box(Vector3(width * 0.22, width * 0.2, 1.3)), Vector3(0, 0, 0.65), m_cloth)
	_part(tip, _box(Vector3(0.5, 0.06, 0.4)), Vector3(0, 0, 1.3), m_hair)
	var membrane := _mat(scales.darkened(0.5).lerp(Color(0.4, 0.1, 0.08), 0.3), 0.9)
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var wing := _bone("wing_" + ("l" if side < 0 else "r"), torso, Vector3(side * width * 0.45, width * 0.45, -length * 0.15))
		_part(wing, _box(Vector3(2.2, 0.08, 0.12)), Vector3(side * 1.1, 0.15, 0), m_skin, Vector3(0, 0, side * 0.15))  # the arm
		_part(wing, _box(Vector3(2.1, 0.02, 1.5)), Vector3(side * 1.05, 0.08, 0.75), membrane, Vector3(0, 0, side * 0.15))


func _eye_mat() -> StandardMaterial3D:
	var m := _mat(Color(0.9, 0.75, 0.2))
	m.emission = Color(0.6, 0.45, 0.1)
	return m


func _build_crawler(shell: Color) -> void:
	m_cloth = _mat(shell, 0.4, 0.2)
	m_skin = _mat(shell.darkened(0.4))
	m_boots = _mat(shell.darkened(0.6))
	var torso := _bone("torso", self, Vector3(0, 0.45, 0))
	_part(torso, _sphere(0.32), Vector3(0, 0, 0.35), m_cloth)
	_part(torso, _box(Vector3(0.4, 0.22, 0.5)), Vector3(0, 0, -0.05), m_cloth)
	var head := _bone("head", torso, Vector3(0, 0.02, -0.32))
	_part(head, _box(Vector3(0.3, 0.18, 0.22)), Vector3(0, 0, -0.08), m_skin)
	for side in [-1.0, 1.0]:
		var mand := _bone("mand_" + ("l" if side < 0 else "r"), head, Vector3(side * 0.1, -0.05, -0.18))
		_part(mand, _box(Vector3(0.04, 0.04, 0.2)), Vector3(0, 0, -0.08), m_boots)
		_part(head, _box(Vector3(0.05, 0.05, 0.03)), Vector3(side * 0.08, 0.06, -0.19), _eye_mat())
	for i in 3:
		for side in [-1.0, 1.0]:
			var k := "%s%d" % ["l" if side < 0 else "r", i]
			var hip := _bone(k + "_hip", torso, Vector3(side * 0.2, 0, -0.2 + float(i) * 0.2))
			hip.rotation.z = side * 1.0
			_part(hip, _capsule(0.035, 0.42), Vector3(0, -0.19, 0), m_skin)
			var knee := _bone(k + "_knee", hip, Vector3(0, -0.38, 0))
			knee.rotation.z = -side * 1.6
			_part(knee, _capsule(0.03, 0.5), Vector3(0, -0.23, 0), m_boots)


func _build_spirit(color: Color) -> void:
	m_cloth = _mat(color)
	m_cloth.emission = color
	m_cloth.emission_energy_multiplier = 1.2
	m_cloth.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_cloth.albedo_color.a = 0.85
	base_colors[base_colors.size() - 1] = m_cloth.albedo_color
	m_skin = m_cloth
	var hips := _bone("hips", self, Vector3(0, 1.0, 0))
	_part(hips, _capsule(0.18, 0.7), Vector3(0, -0.15, 0), m_cloth)
	var spine := _bone("spine", hips, Vector3(0, 0.1, 0))
	_part(spine, _box(Vector3(0.4, 0.5, 0.24)), Vector3(0, 0.28, 0), m_cloth)
	var neck := _bone("neck", spine, Vector3(0, 0.56, 0))
	_part(neck, _sphere(0.15), Vector3(0, 0.15, 0), m_cloth)
	var core := OmniLight3D.new()
	core.light_color = color
	core.light_energy = 1.5
	core.omni_range = 5.0
	core.position = Vector3(0, 0.3, 0)
	spine.add_child(core)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var shoulder := _bone(side + "_shoulder", spine, Vector3(sx * 0.27, 0.5, 0))
		_part(shoulder, _capsule(0.06, 0.32), Vector3(0, -0.15, 0), m_cloth)
		var elbow := _bone(side + "_elbow", shoulder, Vector3(0, -0.3, 0))
		_part(elbow, _capsule(0.05, 0.3), Vector3(0, -0.13, 0), m_cloth)
		_bone(side + "_hand", elbow, Vector3(0, -0.29, 0))
	grip = Node3D.new()
	bones["r_hand"].add_child(grip)


# ---------------------------------------------------------------- glow and flash

## Telegraph glow (0..1) in a color: a swing or spell is coming
func set_glow(amount: float, color: Color) -> void:
	_glow = amount
	_glow_color = color


func flash() -> void:
	_flash = 0.18
	_flinch = 1.0
	if model_body != null:
		model_body.flinch()


func _update_emission(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	var e := _glow_color * (_glow * 1.6)
	if _flash > 0.0:
		e = Color(1, 1, 1) * (_flash / 0.18) * 1.2
	if kind == Kind.SPIRIT:
		e = e + m_cloth.albedo_color * 0.6
	if e.is_equal_approx(_last_emission):
		return
	_last_emission = e
	for m in mats:
		m.emission = e
		m.emission_energy_multiplier = 1.0


# ---------------------------------------------------------------- the animator

func _process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_time += delta
	_flinch = maxf(_flinch - delta * 5.0, 0.0)
	_update_emission(delta)
	# Far away: animate rarely (or not at all)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d2 := cam.global_position.distance_squared_to(global_position)
		if model_body != null:
			model_body.set_far(d2 > LOD_FAR * LOD_FAR)
		if d2 > LOD_FAR * LOD_FAR:
			return
		if d2 > LOD_NEAR * LOD_NEAR:
			_lod_timer -= delta
			if _lod_timer > 0.0:
				return
			delta = 0.25 - _lod_timer
			_lod_timer = 0.25
	var v: Vector3 = enemy.velocity
	_speed = lerpf(_speed, Vector2(v.x, v.z).length(), clampf(delta * 8.0, 0.0, 1.0))
	if not _model_checked and kind == Kind.HUMANOID:
		_try_model()
	if model_body != null:
		model_body.animate(delta, _speed)
		return
	match kind:
		Kind.HUMANOID, Kind.SPIRIT:
			_animate_humanoid(delta)
		Kind.BEAST:
			_animate_beast(delta)
		Kind.CRAWLER:
			_animate_crawler(delta)
	_update_hand_orb()


func _rot(bone_name: String, target: Vector3, rate: float, delta: float) -> void:
	var b: Node3D = bones.get(bone_name)
	if b == null:
		return
	var k := clampf(rate * delta, 0.0, 1.0)
	b.rotation = Vector3(lerp_angle(b.rotation.x, target.x, k), lerp_angle(b.rotation.y, target.y, k), lerp_angle(b.rotation.z, target.z, k))


func _pos(bone_name: String, target: Vector3, rate: float, delta: float) -> void:
	var b: Node3D = bones.get(bone_name)
	if b != null:
		b.position = b.position.lerp(target, clampf(rate * delta, 0.0, 1.0))


func _animate_humanoid(delta: float) -> void:
	var combat: MeleeCombat = enemy.combat
	var moving := clampf(_speed / 1.2, 0.0, 1.0)
	var run := clampf((_speed - 2.0) / 2.5, 0.0, 1.0)
	_phase += delta * (3.0 + _speed * 2.4) * (1.0 if moving > 0.05 else 0.0)
	var s := sin(_phase)
	var rate := 12.0
	var t := {
		"hips": Vector3.ZERO, "spine": Vector3(-0.04 - 0.22 * run, 0, 0), "neck": Vector3.ZERO,
		"l_shoulder": Vector3(-s * (0.45 + 0.35 * run) * moving, 0, -0.08), "r_shoulder": Vector3(s * (0.45 + 0.35 * run) * moving, 0, 0.08),
		"l_elbow": Vector3(0.15 + 0.6 * run, 0, 0), "r_elbow": Vector3(0.15 + 0.6 * run, 0, 0),
		"l_hip": Vector3(s * (0.4 + 0.3 * run) * moving, 0, 0), "r_hip": Vector3(-s * (0.4 + 0.3 * run) * moving, 0, 0),
		"l_knee": Vector3(-maxf(0.0, sin(_phase - 1.3)) * (0.6 + 0.6 * run) * moving, 0, 0),
		"r_knee": Vector3(-maxf(0.0, sin(_phase + PI - 1.3)) * (0.6 + 0.6 * run) * moving, 0, 0),
	}
	var hips_y := 0.95 + absf(cos(_phase)) * 0.04 * moving
	if kind == Kind.SPIRIT:
		hips_y = 1.0 + sin(_time * 2.0) * 0.08
		t["l_hip"] = Vector3.ZERO
		t["r_hip"] = Vector3.ZERO
	else:
		# breathing
		t["spine"].x += sin(_time * 1.6) * 0.015

	var fighting: bool = enemy.state == Enemy.State.CHASE or enemy.state == Enemy.State.ATTACK
	var main: ItemData = enemy.equipment.get_main_hand() if enemy.equipment != null else null
	var two := main != null and main.two_handed
	if fighting and main != null:
		# Guard: weapon up in front
		t["r_shoulder"] = Vector3(0.45 + t["r_shoulder"].x * 0.3, 0.0, 0.12)
		t["r_elbow"] = Vector3(1.15, 0, 0)
		if two:
			t["l_shoulder"] = Vector3(0.55, 0.0, 0.35)
			t["l_elbow"] = Vector3(1.1, 0, 0)

	# The swing, following MeleeCombat's phases
	if combat != null and combat.get_phase() != MeleeCombat.Phase.IDLE:
		rate = 22.0
		_swing_pose(t, combat, two)

	if combat != null and combat.is_blocking():
		rate = 20.0
		t["l_shoulder"] = Vector3(1.25, 0.0, 0.35)
		t["l_elbow"] = Vector3(0.9, 0, 0)
		t["r_shoulder"] = Vector3(0.7, 0.0, 0.1)
		t["r_elbow"] = Vector3(1.0, 0, 0)
		t["spine"].x = 0.05

	if bow_draw > 0.0:
		rate = 18.0
		t["l_shoulder"] = Vector3(1.5, 0.0, 0.2)
		t["l_elbow"] = Vector3(0.05, 0, 0)
		t["r_shoulder"] = Vector3(1.35, 0.0, -0.3)
		t["r_elbow"] = Vector3(0.6 + 1.6 * bow_draw, 0, 0)
		t["spine"] = Vector3(0.0, 0.5, 0)
	if cast_charge > 0.0:
		rate = 18.0
		t["l_shoulder"] = Vector3(1.0 + 0.5 * cast_charge, 0.0, 0.15)
		t["l_elbow"] = Vector3(0.6 - 0.5 * cast_charge, 0, 0)

	if combat != null and combat.is_stunned() and pose != &"paralyzed":
		rate = 14.0
		var wob := sin(_time * 9.0) * 0.1
		t["spine"] = Vector3(0.35, wob, 0)
		t["neck"] = Vector3(0.3, 0, 0)
		t["l_shoulder"] = Vector3(-0.4, 0, -0.9)
		t["r_shoulder"] = Vector3(-0.4, 0, 0.9)
		t["l_elbow"] = Vector3(0.6, 0, 0)
		t["r_elbow"] = Vector3(0.6, 0, 0)

	# Calm poses (only when standing still and not fighting)
	if not fighting and _speed < 0.5:
		hips_y = _calm_pose(t, hips_y)
	if pose == &"paralyzed":
		rate = 30.0

	if _flinch > 0.0:
		t["spine"].x += 0.25 * _flinch
		t["neck"].x += 0.2 * _flinch

	_head_track(t)
	for k in t:
		_rot(k, t[k], rate, delta)
	_pos("hips", Vector3(0, hips_y, 0), 10.0, delta)


func _swing_pose(t: Dictionary, combat: MeleeCombat, two: bool) -> void:
	var phase := combat.get_phase()
	var p := combat.get_phase_progress()
	var kind_now := combat.get_action_kind()
	var heavy := combat.is_heavy_action()
	var w := combat.get_action_weapon()
	var arc := w != null and w.attack_style == ItemData.AttackStyle.ARC
	var dir := combat.get_swing_dir()
	if kind_now == MeleeCombat.Kind.BASH:
		var f := p if phase == MeleeCombat.Phase.WINDUP else (1.0 if phase == MeleeCombat.Phase.ACTIVE else 1.0 - p)
		t["l_shoulder"] = Vector3(0.6 + 0.9 * f, 0, 0.2)
		t["l_elbow"] = Vector3(1.0 - 0.8 * f, 0, 0)
		t["spine"] = Vector3(-0.15 * f, -0.3 * f, 0)
		return
	if kind_now == MeleeCombat.Kind.SLAM:
		arc = false
		heavy = true
	# a: 0 = wound up, 1 = follow-through
	var a := 0.0
	var up := 0.0
	match phase:
		MeleeCombat.Phase.WINDUP:
			up = 1.0 - pow(1.0 - p, 2.0)
		MeleeCombat.Phase.ACTIVE:
			up = 1.0 - p
			a = p
		MeleeCombat.Phase.RECOVERY:
			a = 1.0 - p
	var big := 1.25 if heavy else 1.0
	if arc:
		# Horizontal sweep from the right side across to the left (or back, every other swing)
		var side := 1.0 if dir >= 0.0 else -1.0
		var from := 1.35 * side
		var to := -0.9 * side
		var sweep := lerpf(from, to, a) if phase != MeleeCombat.Phase.WINDUP else lerpf(0.3 * side, from, up)
		t["spine"] = Vector3(-0.1, sweep * 0.45 * big, 0)
		t["r_shoulder"] = Vector3(1.0 + 0.3 * up, 0.0, 0.2 + maxf(sweep, -0.4) * 0.9)
		t["r_elbow"] = Vector3(0.5 + 0.6 * up, 0, 0)
		t["r_shoulder"].y = sweep * 0.3
	else:
		# Overhead chop: arm goes up and back, then comes down in front
		var raise := -2.5 * big
		var down := 0.95
		var x := lerpf(0.4, raise, up) if phase == MeleeCombat.Phase.WINDUP else lerpf(raise, down, a)
		t["r_shoulder"] = Vector3(x, 0.0, 0.15)
		t["r_elbow"] = Vector3(lerpf(0.3, 1.5, up) if phase == MeleeCombat.Phase.WINDUP else lerpf(1.5, 0.2, a), 0, 0)
		t["spine"] = Vector3(lerpf(0.0, 0.2 * big, up) - 0.35 * a * big, 0.15 * up, 0)
	if two:
		t["l_shoulder"] = Vector3(t["r_shoulder"].x, -t["r_shoulder"].y, 0.4)
		t["l_elbow"] = t["r_elbow"]
	if heavy:
		t["l_hip"] = Vector3(0.35 * a, 0, 0)
		t["r_hip"] = Vector3(-0.3 * a, 0, 0)
		t["r_knee"] = Vector3(-0.4 * a, 0, 0)


# People going about their day
func _calm_pose(t: Dictionary, hips_y: float) -> float:
	match pose:
		&"sit":
			t["l_hip"] = Vector3(1.45, 0, -0.05)
			t["r_hip"] = Vector3(1.45, 0, 0.05)
			t["l_knee"] = Vector3(-1.45, 0, 0)
			t["r_knee"] = Vector3(-1.45, 0, 0)
			t["l_shoulder"] = Vector3(0.35, 0, -0.05)
			t["r_shoulder"] = Vector3(0.35 + sin(_time * 0.7 + _gesture_seed) * 0.1, 0, 0.05)
			t["l_elbow"] = Vector3(0.9, 0, 0)
			t["r_elbow"] = Vector3(0.9, 0, 0)
			return 0.5
		&"sleep":
			for k in t:
				t[k] = Vector3.ZERO
			t["neck"] = Vector3(0, 0.4, 0)
			t["l_shoulder"] = Vector3(0, 0, -0.1)
			t["r_shoulder"] = Vector3(0, 0, 0.1)
		&"pray":
			t["l_hip"] = Vector3(0.05, 0, 0)
			t["r_hip"] = Vector3(0.05, 0, 0)
			t["l_knee"] = Vector3(-1.55, 0, 0)
			t["r_knee"] = Vector3(-1.55, 0, 0)
			t["l_shoulder"] = Vector3(0.95, 0, 0.35)
			t["r_shoulder"] = Vector3(0.95, 0, -0.35)
			t["l_elbow"] = Vector3(1.3, 0, 0)
			t["r_elbow"] = Vector3(1.3, 0, 0)
			t["neck"] = Vector3(0.35, 0, 0)
			return 0.52
		&"work":
			var hit := pow(maxf(sin(_time * 4.0 + _gesture_seed), 0.0), 3.0)
			t["spine"] = Vector3(-0.3, 0.1, 0)
			t["r_shoulder"] = Vector3(lerpf(-1.3, 0.75, hit), 0, 0.15)
			t["r_elbow"] = Vector3(lerpf(1.6, 0.6, hit), 0, 0)
			t["l_shoulder"] = Vector3(0.75, 0, 0.25)
			t["l_elbow"] = Vector3(0.9, 0, 0)
		&"chop":
			var c := pow(maxf(sin(_time * 2.6 + _gesture_seed), 0.0), 2.0)
			t["spine"] = Vector3(-0.15 - 0.3 * c, 0, 0)
			t["r_shoulder"] = Vector3(lerpf(-2.6, 0.9, c), 0, 0.2)
			t["l_shoulder"] = Vector3(lerpf(-2.6, 0.9, c), 0, -0.2)
			t["r_elbow"] = Vector3(0.4, 0, 0)
			t["l_elbow"] = Vector3(0.4, 0, 0)
		&"farm":
			var f := sin(_time * 1.8 + _gesture_seed)
			t["spine"] = Vector3(-0.85, f * 0.1, 0)
			t["neck"] = Vector3(-0.3, 0, 0)
			t["l_shoulder"] = Vector3(0.6 + f * 0.25, 0, -0.1)
			t["r_shoulder"] = Vector3(0.6 - f * 0.25, 0, 0.1)
			t["l_hip"] = Vector3(0.25, 0, 0)
			t["r_hip"] = Vector3(0.25, 0, 0)
			t["l_knee"] = Vector3(-0.35, 0, 0)
			t["r_knee"] = Vector3(-0.35, 0, 0)
			return 0.9
		&"sweep":
			var w := sin(_time * 2.2 + _gesture_seed)
			t["spine"] = Vector3(-0.3, w * 0.25, 0)
			t["l_shoulder"] = Vector3(0.7, w * 0.3, 0.2)
			t["r_shoulder"] = Vector3(0.5, w * 0.3, -0.1)
			t["l_elbow"] = Vector3(0.6, 0, 0)
			t["r_elbow"] = Vector3(0.9, 0, 0)
		&"drink":
			var d := smoothstep(0.6, 1.0, sin(_time * 0.6 + _gesture_seed))
			t["r_shoulder"] = Vector3(0.4 + 0.6 * d, 0, 0.2)
			t["r_elbow"] = Vector3(0.6 + 1.7 * d, 0, 0)
			t["neck"] = Vector3(-0.35 * d, 0, 0)
		&"talk":
			_gesture -= get_process_delta_time()
			var g := sin(_time * 1.3 + _gesture_seed)
			t["r_shoulder"] = Vector3(0.35 + maxf(g, 0.0) * 0.5, 0, 0.15)
			t["r_elbow"] = Vector3(0.9 + maxf(g, 0.0) * 0.5, 0, 0)
			t["l_shoulder"] = Vector3(0.2 + maxf(-g, 0.0) * 0.4, 0, -0.15)
			t["l_elbow"] = Vector3(0.7 + maxf(-g, 0.0) * 0.4, 0, 0)
			t["neck"] = Vector3(sin(_time * 2.1) * 0.06, 0, 0)
		&"paralyzed":
			pass
	return hips_y


# Look at the player when they are close and we are not busy
func _head_track(t: Dictionary) -> void:
	if pose == &"sleep" or pose == &"paralyzed":
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player == enemy or not bones.has("neck"):
		return
	var to := player.global_position - global_position
	if to.length() > 5.0 or enemy.state == Enemy.State.ATTACK:
		return
	var local := global_transform.basis.inverse() * to
	var yaw := clampf(atan2(-local.x, -local.z), -1.0, 1.0)
	t["neck"].y = yaw - (t["spine"] as Vector3).y


func _animate_beast(delta: float) -> void:
	var combat: MeleeCombat = enemy.combat
	var moving := clampf(_speed / 1.0, 0.0, 1.0)
	_phase += delta * (4.0 + _speed * 2.6) * (1.0 if moving > 0.05 else 0.0)
	var amp := 0.45 + 0.25 * clampf((_speed - 2.5) / 3.0, 0.0, 1.0)
	var t := {"torso": Vector3.ZERO, "neck": Vector3(0.1, 0, 0), "head": Vector3.ZERO, "jaw": Vector3.ZERO,
		"tail": Vector3(-0.3 + sin(_time * 4.0) * 0.05, sin(_time * 3.0) * 0.25, 0)}
	var offsets := {"fl": 0.0, "br": 0.0, "fr": PI, "bl": PI}
	for k in offsets:
		var ph: float = _phase + offsets[k]
		t[k + "_hip"] = Vector3(sin(ph) * amp * moving, 0, 0)
		t[k + "_knee"] = Vector3(-maxf(0.0, sin(ph - 1.2)) * 0.8 * moving if k.begins_with("f") else maxf(0.0, sin(ph - 1.2)) * 0.8 * moving, 0, 0)
	var y := 0.0
	var rate := 12.0
	if combat != null and combat.get_phase() != MeleeCombat.Phase.IDLE:
		rate = 22.0
		var p := combat.get_phase_progress()
		match combat.get_phase():
			MeleeCombat.Phase.WINDUP:
				t["torso"] = Vector3(0.18 * p, 0, 0)
				t["neck"] = Vector3(-0.35 * p, 0, 0)
				t["jaw"] = Vector3(0.5 * p, 0, 0)
				t["bl_hip"] = Vector3(0.4 * p, 0, 0)
				t["br_hip"] = Vector3(0.4 * p, 0, 0)
				y = -0.08 * p
			MeleeCombat.Phase.ACTIVE:
				t["torso"] = Vector3(-0.2, 0, 0)
				t["neck"] = Vector3(0.45, 0, 0)
				t["jaw"] = Vector3(0.6 * (1.0 - p), 0, 0)
				t["fl_hip"] = Vector3(-0.8, 0, 0)
				t["fr_hip"] = Vector3(-0.8, 0, 0)
				y = 0.08
			MeleeCombat.Phase.RECOVERY:
				t["neck"] = Vector3(0.2 * (1.0 - p), 0, 0)
	elif enemy.state == Enemy.State.ATTACK or enemy.state == Enemy.State.CHASE:
		t["neck"] = Vector3(0.25, 0, 0)  # head low, stalking
		t["tail"] = Vector3(-0.1, sin(_time * 2.0) * 0.1, 0)
	if combat != null and combat.is_stunned():
		t["torso"] = Vector3(0, 0, sin(_time * 10.0) * 0.2)
		t["neck"] = Vector3(-0.4, 0, 0)
	if pose == &"sleep":
		y = -0.35
		for k in offsets:
			t[k + "_hip"] = Vector3(-1.2 if k.begins_with("f") else 1.2, 0, 0)
		t["neck"] = Vector3(0.5, 0, 0)
	if _flinch > 0.0:
		t["torso"].z += 0.2 * _flinch
	if bones.has("wing_l"):
		# Folded at rest, half-open and beating when it fights, spread wide as it strikes
		var fighting: bool = enemy.state == Enemy.State.ATTACK or enemy.state == Enemy.State.CHASE
		var spread := 0.15 if not fighting else 0.55 + sin(_time * 3.0) * 0.35
		if combat != null and combat.get_phase() == MeleeCombat.Phase.ACTIVE:
			spread = 0.9
		t["wing_l"] = Vector3(0, 0.6 * (1.0 - spread), -spread * 0.9)
		t["wing_r"] = Vector3(0, -0.6 * (1.0 - spread), spread * 0.9)
		t["tail_tip"] = Vector3(0, sin(_time * 2.2) * 0.35, 0)
	for k in t:
		_rot(k, t[k], rate, delta)
	var base_h: float = bones["torso"].position.y if not has_meta("torso_h") else float(get_meta("torso_h"))
	if not has_meta("torso_h"):
		set_meta("torso_h", base_h)
	_pos("torso", Vector3(0, base_h + y + absf(cos(_phase)) * 0.03 * moving, 0), 12.0, delta)


func _animate_crawler(delta: float) -> void:
	var moving := clampf(_speed / 1.0, 0.0, 1.0)
	_phase += delta * (6.0 + _speed * 3.0) * (1.0 if moving > 0.05 else 0.0)
	for i in 3:
		for side in ["l", "r"]:
			var k := "%s%d" % [side, i]
			var tri: bool = (i % 2 == 0) == (side == "l")
			var ph := _phase + (0.0 if tri else PI)
			var b: Node3D = bones[k + "_hip"]
			b.rotation.y = sin(ph) * 0.4 * moving
			b.rotation.x = maxf(0.0, cos(ph)) * 0.3 * moving
	var combat: MeleeCombat = enemy.combat
	var snap := 0.0
	if combat != null and combat.get_phase() == MeleeCombat.Phase.WINDUP:
		snap = combat.get_phase_progress()
	elif combat != null and combat.get_phase() == MeleeCombat.Phase.ACTIVE:
		snap = -0.4
	for side in ["l", "r"]:
		var m: Node3D = bones.get("mand_" + side)
		if m != null:
			m.rotation.y = lerp_angle(m.rotation.y, (0.5 * snap) * (1.0 if side == "l" else -1.0), clampf(delta * 20.0, 0.0, 1.0))
	_rot("torso", Vector3(-0.15 * snap, 0, sin(_phase * 0.5) * 0.04 * moving), 14.0, delta)


# A glowing orb in the left hand while a spell charges
func _update_hand_orb() -> void:
	if cast_charge <= 0.0:
		if _hand_orb != null:
			_hand_orb.queue_free()
			_hand_orb = null
		return
	if _hand_orb == null and bones.has("l_hand"):
		_hand_orb = SpellFX.orb(cast_color, 0.09, 3.0)
		bones["l_hand"].add_child(_hand_orb)
		_hand_orb.position = Vector3(0, -0.1, 0)
	if _hand_orb != null:
		_hand_orb.scale = Vector3.ONE * (0.5 + cast_charge)


## Where the torso is (for ragdolls and the camera)
func get_root_bone() -> Node3D:
	return bones.get("hips", bones.get("torso", self))
