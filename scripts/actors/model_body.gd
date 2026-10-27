class_name ModelBody
extends Node3D
## A real, animated model standing in for a CreatureBody's boxes (see ModelLibrary). The box
## skeleton stays underneath, hidden, so everything that asks the body where its hand or head is
## still gets an answer; the model plays its own clips, picked each frame from the same things the
## box animator reads: speed, the MeleeCombat phase, blocking, a drawn bow, a spell charging, a
## stagger, and the calm poses townsfolk use (sit, sleep, pray, work, chop, farm, talk, drink).
## Weapons and shields hang from the model's hand bones. On death the model plays its death clip
## and lies as one piece (Ragdoll._build_model_corpse), still searchable and draggable.
##
## Clips are found by name, so any model works: each role below lists names to look for (exact
## name after the last "|" first, then any name containing it). A models.json entry can name its
## own clips with "clips": {"walk": "MyWalk"}.

const ROLE_CLIPS := {
	"idle": ["Idle", "Idle_A", "Unarmed_Idle", "Standing", "ZombieIdle", "Flying", "Slime_Idle"],
	"idle_combat": ["Idle_Combat", "Idle_swordRight", "Idle1h", "Idle"],
	"idle_combat_2h": ["2H_Melee_Idle", "Idle2c", "Idle_Combat", "Idle"],
	"walk": ["Walking_A", "Walking_D_Skeletons", "Walk", "Walking", "ZombieWalk", "WalkSlow", "Flying"],
	"run": ["Running_A", "Run", "Running", "ZombieRun", "Skeleton_Running", "Walk", "Flying"],
	"attack": ["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Chop", "SwordSlash", "Run_swordAttack", "Attack", "ZombieBite", "Bite", "Punch"],
	"attack_alt": ["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Stab", "Attack2", "Attack"],
	"attack2h": ["2H_Melee_Attack_Slice", "2H_Melee_Attack_Chop", "Attack2", "SwordSlash", "Attack"],
	"attack_unarmed": ["Unarmed_Melee_Attack_Punch_A", "Punch", "Attack", "ZombieBite"],
	"bash": ["Block_Attack", "Unarmed_Melee_Attack_Kick", "Attack"],
	"block": ["Blocking", "Block"],
	"hit": ["Hit_A", "Hit", "Hit_B"],
	"death": ["Death_A", "Death", "Death_B", "Death_C_Skeletons"],
	"cast": ["Spellcasting", "Spellcast_Long", "Spellcast_Raise"],
	"aim": ["2H_Ranged_Aiming", "1H_Ranged_Aiming"],
	"sit": ["Sit_Chair_Idle", "Sitting", "Sit_Floor_Idle"],
	"kneel": ["Sit_Floor_Idle", "Sitting", "Sit_Chair_Idle"],
	"lie": ["Lie_Idle", "Lie_Pose", "Death_A_Pose"],
	"work": ["Interact", "Use_Item", "PickUp"],
	"chop": ["1H_Melee_Attack_Chop", "2H_Melee_Attack_Chop", "Punch"],
	"talk": ["Idle_B", "Taunt", "Clapping", "Idle"],
	"drink": ["Use_Item", "Idle"],
	"stun": ["Hit_B", "Hit_A", "Hit"],
}
## Roles that play once (the rest loop)
const ONCE := ["attack", "attack_alt", "attack2h", "attack_unarmed", "bash", "hit", "death"]

var body: CreatureBody
var model: Node3D
var player: AnimationPlayer
var entry: Dictionary
var clips := {}                 # role -> animation name ("" = none)
var _role := ""
var _attack_role := ""
var _last_phase := 0
var _hit_time := 0.0
var _dead := false
var _walk_speed := 1.5          # m/s the walk clip is made for (for its playback speed)
var _run_speed := 4.0


## Puts the model `key` on `body`, fitted to the space its boxes take up. null if it can't load.
static func attach(p_body: CreatureBody, key: String) -> ModelBody:
	var e := ModelLibrary.entry(key)
	if e.is_empty():
		return null
	# The space the boxes take up, before they are hidden
	var old := ModelLibrary.bounds(p_body)
	if old.size.y < 0.05:
		old = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
	var holder := ModelLibrary.instance(key)
	if holder == null:
		return null
	var mb := ModelBody.new()
	mb.name = "ModelBody"
	mb.body = p_body
	mb.entry = e
	mb.model = holder
	mb.set_meta("model_key", key)
	# Things the model holds that the game gives it itself (built-in weapons, shields, mugs)
	var hide: Array = e.get("hide", [])
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		for h in hide:
			if String(mi.name).to_lower().contains(String(h).to_lower()):
				mi.visible = false
				break
	for gi in holder.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = CreatureBody.DRAW_DISTANCE
	mb.add_child(holder)
	p_body.add_child(mb)
	mb._fit(old)
	var players := holder.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		mb.player = players[0]
		mb.player.playback_default_blend_time = 0.15
		mb._find_clips()
	mb._hide_boxes()
	mb._hang_hands()
	mb._play("idle")
	mb._fit_hitbox()
	return mb


# The owner's standing capsule takes the model's size: upright for people, lying along the body
# for long four-legged things. Its eye point (Head) moves to the model's head height.
func _fit_hitbox() -> void:
	var owner_body := body.enemy as Enemy
	if owner_body == null:
		return
	var box := ModelLibrary.relative_transform(owner_body, self) * ModelLibrary.bounds(self)
	if box.size.y < 0.05:
		return
	for c in owner_body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is CapsuleShape3D):
			continue
		var cap := cs.shape as CapsuleShape3D
		var long := maxf(box.size.x, box.size.z)
		if long > box.size.y * 1.3:
			cap.radius = clampf(minf(box.size.y, minf(box.size.x, box.size.z)) * 0.5, 0.15, 1.2)
			cap.height = maxf(minf(long, 2.4 * owner_body.body_scale), cap.radius * 2.0 + 0.01)
			cs.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			cs.position = Vector3(0.0, maxf(cap.radius, box.get_center().y), box.get_center().z)
		else:
			cap.radius = clampf(minf(box.size.x, box.size.z) * 0.45, 0.3, 1.2)  # arms at the sides count too
			cap.height = maxf(box.size.y, cap.radius * 2.0 + 0.01)
			cs.rotation = Vector3.ZERO
			cs.position = Vector3(0.0, box.position.y + cap.height * 0.5, 0.0)
		break
	if owner_body.head != null:
		owner_body.head.position.y = box.position.y + box.size.y * 0.85


func _fit(old: AABB) -> void:
	var box := ModelLibrary.bounds(model)
	if box.size.y < 0.0001:
		return
	var mode := String(entry.get("fit", "height"))
	var s := 1.0
	match mode:
		"long":
			s = maxf(old.size.x, old.size.z) / maxf(maxf(box.size.x, box.size.z), 0.0001)
		"real", "creature":
			s = 1.0  # already in metres (Morrowind's own size); the body's own scale still applies
		_:
			s = old.size.y / box.size.y
	s *= float(entry.get("scale", 1.0))
	model.scale = Vector3.ONE * s
	box = ModelLibrary.bounds(self)
	model.position += Vector3(old.get_center().x - box.get_center().x, old.position.y - box.position.y, old.get_center().z - box.get_center().z)
	if entry.has("lift"):
		model.position.y += float(entry["lift"]) * s


func _find_clips() -> void:
	var names := player.get_animation_list()
	var own: Dictionary = entry.get("clips", {})
	for role in ROLE_CLIPS:
		var found := ""
		var wanted: Array = [own[role]] if own.has(role) else ROLE_CLIPS[role]
		for want in wanted:
			found = _match(names, String(want))
			if found != "":
				break
		clips[role] = found
		if found != "":
			var anim := player.get_animation(found)
			if anim != null:
				anim.loop_mode = Animation.LOOP_NONE if role in ONCE else Animation.LOOP_LINEAR
	var walk_speed = entry.get("walk_speed", null)
	if walk_speed != null:
		_walk_speed = float(walk_speed)
	var run_speed = entry.get("run_speed", null)
	if run_speed != null:
		_run_speed = float(run_speed)


static func _match(names: PackedStringArray, want: String) -> String:
	var w := want.to_lower()
	# The exact name first ("Idle" must not find "2H_Melee_Idle"), then the same with a rig or
	# character prefix ("HumanArmature|Man_Walk"), then any name holding it
	for n in names:
		var short := String(n).get_slice("|", String(n).get_slice_count("|") - 1).to_lower()
		if short == w:
			return n
	for n in names:
		var short := String(n).get_slice("|", String(n).get_slice_count("|") - 1).to_lower()
		if short.trim_prefix("man_").trim_prefix("female_") == w or short.ends_with("_" + w):
			return n
	for n in names:
		if String(n).to_lower().contains(w):
			return n
	return ""


# The box parts stay (the ragdoll and hand positions use their bones) but are not drawn
func _hide_boxes() -> void:
	for c in body.get_children():
		if c != self and c is Node3D:
			(c as Node3D).visible = false


# The grip nodes move onto the model's hands, so weapons and shields follow its animation
func _hang_hands() -> void:
	var skel := _skeleton()
	if skel == null:
		return
	var hands: Dictionary = entry.get("hands", {})
	var auto := String(entry.get("grip", "")) == "auto" or String(entry.get("source", "")) == "morrowind"
	if String(entry.get("source", "")) == "morrowind":
		hands = {"r": "Bip01 R Hand", "l": "Bip01 L Hand"}  # imports from before 1.15.4 named the weapon bones
	for side in ["r", "l"]:
		var bone_name := String(hands.get(side, ""))
		# Morrowind's rigs carry shields on their own forearm bone, which its shields are made for
		var on_shield_bone: bool = side == "l" and skel.find_bone("Shield Bone") >= 0 and body.off_grip != null and _holds_shield()
		if on_shield_bone:
			bone_name = "Shield Bone"
		var bone := skel.find_bone(bone_name) if bone_name != "" else -1
		if bone < 0:
			continue
		var att := BoneAttachment3D.new()
		att.name = "Hand_" + side
		att.bone_name = bone_name
		skel.add_child(att)
		var holder := Node3D.new()
		holder.name = "Holder"
		# Undo every scale between the body and the skeleton, so weapons keep their real size
		var skel_scale := ModelLibrary.relative_transform(self, skel).basis.get_scale()
		var unscale := Basis.from_scale(Vector3.ONE / skel_scale.max(Vector3.ONE * 0.00001))
		var fitted = _auto_grip(skel, bone, side) if auto and not on_shield_bone else null
		if on_shield_bone:
			# Morrowind's shield as made for this bone faces forward; a quarter turn about the forearm faces it
			# out from the arm, the bowl round the arm (CreatureBody hangs the raw model)
			fitted = Transform3D(Basis(_forearm_axis(skel, bone), SHIELD_TURN), Vector3.ZERO)
		if fitted != null:
			holder.transform = Transform3D((fitted as Transform3D).basis.orthonormalized() * unscale, (fitted as Transform3D).origin)
		else:
			var rot: Array = entry.get("grip_rot_" + side, [0, 0, 0])
			holder.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2]))) * unscale, Vector3.ZERO)
		att.add_child(holder)
		var g: Node3D = body.grip if side == "r" else body.off_grip
		if g != null:
			g.get_parent().remove_child(g)
			holder.add_child(g)
			g.position = Vector3.ZERO
			g.rotation = Vector3.ZERO
			g.visible = true
		if on_shield_bone:
			_seat_shield.call_deferred(holder, skel, bone, 8)


## A grip worked out from the hand's own bones, for models with finger and thumb bones ("grip":
## "auto"): it sits in the palm, between the wrist and the knuckles; a weapon's handle runs across
## the fist with the blade out of the index-finger side (the grip's -Z) and its edge along the knuckles (X);
## a shield lies flat on the back of the left hand. In the hand bone's own space; null without fingers.
func _auto_grip(skel: Skeleton3D, hand: int, side: String) -> Variant:
	var finger := _find_below(skel, hand, ["finger1", "middlehand", "finger2", "fingers", "index", "middle"])
	var thumb := _find_below(skel, hand, ["thumb", "finger0"])
	if thumb < 0 and skel.get_bone_parent(hand) >= 0:
		thumb = _find_below(skel, skel.get_bone_parent(hand), ["thumb"])  # some rigs hang it off the forearm
	if finger < 0 or thumb < 0:
		return null
	var hand_rest := skel.get_bone_global_rest(hand)
	var h := hand_rest.origin
	var f := skel.get_bone_global_rest(finger).origin
	var fwd := (f - h).normalized()
	# Across the fist: from the outer fingers to the index finger when the hand has both (a thumb
	# can sit under the palm, as Morrowind's do), else toward the thumb
	var across := skel.get_bone_global_rest(thumb).origin - h
	var outer := _find_below(skel, hand, ["finger2", "finger3", "ring", "pinky"])
	if outer >= 0 and outer != finger:
		across = f - skel.get_bone_global_rest(outer).origin
	across = (across - fwd * across.dot(fwd)).normalized()
	if fwd.length() < 0.5 or across.length() < 0.5:
		return null
	var x := fwd
	# Right: the blade comes out of the thumb side. Left: the shield faces out from the back of the hand.
	var z := -across if side == "r" else across.cross(fwd).normalized()
	var y := z.cross(x).normalized()
	return hand_rest.affine_inverse() * Transform3D(Basis(x, y, z), h + (f - h) * 0.55)


# The first bone under `from` (breadth first) whose name holds one of `names`, tried in order
static func _find_below(skel: Skeleton3D, from: int, names: Array) -> int:
	var order: Array[int] = []
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var b: int = queue.pop_front()
		if b != from:
			order.append(b)
		queue.append_array(Array(skel.get_bone_children(b)))
	for n in names:
		for b in order:
			if skel.get_bone_name(b).to_lower().contains(String(n)):
				return b
	return -1


func _skeleton() -> Skeleton3D:
	var list := model.find_children("*", "Skeleton3D", true, false)
	return list[0] as Skeleton3D if not list.is_empty() else null


## Where a left-hand weapon goes (null = the model has no left hand)
func left_holder() -> Node3D:
	var n := model.find_child("Hand_l", true, false)
	return n.get_child(0) as Node3D if n != null else null


func _play(role: String, speed: float = 1.0) -> void:
	if player == null:
		return
	var clip: String = clips.get(role, "")
	if clip == "":
		clip = clips.get("idle", "")
		if clip == "":
			return
	player.speed_scale = speed
	if role == _role and player.current_animation == clip and player.is_playing():
		return
	_role = role
	player.play(clip)


func _replay(role: String, speed: float) -> void:
	_role = ""
	if player != null:
		player.stop(true)
	_play(role, speed)


## Far away the animation stops (a statue in the fog), as the box bodies did
func set_far(far: bool) -> void:
	if player != null and not _dead:
		player.active = not far


func flinch() -> void:
	_hit_time = 0.3


## Called by CreatureBody every frame it animates
func animate(delta: float, speed: float) -> void:
	if _dead or player == null:
		return
	_hit_time = maxf(_hit_time - delta, 0.0)
	var e = body.enemy
	var combat: MeleeCombat = e.combat if e != null else null
	var pose := body.pose
	if pose == &"paralyzed":
		player.speed_scale = 0.0
		return
	if combat != null and combat.is_stunned():
		_play("stun")
		return
	if combat != null and combat.get_phase() != MeleeCombat.Phase.IDLE:
		var phase := combat.get_phase()
		if phase == MeleeCombat.Phase.WINDUP and _last_phase != MeleeCombat.Phase.WINDUP:
			_attack_role = _attack_role_for(combat)
			_replay(_attack_role, 1.3 if not combat.is_heavy_action() else 0.9)
		_last_phase = phase
		return
	_last_phase = MeleeCombat.Phase.IDLE
	if combat != null and combat.is_blocking():
		_play("block")
		return
	if body.bow_draw > 0.0:
		_play("aim")
		return
	if body.cast_charge > 0.0:
		_play("cast")
		return
	if _hit_time > 0.0 and clips.get("hit", "") != "":
		_play("hit", 1.5)
		return
	var fighting: bool = e != null and (e.state == Enemy.State.CHASE or e.state == Enemy.State.ATTACK)
	if speed > 2.6:
		_play("run", clampf(speed / _run_speed, 0.6, 1.8))
		return
	if speed > 0.35:
		_play("walk", clampf(speed / _walk_speed, 0.5, 2.0))
		return
	if not fighting:
		match pose:
			&"sit": _play("sit"); return
			&"sleep": _play("lie"); return
			&"pray": _play("kneel"); return
			&"work", &"farm", &"sweep": _play("work", 0.7); return
			&"chop": _play("chop", 0.6); return
			&"talk": _play("talk"); return
			&"drink": _play("drink"); return
	if fighting:
		var main: ItemData = e.equipment.get_main_hand() if e != null and e.equipment != null else null
		_play("idle_combat_2h" if main != null and main.two_handed else "idle_combat")
		return
	_play("idle")


func _attack_role_for(combat: MeleeCombat) -> String:
	if combat.get_action_kind() == MeleeCombat.Kind.BASH:
		return "bash"
	var w := combat.get_action_weapon()
	if w == null:
		return "attack_unarmed"
	if w.two_handed:
		return "attack2h"
	return "attack_alt" if combat.get_swing_dir() < 0.0 else "attack"


## The death clip, then held on its last frame. at_end = a corpse loaded from a save.
func die(at_end: bool = false) -> void:
	_dead = true
	if player == null:
		return
	var clip: String = clips.get("death", "")
	if clip == "":
		player.stop()
		return
	player.active = true
	player.speed_scale = 1.0
	player.play(clip, 0.1)
	if at_end:
		player.seek(player.get_animation(clip).length, true)


## Drawn or not (the box body's own visibility no longer shows anything)
func set_shown(on: bool) -> void:
	model.visible = on


## Bones that take part in a ragdoll (matched in their names, any rig: Morrowind's Bip01, KayKit, Quaternius)
const RAG_BONES := ["pelvis", "hips", "spine", "chest", "neck", "head", "upperarm", "upper_arm", "arm.l", "arm.r",
	"forearm", "lowerarm", "lower_arm", "thigh", "upperleg", "upper_leg", "calf", "lowerleg", "lower_leg", "shin", "leg"]
const RAG_SKIP := ["finger", "toe", "nub", "weapon", "shield", "eye", "jaw", "twist", "tail", "clav", "foot", "hand", "prop", "root"]



## The skeleton bones a ragdoll is made of: the main joints, any rig (Morrowind's Bip01, KayKit, Quaternius)
func ragdoll_bones() -> Array[int]:
	var out: Array[int] = []
	var skel := _skeleton()
	if skel == null:
		return out
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		if RAG_BONES.any(func(w): return n.contains(w)) and not RAG_SKIP.any(func(w): return n.contains(w)):
			out.append(i)
	return out


## Stops the clips for good: from here a ragdoll moves the bones
func hand_to_ragdoll() -> Skeleton3D:
	_dead = true
	if player != null:
		player.stop()
		player.active = false
	return _skeleton()


# Whether the off hand carries a shield (rather than a second weapon or a torch)
func _holds_shield() -> bool:
	var e := body.get_parent() as Enemy
	if e == null:
		return true
	var off: ItemData = e.starting_off_hand
	return off == null or off.secondary_action == ItemData.SecondaryAction.BLOCK




## True when shields go on Morrowind's own shield bone (where its shield models sit as they are made)
func has_shield_bone() -> bool:
	var skel := _skeleton()
	return skel != null and skel.find_bone("Shield Bone") >= 0


## The quarter turn about the forearm that faces a shield out from the arm
const SHIELD_TURN := -PI * 0.5


# Along the forearm (toward the hand), in `bone`'s own space
func _forearm_axis(skel: Skeleton3D, bone: int) -> Vector3:
	var hand := skel.find_bone("Bip01 L Hand")
	var fore := skel.find_bone("Bip01 L Forearm")
	if hand < 0 or fore < 0:
		return Vector3.UP
	var at := skel.get_bone_global_rest(bone)
	var d := at.basis.inverse() * (skel.get_bone_global_rest(hand).origin - skel.get_bone_global_rest(fore).origin)
	return d.normalized() if d.length() > 0.0001 else Vector3.UP


# The turned shield rests against the forearm: its middle a little past halfway down the forearm and just
# out from it, the bowl round the arm (waits a few frames for the shield to be hung)
func _seat_shield(holder: Node3D, skel: Skeleton3D, bone: int, tries: int) -> void:
	if not is_instance_valid(holder) or not is_instance_valid(skel):
		return
	var meshes := holder.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		if tries > 0:
			get_tree().create_timer(0.25).timeout.connect(_seat_shield.bind(holder, skel, bone, tries - 1))
		return
	var att := holder.get_parent() as Node3D
	var b := AABB()
	for i in meshes.size():
		var m := meshes[i] as MeshInstance3D
		var mb := ModelLibrary.relative_transform(att, m) * m.get_aabb()
		b = mb if i == 0 else b.merge(mb)
	var hand := skel.find_bone("Bip01 L Hand")
	var fore := skel.find_bone("Bip01 L Forearm")
	if hand < 0 or fore < 0:
		return
	var inv := skel.get_bone_global_rest(bone).affine_inverse()  # into the shield bone's space
	var f := inv * skel.get_bone_global_rest(fore).origin
	var h := inv * skel.get_bone_global_rest(hand).origin
	var axis := (h - f).normalized()
	var c := b.get_center()
	var out := (c - f) - axis * (c - f).dot(axis)
	if out.length() < 0.001:
		return
	var scale_f := skel.global_transform.basis.get_scale().x  # metres -> the bone's own units
	var want := f.lerp(h, 0.55) + out.normalized() * (SHIELD_OFF_ARM / maxf(scale_f, 0.0001))
	holder.position += want - c


## How far the middle of a shield sits out from the forearm (metres)
const SHIELD_OFF_ARM := 0.0
