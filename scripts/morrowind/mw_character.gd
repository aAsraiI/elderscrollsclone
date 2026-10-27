class_name MwCharacter
extends RefCounted
## Builds a Morrowind person from your own copy of the game: the race's skeleton, its body parts
## (head, hair, skin), clothing and armour on their slots, textures, and the animations from the
## .kf file cut into named clips (Idle, WalkForward, RunForward, WeaponOneHand_Chop, Death1...).
## The result is an ordinary Godot scene (Skeleton3D + meshes + AnimationPlayer) that ModelBody
## plays like any other model. Nothing from Morrowind is stored in the project: MwImport writes
## these into your own models folder.
##
## spec: {"race": "imperial", "female": false, "head": 1, "hair": 1, "wear": ["common_shirt_01", ...]}

## Morrowind units to metres (a person is about 128 units tall)
const SCALE := 1.0 / 70.0
const FPS := 30.0

## Wearable slot -> the skeleton node it hangs from (slot numbers are Morrowind's)
const SLOT_BONES := {0: "Head", 1: "Head", 2: "Neck", 3: "Chest", 4: "Groin", 5: "Groin", 6: "Right Hand",
	7: "Left Hand", 8: "Right Wrist", 9: "Left Wrist", 10: "Shield Bone", 11: "Right Forearm", 12: "Left Forearm",
	13: "Right Upper Arm", 14: "Left Upper Arm", 15: "Right Foot", 16: "Left Foot", 17: "Right Ankle", 18: "Left Ankle",
	19: "Right Knee", 20: "Left Knee", 21: "Right Upper Leg", 22: "Left Upper Leg", 23: "Right Clavicle",
	24: "Left Clavicle", 25: "Weapon Bone", 26: "Tail"}
## Body part kind (MwEsm.Part) -> the slots it fills
const PART_SLOTS := {0: [0], 1: [1], 2: [2], 3: [3], 4: [4], 5: [6, 7], 6: [8, 9], 7: [11, 12], 8: [13, 14],
	9: [15, 16], 10: [17, 18], 11: [19, 20], 12: [21, 22], 13: [23, 24], 14: [26]}
## The clips taken from the .kf (the rest are left out to keep the model small)
const CLIPS := ["Idle", "Idle2", "Idle3", "Idle4", "Idle5", "Idle6", "Idle7", "Idle8", "Idle9", "Idle1h", "Idle2c",
	"Idle2w", "Idlehh", "Idlespell", "Hit1", "Hit2", "Death1", "Death2", "Knockout", "WalkForward", "RunForward",
	"WalkBack", "WeaponOneHand_Chop", "WeaponOneHand_Slash", "WeaponOneHand_Thrust", "WeaponTwoHand_Chop",
	"WeaponTwoHand_Slash", "WeaponTwoWide_Chop", "HandToHand_Chop", "HandToHand_Slash", "Shield_Block",
	"SpellCast_Target", "SpellCast_Self", "BowAndArrow_Shoot", "Idle1s", "Attack1", "Attack2", "Attack3", "Death3"]

var data: MwData
var problems := PackedStringArray()
var _skel: Skeleton3D
var _attach := {}      # bone name -> BoneAttachment3D
var _materials := {}   # texture name -> material
## Clip -> how fast its root moves forward (Morrowind units per second), for WalkForward and RunForward
var speeds := {}
var _clip_name := ""


func _init(p_data: MwData) -> void:
	data = p_data


## The finished person, or null (see `problems`)
func build(spec: Dictionary) -> Node3D:
	var race := String(spec.get("race", "imperial")).to_lower()
	var female := bool(spec.get("female", false))
	var beast: bool = data.esm.races.get(race, {}).get("beast", false)
	var skel_path := "meshes\\base_animkna.nif" if beast else ("meshes\\base_anim_female.nif" if female and data.has("meshes\\base_anim_female.nif") else "meshes\\base_anim.nif")
	var kf_path := "meshes\\xbase_animkna.kf" if beast else ("meshes\\xbase_anim_female.kf" if female and data.has("meshes\\xbase_anim_female.kf") else "meshes\\xbase_anim.kf")
	var skel_nif := data.nif(skel_path)
	if skel_nif == null:
		problems.append("no skeleton " + skel_path)
		return null
	var root := Node3D.new()
	root.name = "MwCharacter"
	# Morrowind is Z-up and faces +Y: turned so it stands up and faces -Z
	root.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	root.scale = Vector3.ONE * SCALE
	var height: float = data.esm.races.get(race, {}).get("female_height" if female else "male_height", 1.0)
	root.scale *= height
	_skel = Skeleton3D.new()
	_skel.name = "Skeleton3D"
	root.add_child(_skel)
	for r in skel_nif.roots:
		_add_bones(skel_nif, r, -1, true)
	_skel.reset_bone_poses()
	# What goes in each slot: the race's own parts, then clothes and armour on top
	var parts := _skin_parts(race, female, int(spec.get("head", 1)), int(spec.get("hair", 1)))
	for id in spec.get("wear", []):
		var w: Dictionary = data.esm.wearables.get(String(id).to_lower(), {})
		if w.is_empty():
			problems.append("no item " + String(id))
			continue
		for s in w["slots"]:
			var part: String = s[2] if female and s[2] != "" else s[1]
			parts[int(s[0])] = part
	for slot in parts:
		var part: String = parts[slot]
		if part == "" or not SLOT_BONES.has(slot):
			continue
		var body: Dictionary = data.esm.bodies.get(part, {})
		if body.is_empty():
			problems.append("no body part " + part)
			continue
		_add_part("meshes\\" + String(body["model"]).to_lower(), SLOT_BONES[slot])
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	_add_clips(player, data.nif(kf_path))
	return root


## Any Morrowind mesh that does not move (furniture, a barrel, a sword, a rock, a tree), at its real
## size, standing up and facing -Z. Light meshes (candles, lanterns, sconces) get a light where
## Morrowind puts theirs. null if it cannot be read.
func build_static(path: String) -> Node3D:
	var nif := data.nif(path)
	if nif == null:
		problems.append("could not read " + path)
		return null
	var root := Node3D.new()
	root.name = "MwStatic"
	root.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	root.scale = Vector3.ONE * SCALE
	var shapes: Array = []
	for r in nif.roots:
		_collect_shapes(nif, r, Transform3D.IDENTITY, [], shapes)
	for s in shapes:
		var shape: Dictionary = nif.records[s[0]]
		var mesh := _mesh(nif, shape, s[2], false)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(shape["name"]).validate_node_name()
		mi.mesh = mesh
		mi.transform = s[1]
		root.add_child(mi)
	if root.get_child_count() == 0:
		root.free()
		problems.append("nothing to draw in " + path)
		return null
	# Flames and embers (Morrowind draws them as particles): a small glow where they come from
	for flame_at in _find_particles(nif):
		var flame := MeshInstance3D.new()
		flame.name = "Flame"
		var q := QuadMesh.new()
		q.size = Vector2(4.0, 6.0)
		flame.mesh = q
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.billboard_keep_scale = true  # or it would ignore the model's size and be metres across
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.albedo_color = Color(1.0, 0.62, 0.25, 0.9)
		fm.albedo_texture = _flame_texture()
		flame.material_override = fm
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.transform = Transform3D(Basis.IDENTITY, flame_at.origin + Vector3(0, 0, 2.0))
		root.add_child(flame)
	for light_at in _find_nodes(nif, "AttachLight"):
		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = Color(1.0, 0.72, 0.42)
		light.light_energy = 1.1
		light.omni_range = 4.5 / SCALE
		light.shadow_enabled = false
		light.transform = light_at
		root.add_child(light)
	return root


# Where the particle emitters are, within the file
func _find_particles(nif: MwNif) -> Array:
	var out: Array = []
	var walk := func(walk_fn: Callable, idx: int, xf: Transform3D) -> void:
		if idx < 0 or idx >= nif.records.size():
			return
		var r: Dictionary = nif.records[idx]
		if r.get("particles", false):
			out.append(xf * _xf(r))
			return
		if not r.has("children") or int(r.get("flags", 0)) & 1:
			return
		var here := xf * _xf(r)
		for c in r["children"]:
			walk_fn.call(walk_fn, c, here)
	for r in nif.roots:
		walk.call(walk, r, Transform3D.IDENTITY)
	return out


static var _flame_tex: Texture2D


# A soft round glow, bright in the middle
static func _flame_texture() -> Texture2D:
	if _flame_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.6)
		t.fill_to = Vector2(0.5, 0.05)
		t.width = 32
		t.height = 32
		_flame_tex = t
	return _flame_tex


# Where nodes with this name are, within the file
func _find_nodes(nif: MwNif, wanted: String) -> Array:
	var out: Array = []
	var walk := func(walk_fn: Callable, idx: int, xf: Transform3D) -> void:
		if idx < 0 or idx >= nif.records.size():
			return
		var r: Dictionary = nif.records[idx]
		if not r.has("children"):
			return
		var here := xf * _xf(r)
		if String(r["name"]) == wanted:
			out.append(here)
		for c in r["children"]:
			walk_fn.call(walk_fn, c, here)
	for r in nif.roots:
		walk.call(walk, r, Transform3D.IDENTITY)
	return out


## A Morrowind creature (rat, guar, kwama, atronach...): its own skeleton and skin from the .nif,
## its animations from the matching x<name>.kf, cut into clips like a person's.
func build_creature(path: String, kf_path: String) -> Node3D:
	var nif := data.nif(path)
	if nif == null:
		problems.append("could not read " + path)
		return null
	var root := Node3D.new()
	root.name = "MwCreature"
	root.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	root.scale = Vector3.ONE * SCALE
	_skel = Skeleton3D.new()
	_skel.name = "Skeleton3D"
	root.add_child(_skel)
	for r in nif.roots:
		_add_bones(nif, r, -1, true)
	_skel.reset_bone_poses()
	# Shapes: skinned ones bind to the bones by name, the rest hang from the node they sit under
	for r in nif.roots:
		_creature_shapes(nif, r, "", Transform3D.IDENTITY, [])
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	_add_clips(player, data.nif(kf_path) if kf_path != "" else null)
	# Two-legged creatures on Morrowind's own skeleton (skeletons, draugr, goblins) share the people's
	# animations for whatever their own file leaves out
	if _skel.find_bone("Bip01 Spine1") >= 0 and _skel.find_bone("Bip01 L Thigh") >= 0:
		_add_clips(player, data.nif("meshes/xbase_anim.kf"))
	if _skel.get_child_count() == 0:
		root.free()
		problems.append("nothing to draw in " + path)
		return null
	return root


func _creature_shapes(nif: MwNif, idx: int, bone: String, xf: Transform3D, props: Array) -> void:
	if idx < 0 or idx >= nif.records.size():
		return
	var r: Dictionary = nif.records[idx]
	if r["type"] == "RootCollisionNode" or not r.has("flags") or int(r["flags"]) & 1:
		return
	var my_props: Array = props + Array(r.get("properties", []))
	if r["type"] == "NiTriShape":
		if int(r["skin"]) >= 0:
			_add_skinned(nif, r, my_props)
		elif bone != "":
			_add_rigid(nif, r, xf * _xf(r), my_props, bone, false)
		return
	if not r.has("children"):
		return
	# A node that is a bone starts a new local space
	var name := String(r["name"])
	var next_bone := bone
	var next_xf := xf * _xf(r)
	if _skel.find_bone(name) >= 0:
		next_bone = name
		next_xf = Transform3D.IDENTITY
	for c in r["children"]:
		_creature_shapes(nif, c, next_bone, next_xf, my_props)


# ---------------------------------------------------------------- skeleton

func _add_bones(nif: MwNif, idx: int, parent: int, is_root: bool) -> void:
	if idx < 0 or idx >= nif.records.size():
		return
	var r: Dictionary = nif.records[idx]
	if not r.has("children"):
		return
	var name := String(r["name"])
	if name == "Bounding Box" or r["type"] == "RootCollisionNode":
		return
	var me := parent
	if not is_root and _skel.find_bone(name) < 0:
		me = _skel.get_bone_count()
		_skel.add_bone(name)
		if parent >= 0:
			_skel.set_bone_parent(me, parent)
		_skel.set_bone_rest(me, _xf(r))
	for c in r["children"]:
		_add_bones(nif, c, me, false)


static func _xf(r: Dictionary) -> Transform3D:
	return Transform3D((r["basis"] as Basis).scaled(Vector3.ONE * float(r["scale"])), r["origin"])


# ---------------------------------------------------------------- parts

func _skin_parts(race: String, female: bool, head: int, hair: int) -> Dictionary:
	var out := {}
	var heads := []
	var hairs := []
	# Male parts first, so a female body falls back to them for any part it lacks
	for want_female in ([false, true] if female else [false]):
		for id in data.esm.bodies:
			var b: Dictionary = data.esm.bodies[id]
			if b["race"] != race or b["kind"] != 0 or b["female"] != want_female or String(id).ends_with(".1st"):
				continue
			match int(b["part"]):
				MwEsm.Part.HEAD:
					if b["female"] == female:
						heads.append(id)
				MwEsm.Part.HAIR:
					if b["female"] == female:
						hairs.append(id)
				_:
					for slot in PART_SLOTS.get(int(b["part"]), []):
						out[slot] = id
	heads.sort()
	hairs.sort()
	if not heads.is_empty():
		out[0] = heads[clampi(head - 1, 0, heads.size() - 1)]
	if not hairs.is_empty():
		out[1] = hairs[clampi(hair - 1, 0, hairs.size() - 1)]
	return out


func _add_part(path: String, bone: String) -> void:
	var nif := data.nif(path)
	if nif == null:
		problems.append("could not read " + path)
		return
	var shapes: Array = []  # [record index, transform within the part]
	for r in nif.roots:
		_collect_shapes(nif, r, Transform3D.IDENTITY, [], shapes)
	# One file can hold several slots ("Tri Chest", "Tri Left Hand 0"...): keep this slot's
	var want := "tri " + bone.to_lower()
	var mine := shapes.filter(func(s): return String(nif.records[s[0]]["name"]).to_lower().begins_with(want))
	if mine.is_empty():
		var sided := shapes.any(func(s):
			var n := String(nif.records[s[0]]["name"]).to_lower()
			return n.begins_with("tri left") or n.begins_with("tri right"))
		if sided:
			return
		mine = shapes
	var left := bone.begins_with("Left")
	for s in mine:
		var r: Dictionary = nif.records[s[0]]
		if int(r["skin"]) >= 0:
			_add_skinned(nif, r, s[2])
		else:
			_add_rigid(nif, r, s[1], s[2], bone, left)


func _collect_shapes(nif: MwNif, idx: int, parent_xf: Transform3D, props: Array, out: Array) -> void:
	if idx < 0 or idx >= nif.records.size():
		return
	var r: Dictionary = nif.records[idx]
	if r["type"] == "RootCollisionNode" or not r.has("flags") or int(r["flags"]) & 1:
		return
	var xf := parent_xf * _xf(r)
	var my_props: Array = props + Array(r.get("properties", []))
	if r["type"] == "NiTriShape":
		out.append([idx, xf, my_props])
	for c in r.get("children", []):
		_collect_shapes(nif, c, xf, my_props, out)


func _mesh(nif: MwNif, shape: Dictionary, props: Array, flip: bool, skin_bones: Array = []) -> ArrayMesh:
	var d: Dictionary = nif.records[shape["data"]]
	var verts: PackedVector3Array = d["vertices"]
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not (d["normals"] as PackedVector3Array).is_empty():
		arrays[Mesh.ARRAY_NORMAL] = d["normals"]
	if not (d["uvs"] as Array).is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = d["uvs"][0]
	var tris: PackedInt32Array = (d["triangles"] as PackedInt32Array).duplicate()
	# Godot draws clockwise triangles as the front; Morrowind's are the other way round
	if not flip:
		for i in range(0, tris.size(), 3):
			var t := tris[i + 1]
			tris[i + 1] = tris[i + 2]
			tris[i + 2] = t
	arrays[Mesh.ARRAY_INDEX] = tris
	if not skin_bones.is_empty():
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(verts.size() * 4)
		weights.resize(verts.size() * 4)
		var used := PackedInt32Array()
		used.resize(verts.size())
		for bi in skin_bones.size():
			var b: Dictionary = skin_bones[bi]
			var idx: PackedInt32Array = b["vertices"]
			var w: PackedFloat32Array = b["weights"]
			for k in idx.size():
				var v := idx[k]
				if v >= verts.size():
					continue
				var slot := used[v]
				if slot < 4:
					bones[v * 4 + slot] = bi
					weights[v * 4 + slot] = w[k]
					used[v] = slot + 1
				else:
					# Keep the four strongest
					var weakest := 0
					for j in 4:
						if weights[v * 4 + j] < weights[v * 4 + weakest]:
							weakest = j
					if w[k] > weights[v * 4 + weakest]:
						bones[v * 4 + weakest] = bi
						weights[v * 4 + weakest] = w[k]
		for v in verts.size():
			var total := 0.0
			for j in 4:
				total += weights[v * 4 + j]
			if total > 0.0:
				for j in 4:
					weights[v * 4 + j] /= total
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material(nif, props))
	return mesh


func _material(nif: MwNif, props: Array) -> Material:
	var tex_name := ""
	var alpha_flags := 0
	var alpha_ref := 128
	var diffuse := Color.WHITE
	for p in props:
		if p < 0 or p >= nif.records.size():
			continue
		var r: Dictionary = nif.records[p]
		match r["type"]:
			"NiTexturingProperty":
				var tex: Array = r["textures"]
				if not tex.is_empty() and (tex[0] as Dictionary).has("source"):
					var src: Dictionary = nif.records[tex[0]["source"]]
					tex_name = String(src.get("file", ""))
			"NiAlphaProperty":
				alpha_flags = int(r["flags"])
				alpha_ref = int(r["threshold"])
			"NiMaterialProperty":
				var c: Vector3 = r["diffuse"]
				diffuse = Color(c.x, c.y, c.z, float(r["alpha"]))
	var key := "%s|%d|%s" % [tex_name, alpha_flags, diffuse.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	if tex_name != "":
		m.albedo_texture = data.texture(tex_name)
		if m.albedo_texture == null:
			problems.append("no texture " + tex_name)
	if diffuse.a < 0.99:
		m.albedo_color = Color(1, 1, 1, diffuse.a)
	if alpha_flags & 0x200:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = alpha_ref / 255.0
	elif alpha_flags & 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[key] = m
	return m


func _add_skinned(nif: MwNif, shape: Dictionary, props: Array) -> void:
	var inst: Dictionary = nif.records[shape["skin"]]
	var sd: Dictionary = nif.records[inst["data"]]
	var skin := Skin.new()
	var bones: Array = sd["bones"]
	var refs: PackedInt32Array = inst["bones"]
	for i in refs.size():
		var bone_name := String(nif.records[refs[i]]["name"])
		if _skel.find_bone(bone_name) < 0:
			problems.append("bone %s missing for %s" % [bone_name, shape["name"]])
			return
		var b: Dictionary = bones[i]
		skin.add_named_bind(bone_name, Transform3D((b["basis"] as Basis).scaled(Vector3.ONE * float(b["scale"])), b["origin"]))
	var mesh := _mesh(nif, shape, props, false, bones)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = String(shape["name"]).validate_node_name()
	mi.mesh = mesh
	mi.skin = skin
	_skel.add_child(mi)
	mi.skeleton = NodePath("..")


func _add_rigid(nif: MwNif, shape: Dictionary, xf: Transform3D, props: Array, bone: String, left: bool) -> void:
	if _skel.find_bone(bone) < 0:
		problems.append("no bone " + bone)
		return
	var mesh := _mesh(nif, shape, props, left)
	if mesh == null:
		return
	if not _attach.has(bone):
		var att := BoneAttachment3D.new()
		att.name = bone.validate_node_name()
		att.bone_name = bone
		_skel.add_child(att)
		_attach[bone] = att
	var holder := Node3D.new()
	holder.name = "Part"
	if left:
		# Left side parts are the right side's mirrored (as Morrowind does)
		holder.scale = Vector3(-1, 1, 1)
	(_attach[bone] as Node3D).add_child(holder)
	var mi := MeshInstance3D.new()
	mi.name = String(shape["name"]).validate_node_name()
	mi.mesh = mesh
	mi.transform = xf
	holder.add_child(mi)


# ---------------------------------------------------------------- animation

func _add_clips(player: AnimationPlayer, kf: MwNif) -> void:
	if kf == null or kf.roots.is_empty():
		problems.append("no animation file")
		return
	var helper: Dictionary = kf.records[kf.roots[0]]
	# Text keys and bone names hang off the helper in a chain; controllers in another
	var keys: Array = []
	var bone_names: Array = []
	var e := int(helper.get("extra", -1))
	while e >= 0:
		var r: Dictionary = kf.records[e]
		if r["type"] == "NiTextKeyExtraData":
			keys = r["keys"]
		elif r["type"] == "NiStringExtraData":
			bone_names.append(String(r["text"]))
		e = int(r.get("next", -1))
	var tracks: Array = []  # [bone, NiKeyframeData]
	var c := int(helper.get("controller", -1))
	var i := 0
	while c >= 0:
		var r: Dictionary = kf.records[c]
		if i < bone_names.size() and int(r.get("data", -1)) >= 0:
			tracks.append([bone_names[i], kf.records[r["data"]]])
		i += 1
		c = int(r.get("next", -1))
	var lib: AnimationLibrary = player.get_animation_library("") if player.has_animation_library("") else AnimationLibrary.new()
	# Names as Morrowind spells them, whatever the capitals ("Walkforward", "KnockOut")
	var ranges := {}
	var found := clip_ranges(keys)
	for k in found:
		ranges[String(k).to_lower()] = found[k]
	for clip in CLIPS:
		var r = ranges.get(String(clip).to_lower())
		if r != null and not lib.has_animation(clip):
			_clip_name = clip
			lib.add_animation(clip, _clip(tracks, r[0], r[1]))
	if not player.has_animation_library(""):
		player.add_animation_library("", lib)


## Clip name -> [start, stop] from Morrowind's text keys ("Idle: Start", "WeaponOneHand: Chop Start"...)
static func clip_ranges(keys: Array) -> Dictionary:
	var out := {}
	var open := {}
	for k in keys:
		var t := float(k[0])
		for line in String(k[1]).split("\n"):
			line = line.strip_edges()
			var colon := line.find(":")
			if colon < 0:
				continue
			var group := line.substr(0, colon).strip_edges()
			var ev := line.substr(colon + 1).strip_edges().to_lower()
			if ev == "start":
				open[group] = t
			elif ev == "stop" and open.has(group):
				out[group] = [open[group], t]
				open.erase(group)
			elif ev.ends_with(" start"):
				var what := ev.trim_suffix(" start")
				if not what.contains(" ") and what != "loop":
					open[group + "_" + what.capitalize()] = t
			elif ev.ends_with(" stop"):
				var what := ev.get_slice(" ", 0)
				var name := group + "_" + what.capitalize()
				if open.has(name):
					out[name] = [open[name], t]
					open.erase(name)
	return out


func _clip(tracks: Array, t0: float, t1: float) -> Animation:
	var anim := Animation.new()
	anim.length = maxf(t1 - t0, 1.0 / FPS)
	for tr in tracks:
		var bone: String = tr[0]
		if _skel.find_bone(bone) < 0:
			continue
		var d: Dictionary = tr[1]
		var path := NodePath("Skeleton3D:" + bone)
		var rot: Array = d.get("rotations", [])
		if not rot.is_empty():
			var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(ti, path)
			for t in _times(rot, t0, t1):
				anim.rotation_track_insert_key(ti, t - t0, _sample_rot(rot, t))
		var pos: Array = d.get("translations", [])
		if not pos.is_empty():
			var ti := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(ti, path)
			var start: Vector3 = _sample(pos, t0)
			if bone == "Bip01":
				var travel: Vector3 = _sample(pos, t1) - start
				speeds[_clip_name] = Vector2(travel.x, travel.y).length() / maxf(t1 - t0, 0.001)
			for t in _times(pos, t0, t1):
				var p: Vector3 = _sample(pos, t)
				if bone == "Bip01":
					# The walk and run clips move the whole body forward: keep it in place
					p = Vector3(start.x, start.y, p.z)
				anim.position_track_insert_key(ti, t - t0, p)
		var sc: Array = d.get("scales", [])
		if not sc.is_empty():
			var ti := anim.add_track(Animation.TYPE_SCALE_3D)
			anim.track_set_path(ti, path)
			for t in _times(sc, t0, t1):
				anim.scale_track_insert_key(ti, t - t0, Vector3.ONE * float(_sample(sc, t)))
	return anim


# The key times inside [t0, t1], plus both ends
static func _times(keys: Array, t0: float, t1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([t0])
	for k in keys:
		var t := float(k[0])
		if t > t0 + 0.0001 and t < t1 - 0.0001:
			out.append(t)
	out.append(t1)
	return out


static func _bracket(keys: Array, t: float) -> int:
	var lo := 0
	var hi := keys.size() - 1
	if t <= float(keys[0][0]):
		return -1
	if t >= float(keys[hi][0]):
		return hi
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(keys[mid][0]) <= t:
			lo = mid
		else:
			hi = mid
	return lo


static func _sample(keys: Array, t: float) -> Variant:
	var i := _bracket(keys, t)
	if i < 0:
		return keys[0][1]
	if i >= keys.size() - 1:
		return keys[-1][1]
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var f := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.00001)
	return lerp(a[1], b[1], f)


static func _sample_rot(keys: Array, t: float) -> Quaternion:
	var i := _bracket(keys, t)
	if i < 0:
		return (keys[0][1] as Quaternion).normalized()
	if i >= keys.size() - 1:
		return (keys[-1][1] as Quaternion).normalized()
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var f := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.00001)
	return (a[1] as Quaternion).normalized().slerp((b[1] as Quaternion).normalized(), f)
