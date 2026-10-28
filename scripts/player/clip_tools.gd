class_name ClipTools
extends RefCounted
## Tools for first-person clips made from Morrowind's (FirstPersonArms):
##   mirror()   the same move done with the other arm (Morrowind only swings right-handed): each bone turns
##              as its opposite number did, reflected across the body, and keeps its own length;
##              a fixed correction per bone keeps its own rest pose exact, so mirrored rigs come out right
##   compose()  one clip from two: one arm from the first, the other arm (and nothing else) from the second,
##              so the right hand can swing while the left keeps its own idle, cast, or block

## The axis that runs from one side of the body to the other, in the skeleton's space (0 = x, 1 = y, 2 = z)
static func side_axis(skel: Skeleton3D) -> int:
	var l := skel.find_bone("Bip01 L Hand")
	var r := skel.find_bone("Bip01 R Hand")
	if l < 0 or r < 0:
		return 0
	var d := skel.get_bone_global_rest(l).origin - skel.get_bone_global_rest(r).origin
	var a := Vector3(absf(d.x), absf(d.y), absf(d.z))
	return 0 if a.x >= a.y and a.x >= a.z else (1 if a.y >= a.z else 2)


## The bone on the other side ("Bip01 L Forearm" <-> "Bip01 R Forearm"), or the same bone in the middle
static func opposite(skel: Skeleton3D, bone: int) -> int:
	var n := skel.get_bone_name(bone)
	var swapped := n
	for pair in [[" L ", " R "], [" L", " R"], ["Left ", "Right "], ["Shield Bone", "Weapon Bone"]]:
		if n.contains(pair[0]):
			swapped = n.replace(pair[0], pair[1])
			break
		if n.contains(pair[1]):
			swapped = n.replace(pair[1], pair[0])
			break
	var o := skel.find_bone(swapped)
	return o if o >= 0 else bone


## Which side a bone is on: -1 left, 1 right, 0 the middle
static func side_of(skel: Skeleton3D, bone: int) -> int:
	var n := skel.get_bone_name(bone)
	if n.contains(" L ") or n.ends_with(" L") or n.begins_with("Left ") or n == "Shield Bone":
		return -1
	if n.contains(" R ") or n.ends_with(" R") or n.begins_with("Right ") or n == "Weapon Bone":
		return 1
	return 0


## The clip with every move made by the other side of the body
static func mirror(anim: Animation, skel: Skeleton3D, fps: float = 30.0) -> Animation:
	var axis := side_axis(skel)
	var s := Basis.from_scale(Vector3(-1 if axis == 0 else 1, -1 if axis == 1 else 1, -1 if axis == 2 else 1))
	var c := center(skel, axis)
	var n := skel.get_bone_count()
	var rest_g: Array[Transform3D] = []
	for b in n:
		rest_g.append(skel.get_bone_global_rest(b))
	# the correction that keeps each bone's own rest pose: rest = M(rest of its opposite) * C
	var corr: Array[Transform3D] = []
	var opp: Array[int] = []
	for b in n:
		var o := opposite(skel, b)
		opp.append(o)
		corr.append(_m(rest_g[o], s, c).affine_inverse() * rest_g[b])
	var tracks := _tracks_by_bone(anim, skel)
	var out := Animation.new()
	out.length = anim.length
	var moving := {}  # every bone: one the clip leaves alone may still sit differently once mirrored
	for b in n:
		moving[b] = true
	var rot_t := {}
	var pos_t := {}
	for b in moving:
		var path := NodePath("Skeleton3D:" + skel.get_bone_name(b))
		rot_t[b] = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rot_t[b], path)
		# Only the middle moves: an arm's or hand's bones keep their own lengths, since the two sides
		# are not quite each other's mirror (copying the other side's would stretch the skin)
		if side_of(skel, b) == 0:
			pos_t[b] = out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(pos_t[b], path)
	var steps := maxi(int(ceil(anim.length * fps)), 1)
	for i in steps + 1:
		var t := minf(float(i) / fps, anim.length)
		var g := _pose_at(anim, skel, tracks, t)
		var mg: Array[Transform3D] = []
		mg.resize(n)
		for b in n:
			# where it is: exactly the reflection of its opposite; which way it turns: corrected for the bone's own axes
			var r := _m(g[opp[b]], s, c)
			mg[b] = Transform3D(r.basis * corr[b].basis, r.origin)
		for b in moving:
			var p := skel.get_bone_parent(b)
			var local: Transform3D = (mg[p].affine_inverse() * mg[b]) if p >= 0 else mg[b]
			out.rotation_track_insert_key(rot_t[b], t, local.basis.get_rotation_quaternion())
			if pos_t.has(b):
				out.position_track_insert_key(pos_t[b], t, local.origin)
	return out


## One arm from `arm_clip` (side: 1 right, -1 left), everything else from `rest_clip`
static func compose(rest_clip: Animation, arm_clip: Animation, skel: Skeleton3D, side: int) -> Animation:
	var out := Animation.new()
	out.length = maxf(rest_clip.length, arm_clip.length)
	for src: Animation in [rest_clip, arm_clip]:
		for i in src.get_track_count():
			var path: NodePath = src.track_get_path(i)
			var b := skel.find_bone(String(path.get_subname(0)))
			var on_arm := b >= 0 and side_of(skel, b) == side
			if (src == arm_clip) != on_arm:
				continue
			var ti := out.add_track(src.track_get_type(i))
			out.track_set_path(ti, path)
			for k in src.track_get_key_count(i):
				out.track_insert_key(ti, src.track_get_key_time(i, k), src.track_get_key_value(i, k))
	return out


# The reflection of a transform across the body's middle, the plane through `c` (a proper rotation again)
static func _m(x: Transform3D, s: Basis, c: Vector3) -> Transform3D:
	return Transform3D(s * x.basis * s, s * (x.origin - c) + c)


## A point on the body's middle (the spine), in the skeleton's space
static func center(skel: Skeleton3D, axis: int) -> Vector3:
	for n in ["Bip01 Spine1", "Bip01 Spine", "Bip01 Neck", "Bip01"]:
		var b := skel.find_bone(n)
		if b >= 0:
			var p := skel.get_bone_global_rest(b).origin
			var out := Vector3.ZERO
			out[axis] = p[axis]
			return out
	return Vector3.ZERO


static func _tracks_by_bone(anim: Animation, skel: Skeleton3D) -> Dictionary:
	var out := {}  # bone -> {"rot": track, "pos": track, "scale": track}
	for i in anim.get_track_count():
		var b := skel.find_bone(String(anim.track_get_path(i).get_subname(0)))
		if b < 0:
			continue
		if not out.has(b):
			out[b] = {}
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				out[b]["rot"] = i
			Animation.TYPE_POSITION_3D:
				out[b]["pos"] = i
			Animation.TYPE_SCALE_3D:
				out[b]["scale"] = i
	return out


# Every bone's pose in the skeleton's space at time t (rest where the clip says nothing)
static func _pose_at(anim: Animation, skel: Skeleton3D, tracks: Dictionary, t: float) -> Array[Transform3D]:
	var n := skel.get_bone_count()
	var local: Array[Transform3D] = []
	for b in n:
		var r := skel.get_bone_rest(b)
		var q := r.basis.get_rotation_quaternion()
		var p := r.origin
		var sc := r.basis.get_scale()
		if tracks.has(b):
			var tr: Dictionary = tracks[b]
			if tr.has("rot"):
				q = anim.rotation_track_interpolate(tr["rot"], t)
			if tr.has("pos"):
				p = anim.position_track_interpolate(tr["pos"], t)
			if tr.has("scale"):
				sc = anim.scale_track_interpolate(tr["scale"], t)
		local.append(Transform3D(Basis(q).scaled(sc), p))
	var g: Array[Transform3D] = []
	g.resize(n)
	var done: Array[bool] = []
	done.resize(n)
	for b in n:
		_global(b, skel, local, g, done)
	return g


static func _global(b: int, skel: Skeleton3D, local: Array[Transform3D], g: Array[Transform3D], done: Array[bool]) -> Transform3D:
	if done[b]:
		return g[b]
	var p := skel.get_bone_parent(b)
	g[b] = (_global(p, skel, local, g, done) * local[b]) if p >= 0 else local[b]
	done[b] = true
	return g[b]
