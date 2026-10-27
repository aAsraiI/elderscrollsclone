extends SceneTree
## Prints each ModelLibrary key's size after its entry's turn, posed with a clip (default walk),
## and where its head bone ends up. A long four-legged model should be longest along Z with its
## head toward -Z (the game's forward).
##   godot --headless --path . -s res://tools/measure_keys.gd -- creature/ [role]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else ""
	var role := args[1] if args.size() > 1 else "walk"
	var keys := ModelLibrary.keys()
	keys.sort()
	for key in keys:
		if not String(key).begins_with(prefix):
			continue
		var holder := ModelLibrary.instance(key)
		if holder == null:
			print("%s\tFAILED" % key)
			continue
		root.add_child(holder)
		var clip := ""
		for ap in holder.find_children("*", "AnimationPlayer", true, false):
			var p := ap as AnimationPlayer
			for want in ModelBody.ROLE_CLIPS.get(role, []):
				clip = ModelBody._match(p.get_animation_list(), String(want))
				if clip != "":
					break
			if clip != "":
				p.play(clip)
				p.seek(0.2, true)
		var box := ModelLibrary.bounds(holder)
		var line := "%s\t%s\tsize=(%.2f, %.2f, %.2f)" % [key, clip, box.size.x, box.size.y, box.size.z]
		for sk in holder.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			for i in s.get_bone_count():
				var bn := s.get_bone_name(i).to_lower()
				if bn == "head" or bn == "bone.003" and line.find("head") < 0:
					var hp := ModelLibrary.relative_transform(holder, s) * s.get_bone_global_pose(i).origin
					var d := hp - box.get_center()
					line += "\thead(%s)=(%.2f, %.2f, %.2f)" % [bn, d.x / maxf(box.size.x, 0.01), d.y / maxf(box.size.y, 0.01), d.z / maxf(box.size.z, 0.01)]
		# Toes point forward
		for sk in holder.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			var foot := s.find_bone("foot.l")
			var toe := s.find_bone("toes.l")
			if foot < 0:
				foot = s.find_bone("Foot.L")
				toe = s.find_bone("Foot.L_end")
			if foot >= 0 and toe >= 0:
				var xf := ModelLibrary.relative_transform(holder, s)
				var dir := (xf * s.get_bone_global_pose(toe).origin) - (xf * s.get_bone_global_pose(foot).origin)
				line += "\ttoes=(%.2f, %.2f, %.2f)" % [dir.normalized().x, dir.normalized().y, dir.normalized().z]
		print(line)
		holder.queue_free()
	quit()
